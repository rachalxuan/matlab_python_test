classdef HelperCCSDSTMDecoder < comm.internal.Helper & satcom.internal.ccsds.tmBase
    % HelperCCSDSTMDecoder CCSDS telemetry Decoder
    %
    %   Note: This is a helper and its API and/or functionality may change
    %   in subsequent releases.
    %
    %   HDEC = HelperCCSDSTMDecoder creates a CCSDS telemetry decoder
    %   object, HDEC. The object is designed to decode the demodulated
    %   telemetry symbols that is based on CCSDS TM synchronization and
    %   channel coding standard. The object supports decoding of RS,
    %   convolutional, and concatenated. The object also supports no
    %   channel coding scheme. The object also does the frame
    %   synchronization along with phase ambiguity resolution.
    %
    %   Step method syntax:
    %
    %   Y = step(HDEC,X) decodes the demodulated symbols X and returns the
    %   decoded bits, Y. Except for RS codes, all other decoding schemes
    %   expect soft input. Length of Y is an integer multiple of transfer
    %   frame length for the specified link. If input X doesn't contain
    %   sufficient bits such that Y doesn't make up a transfer frame, then
    %   Y is a zero vector of transfer frame length. This situation
    %   typically occurs while the simulation chain is in initial stages
    %   where there will be delays incurred while doing demodulation and
    %   decoding. For this reason, the size of X can change even after the
    %   object is locked.
    %
    %   Limitations of the current system object:
    %   1. Does not support ConvolutionalCodeRate to be '3/4', '5/6 and
    %      '7/8'
    %   2. Phase ambiguity resolution of only BPSK and QPSK are
    %      supported currently.
    %   3. Does not support turbo and LDPC decoding
    %   4. Does not support PCM-format of 'NRZ-M' for convolutional and
    %      concatenated codes
    %
    %   System objects may be called directly like a function instead of
    %   using the step method. For example, y = step(obj, x) and y = obj(x)
    %   are equivalent.
    %
    %   HelperCCSDSTMDecoder properties:
    %
    %   ChannelCoding               - Error control channel coding scheme
    %   NumBytesInTransferFrame     - Number of bytes in one transfer frame
    %   ConvolutionalCodeRate       - Code rate of convolutional code
    %   ViterbiTraceBackDepth       - Viterbi traceback depth
    %   ViterbiTrellis              - Trellis structure of Viterbi decoder
    %   ViterbiWordLength           - Quantization word length for Viterbi
    %                                 decoder
    %   RandomizerEnabled           - Option for randomizing the data
    %   HasASM                      - Option for inserting attached sync
    %                                 marker (ASM)
    %   RSMessageLength             - Number of bytes in one Reed-Solomon
    %                                 (RS) message block
    %   RSInterleavingDepth         - Interleaving depth of the RS code
    %   IsRSMessageShortened        - Option to shorten RS code
    %   RSShortenedMessageLength    - Number of bytes in RS shortened
    %                                 message block
    %   Modulation                  - Modulation scheme
    %   PCMFormat                   - Pulse code modulation (PCM) format
    %   DisableFrameSynchronization - Option to disable frame
    %                                 synchronization
    %   DisablePhaseAmbiguityResolution - Option to disable phase ambiguity
    %                                     resolution

    %   Copyright 2020-2021 The MathWorks, Inc.

    % Public, non-tunable properties
    properties(Nontunable)
        ViterbiTraceBackDepth = 60
        ViterbiTrellis = poly2trellis(7, [171 133])
        ViterbiWordLength = 8
        DisableFrameSynchronization = false
        DisablePhaseAmbiguityResolution = false
        DebugPCMFormat = false
        DebugLDPC = false
        DebugTurbo = false
        % Maximum belief-propagation iterations for ordinary TM LDPC.
        % Five iterations is too shallow near the decoder waterfall and
        % can turn a low raw BER into an otherwise avoidable frame loss.
        LDPCMaxIterations = 20
        CodedSyncOffset = 0
        UsePeriodicCodedASMSync = true
        CodedASMPeriodicFrames = 8
        % Production-style ASM state controls.  ErrorThreshold is mapped
        % to a normalized soft-correlation floor; lock/unlock thresholds
        % provide holdover through isolated faded frames.
        FrameSyncBitSlipTolerance = 3
        FrameSyncASMErrorThreshold = 3
        FrameSyncLockThreshold = 2
        FrameSyncUnlockThreshold = 3
    end

    % Pre-computed constants
    properties(Access = private)
        pDec
        pFirstTimeStepCalling = true % To detect if step method is being for the first time. This is helpful in convolutional codes where delay is there for the first time it is called
        pInputBuffer
        pOutputBuffer
        pDifferentialDecoderBit
        pRotatedASM
        pFullInputBufferLength
        pFrameLength
        pASMOffsetLength
        pLDPCDecoderCfg
        pLDPCCodewordLength
        pLDPCFullCodewordLength
        pLDPCPuncturedLength = 0
        pLDPCMessageLength
        pLDPCMaxIterations = 20
        pTurboDecoder
        pTurboCodewordLength
        pTurboMessageLength
        pTurboInputIndices
        pFrameSyncLocked = false
        pFrameSyncGoodCount = 0
        pFrameSyncBadCount = 0
        pFrameSyncLastPhase = 1
        pFrameSyncObservationIndex = zeros(0,1)
        pFrameSyncAcceptedTrace = false(0,1)
        pFrameSyncLockedTrace = false(0,1)
        pFrameSyncHoldoverTrace = false(0,1)
        pFrameSyncCorrelationTrace = zeros(0,1)
        pFrameSyncThresholdTrace = zeros(0,1)
        pFrameSyncPositionTrace = zeros(0,1)
        pFrameSyncPhaseTrace = zeros(0,1)
        pFrameSyncTelemetrySource = 'unavailable'
        % Side-band provenance only: never used to alter synchronization/FEC.
        pInputBitsSeen = 0
        pPendingFrameStartBits = zeros(0,1)
        pDecodedFrameStartBits = zeros(0,1)
    end

    properties
        % RandomizerFECPosition Randomizer position relative to the TX FEC encoder.
        %   "afterEncoding" means RX derandomizes before FEC decoding.
        %   "beforeEncoding" means RX derandomizes after FEC decoding.
        RandomizerFECPosition = 'afterEncoding'
        % DataPathMode Information-stream topology handled by this decoder.
        %   "single" decodes one ordinary TM stream. The top-level receiver
        %   deinterleaves "dualIQ" into two independent single-stream decoders.
        DataPathMode = 'single'
        % ConvolutionalG1G2Mode Received convolutional stream convention.
        %   Must match the transmitter. Supported values are G1G2,
        %   G1G2-inverted (G1G2反), G2G1, and G2G1-inverted (G2G1反).
        ConvolutionalG1G2Mode = 'auto-ccsds'
        % TPCCodeRate Effective shortened TPC rate.
        %   "native" uses 57x57/64x64. "1/2" uses 45x45/64x64.
        %   "2/3" uses 52x52/64x64.
        TPCCodeRate = 'native'
        % TPCBlocksPerTF Number of TPC codewords contained in one coded TF.
        TPCBlocksPerTF = 1
        % TPCInterleaver Codeword deinterleaver mode for TPC.
        %   Must match the transmitter-side TPCInterleaver setting.
        TPCInterleaver = 'auto'
        % TPCUseKnownZeroConstraint Use deterministic zero filler as prior.
        %   This improves shortened-rate decoding without changing the
        %   transmitted 64-by-64 codeword or its interleaver.
        TPCUseKnownZeroConstraint = false
        % TPCDecoderMode Product-code decoder mode.
        %   "iterative" is the production Chase decoder.  The
        %   "hard-systematic-debug" mode is a front-end diagnostic that
        %   bypasses FEC correction and extracts transmitted systematic bits.
        TPCDecoderMode = 'iterative'
    end

    methods
        % Constructor
        function obj = HelperCCSDSTMDecoder(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,numel(varargin),varargin{:})
        end

        function positions = getDecodedFramePositions(obj)
            % One entry per decoded TF returned by the latest call. NaN is
            % an invalid/dummy output, not a received physical frame.
            positions = struct('Available',true, ...
                'Source','decoder-input-bit-position', ...
                'InputStartBit',obj.pDecodedFrameStartBits(:), ...
                'InputFrameLength',double(obj.pFullInputBufferLength));
        end

        function telemetry = getFrameSyncTelemetry(obj)
            % Return receiver-observable ASM lock history.  This method
            % deliberately exposes no transmitted-frame or BER truth.
            locked = logical(obj.pFrameSyncLockedTrace(:));
            accepted = logical(obj.pFrameSyncAcceptedTrace(:));
            transitions = diff([false;locked]);
            lockEvents = nnz(transitions == 1);
            lossEvents = nnz(transitions == -1);
            telemetry = struct( ...
                'Available',obj.HasASM && ~isempty(locked), ...
                'Source',char(obj.pFrameSyncTelemetrySource), ...
                'ObservationIndex',double(obj.pFrameSyncObservationIndex(:)), ...
                'ASMObservationAccepted',accepted, ...
                'Locked',locked, ...
                'Holdover',logical(obj.pFrameSyncHoldoverTrace(:)), ...
                'Correlation',double(obj.pFrameSyncCorrelationTrace(:)), ...
                'MinimumCorrelation',double(obj.pFrameSyncThresholdTrace(:)), ...
                'PeakPosition',double(obj.pFrameSyncPositionTrace(:)), ...
                'PhaseIndex',double(obj.pFrameSyncPhaseTrace(:)), ...
                'AcquireThresholdFrames',max(1,round(double( ...
                    obj.FrameSyncLockThreshold))), ...
                'LoseThresholdFrames',max(1,round(double( ...
                    obj.FrameSyncUnlockThreshold))), ...
                'LockRate',mean(double(locked)), ...
                'LockedAtEnd',logical(obj.pFrameSyncLocked), ...
                'LockEvents',lockEvents, ...
                'LossEvents',lossEvents, ...
                'Reacquisitions',max(0,lockEvents-1));
        end
    end

    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants
            setupImpl@satcom.internal.ccsds.tmBase(obj);
            if ~any(strcmpi(obj.RandomizerFECPosition, {'afterEncoding','beforeEncoding'}))
                error('HelperCCSDSTMDecoder:InvalidRandomizerFECPosition', ...
                    ['Unsupported RandomizerFECPosition="%s". Use ' ...
                     'afterEncoding or beforeEncoding.'], ...
                    char(obj.RandomizerFECPosition));
            end
            if ~any(strcmpi(obj.DataPathMode, {'single','dualIQ'}))
                error('HelperCCSDSTMDecoder:InvalidDataPathMode', ...
                    'Unsupported DataPathMode="%s". Use single or dualIQ.', ...
                    char(obj.DataPathMode));
            end
            obj.pInputBuffer = [];
            obj.pOutputBuffer = [];
            asm = obj.pASM;
            obj.pFullInputBufferLength = obj.pPRNSequenceLength + length(asm)*obj.HasASM;
            if obj.IsRSMessageShortened == 0
                % It is possible that "RSShortenedMessageLength" is
                % set to non standard value even after disabling
                % shortening.
                obj.RSShortenedMessageLength = obj.RSMessageLength;
            end
            if any(strcmp(obj.ChannelCoding, {'convolutional', 'concatenated'}))
                [convTrellis, canonicalConvMode] = ...
                    ccsdsTMConvolutionalOutputTrellis( ...
                    obj.ViterbiTrellis, obj.ConvolutionalG1G2Mode, ...
                    obj.ConvolutionalCodeRate);
                isDefaultConvMode = strcmpi(canonicalConvMode, ...
                    'G1G2-inverted');
                obj.pFirstTimeStepCalling = true;
                obj.pDec = comm.ViterbiDecoder("TracebackDepth",obj.ViterbiTraceBackDepth,...
                    "TerminationMethod","Continuous",...
                    "TrellisStructure",convTrellis,...
                    "InputFormat","Soft",...
                    "OutputDataType","double",...
                    "SoftInputWordLength",obj.ViterbiWordLength,...
                    "PuncturePatternSource","Property");
                obj.pDifferentialDecoderBit = 0; % In practice, the initial value of this bit doesn't matter as initial few frames needs to be discarded for the synchronization algorithms to converge. So, by the time full frames are being taken, proper value in this property will be initialized
                if any(strcmp(obj.PCMFormat, {'NRZ-M','NRZ-S'}))
                    if obj.DebugPCMFormat
                        fprintf('[PCM DEBUG] %s + %s: use differential-coded ASM sync before Viterbi, then differential decode after Viterbi.\n', ...
                            obj.ChannelCoding, obj.PCMFormat);
                    end
                end
                % Calculate buffer length
                switch(obj.ConvolutionalCodeRate)
                    case '1/2'
                        % These values are generated by separately
                        % passing ASM bits through the 1/2 rate
                        % convolutional encoder that is given in CCSDS
                        % standard and taking the last 52 bits
                        asm = [1;0;0;0;0;0;0;1;1;1;0;0;1;0;0;1;0;1;1;1;0;0;0;1;1;0;1;...
                            0;1;0;1;0;0;1;1;1;0;0;1;1;1;1;0;1;0;0;1;1;1;1;1;0];
                        obj.pDec.PuncturePattern = [1;1];
                        obj.pASMOffsetLength = 12;
                        obj.pFullInputBufferLength = 2*(obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM);
                        if ~localIsDefaultTMASM(obj.pASM) || ~isDefaultConvMode
                            asm = buildConvEncodedASMForSync(obj, obj.pASM, convTrellis, ...
                                obj.pDec.PuncturePattern, obj.pASMOffsetLength, false);
                        end
                    case '2/3'
                        % Following values are generated by separately
                        % passing ASM bits through the 2/3
                        % convolutional encoder and taking only 38 bits
                        asm = [1;1;0;1;0;1;0;1;1;1;0;0;0;0;0;1;0;...
                            1;1;1;1;1;1;0;0;0;0;1;0;1;0;0;0;1;0;1;0;1];
                        obj.pDec.PuncturePattern = [1;1;0;1];
                        % 理论上，6 个输入 bit 会产生：6 input bits × 2 = 12 mother coded bits
                        % 然后按 [1 1 0 1] 打孔，12 个 mother bits 里大约保留 9 个。
                        % 经验多跳 1 bit，保留 38-bit ASM 模板
                        obj.pASMOffsetLength = 10;
                        obj.pFullInputBufferLength = 3*(obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM)/2; % Note that obj.pPRNSequenceLength is always an even number. So, division by 2 is always an integer value
                        if ~localIsDefaultTMASM(obj.pASM) || ~isDefaultConvMode
                            asm = buildConvEncodedASMForSync(obj, obj.pASM, convTrellis, ...
                                obj.pDec.PuncturePattern, obj.pASMOffsetLength, false);
                        end
                    case '3/4'
                        % 3/4 punctured convolutional code.
                        % Tx side uses the same puncture pattern:
                        % [1;1;0;1;1;0]

                        obj.pDec.PuncturePattern = [1;1;0;1;1;0];

                        % 3/4 means: 3 input bits -> 4 transmitted coded bits.
                        % Use the same input-length trimming logic as transmitter:
                        % puncture period corresponds to 3 input bits.
                        tempLen = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                        convInLen = tempLen - mod(tempLen, 3);
                        obj.pFullInputBufferLength = 4*convInLen/3;

                        % Convolutional encoder memory = 6 input bits.
                        % Mother code rate is 1/2, so first 6 input bits
                        % correspond to 12 mother-code output bits.
                        % After puncturing, this becomes 8 transmitted coded bits
                        % for pattern [1;1;0;1;1;0].
                        % 6 input bits -> 2 个 puncture 周期 -> 8 个 transmitted coded bits

                        % The stable coded-ASM suffix starts 9 transmitted
                        % bits after the true coded-frame boundary for 3/4.
                        % Using 7 cuts the Viterbi input two bits late and
                        % breaks the puncture phase.
                        obj.pASMOffsetLength = 9;

                        % Build coded ASM template for frame synchronization.
                        asm = buildConvEncodedASMForSync(obj, obj.pASM, convTrellis, ...
                            obj.pDec.PuncturePattern, obj.pASMOffsetLength, false);
                    case '5/6'
                        % 5/6 punctured convolutional code.
                        % Tx side pattern:
                        % [1;1;0;1;1;0;0;1;1;0]
                        %
                        % 5 input bits -> 6 transmitted coded bits.

                        obj.pDec.PuncturePattern = [1;1;0;1;1;0;0;1;1;0];
                        % 3/4 means: 3 input bits -> 4 transmitted coded bits.
                        % Use the same input-length trimming logic as transmitter:
                        % puncture period corresponds to 3 input bits.
                        tempLen = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                        punctureInputPeriod = 5;
                        if obj.HasASM
                            localValidateHighRateConvFrameLength( ...
                                obj.ConvolutionalCodeRate, tempLen, punctureInputPeriod, '1116');
                        end
                        convInLen = tempLen - mod(tempLen, punctureInputPeriod);
                        obj.pFullInputBufferLength = 6*convInLen/5;

                        % Convolutional encoder memory = 6 input bits.
                        % Mother code rate is 1/2, so first 6 input bits
                        % correspond to 12 mother-code output bits.
                        % After puncturing, this becomes 8 transmitted coded bits
                        % for pattern [1;1;0;1;1;0].
                        % 6 input bits -> 2 个 puncture 周期 -> 8 个 transmitted coded bits

%                         这个 offset 是因为卷积码有记忆，ASM 的前若干编码输出会受前面状态影响，所以同步时不是简单拿完整编码 ASM 直接匹配，而是取稳定后的部分。
                        obj.pASMOffsetLength = 9;

                        % Build coded ASM template for frame synchronization.
                        asm = buildConvEncodedASMForSync(obj, obj.pASM, convTrellis, ...
                            obj.pDec.PuncturePattern, obj.pASMOffsetLength, false);
                    case '7/8'
                        % 7/8 punctured convolutional code.
                        % Tx side pattern:
                        % [1;1;0;1;0;1;0;1;1;0;0;1;1;0]
                        %
                        % 7 input bits -> 8 transmitted coded bits.

                        obj.pDec.PuncturePattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];

                        tempLen = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                        punctureInputPeriod = 7;
                        if obj.HasASM
                            localValidateHighRateConvFrameLength( ...
                                obj.ConvolutionalCodeRate, tempLen, punctureInputPeriod, '1116 or 1123');
                        end
                        convInLen = tempLen - mod(tempLen, punctureInputPeriod);
                        obj.pFullInputBufferLength = 8*convInLen/7;

                        obj.pASMOffsetLength = 7;

                        % Build coded ASM template for frame synchronization.
                        asm = buildConvEncodedASMForSync(obj, obj.pASM, convTrellis, ...
                            obj.pDec.PuncturePattern, obj.pASMOffsetLength, false);

                end
            end

            if obj.DisablePhaseAmbiguityResolution
                modscheme = "other"; % So that following switch case executes code in otherwise case.
            else
                modscheme = obj.Modulation;
            end

            switch(modscheme)
                case {"BPSK", "GMSK"}
                    obj.pRotatedASM = zeros(length(asm), 2);
                    obj.pRotatedASM(:, 1) = 2*asm(:)-1; % Map to +1, -1
                    obj.pRotatedASM(:, 2) = 1 - 2*asm(:); % Map to -1, +1
                    obj.pNumBitsPerSymbol = 1;
                case {"QPSK", "OQPSK"}
                    RotationMap = [0, 1, 2, 3; ... % Mapping for phase rotation of 0
                        2, 0, 3, 1; ... % Mapping for phase rotation of pi/2
                        3, 2, 1, 0; ... % Mapping for phase rotation of pi
                        1, 3, 0, 2;... % Mapping for phase rotation of 3*pi/2
                        ];
                    m = 2;
                    obj.pNumBitsPerSymbol = 2;
                    ASMSymbols = comm.internal.utilities.bi2deLeftMSB(double(reshape(asm,m,[]).'),2);
                    obj.pRotatedASM = zeros(length(asm), 2^m);
                    for iRot = 1:4
                        temp = comm.internal.utilities.de2biBase2LeftMSB(RotationMap(iRot, ASMSymbols+1).', m).';
                        obj.pRotatedASM(:, iRot) = 2*temp(:)-1; % Map to +1, -1
                    end
                    case "8PSK"
                    % === 【修改点】新增 8PSK 支持 ===
                    % 目前只支持 0 相位下的 ASM 匹配 (假设 Demodulator 已经解对了)
                    % 如果需要支持 8 相位搜索，需要生成 8 个旋转后的 ASM 模式，这里暂取基准模式
                    % obj.pRotatedASM = 2*asm(:)-1;
                    % obj.pNumBitsPerSymbol = 3;

                    %----------------------------
                    m = 3;
                    obj.pNumBitsPerSymbol = m;

                    % TM 8PSK demodulator uses this custom mapping:
                    % comm.PSKDemodulator(8, pi/4, ...
                    %   'SymbolMapping','Custom', ...
                    %   'CustomSymbolMapping',[0 4 6 2 3 7 5 1])
                    %
                    % CustomSymbolMapping maps symbol index -> bit label.
                    map = [0 4 6 2 3 7 5 1];

                    % Inverse map: bit label -> symbol index.
                    invMap = zeros(1, 8);
                    for k = 1:8
                        invMap(map(k) + 1) = k - 1;
                    end

                    % ASM length may not be divisible by 3 in all configurations.
                    % Pad only for symbol grouping, then trim back to original ASM bit length.
                    asmLen = length(asm);
                    padLen = mod(m - mod(asmLen, m), m);
                    asmPadded = [asm(:); zeros(padLen, 1)];

                    % Convert ASM bits into 8PSK demod bit labels.
                    asmLabels = comm.internal.utilities.bi2deLeftMSB( ...
                        double(reshape(asmPadded, m, []).'), 2);

                    % Convert bit labels to transmitted 8PSK symbol indices.
                    asmSymIdx = zeros(size(asmLabels));
                    for k = 1:length(asmLabels)
                        asmSymIdx(k) = invMap(asmLabels(k) + 1);
                    end

                    % Generate all 8 possible carrier phase ambiguities.
                    % A rotation by k*pi/4 advances the received symbol index by k modulo 8.
                    obj.pRotatedASM = zeros(asmLen, 8);

                    for iRot = 1:8
                        rot = iRot - 1;

                        rotatedSymIdx = mod(asmSymIdx + rot, 8);

                        % Convert rotated symbol index back to the bit label the demodulator
                        % would produce under this phase ambiguity.
                        rotatedLabels = map(rotatedSymIdx + 1).';

                        rotatedBits = comm.internal.utilities.de2biBase2LeftMSB( ...
                            rotatedLabels, m).';

                        rotatedBits = rotatedBits(:);
                        rotatedBits = rotatedBits(1:asmLen);

                        % Decoder frame correlation expects soft sign convention:
                        % bit 1 -> +1, bit 0 -> -1, matching existing code style.
                        obj.pRotatedASM(:, iRot) = 2*rotatedBits(:) - 1;
                    end
                    %-----------------------------

                otherwise % Don't do phase ambiguity resolution
                    obj.pRotatedASM = 2*asm(:)-1;
                    obj.pNumBitsPerSymbol = 1;
            end

            if any(strcmp(obj.ChannelCoding, {'convolutional','concatenated'})) && ...
                    any(strcmp(obj.PCMFormat, {'NRZ-M','NRZ-S'})) && ...
                    any(strcmp(modscheme, {'BPSK','GMSK','QPSK','OQPSK','8PSK'}))
                sync0 = localPCMBuildConvEncodedASMSync(obj.pASM, 0, obj.PCMFormat, ...
                    convTrellis, obj.pDec.PuncturePattern, ...
                    obj.pASMOffsetLength, false);
                sync1 = localPCMBuildConvEncodedASMSync(obj.pASM, 1, obj.PCMFormat, ...
                    convTrellis, obj.pDec.PuncturePattern, ...
                    obj.pASMOffsetLength, false);
                obj.pRotatedASM = [ ...
                    localPCMBuildRotatedASMForMod(sync0, modscheme), ...
                    localPCMBuildRotatedASMForMod(sync1, modscheme)];
                if obj.DebugPCMFormat
                    fprintf('[PCM DEBUG] pre-Viterbi sync templates: len=%d, columns=%d, offset=%d\n', ...
                        size(obj.pRotatedASM,1), size(obj.pRotatedASM,2), obj.pASMOffsetLength);
                end
            end

            if any(strcmp(obj.ChannelCoding, {'concatenated', 'convolutional'}))
%                 obj.pFrameLength = length(asm) + obj.pPRNSequenceLength*obj.pInverseCodeRate;
                obj.pFrameLength = obj.pFullInputBufferLength - obj.pASMOffsetLength;
            else
                obj.pFrameLength = length(asm) + obj.pPRNSequenceLength;
            end

            if strcmp(obj.ChannelCoding, "turbo")
                invr = getInverseCodeRate(obj);
                kReq = double(obj.NumBitsInInformationBlock);
                syncLen = length(obj.pASM)*obj.HasASM;

                obj.pTurboMessageLength = kReq;
                mask = logical(obj.pTurboPuncturePattern(:));
                obj.pTurboCodewordLength = nnz(mask);

                idxFull = getTurboIOIndices(kReq, 4, 4);
                assert(length(idxFull) == length(mask), ...
                    'Turbo IO index length mismatch: idxFull=%d, punctureMask=%d.', ...
                    length(idxFull), length(mask));
                obj.pTurboInputIndices = idxFull(mask);
                obj.pTurboDecoder = comm.TurboDecoder( ...
                    'TrellisStructure', obj.TurboTrellis, ...
                    'InterleaverIndices', obj.pTurboInterleaverIndices, ...
                    'InputIndicesSource', 'Property', ...
                    'InputIndices', obj.pTurboInputIndices, ...
                    'NumIterations', 6);

                obj.pFullInputBufferLength = obj.pTurboCodewordLength + syncLen;
                obj.pFrameLength = obj.pFullInputBufferLength;

                if obj.DebugTurbo
                    fprintf('[Turbo setup] k=%d, invr=%d, syncLen=%d, cwLen=%d, fullFrame=%d\n', ...
                        obj.pTurboMessageLength, invr, syncLen, ...
                        obj.pTurboCodewordLength, obj.pFullInputBufferLength);
                end
            end

            if strcmp(obj.ChannelCoding, "LDPC")
                invr = getInverseCodeRate(obj);
                kReq = double(obj.NumBitsInInformationBlock);
                S = loadOrCreateTMLDPCH(kReq, invr);

                maxIterations = double(obj.LDPCMaxIterations);
                if ~isscalar(maxIterations) || ~isfinite(maxIterations) || ...
                        maxIterations < 1
                    error('HelperCCSDSTMDecoder:InvalidLDPCMaxIterations', ...
                        'LDPCMaxIterations must be a finite positive scalar.');
                end
                obj.pLDPCMaxIterations = max(1, round(maxIterations));

                obj.pLDPCMessageLength = S.k;
                obj.pLDPCCodewordLength = S.n;
                obj.pLDPCFullCodewordLength = size(S.H, 2);
                obj.pLDPCPuncturedLength = ...
                    obj.pLDPCFullCodewordLength - obj.pLDPCCodewordLength;
                if obj.pLDPCPuncturedLength < 0
                    error('HelperCCSDSTMDecoder:InvalidLDPCMatrixLength', ...
                        ['LDPC parity-check matrix has %d columns but the ', ...
                         'transmitted codeword has %d bits.'], ...
                        obj.pLDPCFullCodewordLength, obj.pLDPCCodewordLength);
                end
                obj.pLDPCDecoderCfg = ldpcDecoderConfig(sparse(logical(S.H)));

                % 普通 TM LDPC: coded frame = ASM + LDPC codeword
                syncLen = length(obj.pASM)*obj.HasASM;
                obj.pFullInputBufferLength = obj.pLDPCCodewordLength + syncLen;
                obj.pFrameLength = obj.pFullInputBufferLength;

                if obj.DebugLDPC
                    fprintf(['[LDPC setup] k=%d, txN=%d, fullN=%d, ', ...
                        'punctured=%d, rate=%.6f, syncLen=%d, ', ...
                        'fullFrame=%d, maxIter=%d, Hnnz=%d\n'], ...
                        obj.pLDPCMessageLength, ...
                        obj.pLDPCCodewordLength, ...
                        obj.pLDPCFullCodewordLength, ...
                        obj.pLDPCPuncturedLength, ...
                        obj.pLDPCMessageLength/obj.pLDPCCodewordLength, ...
                        obj.pFullInputBufferLength - obj.pLDPCCodewordLength, ...
                        obj.pFullInputBufferLength, obj.pLDPCMaxIterations, ...
                        nnz(S.H));
                end
            end
            if strcmp(obj.ChannelCoding, "TPC")
                syncLen = length(obj.pASM)*obj.HasASM;
                blocksPerTF = localPositiveInteger(obj.TPCBlocksPerTF, 1);
                obj.pFullInputBufferLength = 64*64*blocksPerTF + syncLen;
                obj.pFrameLength = obj.pFullInputBufferLength;
                payloadBits = localTPCPayloadBits(obj.TPCCodeRate);
                knownZeroBits = 57*57-payloadBits;
                fprintf(['[TPC setup] k=%d, n=%d, rate=%.6f, ', ...
                    'blocksPerTF=%d, syncLen=%d, fullFrame=%d, ', ...
                    'knownZeroConstraint=%d (%d bits/codeword), decoder=%s\n'], ...
                    payloadBits, 64*64, ...
                    localTPCEffectiveRate(obj.TPCCodeRate), blocksPerTF, ...
                    syncLen, obj.pFullInputBufferLength, ...
                    logical(obj.TPCUseKnownZeroConstraint) && ...
                    knownZeroBits > 0, knownZeroBits, ...
                    char(string(obj.TPCDecoderMode)));
            end
        end



        function y = stepImpl(obj,llr)
            % Implement algorithm. Calculate y as a function of input u and
            % discrete states.

            randomizerEnabled = obj.RandomizerEnabled;
            obj.pDecodedFrameStartBits = zeros(0,1);
            inputStartBit = obj.pInputBitsSeen - numel(obj.pInputBuffer) + 1;
            nextInputBitsSeen = obj.pInputBitsSeen + numel(llr);
            if strcmpi(obj.DataPathMode, 'dualIQ')
                error('HelperCCSDSTMDecoder:SplitNotImplemented', ...
                    ['DataPathMode="dualIQ" must be deinterleaved by the ' ...
                     'top-level receiver before calling this single-stream decoder.']);
            end

            if isempty(llr)
                y = zeros(0, 1, 'int8');
                return;
            end

            if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)') && contains(string(obj.Modulation),'APSK')
                llrCol = llr(:);
                llr_stats = [min(llrCol), max(llrCol), mean(llrCol), std(llrCol)];
                hardBits = int8(llrCol > 0);
                fprintf('[APSK decode entry] llr len=%d, [min max mean std]=[%.2f %.2f %.3f %.3f]\n', ...
                    length(llrCol), llr_stats);
                fprintf('[APSK decode entry] hard bits first 32 = %s\n', ...
                    mat2str(hardBits(1:min(32,end)).'));
                assignin('base','debug_apsk_decoder_llr', llrCol(1:min(1000,end)));

                if obj.HasASM && ~isempty(obj.pRotatedASM)
                    searchLimit = min(length(llrCol), obj.pFullInputBufferLength);
                    bestErr = inf;
                    bestPos = 0;
                    bestPhase = 0;
                    for iPhase = 1:size(obj.pRotatedASM,2)
                        syncBits = int8(obj.pRotatedASM(:,iPhase) > 0);
                        syncLen = length(syncBits);
                        maxStart = searchLimit - syncLen + 1;
                        if maxStart > 0
                            for iPos = 1:maxStart
                                errNow = nnz(hardBits(iPos:iPos+syncLen-1) ~= syncBits);
                                if errNow < bestErr
                                    bestErr = errNow;
                                    bestPos = iPos;
                                    bestPhase = iPhase;
                                end
                            end
                        end
                    end
                    fprintf('[APSK decode entry] ASM hard-scan bestPos=%d, bestErr=%d, phase=%d, searchLimit=%d\n', ...
                        bestPos, bestErr, bestPhase, searchLimit);
                end
            end

%             if obj.HasASM
%                 asmlen = length(obj.pASM);
%                 % Frame synchronization
%                 [frames, syncLostFlag] = frameSynchronize(obj, llr);
%             else
%                 asmlen = 0;
%                 [frames,obj.pInputBuffer] = buffer([obj.pInputBuffer;llr], obj.pFullInputBufferLength); % When ASM is not there, then it is assumed that frame sync is done through other mechanisms
%                 syncLostFlag = false;
%             end
            if obj.HasASM
                asmlen = length(obj.pASM);
            else
                asmlen = 0;
            end

            isGMSKModulation = strcmpi(string(obj.Modulation), "GMSK");
            isRawASMBlockCode = any(strcmpi(string(obj.ChannelCoding), ...
                ["LDPC", "turbo"]));
            % Uncoded ordinary TM still carries a raw ASM once per transfer
            % frame.  Use the same multi-frame periodic evidence as the
            % block-code paths; otherwise a strong payload correlation in a
            % single frame can steal acquisition even after the top-level
            % APSK phase search found the correct rotation.
            isRawASMUncoded = strcmpi(string(obj.ChannelCoding), "none") && ...
                ~isGMSKModulation;
            usePeriodicASMSync = strcmpi(string(obj.ChannelCoding), "TPC") || ...
                (isRawASMBlockCode && ~isGMSKModulation) || ...
                isRawASMUncoded || ...
                (strcmp(obj.ChannelCoding, "RS") && contains(string(obj.Modulation), "APSK"));
            if obj.HasASM && usePeriodicASMSync
                syncInput = [obj.pInputBuffer; llr(:)];
                asmBits = int8(obj.pASM(:) ~= 0);
                searchLimit = min(obj.pFullInputBufferLength, numel(syncInput) - asmlen + 1);
                bestPos = 1;
                bestErr = asmlen + 1;
                bestMeanErr = inf;
                bestFrames = 0;
                bestPolarity = 1;

                if searchLimit > 0
                    for polarity = [1 -1]
                        hardBits = int8((polarity * syncInput(:)) > 0);
                        for iPos = 1:searchLimit
                            errNow = nnz(hardBits(iPos:iPos+asmlen-1) ~= asmBits);
                            errsPeriodic = errNow;
                            nPeriodic = 1;
                            nextPos = iPos + obj.pFullInputBufferLength;
                            while nextPos + asmlen - 1 <= numel(hardBits) && nPeriodic < 8
                                errsPeriodic(end+1,1) = nnz(hardBits(nextPos:nextPos+asmlen-1) ~= asmBits); %#ok<AGROW>
                                nPeriodic = nPeriodic + 1;
                                nextPos = nextPos + obj.pFullInputBufferLength;
                            end
                            meanErr = mean(errsPeriodic);
                            if meanErr < bestMeanErr || ...
                                    (abs(meanErr - bestMeanErr) < 1e-12 && errNow < bestErr)
                                bestMeanErr = meanErr;
                                bestErr = errNow;
                                bestPos = iPos;
                                bestFrames = nPeriodic;
                                bestPolarity = polarity;
                            end
                        end
                    end
                end

                periodicSyncAccepted = searchLimit > 0 && ...
                    bestFrames >= 2 && bestMeanErr <= asmlen/2;
                if periodicSyncAccepted
                    syncInput = syncInput(bestPos:end);
                    inputStartBit = inputStartBit + bestPos - 1;
                end
                if bestPolarity < 0
                    syncInput = -syncInput;
                end

                [frames, obj.pInputBuffer] = buffer(syncInput, obj.pFullInputBufferLength);
                frameStartBits = inputStartBit + ...
                    (0:size(frames,2)-1).' * obj.pFullInputBufferLength;
                syncLostFlag = false;

                % Export the same per-frame ASM evidence that a hardware
                % lock lamp would consume.  This monitor is deliberately
                % side-band: it does not gate or realign decoder output.
                selectedASMLength = numel(obj.pASM);
                maxASMErrors = min(max(0,round(double( ...
                    obj.FrameSyncASMErrorThreshold))), ...
                    floor(selectedASMLength/2));
                minimumCorrelation = 1 - ...
                    2*maxASMErrors/max(selectedASMLength,1);
                for iSyncObservation = 1:size(frames,2)
                    bestFrameCorrelation = -inf;
                    bestFramePhase = 1;
                    for iSyncPhase = 1:size(obj.pRotatedASM,2)
                        marker = double(sign( ...
                            obj.pRotatedASM(:,iSyncPhase)));
                        marker(marker == 0) = 1;
                        markerLength = min(numel(marker),size(frames,1));
                        sample = double(frames(1:markerLength, ...
                            iSyncObservation));
                        frameCorrelation = sum( ...
                            marker(1:markerLength).*sample(:)) / ...
                            (sum(abs(sample(:)))+eps);
                        if frameCorrelation > bestFrameCorrelation
                            bestFrameCorrelation = frameCorrelation;
                            bestFramePhase = iSyncPhase;
                        end
                    end
                    evidenceAccepted = periodicSyncAccepted && ...
                        isfinite(bestFrameCorrelation) && ...
                        bestFrameCorrelation >= minimumCorrelation;
                    updateFrameSyncMonitorState(obj,evidenceAccepted);
                    recordFrameSyncObservation(obj,evidenceAccepted, ...
                        false,bestFrameCorrelation,minimumCorrelation, ...
                        1,bestFramePhase,'periodic-raw-asm');
                end

                if strcmp(obj.ChannelCoding, "TPC") && evalin('base','exist(''debugTPC_encodedBits'',''var'')')
                    fprintf('[TPC DEBUG] decoder ASM sync pos=%d err=%d mean=%.2f frames=%d, polarity=%+d, outFrames=%d\n', ...
                        bestPos, bestErr, bestMeanErr, bestFrames, bestPolarity, size(frames,2));
                elseif strcmp(obj.ChannelCoding, "RS") && ...
                        evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
                    fprintf('[APSK RS sync] pos=%d err=%d mean=%.2f frames=%d, polarity=%+d, outFrames=%d\n', ...
                        bestPos, bestErr, bestMeanErr, bestFrames, bestPolarity, size(frames,2));
                elseif isRawASMUncoded && ...
                        evalin('base','exist(''debugCodedBoundaryEnabled'',''var'') && logical(debugCodedBoundaryEnabled)')
                    fprintf(['[TM uncoded ASM sync] pos=%d err=%d mean=%.2f ', ...
                        'frames=%d polarity=%+d accepted=%d outFrames=%d\n'], ...
                        bestPos, bestErr, bestMeanErr, bestFrames, ...
                        bestPolarity, periodicSyncAccepted, size(frames,2));
                end
            elseif obj.HasASM && obj.DisableFrameSynchronization
                [frames, obj.pInputBuffer] = buffer([obj.pInputBuffer; llr], obj.pFullInputBufferLength);
                frameStartBits = inputStartBit + ...
                    (0:size(frames,2)-1).' * obj.pFullInputBufferLength;
                syncLostFlag = false;
                % An upstream stage established the boundary.  Do not
                % fabricate per-frame ASM observations here; that stage
                % must explicitly export its own telemetry.
            elseif obj.HasASM
                [frames, syncLostFlag,~,~,frameStartBits] = ...
                    frameSynchronize(obj, llr, inputStartBit);
            else
                [frames, obj.pInputBuffer] = buffer([obj.pInputBuffer; llr], obj.pFullInputBufferLength);
                frameStartBits = inputStartBit + ...
                    (0:size(frames,2)-1).' * obj.pFullInputBufferLength;
                syncLostFlag = false;


            end


            obj.pInputBitsSeen = nextInputBitsSeen;
            obj.pPendingFrameStartBits = [obj.pPendingFrameStartBits; frameStartBits];
            n = 0;
            if any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'}))
                u = frames;
            else
                % [tu,obj.pInputBuffer] = buffer([obj.pInputBuffer;frames],obj.pPRNSequenceLength+asmlen);
                % n = size(tu,2);
                n = size(frames,2);
                u = frames(asmlen+1:end,:);
            end

            if syncLostFlag
                y = zeros(obj.pTFLen*8, 1, 'int8');
                % valid = false;
            else
                if ~isempty(u)
                    switch(obj.ChannelCoding)
                        case "none"
                            if n % For non zero value of n
                                if isGMSKModulation
                                    hardU = int8(u < 0);
                                else
                                    hardU = int8(u > 0);
                                end
%                                 if obj.RandomizerEnabled
                                if randomizerEnabled
                                    tempy = bitxor(hardU,obj.pPRNSequence);
                                    y = tempy(:);
                                else
                                    y = hardU(:);
                                end
                                % valid = true;
                            else
                                y = zeros(obj.pTFLen*8, 1, 'int8');
                                % valid = false;
                            end
                        case "RS"
                            if n % For non zero value of n
                                if isGMSKModulation
                                    hardU = int8(u < 0);
                                else
                                    hardU = int8(u > 0);
                                end
                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                                    derandom = logical(bitxor(hardU,obj.pPRNSequence));
                                else
                                    derandom = logical(hardU);
                                end
                                tfl = obj.pTFLen*8;
                                y = zeros(n*tfl, 1, 'int8');
                                for iWord = 1:n
                                    decodedWord = ccsdsRSDecode(derandom(:,iWord),obj.RSMessageLength,obj.RSInterleavingDepth,obj.RSShortenedMessageLength);
                                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                                        decodedWord = bitxor(int8(decodedWord), obj.pPRNSequence(1:tfl));
                                    end
                                    y((iWord-1)*tfl+1:iWord*tfl) = decodedWord;
                                end
                                % valid = true;
                            else
                                y = zeros(obj.pTFLen*8, 1, 'int8');
                                % valid = false;
                            end
                        case "convolutional"
                            % Canonical official GMSK is positive=bit0;
                            % the generic soft-input Viterbi path below is
                            % positive=bit1. Convert once at this FEC
                            % boundary, independent of received frame data.
                            if isGMSKModulation
                                u = -u;
                            end
                            if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                               if strcmpi(obj.DataPathMode, 'single')

                                   encodedASMLength = localEncodedASMLength( ...
                                       obj.ChannelCoding, asmlen, obj.pInverseCodeRate);

                                   % 注意：
                                   % 对卷积码，obj.pFrameLength 是 ASM 搜索用长度，
                                   % 不是完整 coded frame 长度。
                                   % afterEncoding randomization must be undone over the full coded frame.
                                   % 所以这里要用 size(u,1)。
                                   codedFrameLength = size(u, 1);

                                   u = localFrameSoftPayloadFlip( ...
                                       u, codedFrameLength, encodedASMLength, []);

                               elseif strcmpi(obj.DataPathMode, 'dualIQ')

                                   error('HelperCCSDSTMDecoder:SplitNotImplemented', ...
                                       'DataPathMode="dualIQ" must be deinterleaved before decoding.');

                               end
                            end
                            peakValue = max(abs(u(:)));
                            if isempty(peakValue) || ~isfinite(peakValue) || ...
                                    peakValue <= 0
                                % A rejected/erased official GMSK frame is
                                % represented by zero soft values. Feed a
                                % neutral quantizer level instead of making
                                % uencode throw before the next phase/frame
                                % candidate can be evaluated.
                                peakValue = eps;
                            end
                            quantized = uencode(u,obj.ViterbiWordLength, ...
                                peakValue,'unsigned');
                            % [vitin,obj.pInputBuffer] = buffer([obj.pInputBuffer;quantized], log2(obj.pDec.TrellisStructure.numOutputSymbols));
                            decoded = obj.pDec(quantized(:));
                            if obj.pFirstTimeStepCalling
                                tdecoded = decoded(obj.ViterbiTraceBackDepth+1:end);
                                obj.pFirstTimeStepCalling = false;
                            else
                                tdecoded = decoded;
                            end
                            if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                                [tdecoded, obj.pDifferentialDecoderBit] = localPCMHardDifferentialDecode( ...
                                    tdecoded, obj.pDifferentialDecoderBit, obj.PCMFormat);
                                if obj.DebugPCMFormat
                                    localPCMPrintDecodedDebug(obj, tdecoded, 'convolutional');
                                end
                            end
%                             [ty,obj.pOutputBuffer] = buffer([obj.pOutputBuffer;tdecoded],obj.pPRNSequenceLength+asmlen);
%                             n = size(ty,2);
%                             if n
%                                 tempy = ty(asmlen+1:end, :);
%                                 if obj.RandomizerEnabled
%                                     derandom = bitxor(int8(tempy),obj.pPRNSequence);
%                                     y = derandom(:);
%                                 else
%                                     y = int8(tempy(:));
%                                 end
%                                 % valid = true;
%                             else
%                                 y = zeros(obj.pTFLen*8, 1, 'int8');
%                                 % valid = false;
%                             end
                            [ty,obj.pOutputBuffer] = buffer([obj.pOutputBuffer;tdecoded], ...
                                obj.pPRNSequenceLength+asmlen);

                            n = size(ty,2);

                            if n
                                tempy = ty(asmlen+1:end, :);
                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                                    derandom = bitxor(int8(tempy),obj.pPRNSequence);
                                    y = derandom(:);
                                else
                                    y = int8(tempy(:));
                                end
                            else
                                y = zeros(obj.pTFLen*8, 1, 'int8');
                            end
                        case "concatenated"
                            if isGMSKModulation
                                u = -u;
                            end
                            if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                                 if strcmpi(obj.DataPathMode, 'single')

                                     encodedASMLength = localEncodedASMLength( ...
                                         obj.ChannelCoding, asmlen, obj.pInverseCodeRate);

                                     codedFrameLength = size(u, 1);

                                     u = localFrameSoftPayloadFlip( ...
                                         u, codedFrameLength, encodedASMLength, []);

                                 elseif strcmpi(obj.DataPathMode, 'dualIQ')

                                     error('HelperCCSDSTMDecoder:SplitNotImplemented', ...
                                         'DataPathMode="dualIQ" must be deinterleaved before decoding.');

                                 end
                            end
                            peakValue = max(abs(u(:)));
                            if isempty(peakValue) || ~isfinite(peakValue) || ...
                                    peakValue <= 0
                                peakValue = eps;
                            end
                            quantized = uencode(u,obj.ViterbiWordLength, ...
                                peakValue,'unsigned');
                            % [vitin,obj.pInputBuffer] = buffer([obj.pInputBuffer;quantized], log2(obj.pDec.TrellisStructure.numOutputSymbols));
                            decoded = obj.pDec(quantized(:));
                            if obj.pFirstTimeStepCalling
                                tdecoded = decoded(obj.ViterbiTraceBackDepth+1:end);
                                obj.pFirstTimeStepCalling = false;
                            else
                                tdecoded = decoded;
                            end
                            if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                                [tdecoded, obj.pDifferentialDecoderBit] = localPCMHardDifferentialDecode( ...
                                    tdecoded, obj.pDifferentialDecoderBit, obj.PCMFormat);
                                if obj.DebugPCMFormat
                                    localPCMPrintDecodedDebug(obj, tdecoded, 'concatenated');
                                end
                            end
                            [ty,obj.pOutputBuffer] = buffer([obj.pOutputBuffer;tdecoded],obj.pPRNSequenceLength+asmlen);
                            n = size(ty,2);
                            if n
                                viterbiDecoded = logical(ty(asmlen+1:end, :)); % By this time, frame synchronization is complete. Hence, ASM can be discarded
                                derandom = viterbiDecoded;
                                tfl = obj.pTFLen*8;
                                y = zeros(n*tfl, 1, 'int8');
                                for iWord = 1:n
                                    decodedWord = ccsdsRSDecode(derandom(:,iWord),obj.RSMessageLength,obj.RSInterleavingDepth,obj.RSShortenedMessageLength);
                                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                                        decodedWord = bitxor(int8(decodedWord), obj.pPRNSequence(1:tfl));
                                    end
                                    y((iWord-1)*tfl+1:iWord*tfl) = decodedWord;
                                end
                                % valid = true;
                            else
                                y = zeros(obj.pTFLen*8, 1, 'int8');
                                % valid = false;
                            end
                        case "turbo"
                            if obj.DebugTurbo
                                fprintf('[Turbo step] frames=%dx%d, syncLen=%d, cwLen=%d, msgLen=%d\n', ...
                                    size(frames,1), size(frames,2), ...
                                    length(obj.pASM)*obj.HasASM, ...
                                    obj.pTurboCodewordLength, obj.pTurboMessageLength);
                            end

                            if n
                                cwSoft = u(1:obj.pTurboCodewordLength, :);
                                numWords = size(cwSoft, 2);
                                y = zeros(obj.pTurboMessageLength*numWords, 1, 'int8');

                                for iWord = 1:numWords
                                    llr = double(cwSoft(:, iWord));
                                    if strcmpi(string(obj.Modulation), "GMSK")
                                        % Official GMSK soft metrics use
                                        % positive for bit 0. The Turbo
                                        % decoder input convention used by
                                        % the generic TM chain is opposite,
                                        % so invert after applying a uniform
                                        % hard-decision confidence.
                                        llrHard = 5 * sign(llr);
                                        llrHard(llr == 0) = 0;
                                        llr = -llrHard;
                                    end

                                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                                        basePRN = obj.pPRNSequence(:);
                                        repNum = ceil(obj.pTurboCodewordLength / length(basePRN));
                                        prn = repmat(basePRN, repNum, 1);
                                        prn = prn(1:obj.pTurboCodewordLength);
                                        llr(logical(prn)) = -llr(logical(prn));
                                    end

                                    reset(obj.pTurboDecoder);
                                    msg = obj.pTurboDecoder(llr);
                                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                                        msg = bitxor(int8(msg(:)), obj.pPRNSequence(1:obj.pTurboMessageLength));
                                    end
                                    y((iWord-1)*obj.pTurboMessageLength+1:iWord*obj.pTurboMessageLength) = int8(msg(:));
                                end
                            else
                                y = zeros(obj.pTFLen*8, 1, 'int8');
                            end

                        case "LDPC"
                            % frames 是已经 frameSynchronize 后的一帧或多帧 soft coded frame
                            % 如果 HasASM=true，前 32 bits 是 ASM，后面是 LDPC codeword
                            if obj.DebugLDPC
                                fprintf('[LDPC step] frames=%dx%d, syncLen=%d, cwLen=%d, msgLen=%d\n', ...
                                    size(frames,1), size(frames,2), ...
                                    length(obj.pASM)*obj.HasASM, ...
                                    obj.pLDPCCodewordLength, obj.pLDPCMessageLength);
                            end
                            if obj.HasASM
                                cwSoft = frames(length(obj.pASM)+1:end, :);
                            else
                                cwSoft = frames;
                            end

                            % 只取 LDPC codeword 长度，避免 buffer 多余
                            cwSoft = cwSoft(1:obj.pLDPCCodewordLength, :);

                            numWords = size(cwSoft, 2);
                            y = zeros(obj.pLDPCMessageLength*numWords, 1, 'int8');

                            for iWord = 1:numWords
                                llrIn = double(cwSoft(:,iWord));

                                % ldpcDecode expects bit 0 positive and bit 1
                                % negative.  The official GMSK entry already
                                % uses that convention; the generic TM
                                % demodulator uses the opposite convention.
                                if strcmpi(string(obj.Modulation), "GMSK")
                                    llr = llrIn;
                                else
                                    llr = -llrIn;
                                end

                                % 如果启用了 randomizer：
                                % 发送端是对 LDPC codeword bits 做 XOR；
                                % 接收端对 soft LLR 的处理就是 PRN=1 的位置翻号。
                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                                    prn = obj.pPRNSequence(1:obj.pLDPCCodewordLength);
                                    llr(logical(prn)) = -llr(logical(prn));
                                end

                                % CCSDS AR4JA rate-1/2 transmits only the
                                % first 4M variables.  The final M variables
                                % belong to the standard sparse graph but are
                                % punctured, so their channel LLR is exactly
                                % zero (unknown) at the decoder input.
                                if obj.pLDPCPuncturedLength > 0
                                    llr = [llr; ...
                                        zeros(obj.pLDPCPuncturedLength, 1)]; %#ok<AGROW>
                                end

                                decWhole = ldpcDecode(llr, obj.pLDPCDecoderCfg, ...
                                    obj.pLDPCMaxIterations, 'OutputFormat','whole');

                                msg = int8(decWhole(1:obj.pLDPCMessageLength));
                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                                    msg = bitxor(msg, obj.pPRNSequence(1:obj.pLDPCMessageLength));
                                end

                                y((iWord-1)*obj.pLDPCMessageLength+1:iWord*obj.pLDPCMessageLength) = msg(:);
                            end
                        case "TPC"
                            codeLen = 64*64;
                            infoLen = localTPCPayloadBits(obj.TPCCodeRate);
                            if n
                                tpcSoft = u;
                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                                    % TX randomizes every coded TPC payload
                                    % after its raw ASM. Undo the same PRN on
                                    % aligned soft frames before decoding.
                                    tpcSoft = localSoftXorByPRN(tpcSoft, ...
                                        size(tpcSoft, 1), obj.pPRNSequence);
                                end
                                usableLen = floor(numel(tpcSoft) / codeLen) * codeLen;
                                cwSoft = reshape(tpcSoft(1:usableLen), codeLen, []);

                                % The periodic raw-ASM synchronizer above
                                % already resolves the detector polarity for
                                % every TPC modulation and normalizes u to the
                                % generic TM convention (positive = bit 1).
                                % Do not invert GMSK again here: doing so
                                % turns an error-free GMSK TPC codeword into
                                % its complement before product decoding.
                                numWords = size(cwSoft, 2);
                                y = zeros(infoLen*numWords, 1, 'int8');

                                for iWord = 1:numWords
                                    if evalin('base','exist(''debugTPC_encodedBits'',''var'')') && iWord <= 3
                                        txEncDbg = evalin('base','debugTPC_encodedBits');
                                        localTPCDecoderBoundaryDebug(cwSoft(:,iWord), txEncDbg, ...
                                            length(obj.pASM)*obj.HasASM, codeLen, iWord, ...
                                            localPositiveInteger(obj.TPCBlocksPerTF, 1), bestPos);
                                    end
                                    [msg, ~] = ccsdsTPCDecodeSoft(cwSoft(:,iWord), ...
                                        'TPCCodeRate', obj.TPCCodeRate, ...
                                        'TPCInterleaver', obj.TPCInterleaver, ...
                                        'UseKnownZeroConstraint', ...
                                        obj.TPCUseKnownZeroConstraint, ...
                                        'DecoderMode', obj.TPCDecoderMode);
                                    y((iWord-1)*infoLen+1:iWord*infoLen) = msg(:);
                                end

                                if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding') && ~isempty(y)
                                    prn = repmat(obj.pPRNSequence, ceil(numel(y)/numel(obj.pPRNSequence)), 1);
                                    y = bitxor(y, prn(1:numel(y)));
                                end
                            else
                                y = zeros(0, 1, 'int8');
                            end
                    end

                else
                    y = zeros(0, 1, 'int8');
                end
            end
            numDecoded = floor(numel(y)/(obj.pTFLen*8));
            obj.pDecodedFrameStartBits = nan(numDecoded,1);
            if ~syncLostFlag && ~isempty(u) && n>0 && ...
                    numDecoded<=numel(obj.pPendingFrameStartBits)
                obj.pDecodedFrameStartBits = obj.pPendingFrameStartBits(1:numDecoded);
                obj.pPendingFrameStartBits(1:numDecoded) = [];
            end
        end

        function [v, syncFailed, pos, PhaseIndex, frameStartBits] = ...
                frameSynchronize(obj,u,inputStartBit)
            % Do frame synchronization and phase ambiguity resolution

            [frames, obj.pInputBuffer] = buffer([obj.pInputBuffer;u], obj.pFullInputBufferLength);
            frameStartBits = inputStartBit + ...
                (0:size(frames,2)-1).' * obj.pFullInputBufferLength;
            pos = 1; PhaseIndex = 1;
            n = size(frames, 2);
            v = zeros(obj.pFullInputBufferLength, n);
            validOutput = false(1, n);
            syncFailed = true;
            debugCodedBoundary = evalin('base','exist(''debugCodedBoundaryEnabled'',''var'') && logical(debugCodedBoundaryEnabled)');
            if debugCodedBoundary && n == 0 && localShouldPrintCodedFrameSyncDebug()
                fprintf('[Coded DEBUG] decoder frameSync no full frame yet: inputLen=%d, buffered=%d, frameLen=%d\n', ...
                    numel(u), numel(obj.pInputBuffer), obj.pFullInputBufferLength);
            end
            numPhases = size(obj.pRotatedASM, 2);
            periodicFrameCount = 1;
            usePeriodicCodedASM = obj.UsePeriodicCodedASMSync && ...
                any(strcmp(obj.ChannelCoding, {'convolutional','concatenated'})) && ...
                n >= 3;
            periodicPeakPos = zeros(numPhases, 1);
            periodicMaxCorrValues = zeros(numPhases, 1);
            if usePeriodicCodedASM
                periodicFrameCount = min( ...
                    max(3, round(double(obj.CodedASMPeriodicFrames))), n);
                for iPhase = 1:numPhases
                    si = obj.pRotatedASM(:, iPhase); % Take the ASM corresponding to that particular rotation of phase ambiguity.
                    % Every coded TM frame contains an ASM at the same
                    % offset. Score a candidate at that offset across
                    % several complete frames so that an isolated payload
                    % correlation peak cannot steal lock from the true,
                    % periodically repeating ASM.
                    [periodicPeakPos(iPhase), periodicMaxCorrValues(iPhase)] = ...
                        FrameCorrelatePeriodic(obj, ...
                        frames(:,1:periodicFrameCount), si);
                end
            end
            for iFrame = 1:n % For non-zero value of n
                printFrameSyncDebug = debugCodedBoundary && localShouldPrintCodedFrameSyncDebug();
                if usePeriodicCodedASM
                    peakpos = periodicPeakPos;
                    maxCorrValues = periodicMaxCorrValues;
                else
                    maxCorrValues = zeros(numPhases, 1);
                    peakpos = zeros(numPhases, 1);
                    for iPhase = 1:numPhases
                        si = obj.pRotatedASM(:, iPhase); % Take the ASM corresponding to that particular rotation of phase ambiguity.
                        [peakpos(iPhase), maxCorrValues(iPhase)] = ...
                            FrameCorrelate(obj, frames(:,iFrame), si); % This is as per section
                    end
                end
                [~,PhaseIndex] = max(maxCorrValues);
                pos = peakpos(PhaseIndex);
                rawPos = pos;
                if printFrameSyncDebug
                    nShow = min(8, numel(maxCorrValues));
                    fprintf('[Coded DEBUG] decoder frameSync frame=%d/%d rawPos=%d phase=%d maxCorr=%.4g frameLen=%d searchLen=%d asmOffset=%d templates=%d periodicFrames=%d\n', ...
                        iFrame, n, rawPos, PhaseIndex, maxCorrValues(PhaseIndex), ...
                        obj.pFullInputBufferLength, obj.pFrameLength, obj.pASMOffsetLength, ...
                        numPhases, periodicFrameCount);
                    fprintf('[Coded DEBUG] decoder phase peaks pos=%s corr=%s\n', ...
                        mat2str(peakpos(1:nShow).'), mat2str(maxCorrValues(1:nShow).', 4));
                end
                if any(strcmp(obj.ChannelCoding, {'convolutional','concatenated'}))
                    % The convolutional ASM templates drop the unstable
                    % first coded ASM bits. A peak inside that dropped
                    % prefix still means the coded frame begins at sample 1.
                    pos = max(1, pos - obj.pASMOffsetLength);
                    if obj.CodedSyncOffset ~= 0
                        pos = max(1, pos + round(double(obj.CodedSyncOffset)));
                    end
                end
                if printFrameSyncDebug && pos ~= rawPos
                    fprintf('[Coded DEBUG] decoder frameSync adjustedPos=%d from rawPos=%d codedOffset=%d CodedSyncOffset=%d\n', ...
                        pos, rawPos, obj.pASMOffsetLength, obj.CodedSyncOffset);
                end

                % Reject weak payload correlations before they can trigger
                % a destructive frame-buffer realignment.  While locked,
                % tolerate the configured number of consecutive weak ASM
                % observations and keep the last phase (holdover).
                selectedCorrelation = maxCorrValues(PhaseIndex);
                selectedASMLength = numel(obj.pRotatedASM(:,PhaseIndex));
                maxASMErrors = min(max(0, round(double( ...
                    obj.FrameSyncASMErrorThreshold))), ...
                    floor(selectedASMLength/2));
                minimumCorrelation = 1 - 2*maxASMErrors/selectedASMLength;
                slipTolerance = max(0, round(double( ...
                    obj.FrameSyncBitSlipTolerance)));
                correlationAccepted = isfinite(selectedCorrelation) && ...
                    selectedCorrelation >= minimumCorrelation;
                if obj.pFrameSyncLocked && abs(pos-1) > slipTolerance
                    correlationAccepted = false;
                end

                holdoverUsed = false;
                if correlationAccepted
                    obj.pFrameSyncGoodCount = obj.pFrameSyncGoodCount + 1;
                    obj.pFrameSyncBadCount = 0;
                    obj.pFrameSyncLastPhase = PhaseIndex;
                    if obj.pFrameSyncGoodCount >= max(1, round(double( ...
                            obj.FrameSyncLockThreshold)))
                        obj.pFrameSyncLocked = true;
                    end
                else
                    obj.pFrameSyncGoodCount = 0;
                    obj.pFrameSyncBadCount = obj.pFrameSyncBadCount + 1;
                    unlockThreshold = max(1, round(double( ...
                        obj.FrameSyncUnlockThreshold)));
                    if obj.pFrameSyncLocked && ...
                            obj.pFrameSyncBadCount < unlockThreshold
                        pos = 1;
                        PhaseIndex = obj.pFrameSyncLastPhase;
                        holdoverUsed = true;
                        if printFrameSyncDebug
                            fprintf(['[Coded DEBUG] decoder ASM holdover ', ...
                                'corr=%.4f threshold=%.4f bad=%d/%d\n'], ...
                                selectedCorrelation, minimumCorrelation, ...
                                obj.pFrameSyncBadCount, unlockThreshold);
                        end
                    else
                        obj.pFrameSyncLocked = false;
                        syncFailed = true;
                        recordFrameSyncObservation(obj,false,false, ...
                            selectedCorrelation,minimumCorrelation, ...
                            rawPos,PhaseIndex, ...
                            'decoder-soft-asm-correlator');
                        if printFrameSyncDebug
                            fprintf(['[Coded DEBUG] decoder ASM rejected ', ...
                                'corr=%.4f threshold=%.4f pos=%d\n'], ...
                                selectedCorrelation, minimumCorrelation, pos);
                        end
                        % During acquisition, a filter/transient-damaged
                        % first frame must not prevent later complete frame
                        % columns in this same call from acquiring lock.
                        continue;
                    end
                end

                recordFrameSyncObservation(obj,correlationAccepted, ...
                    holdoverUsed,selectedCorrelation,minimumCorrelation, ...
                    rawPos,PhaseIndex,'decoder-soft-asm-correlator');

                % Resolve phase ambiguity
                if any(strcmp(obj.Modulation,{'QPSK','OQPSK'}))
                    basePhaseIndex = mod(PhaseIndex-1, 4) + 1;
                    if basePhaseIndex == 1
                        derotated = frames(:,iFrame);
                    elseif basePhaseIndex == 2
                        reshapredFrame = reshape(frames(:,iFrame),2,[]);
                        temp = [reshapredFrame(2,:); -1*reshapredFrame(1,:)];
                        derotated = temp(:);
                    elseif basePhaseIndex == 3
                        derotated = -1*frames(:,iFrame);
                    elseif basePhaseIndex == 4
                        reshapredFrame = reshape(frames(:,iFrame),2,[]);
                        temp = [-1*reshapredFrame(2,:); reshapredFrame(1,:)];
                        derotated = temp(:);
                    end
                elseif strcmp(obj.Modulation,["BPSK", "GMSK"])
                    if mod(PhaseIndex, 2) == 1
                        derotated = frames(:,iFrame);
                    else
                        derotated = -1*frames(:,iFrame);
                    end
                else % Do not do phase ambiguity resolution
                    derotated = frames(:,iFrame);
                end

                if pos == 1
                    syncFailed = false;
                    v(:,iFrame) = derotated;
                    validOutput(iFrame) = true;
                else
                    tempInputBuffer = obj.pInputBuffer;
                    resetImpl(obj);
                    realignedStart = inputStartBit + ...
                        (iFrame-1)*obj.pFullInputBufferLength + pos - 1;
                    if strcmpi(string(obj.Modulation), "GMSK") && strcmpi(string(obj.ChannelCoding), "turbo")
                        tempFrames = [reshape(frames(:,iFrame:end),[],1); tempInputBuffer];
                        [newFrames, obj.pInputBuffer] = buffer(tempFrames(pos:end), obj.pFullInputBufferLength);
                        frameStartBits = realignedStart + ...
                            (0:size(newFrames,2)-1).' * obj.pFullInputBufferLength;
                        if isempty(newFrames)
                            syncFailed = true;
                            v = zeros(obj.pFullInputBufferLength, 0);
                        else
                            syncFailed = false;
                            if PhaseIndex == 2
                                v = -newFrames;
                            else
                                v = newFrames;
                            end
                        end
                        if printFrameSyncDebug
                            fprintf('[Coded DEBUG] decoder realign pos=%d phase=%d newFrames=%d buffered=%d syncFailed=%d\n', ...
                                pos, PhaseIndex, size(newFrames,2), numel(obj.pInputBuffer), syncFailed);
                        end
                        return;
                    end
                    syncFailed = true;
                    % Adjust the next frame accordingly
                    tempFrames = [reshape(frames(:,iFrame:end),[],1);tempInputBuffer];
                    [newFrames, obj.pInputBuffer] = buffer(tempFrames(pos:end), obj.pFullInputBufferLength);
                    frameStartBits = realignedStart + ...
                        (0:size(newFrames,2)-1).' * obj.pFullInputBufferLength;
                    if isempty(newFrames)
                        v = zeros(obj.pFullInputBufferLength, 0);
                    else
                        syncFailed = false;
                        v = applyPhaseAmbiguityToFrames(obj, newFrames, PhaseIndex);
                    end
                    if printFrameSyncDebug
                        fprintf('[Coded DEBUG] decoder realign pos=%d phase=%d newFrames=%d buffered=%d syncFailed=%d\n', ...
                            pos, PhaseIndex, size(newFrames,2), numel(obj.pInputBuffer), syncFailed);
                    end
                    return;
                end
            end

            % Take care of additional frames that might getting added when
            % sync is lost
            if size(frames,2)~=n
                obj.pInputBuffer = [reshape(frames(:,iFrame+1:end),[],1);obj.pInputBuffer];
            end

            if n > 0
                v = v(:,validOutput);
                frameStartBits = frameStartBits(validOutput);
                syncFailed = isempty(v);
            else
                syncFailed = true;
                v = zeros(obj.pFullInputBufferLength, 0);
                frameStartBits = zeros(0,1);
            end
        end

        function corrected = applyPhaseAmbiguityToFrames(obj, frames, PhaseIndex)
            if isempty(frames)
                corrected = frames;
                return;
            end

            if any(strcmp(obj.Modulation,{'QPSK','OQPSK'}))
                basePhaseIndex = mod(PhaseIndex-1, 4) + 1;
                if basePhaseIndex == 1
                    corrected = frames;
                elseif basePhaseIndex == 2
                    reshapedFrames = reshape(frames, 2, []);
                    temp = [reshapedFrames(2,:); -1*reshapedFrames(1,:)];
                    corrected = reshape(temp(:), size(frames));
                elseif basePhaseIndex == 3
                    corrected = -1*frames;
                elseif basePhaseIndex == 4
                    reshapedFrames = reshape(frames, 2, []);
                    temp = [-1*reshapedFrames(2,:); reshapedFrames(1,:)];
                    corrected = reshape(temp(:), size(frames));
                else
                    corrected = frames;
                end
            elseif strcmp(obj.Modulation,["BPSK", "GMSK"])
                if mod(PhaseIndex, 2) == 1
                    corrected = frames;
                else
                    corrected = -1*frames;
                end
            else
                corrected = frames;
            end
        end

        function [PeakPos, maxcorr] = FrameCorrelate(obj, demodData, syncMarker)
            % Use normalized soft correlation so true high-confidence ASM
            % peaks beat accidental hard-bit matches in payload data.
            syncSign = double(sign(syncMarker(:)));
            syncSign(syncSign == 0) = 1;

            F = min(obj.pFrameLength, numel(demodData));
            asmLen = numel(syncSign);
            maxPos = F - asmLen + 1;

            if maxPos < 1
                PeakPos = 1;
                maxcorr = -inf;
                return;
            end

            corrValue = -inf(maxPos, 1);
            for iBit = 1:maxPos
                yi = double(demodData(iBit:iBit+asmLen-1));
                corrValue(iBit) = sum(syncSign .* yi(:)) / (sum(abs(yi(:))) + eps);
            end

            [maxcorr, PeakPos] = max(corrValue);
        end

        function [PeakPos, maxcorr] = FrameCorrelatePeriodic(obj, demodFrames, syncMarker)
            % Score each possible coded-ASM position at the same offset in
            % multiple consecutive frame-length columns. A real ASM
            % repeats at the frame period; a payload false peak does not.
            syncSign = double(sign(syncMarker(:)));
            syncSign(syncSign == 0) = 1;

            F = min(obj.pFrameLength, size(demodFrames, 1));
            asmLen = numel(syncSign);
            maxPos = F - asmLen + 1;
            numFrames = size(demodFrames, 2);

            if maxPos < 1 || numFrames < 1
                PeakPos = 1;
                maxcorr = -inf;
                return;
            end

            corrPerFrame = zeros(maxPos, numFrames);
            numeratorKernel = flipud(syncSign);
            denominatorKernel = ones(asmLen, 1);
            for iFrame = 1:numFrames
                yi = double(demodFrames(1:F, iFrame));
                numerator = conv(yi, numeratorKernel, 'valid');
                denominator = conv(abs(yi), denominatorKernel, 'valid');
                corrPerFrame(:, iFrame) = numerator ./ (denominator + eps);
            end

            periodicScore = mean(corrPerFrame, 2);
            [maxcorr, PeakPos] = max(periodicScore);
        end

        function [PeakPos, minDist] = RawASMCorrelate(obj, decodedFrame, asmBits)
            % 在 Viterbi 后的 hard bits 中滑动寻找原始 ASM。
            % 类似 FrameCorrelate，但这里没有 soft value，所以用汉明距离。

            asmLen = length(asmBits);
            F = length(decodedFrame);

            maxPos = F - asmLen + 1;

            if maxPos < 1
                PeakPos = 1;
                minDist = inf;
                return;
            end

            dist = inf(maxPos, 1);

            for iBit = 1:maxPos
                yi = decodedFrame(iBit:iBit+asmLen-1);
                dist(iBit) = sum(yi ~= asmBits);
            end

            [minDist, PeakPos] = min(dist);
        end

        function syncASM = buildConvEncodedASMForSync(~, asmBits, trellis, puncturePattern, offsetLength, flipSecondBranch)
            % Build convolutionally encoded ASM template for coded-frame sync.
            %
            % Important:
            % Do NOT let comm.ConvolutionalEncoder apply puncturing here.
            % 32-bit ASM produces 64 mother-code bits. For 3/4, puncture pattern
            % length is 6, and 64 is not divisible by 6, so MATLAB will error.
            %
            % Instead:
            %   1. Generate mother rate-1/2 coded bits.
            %   2. Apply puncturing manually.
            %   3. Drop the first offsetLength coded bits.

            asmBits = int8(asmBits(:));

            % 1) Mother rate-1/2 convolutional encoding, no puncturing here.
            enc = comm.ConvolutionalEncoder('TrellisStructure', trellis);
            motherBits = enc(asmBits);

            % For 1/2 CCSDS case only, second branch is inverted.
            % For 3/4, flipSecondBranch should be false.
            if flipSecondBranch
                motherBits(2:2:end) = int8(~motherBits(2:2:end));
            end

            % 2) Manual puncturing.
            p = puncturePattern(:);
            pp = repmat(p, ceil(length(motherBits)/length(p)), 1);
            pp = pp(1:length(motherBits));

            codedASM = motherBits(logical(pp));

            % 3) Drop leading bits affected by convolutional encoder memory.
            offsetLength = min(offsetLength, length(codedASM)-1);
            syncASM = codedASM(offsetLength+1:end);
        end

        function updateFrameSyncMonitorState(obj,evidenceAccepted)
            % Apply the configured acquisition/loss hysteresis for paths
            % whose decoding is already aligned elsewhere.  The ordinary
            % soft-ASM correlator updates the same state inline because it
            % also uses HOLD to control decoder output.
            if evidenceAccepted
                obj.pFrameSyncGoodCount = obj.pFrameSyncGoodCount + 1;
                obj.pFrameSyncBadCount = 0;
                if obj.pFrameSyncGoodCount >= max(1,round(double( ...
                        obj.FrameSyncLockThreshold)))
                    obj.pFrameSyncLocked = true;
                end
            else
                obj.pFrameSyncGoodCount = 0;
                obj.pFrameSyncBadCount = obj.pFrameSyncBadCount + 1;
                if obj.pFrameSyncLocked && ...
                        obj.pFrameSyncBadCount >= max(1,round(double( ...
                        obj.FrameSyncUnlockThreshold)))
                    obj.pFrameSyncLocked = false;
                end
            end
        end

        function recordFrameSyncObservation(obj,accepted,holdover, ...
                correlation,minimumCorrelation,position,phaseIndex,source)
            observationIndex = numel(obj.pFrameSyncLockedTrace)+1;
            obj.pFrameSyncObservationIndex(end+1,1) = observationIndex;
            obj.pFrameSyncAcceptedTrace(end+1,1) = logical(accepted);
            obj.pFrameSyncLockedTrace(end+1,1) = ...
                logical(obj.pFrameSyncLocked);
            obj.pFrameSyncHoldoverTrace(end+1,1) = logical(holdover);
            obj.pFrameSyncCorrelationTrace(end+1,1) = correlation;
            obj.pFrameSyncThresholdTrace(end+1,1) = minimumCorrelation;
            obj.pFrameSyncPositionTrace(end+1,1) = position;
            obj.pFrameSyncPhaseTrace(end+1,1) = phaseIndex;
            if strcmp(obj.pFrameSyncTelemetrySource,'unavailable')
                obj.pFrameSyncTelemetrySource = char(source);
            elseif ~strcmp(obj.pFrameSyncTelemetrySource,char(source))
                obj.pFrameSyncTelemetrySource = 'mixed';
            end
        end

        function resetImpl(obj)
            % Initialize / reset discrete-state properties
            if ~isempty(obj.pDec)
                reset(obj.pDec);
            end
            if ~isempty(obj.pTurboDecoder)
                reset(obj.pTurboDecoder);
            end
%             reset(obj.pDec);
            obj.pFirstTimeStepCalling = true;
            obj.pInputBitsSeen = 0;
            obj.pPendingFrameStartBits = zeros(0,1);
            obj.pDecodedFrameStartBits = zeros(0,1);
            obj.pInputBuffer = [];
            obj.pOutputBuffer = [];
            obj.pDifferentialDecoderBit = 0;
            obj.pFrameSyncLocked = false;
            obj.pFrameSyncGoodCount = 0;
            obj.pFrameSyncBadCount = 0;
            obj.pFrameSyncLastPhase = 1;
            obj.pFrameSyncObservationIndex = zeros(0,1);
            obj.pFrameSyncAcceptedTrace = false(0,1);
            obj.pFrameSyncLockedTrace = false(0,1);
            obj.pFrameSyncHoldoverTrace = false(0,1);
            obj.pFrameSyncCorrelationTrace = zeros(0,1);
            obj.pFrameSyncThresholdTrace = zeros(0,1);
            obj.pFrameSyncPositionTrace = zeros(0,1);
            obj.pFrameSyncPhaseTrace = zeros(0,1);
            obj.pFrameSyncTelemetrySource = 'unavailable';
        end

        function releaseImpl(obj)
            % Release resources, such as file handles
            if ~isempty(obj.pDec)
                release(obj.pDec);
            end
            if ~isempty(obj.pTurboDecoder)
                release(obj.pTurboDecoder);
            end
        end

        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Set properties in structure s to values in object obj

            % Set public properties and states
            s = saveObjectImpl@satcom.internal.ccsds.tmBase(obj);
            s.RandomizerFECPosition = obj.RandomizerFECPosition;
            s.DataPathMode = obj.DataPathMode;
            s.ConvolutionalG1G2Mode = obj.ConvolutionalG1G2Mode;
            s.DebugLDPC = obj.DebugLDPC;
            s.LDPCMaxIterations = obj.LDPCMaxIterations;
            s.CodedSyncOffset = obj.CodedSyncOffset;
            s.UsePeriodicCodedASMSync = obj.UsePeriodicCodedASMSync;
            s.CodedASMPeriodicFrames = obj.CodedASMPeriodicFrames;
            s.FrameSyncBitSlipTolerance = obj.FrameSyncBitSlipTolerance;
            s.FrameSyncASMErrorThreshold = obj.FrameSyncASMErrorThreshold;
            s.FrameSyncLockThreshold = obj.FrameSyncLockThreshold;
            s.FrameSyncUnlockThreshold = obj.FrameSyncUnlockThreshold;
            s.TPCCodeRate = obj.TPCCodeRate;
            s.TPCBlocksPerTF = obj.TPCBlocksPerTF;
            s.TPCInterleaver = obj.TPCInterleaver;
            s.TPCUseKnownZeroConstraint = obj.TPCUseKnownZeroConstraint;
            s.TPCDecoderMode = obj.TPCDecoderMode;
            s.ViterbiTraceBackDepth = obj.ViterbiTraceBackDepth;
            s.ViterbiTrellis = obj.ViterbiTrellis;
            s.ViterbiWordLength = obj.ViterbiTrellis;
            if isLocked(obj)
                if ~isempty(obj.pDec) % For the case of ChannelCoding being "none" or "RS", pDec is not defined. Hence, this should not be saved then
                    s.pDec = matlab.System.saveObject(obj.pDec);
                end
                s.pFirstTimeStepCalling = obj.pFirstTimeStepCalling;
                s.pInputBuffer = obj.pInputBuffer;
                s.pOutputBuffer = obj.pOutputBuffer;
                s.pInputBitsSeen = obj.pInputBitsSeen;
                s.pPendingFrameStartBits = obj.pPendingFrameStartBits;
                s.pDecodedFrameStartBits = obj.pDecodedFrameStartBits;
                s.pDifferentialDecoderBit = obj.pDifferentialDecoderBit;
                s.pFrameSyncLocked = obj.pFrameSyncLocked;
                s.pFrameSyncGoodCount = obj.pFrameSyncGoodCount;
                s.pFrameSyncBadCount = obj.pFrameSyncBadCount;
                s.pFrameSyncLastPhase = obj.pFrameSyncLastPhase;
            end
        end

        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s

            if isfield(s,'RandomizerFECPosition')
                obj.RandomizerFECPosition = s.RandomizerFECPosition;
            end
            if isfield(s,'DataPathMode')
                obj.DataPathMode = s.DataPathMode;
            end
            if isfield(s,'ConvolutionalG1G2Mode')
                obj.ConvolutionalG1G2Mode = s.ConvolutionalG1G2Mode;
            end
            if isfield(s,'DebugLDPC')
                obj.DebugLDPC = s.DebugLDPC;
            end
            if isfield(s,'LDPCMaxIterations')
                obj.LDPCMaxIterations = s.LDPCMaxIterations;
            end
            if isfield(s,'CodedSyncOffset')
                obj.CodedSyncOffset = s.CodedSyncOffset;
            end
            if isfield(s,'UsePeriodicCodedASMSync')
                obj.UsePeriodicCodedASMSync = s.UsePeriodicCodedASMSync;
            end
            if isfield(s,'CodedASMPeriodicFrames')
                obj.CodedASMPeriodicFrames = s.CodedASMPeriodicFrames;
            end
            if isfield(s,'FrameSyncBitSlipTolerance')
                obj.FrameSyncBitSlipTolerance = s.FrameSyncBitSlipTolerance;
            end
            if isfield(s,'FrameSyncASMErrorThreshold')
                obj.FrameSyncASMErrorThreshold = s.FrameSyncASMErrorThreshold;
            end
            if isfield(s,'FrameSyncLockThreshold')
                obj.FrameSyncLockThreshold = s.FrameSyncLockThreshold;
            end
            if isfield(s,'FrameSyncUnlockThreshold')
                obj.FrameSyncUnlockThreshold = s.FrameSyncUnlockThreshold;
            end
            if isfield(s,'TPCCodeRate')
                obj.TPCCodeRate = s.TPCCodeRate;
            end
            if isfield(s,'TPCBlocksPerTF')
                obj.TPCBlocksPerTF = s.TPCBlocksPerTF;
            end
            if isfield(s,'TPCInterleaver')
                obj.TPCInterleaver = s.TPCInterleaver;
            end
            if isfield(s,'TPCUseKnownZeroConstraint')
                obj.TPCUseKnownZeroConstraint = ...
                    s.TPCUseKnownZeroConstraint;
            end
            if isfield(s,'TPCDecoderMode')
                obj.TPCDecoderMode = s.TPCDecoderMode;
            end

            if wasLocked
                if isfield(s,'pDec') % For the case of ChannelCoding being "none" or "RS", pDec is not defined. Hence, this should not be saved then
                    obj.pDec = matlab.System.loadObject(s.pDec);
                end
                obj.pFirstTimeStepCalling = s.pFirstTimeStepCalling;
                obj.pInputBuffer = s.pInputBuffer;
                obj.pOutputBuffer = s.pOutputBuffer;
                if isfield(s,'pInputBitsSeen')
                    obj.pInputBitsSeen = s.pInputBitsSeen;
                    obj.pPendingFrameStartBits = s.pPendingFrameStartBits;
                    obj.pDecodedFrameStartBits = s.pDecodedFrameStartBits;
                end
                obj.pDifferentialDecoderBit = s.pDifferentialDecoderBit;
                if isfield(s,'pFrameSyncLocked')
                    obj.pFrameSyncLocked = s.pFrameSyncLocked;
                    obj.pFrameSyncGoodCount = s.pFrameSyncGoodCount;
                    obj.pFrameSyncBadCount = s.pFrameSyncBadCount;
                    obj.pFrameSyncLastPhase = s.pFrameSyncLastPhase;
                end
            end
            obj.ViterbiTraceBackDepth = s.ViterbiTraceBackDepth;
            obj.ViterbiTrellis = s.ViterbiTrellis;
            obj.ViterbiWordLength = s.ViterbiTrellis;

            % Set public properties and states
            loadObjectImpl@satcom.internal.ccsds.tmBase(obj,s,wasLocked);
        end

        %% Advanced functions
        function flag = isInputSizeMutableImpl(~,~)
            % Return false if input size cannot change
            % between calls to the System object
            flag = true;
        end

        function flag = isInactivePropertyImpl(obj,prop)
            % Return false if property is visible based on object
            % configuration, for the command line and System block dialog
            flag = true;
            isFACM = false; % Currently FACM waveform is not supported
            smtfFlag = isFACM || (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF);
            if strcmp(prop,'ChannelCoding')
                flag = isFACM;
            elseif strcmp(prop,'NumBytesInTransferFrame')
                flag = any(strcmp(obj.ChannelCoding,{'RS','concatenated','turbo'}));
                if strcmp(obj.ChannelCoding,'LDPC')
                    flag = ~obj.IsLDPCOnSMTF;
                end
            elseif any(strcmp(prop,{'ConvolutionalCodeRate', 'ConvolutionalG1G2Mode', ...
                    'ViterbiTraceBackDepth','ViterbiTrellis','ViterbiWordLength'}))
                flag = ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) || isFACM;
            elseif strcmp(prop,'DebugPCMFormat')
                flag = false;
            elseif strcmp(prop,'DebugLDPC')
                flag = false;
            elseif strcmp(prop,'LDPCMaxIterations')
                flag = ~strcmp(obj.ChannelCoding,'LDPC') || isFACM;
            elseif strcmp(prop,'DebugTurbo')
                flag = false;
            elseif strcmp(prop,'CodedSyncOffset')
                flag = false;
            elseif strcmp(prop,'CodeRate')
                flag = ~any(strcmp(obj.ChannelCoding,{'turbo','LDPC'})) || isFACM;
            elseif strcmp(prop,'TPCCodeRate')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCBlocksPerTF')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCInterleaver')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCUseKnownZeroConstraint')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCDecoderMode')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'NumBitsInInformationBlock')
                flag = ~any(strcmp(obj.ChannelCoding,{'LDPC','turbo'})) || isFACM;
            elseif strcmp(prop,'IsLDPCOnSMTF')
                flag = ~strcmp(obj.ChannelCoding,'LDPC') || isFACM;
            elseif strcmp(prop,'LDPCCodeblockSize')
                flag = ~(strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF) || isFACM;
            elseif any(strcmp(prop,{'RandomizerEnabled','RandomizerFECPosition','DataPathMode'}))
                flag = smtfFlag;
            elseif strcmp(prop,'HasASM')
                flag = smtfFlag;
            elseif any(strcmp(prop,{'ASMLength','ASMHex'}))
                flag = ~obj.HasASM || smtfFlag;
            elseif any(strcmp(prop,{'RSMessageLength','RSInterleavingDepth','IsRSMessageShortened'}))
                flag = ~any(strcmp(obj.ChannelCoding,{'RS','concatenated'})) || isFACM;
            elseif strcmp(prop,'RSShortenedMessageLength')
                flag = ~any(strcmp(obj.ChannelCoding,{'RS','concatenated'}));
                if ~flag && obj.IsRSMessageShortened
                    flag = false;
                else
                    flag = true;
                end
                flag = flag  || isFACM;
            elseif strcmp(prop,'Modulation')
                flag = isFACM;
            elseif strcmp(prop,'PCMFormat')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','BPSK','QPSK','8PSK', ...
                    'OQPSK','16QAM','32QAM','16APSK','32APSK'})) || isFACM;
            elseif any(strcmp(prop, {'DisableFrameSynchronization','DisablePhaseAmbiguityResolution', ...
                    'FrameSyncBitSlipTolerance','FrameSyncASMErrorThreshold', ...
                    'FrameSyncLockThreshold','FrameSyncUnlockThreshold'}))
                flag = false; % Always visible
            end
        end
    end

    methods(Access = protected, Static)
        function group = getPropertyGroupsImpl
            % Define property section(s) for System block dialog
            genprops = {'ChannelCoding',...
                'RandomizerEnabled',...
                'RandomizerFECPosition',...
                'DataPathMode',...
                'HasASM',...
                'ASMLength',...
                'ASMHex',...
                'DisableFrameSynchronization',...
                'DisablePhaseAmbiguityResolution',...
                'DebugPCMFormat',...
                'DebugLDPC',...
                'LDPCMaxIterations',...
                'CodedSyncOffset',...
                'FrameSyncBitSlipTolerance',...
                'FrameSyncASMErrorThreshold',...
                'FrameSyncLockThreshold',...
                'FrameSyncUnlockThreshold',...
                'NumBytesInTransferFrame',...
                'ConvolutionalCodeRate',...
                'ConvolutionalG1G2Mode',...
                'CodeRate',...
                'TPCCodeRate',...
                'TPCBlocksPerTF',...
                'TPCInterleaver',...
                'TPCUseKnownZeroConstraint',...
                'TPCDecoderMode',...
                'NumBitsInInformationBlock',...
                'IsLDPCOnSMTF',...
                'LDPCCodeblockSize',...
                'ViterbiTraceBackDepth',...
                'ViterbiTrellis',...
                'ViterbiWordLength',...
                'RSMessageLength',...
                'RSInterleavingDepth',...
                'IsRSMessageShortened',...
                'RSShortenedMessageLength',...
                'Modulation',...
                'PCMFormat'};
            group = matlab.system.display.SectionGroup('PropertyList', genprops);
        end
    end
end

function tf = localIsDefaultTMASM(bits)
defaultASM = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
tf = numel(bits) == numel(defaultASM) && all(int8(bits(:) ~= 0) == defaultASM);
end

function S = loadOrCreateTMLDPCH(k, invr)
    % The AR4JA rate-1/2 family is defined by a sparse 3M-by-5M graph.  Its
    % final M variables are punctured, leaving a transmitted length of 4M.
    % Decode on that original graph instead of a dense algebraically
    % equivalent H=[P' I], whose short cycles destroy iterative performance.
    if abs(double(invr) - 2) < 1e-12 && ...
            ismember(double(k), [1024 4096 16384])
        [H, meta] = buildTMLDPC_H_standard(k, invr);
        S = struct( ...
            'H', H, ...
            'k', double(k), ...
            'n', meta.TransmittedLength, ...
            'fullN', meta.FullCodewordLength, ...
            'puncturedLength', meta.PuncturedLength, ...
            'invr', double(invr), ...
            'matrixMode', 'ccsds-ar4ja-sparse-punctured');
        return;
    end

    cacheDir = fileparts(mfilename('fullpath'));
    invrTag = rateTagFromInverse(invr);
    cacheName = sprintf('tm_ldpc_H_k%d_%s.mat', k, invrTag);
    cachePath = fullfile(cacheDir, cacheName);

    if exist(cachePath, 'file')
        S = load(cachePath, 'H', 'k', 'n');
        S.invr = invr;
        return;
    end

    legacyPath = fullfile(cacheDir, 'tm_ldpc_H_k7136_n8160.mat');
    if k == 7136 && exist(legacyPath, 'file')
        S = load(legacyPath, 'H', 'k', 'n');
        S.invr = invr;
        return;
    end

    fprintf('[LDPC setup] cache miss: building %s\n', cacheName);
    H = buildTMLDPC_H_from_encoder(k, invr);
    Gc = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(k, invr);
    z = zeros(k, 1, 'int8');
    cw = int8(satcom.internal.ccsds.tmldpcEncode(z, Gc));
    n = length(cw);
    save(cachePath, 'H', 'k', 'n', 'invr', '-v7.3');
    S = struct('H', H, 'k', k, 'n', n, 'invr', invr);
end

function tag = rateTagFromInverse(invr)
    rate = 1 / double(invr);
    if abs(rate - 1/2) < 1e-9
        tag = 'r1_2';
    elseif abs(rate - 2/3) < 1e-9
        tag = 'r2_3';
    elseif abs(rate - 4/5) < 1e-9
        tag = 'r4_5';
    elseif abs(rate - 7/8) < 1e-3 || abs(rate - 7136/8160) < 1e-3
        tag = 'r7_8';
    else
        tag = sprintf('invr_%s', strrep(num2str(double(invr), '%.12g'), '.', 'p'));
    end
end

function syncASM = localPCMBuildConvEncodedASMSync(asmBits, initState, pcmFormat, trellis, puncturePattern, offsetLength, flipSecondBranch)
    asmBits = int8(asmBits(:) ~= 0);
    diffBits = zeros(size(asmBits), 'int8');
    state = int8(initState ~= 0);

    for k = 1:numel(asmBits)
        inBit = asmBits(k);
        if strcmp(pcmFormat,'NRZ-S')
            inBit = int8(~logical(inBit));
        end
        state = int8(xor(logical(state), logical(inBit)));
        diffBits(k) = state;
    end

    enc = comm.ConvolutionalEncoder('TrellisStructure', trellis);
    motherBits = int8(enc(diffBits));

    if flipSecondBranch
        motherBits(2:2:end) = int8(~logical(motherBits(2:2:end)));
    end

    p = puncturePattern(:);
    pp = repmat(p, ceil(length(motherBits)/length(p)), 1);
    pp = pp(1:length(motherBits));

    codedASM = motherBits(logical(pp));
    offsetLength = min(offsetLength, length(codedASM)-1);
    syncASM = int8(codedASM(offsetLength+1:end));
end

function rotatedASM = localPCMBuildRotatedASMForMod(asmBits, modscheme)
    asmBits = int8(asmBits(:) ~= 0);
    asmLen = numel(asmBits);

    switch char(modscheme)
        case {'BPSK','GMSK'}
            rotatedASM = [2*asmBits(:)-1, 1-2*asmBits(:)];

        case {'QPSK','OQPSK'}
            rotationMap = [0, 1, 2, 3; ...
                2, 0, 3, 1; ...
                3, 2, 1, 0; ...
                1, 3, 0, 2];
            m = 2;
            padLen = mod(m - mod(asmLen, m), m);
            asmPadded = [asmBits(:); zeros(padLen, 1, 'int8')];
            asmSymbols = comm.internal.utilities.bi2deLeftMSB( ...
                double(reshape(asmPadded, m, []).'), 2);
            rotatedASM = zeros(asmLen, 4);
            for iRot = 1:4
                temp = comm.internal.utilities.de2biBase2LeftMSB( ...
                    rotationMap(iRot, asmSymbols+1).', m).';
                temp = temp(:);
                rotatedASM(:, iRot) = 2*temp(1:asmLen) - 1;
            end

        case '8PSK'
            m = 3;
            map = [0 4 6 2 3 7 5 1];
            invMap = zeros(1, 8);
            for k = 1:8
                invMap(map(k) + 1) = k - 1;
            end

            padLen = mod(m - mod(asmLen, m), m);
            asmPadded = [asmBits(:); zeros(padLen, 1, 'int8')];
            asmLabels = comm.internal.utilities.bi2deLeftMSB( ...
                double(reshape(asmPadded, m, []).'), 2);

            asmSymIdx = zeros(size(asmLabels));
            for k = 1:length(asmLabels)
                asmSymIdx(k) = invMap(asmLabels(k) + 1);
            end

            rotatedASM = zeros(asmLen, 8);
            for iRot = 1:8
                rot = iRot - 1;
                rotatedSymIdx = mod(asmSymIdx + rot, 8);
                rotatedLabels = map(rotatedSymIdx + 1).';
                rotatedBits = comm.internal.utilities.de2biBase2LeftMSB( ...
                    rotatedLabels, m).';
                rotatedBits = rotatedBits(:);
                rotatedASM(:, iRot) = 2*rotatedBits(1:asmLen) - 1;
            end

        otherwise
            rotatedASM = 2*asmBits(:)-1;
    end
end

function [decodedBits, lastLineBit] = localPCMHardDifferentialDecode(lineBits, lastLineBit, pcmFormat)
    lineBits = int8(lineBits(:) ~= 0);
    if isempty(lineBits)
        decodedBits = lineBits;
        return;
    end

    prev = int8(lastLineBit ~= 0);
    prevBits = [prev; lineBits(1:end-1)];
    decodedBits = int8(xor(logical(lineBits), logical(prevBits)));

    if strcmp(pcmFormat,'NRZ-S')
        decodedBits = int8(~logical(decodedBits));
    end

    lastLineBit = lineBits(end);
end

function localPCMPrintDecodedDebug(obj, decodedBits, tag)
    asmBits = int8(obj.pASM(:));
    decodedBits = int8(decodedBits(:) ~= 0);
    asmLen = numel(asmBits);
    maxStart = min(numel(decodedBits) - asmLen + 1, 5*(obj.pPRNSequenceLength + asmLen));
    bestPos = 0;
    bestErr = asmLen;
    invBestPos = 0;
    invBestErr = asmLen;

    if maxStart > 0
        for iPos = 1:maxStart
            errNow = nnz(decodedBits(iPos:iPos+asmLen-1) ~= asmBits);
            if errNow < bestErr
                bestErr = errNow;
                bestPos = iPos;
                if bestErr == 0
                    break;
                end
            end

            invErrNow = nnz(decodedBits(iPos:iPos+asmLen-1) == asmBits);
            if invErrNow < invBestErr
                invBestErr = invErrNow;
                invBestPos = iPos;
            end
        end
    end

    fprintf('[PCM DEBUG] %s %s: Viterbi+PCM bits=%d, best ASM pos=%d, err=%d/%d, invASM pos=%d, err=%d/%d, diffState=%d\n', ...
        tag, obj.PCMFormat, numel(decodedBits), bestPos, bestErr, asmLen, ...
        invBestPos, invBestErr, asmLen, obj.pDifferentialDecoderBit);
end

function bits = localTPCPayloadBits(rawRate)
    side = localTPCPayloadSideLength(rawRate);
    bits = side * side;
end

function value = localPositiveInteger(rawValue, defaultValue)
    if nargin < 2
        defaultValue = 1;
    end
    if nargin < 1 || isempty(rawValue)
        value = defaultValue;
        return;
    end
    if ischar(rawValue) || isstring(rawValue)
        value = str2double(strtrim(char(rawValue)));
    else
        value = double(rawValue);
    end
    if ~isfinite(value)
        value = defaultValue;
    end
    value = max(1, round(value));
end

function localTPCDecoderBoundaryDebug(cwSoft, txEncodedBits, syncLen, codeLen, wordIndex, blocksPerTF, rxSyncPos)
    if nargin < 6 || isempty(blocksPerTF)
        blocksPerTF = 1;
    end
    if nargin < 7 || isempty(rxSyncPos)
        rxSyncPos = NaN;
    end
    blocksPerTF = localPositiveInteger(blocksPerTF, 1);
    txEncodedBits = int8(txEncodedBits(:) ~= 0);
    cwHard0 = int8(cwSoft(:) > 0);
    if isempty(txEncodedBits) || isempty(cwHard0)
        return;
    end

    codedTFLen = syncLen + codeLen * blocksPerTF;
    numTxFrames = floor(numel(txEncodedBits) / codedTFLen);
    if numTxFrames < 1
        return;
    end

    if evalin('base','exist(''debugTPC_demodBestOffset'',''var'')') && isfinite(rxSyncPos)
        demodOffset = evalin('base','debugTPC_demodBestOffset');
        demodOffset = double(demodOffset);
        rxFrameIndex = floor((wordIndex-1) / blocksPerTF) + 1;
        rxBlockInFrame = mod(wordIndex-1, blocksPerTF) + 1;
        rxCodeStart = double(rxSyncPos) + syncLen + ...
            (rxFrameIndex-1) * codedTFLen + (rxBlockInFrame-1) * codeLen;
        txCodeStart = round(rxCodeStart - demodOffset);
        txCodeStop = txCodeStart + codeLen - 1;

        if txCodeStart >= 1 && txCodeStop <= numel(txEncodedBits)
            txFrameIndex = floor((txCodeStart-1) / codedTFLen) + 1;
            txFrameStart = (txFrameIndex-1) * codedTFLen + 1;
            txBlockInFrame = floor((txCodeStart - txFrameStart - syncLen) / codeLen) + 1;
            txCW = txEncodedBits(txCodeStart:txCodeStop);
            errPos = nnz(cwHard0 ~= txCW);
            errNeg = nnz(int8(~logical(cwHard0)) ~= txCW);
            if errPos <= errNeg
                expectedPolarity = 1;
                expectedErr = errPos;
                expectedSoft = double(cwSoft(:));
            else
                expectedPolarity = -1;
                expectedErr = errNeg;
                expectedSoft = -double(cwSoft(:));
            end
            fprintf('[TPC DEBUG] decoder cwSoft word=%d expectedTxFrame=%d block=%d txStart=%d polarity=%+d hardBER=%.6g (%d/%d), |soft|=%.3g, softMean=%+.3g, hard1=%.1f%%\n', ...
                wordIndex, txFrameIndex, txBlockInFrame, txCodeStart, ...
                expectedPolarity, expectedErr/codeLen, expectedErr, codeLen, ...
                mean(abs(expectedSoft)), mean(expectedSoft), 100*mean(expectedSoft > 0));
        else
            fprintf('[TPC DEBUG] decoder cwSoft word=%d expectedTxStart=%d outside tx range (rxSyncPos=%g, demodOffset=%g)\n', ...
                wordIndex, txCodeStart, rxSyncPos, demodOffset);
        end
    end

    bestErr = inf;
    bestFrame = NaN;
    bestBlockInFrame = NaN;
    bestGlobalBlock = NaN;
    bestPolarity = 1;
    bestLen = 0;
    for iFrame = 1:numTxFrames
        frameStart = (iFrame-1)*codedTFLen + syncLen;
        for jBlock = 1:blocksPerTF
            startIdx = frameStart + (jBlock-1)*codeLen + 1;
            stopIdx = startIdx + codeLen - 1;
            if stopIdx > numel(txEncodedBits)
                break;
            end
            txCW = txEncodedBits(startIdx:stopIdx);
            L = min(numel(txCW), numel(cwHard0));
            for polarity = [1 -1]
                if polarity > 0
                    cwHard = cwHard0;
                else
                    cwHard = int8(~logical(cwHard0));
                end
                err = nnz(cwHard(1:L) ~= txCW(1:L));
                if err < bestErr
                    bestErr = err;
                    bestFrame = iFrame;
                    bestBlockInFrame = jBlock;
                    bestGlobalBlock = (iFrame-1)*blocksPerTF + jBlock;
                    bestPolarity = polarity;
                    bestLen = L;
                end
            end
        end
    end

    if bestLen > 0
        fprintf('[TPC DEBUG] decoder cwSoft word=%d globalBestTxFrame=%d block=%d globalBlock=%d polarity=%+d hardBER=%.6g (%d/%d)\n', ...
            wordIndex, bestFrame, bestBlockInFrame, bestGlobalBlock, ...
            bestPolarity, bestErr/bestLen, bestErr, bestLen);
    end
end

function rate = localTPCEffectiveRate(rawRate)
    rate = localTPCPayloadBits(rawRate) / (64 * 64);
end

function side = localTPCPayloadSideLength(rawRate)
    if nargin < 1 || isempty(rawRate)
        rawRate = 'native';
    end

    if isnumeric(rawRate)
        side = round(double(rawRate));
    else
        key = lower(strtrim(char(rawRate)));
        switch key
            case {'native','default','0.7932','57','57x57'}
                side = 57;
            case {'1/2','half'}
                side = 45;
            case {'2/3'}
                side = 52;
            otherwise
                xPos = strfind(key, 'x');
                if numel(xPos) == 1
                    side = round(str2double(key(1:xPos-1)));
                else
                    side = round(str2double(key));
                end
        end
    end

    if ~isfinite(side) || side < 1 || side > 57
        error('HelperCCSDSTMDecoder:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end

function out = localFrameSoftPayloadFlip(values, frameLength, headerLength, prnSeq)
    out = values;
    frameLength = max(1, round(double(frameLength)));
    headerLength = max(0, round(double(headerLength)));
    payloadLength = frameLength - headerLength;
    if payloadLength <= 0 || isempty(out)
        return;
    end
    if nargin < 4 || isempty(prnSeq) || numel(prnSeq) < payloadLength
        prn = satcom.internal.ccsds.tmrandseq(payloadLength);
    else
        prn = int8(prnSeq(1:payloadLength));
    end
    mask = logical(prn(:));

    if isvector(out)
        numFrames = floor(numel(out) / frameLength);
        for iFrame = 1:numFrames
            startIdx = (iFrame-1)*frameLength + headerLength + 1;
            stopIdx = startIdx + payloadLength - 1;
            payload = out(startIdx:stopIdx);
            payload(mask) = -payload(mask);
            out(startIdx:stopIdx) = payload;
        end
    else
        rows = size(out, 1);
        if rows >= headerLength + payloadLength
            payload = out(headerLength+1:headerLength+payloadLength, :);
            payload(mask, :) = -payload(mask, :);
            out(headerLength+1:headerLength+payloadLength, :) = payload;
        end
    end
end

function out = localSoftXorByPRN(values, payloadLength, prnSeq)
    out = values;
    payloadLength = max(1, round(double(payloadLength)));
    if nargin < 3 || isempty(prnSeq) || numel(prnSeq) < payloadLength
        prn = satcom.internal.ccsds.tmrandseq(payloadLength);
    else
        prn = int8(prnSeq(1:payloadLength));
    end
    mask = logical(prn(:));
    if isvector(out)
        usableLen = floor(numel(out) / payloadLength) * payloadLength;
        tmp = reshape(out(1:usableLen), payloadLength, []);
        tmp(mask, :) = -tmp(mask, :);
        out(1:usableLen) = tmp(:);
    else
        tmp = out(1:payloadLength, :);
        tmp(mask, :) = -tmp(mask, :);
        out(1:payloadLength, :) = tmp;
    end
end

function headerLength = localEncodedASMLength(channelCoding, rawASMLength, inverseCodeRate)
    if rawASMLength <= 0
        headerLength = 0;
        return;
    end

    if any(strcmp(channelCoding, {'convolutional','concatenated'}))
        headerLength = ceil(double(rawASMLength) * double(inverseCodeRate));
    else
        headerLength = rawASMLength;
    end
end

function tf = localShouldPrintCodedFrameSyncDebug()
    tf = true;
    try
        hasLimit = evalin('base', 'exist(''debugCodedFrameSyncPrintLimit'',''var'')');
        if ~hasLimit
            return;
        end

        limit = evalin('base', 'debugCodedFrameSyncPrintLimit');
        limit = round(double(limit));
        if ~isfinite(limit) || limit < 0
            return;
        end
        if limit == 0
            tf = false;
            return;
        end

        hasCount = evalin('base', 'exist(''debugCodedFrameSyncPrintCount'',''var'')');
        if hasCount
            count = round(double(evalin('base', 'debugCodedFrameSyncPrintCount')));
        else
            count = 0;
        end
        if ~isfinite(count) || count < 0
            count = 0;
        end

        tf = count < limit;
        if tf
            assignin('base', 'debugCodedFrameSyncPrintCount', count + 1);
        end
    catch
        tf = true;
    end
end

function localValidateHighRateConvFrameLength(rateStr, caduBits, punctureInputPeriod, exampleText)
    if mod(double(caduBits), double(punctureInputPeriod)) == 0
        return;
    end
    error('HelperCCSDSTMDecoder:HighRateConvFrameLengthUnsupported', ...
        ['ConvolutionalCodeRate="%s" requires ASM+TF length (%d bits) ', ...
         'to be divisible by %d so the puncture phase resets at each frame. ', ...
         'Use NumBytesInTransferFrame=%s, or another aligned TF length.'], ...
        char(rateStr), double(caduBits), double(punctureInputPeriod), char(exampleText));
end
