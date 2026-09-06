classdef ccsdsTMWaveformGenerator < satcom.internal.ccsds.tmBase
    %ccsdsTMWaveformGenerator CCSDS telemetry waveform generator
    %   TMWAVEGEN = ccsdsTMWaveformGenerator creates a CCSDS telemetry (TM)
    %   waveform generator System object, TMWAVEGEN. This object takes
    %   information bits and processes it through the CCSDS TM waveform
    %   generation components. This object implements the waveform
    %   generation aspects of CCSDS 131.0-B-3, 401.0-B-30, and 131.2-B-1.
    %   The object supports generating the waveform that is specified by
    %   the CCSDS TM synchronization and channel coding [1] standard and
    %   CCSDS flexible advanced coding and modulation scheme for high rate
    %   telemetry [3] standard.
    %
    %   TMWAVEGEN = ccsdsTMWaveformGenerator(Name,Value) creates a CCSDS TM
    %   waveform generator object, TMWAVEGEN, with the specified property
    %   Name set to the specified Value. You can specify additional
    %   name-value pair arguments in any order as
    %   (Name1,Value1,...,NameN,ValueN).
    %
    %   Step method syntax:
    %
    %   [TXWAVEFORM,ENCODEDBITS] = STEP(TMWAVEGEN,BITS) generates CCSDS TM
    %   time-domain samples from input bits, BITS, with CCSDS TM waveform
    %   generator object, TMWAVEGEN. BITS is the information bits in the
    %   form of transfer frames. Length of BITS should be an integral
    %   multiple of the number of bits in one transfer frame. The number of
    %   bits in one transfer frame can be found using the read-only
    %   property, TMWAVEGEN.NumInputBits. BITS can be a double, int8, or
    %   logical typed binary column vector. TXWAVEFORM is a complex double
    %   column vector. ENCODEDBITS is a binary column vector of int8
    %   containing the bits after channel encoding is done inside the
    %   object.
    %
    %   System objects may be called directly like a function instead of
    %   using the step method. For example, y = step(obj,x) and y = obj(x)
    %   are equivalent.
    %
    %   ccsdsTMWaveformGenerator methods:
    %
    %   step          -  Generate CCSDS TM based time-domain samples (see
    %                    above)
    %   release       -  Allow property value and input characteristics
    %                    changes
    %   clone         -  Create a CCSDS TM waveform generator object with
    %                    same property values
    %   isLocked      -  Locked status (logical)
    %   reset         -  Reset states of CCSDS TM waveform generator object
    %   <a href="matlab:help ccsdsTMWaveformGenerator/infoImpl">info</a>          -  Return physical layer parameters of the waveform
    %                     generator
    %   flushFilter   -  Get residual data samples in the filter state by
    %                    flushing zeros
    %
    %   ccsdsTMWaveformGenerator properties:
    %
    %   WaveformSource              - CCSDS telemetry waveform source
    %   ACMFormat                   - Adaptive coding and modulation format
    %   NumBytesInTransferFrame     - Number of bytes in one transfer frame
    %   RandomizerEnabled           - Option for randomizing the data
    %   HasASM                      - Option for inserting attached sync
    %                                 marker (ASM)
    %   PCMFormat                   - Pulse code modulation (PCM) format
    %   ChannelCoding               - Error control channel coding scheme
    %   NumBitsInInformationBlock   - Number of bits in turbo/LDPC message
    %   ConvolutionalCodeRate       - Code rate of convolutional code
    %   CodeRate                    - Code rate of turbo or LDPC code
    %   RSMessageLength             - Number of bytes in one Reed-Solomon
    %                                 (RS) message block
    %   RSInterleavingDepth         - Interleaving depth of the RS code
    %   IsRSMessageShortened        - Option to shorten RS code
    %   RSShortenedMessageLength    - Number of bytes in RS shortened
    %                                 message block
    %   IsLDPCOnSMTF                - Option for using LDPC on stream of
    %                                 sync marked transfer frame (SMTF)
    %   LDPCCodeblockSize           - Number of LDPC codewords in LDPC
    %                                 codeblock of stream of SMTF
    %   Modulation                  - Modulation scheme
    %   PulseShapingFilter          - Pulse shaping filter
    %   RolloffFactor               - Rolloff factor for transmit filtering
    %   FilterSpanInSymbols         - Transmit filter span in symbols
    %   BandwidthTimeProduct        - Bandwidth time product for Gaussian
    %                                 minimum shift keying (GMSK) modulator
    %   ModulationEfficiency        - Modulation efficiency of 4
    %                                 dimensional 8 phase shift keying
    %                                 trellis coded modulation
    %                                 (4D-8PSK-TCM)
    %   SubcarrierWaveform          - Waveform used to phase shift keying
    %                                 (PSK) modulate the non return to zero
    %                                 (NRZ) data
    %   ModulationIndex             - Modulation index in radians
    %                                 in the residual carrier phase
    %                                 modulation
    %   SymbolRate                  - Symbol rate (coded symbols/s)
    %   SubcarrierToSymbolRateRatio - Ratio of subcarrier frequency to
    %                                 symbol rate
    %   SamplesPerSymbol            - Samples per symbol
    %   HasPilots                   - Option for inserting pilot symbols
    %   ScramblingCodeNumber        - Scrambling code number
    %   NumInputBits                - Minimum number of input bits required
    %                                 to generate waveform
    %   MinNumTransferFrames        - Minimum number of transfer frames for
    %                                 non-empty output
    %
    %   References:
    %    [1] TM Synchronization and Channel Coding. Recommendation
    %        for Space Data System Standards, CCSDS 131.0-B-3. Blue Book.
    %        Issue 3. Washington, D.C.: CCSDS, September 2017.
    %    [2] Radio Frequency and Modulation Systems--Part 1: Earth Stations
    %        and Spacecraft. Recommendation for Space Data System
    %        Standards, CCSDS 401.0-B-30. Blue Book. Issue 30. Washington,
    %        D.C.: CCSDS, February 2020.
    %    [3] Flexible Advanced Coding and Modulation Scheme for High Rate
    %        Telemetry Applications. Recommendation for Space Data System
    %        Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington,
    %        D.C.: CCSDS, March 2012.
    %
    %   Examples:
    %
    %   % Example 1:
    %   % Generate a CCSDS TM waveform with Reed-Solomon (RS) channel
    %   % coding scheme and Gaussian minimum shift keying (GMSK)
    %   % modulation scheme, and compare the spectrum of GMSK waveforms
    %   % with bandwidth time product of 0.25 and 0.5.
    %
    %   tmWaveGen1 = ccsdsTMWaveformGenerator("ChannelCoding", "RS", ...
    %                     "RSMessageLength", 239, ...
    %                     "Modulation", "GMSK",...
    %                     "BandwidthTimeProduct", 0.5)
    %
    %   rng default % To get reproducible results
    %   bits = randi([0 1], tmWaveGen1.NumInputBits, 1);
    %   waveform1 = tmWaveGen1(bits);
    %
    %   tmWaveGen2 = ccsdsTMWaveformGenerator("ChannelCoding", "RS", ...
    %                        "RSMessageLength", 239, ...
    %                        "Modulation", "GMSK")
    %   bits = randi([0 1], tmWaveGen2.NumInputBits, 1);
    %   waveform2 = tmWaveGen2(bits);
    %
    %   scope = dsp.SpectrumAnalyzer;
    %   scope.SampleRate = tmWaveGen2.SamplesPerSymbol*2e6; % 2MHz rate
    %   scope.AveragingMethod = "Exponential"; % To have a smooth spectrum
    %   scope.ShowLegend = true;
    %   scope.ChannelNames = {'BandwidthTimeProduct = 0.5', ...
    %                         'BandwidthTimeProduct = 0.25'};
    %   scope.Title = ['Spectrum of waveform with channel coding of ', ...
    %                  'RS and GMSK modulation'];
    %   scope([waveform1,waveform2]);
    %
    %   % Example 2:
    %   % Generate waveform for CCSDS flexible advanced coding
    %   % and modulation scheme for high rate telemetry applications
    %   % standard for one physical layer (PL) frame and plot the
    %   % constellation.
    %
    %   tmWaveGen = ccsdsTMWaveformGenerator("WaveformSource", ...
    %       "flexible advanced coding and modulation", ...
    %       "PulseShapingFilter", "none", ...
    %       "ACMFormat", 14); % Configure the waveform generator as needed
    %                         % ACMFormat of 14 means that the modulation
    %                         % scheme is 16 APSK along with the number of
    %                         % input bits to SCCC encoder is 21358.
    %
    %   rng default % To get reproducible results
    %
    %   hasfilt = ~strcmp(tmWaveGen.PulseShapingFilter,"none");
    %
    %   % As there are 16 codewords in one PL frame for flexible advanced
    %   % coding and modulation for high rate telemetry applications
    %   % standard [3], multiply MinNumTransferFrames by 16 to get number
    %   % of transfer frames needed to generate one PL frame.
    %
    %   NumTFForOnePLFrame = tmWaveGen.MinNumTransferFrames*16
    %
    %   waveform = [];
    %
    %   for iTF = 1:NumTFForOnePLFrame
    %       bits = randi([0 1], tmWaveGen.NumInputBits, 1);
    %       waveform = [waveform;tmWaveGen(bits)];
    %   end
    %
    %   scatterplot(waveform); % Plot the constellation
    %   legend off;
    %
    %   % Example 3:
    %   % Generate telemetry waveform with 4 dimentional 8 phase shift
    %   % keying trellis coded modulation (4D-8PSK-TCM) with a modulation
    %   % efficiency of 2 by passing multiple transfer frames in one system
    %   % object call.
    %
    %   % Initialize the CCSDS TM waveform generator system object
    %   tmWaveGen = ccsdsTMWaveformGenerator("ChannelCoding", "none", ...
    %       "Modulation", "4D-8PSK-TCM")
    %
    %   numTF = 20; % Number of transfer frames
    %
    %   rng default % To get reproducible results
    %
    %   % Generate bits for all transfer frames at once
    %   bits = randi([0 1], numTF*tmWaveGen.NumInputBits, 1);
    %
    %   % Generate waveform by passing all bits at once
    %   waveform = tmWaveGen(bits);
    %
    %   % Example 4:
    %   % Generate CCSDS telemetry waveform with turbo channel coding with
    %   % QPSK modulation and generate the waveform in multiple system
    %   % object calls.
    %
    %   % Initialize the CCSDS TM waveform generator system object
    %   tmWaveGen = ccsdsTMWaveformGenerator("ChannelCoding", "turbo", ...
    %       "Modulation", "QPSK")
    %
    %   numTF = 10;
    %
    %   rng default % To get reproducible results
    %
    %   waveform = []; % Initialize waveform as null
    %
    %   for iTF = 1:numTF
    %       bits = randi([0 1], tmWaveGen.NumInputBits, 1);
    %       waveform = [waveform; tmWaveGen(bits)];
    %   end
    %
    %   % Example 5:
    %   % Generate CCSDS telemetry waveform with LDPC on stream of sync
    %   % marked transfer frames (SMTF) for one LDPC codeblock.
    %
    %   tmWaveGen = ccsdsTMWaveformGenerator("ChannelCoding", "LDPC", ...
    %       "NumBitsInInformationBlock", 4096, ...
    %       "IsLDPCOnSMTF", true, ...
    %       "Modulation", "BPSK")
    %
    %   % Calculate number of bits in one LDPC codeword
    %   n = tmWaveGen.NumBitsInInformationBlock/...
    %            tmWaveGen.info.ActualCodeRate
    %
    %   % Calculate number of transfer frames such that one LDPC
    %   % codeblock is generated
    %   NumTFForOneCodeblock = tmWaveGen.MinNumTransferFrames*...
    %                         tmWaveGen.LDPCCodeblockSize
    %
    %   % Calculate number of bits in one LDPC codeblock
    %   csmlen = 32*strcmp(tmWaveGen.CodeRate,"7/8") + ...
    %       64*(~strcmp(tmWaveGen.CodeRate,"7/8"));
    %   NumBitsInOneCodeblock = n*tmWaveGen.LDPCCodeblockSize + csmlen
    %
    %   % Calculate the number of samples that are there in one LDPC code
    %   % block
    %   NumSamplesInOneCodeblock = ceil(NumBitsInOneCodeblock*...
    %                              tmWaveGen.SamplesPerSymbol/...
    %                              tmWaveGen.info.NumBitsPerSymbol)
    %
    %   rng default % To get reproducible results
    %
    %   % Generate the bits that are needed to generate the waveform for
    %   % one LDPC codeblock
    %   bits = ...
    %        randi([0 1], NumTFForOneCodeblock*tmWaveGen.NumInputBits, 1);
    %
    %   % While generating waveform, pass additional zeros to flush any
    %   % bits in the buffers that are handled internal to the
    %   % ccsdsTMWaveformGenerator system object
    %   waveform = tmWaveGen([bits; ...
    %              zeros(NumTFForOneCodeblock*tmWaveGen.NumInputBits, 1)]);
    %
    %   txWaveform = waveform(1:NumSamplesInOneCodeblock);
    %
    %   See also ccsdsTCConfig, ccsdsTCWaveform, ccsdsTCIdealReceiver.

    %   Copyright 2020 The MathWorks, Inc.

    %#codegen
    properties
        % RandomizerFECPosition Randomizer position relative to the TX FEC encoder.
        %   "afterEncoding" randomizes the FEC codeword.
        %   "beforeEncoding" randomizes the information bits.
        RandomizerFECPosition = 'afterEncoding'
        % DataPathMode Information-stream topology.
        %   "single" uses one ordinary TM information stream.
        %   "dualIQ" encodes and randomizes independent I/Q information rails.
        %   "unequalDualIQ" uses UQPSK with two I-rail frames for every
        %   one Q-rail frame. Both rails have independent ASM/FEC state.
        % Randomizer enable/bypass is controlled only by RandomizerEnabled.
        DataPathMode = 'single'
        % ConvolutionalG1G2Mode Convolutional encoder output convention.
        %   Supported values are G1G2, G1G2-inverted (device label
        %   G1G2反), G2G1, and G2G1-inverted (device label G2G1反).
        %   The default preserves the CCSDS G1/~G2 convention previously
        %   hard-coded by flipping every second encoded bit.
        ConvolutionalG1G2Mode = 'auto-ccsds'
        % SplitPathDebug Print TX split-path rail/interleave diagnostics.
        SplitPathDebug = false
        % TPCCodeRate Effective shortened TPC rate.
        %   "native" uses 57x57/64x64. "1/2" uses 45x45/64x64.
        %   "2/3" uses 52x52/64x64.
        TPCCodeRate = 'native'
        % TPCBlocksPerTF Number of TPC codewords in one coded transfer frame.
        TPCBlocksPerTF = 1
        % TPCInterleaver Codeword interleaver mode for TPC.
        %   "auto" enables a 4096-bit codeword interleaver for TPC 1/2 and
        %   leaves other TPC rates unchanged. Use "none" to bypass it.
        TPCInterleaver = 'auto'
        % HasTMAPSKPilots Insert ordinary-TM APSK pilot symbols after mapping.
        %   These pilots are physical-layer helpers and are removed before
        %   APSK demapping at the receiver.
        HasTMAPSKPilots = false
        % TMAPSKPilotInterval Number of APSK data symbols between pilots.
        TMAPSKPilotInterval = 512
        % TMAPSKPilotLength Number of pilot symbols in each periodic block.
        TMAPSKPilotLength = 32
        % TMAPSKPilotPreambleLength Number of pilot symbols at stream start.
        TMAPSKPilotPreambleLength = 64
    end
    % Read-only properties
    properties(SetAccess = private)
        %NumInputBits Minimum number of input bits required to generate
        %waveform
        %   The minimum number of input bits required to generate a
        %   waveform. This property is read-only. The number of input bits
        %   must be integral multiples of NumInputBits.
        NumInputBits
        %MinNumTransferFrames Minimum number of transfer frames for non-empty
        %output
        %   Minimum number of transfer frames required for non-empty system
        %   object output. If WaveformSource is set to "flexible advanced
        %   coding and modulation", or IsLDPCOnSMTF is set to true with
        %   WaveformSource set to "synchronization and channel coding",
        %   system object output is empty until the object has sufficient
        %   input to process through channel coding and modulation.
        %   MinNumTransferFrames indicates the minimum number of transfer
        %   frames required for the system object to process the input and
        %   give non-empty output. This property is read-only.
        MinNumTransferFrames
    end

    % Pre-computed constants
    properties(Nontunable, Access = private)
        pConvEncInLen
        pNumModInBits = 0 % This property is defined to be non-tunable to make code generation work
    end

    properties(Access = private)
        pTransmitFilter % Filter object
        pDiffEnc % comm.DifferentialEncoder object to be used while using NRZ-M
        pDiffEncI
        pDiffEncQ
        pConvEnc % Convolutional encoder object to be used for convolutional coding, concatenated coding and 4D 8PSK TCM
        pConvEnc1 % 1st Convolutional encoder object to be used inside turbo encoder
        pConvEnc2 % 2nd Convolutional encoder object to be used inside turbo encoder
        pN = 4 % Number of output bits for every input bit of the constituent convolutional encoder in the turbo encoder
        pMaxNumCW
        pLDPCGeneratorMatrix % Generator matrix for LDPC encoder
        pConvEncState % Convolutional encoder state for 4D-8PSK-TCM.
        pDiffEncState
        pMod
        pModInputBuffer
        pNumBitsInpModInputBuffer
        pGain
        pSubcarrierPhase = 0
        pGMSKState = struct('altersymb',1,'PrevLastSymb',1);
        pInputBuffer
        pNumBitsInInputBuffer
        pCodewordIndex
        pConvEncI
        pConvEncQ
        pInputBufferI
        pInputBufferQ
        pNumBitsInInputBufferI = 0
        pNumBitsInInputBufferQ = 0
    end

    methods
        % Constructor
        function obj = ccsdsTMWaveformGenerator(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,numel(varargin),varargin{:})
        end
    end

    methods(Access = protected)
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants
            setupImpl@satcom.internal.ccsds.tmBase(obj);
            if ~any(strcmpi(obj.RandomizerFECPosition, {'afterEncoding','beforeEncoding'}))
                error('ccsdsTMWaveformGenerator:InvalidRandomizerFECPosition', ...
                    ['Unsupported RandomizerFECPosition="%s". Use ' ...
                     'afterEncoding or beforeEncoding.'], ...
                    char(obj.RandomizerFECPosition));
            end
            if ~any(strcmpi(obj.DataPathMode, ...
                    {'single','dualIQ','unequalDualIQ'}))
                error('ccsdsTMWaveformGenerator:InvalidDataPathMode', ...
                    ['Unsupported DataPathMode="%s". Use single, dualIQ, ', ...
                     'or unequalDualIQ.'], ...
                    char(obj.DataPathMode));
            end
            % Independent dual-rail information paths
            isEqualSplit = strcmpi(obj.DataPathMode, 'dualIQ');
            isUnequalSplit = strcmpi(obj.DataPathMode, 'unequalDualIQ');
            isSplit = isEqualSplit || isUnequalSplit;
            if isEqualSplit
                splitCapabilities = tm_data_path_capabilities();
                splitOkMods = cellstr(splitCapabilities.SupportedModulations);
                splitOkCodes = cellstr(splitCapabilities.SupportedCodings);

                if obj.pIsFACM || (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF)
                    error('ccsdsTMWaveformGenerator:SplitUnsupported', ...
                        'dualIQ is available only on the ordinary TM path.');
                end
                if ~any(strcmp(obj.Modulation, splitOkMods))
                    error('ccsdsTMWaveformGenerator:SplitUnsupportedModulation', ...
                        'dualIQ does not support Modulation="%s". Supported: %s.', ...
                        obj.Modulation, ...
                        char(strjoin(splitCapabilities.SupportedModulations, ', ')));
                end
                if ~any(strcmp(obj.ChannelCoding, splitOkCodes))
                    error('ccsdsTMWaveformGenerator:SplitUnsupportedCoding', ...
                        'dualIQ does not support ChannelCoding="%s". Supported: %s.', ...
                        obj.ChannelCoding, ...
                        char(strjoin(splitCapabilities.SupportedCodings, ', ')));
                end
            end
            if isUnequalSplit
                splitCapabilities = tm_data_path_capabilities();
                unequal = splitCapabilities.UnequalDualIQ;
                if obj.pIsFACM || ...
                        (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF)
                    error('ccsdsTMWaveformGenerator:UnequalSplitUnsupported', ...
                        'unequalDualIQ is available only on the ordinary TM path.');
                end
                if ~strcmp(obj.Modulation, char(unequal.Modulation))
                    error('ccsdsTMWaveformGenerator:UnequalSplitRequiresUQPSK', ...
                        ['unequalDualIQ requires Modulation="UQPSK"; ', ...
                         'got "%s".'], obj.Modulation);
                end
                if ~any(strcmp(obj.ChannelCoding, ...
                        cellstr(unequal.SupportedCodings)))
                    error('ccsdsTMWaveformGenerator:UnequalSplitUnsupportedCoding', ...
                        ['unequalDualIQ does not support ChannelCoding="%s". ', ...
                         'Supported: %s.'], obj.ChannelCoding, ...
                        char(strjoin(unequal.SupportedCodings, ', ')));
                end
                if ~strcmp(obj.PCMFormat, "NRZ-L")
                    error('ccsdsTMWaveformGenerator:UnequalSplitPCMFormat', ...
                        'unequalDualIQ currently requires PCMFormat="NRZ-L".');
                end
            end
            localValidateHighRateConvFrameLength(obj);


            sps = double(obj.SamplesPerSymbol);
            if obj.pIsFACM
                obj.pInputBuffer = zeros(obj.pK,1,'int8');
                obj.pNumBitsInInputBuffer = 0;
                obj.pCodewordIndex = 1;
                obj.pMaxNumCW = 16;
            else
                switch(obj.ChannelCoding)
                    case {'convolutional','concatenated'}
                        [convTrellis, canonicalConvMode] = ...
                            ccsdsTMConvolutionalOutputTrellis( ...
                            obj.ConvolutionalCodesTrellis, ...
                            obj.ConvolutionalG1G2Mode, ...
                            obj.ConvolutionalCodeRate);
                        if obj.SplitPathDebug
                            fprintf('[TM convolutional TX] mode=%s rate=%s path=%s\n', ...
                                canonicalConvMode, char(obj.ConvolutionalCodeRate), ...
                                char(obj.DataPathMode));
                        end
                        switch obj.ConvolutionalCodeRate
                            case '1/2'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis);
                            case '2/3'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1]);
                            case '3/4'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0]);
                            case '5/6'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0;0;1;1;0]);
                            otherwise % case '7/8'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;0;1;0;1;1;0;0;1;1;0]);
                        end
                        temp = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                        obj.pConvEncInLen = temp - mod(temp,length(obj.pConvEnc.PuncturePattern)/2)*(~strcmp(obj.ConvolutionalCodeRate,'1/2'));
                        if isSplit && strcmp(obj.ChannelCoding,'convolutional')
                            obj.pConvEncI = createConvEncoder(obj);
                            obj.pConvEncQ = createConvEncoder(obj);
                            obj.pInputBufferI = zeros(obj.pConvEncInLen,1,'int8');
                            obj.pInputBufferQ = zeros(obj.pConvEncInLen,1,'int8');
                            obj.pNumBitsInInputBufferI = 0;
                            obj.pNumBitsInInputBufferQ = 0;
                        end
                    case 'turbo'
                        obj.pConvEnc1 = comm.ConvolutionalEncoder('TrellisStructure',...
                            obj.TurboTrellis, 'TerminationMethod', 'Terminated');
                        obj.pConvEnc2 = comm.ConvolutionalEncoder('TrellisStructure',...
                            obj.TurboTrellis, 'TerminationMethod', 'Terminated');
                    case 'TPC'
                        % TPC uses the teacher (64,57)^2 product-code
                        % encoder through ccsdsTPCEncodeBits.
                    case 'LDPC'
                        invr = obj.pInverseCodeRate;
                        k = obj.NumBitsInInformationBlock;
                        m = double(obj.LDPCCodeblockSize);
                        if obj.IsLDPCOnSMTF
                            obj.pMaxNumCW = m;
                            obj.pInputBuffer = zeros(k,1,'int8');
                            obj.pNumBitsInInputBuffer = 0;
                        end
                        obj.pLDPCGeneratorMatrix = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(k, invr);
                end

                if any(strcmp(obj.ChannelCoding, {'convolutional','concatenated'}))
                    temp = obj.pInverseCodeRate*obj.pConvEncInLen;
                else
                    temp = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                    if strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF
                        temp = double(obj.NumBitsInInformationBlock)*obj.pInverseCodeRate;
                    end
                end
                switch(obj.Modulation)
                    case '8PSK'
                        obj.pNumModInBits = temp - mod(temp,3);
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                        obj.pMod = comm.PSKModulator(8,pi/4,'SymbolMapping','Custom',...
                            'BitInput',true,'CustomSymbolMapping',[0 4 6 2 3 7 5 1]);
                     % additional 16QAM
                     case '16QAM'
                         bitsPerSymbol = 4;
                         obj.pNumModInBits = temp - mod(temp,bitsPerSymbol);
                         obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                         obj.pNumBitsInpModInputBuffer = 0;
                     % additional 32QAM
                    case '32QAM'
                        bitsPerSymbol = 5;
                        obj.pNumModInBits = temp - mod(temp,bitsPerSymbol);
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                    case '16APSK'
                        bitsPerSymbol = 4;
                        obj.pNumModInBits = temp - mod(temp,bitsPerSymbol);
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                    case '32APSK'
                        bitsPerSymbol = 5;
                        obj.pNumModInBits = temp - mod(temp,bitsPerSymbol);
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                    case '4D-8PSK-TCM'
                        obj.pNumModInBits = temp - mod(temp,4*double(obj.ModulationEfficiency));
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                        obj.pConvEncState = zeros(6,1,'int8');
                        obj.pDiffEncState = zeros(3,1,'int8');
                    case 'UQPSK'
                        rRatio = 2;
                        bitsPerGroup = rRatio + 1;

                        obj.pNumModInBits = temp - mod(temp, bitsPerGroup);
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                    case 'FM'
                        % FM 鎵╁睍璋冨埗锛? bit / symbol
                        obj.pNumModInBits = temp;
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                    case 'MSK'
                        % 标准 MSK：
                        % 直接输入 0/1 bit，不使用 GMSK 的 Gaussian BT 参数，
                        % 也不使用 CCSDS GMSK 专用 transition precode。
                        obj.pMod = comm.MSKModulator( ...
                            'BitInput', true, ...
                            'InitialPhaseOffset', 0, ...
                            'SamplesPerSymbol', sps);

                        obj.pNumModInBits = temp;
                    case 'GMSK'
                        btprod = double(obj.BandwidthTimeProduct);
                        if btprod == 0.5
                            pulselen = 2;
                        else % btprod==0.25
                            pulselen = 3;
                        end
                        obj.pMod = comm.GMSKModulator('BitInput',false,'BandwidthTimeProduct',...
                            btprod,'PulseLength',pulselen,'SamplesPerSymbol',sps);
                        obj.pGMSKState = struct('altersymb',int8(1),'PrevLastSymb',int8(1));
                        obj.pNumModInBits = temp;
                    case 'OQPSK'
                        obj.pMod = comm.OQPSKModulator('BitInput',true,...
                            'PulseShape','Root raised cosine',...
                            'RolloffFactor',double(obj.RolloffFactor),...
                            'SamplesPerSymbol',sps,...
                            'SymbolMapping',[0 2 3 1],...
                            'FilterSpanInSymbols',double(obj.FilterSpanInSymbols));
                        obj.pNumModInBits = temp;
                        obj.PulseShapingFilter = "root raised cosine";
                    case 'PCM/PSK/PM'
                        obj.pSubcarrierPhase = 0;
                        obj.pNumModInBits = temp;
                    otherwise % For BPSK, QPSK, PCM/PM/biphase-L
                        obj.pNumModInBits = temp;
                end
                obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                obj.pNumBitsInpModInputBuffer = 0;
            end

            if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                obj.pDiffEnc = comm.DifferentialEncoder;
                if isSplit && strcmp(obj.ChannelCoding,'convolutional')
                    obj.pDiffEncI = comm.DifferentialEncoder;
                    obj.pDiffEncQ = comm.DifferentialEncoder;
                end
            end

            if ~strcmp(obj.PulseShapingFilter,'none') && ~any(strcmp(obj.Modulation,{'GMSK','MSK','OQPSK','FM','PCM/PSK/PM','PCM/PM/biphase-L'}))
                obj.pTransmitFilter = comm.RaisedCosineTransmitFilter(...
                    'RolloffFactor', double(obj.RolloffFactor), 'FilterSpanInSymbols', ...
                    double(obj.FilterSpanInSymbols), 'OutputSamplesPerSymbol', ...
                    sps); % This is not used only for GMSK and OQPSK and also when there is not filter
                b = rcosdesign(double(obj.RolloffFactor), double(obj.FilterSpanInSymbols),sps);
                % |H(f)| = 1  for |f| < fN(1-alpha) - Section 6 in [3]
                obj.pGain =  1/sum(b);
            elseif strcmp(obj.Modulation,'OQPSK')
                b = rcosdesign(double(obj.RolloffFactor), double(obj.FilterSpanInSymbols), ...
                    sps);
                % |H(f)| = 1  for |f| < fN(1-alpha) - Section 6 in [3]
                obj.pGain =  1/sum(b);
            end
        end

        function [waveform,encodedBits] = stepImpl(obj,bits)

            if isempty(bits)
                waveform = complex(zeros(0,1));
                encodedBits = zeros(0,1,'int8');
                return;
            end

            validateattributes(bits,{'double','int8','logical'},...
                {'nonnan','finite','column','binary'},mfilename,'BITS');


            if obj.pIsFACM || (obj.IsLDPCOnSMTF && strcmp(obj.ChannelCoding,'LDPC'))
                k = obj.pK;
                IVal = round(3*(k+2)/2); % See the Note in section 4.1.1.2 in [3]
                n = obj.pLDPCCodeWordLength;
                pilots = repmat((1+1j)/sqrt(2),16,15); % Pilots are 1+1j with 16 symbols in each sub-codeblock. See section 5.3.4 of [3]
                NumTF = length(bits)/(obj.pTFLen*8);

                % Mode adaptation - see figure 2-2 in [3]
                if obj.pIsFACM
                    randomized = bitxor(int8(bits(:)),repmat(obj.pPRNSequence,NumTF,1));
                else % LDPC on SMTF
                    randomized = int8(bits);
                end

                asmlen = length(obj.pASM);

                cadus = zeros(NumTF*asmlen+length(bits),1,'int8');
                tflen = obj.pTFLen*8;
                tfasmlen = tflen + asmlen;
                for iTF = 1:NumTF
                    cadus((iTF-1)*tfasmlen+1:iTF*tfasmlen) = [obj.pASM;randomized((iTF-1)*tflen+1:iTF*tflen)];
                end

                % Slicing, encoding and modulation
                [slices,numSlices] = updateInputBuffer(obj,cadus);
                OutputBuffer = complex(zeros(0,1));
                OutputBitsBuffer = zeros(0,1,'int8');
                coder.varsize('OutputBuffer','OutputBitsBuffer');
                if numSlices % If numSlices is not zero
                    % This branch indicates that the input buffer is full
                    for iSlice = 1:numSlices
                        currentSlice = slices((iSlice-1)*k+1:iSlice*k);
                        if obj.pIsFACM
                            % SCCC encoding
                            cw = satcom.internal.ccsds.scccEncode(currentSlice,obj.ACMFormat,...
                                obj.pNumBitsPerSymbol,IVal,obj.pInterleavingIndices,obj.pSCCCPuncturePattern2);
                            % Modulation
                            sym = satcom.internal.ccsds.facmModulate(cw,obj.pNumBitsPerSymbol,obj.pRadii);

                            % Insert pilots
                            if obj.HasPilots
                                s = [reshape(sym,540,15);pilots]; % See section 5.3.4 of [3]
                                tsymbols = s(:);
                            else
                                tsymbols = sym(:);
                            end

                            % Apply PL randomizer
                            randsym = obj.pPLRandomSymbols(:,obj.pCodewordIndex);
                            tsymbols = tsymbols.*randsym;

                            % Header insertion
                            if obj.pCodewordIndex == 1
                                PLSymbols = [obj.pHeader; tsymbols];
                            else
                                PLSymbols = tsymbols;
                            end
                        else
                            tempcw = int8(satcom.internal.ccsds.tmldpcEncode(currentSlice(:),obj.pLDPCGeneratorMatrix));
                            randomized = bitxor(tempcw,obj.pPRNSequence(n*(obj.pCodewordIndex-1)+1:n*obj.pCodewordIndex));
                            if obj.pCodewordIndex == 1
                                cw = [obj.pCSM;randomized];
                            else
                                cw = randomized;
                            end
                            PLSymbols = tmModulate(obj,cw);
                        end

                        % Update codeword index
                        obj.pCodewordIndex = mod(obj.pCodewordIndex + 1,obj.pMaxNumCW);
                        if obj.pCodewordIndex == 0
                            obj.pCodewordIndex = obj.pMaxNumCW;
                        end

                        previousSymbols = OutputBuffer;
                        OutputBuffer = [previousSymbols;PLSymbols];
                        previousbits = OutputBitsBuffer(:);
                        OutputBitsBuffer = [previousbits;cw];
                    end
                end
                symbols = complex(OutputBuffer(:));
                encodedBits = OutputBitsBuffer(:);
            else
                % Channel encoding, randomization and ASM insertion
                if strcmpi(obj.DataPathMode, 'dualIQ')
                    bits = int8(bits(:));
                    if mod(numel(bits), 2) ~= 0
                        error('ccsdsTMWaveformGenerator:SplitInputLength', ...
                            'split input must be [msgI; msgQ] with equal lengths.');
                    end

                    half = numel(bits)/2;
                    encI = tmEncode(obj, bits(1:half), 'I');
                    encQ = tmEncode(obj, bits(half+1:end), 'Q');
                    if obj.SplitPathDebug
                        assignin('base', 'debug_split_tx_encoded_i_bits', int8(encI(:)));
                        assignin('base', 'debug_split_tx_encoded_q_bits', int8(encQ(:)));
                        fprintf('[SplitPath TX rail reference] encI=%d bits, encQ=%d bits\n', ...
                            numel(encI), numel(encQ));
                    end

                    encodedBits = localSplitPackIQForModulation( ...
                        encI, encQ, obj.Modulation, obj.SplitPathDebug);
                    if obj.SplitPathDebug
                        fprintf(['[SplitPath TX interleave] mode=split, input=[I;Q]=%d bits, ', ...
                            'railInput=%d bits, encI=%d, encQ=%d, interleaved=%d, ', ...
                            'mod=%s, coding=%s, randomizer=%s/%s\n'], ...
                            numel(bits), half, numel(encI), numel(encQ), numel(encodedBits), ...
                            char(obj.Modulation), char(obj.ChannelCoding), ...
                            char(obj.RandomizerFECPosition), char(obj.DataPathMode));
                    end
                elseif strcmpi(obj.DataPathMode, 'unequalDualIQ')
                    bits = int8(bits(:));
                    if mod(numel(bits), 3) ~= 0
                        error('ccsdsTMWaveformGenerator:UnequalSplitInputLength', ...
                            ['unequalDualIQ input must be [msgI;msgQ] with ', ...
                             'numel(msgI)=2*numel(msgQ).']);
                    end

                    qLength = numel(bits)/3;
                    iLength = 2*qLength;
                    encI = tmEncode(obj, bits(1:iLength), 'I');
                    encQ = tmEncode(obj, bits(iLength+1:end), 'Q');
                    encodedBits = tm_uqpsk_unequal_bit_mux(encI, encQ, 2);
                    if obj.SplitPathDebug
                        assignin('base', ...
                            'debug_uqpsk_unequal_tx_encoded_i_bits', ...
                            int8(encI(:)));
                        assignin('base', ...
                            'debug_uqpsk_unequal_tx_encoded_q_bits', ...
                            int8(encQ(:)));
                        assignin('base', ...
                            'debug_split_tx_encoded_i_bits', int8(encI(:)));
                        assignin('base', ...
                            'debug_split_tx_encoded_q_bits', int8(encQ(:)));
                        fprintf(['[UQPSK unequal TX] input I/Q=%d/%d, ', ...
                            'encoded I/Q=%d/%d, grouped=%d, layout=', ...
                            '[I1,I2,Q1,...]\n'], ...
                            iLength, qLength, numel(encI), numel(encQ), ...
                            numel(encodedBits));
                    end
                else
                    encodedBits = tmEncode(obj,int8(bits));
                end

                % Modulate the encoded bits
                symbols = tmModulate(obj,encodedBits);
            end

            % Pass the symbols through filter
            if strcmp(obj.PulseShapingFilter,"root raised cosine") && ~any(strcmp(obj.Modulation,{'GMSK','MSK','OQPSK','FM','PCM/PSK/PM','PCM/PM/biphase-L'}))
                if ~isempty(symbols)
                    waveform = complex(obj.pTransmitFilter(symbols).*obj.pGain); % Here casting to complex is needed. Though "symbols" is coming as complex, after filtering, they are becoming real again
                else
                    waveform = complex(zeros(0,1));
                end
            else
                waveform = symbols;
            end
        end

        function resetImpl(obj)
            % Initialize / reset discrete-state properties

            % Reset the system objects that are used if they are defined
            if ~isempty(obj.pTransmitFilter)
                reset(obj.pTransmitFilter);
            end

            if ~isempty(obj.pDiffEnc)
                reset(obj.pDiffEnc);
            end
            if ~isempty(obj.pDiffEncI)
                reset(obj.pDiffEncI);
            end
            if ~isempty(obj.pDiffEncQ)
                reset(obj.pDiffEncQ);
            end

            if ~isempty(obj.pConvEnc)
                reset(obj.pConvEnc);
            end
            if ~isempty(obj.pConvEncI)
                reset(obj.pConvEncI);
            end
            if ~isempty(obj.pConvEncQ)
                reset(obj.pConvEncQ);
            end

            if ~isempty(obj.pConvEnc1)
                reset(obj.pConvEnc1);
            end

            if ~isempty(obj.pConvEnc2)
                reset(obj.pConvEnc2);
            end

            if ~isempty(obj.pMod)
                reset(obj.pMod);
            end

            % Reset the states of the system object
            obj.pInputBuffer = zeros(obj.pK,1,'int8');
            obj.pNumBitsInInputBuffer = 0;
            obj.pCodewordIndex = 1;
            obj.pConvEncState = zeros(6,1,'int8');
            obj.pDiffEncState = zeros(3,1,'int8');
            obj.pSubcarrierPhase = 0;
            obj.pGMSKState = struct('altersymb',int8(1),'PrevLastSymb',int8(1));

            if any(strcmp(obj.ChannelCoding,{'concatenated','convolutional'}))
                obj.pInputBuffer = zeros(obj.pConvEncInLen,1,'int8');
            end
            if any(strcmpi(obj.DataPathMode, ...
                    {'dualIQ','unequalDualIQ'})) && ...
                    strcmp(obj.ChannelCoding,'convolutional')
                obj.pInputBufferI = zeros(obj.pConvEncInLen,1,'int8');
                obj.pInputBufferQ = zeros(obj.pConvEncInLen,1,'int8');
                obj.pNumBitsInInputBufferI = 0;
                obj.pNumBitsInInputBufferQ = 0;
            end

            obj.pModInputBuffer = zeros(round(obj.pNumModInBits(1)),1,'int8');
            obj.pNumBitsInpModInputBuffer = 0;
        end

        function releaseImpl(obj)
            % Release resources, such as file handles
            if ~isempty(obj.pTransmitFilter)
                release(obj.pTransmitFilter);
            end

            if ~isempty(obj.pDiffEnc)
                release(obj.pDiffEnc);
            end
            if ~isempty(obj.pDiffEncI)
                release(obj.pDiffEncI);
            end
            if ~isempty(obj.pDiffEncQ)
                release(obj.pDiffEncQ);
            end

            if ~isempty(obj.pConvEnc)
                release(obj.pConvEnc);
            end
            if ~isempty(obj.pConvEncI)
                release(obj.pConvEncI);
            end
            if ~isempty(obj.pConvEncQ)
                release(obj.pConvEncQ);
            end

            if ~isempty(obj.pConvEnc1)
                release(obj.pConvEnc1);
            end

            if ~isempty(obj.pConvEnc2)
                release(obj.pConvEnc2);
            end

            if ~isempty(obj.pMod)
                release(obj.pMod);
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
            s.SplitPathDebug = obj.SplitPathDebug;
            s.TPCCodeRate = obj.TPCCodeRate;
            s.TPCBlocksPerTF = obj.TPCBlocksPerTF;
            s.TPCInterleaver = obj.TPCInterleaver;
            if isLocked(obj)
                % Save inherited properties
                s.pIsFACM = obj.pIsFACM;
                s.pASM = obj.pASM;
                s.pCSM = obj.pCSM;
                s.pPRNSequence = obj.pPRNSequence;
                s.pPRNSequenceLength = obj.pPRNSequenceLength;
                s.pTurboPuncturePattern = obj.pTurboPuncturePattern;
                s.pTurboInterleaverIndices = obj.pTurboInterleaverIndices;
                s.pLDPCCodeWordLength = obj.pLDPCCodeWordLength;
                s.pInverseCodeRate = obj.pInverseCodeRate;
                s.pInputBuffer = obj.pInputBuffer;
                s.pNumBitsInInputBuffer = obj.pNumBitsInInputBuffer;
                s.pK = obj.pK;
                s.pCodewordIndex = obj.pCodewordIndex;
                s.pHeader = obj.pHeader;
                s.pMaxNumCW = obj.pMaxNumCW;
                s.pSubcarrierPhase = obj.pSubcarrierPhase;
                if strcmp(obj.WaveformSource,'flexible advanced coding and modulation')
                    s.pNumBitsPerSymbol = obj.pNumBitsPerSymbol;
                    s.pInterleavingIndices = obj.pInterleavingIndices;
                    s.pSCCCPuncturePattern2 = obj.pSCCCPuncturePattern2;
                    s.pPLRandomSymbols = obj.pPLRandomSymbols;
                end
                s.pTFLen = obj.pTFLen;
                s.pRadii = obj.pRadii;
                s.pSubcarrierFrequency = obj.pSubcarrierFrequency;
                s.NumInputBits = obj.NumInputBits;
                s.pTransmitFilter = matlab.System.saveObject(obj.pTransmitFilter);
                s.pDiffEnc = matlab.System.saveObject(obj.pDiffEnc);
                if ~isempty(obj.pDiffEncI)
                    s.pDiffEncI = matlab.System.saveObject(obj.pDiffEncI);
                else
                    s.pDiffEncI = [];
                end
                if ~isempty(obj.pDiffEncQ)
                    s.pDiffEncQ = matlab.System.saveObject(obj.pDiffEncQ);
                else
                    s.pDiffEncQ = [];
                end
                s.pConvEnc = matlab.System.saveObject(obj.pConvEnc);
                if ~isempty(obj.pConvEncI)
                    s.pConvEncI = matlab.System.saveObject(obj.pConvEncI);
                else
                    s.pConvEncI = [];
                end
                if ~isempty(obj.pConvEncQ)
                    s.pConvEncQ = matlab.System.saveObject(obj.pConvEncQ);
                else
                    s.pConvEncQ = [];
                end
                s.pConvEnc1 = matlab.System.saveObject(obj.pConvEnc1);
                s.pConvEnc2 = matlab.System.saveObject(obj.pConvEnc2);
                s.pN = obj.pN;
                s.pLDPCGeneratorMatrix = obj.pLDPCGeneratorMatrix;
                s.pConvEncState = obj.pConvEncState;
                s.pDiffEncState = obj.pDiffEncState;
                s.pMod = matlab.System.saveObject(obj.pMod);
                s.pGain = obj.pGain;
                s.pGMSKState = obj.pGMSKState;
                s.pConvEncInLen = obj.pConvEncInLen;
                s.pInputBufferI = obj.pInputBufferI;
                s.pInputBufferQ = obj.pInputBufferQ;
                s.pNumBitsInInputBufferI = obj.pNumBitsInInputBufferI;
                s.pNumBitsInInputBufferQ = obj.pNumBitsInInputBufferQ;
                s.pModInputBuffer = obj.pModInputBuffer;
                s.pNumBitsInpModInputBuffer = obj.pNumBitsInpModInputBuffer;
                s.pNumModInBits = obj.pNumModInBits;
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
            if isfield(s,'SplitPathDebug')
                obj.SplitPathDebug = s.SplitPathDebug;
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
            if wasLocked
                % Save inherited properties
                obj.pIsFACM = s.pIsFACM;
                obj.pASM = s.pASM;
                obj.pCSM = s.pCSM;
                obj.pPRNSequence = s.pPRNSequence;
                obj.pPRNSequenceLength = s.pPRNSequenceLength;
                obj.pTurboPuncturePattern = s.pTurboPuncturePattern;
                obj.pTurboInterleaverIndices = s.pTurboInterleaverIndices;
                obj.pLDPCCodeWordLength = s.pLDPCCodeWordLength;
                obj.pInverseCodeRate = s.pInverseCodeRate;
                obj.pInputBuffer = s.pInputBuffer;
                obj.pNumBitsInInputBuffer = s.pNumBitsInInputBuffer;
                obj.pK = s.pK;
                obj.pCodewordIndex = s.pCodewordIndex;
                obj.pHeader = s.pHeader;
                obj.pMaxNumCW = s.pMaxNumCW;
                obj.pRadii = s.pRadii;
                obj.pSubcarrierFrequency = s.pSubcarrierFrequency;
                obj.NumInputBits = s.NumInputBits;
                obj.pTransmitFilter = matlab.System.loadObject(s.pTransmitFilter);
                obj.pDiffEnc = matlab.System.loadObject(s.pDiffEnc);
                if isfield(s,'pDiffEncI') && ~isempty(s.pDiffEncI)
                    obj.pDiffEncI = matlab.System.loadObject(s.pDiffEncI);
                else
                    obj.pDiffEncI = [];
                end
                if isfield(s,'pDiffEncQ') && ~isempty(s.pDiffEncQ)
                    obj.pDiffEncQ = matlab.System.loadObject(s.pDiffEncQ);
                else
                    obj.pDiffEncQ = [];
                end
                obj.pConvEnc = matlab.System.loadObject(s.pConvEnc);
                if isfield(s,'pConvEncI') && ~isempty(s.pConvEncI)
                    obj.pConvEncI = matlab.System.loadObject(s.pConvEncI);
                else
                    obj.pConvEncI = [];
                end
                if isfield(s,'pConvEncQ') && ~isempty(s.pConvEncQ)
                    obj.pConvEncQ = matlab.System.loadObject(s.pConvEncQ);
                else
                    obj.pConvEncQ = [];
                end
                obj.pConvEnc1 = matlab.System.loadObject(s.pConvEnc1);
                obj.pConvEnc2 = matlab.System.loadObject(s.pConvEnc2);
                obj.pN = s.pN;
                obj.pLDPCGeneratorMatrix = s.pLDPCGeneratorMatrix;
                obj.pConvEncState = s.pConvEncState;
                obj.pDiffEncState = s.pDiffEncState;
                obj.pMod = matlab.System.loadObject(s.pMod);
                obj.pGain = s.pGain;
                obj.pSubcarrierPhase = s.pSubcarrierPhase;
                obj.pGMSKState = s.pGMSKState;
                obj.pConvEncInLen = s.pConvEncInLen;
                if isfield(s,'pInputBufferI'), obj.pInputBufferI = s.pInputBufferI; end
                if isfield(s,'pInputBufferQ'), obj.pInputBufferQ = s.pInputBufferQ; end
                if isfield(s,'pNumBitsInInputBufferI'), obj.pNumBitsInInputBufferI = s.pNumBitsInInputBufferI; end
                if isfield(s,'pNumBitsInInputBufferQ'), obj.pNumBitsInInputBufferQ = s.pNumBitsInInputBufferQ; end
                obj.pModInputBuffer = s.pModInputBuffer;
                obj.pNumBitsInpModInputBuffer = s.pNumBitsInpModInputBuffer;
                obj.pNumModInBits = s.pNumModInBits;
                obj.pTFLen = s.pTFLen;
            end
            % Set public properties and states
            obj.ChannelCoding = s.ChannelCoding;
            loadObjectImpl@satcom.internal.ccsds.tmBase(obj,s,wasLocked);
            if wasLocked && strcmp(obj.WaveformSource,'flexible advanced coding and modulation')
                obj.pNumBitsPerSymbol = s.pNumBitsPerSymbol;
                obj.pInterleavingIndices = s.pInterleavingIndices;
                obj.pSCCCPuncturePattern2 = s.pSCCCPuncturePattern2;
                obj.pPLRandomSymbols = s.pPLRandomSymbols;
            end
        end

        %% Advanced functions
        function validateInputsImpl(obj,bits)
            % Validate inputs to the step method at initialization
            numBits = length(bits);
            coder.internal.errorIf(logical(mod(numBits,obj.NumInputBits)),...
                'satcom:ccsdsTMWaveformGenerator:InvalidTMDataLength');
        end

        function validatePropertiesImpl(obj)
            % Validate related or interdependent property values
            validatePropertiesImpl@satcom.internal.ccsds.tmBase(obj);
        end

        function processTunedPropertiesImpl(obj)
            % Perform actions when tunable properties change
            % between calls to the System object
            processTunedPropertiesImpl@satcom.internal.ccsds.tmBase(obj);
            if obj.pIsFACM
                k = obj.pK; % pK is updated in the tmBase class

                if obj.pNumBitsInInputBuffer<=k
                    bufferBits = obj.pInputBuffer(1:obj.pNumBitsInInputBuffer);
                    obj.pInputBuffer = zeros(k,1,'int8');
                    obj.pInputBuffer(1:obj.pNumBitsInInputBuffer) = bufferBits;
                end
            end
        end

        function flag = isInactivePropertyImpl(obj,prop)
            flag = false;
            if strcmp(obj.WaveformSource, 'flexible advanced coding and modulation')
                isFACM = true;
            else
                isFACM = false;
            end
            smtfFlag = isFACM || (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF);
            if strcmp(prop,'ChannelCoding')
                flag = isFACM;
            elseif strcmp(prop,'NumBytesInTransferFrame')
                flag = any(strcmp(obj.ChannelCoding,{'RS','concatenated','turbo'}));
                if strcmp(obj.ChannelCoding,'LDPC')
                    flag = ~obj.IsLDPCOnSMTF;
                end
                if smtfFlag
                    flag = false;
                end
            elseif strcmp(prop,'ConvolutionalCodeRate')
                flag = ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) || isFACM;
            elseif strcmp(prop,'ConvolutionalG1G2Mode')
                flag = ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) || isFACM;
            elseif strcmp(prop,'CodeRate')
                flag = ~any(strcmp(obj.ChannelCoding,{'turbo','LDPC'})) || isFACM;
            elseif strcmp(prop,'TPCCodeRate')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCBlocksPerTF')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif strcmp(prop,'TPCInterleaver')
                flag = ~strcmp(obj.ChannelCoding,'TPC') || isFACM;
            elseif any(strcmp(prop,{'RandomizerEnabled','RandomizerFECPosition','DataPathMode'}))
                flag = smtfFlag;
            elseif strcmp(prop,'HasASM')
                flag = smtfFlag;
            elseif any(strcmp(prop,{'ASMLength','ASMHex'}))
                flag = ~obj.HasASM || smtfFlag;
            elseif strcmp(prop,'NumBitsInInformationBlock')
                flag = ~any(strcmp(obj.ChannelCoding,{'LDPC','turbo'})) || isFACM;
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
            elseif strcmp(prop,'IsLDPCOnSMTF')
                flag = ~strcmp(obj.ChannelCoding,'LDPC') || isFACM;
            elseif strcmp(prop,'LDPCCodeblockSize')
                flag = ~(strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF) || isFACM;
            elseif strcmp(prop,'Modulation')
                flag = isFACM;
            elseif strcmp(prop,'PulseShapingFilter')
                flag = any(strcmp(obj.Modulation,{'GMSK','MSK','FM','OQPSK','PCM/PSK/PM','PCM/PM/biphase-L'})) && ~isFACM;
            elseif strcmp(prop,'RolloffFactor')
                if any(strcmp(obj.Modulation,{'GMSK','MSK','PCM/PSK/PM','PCM/PM/biphase-L','OQPSK'})) && ~isFACM
                    flag = true;
                    if strcmp(obj.Modulation,'OQPSK')
                        flag = false; % Visible in case of OQPSK
                    end
                else
                    flag = strcmp(obj.PulseShapingFilter,"none");
                end
            elseif strcmp(prop,'SamplesPerSymbol')
                if any(strcmp(obj.Modulation,{'GMSK','MSK','PCM/PSK/PM','PCM/PM/biphase-L','FM','OQPSK'})) && ~isFACM
                    flag = false;
                else
                    flag = strcmp(obj.PulseShapingFilter,"none");
                end
            elseif strcmp(prop,'BandwidthTimeProduct')
                flag = ~any(strcmp(obj.Modulation,{'GMSK'})) || isFACM;
            elseif strcmp(prop,'ModulationEfficiency')
                flag = ~strcmp(obj.Modulation,'4D-8PSK-TCM') || isFACM;
            elseif any(strcmp(prop,{'SubcarrierWaveform','SymbolRate','SubcarrierToSymbolRateRatio'}))
                flag = ~strcmp(obj.Modulation,'PCM/PSK/PM') || isFACM;
            elseif strcmp(prop,'PCMFormat')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','BPSK','QPSK','8PSK', ...
                    'OQPSK','16QAM','32QAM','16APSK','32APSK'})) || isFACM;
            elseif strcmp(prop,'ModulationIndex')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','PCM/PM/biphase-L'})) || isFACM;
            elseif strcmp(prop,'FilterSpanInSymbols')
                if any(strcmp(obj.Modulation,{'GMSK','MSK','PCM/PSK/PM','PCM/PM/biphase-L','OQPSK'})) && ~isFACM
                    flag = true;
                    if strcmp(obj.Modulation,'OQPSK')
                        flag = false; % Visible in case of OQPSK
                    end
                else
                    flag = strcmp(obj.PulseShapingFilter,"none");
                end
            elseif any(strcmp(prop,{'ACMFormat','ScramblingCodeNumber', 'HasPilots'}))
                flag = ~isFACM;
            elseif strcmp(prop,'MinNumTransferFrames')
                flag = ~smtfFlag;
            end
        end

        function s = infoImpl(obj)
            %info Returns physical layer information about CCSDS TM
            %waveform generation
            %   S = info(OBJ) returns a structure containing physical layer
            %   parameters, S, about the CCSDS TM waveform generation. A
            %   description of the fields and their values is as follows:
            %
            %   ActualCodeRate      - Numeric value of the code rate of the
            %                         channel coding scheme that is used
            %                         for generating the CCSDS TM waveform.
            %   NumBitsPerSymbol    - Number of bits per modulated symbol.
            %                         For example, in QPSK modulation, this
            %                         property value is 2.
            %   SubcarrierFrequency - Subcarrier frequency when
            %                         "PCM/PSK/PM" modulation scheme is
            %                         used. For other modulation schemes,
            %                         this property is not applicable and
            %                         returns empty value as output in
            %                         such cases.

            if strcmp(obj.WaveformSource,'flexible advanced coding and modulation')
                k = obj.K_Values(obj.ACMFormat);
                m = obj.m_Values(obj.ACMFormat);
                s.ActualCodeRate = k/(8100*m);
                s.NumBitsPerSymbol = m;
                s.SubcarrierFrequency = [];
            else
                invr = getInverseCodeRate(obj);
                s = struct('ActualCodeRate',1/invr);
                if strcmp(obj.ChannelCoding,'concatenated')
                    if obj.IsRSMessageShortened
                        rsCodeRate = double(obj.RSShortenedMessageLength)/(obj.pRSParams.n-double(obj.RSMessageLength)+double(obj.RSShortenedMessageLength));
                    else
                        rsCodeRate = double(obj.RSMessageLength)/obj.pRSParams.n;
                    end
                    s.ActualCodeRate = rsCodeRate/invr;
                elseif strcmp(obj.ChannelCoding,'none')
                    s.ActualCodeRate = 1;
                elseif strcmp(obj.ChannelCoding,'RS')
                    if obj.IsRSMessageShortened
                        s.ActualCodeRate = double(obj.RSShortenedMessageLength)/(obj.pRSParams.n-double(obj.RSMessageLength)+double(obj.RSShortenedMessageLength));
                    else
                        s.ActualCodeRate = double(obj.RSMessageLength)/obj.pRSParams.n;
                    end
                elseif strcmp(obj.ChannelCoding,'TPC')
                    s.ActualCodeRate = localTPCEffectiveRate(obj.TPCCodeRate);
                    s.TPCBlocksPerTF = localPositiveInteger(obj.TPCBlocksPerTF, 1);
                    s.TPCInfoBitsPerTransferFrame = localTPCPayloadBits(obj.TPCCodeRate) * s.TPCBlocksPerTF;
                    syncLen = localConfiguredASMLength(obj) * double(logical(obj.HasASM));
                    s.TPCCodedTransferFrameBits = syncLen + 64*64*s.TPCBlocksPerTF;
                end
                switch(obj.Modulation)
                    case 'QPSK'
                        m = 2;
                    case '8PSK'
                        m = 3;
                     % additional 16QAM
                    case '16QAM'
                        m = 4;
                     % additional 32QAM
                    case '32QAM'
                        m = 5;
                    case '16APSK'
                        m = 4;
                    case '32APSK'
                        m = 5;
                    case 'UQPSK'
                        m = 1.5;
                    case '4D-8PSK-TCM'
                        m = double(obj.ModulationEfficiency);
                    case 'OQPSK'
                        m = 2;
                    case 'FM'
                        m = 1;
                    otherwise % case 'PCM/PM/biphase-L', 'PCM/PSK/PM', 'GMSK', 'BPSK'
                        m = 1;
                end
                s.NumBitsPerSymbol = m;
                s.SubcarrierFrequency = [];
                if strcmp(obj.Modulation,'PCM/PSK/PM')
                    s.SubcarrierFrequency = double(obj.SubcarrierToSymbolRateRatio) * double(obj.SymbolRate);
                end
            end
        end
    end

    methods(Static, Access=protected)
        function groups = getPropertyGroupsImpl
            genprops = {'WaveformSource',...
                'ACMFormat',...
                'NumBytesInTransferFrame',...
                'RandomizerEnabled',...
                'RandomizerFECPosition',...
                'DataPathMode',...
                'SplitPathDebug',...
                'HasASM',...
                'ASMLength',...
                'ASMHex',...
                'PCMFormat'};

            encProps = {'ChannelCoding',...
                'NumBitsInInformationBlock',...
                'ConvolutionalCodeRate',...
                'ConvolutionalG1G2Mode',...
                'CodeRate',...
                'TPCCodeRate',...
                'TPCBlocksPerTF',...
                'TPCInterleaver',...
                'RSMessageLength',...
                'RSInterleavingDepth',...
                'IsRSMessageShortened',...
                'RSShortenedMessageLength',...
                'IsLDPCOnSMTF',...
                'LDPCCodeblockSize'};

            modProps = {'Modulation',...
                'PulseShapingFilter',...
                'RolloffFactor',...
                'FilterSpanInSymbols',...
                'BandwidthTimeProduct',...
                'ModulationEfficiency',...
                'SubcarrierWaveform',...
                'ModulationIndex',...
                'SymbolRate',...
                'SubcarrierToSymbolRateRatio',...
                'SamplesPerSymbol',...
                'HasPilots',...
                'ScramblingCodeNumber'};

            readonlyprops = {'NumInputBits',...
                'MinNumTransferFrames'};

            encoderGroupTitle = "Channel coding";
            modulationGroupTitle = "Digital modulation and filter";
            readonlyGroupTitle = "Read-only";

            generalGroup = matlab.system.display.SectionGroup('PropertyList', genprops);
            encoderGroup = matlab.system.display.SectionGroup('Title', ...
                encoderGroupTitle, 'PropertyList', encProps);
            encoderGroup.IncludeInShortDisplay = true;
            modulationGroup = matlab.system.display.SectionGroup('Title', ...
                modulationGroupTitle, 'PropertyList', modProps);
            modulationGroup.IncludeInShortDisplay = true;
            readonlyGroup = matlab.system.display.SectionGroup('Title', ...
                readonlyGroupTitle, 'PropertyList', readonlyprops);

            groups = [generalGroup encoderGroup modulationGroup readonlyGroup];
        end
    end

    methods % get and set methods
        function l = get.NumInputBits(obj)
            l = getNumBytesInTransferFrame(obj)*8;
            if strcmpi(obj.DataPathMode, 'dualIQ')
                l = 2*l;
            elseif strcmpi(obj.DataPathMode, 'unequalDualIQ')
                l = 3*l;
            end
        end

        function n = get.MinNumTransferFrames(obj)
            if strcmp(obj.WaveformSource,'flexible advanced coding and modulation') || (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF)
                if strcmp(obj.WaveformSource, 'flexible advanced coding and modulation')
                    k = obj.K_Values(obj.ACMFormat);
                else % LDPC on SMTF
                    k = double(obj.NumBitsInInformationBlock);
                end
                asmLen = localConfiguredASMLength(obj);
                n = ceil(k/(double(logical(obj.HasASM))*asmLen+getNumBytesInTransferFrame(obj)*8));
            else
                n = 1;
            end
        end
    end

    methods(Access = private)
        function enc = createConvEncoder(obj)
            convTrellis = ccsdsTMConvolutionalOutputTrellis( ...
                obj.ConvolutionalCodesTrellis, obj.ConvolutionalG1G2Mode, ...
                obj.ConvolutionalCodeRate);
            switch obj.ConvolutionalCodeRate
                case '1/2'
                    enc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis);
                case '2/3'
                    enc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                        'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1]);
                case '3/4'
                    enc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                        'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0]);
                case '5/6'
                    enc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                        'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0;0;1;1;0]);
                otherwise % case '7/8'
                    enc = comm.ConvolutionalEncoder('TrellisStructure',convTrellis,...
                        'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;0;1;0;1;1;0;0;1;1;0]);
            end
        end

        function y = convEncodeForRail(obj,bits,rail)
            switch upper(char(rail))
                case 'I'
                    y = obj.pConvEncI(bits);
                case 'Q'
                    y = obj.pConvEncQ(bits);
                otherwise
                    y = obj.pConvEnc(bits);
            end
        end

        function diffEnc = diffEncoderForRail(obj,rail)
            switch upper(char(rail))
                case 'I'
                    diffEnc = obj.pDiffEncI;
                case 'Q'
                    diffEnc = obj.pDiffEncQ;
                otherwise
                    diffEnc = obj.pDiffEnc;
            end
        end

        function [bits, n] = updateInputBufferForRail(obj,u,rail)
            if any(strcmpi(obj.DataPathMode, ...
                    {'dualIQ','unequalDualIQ'})) && ...
                    strcmp(obj.ChannelCoding,'convolutional')
                switch upper(char(rail))
                    case 'I'
                        [bits,n,railBuffer,railNumBits] = ...
                            localUpdateBufferedBits(obj.pInputBufferI, obj.pNumBitsInInputBufferI, u, obj.pConvEncInLen);
                        obj.pInputBufferI = railBuffer;
                        obj.pNumBitsInInputBufferI = railNumBits;
                    case 'Q'
                        [bits,n,railBuffer,railNumBits] = ...
                            localUpdateBufferedBits(obj.pInputBufferQ, obj.pNumBitsInInputBufferQ, u, obj.pConvEncInLen);
                        obj.pInputBufferQ = railBuffer;
                        obj.pNumBitsInInputBufferQ = railNumBits;
                    otherwise
                        [bits,n] = updateInputBuffer(obj,u);
                end
            else
                [bits,n] = updateInputBuffer(obj,u);
            end
        end

        function encoded = tmEncode(obj,bits,rail)
            if nargin < 3 || isempty(rail)
                rail = 'M';
            end
            % TM synchronization and channel coding
            HasASM = obj.HasASM;
            tfl = obj.pTFLen*8;
            numTF = length(bits)/tfl;

            randomizerEnabled = obj.RandomizerEnabled;
            railPathMode = obj.DataPathMode;
            if any(strcmpi(railPathMode, {'dualIQ','unequalDualIQ'}))
                railPathMode = 'single';
            end

            switch(obj.ChannelCoding)
                case 'none'
%                     if obj.RandomizerEnabled
                    if randomizerEnabled
                        randomized = bitxor(bits,repmat(obj.pPRNSequence,numTF,1));
                    else
                        randomized = bits;
                    end
                    if HasASM
                        trandbits = reshape(randomized, tfl, numTF);
                        encoded1 = [repmat(obj.pASM, 1, numTF); trandbits];
                    else
                        encoded1 = randomized;
                    end
                    encoded = encoded1(:);
                case 'RS'
                    n = obj.pRSParams.n;
                    k = obj.pRSParams.k;
                    s = obj.pRSParams.s;
                    i = obj.pRSParams.i;
                    numBitsInCADU = 8*i*(n-k+s)+HasASM*length(obj.pASM);
                    encoded = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tbits = bits((itf-1)*tfl+1:itf*tfl);
                        % 后解扰 就是前加扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                            if strcmpi(railPathMode, 'single')
                                tbits = bitxor(tbits, obj.pPRNSequence(1:tfl));

                            end
                        end
%                         编码
                        cw = int8(ccsdsRSEncode(logical(tbits),k,i,s));
                        % 前解扰 就是后加扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                            if strcmpi(railPathMode, 'single')
                                randomized = bitxor(cw,obj.pPRNSequence);

                            end
                        else
                            randomized = cw;
                        end

                        if HasASM
                            code = [obj.pASM; randomized];
                        else
                            code = randomized;
                        end
                        encoded((itf-1)*numBitsInCADU+1:itf*numBitsInCADU) = code;
                    end
                case 'convolutional'
                    % 后解扰
                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                        if strcmpi(railPathMode, 'single')
                            randomized = bitxor(bits,repmat(obj.pPRNSequence,numTF,1));

                        end
                    else
                        randomized = bits;
                    end

                    if HasASM
                        trandbits = reshape(randomized, tfl, numTF);
                        tcadu = [repmat(obj.pASM,1,numTF); trandbits];
                    else
                        tcadu = randomized;
                    end
                    cadu = tcadu(:);

                    [encin,numcw] = updateInputBufferForRail(obj,cadu,rail);
                    bLen = length(encin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pConvEncInLen,numcw);
                    symIdx = reshape(1:bLen*obj.pInverseCodeRate,obj.pInverseCodeRate*bLen/numcw,numcw);
                    encodedTemp = int8(zeros(bLen*obj.pInverseCodeRate,1));
                    for iSlice = 1:numcw
                        tempbits = encin(indices(:,iSlice));
                        if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            % Refer section 3.3.3 of [1], which specifies
                            % that differential PCM coding should be done before
                            % convolutional encoder.
                            tfullcadu = localPCMDifferentialEncode(diffEncoderForRail(obj,rail), tempbits, obj.PCMFormat);
                        else % Case of NRZ-L
                            tfullcadu = tempbits;
                        end
                        encodedTemp(symIdx(:,iSlice)) = convEncodeForRail(obj,tfullcadu,rail);
                    end
                    % G1/G2 ordering and the optional second-stream
                    % inversion are embedded in the configured trellis.
                    % This keeps the convention correct before puncturing.
                    encoded = encodedTemp(:);
                case 'concatenated'
                    n = 255;
                    k = obj.pRSParams.k;
                    s = obj.pRSParams.s;
                    i = obj.pRSParams.i;
                    numBitsInCADU = 8*i*(n-k+s)+HasASM*length(obj.pASM);
                    cadu = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tbits = bits((itf-1)*tfl+1:itf*tfl);
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                            if strcmpi(railPathMode, 'single')
                                tbits = bitxor(tbits, obj.pPRNSequence(1:tfl));

                            end
                        end
                        cw = int8(ccsdsRSEncode(logical(tbits),k,i,s));
                        randomized = cw;
                        if HasASM
                            code = int8([obj.pASM; randomized]);
                        else
                            code = int8(randomized);
                        end
                        cadu((itf-1)*numBitsInCADU+1:itf*numBitsInCADU) = code;
                    end
                    [encin,numcw] = updateInputBuffer(obj,cadu);
                    bLen = length(encin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pConvEncInLen,numcw);
                    symIdx = reshape(1:bLen*obj.pInverseCodeRate,obj.pInverseCodeRate*bLen/numcw,numcw);
                    encodedTemp = int8(zeros(bLen*obj.pInverseCodeRate,1));
                    for iSlice = 1:numcw
                        tempbits = encin(indices(:,iSlice));
                        if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            % Refer section 3.3.3 of [1] which specifies
                            % that differential PCM coding should be done before
                            % convolutional encoder.
                            tfullcadu = localPCMDifferentialEncode(obj.pDiffEnc, tempbits, obj.PCMFormat);
                        else % Case of NRZ-L
                            tfullcadu = tempbits;
                        end
                        encodedTemp(symIdx(:,iSlice)) = obj.pConvEnc(tfullcadu);
                    end
                    encoded = encodedTemp;
                case 'turbo'
                    numBitsInCADU = obj.pInverseCodeRate*(tfl+4)+HasASM*length(obj.pASM);
                    encoded = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tbits = bits((itf-1)*tfl+1:itf*tfl);
%                         后解扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                            if strcmpi(railPathMode, 'single')
                                tbits = bitxor(tbits, obj.pPRNSequence(1:tfl));

                            end
                        end

                        % Split mode calls tmEncode once per rail. Resetting
                        % the terminated constituent encoders per frame keeps
                        % I/Q rail state independent and also preserves the
                        % ordinary merge framing semantics.
                        reset(obj.pConvEnc1);
                        reset(obj.pConvEnc2);
                        y1 = obj.pConvEnc1(tbits);
                        y2 = obj.pConvEnc2(tbits(obj.pTurboInterleaverIndices));

                        % Reshape the bits in y1 and y2 into a matrix form so
                        % that they can be concatenated. Each one is reshaped
                        % into a matrix with number of rows equal to the number
                        % of output bits per input bit of a given convolutional
                        % encoder and number of columns equal to the number of
                        % input bits. Number of rows here will be 4 for CCSDS
                        % standard. So, keeping that value as constant in the
                        % variable pN.
                        y1R = reshape(y1, obj.pN, tfl+4);
                        y2R = reshape(y2, obj.pN, tfl+4); % 4 is for the tail bits processing

                        y = [y1R; y2R(2:end,:)]; % First row of y2R is the interleaved data itself which is not an output as per CCSDS standard, [1]
                        encodedWithoutPuncturing = y(:); % This includes tail bits too

                        % Puncture the codeword as per the rate of the code.
                        cw = encodedWithoutPuncturing(obj.pTurboPuncturePattern);
                        % 前解扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                            if strcmpi(railPathMode, 'single')
                                randomized = bitxor(cw,obj.pPRNSequence);

                            end
                        else
                            randomized = cw;
                        end
                        if HasASM
                            code = [obj.pASM; randomized];
                        else
                            code = randomized;
                        end
                        encoded((itf-1)*numBitsInCADU+1:itf*numBitsInCADU) = code;
                    end
                case 'TPC'
                    if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                        if strcmpi(railPathMode, 'single')
                            prn = repmat(obj.pPRNSequence, ceil(numel(bits)/numel(obj.pPRNSequence)), 1);
                            randomized = bitxor(bits, prn(1:numel(bits)));

                        end
                    else
                        randomized = bits;
                    end
                    encoded = ccsdsTPCEncodeBits(randomized, HasASM, obj.pASM, ...
                        'TPCCodeRate', obj.TPCCodeRate, ...
                        'TPCBlocksPerTF', obj.TPCBlocksPerTF, ...
                        'TPCInterleaver', obj.TPCInterleaver);
                case 'LDPC'
                    numBitsInCADU = obj.pInverseCodeRate*tfl+HasASM*length(obj.pASM);
                    encoded = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tf = bits((itf-1)*tfl+1:itf*tfl);
                        %后解扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'beforeEncoding')
                            if strcmpi(railPathMode, 'single')
                                tf = bitxor(tf, obj.pPRNSequence(1:tfl));

                            end
                        end

                        cw = int8(satcom.internal.ccsds.tmldpcEncode(tf(:),obj.pLDPCGeneratorMatrix));
                        %前解扰
                        if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                            if strcmpi(railPathMode, 'single')
                                randomized = bitxor(cw,obj.pPRNSequence);

                            end
                        else
                            randomized = cw;
                        end

                        if HasASM
                            code = [obj.pASM; randomized];
                        else
                            code = randomized;
                        end
                        encoded((itf-1)*numBitsInCADU+1:itf*numBitsInCADU) = code;
                    end
            end

            if randomizerEnabled && strcmpi(obj.RandomizerFECPosition, 'afterEncoding')
                if strcmpi(railPathMode, 'single')
                    if any(strcmp(obj.ChannelCoding, {'convolutional','concatenated','TPC'}))
                        encodedASMLength = localEncodedASMLength( ...
                            obj.ChannelCoding, length(obj.pASM)*HasASM, obj.pInverseCodeRate);
                        encodedFrameLength = floor(numel(encoded) / max(1, numTF));
                        encoded = localFramePayloadXor( ...
                            encoded, encodedFrameLength, encodedASMLength, []);
                    end

                end
            end
        end

        function waveform = tmModulate(obj,bits)
            %tmModulate Modulate the bits to symbols
            [modin,n] = updateModInputBuffer(obj,bits);
            sps = double(obj.SamplesPerSymbol);
            switch(obj.Modulation)
                case 'BPSK'
                    bLen = length(modin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);
                    w = complex(zeros(bLen,1));
                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        w(indices(:,iSlice)) = complex(double(2*tbits-1));
                    end
                    waveform = complex(w);
                case 'QPSK'
                    bLen = length(modin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);
                    waveform = complex(zeros(bLen/2,1));
                    symIdx = reshape(1:bLen/2,obj.pNumModInBits/2,n);
                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        symTemp = double(1 - 2*(reshape(tbits, 2, length(tbits)/2)));
                        waveform(symIdx(:,iSlice)) = (1/sqrt(2))*(symTemp(1,:)+ 1j*symTemp(2,:)).';
                    end
                case '8PSK'
                    bLen = length(modin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);
                    waveform = complex(zeros(bLen/3,1));
                    symIdx = reshape(1:bLen/3,obj.pNumModInBits/3,n);
                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        waveform(symIdx(:,iSlice)) = obj.pMod(double(tbits));
                    end
                % additional 16QAM
                case '16QAM'
                    bLen = length(modin);
                    bitsPerSymbol = 4;
                    qamM = 16;

                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);

                    waveform = complex(zeros(bLen/bitsPerSymbol,1));
                    symIdx = reshape(1:bLen/bitsPerSymbol, ...
                        obj.pNumModInBits/bitsPerSymbol,n);

                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end

                        waveform(symIdx(:,iSlice)) = qammod(double(tbits), qamM, ...
                            'InputType','bit', ...
                            'UnitAveragePower',true);
                    end

                    % additional 32QAM
                case '32QAM'
                    bLen = length(modin);
                    bitsPerSymbol = 5;
                    qamM = 32;

                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);

                    waveform = complex(zeros(bLen/bitsPerSymbol,1));
                    symIdx = reshape(1:bLen/bitsPerSymbol, ...
                        obj.pNumModInBits/bitsPerSymbol,n);

                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end

                        waveform(symIdx(:,iSlice)) = qammod(double(tbits), qamM, ...
                            'InputType','bit', ...
                            'UnitAveragePower',true);
                    end
                case {'16APSK','32APSK'}
                    bLen = length(modin);
                    if strcmp(obj.Modulation,'16APSK')
                        bitsPerSymbol = 4;
                    else
                        bitsPerSymbol = 5;
                    end

                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);

                    waveform = complex(zeros(bLen/bitsPerSymbol,1));
                    symIdx = reshape(1:bLen/bitsPerSymbol, ...
                        obj.pNumModInBits/bitsPerSymbol,n);

                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end

                        waveform(symIdx(:,iSlice)) = localTMAPSKModulate(tbits, obj.Modulation);
                    end
                    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
                        txAPSK_samples = waveform(1:min(2000,end));
                        assignin('base','debug_apsk_tx_symbols', txAPSK_samples);
                        radiiRounded = unique(round(abs(waveform(:))*1000)/1000);
                        fprintf('[APSK TX] mod=%s, symbols=%d, mean|s|^2=%.4f, unique radii=%d\n', ...
                            obj.Modulation, length(waveform), mean(abs(waveform).^2), length(radiiRounded));
                    end
                    if obj.HasTMAPSKPilots
                        dataSymbolCount = numel(waveform);
                        waveform = localInsertTMAPSKPilots(waveform, ...
                            obj.TMAPSKPilotInterval, obj.TMAPSKPilotLength, ...
                            obj.TMAPSKPilotPreambleLength);
                        if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
                            fprintf('[APSK TX pilots] data=%d, withPilots=%d, preamble=%d, interval=%d, pilotLen=%d\n', ...
                                dataSymbolCount, numel(waveform), obj.TMAPSKPilotPreambleLength, ...
                                obj.TMAPSKPilotInterval, obj.TMAPSKPilotLength);
                        end
                    end
                case 'UQPSK'
                    bLen = length(modin);
                    temp = 1:bLen;

                    rRatio = 2;
                    aRatio = 2;
                    bitsPerGroup = rRatio + 1;   % 3 bit 涓€缁?
                    indices = reshape(temp, obj.pNumModInBits, n);

                    % 姣?3 bit -> 2 涓鍙凤紝鎵€浠ヨ緭鍑虹鍙锋暟 = bLen/3*2
                    waveform = complex(zeros(bLen / bitsPerGroup * rRatio, 1));
                    symIdx = reshape(1:(obj.pNumModInBits / bitsPerGroup * rRatio * n), ...
                        obj.pNumModInBits / bitsPerGroup * rRatio, n);

                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end

                        waveform(symIdx(:,iSlice)) = uqpskMapBitsLocal(tbits, rRatio, aRatio);
                    end
                case 'FM'
                    bLen = length(modin);
                    temp = 1:bLen;
                    indices = reshape(temp, obj.pNumModInBits, n);

                    tbitsAll = zeros(bLen, 1, 'int8');
                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        tbitsAll(indices(:,iSlice)) = int8(tbits(:));
                    end
                    fmParams = struct();
                    fmParams.symbolRate = 1;
                    fmParams.fs = double(obj.SamplesPerSymbol);
                    fmParams.sps = double(obj.SamplesPerSymbol);
                    fmParams.RolloffFactor = double(obj.RolloffFactor);
                    fmParams.TZZS = 0.715;
                    fmParams.fmPayloadBitsPerFrame = numel(tbitsAll);
                    waveform = ccsdsFMModulateBits(tbitsAll, fmParams);
                case '4D-8PSK-TCM'
                    if coder.target('MATLAB')
                         if evalin('base','exist(''DEBUG_4D_TX_MODIN'',''var'') && logical(DEBUG_4D_TX_MODIN)')
                             assignin('base','debug4D_tx_modin', int8(modin(:)));
                             assignin('base','debug4D_tx_eff', double(obj.ModulationEfficiency));
                             assignin('base','debug4D_tx_convState_before', obj.pConvEncState);
                             assignin('base','debug4D_tx_diffState_before', obj.pDiffEncState);

                             fprintf('[TX 4D debug] modinLen=%d, eff=%.2f, groupBits=%d, remainder=%d\n', ...
                                 length(modin), ...
                                 double(obj.ModulationEfficiency), ...
                                 round(4*double(obj.ModulationEfficiency)), ...
                                 mod(length(modin), round(4*double(obj.ModulationEfficiency))));

                             fprintf('[TX 4D debug] convBefore=%s, diffBefore=%s\n', ...
                                 mat2str(obj.pConvEncState(:).'), ...
                                 mat2str(obj.pDiffEncState(:).'));

                             fprintf('[TX 4D debug] first 64 modin bits:\n');
                             disp(double(modin(1:min(64,end))).');
                         end

                         [waveform, obj.pConvEncState, obj.pDiffEncState] = ...
                             satcom.internal.ccsds.cg_fourD8PSKTCMMod_int8( ...
                             modin, double(obj.ModulationEfficiency), ...
                             obj.pConvEncState, obj.pDiffEncState);

                         if evalin('base','exist(''DEBUG_4D_TX_MODIN'',''var'') && logical(DEBUG_4D_TX_MODIN)')
                             assignin('base','debug4D_tx_symbols', complex(waveform(:)));
                             assignin('base','debug4D_tx_convState_after', obj.pConvEncState);
                             assignin('base','debug4D_tx_diffState_after', obj.pDiffEncState);

                             fprintf('[TX 4D debug] convAfter=%s, diffAfter=%s\n', ...
                                 mat2str(obj.pConvEncState(:).'), ...
                                 mat2str(obj.pDiffEncState(:).'));
                         end
                        %%

%                         [waveform, obj.pConvEncState, obj.pDiffEncState] = satcom.internal.ccsds.cg_fourD8PSKTCMMod_int8(modin, double(obj.ModulationEfficiency), obj.pConvEncState, obj.pDiffEncState);
                    else
                        [waveform, obj.pConvEncState, obj.pDiffEncState] = satcom.internal.ccsds.fourD8PSKTCMMod(modin, double(obj.ModulationEfficiency), obj.pConvEncState, obj.pDiffEncState);
                    end
                case 'MSK'
                    % 标准 MSK，不执行 GMSK 专用预编码
                    bLen = length(modin);

                    temp = 1:bLen;
                    indices = reshape(temp, obj.pNumModInBits, n);

                    symIdx = reshape( ...
                        1:bLen*sps, ...
                        sps*obj.pNumModInBits, ...
                        n);

                    waveform = complex(zeros(bLen*sps, 1));

                    for iSlice = 1:n
                        inputBits = logical(modin(indices(:, iSlice)));

                        waveform(symIdx(:, iSlice)) = ...
                            obj.pMod(inputBits);
                    end
                case 'GMSK'
                    % Pre-code the bits before passing through GMSK modulator. Refer
                    % figure 2.4.17A-1 in [2].
                    dbits = 2*modin-1;
                    bLen = length(dbits);
                    numHalfBits = bLen/2;
                    altrsym = cast(repmat([obj.pGMSKState.altersymb;-1*obj.pGMSKState.altersymb],floor(numHalfBits),1),class(dbits));
                    dbits(1:end)=([obj.pGMSKState.PrevLastSymb;dbits(1:end-1)].*dbits(1:end)).*altrsym(1:end);
                    obj.pGMSKState.PrevLastSymb = 2*modin(end)-1;

                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);
                    symIdx = reshape(1:bLen*sps,sps*obj.pNumModInBits,n);
                    waveform = complex(zeros(bLen*sps,1));
                    for iSlice = 1:n
                        tempsym = dbits(indices(:,iSlice));
                        waveform(symIdx(:,iSlice)) = obj.pMod(tempsym);
                    end
                case 'OQPSK'
                    bLen = length(modin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pNumModInBits,n);
                    waveform = complex(zeros(sps*bLen/2,1));
                    symIdx = reshape(1:bLen*sps/2,sps*obj.pNumModInBits/2,n);
                    for iSlice = 1:n
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                            tbits = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        waveform(symIdx(:,iSlice)) = obj.pMod(tbits)/sqrt(sps/2).*obj.pGain;
                    end
                case 'PCM/PSK/PM'
                    if any(strcmp(obj.ChannelCoding,{'convolutional', 'concatenated'}))
                        sig = satcom.internal.ccsds.lineEncode(modin,'NRZ-L',sps);
                    else
                        bLen = length(modin);
                        temp = 1:bLen;
                        indices = reshape(temp,obj.pNumModInBits,n);
                        dbits = zeros(bLen,1);
                        for iSlice = 1:n % So that variable number of bits are not passed into differential encoder even if input size change
                            if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
                                dbits(indices(:,iSlice)) = localPCMDifferentialEncode(obj.pDiffEnc, modin(indices(:,iSlice)), obj.PCMFormat);
                            else
                                dbits(indices(:,iSlice)) = modin(indices(:,iSlice));
                            end
                        end
                        a = repmat(dbits,1,sps).';
                        sig = double(2*a(:)-1);
                    end
                    % Subcarrier modulation
                    modidx = double(obj.ModulationIndex);
                    R = double(obj.SymbolRate);
                    Fc = obj.pSubcarrierFrequency;
                    Fs = sps*R;
                    T = length(modin)/R;
                    if strcmp(obj.SubcarrierWaveform, 'sine')
                        t = (obj.pSubcarrierPhase:(1/Fs):obj.pSubcarrierPhase+T-(1/Fs)).';
                        obj.pSubcarrierPhase = obj.pSubcarrierPhase+T;
                        x = sin(2*pi*Fc*t);
                        y = sig.*x;

                        % Waveform generation
                        I = sin(modidx*y);
                        Q = -1*cos(modidx*y);
                    else
                        % Square wave Subcarrier waveform
                        t = (0:(1/Fs):T-(1/Fs)).';
                        delta = min(t(t~=0))*1e-8;
                        t = t + delta; % Add delta to take t+ value for proper square wave value
                        x = square(2*pi*Fc*t);
                        y = sig.*x;

                        I = y*sin(modidx);
                        Q = -1*cos(modidx);
                    end
                    waveform = I+1j*Q;
                otherwise % case 'PCM/PM/biphase-L'
                    % Line coded signal
                    sig = satcom.internal.ccsds.lineEncode(bits,'BIPHASE-L',sps);
                    % Waveform generation
                    modidx = double(obj.ModulationIndex);
                    I = sig*sin(modidx);
                    Q = -1*cos(modidx);
                    waveform = I+1j*Q;
            end
        end

        function [bits, n] = updateInputBuffer(obj,u)
            %updateInputBuffer Updates the bits in the input buffer
            %   [BITS, N] = updateInputBuffer(OBJ,U) fills the pInputBuffer
            %   property that is there in OBJ with the received bits in U.
            %   BITS contains integer number of length of OBJ.pInputBuffer.
            %   N is the number of slices that can be formed with the
            %   already existing bits in OBJ.pInputBuffer and the input, U.
            %   After these slices are formed, OBJ.pInputBuffer is filled
            %   with the left out bits. Number of bits in the input buffer
            %   at the end is indicated by OBJ.pNumBitsInInputBuffer.
            k = obj.pTFLen*8;
            if strcmp(obj.WaveformSource, 'flexible advanced coding and modulation')
                k = obj.pK;
            elseif strcmp(obj.ChannelCoding,'LDPC')
                k = double(obj.NumBitsInInformationBlock);
            elseif any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'}))
                k = obj.pConvEncInLen;
            end
            numTotalBits = obj.pNumBitsInInputBuffer + length(u);
            if numTotalBits >= k
                allbits = [obj.pInputBuffer(1:obj.pNumBitsInInputBuffer);u];
                n = floor(length(allbits)/k);
                bits = allbits(1:n*k);
                numBitsLeft = mod(length(allbits),k);
                obj.pInputBuffer = zeros(k,1,'int8'); % Input buffer needs to be flushed as the buffer is full
                obj.pNumBitsInInputBuffer = numBitsLeft;
                if numBitsLeft % When numBitsLeft is non-zero
                    obj.pInputBuffer(1:numBitsLeft) = allbits(n*k+1:end);
                end
            else
                bits = zeros(0,1,'int8'); % Output is nothing as input buffer is not yet full
                n = 0; % As no output is there
                obj.pInputBuffer(obj.pNumBitsInInputBuffer+1:numTotalBits) = u; % Update input buffer
                obj.pNumBitsInInputBuffer = numTotalBits; % Update number of bits in input buffer
            end
        end

        function [bits, n] = updateModInputBuffer(obj,u)
            %updateModInputBuffer Updates the bits in the input buffer of
            %modulator
            %   [BITS, N] = updateModInputBuffer(OBJ,U) fills the pModInputBuffer
            %   property that is there in OBJ with the received bits in U.
            %   BITS contains integer number of length of OBJ.pModInputBuffer.
            %   N is the number of slices that can be formed with the
            %   already existing bits in OBJ.pModInputBuffer and the input, U.
            %   After these slices are formed, OBJ.pModInputBuffer is filled
            %   with the left out bits. Number of bits in the input buffer
            %   at the end is indicated by OBJ.pNumBitsInpModInputBuffer.
            k = obj.pNumModInBits;
            numBitsToTake = k-obj.pNumBitsInpModInputBuffer; % This is always a positive value
            numBlocksLeft = floor(length(u(numBitsToTake+1:end))/k);
            bits = int8([obj.pModInputBuffer(1:obj.pNumBitsInpModInputBuffer);u(1:numBitsToTake+numBlocksLeft*k)]);
            numBitsLeft = mod(length(u(numBitsToTake+1:end)),k);
            obj.pModInputBuffer = zeros(k,1,'int8'); % pModInputBuffer needs to be flushed as the buffer is full
            obj.pNumBitsInpModInputBuffer = numBitsLeft;
            obj.pModInputBuffer(1:numBitsLeft) = u(numBitsToTake+numBlocksLeft*k+1:end);
            n = numBlocksLeft + 1;
        end
    end

    methods % Public
        function s = debugTurboInfo(obj)
            s.ChannelCoding = obj.ChannelCoding;
            s.NumInputBits = obj.NumInputBits;
            s.CodeRate = obj.CodeRate;
            s.InverseCodeRate = getInverseCodeRate(obj);

            s.ASMLength = length(obj.pASM);
            s.ASM = obj.pASM;

            s.TurboInterleaverLength = length(obj.pTurboInterleaverIndices);
            s.TurboInterleaverIndices = obj.pTurboInterleaverIndices;

            s.TurboPuncturePatternLength = length(obj.pTurboPuncturePattern);
            s.TurboPuncturePatternMax = max(obj.pTurboPuncturePattern);
            s.TurboPuncturePattern = obj.pTurboPuncturePattern;

            s.TurboN = obj.pN;
            s.TurboTrellis = obj.TurboTrellis;
        end

        function out = flushFilter(obj)
            %flushFilter Get residual data samples in the filter state by
            %flushing zeros
            %
            %   OUT = flushFilter(OBJ) passes zeroes through the transmit
            %   filter in the CCSDS TM waveform generator to flush the data
            %   samples remaining in the filter state. This method must be
            %   used after the step method. The number of zeros passed
            %   depends on the filter delay. This method is applicable only
            %   for certain channel coding and modulation schemes. For the
            %   coding and modulation schemes that are not supported, this
            %   function errors out. The supported channel coding schemes
            %   for this method are "none", "RS", "turbo", "LDPC" with
            %   IsLDPCOnSMTF set to false, "convolutional" with
            %   ConvolutionalCodeRate set to either "1/2" or "2/3",
            %   "concatenated" with ConvolutionalCodeRate set to either
            %   "1/2" or "2/3". The supported modulation schemes for this
            %   method are "BPSK", and "QPSK". This method is not
            %   applicable when WaveformSource is set to "flexible advanced
            %   coding and modulation".

            if strcmp(obj.WaveformSource, "synchronization and channel coding")
                isSupported = true;
                if strcmp(obj.ChannelCoding, "LDPC") && obj.IsLDPCOnSMTF
                    isSupported = false;
                elseif any(strcmp(obj.ChannelCoding, ["convolutional", "concatenated"])) && (~any(strcmp(obj.ConvolutionalCodeRate, ["1/2", "2/3"])))
                    isSupported = false;
                end
                if ~any(strcmp(obj.Modulation, ["BPSK", "QPSK"]))
                    isSupported = false;
                end
                coder.internal.errorIf(~isSupported, "satcom:ccsdsTMWaveformGenerator:FlushFilterNotApplicable");
                if ~isempty(obj.pTransmitFilter)
                    data = complex(zeros(obj.FilterSpanInSymbols, 1));
                    out = obj.pTransmitFilter(data).*obj.pGain;
                else
                    out = [];
                end
            else
                coder.internal.error("satcom:ccsdsTMWaveformGenerator:FlushFilterNotApplicable");
            end
        end
    end
end

function encodedBits = localPCMDifferentialEncode(diffEnc, bits, pcmFormat)
    bits = int8(bits(:));
    if strcmp(pcmFormat,'NRZ-S')
        diffIn = int8(~logical(bits));
    else
        diffIn = bits;
    end
    encodedBits = diffEnc(diffIn);
end

function [bits,n,buffer,numBits] = localUpdateBufferedBits(buffer,numBits,u,k)
    u = int8(u(:));
    numTotalBits = numBits + length(u);
    if numTotalBits >= k
        allbits = [buffer(1:numBits); u];
        n = floor(length(allbits)/k);
        bits = allbits(1:n*k);
        numBits = mod(length(allbits),k);
        buffer = zeros(k,1,'int8');
        if numBits
            buffer(1:numBits) = allbits(n*k+1:end);
        end
    else
        bits = zeros(0,1,'int8');
        n = 0;
        buffer(numBits+1:numTotalBits) = u;
        numBits = numTotalBits;
    end
end

function rate = localTPCEffectiveRate(rawRate)
    side = localTPCPayloadSideLength(rawRate);
    rate = (side * side) / (64 * 64);
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

function bits = localTPCPayloadBits(rawRate)
    side = localTPCPayloadSideLength(rawRate);
    bits = side * side;
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
        error('ccsdsTMWaveformGenerator:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end

function out = localFramePayloadXor(bits, frameLength, headerLength, prnSeq)
    out = int8(bits(:));
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

    numFrames = floor(numel(out) / frameLength);
    for iFrame = 1:numFrames
        startIdx = (iFrame-1)*frameLength + headerLength + 1;
        stopIdx = startIdx + payloadLength - 1;
        out(startIdx:stopIdx) = bitxor(out(startIdx:stopIdx), prn);
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

function sym = localTMAPSKModulate(bits, modulation)
    [acmFmt, bitsPerSymbol] = localTMAPSKFormat(modulation);
    radii = localTMAPSKRadii(acmFmt, bitsPerSymbol);
    sym = satcom.internal.ccsds.facmModulate(int8(bits(:)), bitsPerSymbol, radii);
end

function y = localInsertTMAPSKPilots(x, pilotInterval, pilotLen, preambleLen)
    x = x(:);
    pilotInterval = max(1, round(double(pilotInterval)));
    pilotLen = max(1, round(double(pilotLen)));
    preambleLen = max(0, round(double(preambleLen)));

    blocks = {};
    if preambleLen > 0
        blocks{end+1} = localTMAPSKPilotSequence(preambleLen, 1); %#ok<AGROW>
    end

    pos = 1;
    pilot = localTMAPSKPilotSequence(pilotLen, 2);
    while pos <= numel(x)
        nData = min(pilotInterval, numel(x)-pos+1);
        blocks{end+1} = x(pos:pos+nData-1); %#ok<AGROW>
        pos = pos + nData;
        if pos <= numel(x)
            blocks{end+1} = pilot; %#ok<AGROW>
        end
    end

    if isempty(blocks)
        y = complex(zeros(0,1));
    else
        y = vertcat(blocks{:});
    end
end

function p = localTMAPSKPilotSequence(N, seed)
    N = max(0, round(double(N)));
    if N == 0
        p = complex(zeros(0,1));
        return;
    end
    n = (1:N).';
    q = mod(floor(abs(sin((n + double(seed)*97) * 12.9898) * 43758.5453)), 4);
    p = exp(1j * (pi/4 + pi/2*q));
    p = p ./ sqrt(mean(abs(p).^2) + eps);
end

function [acmFmt, bitsPerSymbol] = localTMAPSKFormat(modulation)
    modKey = upper(string(modulation));
    if contains(modKey, '32APSK')
        acmFmt = 21;
        bitsPerSymbol = 5;
    else
        acmFmt = 14;
        bitsPerSymbol = 4;
    end
end

function r = localTMAPSKRadii(acmFmt, bitsPerSymbol)
    switch acmFmt
        case 14
            radiiRatio = 3.15;
        case 21
            radiiRatio = [2.72; 4.87];
        otherwise
            error('ccsdsTMWaveformGenerator:UnsupportedTMAPSKFormat', ...
                'Unsupported TM APSK ACM format %d.', acmFmt);
    end

    switch bitsPerSymbol
        case 4
            radius1 = sqrt(4/(1 + 3*(radiiRatio(1)^2)));
            radius2 = radiiRatio(1)*radius1;
            r = [radius1; radius2];
        case 5
            radius1 = sqrt(8/(1 + 3*(radiiRatio(1)^2) + 4*(radiiRatio(2)^2)));
            radius2 = radiiRatio(1)*radius1;
            radius3 = radiiRatio(2)*radius1;
            r = [radius1; radius2; radius3];
        otherwise
            error('ccsdsTMWaveformGenerator:UnsupportedTMAPSKOrder', ...
                'Unsupported TM APSK bits per symbol %d.', bitsPerSymbol);
    end
end
% 交织函数
function out = localSplitPackIQForModulation(iBits, qBits, modulation, debugEnabled)
    if nargin < 4
        debugEnabled = false;
    end

    out = tm_data_path_bit_interleave(int8(iBits), int8(qBits));
    [bitsPerSymbol, fpgaBlockBits] = localSplitFPGAPackingShape(modulation);

    if debugEnabled
        fprintf('[SplitPath TX pack input] mod=%s, iqInterleavedFirst64=%s\n', ...
            char(modulation), localBitVectorString(out, 64));
        assignin('base', 'debug_split_tx_pack_input_bits', out);
    end

    % Keep Phase-1 split as a plain serial I/Q bit interleave. The FPGA
    % 96/160-bit mapper packing is intentionally disabled while debugging
    % odd bits-per-symbol modes; RX will handle the possible I/Q parity
    % phase before rail deinterleave.
    % if fpgaBlockBits > 0
    %     out = localReverseSymbolGroupsInBlocks(out, bitsPerSymbol, fpgaBlockBits);
    % end

    if debugEnabled
        fprintf('[SplitPath TX pack output] mod=%s, fpgaBlockBits=%d, bitsPerSymbol=%d, blockReverse=off, packedFirst64=%s\n', ...
            char(modulation), fpgaBlockBits, bitsPerSymbol, localBitVectorString(out, 64));
        assignin('base', 'debug_split_tx_packed_bits', out);
    end
end

function [bitsPerSymbol, fpgaBlockBits] = localSplitFPGAPackingShape(modulation)
    switch char(modulation)
        case '8PSK'
            bitsPerSymbol = 3;
            fpgaBlockBits = 96;   % 3 x 32-bit interleaved words -> 4 x 24-bit mapper words
        case '32QAM'
            bitsPerSymbol = 5;
            fpgaBlockBits = 160;  % 5 x 32-bit interleaved words -> 4 x 40-bit mapper words
        case '16APSK'
            bitsPerSymbol = 4;
            fpgaBlockBits = 0;    % MATLAB software path: plain serial I/Q interleave
        case '32APSK'
            bitsPerSymbol = 5;
            fpgaBlockBits = 0;    % MATLAB software path: RX resolves the odd-bit start structurally
        otherwise
            bitsPerSymbol = 0;
            fpgaBlockBits = 0;
    end
end

function out = localReverseSymbolGroupsInBlocks(x, bitsPerSymbol, blockBits)
    out = x(:);
    if bitsPerSymbol <= 0 || blockBits <= 0 || mod(blockBits, bitsPerSymbol) ~= 0
        return;
    end

    numFullBlocks = floor(numel(out) / blockBits);
    if numFullBlocks <= 0
        return;
    end

    symbolsPerBlock = blockBits / bitsPerSymbol;
    for iBlock = 1:numFullBlocks
        idx = (iBlock-1)*blockBits + (1:blockBits);
        symbolGroups = reshape(out(idx), bitsPerSymbol, symbolsPerBlock);
        out(idx) = reshape(symbolGroups(:, end:-1:1), [], 1);
    end
end

function txt = localBitVectorString(bits, maxLen)
    if nargin < 2
        maxLen = 64;
    end
    bits = int8(bits(:));
    bits = bits(1:min(maxLen, numel(bits)));
    if isempty(bits)
        txt = '';
        return;
    end
    txt = char('0' + double(bits(:).'));
end

function localValidateHighRateConvFrameLength(obj)
    if ~any(strcmp(obj.ChannelCoding, {'convolutional','concatenated'}))
        return;
    end
    if ~obj.HasASM
        return;
    end

    switch char(obj.ConvolutionalCodeRate)
        case '5/6'
            punctureInputPeriod = 5;
            exampleText = '1116';
        case '7/8'
            punctureInputPeriod = 7;
            exampleText = '1116 or 1123';
        otherwise
            return;
    end

    caduBits = double(obj.NumBytesInTransferFrame)*8 + length(obj.pASM);
    if mod(caduBits, punctureInputPeriod) ~= 0
        error('ccsdsTMWaveformGenerator:HighRateConvFrameLengthUnsupported', ...
            ['ConvolutionalCodeRate="%s" requires ASM+TF length (%d bits) ', ...
             'to be divisible by %d so the puncture phase resets at each frame. ', ...
             'Use NumBytesInTransferFrame=%s, or another aligned TF length.'], ...
            char(obj.ConvolutionalCodeRate), caduBits, punctureInputPeriod, exampleText);
    end
end

function asmLen = localConfiguredASMLength(obj)
    if ~isempty(obj.pASM)
        asmLen = length(obj.pASM);
    elseif ~isempty(obj.ASMLength)
        asmLen = double(obj.ASMLength);
    elseif ~isempty(obj.ASMHex)
        asmLen = 4*numel(char(obj.ASMHex));
    else
        asmLen = 32;
    end
end

% LocalWords:  TMWAVEGEN TXWAVEFORM tm randi hasfilt csmlen LDPCSMTF nd altersymb Prev Symb LDPCG
% LocalWords:  invr btprod updatep Inp
