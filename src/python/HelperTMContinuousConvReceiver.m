classdef HelperTMContinuousConvReceiver < handle
    %HELPERTMCONTINUOUSCONVRECEIVER Experimental continuous punctured-conv RX.
    %   It keeps puncture/Viterbi state across arbitrary input chunks,
    %   resolves every possible received puncture-period offset from decoded
    %   ASM evidence, and finds TM boundaries after Viterbi decoding.
    %
    %   TX truth is not accepted by this class.  It must only be used by the
    %   caller after finalize() for independent BER/coverage evaluation.

    properties (SetAccess = private)
        CodeRate = '3/4'
        ASM
        FramePayloadBits
        TracebackDepth = 60
        SoftInputWordLength = 8
        SoftClip = 1
        ASMErrorThreshold = 3
        MinASMFrames = 4
        ConvolutionalG1G2Mode = 'auto-ccsds'
        Verbose = true
    end

    properties (Access = private)
        PuncturePattern
        PunctureInputBits
        PunctureOutputBits
        CandidateOffsets
        CandidateDecoders
        CandidatePendingSoft
        CandidateDecodedBits
        CandidateDiscardRemaining
        InputBitsSeen = 0
        Finalized = false
    end

    methods
        function obj = HelperTMContinuousConvReceiver(varargin)
            parser = inputParser;
            parser.FunctionName = 'HelperTMContinuousConvReceiver';
            addParameter(parser,'CodeRate','3/4');
            addParameter(parser,'ASM',localDefaultASM());
            addParameter(parser,'FramePayloadBits',[]);
            addParameter(parser,'TracebackDepth',60);
            addParameter(parser,'SoftInputWordLength',8);
            addParameter(parser,'SoftClip',1);
            addParameter(parser,'ASMErrorThreshold',3);
            addParameter(parser,'MinASMFrames',4);
            addParameter(parser,'ConvolutionalG1G2Mode','auto-ccsds');
            addParameter(parser,'Verbose',true);
            parse(parser,varargin{:});

            obj.CodeRate = char(string(parser.Results.CodeRate));
            supportedRates = {'1/2','2/3','3/4','5/6','7/8'};
            if ~any(strcmp(obj.CodeRate,supportedRates))
                error('HelperTMContinuousConvReceiver:RateNotImplemented', ...
                    ['The continuous stream receiver implements ', ...
                     'ConvolutionalCodeRate 1/2, 2/3, 3/4, 5/6, and 7/8.']);
            end
            obj.ASM = int8(parser.Results.ASM(:));
            obj.FramePayloadBits = double(parser.Results.FramePayloadBits);
            obj.TracebackDepth = double(parser.Results.TracebackDepth);
            obj.SoftInputWordLength = double(parser.Results.SoftInputWordLength);
            obj.SoftClip = double(parser.Results.SoftClip);
            obj.ASMErrorThreshold = double(parser.Results.ASMErrorThreshold);
            obj.MinASMFrames = double(parser.Results.MinASMFrames);
            obj.ConvolutionalG1G2Mode = char(string( ...
                parser.Results.ConvolutionalG1G2Mode));
            obj.Verbose = logical(parser.Results.Verbose);

            validateattributes(obj.ASM,{'numeric','logical'}, ...
                {'column','binary','nonempty'},mfilename,'ASM');
            validateattributes(obj.FramePayloadBits,{'numeric'}, ...
                {'scalar','integer','positive'},mfilename,'FramePayloadBits');
            validateattributes(obj.TracebackDepth,{'numeric'}, ...
                {'scalar','integer','positive'},mfilename,'TracebackDepth');
            validateattributes(obj.SoftInputWordLength,{'numeric'}, ...
                {'scalar','integer','>=',3,'<=',16},mfilename, ...
                'SoftInputWordLength');
            validateattributes(obj.SoftClip,{'numeric'}, ...
                {'scalar','real','finite','positive'},mfilename,'SoftClip');
            validateattributes(obj.ASMErrorThreshold,{'numeric'}, ...
                {'scalar','integer','>=',0,'<=',numel(obj.ASM)},mfilename, ...
                'ASMErrorThreshold');
            validateattributes(obj.MinASMFrames,{'numeric'}, ...
                {'scalar','integer','>=',2},mfilename,'MinASMFrames');

            puncture = ccsdsTMConvolutionalPunctureConfig(obj.CodeRate);
            obj.PuncturePattern = puncture.Pattern;
            obj.PunctureInputBits = puncture.InputBitsPerPeriod;
            obj.PunctureOutputBits = puncture.OutputBitsPerPeriod;
            obj.CandidateOffsets = (0:obj.PunctureOutputBits-1).';

            baseTrellis = poly2trellis(7,[171 133]);
            [trellis,canonicalMode] = ccsdsTMConvolutionalOutputTrellis( ...
                baseTrellis,obj.ConvolutionalG1G2Mode,obj.CodeRate);
            obj.ConvolutionalG1G2Mode = canonicalMode;

            nCandidates = numel(obj.CandidateOffsets);
            obj.CandidateDecoders = cell(nCandidates,1);
            obj.CandidatePendingSoft = cell(nCandidates,1);
            obj.CandidateDecodedBits = cell(nCandidates,1);
            obj.CandidateDiscardRemaining = obj.CandidateOffsets;
            for iCandidate = 1:nCandidates
                obj.CandidateDecoders{iCandidate} = comm.ViterbiDecoder( ...
                    'TracebackDepth',obj.TracebackDepth, ...
                    'TerminationMethod','Continuous', ...
                    'TrellisStructure',trellis, ...
                    'InputFormat','Soft', ...
                    'OutputDataType','double', ...
                    'SoftInputWordLength',obj.SoftInputWordLength, ...
                    'PuncturePatternSource','Property', ...
                    'PuncturePattern',obj.PuncturePattern);
                obj.CandidatePendingSoft{iCandidate} = zeros(0,1);
                obj.CandidateDecodedBits{iCandidate} = zeros(0,1,'int8');
            end
        end

        function append(obj,softBits)
            if obj.Finalized
                error('HelperTMContinuousConvReceiver:AlreadyFinalized', ...
                    'Create a new receiver before appending another stream.');
            end
            softBits = double(softBits(:));
            if any(~isfinite(softBits))
                error('HelperTMContinuousConvReceiver:NonfiniteSoftInput', ...
                    'Soft input must contain only finite values.');
            end
            if isempty(softBits)
                return;
            end
            obj.InputBitsSeen = obj.InputBitsSeen + numel(softBits);

            for iCandidate = 1:numel(obj.CandidateOffsets)
                candidateInput = softBits;
                discardNow = min(obj.CandidateDiscardRemaining(iCandidate), ...
                    numel(candidateInput));
                if discardNow > 0
                    candidateInput(1:discardNow) = [];
                    obj.CandidateDiscardRemaining(iCandidate) = ...
                        obj.CandidateDiscardRemaining(iCandidate) - discardNow;
                end
                candidateInput = [obj.CandidatePendingSoft{iCandidate}; ...
                    candidateInput]; %#ok<AGROW>
                nUse = floor(numel(candidateInput)/obj.PunctureOutputBits) * ...
                    obj.PunctureOutputBits;
                if nUse == 0
                    obj.CandidatePendingSoft{iCandidate} = candidateInput;
                    continue;
                end
                useSoft = candidateInput(1:nUse);
                obj.CandidatePendingSoft{iCandidate} = candidateInput(nUse+1:end);
                quantized = localQuantizeSoft(useSoft,obj.SoftClip, ...
                    obj.SoftInputWordLength);
                decoded = obj.CandidateDecoders{iCandidate}(quantized);
                obj.CandidateDecodedBits{iCandidate} = [ ...
                    obj.CandidateDecodedBits{iCandidate}; int8(decoded(:))];
            end
        end

        function [payloadBits,info] = finalize(obj)
            if obj.Finalized
                error('HelperTMContinuousConvReceiver:AlreadyFinalized', ...
                    'finalize() can be called only once for each receiver.');
            end
            obj.Finalized = true;
            nCandidates = numel(obj.CandidateOffsets);
            frameLength = numel(obj.ASM) + obj.FramePayloadBits;
            candidateInfo = repmat(localEmptyCandidateInfo(),nCandidates,1);
            candidateRawBits = cell(nCandidates,1);

            for iCandidate = 1:nCandidates
                decoded = obj.CandidateDecodedBits{iCandidate};
                if numel(decoded) > obj.TracebackDepth
                    decoded = decoded(obj.TracebackDepth+1:end);
                else
                    decoded = zeros(0,1,'int8');
                end
                candidateRawBits{iCandidate} = decoded;
                sync = localFindPeriodicASM(decoded,obj.ASM,frameLength, ...
                    obj.ASMErrorThreshold,obj.MinASMFrames);
                candidateInfo(iCandidate).Offset = ...
                    obj.CandidateOffsets(iCandidate);
                discarded = obj.CandidateOffsets(iCandidate) - ...
                    obj.CandidateDiscardRemaining(iCandidate);
                candidateInfo(iCandidate).InputBitsDiscarded = discarded;
                candidateInfo(iCandidate).InputBitsConsumed = ...
                    obj.InputBitsSeen - discarded - ...
                    numel(obj.CandidatePendingSoft{iCandidate});
                candidateInfo(iCandidate).PendingInputBits = ...
                    numel(obj.CandidatePendingSoft{iCandidate});
                candidateInfo(iCandidate).DecodedBitsAfterTraceback = numel(decoded);
                candidateInfo(iCandidate).Locked = sync.Locked;
                candidateInfo(iCandidate).ASMPhase = sync.Phase;
                candidateInfo(iCandidate).LongestGoodRun = sync.LongestGoodRun;
                candidateInfo(iCandidate).GoodASMCount = sync.GoodASMCount;
                candidateInfo(iCandidate).MeanASMErrors = sync.MeanASMErrors;
                candidateInfo(iCandidate).WorstASMErrors = sync.WorstASMErrors;
                candidateInfo(iCandidate).FirstFrameStart = sync.FirstFrameStart;
                candidateInfo(iCandidate).CompleteFrames = sync.CompleteFrames;
                candidateInfo(iCandidate).FrameStarts = sync.FrameStarts;
                candidateInfo(iCandidate).ASMErrors = sync.ASMErrors;
            end

            score = [[candidateInfo.Locked].', ...
                [candidateInfo.LongestGoodRun].', ...
                [candidateInfo.GoodASMCount].', ...
                -[candidateInfo.MeanASMErrors].', ...
                -[candidateInfo.Offset].'];
            score(~isfinite(score)) = -realmax;
            [~,order] = sortrows(score,[-1 -2 -3 -4 -5]);
            selected = order(1);
            lockedCandidates = find([candidateInfo.Locked]);
            ambiguous = false;
            if numel(lockedCandidates) > 1
                best = candidateInfo(selected);
                for idx = lockedCandidates(:).'
                    if idx ~= selected && ...
                            candidateInfo(idx).LongestGoodRun == best.LongestGoodRun && ...
                            candidateInfo(idx).GoodASMCount == best.GoodASMCount && ...
                            candidateInfo(idx).MeanASMErrors == best.MeanASMErrors
                        ambiguous = true;
                    end
                end
            end

            if isempty(lockedCandidates) || ambiguous
                payloadBits = zeros(obj.FramePayloadBits,0,'int8');
            else
                starts = candidateInfo(selected).FrameStarts;
                raw = candidateRawBits{selected};
                payloadBits = zeros(obj.FramePayloadBits,numel(starts),'int8');
                for iFrame = 1:numel(starts)
                    firstPayload = starts(iFrame) + numel(obj.ASM);
                    payloadBits(:,iFrame) = raw(firstPayload: ...
                        firstPayload+obj.FramePayloadBits-1);
                end
            end

            info = struct;
            info.Available = ~isempty(lockedCandidates) && ~ambiguous;
            info.Reason = 'locked';
            if isempty(lockedCandidates)
                info.Reason = 'no candidate reached the multi-frame ASM lock threshold';
            elseif ambiguous
                info.Reason = 'multiple puncture offsets have indistinguishable ASM evidence';
            end
            info.CodeRate = obj.CodeRate;
            info.PunctureInputBits = obj.PunctureInputBits;
            info.PunctureOutputBits = obj.PunctureOutputBits;
            info.FrameLengthRawBits = frameLength;
            info.InputBitsSeen = obj.InputBitsSeen;
            info.SelectedCandidate = selected;
            info.SelectedOffset = candidateInfo(selected).Offset;
            info.Ambiguous = ambiguous;
            info.Candidates = candidateInfo;
            info.RecoveredFrames = size(payloadBits,2);
            info.TracebackBitsDiscarded = obj.TracebackDepth;
            info.ConvolutionalG1G2Mode = obj.ConvolutionalG1G2Mode;
            info.ASMErrorThreshold = obj.ASMErrorThreshold;
            info.MinASMFrames = obj.MinASMFrames;

            if obj.Verbose
                fprintf('[Conv stream %s] input=%d coded bits, frame=%d raw bits, P/Q=%d/%d\n', ...
                    obj.CodeRate,obj.InputBitsSeen,frameLength,obj.PunctureInputBits, ...
                    obj.PunctureOutputBits);
                for iCandidate = 1:nCandidates
                    c = candidateInfo(iCandidate);
                    fprintf(['  candidate drop=%d: lock=%d, run=%d, goodASM=%d, ', ...
                        'meanErr=%.3g, frames=%d, pending=%d\n'], ...
                        c.Offset,c.Locked,c.LongestGoodRun,c.GoodASMCount, ...
                        c.MeanASMErrors,c.CompleteFrames,c.PendingInputBits);
                end
                if info.Available
                    fprintf('  selected drop=%d, recovered=%d frames (RX ASM evidence only)\n', ...
                        info.SelectedOffset,info.RecoveredFrames);
                else
                    fprintf('  NOT LOCKED: %s\n',info.Reason);
                end
            end
        end
    end
end

function q = localQuantizeSoft(x,clipValue,wordLength)
    x = min(max(double(x(:)),-clipValue),clipValue);
    levels = 2^wordLength-1;
    q = uint16(round((x/clipValue+1)*levels/2));
    if wordLength <= 8
        q = uint8(q);
    end
end

function sync = localFindPeriodicASM(bits,asm,frameLength,errorThreshold,minFrames)
    sync = struct('Locked',false,'Phase',NaN,'LongestGoodRun',0, ...
        'GoodASMCount',0,'MeanASMErrors',Inf,'WorstASMErrors',Inf, ...
        'FirstFrameStart',NaN,'CompleteFrames',0, ...
        'FrameStarts',zeros(0,1),'ASMErrors',zeros(0,1));
    bits = int8(bits(:));
    asm = int8(asm(:));
    if numel(bits) < frameLength || numel(bits) < numel(asm)
        return;
    end
    bipolarBits = 2*double(bits)-1;
    bipolarASM = 2*double(asm)-1;
    corr = conv(bipolarBits,flipud(bipolarASM),'valid');
    allErrors = round((numel(asm)-corr)/2);

    bestKey = [-1,-1,-Inf,-Inf];
    best = sync;
    maxPhase = min(frameLength,numel(allErrors));
    for phase = 1:maxPhase
        positions = (phase:frameLength:numel(allErrors)).';
        positions = positions(positions+frameLength-1 <= numel(bits));
        if isempty(positions)
            continue;
        end
        errors = allErrors(positions);
        good = errors <= errorThreshold;
        [runLength,runStart] = localLongestTrueRun(good);
        goodCount = nnz(good);
        if runLength > 0
            runErrors = errors(runStart:runStart+runLength-1);
            meanErrors = mean(runErrors);
            worstErrors = max(runErrors);
        else
            meanErrors = Inf;
            worstErrors = Inf;
        end
        key = [runLength,goodCount,-meanErrors,-phase];
        if localLexicographicGreater(key,bestKey)
            bestKey = key;
            best.Locked = runLength >= minFrames;
            best.Phase = phase;
            best.LongestGoodRun = runLength;
            best.GoodASMCount = goodCount;
            best.MeanASMErrors = meanErrors;
            best.WorstASMErrors = worstErrors;
            if runLength > 0
                first = positions(runStart);
                starts = (first:frameLength: ...
                    (numel(bits)-frameLength+1)).';
                best.FirstFrameStart = first;
                best.CompleteFrames = numel(starts);
                best.FrameStarts = starts;
                best.ASMErrors = allErrors(starts);
            end
        end
    end
    sync = best;
end

function [bestLength,bestStart] = localLongestTrueRun(mask)
    mask = logical(mask(:));
    padded = [false;mask;false];
    changes = diff(padded);
    starts = find(changes == 1);
    stops = find(changes == -1)-1;
    if isempty(starts)
        bestLength = 0;
        bestStart = 0;
        return;
    end
    lengths = stops-starts+1;
    [bestLength,index] = max(lengths);
    bestStart = starts(index);
end

function tf = localLexicographicGreater(a,b)
    tf = false;
    for k = 1:numel(a)
        if a(k) > b(k)
            tf = true;
            return;
        elseif a(k) < b(k)
            return;
        end
    end
end

function s = localEmptyCandidateInfo()
    s = struct('Offset',NaN,'InputBitsDiscarded',0, ...
        'InputBitsConsumed',0,'PendingInputBits',0, ...
        'DecodedBitsAfterTraceback',0,'Locked',false,'ASMPhase',NaN, ...
        'LongestGoodRun',0,'GoodASMCount',0,'MeanASMErrors',Inf, ...
        'WorstASMErrors',Inf,'FirstFrameStart',NaN,'CompleteFrames',0, ...
        'FrameStarts',zeros(0,1),'ASMErrors',zeros(0,1));
end

function bits = localDefaultASM()
    value = uint32(hex2dec('1ACFFC1D'));
    bits = int8(bitget(value,32:-1:1)).';
end
