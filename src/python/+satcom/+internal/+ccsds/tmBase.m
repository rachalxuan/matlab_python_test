classdef tmBase < matlab.System
    %satcom.internal.ccsds.tmBase Base class for CCSDS telemetry waveform
    %
    %   Note: This is an internal undocumented function and its API and/or
    %   functionality may change in subsequent releases.
    
    %   Copyright 2020 The MathWorks, Inc.
    
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

    %#codegen

    % Public, tunable properties
    properties
        %ACMFormat Adaptive coding and modulation (ACM) format
        %   Specify the ACM format as an integer from 1 to 27, inclusive,
        %   as specified in CCSDS flexible advanced coding and modulation
        %   for high rate telemetry applications standard. This property
        %   applies when WaveformSource is "flexible advanced coding and
        %   modulation". This is a tunable property. The default is 1.
        ACMFormat = 1
    end

    % Public, non-tunable properties in general group
    properties(Nontunable)
        %WaveformSource CCSDS telemetry waveform source
        %   Specify whether coding scheme is chosen from TM synchronization
        %   and channel coding standard or from the flexible advanced
        %   coding and modulation for high rate telemetry applications
        %   standard. This property should be one of 
        %   "synchronization and channel coding" |
        %   "flexible advanced coding and modulation". The default is
        %   "synchronization and channel coding".
        WaveformSource (1, 1) string {matlab.system.mustBeMember(WaveformSource, {'synchronization and channel coding','flexible advanced coding and modulation'})} = "synchronization and channel coding"
        %NumBytesInTransferFrame Number of bytes in one transfer frame
        %   Specify number of bytes in the transfer frame as a positive
        %   integer less than or equal to 2048. This property is applicable
        %   when WaveformSource is set to "synchronization and channel
        %   coding" and ChannelCoding is set to either "none",
        %   "convolutional", or "LDPC" on stream of sync marked transfer
        %   frames (SMTF). This property is also applicable when
        %   WaveformSource is set to "flexible advanced coding and
        %   modulation". In case of "flexible advanced coding and
        %   modulation" waveform, minimum value of NumBytesInTransfer is
        %   223. For other ChannelCoding schemes, this property is
        %   calculated internally based on other properties. The default is
        %   223.
        NumBytesInTransferFrame = 223
        %PCMFormat Pulse code modulation (PCM) format
        %   Specify the pulse code modulation format as one of "NRZ-L" |
        %   "NRZ-M" to select the PCM coding used in the CCSDS TM waveform.
        %   This property applies when WaveformSource is set to
        %   "synchronization and channel coding" and Modulation is either
        %   "BPSK", "QPSK", "8PSK", "OQPSK", or "PCM/PSK/PM". The default
        %   is "NRZ-L".
        PCMFormat (1, 1) string {matlab.system.mustBeMember(PCMFormat, {'NRZ-L','NRZ-M'})} = "NRZ-L"
    end
    
    % Public, non-tunable properties in channel coding group
    properties(Nontunable)
        %ChannelCoding Error control channel coding scheme
        %   Specify the channel coding as one of "none" | "RS" |
        %   "convolutional" | "concatenated" | "turbo" | "LDPC". This
        %   property applies when WaveformSource is "synchronization and
        %   channel coding". The default is "RS".
        ChannelCoding (1, 1) string {matlab.system.mustBeMember(ChannelCoding, {'none','RS','convolutional','concatenated','turbo','LDPC'})} = "RS"
        %NumBitsInInformationBlock Number of bits in the turbo/LDPC message
        %   Specify the information block length (in bits) as one of 1784 |
        %   3568 | 7136 | 8920 when ChannelCoding is set to "turbo".
        %   Specify the information block length (in bits) as one of 1024 |
        %   4096 | 16384 | 7136 when ChannelCoding is set to "LDPC". This
        %   property is applicable when WaveformSource is set to
        %   "synchronization and channel coding" and ChannelCoding is set
        %   to either "turbo" or "LDPC". The default is 7136.
        NumBitsInInformationBlock = 7136
        %ConvolutionalCodeRate Code rate of convolutional code
        %   Specify the code rate of convolutional code as one of "1/2" |
        %   "2/3" | "3/4" | "5/6" | "7/8". This property is applicable when
        %   WaveformSource is set to "synchronization and channel coding"
        %   and  ChannelCoding is set to "convolutional" | "concatenated".
        %   The default is "1/2". The numeric value of code rate for
        %   concatenated code also depends on the constituent Reed-Solomon
        %   (RS) code. This exact numeric value can be obtained from info
        %   method field, ActualCodeRate of the object.
        ConvolutionalCodeRate (1, 1) string {matlab.system.mustBeMember(ConvolutionalCodeRate, {'1/2','2/3','3/4','5/6','7/8'})} = "1/2"
        %CodeRate Code rate of turbo or LDPC code
        %   Specify the code rate as one of "1/2" | "1/3" | "1/4" | "1/6"
        %   when ChannelCoding property is set to "turbo". Specify the code
        %   rate as one of "1/2" | "2/3" | "4/5" | "7/8" when the
        %   ChannelCoding property is set to "LDPC". This property is
        %   applicable when WaveformSource is set to "synchronization and
        %   channel coding" and ChannelCoding scheme is set to either
        %   "turbo" or "LDPC". The default is "1/2" for turbo coding
        %   scheme. For LDPC channel coding, default is "7/8". When
        %   ChannelCoding is set to "LDPC" and NumBitsInInformationBlock is
        %   set to 7136, then CodeRate must be "7/8". Also for LDPC code,
        %   when CodeRate is "7/8", it is not exactly 7/8 numerical. Actual
        %   code rate numerical value is 223/255. This numeric value for
        %   any code can be obtained from info method of the object.
        CodeRate (1, 1) string {matlab.system.mustBeMember(CodeRate, {'1/2','2/3','4/5','7/8','1/3','1/4','1/6'})} = "1/2"
        %RSMessageLength Number of bytes in one Reed-Solomon (RS) message
        %block
        %   Specify the number of bytes in one RS message block as one of
        %   223 | 239. This property is applicable when WaveformSource is
        %   set to "synchronization and channel coding" and ChannelCoding
        %   is set to either "RS" or "concatenated". The default is 223.
        RSMessageLength = 223
        %RSInterleavingDepth Interleaving depth of the Reed-Solomon (RS)
        %code
        %   Specify the interleaving depth of the RS code as one of 1 | 2 |
        %   3 | 4 | 5 | 8. This property is applicable when WaveformSource
        %   is set to "synchronization and channel coding" and
        %   ChannelCoding is set to either "RS" or "concatenated". Interleaving
        %   depth is the number of RS codewords in a codeblock. The default
        %   is 1.
        RSInterleavingDepth = 1
        %RSShortenedMessageLength Number of bytes in Reed-Solomon (RS)
        %shortened message block
        %   Specify the number of bytes in the RS shortened message as a
        %   positive integer value less than or equal to RSMessageLength.
        %   This property is applicable when WaveformSource is set to
        %   "synchronization and channel coding" and ChannelCoding is set
        %   to either "RS" or "concatenated", and IsRSMessageShortened is
        %   set to true. The default is 223.
        RSShortenedMessageLength = 223
        %LDPCCodeblockSize Number of LDPC codewords in LDPC codeblock of
        %stream of sync marked transfer frames (SMTF)
        %   Specify the number of LDPC codewords in one codeblock as one of
        %   1 | 2 | 3 | 4 | 5 | 6 | 7 | 8. This property is applicable when
        %   WaveformSource is set to "synchronization and channel coding"
        %   and IsLDPCOnSMTF is set to true. The default is 1.
        LDPCCodeblockSize = 1
    end
    
    % Public, non-tunable properties in the modulator - demodulator group
    properties(Nontunable)
        %Modulation Modulation scheme
        %   Specify the modulation scheme as one of "BPSK" | "QPSK" |
        %   "8PSK" | "16QAM" | "32QAM" | "GMSK" | "OQPSK" | "4D-8PSK-TCM" | "PCM/PSK/PM" |
        %   "PCM/PM/biphase-L". This property is applicable when
        %   WaveformSource is set to "synchronization and channel coding".
        %   The default is "QPSK".
        Modulation (1, 1) string {matlab.system.mustBeMember(Modulation, {'PCM/PSK/PM','PCM/PM/biphase-L','BPSK','QPSK','8PSK','16QAM','32QAM','4D-8PSK-TCM','GMSK','OQPSK'})} = "QPSK"
        %PulseShapingFilter Pulse shaping filter
        %   Specify the pulse shaping filter as one of "root raised cosine"
        %   | "none". This property is applicable when WaveformSource is
        %   set to "synchronization and channel coding" and Modulation is
        %   set to either "BPSK", "QPSK", "8PSK", or "4D-8PSK-TCM". This
        %   property is also applicable when WaveformSource is set to
        %   "flexible advanced coding and modulation". The default is "root
        %   raised cosine".
        PulseShapingFilter (1, 1) string {matlab.system.mustBeMember(PulseShapingFilter, {'root raised cosine', 'none'})} = "root raised cosine"
        %RolloffFactor Rolloff factor of the baseband filter
        %   Specify the rolloff factor of the square root raised cosine
        %   (SRRC) baseband filter as a floating point number from 0 to 1,
        %   inclusive. This property is applicable when WaveformSource is
        %   set to "synchronization and channel coding" and Modulation is
        %   set to either "BPSK", "QPSK", "8PSK", "OQPSK", or
        %   "4D-8PSK-TCM". This property is also applicable when
        %   WaveformSource is set to "flexible advanced coding and
        %   modulation". This property is not applicable when
        %   PulseShapingFilter property is set to "none" for either value
        %   of the WaveformSource property. The values specified in [2] are
        %   0.35 and 0.5 and the values specified in [3] are 0.2, 0.25,
        %   0.3, and 0.35. The default is 0.35.
        RolloffFactor = 0.35
        %FilterSpanInSymbols Filter span in symbols
        %   Specify the number of symbols the root raised cosine filter
        %   spans as an integer valued positive scalar. This property is
        %   applicable when WaveformSource is set to "synchronization and
        %   channel coding" and Modulation is set to either "BPSK", "QPSK",
        %   "8PSK", "OQPSK", or "4D-8PSK-TCM". This property is also
        %   applicable when WaveformSource is set to "flexible advanced
        %   coding and modulation". The default is 10. Since the ideal root
        %   raised cosine filter has an infinite impulse response, the
        %   object truncates the impulse response to FilterSpanInSymbols
        %   symbols.
        FilterSpanInSymbols = 10
        % BandwidthTimeProduct Bandwidth time product for GMSK modulator
        %   Specify the bandwidth time product as one of 0.25 | 0.5. This
        %   property is applicable when WaveformSource is set to
        %   "synchronization and channel coding" and Modulation is set to
        %   "GMSK". The default is 0.25.
        BandwidthTimeProduct = 0.25
        %ModulationEfficiency Modulation efficiency of 4D-8PSK-TCM
        %   Specify the modulation efficiency of 4D 8PSK trellis coded
        %   modulator as one of 2 | 2.25 | 2.5 | 2.75. This property
        %   indicates number of bits for each complex baseband symbol. This
        %   property is applicable when WaveformSource is set to
        %   "synchronization and channel coding" and Modulation is set to
        %   "4D-8PSK-TCM". The default is 2.
        ModulationEfficiency = 2
        %SubcarrierWaveform Waveform used to PSK modulate the NRZ data
        %   Specify the Subcarrier waveform used in the "PCM/PSK/PM"
        %   modulation as either "sine" or "square". This property is
        %   applicable when WaveformSource is set to "synchronization and
        %   channel coding" and Modulation is set to "PCM/PSK/PM". The
        %   default is "sine".
        SubcarrierWaveform (1, 1) string {matlab.system.mustBeMember(SubcarrierWaveform, {'sine','square'})} = "sine"
        %ModulationIndex Modulation index in the residual carrier phase
        %modulation
        %   Specify the modulation index as a real-valued scalar in the
        %   range [0.2, 2] radians. This property applies when
        %   WaveformSource is set to "synchronization and channel coding"
        %   and Modulation is set to either "PCM/PSK/PM" or
        %   "PCM/PM/biphase-L". The default is 0.4.
        ModulationIndex = 0.4
        %SymbolRate Symbol rate (coded symbols/s)
        %   Specify the coded symbol rate in Hz. This property is
        %   applicable only when WaveformSource is set to "synchronization
        %   and channel coding" and Modulation is set to "PCM/PSK/PM". The
        %   default is 2000.
        SymbolRate = 2e3
        %SubcarrierToSymbolRateRatio Ratio of subcarrier frequency to
        %symbol rate
        %   Specify the ratio of subcarrier frequency to symbol rate as a
        %   positive integer less than or equal to 50. This property is
        %   applicable when WaveformSource is set to "synchronization and
        %   channel coding" and Modulation is set to "PCM/PSK/PM". The
        %   default is 4.
        SubcarrierToSymbolRateRatio = 4
        %SamplesPerSymbol Samples per symbol
        %   Specify the samples per symbol as a positive integer scalar
        %   value. This property is applicable only when Modulation is set
        %   to either "PCM/PSK/PM", "GMSK", or "OQPSK" or
        %   PulseShapingFilter is set to "root raised cosine". This
        %   property is applicable when WaveformSource is set to either
        %   "synchronization and channel coding" or "flexible advanced
        %   coding and modulation". The default is 10.
        SamplesPerSymbol = 10
        %ScramblingCodeNumber Scrambling code number
        %   Specify the scrambling code number for flexible advanced coding
        %   and modulation for high rate telemetry applications standard.
        %   This value is used for randomizing the complex baseband
        %   symbols. This is an integer value in the range 0 to (2^18 - 2).
        %   This property is applicable only when WaveformSource is set to
        %   "flexible advanced coding and modulation". The default is 0.
        ScramblingCodeNumber = 0
    
    % All logical properties at single place
    
        %HasRandomizer Option for randomizing the data
        %   Specify the option to randomize data as true | false. True
        %   value specifies that the data in the channel access data unit
        %   (CADU) is randomized. This property is always applicable except
        %   when WaveformSource is set to "flexible advanced coding and
        %   modulation" or when WaveformSource is set to "Synchronization
        %   and channel coding" along with ChannelCoding is set to "LDPC"
        %   and IsLDPCOnSMTF is set to true. In such invalid cases, this
        %   property value is set to true internally. The default is true.
        HasRandomizer (1, 1) logical = true
        %HasASM Option for inserting attached sync marker (ASM)
        %   Specify the option to insert ASM to data as true | false. True
        %   value specifies that the data in the channel access data unit
        %   (CADU) is attached with ASM. This property is always applicable
        %   except when WaveformSource is set to "flexible advanced coding
        %   and modulation" or when WaveformSource is set to
        %   "Synchronization and channel coding" along with ChannelCoding
        %   is set to "LDPC" and IsLDPCOnSMTF is set to true. In such
        %   invalid cases, this property value is set to true internally.
        %   The default is true.
        HasASM (1, 1) logical = true;
        %IsRSMessageShortened Option to shorten Reed-Solomon (RS) code
        %   Specify the option to shorten RS code as true | false. True
        %   indicates that RS code is shortened. This property is
        %   applicable only when WaveformSource is set to "synchronization
        %   and channel coding" and ChannelCoding is set to either "RS" or
        %   "concatenated". The default is false.
        IsRSMessageShortened (1, 1) logical = false
        %IsLDPCOnSMTF Option for using LDPC on stream of sync marked
        %transfer frames (SMTF)
        %   Specify the option for LDPC on stream of SMTF as true | false.
        %   True indicates that LDPC is on stream of SMTF, as specified in
        %   CCSDS 131.0-B-3 Section 8 of TM Synchronization and Channel
        %   Coding standard [1], and false indicates that the LDPC is on
        %   transfer frame. This property is applicable only when
        %   WaveformSource is set to "synchronization and channel coding"
        %   and ChannelCoding is set to "LDPC". The default is false.
        IsLDPCOnSMTF (1, 1) logical = false
        %HasPilots Option for inserting pilot symbols
        %   Specify whether pilot symbols are inserted within data as
        %   specified in CCSDS flexible advanced coding and modulation for
        %   high rate telemetry applications standard [3]. This property is
        %   applicable only when WaveformSource is set to "flexible
        %   advanced coding and modulation". The default is false.
        HasPilots (1, 1) logical = false
    end
    
    % Non-tunable protected properties
    properties(Access = protected,Nontunable)
        %pIsFACM Indication of usage flexible advanced coding and modulation
        %for high rate telemetry applications standard
        pIsFACM = true;
        %pRSParams is used to hold the properties of Reed-Solomon code.
        %This is initialized so that these parameters with proper datatypes
        %is used throughout the code irrespective of datatype that user
        %gives for these properties.
        pRSParams = struct('n',255,'k',223,'i',1,'s',223,'IsShortened',false);
        pLDPCCodeWordLength = 8160;
        pPRNSequenceLength
        pASM
        pCSM
        pPRNSequence
        pInverseCodeRate = 1 % pInverseCodeRate is defined to be non-tunable for codegen to work
        pTFLen % As NumBytesInTransferFrame get method is removed, this property is needed for correct codegen
    end
    
    % Channel coding related properties
    properties(Access = protected)
        pTurboPuncturePattern % Puncture pattern for the turbo codes
        pTurboInterleaverIndices
        pNumBitsPerSymbol
        pK = 5758
        pHeader
        pInterleavingIndices
        pSCCCPuncturePattern2
    end
    
    % Mod-demod related properties
    properties(Access = protected)
        pRadii
        pSubcarrierFrequency
        pPLRandomSymbols
    end
    
    properties(Constant, Hidden)
        PCMFormat_Values ={'NRZ-L','NRZ-M'};
        WaveformSource_Values = {'synchronization and channel coding','flexible advanced coding and modulation'};
        ChannelCoding_Values = {'none','RS','convolutional','concatenated','turbo','LDPC'};
        CodeRate_Values = {'1/2','2/3','7/8','4/5','1/3','1/4','1/6'};
        ConvolutionalCodeRate_Values = {'1/2','2/3','3/4','5/6','7/8'};
        Modulation_Values = {'GMSK','BPSK','QPSK','8PSK','16QAM','32QAM','4D-8PSK-TCM','OQPSK','PCM/PSK/PM','PCM/PM/biphase-L'};
        SubcarrierWaveform_Values = {'sine','square'};
        PulseShapingFilter_Values = {'root raised cosine', 'none'};
        ConvolutionalCodesTrellis = poly2trellis(7, [171 133]); % Trellis structure for the convolutional encoder that is specified in
        TurboTrellis = poly2trellis(5,[23 33 25 37],23); % Turbo codes rate 1/7
        m_Values = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
        K_Values = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
            19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
            35998;33358;35998;38638;41038;43678];
    end
    
    methods
        % Constructor
        function obj = tmBase(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    % System object related methods
    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants
            obj.pRSParams = getRSParams(obj);
            obj.pTFLen = getNumBytesInTransferFrame(obj);
            if strcmp(obj.WaveformSource,"synchronization and channel coding")
                obj.pIsFACM = false;
            else
                obj.pIsFACM = true;
                obj.pK = obj.K_Values(obj.ACMFormat);
            end
            if any(strcmp(obj.Modulation,{'GMSK', '4D-8PSK-TCM', 'PCM/PM/biphase-L'}))
                obj.PCMFormat = "NRZ-L";
            end
            if ~obj.pIsFACM
                obj.pSubcarrierFrequency = double(obj.SymbolRate)*double(obj.SubcarrierToSymbolRateRatio);
                invr = getInverseCodeRate(obj);
                obj.pInverseCodeRate = invr;
                switch(obj.ChannelCoding)
                    case 'none'
                        obj.pPRNSequenceLength = 8*obj.pTFLen;
                        obj.pASM = generateASM(obj);
                    case 'convolutional'
                        obj.pPRNSequenceLength = 8*obj.pTFLen;
                        obj.pASM = generateASM(obj);
                    case 'RS'
                        obj.pPRNSequenceLength = 8*obj.pRSParams.i*(obj.pRSParams.n-(obj.pRSParams.k-obj.pRSParams.s)*obj.IsRSMessageShortened);
                        obj.pASM = generateASM(obj);
                    case 'concatenated'
                        obj.pPRNSequenceLength = 8*obj.pRSParams.i*(obj.pRSParams.n-(obj.pRSParams.k-obj.pRSParams.s)*obj.IsRSMessageShortened);
                        obj.pASM = generateASM(obj);
                    case 'turbo'
                        obj.pPRNSequenceLength = round((double(obj.NumBitsInInformationBlock)+4)*invr);
                        obj.pASM = generateASM(obj);
                        obj.pTurboInterleaverIndices = satcom.internal.ccsds.tmTurboInterleavingIndices(8*obj.pTFLen);
                        numBitsAtOutputOfTurboEncoderBeforePuncturing = 7*8*obj.pTFLen+28; % 28 is the number of tail bits before puncturing
                        switch(obj.CodeRate)
                            case '1/2'
                                puncpat = logical([1; 1; 0; 0; 0; 0; 0; 1; 0; 0; 0; 1; 0; 0]);
                                numPatterns = numBitsAtOutputOfTurboEncoderBeforePuncturing/length(puncpat);
                                obj.pTurboPuncturePattern = repmat(puncpat,numPatterns,1);
                            case '1/3'
                                puncpat = logical([1; 1; 0; 0; 1; 0; 0]);
                                numPatterns = numBitsAtOutputOfTurboEncoderBeforePuncturing/length(puncpat);
                                obj.pTurboPuncturePattern = repmat(puncpat,numPatterns,1);
                            case '1/4'
                                puncpat = logical([1; 0; 1; 1; 1; 0; 0]);
                                numPatterns = numBitsAtOutputOfTurboEncoderBeforePuncturing/length(puncpat);
                                obj.pTurboPuncturePattern = repmat(puncpat,numPatterns,1);
                            otherwise % case '1/6'
                                puncpat = logical([1; 1; 1; 1; 1; 0; 1]);
                                numPatterns = numBitsAtOutputOfTurboEncoderBeforePuncturing/length(puncpat);
                                obj.pTurboPuncturePattern = repmat(puncpat,numPatterns,1);
                        end
                    otherwise % case 'LDPC'
                        n = round(invr*double(obj.NumBitsInInformationBlock));
                        obj.pLDPCCodeWordLength = n;
                        obj.pK = double(obj.NumBitsInInformationBlock);
                        if obj.IsLDPCOnSMTF
                            obj.pPRNSequenceLength = n*double(obj.LDPCCodeblockSize);
                            obj.pASM = generateASM(obj);
                            obj.pCSM = generateCSM(obj);
                        else
                            obj.pPRNSequenceLength = n;
                            obj.pASM = generateASM(obj);
                        end
                end
            else
                obj.pNumBitsPerSymbol = obj.m_Values(obj.ACMFormat);
                obj.pPRNSequenceLength = 8*obj.pTFLen;
                obj.pASM = generateASM(obj);
                
                % Calculate radii value
                obj.pRadii = getRadiiValue(obj.ACMFormat, obj.pNumBitsPerSymbol);
                
                % Calculate header
                obj.pHeader = getHeaderSymbols(double(obj.ACMFormat),obj.HasPilots);
                
                % Calculate the interleaving indices needed for SCCC
                % encoder
                obj.pInterleavingIndices = getSCCCInterleavingIndices(obj.pK);
                
                % Calculate the puncturing pattern for second convolutional
                % encoder
                obj.pSCCCPuncturePattern2 = getSCCCPuncturePattern2(obj.ACMFormat, obj.pInterleavingIndices);
                
                % Initialize PL randomizer
                n = 8100 + 16*15*obj.HasPilots;
                qpskmap = [1;1j;-1;-1j];
                seq = satcom.internal.ccsds.facmPLScramblingSequence(double(obj.ScramblingCodeNumber),n*16);
                obj.pPLRandomSymbols = reshape(qpskmap(seq+1),n,16);
            end
            obj.pPRNSequence = satcom.internal.ccsds.tmrandseq(obj.pPRNSequenceLength);
        end

        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Set properties in structure s to values in object obj

            % Set public properties and states
            s = saveObjectImpl@matlab.System(obj);
        end

        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s

            % Set public properties and states
            loadObjectImpl@matlab.System(obj,s,wasLocked);
        end

        function validatePropertiesImpl(obj)
            % Validate related or interdependent property values
            
            % Validate if RSShortenedMessageLength is less than or equal to
            % RSMessageLength
            coder.internal.errorIf(double(obj.RSShortenedMessageLength)*obj.IsRSMessageShortened>obj.RSMessageLength,'satcom:ccsdsTMWaveformGenerator:InvalidRSShortenedMessage');
            
            % Validate the NumBitsInInformationBlock for a given channel
            % coding scheme
            coder.internal.errorIf(strcmp(obj.ChannelCoding,'turbo') && ~any([1784,3568,7136,8920]==obj.NumBitsInInformationBlock),...
                'satcom:ccsdsTMWaveformGenerator:InvalidTurboInfoLength',obj.NumBitsInInformationBlock);
            coder.internal.errorIf(strcmp(obj.ChannelCoding,'LDPC') && ~any([1024,4096,16384,7136]==obj.NumBitsInInformationBlock),...
                'satcom:ccsdsTMWaveformGenerator:InvalidLDPCInfoLength',obj.NumBitsInInformationBlock);
            
            % Validate NumBitsInInformationBlock for LDPC code with rate
            % 7/8
            coder.internal.errorIf(strcmp(obj.ChannelCoding,'LDPC') && obj.NumBitsInInformationBlock~=7136 && strcmp(obj.CodeRate,'7/8'),...
                'satcom:ccsdsTMWaveformGenerator:InvalidLDPC7By8Rate');
            
            % Validate CodeRate based on the specified ChannelCoding as
            % LDPC or turbo
            coder.internal.errorIf(strcmp(obj.ChannelCoding,'turbo') && ~any(strcmp(obj.CodeRate,{'1/2','1/3','1/4','1/6'})),...
                'satcom:ccsdsTMWaveformGenerator:InvalidTurboCodeRate',obj.CodeRate);
            coder.internal.errorIf(strcmp(obj.ChannelCoding,'LDPC') && ~any(strcmp(obj.CodeRate,{'1/2','2/3','4/5','7/8'})),...
                'satcom:ccsdsTMWaveformGenerator:InvalidLDPCCodeRate',obj.NumBitsInInformationBlock);
            
            % Validate NumBytesInTransferFrame based on WaveformSource
            if ~strcmp(obj.WaveformSource, "synchronization and channel coding")
                validateattributes(obj.NumBytesInTransferFrame, ...
                    {'double','single','uint16'},{'nonnan','finite',...
                    'scalar','real','positive','integer','<=',2048,...
                    '>=',223},mfilename,'NumBytesInTransferFrame');
            end
            
            % Validate that channel coding of convolutional and 4D-8PSK-TCM
            % does not go together
            coder.internal.errorIf(any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'})) && strcmp(obj.Modulation,'4D-8PSK-TCM'),...
                'satcom:ccsdsTMWaveformGenerator:InvalidModCod');
            
            % Validate SamplesPerSymbols based on Modulation
            if strcmp(obj.Modulation,'PCM/PSK/PM')
                coder.internal.errorIf(obj.SamplesPerSymbol<=2*obj.SubcarrierToSymbolRateRatio,...
                    'satcom:ccsdsTMWaveformGenerator:InvalidSamplingRate');
            end
        end

        function processTunedPropertiesImpl(obj)
            % Perform actions when tunable properties change
            % between calls to the System object
            if obj.pIsFACM
                obj.pK = obj.K_Values(obj.ACMFormat);
                obj.pNumBitsPerSymbol = obj.m_Values(obj.ACMFormat);
                obj.pRadii = getRadiiValue(obj.ACMFormat, obj.pNumBitsPerSymbol);
                obj.pHeader = getHeaderSymbols(double(obj.ACMFormat),obj.HasPilots);
                obj.pInterleavingIndices = getSCCCInterleavingIndices(obj.pK);
                obj.pSCCCPuncturePattern2 = getSCCCPuncturePattern2(obj.ACMFormat, obj.pInterleavingIndices);
            end
        end
    end
    
    % Protected methods useful for functionality implementation
    methods(Access=protected)
        function syncseq = generateASM(obj)
            r = obj.CodeRate;
            chcode = obj.ChannelCoding;
            
            if strcmp(obj.WaveformSource,'synchronization and channel coding') && any(strcmp(chcode,{'turbo','LDPC'}))
                if ~(strcmp(chcode,'LDPC') && obj.IsLDPCOnSMTF)
                    switch (r)
                        case {'1/2', '2/3', '4/5'}
                            syncseq = int8([0;0;0;0;0;0;1;1;0;1;0;0;0;1;1;1;0;1;1;1;0;1;...
                                1;0;1;1;0;0;0;1;1;1;0;0;1;0;0;1;1;1;0;0;1;0;1;0;0;0;...
                                1;0;0;1;0;1;0;1;1;0;1;1;0;0;0;0]); % 0x034776C7272895B0
                        case '1/3'
                            syncseq = int8([0;0;1;0;0;1;0;1;1;1;0;1;0;1;0;1;1;1;0;0;0;0;...
                                0;0;1;1;0;0;1;1;1;0;1;0;0;0;1;0;0;1;1;0;0;1;0;0;0;0;...
                                1;1;1;1;0;1;1;0;1;1;0;0;1;0;0;1;0;1;0;0;0;1;1;0;0;0;...
                                0;1;1;0;1;1;1;1;1;1;0;1;1;1;1;0;0;1;1;1;0;0]); % 0x25D5C0CE8990F6C9461BF79C
                        case '1/4'
                            syncseq = int8([0;0;0;0;0;0;1;1;0;1;0;0;0;1;1;1;0;1;1;1;0;1;...
                                1;0;1;1;0;0;0;1;1;1;0;0;1;0;0;1;1;1;0;0;1;0;1;0;0;0;...
                                1;0;0;1;0;1;0;1;1;0;1;1;0;0;0;0;1;1;1;1;1;1;0;0;1;0;...
                                1;1;1;0;0;0;1;0;0;0;1;0;0;1;0;0;1;1;1;0;0;0;1;1;0;1;...
                                1;0;0;0;1;1;0;1;0;1;1;1;0;1;1;0;1;0;1;0;0;1;0;0;1;1;1;1]); % 0x034776C7272895B0FCB88938D8D76A4F
                        case '1/6'
                            syncseq = int8([0;0;1;0;0;1;0;1;1;1;0;1;0;1;0;1;1;1;0;0;0;0;...
                                0;0;1;1;0;0;1;1;1;0;1;0;0;0;1;0;0;1;1;0;0;1;0;0;0;0;...
                                1;1;1;1;0;1;1;0;1;1;0;0;1;0;0;1;0;1;0;0;0;1;1;0;0;0;...
                                0;1;1;0;1;1;1;1;1;1;0;1;1;1;1;0;0;1;1;1;0;0;1;1;0;1;...
                                1;0;1;0;0;0;1;0;1;0;1;0;0;0;1;1;1;1;1;1;0;0;1;1;0;0;...
                                0;1;0;1;1;1;0;1;1;0;0;1;1;0;1;1;1;1;0;0;0;0;1;0;0;1;...
                                0;0;1;1;0;1;1;0;1;0;1;1;1;0;0;1;1;1;1;0;0;1;0;0;0;0;...
                                0;0;1;0;0;0;0;1;1;0;0;0;1;1]); % 0x25D5C0CE8990F6C9461BF79CDA2A3F31766F0936B9E40863
                        otherwise % case '7/8'
                            syncseq = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;...
                                0;1;1;1;0;1]); % 0x1ACFFC1D
                    end
                    % otherwise % Embedded data stream section 9.6 of CCSDS 131-0.B.3
                    % syncseq = int8([0;0;1;1;0;1;0;1;0;0;1;0;1;1;1;0;1;1;1;1;1;0;0;0;0;1;...
                    % 0;1;0;0;1;1]); % 0x352EF853
                else
                    syncseq = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;...
                        0;1;1;1;0;1]); % 0x1ACFFC1D
                end
            else
                syncseq = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;...
                    0;1;1;1;0;1]); % 0x1ACFFC1D
            end
        end
        
        function syncseq = generateCSM(obj)
            switch(obj.CodeRate)
                case {'1/2','2/3','4/5'}
                    syncseq = int8([0;0;0;0;0;0;1;1;0;1;0;0;0;1;1;1;0;1;1;1;0;1;...
                        1;0;1;1;0;0;0;1;1;1;0;0;1;0;0;1;1;1;0;0;1;0;1;0;0;0;...
                        1;0;0;1;0;1;0;1;1;0;1;1;0;0;0;0]); % 0x034776C7272895B0
                otherwise % case '7/8'
                    syncseq = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;...
                                    0;1;1;1;0;1]); % 0x1ACFFC1D
            end
        end
    end
    
    % Get and set methods
    methods
        % Get methods
        function r = get.CodeRate(obj)
            if obj.NumBitsInInformationBlock==7136 && strcmp(obj.ChannelCoding,'LDPC')
                r = "7/8";
            else
                r = obj.CodeRate;
            end
        end

        % Set methods
        function set.ACMFormat(obj,val)
            prop = 'ACMFormat';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','real','positive','integer','<=',27},mfilename,prop);
            obj.(prop) = double(val);
        end
        
        function set.ChannelCoding(obj,val)
            prop = 'ChannelCoding';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.PCMFormat(obj,val)
            prop = 'PCMFormat';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.WaveformSource(obj,val)
            prop = 'WaveformSource';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.CodeRate(obj,val)
            prop = 'CodeRate';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.ConvolutionalCodeRate(obj,val)
            prop = 'ConvolutionalCodeRate';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.LDPCCodeblockSize(obj,val)
            prop = 'LDPCCodeblockSize';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','integer','positive','<=',8},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.NumBitsInInformationBlock(obj,val)
            prop = 'NumBitsInInformationBlock';
            validateattributes(val,{'double','single','uint16'},{'nonnan','finite','scalar','integer','positive'},mfilename,prop);
            coder.internal.errorIf(~any([1784,3568,7136,8920,1024,4096,16384]==val),'satcom:ccsdsTMWaveformGenerator:InvalidBlockLength',val);
            obj.(prop) = val;
        end
        
        function set.NumBytesInTransferFrame(obj,val)
            prop = 'NumBytesInTransferFrame';
            validateattributes(val, {'double','single','uint16'},{'nonnan','finite','scalar','real','positive','integer','<=',2048},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.RSInterleavingDepth(obj,val)
            prop = 'RSInterleavingDepth';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','integer','positive'},mfilename,prop);
            coder.internal.errorIf(~any([1,2,3,4,5,8]==val), 'satcom:ccsdsTMWaveformGenerator:InvalidRSInterleavingDepth',val);
            obj.(prop) = val;
        end
        
        function set.RSMessageLength(obj,val)
            prop = 'RSMessageLength';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','integer','positive'},mfilename,prop);
            coder.internal.errorIf(~any([223, 239]==val), 'satcom:ccsdsTMWaveformGenerator:InvalidRSMessageLength',val);
            obj.(prop) = val;
        end
        
        function set.RSShortenedMessageLength(obj,val)
            prop = 'RSShortenedMessageLength';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','integer','positive','<=',239},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.BandwidthTimeProduct(obj,val)
            prop = 'BandwidthTimeProduct';
            validateattributes(val,{'double','single'},{'real','nonnan','finite','scalar','positive'},mfilename,prop);
            coder.internal.errorIf(~any([0.5, 0.25]==val), 'satcom:ccsdsTMWaveformGenerator:InvalidBTProduct',num2str(val));
            obj.(prop) = val;
        end
        
        function set.FilterSpanInSymbols(obj,val)
            prop = 'FilterSpanInSymbols';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','real','positive','integer'},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.Modulation(obj,val)
            prop = 'Modulation';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.ModulationEfficiency(obj,val)
            prop = 'ModulationEfficiency';
            validateattributes(val,{'double','single'},{'nonnan','finite','real','scalar','positive'},mfilename,prop);
            coder.internal.errorIf(~any([2,2.25,2.5,2.75]==val),'satcom:ccsdsTMWaveformGenerator:InvalidREff',num2str(val));
            obj.(prop) = val;
        end
        
        function set.ModulationIndex(obj,val)
            prop = 'ModulationIndex';
            validateattributes(val,{'double','single'},{'nonnan','finite','scalar','positive','>=',0.2,'<=',2},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.PulseShapingFilter(obj,val)
            prop = 'PulseShapingFilter';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.RolloffFactor(obj,val)
            prop = 'RolloffFactor';
            validateattributes(val,{'double','single'},{'nonnan','finite','scalar','real','nonnegative','<=',1},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.SamplesPerSymbol(obj,val)
            prop = 'SamplesPerSymbol';
            validateattributes(val,{'double','single','uint16'},{'nonnan','finite','scalar','integer','positive'},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.ScramblingCodeNumber(obj,val)
            prop = 'ScramblingCodeNumber';
            validateattributes(val,{'double','single','uint32'},{'nonnan','finite','scalar','integer','nonnegative','<=',2^18-2},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.SubcarrierToSymbolRateRatio(obj,val)
            prop = 'SubcarrierToSymbolRateRatio';
            validateattributes(val,{'double','single','uint8'},{'nonnan','finite','scalar','integer','positive','<=',50},mfilename,prop);
            obj.(prop) = val;
        end
        
        function set.SubcarrierWaveform(obj,val)
            prop = 'SubcarrierWaveform';
            val = string(validatestring(val, obj.([char(prop), '_Values']), mfilename, prop));
            obj.(prop) = val;
        end
        
        function set.SymbolRate(obj,val)
            prop = 'SymbolRate';
            validateattributes(val,{'double','single'},{'nonnan','finite','scalar','positive'},mfilename,prop);
            obj.(prop) = val;
        end
    end
    
    methods(Access = protected)
        function rsparams = getRSParams(obj)
            rsparams = struct('n',255,'k',double(obj.RSMessageLength),...
                'i',double(obj.RSInterleavingDepth),...
                's',double(obj.RSShortenedMessageLength));
            if ~obj.IsRSMessageShortened
                rsparams.s = rsparams.k;
            end
        end
        function tflen = getNumBytesInTransferFrame(obj)
            obj.pRSParams = getRSParams(obj);
            if strcmp(obj.WaveformSource,'synchronization and channel coding')
                if ~any(strcmp(obj.ChannelCoding,{'none','convolutional','LDPC'}))
                    if any(strcmp(obj.ChannelCoding,{'RS','concatenated'}))
                        if obj.IsRSMessageShortened
                            tflen = obj.pRSParams.s*obj.pRSParams.i;
                        else
                            tflen = obj.pRSParams.k*obj.pRSParams.i;
                        end
                    else % Turbo code
                        tflen = double(obj.NumBitsInInformationBlock)/8; % In bytes
                    end
                else % Channel coding is either none, convolutional, or LDPC
                    if strcmp(obj.ChannelCoding,'LDPC')&&(~obj.IsLDPCOnSMTF)
                        if strcmp(obj.CodeRate,'7/8')
                            tflen = 892; % 7136 bits always. See section 7.3 of CCSDS 131.0-B-3
                        else
                            tflen = double(obj.NumBitsInInformationBlock)/8; % In bytes
                        end
                    else
                        tflen = double(obj.NumBytesInTransferFrame);
                    end
                end
            else % FACM waveform
                tflen = double(obj.NumBytesInTransferFrame);
            end
        end
        
        function r = getInverseCodeRate(obj)
            if any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'}))
                switch(obj.ConvolutionalCodeRate)
                    case '1/2'
                        r = 2;
                    case '2/3'
                        r = 3/2;
                    case '3/4'
                        r = 4/3;
                    case '5/6'
                        r = 6/5;
                    otherwise % case '7/8'
                        r = 8/7;
                end
            else
                switch(obj.CodeRate)
                    case '1/2'
                        r = 2;
                    case '2/3'
                        r = 3/2;
                    case '4/5'
                        r = 5/4;
                    case '1/3'
                        r = 3;
                    case '1/4'
                        r = 4;
                    case '1/6'
                        r = 6;
                    otherwise % case '7/8' of LDPC which is 223/255
                        r = 255/223;
                end
            end
        end
    end
end

% Local functions
function r = getRadiiValue(ACMFormat, m)

switch(ACMFormat)
    case 13
        RadiiRatio = 3.15;
    case 14
        RadiiRatio = 3.15;
    case 15
        RadiiRatio = 2.85;
    case 16
        RadiiRatio = 2.75;
    case 17
        RadiiRatio = 2.60;
    case 18
        RadiiRatio = [2.84;5.27];
    case 19
        RadiiRatio = [2.84;5.27];
    case 20
        RadiiRatio = [2.84;5.27];
    case 21
        RadiiRatio = [2.72;4.87];
    case 22
        RadiiRatio = [2.54;4.33];
    otherwise % 64APSK modulation
        RadiiRatio = [2.73;4.52;6.31];
end
r = 1;
switch(m)
    case 4
        radius1 = sqrt(4/(1+3*(RadiiRatio(1)^2)));
        radius2 = RadiiRatio(1)*radius1; % This and the above equation are formed by solving for R1 and R2 from
        % RadiiRatio(1) = R2/R1 and from the unit energy constraint,
        % R1^2+3*R2^2 = 4.
        r = [radius1;radius2];
    case 5
        radius1 = sqrt(8/(1+3*(RadiiRatio(1)^2)+4*(RadiiRatio(2)^2)));
        radius2 = RadiiRatio(1)*radius1;
        radius3 = RadiiRatio(2)*radius1; % This and the above 2 equations are formed by solving for R1, R2 and R3 from
        % RadiiRatio(1) = R2/R1, RadiiRatio(2) = R3/R1
        % and from the unit energy constraint, R1^2 + 3*R2^2 + 4*R3^2 = 8.
        r = [radius1;radius2;radius3];
    case 6
        radius1 = sqrt(16/(1+3*(RadiiRatio(1)^2)+5*(RadiiRatio(2)^2)+7*(RadiiRatio(3)^2)));
        radius2 = RadiiRatio(1)*radius1;
        radius3 = RadiiRatio(2)*radius1;
        radius4 = RadiiRatio(3)*radius1; % This and the above 2 equations are formed by solving for R1, R2, R3 and R4 from
        % RadiiRatio(1) = R2/R1, RadiiRatio(2) = R3/R1, RadiiRatio(3) = R4/R1
        % and from the unit energy constraint, R1^2 + 3*R2^2 + 5*R3^2 + 7*R4^2 = 16.
        r = [radius1;radius2;radius3;radius4];
end
end

function sym = getHeaderSymbols(ACMFormat,HasPilots)

% Following FrameMarker can be generated using comm.GoldSequence as
% shown in following code:
% H = comm.GoldSequence('FirstPolynomial','z^8+z^6+z^5+z^4+1',...
%     'FirstInitialConditions',[1 0 0 1 0 1 1 0],'SecondPolynomial',...
%     'z^8 + z^6 + z^5 + z^4 + z^3 + z + 1','SecondInitialConditions',...
%     [0 1 0 0 1 0 0 1],'SamplesPerFrame',256);
% FrameMarker = H();
FrameMarker = [1;1;1;1;1;0;1;1;0;1;0;0;0;1;0;0;0;0;0;1;1;1;1;1;...
    0;0;0;1;1;1;0;1;1;0;1;1;1;1;0;1;1;1;0;1;0;1;1;1;0;1;1;1;0;1;...
    1;0;1;1;1;1;0;0;1;0;0;0;1;1;0;1;0;0;0;1;1;1;1;0;0;1;1;1;0;1;...
    1;0;1;0;0;0;0;1;0;0;0;0;1;0;1;1;0;1;0;0;1;0;1;1;0;0;1;1;1;0;...
    1;0;1;0;1;1;1;0;0;1;1;1;0;1;0;1;1;1;1;1;0;1;0;1;1;1;0;1;0;1;...
    1;0;1;1;1;1;1;1;0;0;0;1;1;1;1;0;0;1;1;1;0;0;0;0;1;1;0;0;1;0;...
    1;0;1;1;1;0;1;1;1;0;1;1;0;0;1;1;1;1;1;0;0;1;0;1;0;0;1;0;0;0;...
    0;1;0;1;1;1;0;0;1;1;0;1;1;1;1;0;1;1;0;0;1;1;1;0;0;1;0;1;0;0;...
    0;1;1;0;1;0;1;1;1;1;0;0;0;1;0;1;0;0;0;0;0;1];

% Calculate header
biACM = comm.internal.utilities.de2biBase2LeftMSB(ACMFormat,5);
BiOrthogonalEncoderInput = [logical(biACM');HasPilots];
FrameDescriptor = biOrthogonalEncode(BiOrthogonalEncoderInput);
plHeaderBits = [FrameMarker;FrameDescriptor];
% pi/2 - BPSK modulation
sym = complex(zeros(320,1));
modSymb = (1-2*plHeaderBits)/sqrt(2);
sym(1:2:end) = modSymb(1:2:end)+1j*modSymb(1:2:end);
sym(2:2:end) = -modSymb(2:2:end)+1j*modSymb(2:2:end);
end

function encoded = biOrthogonalEncode(bits)
genMat = [0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1; ...
    0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1; ...
    0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1; ...
    0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1; ...
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1; ...
    1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1];

scramSeq = [0 1 1 1 0 0 0 1 1 0 0 1 1 1 0 1 1 0 0 0 0 0 1 1 1 1 0 0 1 0 0 1 0 1 0 1 0 0 1 1 0 1 0 0 0 0 1 0 0 0 1 0 1 1 0 1 1 1 1 1 1 0 1 0]';

encoded = zeros(64,1);

n = mod(bits(:)'*genMat,2);
encoded(1:2:end) = n;
encoded(2:2:end) = n;

encoded = xor(encoded, scramSeq);
end

function InterleavingIndices = getSCCCInterleavingIndices(k)
IVal = 3*(k+2)/2;
SCCCInterleaverParameters = satcom.internal.ccsds.scccInterleaverParameters(IVal);
alpha = SCCCInterleaverParameters(:,1);
beta = SCCCInterleaverParameters(:,2);
piVal = zeros(IVal,1);
WVal = IVal/120;
for idx = 0:IVal-1
    piVal(idx+1,1) = WVal*(mod(floor(idx/WVal)+beta(mod(idx,WVal)+1),120)) + alpha(mod(idx,WVal)+1) + 1;
end
InterleavingIndices = piVal;
end

function SCCCPuncturePattern2 = getSCCCPuncturePattern2(ACMFormat, InterleavingIndices)
% Calculate puncture positions
Ssur_Values = [300;300;274;251;234;218;292;240;250;234;221;214;255;241;...
    230;220;211;245;234;224;217;210;236;228;220;214;208];
PuncturePosition_Values = [76;1;145;214;256;37;109;181;277;235;...
    55;127;163;19;199;91;289;244;64;268;223;136;172;28;100;190;10;...
    46;118;154;81;207;259;292;232;67;280;247;147;30;111;183;6;48;...
    93;165;129;219;195;270;72;15;297;211;138;102;174;39;250;57;...
    120;156;84;229;193;283;262;25;238;60;201;294;132;96;159;34;...
    265;114;177;225;79;12;151;51;274;204;105;4;241;169;69;124;22;...
    216;285;141;252;187;206;36];
Ssur = Ssur_Values(ACMFormat);
AvailableSsur = 299:-1:200;
idx = find(AvailableSsur==Ssur, 1);
if ~isempty(idx)
    PuncturePositions = PuncturePosition_Values(1:idx(1));
else
    PuncturePositions = zeros(0,1);
end

pattern = true(300,1);
pattern(PuncturePositions+1,1) = false;
jVal = mod(InterleavingIndices-1,300)+1;
SCCCPuncturePattern2 = pattern(jVal);
end

% LocalWords:  FCB CDA syncseq gettrellis nxtst istate de msb outbit tempnxtst
