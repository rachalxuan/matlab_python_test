classdef HelperCCSDSTMSplitReceiver < handle
    %HELPERCCSDSTMSPLITRECEIVER Receive coordinator for independent I/Q TM rails.
    %
    %   This class owns only the split-path coordination layer:
    %     * dualIQ: serial I/Q soft-bit deinterleave;
    %     * unequalDualIQ: UQPSK 2:1 I/Q soft-bit demux;
    %     * optional per-rail periodic ASM alignment for the affected RS paths;
    %     * one ordinary HelperCCSDSTMDecoder instance per rail.
    %
    %   It deliberately does not receive TX reference frames and never selects
    %   IQPhase using BER.  An evaluator may call this object once per explicit
    %   IQPhase when diagnosing 8PSK/32QAM/32APSK, while a production receiver must
    %   supply the phase selected by its packing/ASM contract.

    properties
        % DataPathMode is either "dualIQ" or "unequalDualIQ".
        DataPathMode = 'dualIQ'
        % Modulation is the TM modulation carried by the two rails.
        Modulation = 'QPSK'
        % ChannelCoding is forwarded to the two ordinary decoders.
        ChannelCoding = 'none'
        % BitsPerFrame is required only to frame-interleave ordinary dualIQ output.
        BitsPerFrame = 0
        % DecoderArgs is a name-value cell array for one single-rail Decoder.
        DecoderArgs = {}
        % Options is the evaluation/receiver configuration used by ASM alignment.
        Options = struct()
        % HasASM controls whether the optional RS periodic ASM coordinator runs.
        HasASM = true
        % IQPhase is an explicit 0/1 serial-bit start for ordinary dualIQ.
        IQPhase = 0
        % Debug prints receiver-observable split diagnostics only.
        Debug = false
    end

    methods
        function obj = HelperCCSDSTMSplitReceiver(varargin)
            if mod(nargin, 2) ~= 0
                error('HelperCCSDSTMSplitReceiver:NameValuePairs', ...
                    'Constructor arguments must be name-value pairs.');
            end
            for k = 1:2:nargin
                name = lower(char(string(varargin{k})));
                value = varargin{k+1};
                switch name
                    case 'datapathmode'
                        obj.DataPathMode = char(string(value));
                    case 'modulation'
                        obj.Modulation = char(string(value));
                    case 'channelcoding'
                        obj.ChannelCoding = char(string(value));
                    case 'bitsperframe'
                        obj.BitsPerFrame = double(value);
                    case 'decoderargs'
                        obj.DecoderArgs = value;
                    case 'options'
                        obj.Options = value;
                    case 'hasasm'
                        obj.HasASM = logical(value);
                    case 'iqphase'
                        obj.IQPhase = double(value);
                    case 'debug'
                        obj.Debug = logical(value);
                    otherwise
                        error('HelperCCSDSTMSplitReceiver:UnknownProperty', ...
                            'Unknown property "%s".', char(string(varargin{k})));
                end
            end
            obj.localValidateConfiguration();
        end

        function result = decode(obj, demodData)
            %DECODE Split demodulated soft bits and decode the two TM rails.
            obj.localValidateConfiguration();
            demodData = demodData(:);
            result = obj.localEmptyResult();
            result.DataPathMode = char(obj.DataPathMode);
            result.IQPhase = obj.IQPhase;

            if strcmpi(obj.DataPathMode, 'unequalDualIQ')
                [demodI, demodQ, droppedTail] = ...
                    tm_uqpsk_unequal_bit_demux(demodData, 2, 'drop');
            else
                if obj.IQPhase >= numel(demodData)
                    error('HelperCCSDSTMSplitReceiver:IQPhaseOutsideInput', ...
                        'IQPhase=%d is outside the %d-bit demodulated input.', ...
                        obj.IQPhase, numel(demodData));
                end
                packed = demodData(obj.IQPhase+1:end);
                [demodI, demodQ, droppedTail] = ...
                    tm_data_path_bit_deinterleave(packed, 'drop');
            end

            [demodIForDecoder, demodQForDecoder, decArgsI, decArgsQ, alignment] = ...
                obj.localPrepareRSPeriodicASMAlignment(demodI, demodQ);

            [decArgsI, decArgsQ] = ...
                obj.localPrepareSplitConvolutionalFrameSync(decArgsI, decArgsQ);
            [decodedI, decodedQ, railPolarityI, railPolarityQ, polarityEvidence] = ...
                obj.localDecodeRailsWithPolarity( ...
                    demodIForDecoder, demodQForDecoder, decArgsI, decArgsQ);

            result.DemodI = demodI;
            result.DemodQ = demodQ;
            result.DecoderInputI = demodIForDecoder;
            result.DecoderInputQ = demodQForDecoder;
            result.DroppedTailBits = droppedTail;
            result.DecoderArgsI = decArgsI;
            result.DecoderArgsQ = decArgsQ;
            result.DecodedI = int8(decodedI(:));
            result.DecodedQ = int8(decodedQ(:));
            result.RailPolarityI = railPolarityI;
            result.RailPolarityQ = railPolarityQ;
            result.RailPolarityEvidence = polarityEvidence;
            result.RSASMAlignment = alignment;

            if strcmpi(obj.DataPathMode, 'dualIQ')
                result.DecodedBits = tm_data_path_frame_interleave( ...
                    result.DecodedI, result.DecodedQ, obj.BitsPerFrame, 'truncate');
            else
                % Unequal UQPSK has a 2:1 I/Q frame cadence; consumers must
                % use DecodedI and DecodedQ directly rather than a flat stream.
                result.DecodedBits = zeros(0, 1, 'int8');
            end

            if obj.Debug
                fprintf(['[SplitReceiver] path=%s phase=%d demod I/Q=%d/%d ', ...
                    'decoded I/Q=%d/%d polarity I/Q=%+d/%+d ', ...
                    'droppedTail=%d rsAligned=%d\n'], ...
                    char(obj.DataPathMode), obj.IQPhase, ...
                    numel(result.DemodI), numel(result.DemodQ), ...
                    numel(result.DecodedI), numel(result.DecodedQ), ...
                    result.RailPolarityI, result.RailPolarityQ, ...
                    result.DroppedTailBits, alignment.BothFound);
                obj.localPrintRSASMAlignment('receiver', obj.IQPhase, alignment);
            end
        end
    end

    methods (Access = private)
        function localValidateConfiguration(obj)
            if ~any(strcmpi(obj.DataPathMode, {'dualIQ','unequalDualIQ'}))
                error('HelperCCSDSTMSplitReceiver:InvalidDataPathMode', ...
                    'DataPathMode must be dualIQ or unequalDualIQ.');
            end
            if ~iscell(obj.DecoderArgs) || mod(numel(obj.DecoderArgs), 2) ~= 0
                error('HelperCCSDSTMSplitReceiver:InvalidDecoderArgs', ...
                    'DecoderArgs must be an even-length name-value cell array.');
            end
            if ~isstruct(obj.Options) || ~isscalar(obj.Options)
                error('HelperCCSDSTMSplitReceiver:InvalidOptions', ...
                    'Options must be a scalar struct.');
            end
            if ~isscalar(obj.IQPhase) || ~isfinite(obj.IQPhase) || ...
                    ~ismember(round(obj.IQPhase), [0 1])
                error('HelperCCSDSTMSplitReceiver:InvalidIQPhase', ...
                    'IQPhase must be 0 or 1.');
            end
            obj.IQPhase = round(obj.IQPhase);
            if strcmpi(obj.DataPathMode, 'unequalDualIQ') && obj.IQPhase ~= 0
                error('HelperCCSDSTMSplitReceiver:UnequalIQPhase', ...
                    'unequalDualIQ uses the fixed 2:1 mux contract and IQPhase=0.');
            end
            if strcmpi(obj.DataPathMode, 'dualIQ') && ...
                    (~isscalar(obj.BitsPerFrame) || obj.BitsPerFrame <= 0 || ...
                     mod(obj.BitsPerFrame, 1) ~= 0)
                error('HelperCCSDSTMSplitReceiver:InvalidBitsPerFrame', ...
                    'dualIQ requires a positive integer BitsPerFrame.');
            end
        end

        function result = localEmptyResult(~)
            result = struct( ...
                'DataPathMode','', ...
                'IQPhase',0, ...
                'DemodI',zeros(0,1), ...
                'DemodQ',zeros(0,1), ...
                'DecoderInputI',zeros(0,1), ...
                'DecoderInputQ',zeros(0,1), ...
                'DroppedTailBits',0, ...
                'DecoderArgsI',{{}}, ...
                'DecoderArgsQ',{{}}, ...
                'DecodedI',zeros(0,1,'int8'), ...
                'DecodedQ',zeros(0,1,'int8'), ...
                'RailPolarityI',1, ...
                'RailPolarityQ',1, ...
                'RailPolarityEvidence',struct(), ...
                'DecodedBits',zeros(0,1,'int8'), ...
                'RSASMAlignment',HelperCCSDSTMSplitReceiver.localEmptyRSASMAlignment());
        end

        function enabled = localUseSplitConvolutionalPolaritySearch(obj)
            coding = lower(string(obj.ChannelCoding));
            enabled = strcmpi(obj.DataPathMode, 'dualIQ') && logical(obj.HasASM) && ...
                any(coding == ["convolutional", "concatenated"]);
            raw = HelperCCSDSTMSplitReceiver.localOption(obj.Options, ...
                {'enableSplitConvolutionalRailPolaritySearch', ...
                 'EnableSplitConvolutionalRailPolaritySearch'}, []);
            if ~isempty(raw)
                enabled = enabled && logical(raw);
            end
        end

        function [decArgsI, decArgsQ] = ...
                localPrepareSplitConvolutionalFrameSync(obj, decArgsI, decArgsQ)
            % The rate-1/2 encoded ASM has only 52 state-independent coded
            % bits after the decoder drops the trellis-dependent prefix.
            % In a split QAM path the residual demapper errors are commonly
            % concentrated at that boundary.  Seven allowed errors preserve a
            % wide margin from wrong-polarity peaks while avoiding rejection
            % of an otherwise clean rail.  An explicit caller override always
            % wins, and no single-stream/non-convolutional decoder is touched.
            if ~obj.localUseSplitConvolutionalPolaritySearch()
                return;
            end
            if ~HelperCCSDSTMSplitReceiver.localHasNameValue( ...
                    decArgsI, 'FrameSyncASMErrorThreshold')
                threshold = HelperCCSDSTMSplitReceiver.localNumericOption( ...
                    obj.Options, ...
                    {'SplitConvolutionalFrameSyncASMErrorThreshold'}, 7);
                decArgsI = HelperCCSDSTMSplitReceiver.localSetNameValue( ...
                    decArgsI, 'FrameSyncASMErrorThreshold', threshold);
                decArgsQ = HelperCCSDSTMSplitReceiver.localSetNameValue( ...
                    decArgsQ, 'FrameSyncASMErrorThreshold', threshold);
            end
        end

        function [decodedI, decodedQ, polarityI, polarityQ, bestEvidence] = ...
                localDecodeRailsWithPolarity(obj, demodI, demodQ, decArgsI, decArgsQ)
            polarityList = 1;
            if obj.localUseSplitConvolutionalPolaritySearch()
                polarityList = [1 -1];
            end

            decodedICandidates = cell(size(polarityList));
            decodedQCandidates = cell(size(polarityList));
            for k = 1:numel(polarityList)
                decoderI = HelperCCSDSTMDecoder(decArgsI{:});
                decoderQ = HelperCCSDSTMDecoder(decArgsQ{:});
                decodedICandidates{k} = int8(decoderI( ...
                    polarityList(k) .* demodI));
                decodedQCandidates{k} = int8(decoderQ( ...
                    polarityList(k) .* demodQ));
            end

            bestI = 1;
            bestQ = 1;
            bestEvidence = struct('Available',false,'SelectionScore',-inf, ...
                'BothRailsStructured',false);
            bestNegativeCount = inf;
            for i = 1:numel(polarityList)
                for q = 1:numel(polarityList)
                    evidence = HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
                        decodedICandidates{i}, decodedQCandidates{q}, ...
                        obj.BitsPerFrame, obj.Options, obj.DataPathMode);
                    negativeCount = double(polarityList(i) < 0) + ...
                        double(polarityList(q) < 0);
                    isBetter = evidence.BothRailsStructured && ...
                        ~bestEvidence.BothRailsStructured;
                    if evidence.BothRailsStructured == bestEvidence.BothRailsStructured
                        if evidence.SelectionScore > bestEvidence.SelectionScore
                            isBetter = true;
                        elseif evidence.SelectionScore == bestEvidence.SelectionScore && ...
                                negativeCount < bestNegativeCount
                            isBetter = true;
                        end
                    end
                    if isBetter
                        bestI = i;
                        bestQ = q;
                        bestEvidence = evidence;
                        bestNegativeCount = negativeCount;
                    end
                end
            end

            decodedI = decodedICandidates{bestI};
            decodedQ = decodedQCandidates{bestQ};
            polarityI = polarityList(bestI);
            polarityQ = polarityList(bestQ);
            if obj.Debug || HelperCCSDSTMSplitReceiver.localLogicalOption( ...
                    obj.Options, {'splitPathDebug'}, false)
                fprintf(['[SplitReceiver rail polarity] coding=%s ', ...
                    'I/Q=%+d/%+d structured=%d score=%.0f ', ...
                    'decodedFrames=%d/%d\n'], ...
                    char(string(obj.ChannelCoding)), polarityI, polarityQ, ...
                    bestEvidence.BothRailsStructured, ...
                    bestEvidence.SelectionScore, ...
                    floor(numel(decodedI)/obj.BitsPerFrame), ...
                    floor(numel(decodedQ)/obj.BitsPerFrame));
            end
        end

        function [demodIOut, demodQOut, decArgsI, decArgsQ, alignment] = ...
                localPrepareRSPeriodicASMAlignment(obj, demodI, demodQ)
            demodIOut = demodI;
            demodQOut = demodQ;
            decArgsI = HelperCCSDSTMSplitReceiver.localSetNameValue( ...
                obj.DecoderArgs, 'DataPathMode', 'single');
            decArgsQ = decArgsI;
            alignment = HelperCCSDSTMSplitReceiver.localEmptyRSASMAlignment();
            alignment.Enabled = obj.localUseRSPeriodicASMAlignment();
            if ~alignment.Enabled
                return;
            end

            [alignedI, foundI, infoI] = obj.localTrimDemodToPeriodicASM(demodI);
            [alignedQ, foundQ, infoQ] = obj.localTrimDemodToPeriodicASM(demodQ);
            alignment.I = HelperCCSDSTMSplitReceiver.localRailAlignment(infoI, foundI);
            alignment.Q = HelperCCSDSTMSplitReceiver.localRailAlignment(infoQ, foundQ);
            alignment.BothFound = foundI && foundQ;
            if alignment.BothFound
                alignment.Score = infoI.Score + infoQ.Score;
                alignment.MaxMeanError = max(infoI.MeanError, infoQ.MeanError);
                demodIOut = alignedI;
                demodQOut = alignedQ;
                decArgsI = HelperCCSDSTMSplitReceiver.localSetNameValue( ...
                    decArgsI, 'DisableFrameSynchronization', true);
                decArgsQ = HelperCCSDSTMSplitReceiver.localSetNameValue( ...
                    decArgsQ, 'DisableFrameSynchronization', true);
                alignment.DecoderSyncDisabled = true;
            end
        end

        function enabled = localUseRSPeriodicASMAlignment(obj)
            isOrdinaryDualRS = strcmpi(obj.DataPathMode, 'dualIQ') && ...
                any(strcmpi(obj.Modulation, ...
                    {'8PSK','16QAM','32QAM','16APSK','32APSK'}));
            isUnequalUQPSKRS = strcmpi(obj.DataPathMode, 'unequalDualIQ') && ...
                strcmpi(obj.Modulation, 'UQPSK');
            enabled = logical(obj.HasASM) && strcmpi(obj.ChannelCoding, 'RS') && ...
                (isOrdinaryDualRS || isUnequalUQPSKRS);
            raw = HelperCCSDSTMSplitReceiver.localOption(obj.Options, ...
                {'enableSplitRSPeriodicASMAlign','EnableSplitRSPeriodicASMAlign'}, []);
            if ~isempty(raw)
                enabled = enabled && logical(raw);
            end
        end

        function [demodAligned, alignedFound, info] = localTrimDemodToPeriodicASM(obj, demodData)
            demodAligned = demodData;
            alignedFound = false;
            info = struct( ...
                'BestError',NaN, 'BestPosition',NaN, 'MeanError',NaN, ...
                'PeriodicFrames',0, 'Score',-inf, 'PeriodBits',NaN, 'TrimBits',0);
            if isempty(demodData)
                return;
            end
            asmBits = obj.localRSASM();
            periodBits = obj.localRSASMPeriodBits(numel(asmBits));
            info.PeriodBits = periodBits;
            if ~isfinite(periodBits) || periodBits <= 0
                return;
            end
            hardBits = int8(real(demodData(:)) > 0);
            [bestErr, bestPos, meanErr, nFrames, score] = ...
                HelperCCSDSTMSplitReceiver.localBestASMPeriodicScore( ...
                    hardBits, asmBits, periodBits, obj.Options);
            info.BestError = bestErr;
            info.BestPosition = bestPos;
            info.MeanError = meanErr;
            info.PeriodicFrames = nFrames;
            info.Score = score;
            if bestPos <= 0 || nFrames < 2
                return;
            end
            maxErr = max(2, ceil(0.20 * double(numel(asmBits))));
            if bestErr > maxErr || meanErr > maxErr
                return;
            end
            trimBits = mod(double(bestPos)-1, double(periodBits));
            if trimBits > 0 && trimBits < numel(demodData)
                demodAligned = demodData(trimBits+1:end);
            else
                trimBits = 0;
            end
            info.TrimBits = trimBits;
            alignedFound = true;
        end

        function asmBits = localRSASM(obj)
            [asmLength, hasLength] = HelperCCSDSTMSplitReceiver.localASMOptionLength(obj.Options);
            [asmHex, hasHex] = HelperCCSDSTMSplitReceiver.localASMOptionHex(obj.Options);
            if hasLength || hasHex
                asmBits = HelperCCSDSTMSplitReceiver.localBuildCustomASM( ...
                    asmLength, hasLength, asmHex, hasHex);
            else
                asmBits = HelperCCSDSTMSplitReceiver.localDefaultTMASM();
            end
        end

        function periodBits = localRSASMPeriodBits(obj, asmLength)
            rsN = 255;
            rsK = HelperCCSDSTMSplitReceiver.localNumericOption( ...
                obj.Options, {'RSMessageLength'}, 223);
            rsI = HelperCCSDSTMSplitReceiver.localNumericOption( ...
                obj.Options, {'RSInterleavingDepth'}, 1);
            rsS = HelperCCSDSTMSplitReceiver.localNumericOption( ...
                obj.Options, {'RSShortenedMessageLength'}, rsK);
            shortened = HelperCCSDSTMSplitReceiver.localLogicalOption( ...
                obj.Options, {'IsRSMessageShortened'}, false);
            if ~shortened
                rsS = rsK;
            end
            periodBits = 8 * rsI * (rsN-rsK+rsS) + asmLength;
        end

        function localPrintRSASMAlignment(~, label, iqPhase, alignment)
            if ~isstruct(alignment) || ~isfield(alignment, 'Enabled') || ...
                    ~alignment.Enabled
                return;
            end
            state = 'fallback';
            if alignment.BothFound
                state = 'aligned';
            end
            fprintf(['[SplitReceiver RS ASM %s] iqPhase=%d state=%s asmScore=%.3f ', ...
                'tmScore=%.3f validTM=%g counterRun=%g | ', ...
                'I: found=%d trim=%d err=%g mean=%.2f frames=%g | ', ...
                'Q: found=%d trim=%d err=%g mean=%.2f frames=%g\n'], ...
                char(string(label)), iqPhase, state, alignment.Score, ...
                alignment.TMStructureScore, alignment.TMValidFrames, ...
                alignment.TMMaxCounterRun, ...
                alignment.I.Found, alignment.I.TrimBits, alignment.I.BestError, ...
                alignment.I.MeanError, alignment.I.PeriodicFrames, ...
                alignment.Q.Found, alignment.Q.TrimBits, alignment.Q.BestError, ...
                alignment.Q.MeanError, alignment.Q.PeriodicFrames);
        end
    end

    methods (Static)
        function evidence = scoreDecodedTMStructure(decodedI, decodedQ, bitsPerFrame, options, dataPathMode)
            %SCOREDECODEDTMSTRUCTURE Score two rails without TX reference bits.
            %
            % The score deliberately uses only decoded TM primary-header
            % fields and counter continuity.  It is therefore valid in a
            % deployed receiver, unlike BER which is available only in the
            % evaluator.  For ordinary dualIQ, the configured mux contract
            % also says that the I rail carries even VCFC and Q carries odd
            % VCFC; unequalDualIQ intentionally has no such assumption.
            if nargin < 5 || isempty(dataPathMode)
                dataPathMode = 'dualIQ';
            end
            scoreI = HelperCCSDSTMSplitReceiver.localScoreDecodedTMStructure( ...
                decodedI, bitsPerFrame, options);
            scoreQ = HelperCCSDSTMSplitReceiver.localScoreDecodedTMStructure( ...
                decodedQ, bitsPerFrame, options);

            minValid = max(1, round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                options, {'splitTMStructureMinValidFrames'}, 2)));
            isOrdinaryDual = strcmpi(string(dataPathMode), 'dualIQ');
            orientation = 0;
            swappedOrientation = 0;
            firstI = NaN;
            firstQ = NaN;
            if isOrdinaryDual && ~isempty(scoreI.VCFC) && ~isempty(scoreQ.VCFC)
                firstI = scoreI.VCFC(1);
                firstQ = scoreQ.VCFC(1);
                orientation = nnz(mod(scoreI.VCFC,2) == 0) + ...
                    nnz(mod(scoreQ.VCFC,2) == 1);
                swappedOrientation = nnz(mod(scoreI.VCFC,2) == 1) + ...
                    nnz(mod(scoreQ.VCFC,2) == 0);
            end

            minValidBoth = min(scoreI.ValidFrames, scoreQ.ValidFrames);
            minRunBoth = min(scoreI.MaxCounterRun, scoreQ.MaxCounterRun);
            fieldMatches = scoreI.FieldMatches + scoreQ.FieldMatches;
            % Keep each component separate for debug, but make a valid
            % structure on *both* rails dominate the final scalar score.
            selectionScore = 1e6 * minValidBoth + ...
                1e4 * (scoreI.ValidFrames + scoreQ.ValidFrames) + ...
                1e3 * minRunBoth + 100 * (scoreI.MaxCounterRun + scoreQ.MaxCounterRun) + ...
                fieldMatches + 10 * orientation;
            evidence = struct( ...
                'Available',true, ...
                'DataPathMode',char(string(dataPathMode)), ...
                'I',scoreI, ...
                'Q',scoreQ, ...
                'BothRailsStructured',scoreI.ValidFrames >= minValid && ...
                    scoreQ.ValidFrames >= minValid, ...
                'MinValidFramesRequired',minValid, ...
                'TMStructureScore',scoreI.Score + scoreQ.Score, ...
                'TMValidFrames',scoreI.ValidFrames + scoreQ.ValidFrames, ...
                'TMMinValidFrames',minValidBoth, ...
                'TMMaxCounterRun',scoreI.MaxCounterRun + scoreQ.MaxCounterRun, ...
                'TMMinCounterRun',minRunBoth, ...
                'TMFieldMatches',fieldMatches, ...
                'TMOrientationScore',orientation, ...
                'TMSwappedOrientationScore',swappedOrientation, ...
                'TMFirstIFrameID',firstI, ...
                'TMFirstQFrameID',firstQ, ...
                'SelectionScore',selectionScore);
        end

        function better = isBetterTMStructureCandidate( ...
                candEvidence, candPhase, bestEvidence, bestPhase, preferredPhase)
            %ISBETTERTMSTRUCTURECANDIDATE Compare receiver-only evidence.
            if nargin < 5 || isempty(preferredPhase)
                preferredPhase = 1;
            end
            better = false;
            candAvailable = isstruct(candEvidence) && isfield(candEvidence, 'Available') && ...
                candEvidence.Available;
            bestAvailable = isstruct(bestEvidence) && isfield(bestEvidence, 'Available') && ...
                bestEvidence.Available;
            if candAvailable ~= bestAvailable
                better = candAvailable;
                return;
            elseif ~candAvailable
                better = candPhase == preferredPhase && bestPhase ~= preferredPhase;
                return;
            end

            tol = 1e-12;
            if candEvidence.BothRailsStructured ~= bestEvidence.BothRailsStructured
                better = candEvidence.BothRailsStructured;
                return;
            end
            fields = {'TMOrientationScore','TMMinValidFrames','TMValidFrames', ...
                'TMMinCounterRun','TMMaxCounterRun','TMFieldMatches','SelectionScore'};
            for k = 1:numel(fields)
                field = fields{k};
                a = candEvidence.(field);
                b = bestEvidence.(field);
                if isfinite(a) && isfinite(b) && abs(a-b) > tol
                    better = a > b;
                    return;
                end
            end
            better = candPhase == preferredPhase && bestPhase ~= preferredPhase;
        end

        function alignment = scoreTMStructure(alignment, decodedI, decodedQ, bitsPerFrame, options)
            %SCORETMSTRUCTURE Score a candidate using receiver-observable TM fields.
            if ~isstruct(alignment) || ~isfield(alignment,'Enabled') || ...
                    ~alignment.Enabled || ~alignment.BothFound
                return;
            end
            dataPathMode = HelperCCSDSTMSplitReceiver.localOption( ...
                options, {'DataPathMode','dataPathMode'}, 'dualIQ');
            evidence = HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
                decodedI, decodedQ, bitsPerFrame, options, dataPathMode);
            alignment.TMStructureScore = evidence.TMStructureScore;
            alignment.TMValidFrames = evidence.TMValidFrames;
            alignment.TMMaxCounterRun = evidence.TMMaxCounterRun;
            alignment.TMFirstIFrameID = evidence.TMFirstIFrameID;
            alignment.TMFirstQFrameID = evidence.TMFirstQFrameID;
            alignment.TMOrientationScore = evidence.TMOrientationScore;
            alignment.TMSwappedOrientationScore = evidence.TMSwappedOrientationScore;
        end

        function better = isBetterRSASMCandidate(candAlignment, candPhase, bestAlignment, bestPhase)
            %ISBETTERRSASMCANDIDATE Compare only receiver-observable evidence.
            better = false;
            candEnabled = isstruct(candAlignment) && isfield(candAlignment,'Enabled') && ...
                candAlignment.Enabled;
            bestEnabled = isstruct(bestAlignment) && isfield(bestAlignment,'Enabled') && ...
                bestAlignment.Enabled;
            if ~candEnabled && ~bestEnabled
                return;
            end
            candFound = candEnabled && candAlignment.BothFound;
            bestFound = bestEnabled && bestAlignment.BothFound;
            if candFound ~= bestFound
                better = candFound;
                return;
            end
            if ~candFound
                better = candPhase < bestPhase;
                return;
            end
            tol = 1e-12;
            fields = {'TMOrientationScore','TMStructureScore','TMValidFrames','Score'};
            for k = 1:numel(fields)
                field = fields{k};
                a = candAlignment.(field);
                b = bestAlignment.(field);
                if isfinite(a) && isfinite(b) && abs(a-b) > tol
                    better = a > b;
                    return;
                end
            end
            a = candAlignment.MaxMeanError;
            b = bestAlignment.MaxMeanError;
            if isfinite(a) && isfinite(b) && abs(a-b) > tol
                better = a < b;
                return;
            end
            better = candPhase < bestPhase;
        end
    end

    methods (Static, Access = private)
        function result = localScoreDecodedTMStructure(decodedBits, bitsPerFrame, opt)
            result = struct('Score',-inf,'ValidFrames',0,'MaxCounterRun',0, ...
                'FieldMatches',0,'FramesChecked',0,'VCFC',zeros(0,1));
            numFrames = floor(numel(decodedBits) / bitsPerFrame);
            if bitsPerFrame < 37 || numFrames < 1
                return;
            end
            maxFrames = min(numFrames, max(1, round( ...
                HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'splitRSTMHeaderScoreFrames'}, 32))));
            expectedVersion = round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'TransferFrameVersionNumber'}, 0));
            expectedSCID = round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'SpacecraftID'}, 1));
            expectedVCID = round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'VirtualChannelID'}, 0));
            expectedOCF = double(HelperCCSDSTMSplitReceiver.localLogicalOption(opt, {'HasOCF'}, false));
            expectedSHF = double(HelperCCSDSTMSplitReceiver.localLogicalOption(opt, {'HasSecondaryHeader'}, false));
            expectedSync = round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'SynchronizationFlag'}, 0));
            expectedPacketOrder = round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'PacketOrderFlag'}, 0));
            expectedSLID = HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'SegmentLengthID'}, NaN);
            if ~isfinite(expectedSLID)
                expectedSLID = 3 * double(expectedSync == 0);
            end
            expectedSLID = round(expectedSLID);

            vcfc = zeros(maxFrames,1);
            mcfc = zeros(maxFrames,1);
            fieldMatches = 0;
            validFrames = 0;
            decodedBits = int8(decodedBits(:) ~= 0);
            for iFrame = 1:maxFrames
                idx = (iFrame-1)*bitsPerFrame + (1:37);
                header = decodedBits(idx);
                version = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(1:2));
                scid = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(3:12));
                vcid = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(13:15));
                ocf = double(header(16));
                mcfc(iFrame) = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(17:24));
                vcfc(iFrame) = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(25:32));
                shf = double(header(33));
                syncFlag = double(header(34));
                packetOrder = double(header(35));
                slid = HelperCCSDSTMSplitReceiver.localBitsToUnsignedMSB(header(36:37));
                matches = [version == expectedVersion, scid == expectedSCID, ...
                    vcid == expectedVCID, ocf == expectedOCF, shf == expectedSHF, ...
                    syncFlag == expectedSync, packetOrder == expectedPacketOrder, ...
                    slid == expectedSLID];
                fieldMatches = fieldMatches + nnz(matches);
                validFrames = validFrames + all(matches);
            end
            maxCounterRun = max([ ...
                HelperCCSDSTMSplitReceiver.localModuloCounterRun(vcfc, 1), ...
                HelperCCSDSTMSplitReceiver.localModuloCounterRun(vcfc, 2), ...
                HelperCCSDSTMSplitReceiver.localModuloCounterRun(mcfc, 1), ...
                HelperCCSDSTMSplitReceiver.localModuloCounterRun(mcfc, 2)]);
            result.ValidFrames = validFrames;
            result.MaxCounterRun = maxCounterRun;
            result.FieldMatches = fieldMatches;
            result.FramesChecked = maxFrames;
            result.VCFC = vcfc;
            result.Score = 1000*validFrames + 10*maxCounterRun + fieldMatches/maxFrames;
        end

        function [bestErr, bestPos, meanErr, nFrames, score] = ...
                localBestASMPeriodicScore(hardBits, asmBits, periodBits, opt)
            hardBits = int8(hardBits(:));
            asmBits = int8(asmBits(:) ~= 0);
            bestErr = inf; bestPos = 0; meanErr = inf; nFrames = 0; score = -inf;
            nTop = max(1, round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'phaseResolveASMPeriodicCandidates'}, 32)));
            maxFrames = max(1, round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'phaseResolveASMPeriodicFrames'}, 8)));
            errMargin = max(0, round(HelperCCSDSTMSplitReceiver.localNumericOption( ...
                opt, {'phaseResolveASMErrMargin'}, 4)));
            [errVec, posVec] = HelperCCSDSTMSplitReceiver.localASMErrorVector(hardBits, asmBits);
            if isempty(errVec)
                return;
            end
            [sortedErr, order] = sort(errVec, 'ascend');
            keep = min(nTop, numel(order));
            if isfinite(sortedErr(1))
                keep = min(numel(order), max(keep, ...
                    nnz(sortedErr <= sortedErr(1) + errMargin)));
            end
            for k = 1:keep
                pos = posVec(order(k));
                err = sortedErr(k);
                [meanNow, framesNow] = HelperCCSDSTMSplitReceiver.localPeriodicASMMeanError( ...
                    hardBits, asmBits, pos, periodBits, maxFrames);
                if framesNow <= 0
                    meanNow = err;
                    framesNow = 1;
                end
                scoreNow = (numel(asmBits)-meanNow) + ...
                    0.75*min(framesNow,maxFrames) - 0.10*err;
                if scoreNow > score
                    score = scoreNow;
                    bestErr = err;
                    bestPos = pos;
                    meanErr = meanNow;
                    nFrames = framesNow;
                end
            end
        end

        function [errVec, posVec] = localASMErrorVector(hardBits, asmBits)
            asmLen = numel(asmBits);
            maxStart = numel(hardBits)-asmLen+1;
            if maxStart < 1
                errVec = []; posVec = []; return;
            end
            asmInv = int8(~logical(asmBits));
            errVec = inf(maxStart,1);
            posVec = (1:maxStart).';
            for pos = 1:maxStart
                segment = hardBits(pos:pos+asmLen-1);
                errVec(pos) = min(nnz(segment ~= asmBits), nnz(segment ~= asmInv));
            end
        end

        function [meanErr, nFrames] = localPeriodicASMMeanError(hardBits, asmBits, firstPos, periodBits, maxFrames)
            meanErr = inf; nFrames = 0;
            if ~isfinite(periodBits) || periodBits <= 0 || firstPos <= 0
                return;
            end
            asmLen = numel(asmBits);
            asmInv = int8(~logical(asmBits));
            errors = zeros(maxFrames,1);
            pos = firstPos;
            while pos+asmLen-1 <= numel(hardBits) && nFrames < maxFrames
                nFrames = nFrames + 1;
                segment = hardBits(pos:pos+asmLen-1);
                errors(nFrames) = min(nnz(segment ~= asmBits), nnz(segment ~= asmInv));
                pos = pos + periodBits;
            end
            if nFrames > 0
                meanErr = mean(errors(1:nFrames));
            end
        end

        function alignment = localEmptyRSASMAlignment()
            rail = struct('Found',false,'BestError',NaN,'BestPosition',NaN, ...
                'MeanError',NaN,'PeriodicFrames',0,'Score',-inf, ...
                'PeriodBits',NaN,'TrimBits',0);
            alignment = struct('Enabled',false,'BothFound',false, ...
                'DecoderSyncDisabled',false,'Score',-inf,'MaxMeanError',inf, ...
                'TMStructureScore',-inf,'TMValidFrames',0,'TMMaxCounterRun',0, ...
                'TMOrientationScore',-inf,'TMSwappedOrientationScore',-inf, ...
                'TMFirstIFrameID',NaN,'TMFirstQFrameID',NaN,'I',rail,'Q',rail);
        end

        function rail = localRailAlignment(info, found)
            rail = struct('Found',logical(found),'BestError',info.BestError, ...
                'BestPosition',info.BestPosition,'MeanError',info.MeanError, ...
                'PeriodicFrames',info.PeriodicFrames,'Score',info.Score, ...
                'PeriodBits',info.PeriodBits,'TrimBits',info.TrimBits);
        end

        function args = localSetNameValue(args, name, value)
            for k = 1:2:numel(args)-1
                if strcmpi(string(args{k}), string(name))
                    args{k+1} = value;
                    return;
                end
            end
            args = [args, {name, value}];
        end

        function found = localHasNameValue(args, name)
            found = false;
            for k = 1:2:numel(args)-1
                if strcmpi(string(args{k}), string(name))
                    found = true;
                    return;
                end
            end
        end

        function value = localOption(opt, names, defaultValue)
            value = defaultValue;
            if ~isstruct(opt)
                return;
            end
            for k = 1:numel(names)
                if isfield(opt, names{k}) && ~isempty(opt.(names{k}))
                    value = opt.(names{k});
                    return;
                end
            end
        end

        function value = localNumericOption(opt, names, defaultValue)
            value = HelperCCSDSTMSplitReceiver.localOption(opt, names, defaultValue);
            if ischar(value) || isstring(value)
                value = str2double(string(value));
            end
            value = double(value);
            if ~isscalar(value) || ~isfinite(value)
                value = defaultValue;
            end
        end

        function value = localLogicalOption(opt, names, defaultValue)
            value = HelperCCSDSTMSplitReceiver.localOption(opt, names, defaultValue);
            if ischar(value) || isstring(value)
                value = any(strcmpi(string(value), {'1','true','on','yes'}));
            else
                value = logical(value);
            end
            value = logical(value(1));
        end

        function [asmLength, found] = localASMOptionLength(opt)
            asmLength = []; found = false;
            names = {'ASMLength','asmLength','frameASMLength','FrameASMLength', ...
                'frame_asm_len','frameASMLen','syncWordLength','SyncWordLength'};
            for k = 1:numel(names)
                if ~isfield(opt,names{k}) || isempty(opt.(names{k}))
                    continue;
                end
                raw = opt.(names{k});
                if ischar(raw) || isstring(raw)
                    raw = str2double(string(raw));
                end
                asmLength = double(raw);
                if ~isscalar(asmLength) || ~isfinite(asmLength) || asmLength < 8 || ...
                        asmLength > 64 || mod(asmLength,8) ~= 0
                    error('HelperCCSDSTMSplitReceiver:InvalidASMLength', ...
                        'ASMLength must be an integer number of bytes from 8 to 64 bits.');
                end
                found = true;
                return;
            end
        end

        function [asmHex, found] = localASMOptionHex(opt)
            asmHex = ''; found = false;
            names = {'ASMHex','asmHex','frameASMHex','FrameASMHex', ...
                'frame_asm_hex','syncWordHex','SyncWordHex'};
            for k = 1:numel(names)
                if ~isfield(opt,names{k}) || isempty(opt.(names{k}))
                    continue;
                end
                raw = opt.(names{k});
                if isstring(raw)
                    raw = char(raw);
                end
                if ~ischar(raw)
                    error('HelperCCSDSTMSplitReceiver:InvalidASMHex', ...
                        'ASMHex must be a character vector or string scalar.');
                end
                asmHex = upper(strtrim(raw));
                if startsWith(asmHex, '0X')
                    asmHex = asmHex(3:end);
                end
                asmHex(asmHex == ' ') = [];
                asmHex(asmHex == '_') = [];
                if isempty(asmHex)
                    continue;
                end
                valid = (asmHex >= '0' & asmHex <= '9') | ...
                    (asmHex >= 'A' & asmHex <= 'F');
                if ~all(valid) || numel(asmHex) > 16
                    error('HelperCCSDSTMSplitReceiver:InvalidASMHex', ...
                        'ASMHex must contain at most 16 hexadecimal digits.');
                end
                found = true;
                return;
            end
        end

        function bits = localBuildCustomASM(asmLength, hasLength, asmHex, hasHex)
            if ~hasLength
                if hasHex
                    asmLength = 4*numel(asmHex);
                else
                    asmLength = 32;
                end
            end
            if hasHex
                if 4*numel(asmHex) ~= asmLength
                    error('HelperCCSDSTMSplitReceiver:ASMHexLengthMismatch', ...
                        'ASMHex length must equal ASMLength/4.');
                end
                bits = HelperCCSDSTMSplitReceiver.localHexToBits(asmHex);
            elseif asmLength == 32
                bits = HelperCCSDSTMSplitReceiver.localDefaultTMASM();
            else
                error('HelperCCSDSTMSplitReceiver:ASMHexRequired', ...
                    'Custom ASMLength values other than 32 require ASMHex.');
            end
        end

        function bits = localDefaultTMASM()
            bits = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1; ...
                1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
        end

        function bits = localHexToBits(hexText)
            bits = zeros(4*numel(hexText),1,'int8');
            for k = 1:numel(hexText)
                val = uint8(hex2dec(hexText(k)));
                bits((k-1)*4+(1:4)) = int8(bitget(val,4:-1:1).');
            end
        end

        function value = localBitsToUnsignedMSB(bits)
            bits = double(bits(:).' ~= 0);
            value = sum(bits .* 2.^(numel(bits)-1:-1:0));
        end

        function maxRun = localModuloCounterRun(values, step)
            values = double(values(:));
            if isempty(values)
                maxRun = 0;
                return;
            end
            maxRun = 1;
            run = 1;
            for k = 2:numel(values)
                if values(k) == mod(values(k-1)+step,256)
                    run = run + 1;
                else
                    run = 1;
                end
                maxRun = max(maxRun,run);
            end
        end
    end
end
