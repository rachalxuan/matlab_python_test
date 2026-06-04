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
    %   HasRandomizer               - Option for randomizing the data
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
    end
    
    methods
        % Constructor
        function obj = ccsdsTMWaveformGenerator(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods(Access = protected)
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants
            setupImpl@satcom.internal.ccsds.tmBase(obj);
            sps = double(obj.SamplesPerSymbol);
            if obj.pIsFACM
                obj.pInputBuffer = zeros(obj.pK,1,'int8');
                obj.pNumBitsInInputBuffer = 0;
                obj.pCodewordIndex = 1;
                obj.pMaxNumCW = 16;
            else
                switch(obj.ChannelCoding)
                    case {'convolutional','concatenated'}
                        switch obj.ConvolutionalCodeRate
                            case '1/2'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis);
                            case '2/3'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1]);
                            case '3/4'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0]);
                            case '5/6'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;1;0;0;1;1;0]);
                            otherwise % case '7/8'
                                obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis,...
                                    'PuncturePatternSource', 'Property', 'PuncturePattern', [1;1;0;1;0;1;0;1;1;0;0;1;1;0]);
                        end
                        temp = obj.pPRNSequenceLength + length(obj.pASM)*obj.HasASM;
                        obj.pConvEncInLen = temp - mod(temp,length(obj.pConvEnc.PuncturePattern)/2)*(~strcmp(obj.ConvolutionalCodeRate,'1/2'));
                    case 'turbo'
                        obj.pConvEnc1 = comm.ConvolutionalEncoder('TrellisStructure',...
                            obj.TurboTrellis, 'TerminationMethod', 'Terminated');
                        obj.pConvEnc2 = comm.ConvolutionalEncoder('TrellisStructure',...
                            obj.TurboTrellis, 'TerminationMethod', 'Terminated');
                    otherwise % case 'LDPC'
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
                    case '4D-8PSK-TCM'
                        obj.pNumModInBits = temp - mod(temp,4*double(obj.ModulationEfficiency));
                        obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
                        obj.pNumBitsInpModInputBuffer = 0;
                        obj.pConvEncState = zeros(6,1,'int8');
                        obj.pDiffEncState = zeros(3,1,'int8');
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
            
            if strcmp(obj.PCMFormat,'NRZ-M')
                obj.pDiffEnc = comm.DifferentialEncoder;
            end
            
            if ~strcmp(obj.PulseShapingFilter,'none') && ~any(strcmp(obj.Modulation,{'GMSK','OQPSK','PCM/PSK/PM','PCM/PM/biphase-L'}))
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
                encodedBits = tmEncode(obj,int8(bits));
                
                % Modulate the encoded bits
                symbols = tmModulate(obj,encodedBits);
            end
            
            % Pass the symbols through filter
            if strcmp(obj.PulseShapingFilter,"root raised cosine") && ~any(strcmp(obj.Modulation,{'GMSK','OQPSK','PCM/PSK/PM','PCM/PM/biphase-L'}))
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
            
            if ~isempty(obj.pConvEnc)
                reset(obj.pConvEnc);
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
            
            if ~isempty(obj.pConvEnc)
                release(obj.pConvEnc);
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
                s.pConvEnc = matlab.System.saveObject(obj.pConvEnc);
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
                s.pModInputBuffer = obj.pModInputBuffer;
                s.pNumBitsInpModInputBuffer = obj.pNumBitsInpModInputBuffer;
                s.pNumModInBits = obj.pNumModInBits;
            end
        end
        
        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s
            
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
                obj.pConvEnc = matlab.System.loadObject(s.pConvEnc);
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
            elseif strcmp(prop,'CodeRate')
                flag = ~any(strcmp(obj.ChannelCoding,{'turbo','LDPC'})) || isFACM;
            elseif strcmp(prop,'HasRandomizer')
                flag = smtfFlag;
            elseif strcmp(prop,'HasASM')
                flag = smtfFlag;
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
                flag = any(strcmp(obj.Modulation,{'GMSK','OQPSK','PCM/PSK/PM','PCM/PM/biphase-L'})) && ~isFACM;
            elseif strcmp(prop,'RolloffFactor')
                if any(strcmp(obj.Modulation,{'GMSK','PCM/PSK/PM','PCM/PM/biphase-L','OQPSK'})) && ~isFACM
                    flag = true;
                    if strcmp(obj.Modulation,'OQPSK')
                        flag = false; % Visible in case of OQPSK
                    end
                else
                    flag = strcmp(obj.PulseShapingFilter,"none");
                end
            elseif strcmp(prop,'SamplesPerSymbol')
                if any(strcmp(obj.Modulation,{'GMSK','PCM/PSK/PM','PCM/PM/biphase-L','OQPSK'})) && ~isFACM
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
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','BPSK','QPSK','8PSK','OQPSK'})) || isFACM;
            elseif strcmp(prop,'ModulationIndex')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM', 'PCM/PM/biphase-L'})) || isFACM;
            elseif strcmp(prop,'FilterSpanInSymbols')
                if any(strcmp(obj.Modulation,{'GMSK','PCM/PSK/PM','PCM/PM/biphase-L','OQPSK'})) && ~isFACM
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
                end
                switch(obj.Modulation)
                    case 'QPSK'
                        m = 2;
                    case '8PSK'
                        m = 3;
                    case '4D-8PSK-TCM'
                        m = double(obj.ModulationEfficiency);
                    case 'OQPSK'
                        m = 2;
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
                'HasRandomizer',...
                'HasASM',...
                'PCMFormat'};
            
            encProps = {'ChannelCoding',...
                'NumBitsInInformationBlock',...
                'ConvolutionalCodeRate',...
                'CodeRate',...
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
        end
        
        function n = get.MinNumTransferFrames(obj)
            if strcmp(obj.WaveformSource,'flexible advanced coding and modulation') || (strcmp(obj.ChannelCoding,'LDPC') && obj.IsLDPCOnSMTF)
                if strcmp(obj.WaveformSource, 'flexible advanced coding and modulation')
                    k = obj.K_Values(obj.ACMFormat);
                else % LDPC on SMTF
                    k = double(obj.NumBitsInInformationBlock);
                end
                n = ceil(k/(32+getNumBytesInTransferFrame(obj)*8)); % 32 is the number of bits in ASM
            else
                n = 1;
            end
        end
    end
    
    methods(Access = private)
        function encoded = tmEncode(obj,bits)
            % TM synchronization and channel coding
            HasASM = obj.HasASM;
            tfl = obj.pTFLen*8;
            numTF = length(bits)/tfl;
            switch(obj.ChannelCoding)
                case 'none'
                    if obj.HasRandomizer
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
                        cw = int8(ccsdsRSEncode(logical(tbits),k,i,s));
                        if obj.HasRandomizer
                            randomized = bitxor(cw,obj.pPRNSequence);
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
                    if obj.HasRandomizer
                        randomized = bitxor(bits,repmat(obj.pPRNSequence,numTF,1));
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
                    
                    [encin,numcw] = updateInputBuffer(obj,cadu);
                    bLen = length(encin);
                    temp = 1:bLen;
                    indices = reshape(temp,obj.pConvEncInLen,numcw);
                    symIdx = reshape(1:bLen*obj.pInverseCodeRate,obj.pInverseCodeRate*bLen/numcw,numcw);
                    encodedTemp = int8(zeros(bLen*obj.pInverseCodeRate,1));
                    for iSlice = 1:numcw
                        tempbits = encin(indices(:,iSlice));
                        if strcmp(obj.PCMFormat,'NRZ-M')
                            % Refer section 3.3.3 of [1], which specifies
                            % that NRZ-M should be done before
                            % convolutional encoder.
                            tfullcadu = obj.pDiffEnc(tempbits);
                        else % Case of NRZ-L
                            tfullcadu = tempbits;
                        end
                        encodedTemp(symIdx(:,iSlice)) = obj.pConvEnc(tfullcadu);
                    end
                    if strcmp(obj.ConvolutionalCodeRate,'1/2')
                        % Flip the bit on the second line of the
                        % convolutional encoder as specified in [1] section
                        % 3.3.2, when the code rate is 1/2.
                        encoded = encodedTemp(:);
                        encoded(2:2:end) = int8(~encoded(2:2:end));
                    else
                        encoded = encodedTemp(:);
                    end
                case 'concatenated'
                    n = 255;
                    k = obj.pRSParams.k;
                    s = obj.pRSParams.s;
                    i = obj.pRSParams.i;
                    numBitsInCADU = 8*i*(n-k+s)+HasASM*length(obj.pASM);
                    cadu = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tbits = bits((itf-1)*tfl+1:itf*tfl);
                        cw = int8(ccsdsRSEncode(logical(tbits),k,i,s));
                        if obj.HasRandomizer
                            randomized = bitxor(cw,obj.pPRNSequence);
                        else
                            randomized = cw;
                        end
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
                        if strcmp(obj.PCMFormat,'NRZ-M')
                            % Refer section 3.3.3 of [1] which specifies
                            % that NRZ-M should be done before
                            % convolutional encoder.
                            tfullcadu = obj.pDiffEnc(tempbits);
                        else % Case of NRZ-L
                            tfullcadu = tempbits;
                        end
                        encodedTemp(symIdx(:,iSlice)) = obj.pConvEnc(tfullcadu);
                    end
                    if strcmp(obj.ConvolutionalCodeRate,'1/2')
                        % Flip the bit on the second line of the
                        % convolutional encoder as specified in section
                        % 3.3.2 of [1] when the code rate is 1/2.
                        encoded = encodedTemp;
                        encoded(2:2:end) = int8(~encodedTemp(2:2:end));
                    else
                        encoded = encodedTemp;
                    end
                case 'turbo'
                    numBitsInCADU = obj.pInverseCodeRate*(tfl+4)+HasASM*length(obj.pASM);
                    encoded = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tbits = bits((itf-1)*tfl+1:itf*tfl);
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
                        if obj.HasRandomizer
                            randomized = bitxor(cw,obj.pPRNSequence);
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
                case 'LDPC'
                    numBitsInCADU = obj.pInverseCodeRate*tfl+HasASM*length(obj.pASM);
                    encoded = zeros(numBitsInCADU*numTF,1,'int8');
                    for itf = 1:numTF
                        tf = bits((itf-1)*tfl+1:itf*tfl);
                        cw = int8(satcom.internal.ccsds.tmldpcEncode(tf(:),obj.pLDPCGeneratorMatrix));
                        if obj.HasRandomizer
                            randomized = bitxor(cw,obj.pPRNSequence);
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
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && strcmp(obj.PCMFormat,'NRZ-M')
                            tbits = obj.pDiffEnc(modin(indices(:,iSlice)));
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
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && strcmp(obj.PCMFormat,'NRZ-M')
                            tbits = obj.pDiffEnc(modin(indices(:,iSlice)));
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
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && strcmp(obj.PCMFormat,'NRZ-M')
                            tbits = obj.pDiffEnc(modin(indices(:,iSlice)));
                        else
                            tbits = modin(indices(:,iSlice));
                        end
                        waveform(symIdx(:,iSlice)) = obj.pMod(double(tbits));
                    end
                case '4D-8PSK-TCM'
                    if coder.target('MATLAB')
                        [waveform, obj.pConvEncState, obj.pDiffEncState] = satcom.internal.ccsds.cg_fourD8PSKTCMMod_int8(modin, double(obj.ModulationEfficiency), obj.pConvEncState, obj.pDiffEncState);
                    else
                        [waveform, obj.pConvEncState, obj.pDiffEncState] = satcom.internal.ccsds.fourD8PSKTCMMod(modin, double(obj.ModulationEfficiency), obj.pConvEncState, obj.pDiffEncState);
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
                        if ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && strcmp(obj.PCMFormat,'NRZ-M')
                            tbits = obj.pDiffEnc(modin(indices(:,iSlice)));
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
                            if strcmp(obj.PCMFormat,'NRZ-M')
                                dbits(indices(:,iSlice)) = obj.pDiffEnc(modin(indices(:,iSlice)));
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

% LocalWords:  TMWAVEGEN TXWAVEFORM tm randi hasfilt csmlen LDPCSMTF nd altersymb Prev Symb LDPCG
% LocalWords:  invr btprod updatep Inp
