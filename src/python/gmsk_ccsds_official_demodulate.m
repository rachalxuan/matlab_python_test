function [softBits, info] = gmsk_ccsds_official_demodulate(inputWaveform, cfg)
%GMSK_CCSDS_OFFICIAL_DEMODULATE Production CCSDS GMSK receiver entry point.
%
% This is the only production entry point for the official GMSK detector.
% It owns the complete sequence required by this transmitter:
%   1. comm.GMSKDemodulator Viterbi detection.
%   2. Fixed traceback-delay removal and polarity conversion.
%   3. Per-frame CCSDS transition-precode recovery using the known ASM.
%
% The official detector supports uncoded, convolutional, ordinary TM LDPC,
% Turbo, and TPC frames with HasASM=true.  LDPC-on-SMTF has a different frame
% layout and is rejected explicitly; it never falls back to the legacy
% detector.

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end

    channelCoding = lower(string(localField(cfg, 'ChannelCoding', 'none')));
    hasASM = logical(localField(cfg, 'HasASM', false));
    codeRate = localField(cfg, 'CodeRate', []);
    numInformationBits = localField(cfg, 'NumBitsInInformationBlock', []);
    isLDPCOnSMTF = logical(localField(cfg, 'IsLDPCOnSMTF', false));
    tpcBlocksPerTF = localField(cfg, 'TPCBlocksPerTF', []);
    tpcCodeRate = localField(cfg, 'TPCCodeRate', []);

    localValidateCodingMetadata(channelCoding, codeRate, ...
        numInformationBits, isLDPCOnSMTF, tpcBlocksPerTF);

    supportedCoding = channelCoding == "none" || ...
        contains(channelCoding, "convolutional") || ...
        channelCoding == "ldpc" || channelCoding == "turbo" || ...
        channelCoding == "tpc";

    if ~hasASM
        error('gmsk_ccsds_official_demodulate:ASMRequired', ...
            ['The official CCSDS GMSK receiver requires HasASM=true ', ...
             'for per-frame transition-precode state recovery.']);
    end
    if ~supportedCoding
        error('gmsk_ccsds_official_demodulate:UnsupportedCoding', ...
            ['Official CCSDS GMSK demodulation is not implemented for ', ...
             'ChannelCoding="%s". Supported now: none, convolutional, ', ...
             'ordinary TM LDPC, Turbo, and TPC. ', ...
             'Legacy fallback is forbidden.'], char(channelCoding));
    end

    samplesPerSymbol = localField(cfg, 'SamplesPerSymbol', 8);
    bt = localField(cfg, 'BandwidthTimeProduct', 0.5);
    if isempty(codeRate)
        % Code rate does not participate in the uncoded frame layout.
        codeRate = 'N/A';
    end
    numBytes = localField(cfg, 'NumBytesInTransferFrame', 1115);
    asmBits = localField(cfg, 'ASMBits', []);
    pcmFormat = localField(cfg, 'PCMFormat', 'NRZ-L');
    printDebug = logical(localField(cfg, 'PrintDebug', false));

    % Algorithm constants are intentionally internal.  They are not link
    % or waveform configuration and must not be exposed as sweep knobs.
    officialCfg = struct( ...
        'SamplesPerSymbol', samplesPerSymbol, ...
        'BandwidthTimeProduct', bt, ...
        'TracebackDepth', 32, ...
        'OutputScale', 5);
    [rawMetric, viterbiInfo] = ...
        gmsk_official_viterbi_raw_metric(inputWaveform, officialCfg);

    codingCfg = struct( ...
        'NumBitsInInformationBlock', numInformationBits, ...
        'IsLDPCOnSMTF', isLDPCOnSMTF, ...
        'TPCBlocksPerTF', tpcBlocksPerTF, ...
        'TPCCodeRate', tpcCodeRate);
    if isfield(cfg, 'LDPCCodeblockSize')
        codingCfg.LDPCCodeblockSize = cfg.LDPCCodeblockSize;
    end
    templateCfg = gmsk_frame_reset_asm_config( ...
        char(channelCoding), codeRate, numBytes, asmBits, pcmFormat, ...
        codingCfg);
    if isempty(templateCfg.asmTemplates)
        error('gmsk_ccsds_official_demodulate:ASMTemplate', ...
            ['The ASM templates are not rectangular for coding="%s", ', ...
             'rate="%s". Legacy fallback is forbidden.'], ...
            char(channelCoding), char(string(codeRate)));
    end

    resetCfg = struct();
    resetCfg.framePeriodBits = templateCfg.framePeriodBits;
    resetCfg.asmTemplates = templateCfg.asmTemplates;
    resetCfg.asmOffsetBits = templateCfg.asmOffsetBits;
    resetCfg.asmMaxErrors = max(2, ...
        ceil(0.20 * size(resetCfg.asmTemplates, 1)));
    resetCfg.asmMinGap = max(3, ...
        ceil(0.25 * size(resetCfg.asmTemplates, 1)));
    resetCfg.maxSearchFrames = 8;
    resetCfg.minSearchFrames = 2;
    resetCfg.printDebug = printDebug;
    resetCfg.inputIsRawMetric = true;

    [frameResetData, frameResetInfo] = ...
        gmsk_frame_reset_demodulate(rawMetric, resetCfg);

    detectorSucceeded = frameResetInfo.GridFound && ...
        ~isempty(frameResetData);
    if detectorSucceeded
        softBits = frameResetData;
        failureReason = '';
    else
        % A phase hypothesis that cannot find the ASM is an unlocked
        % candidate, not permission to mix in another detector.
        softBits = zeros(size(rawMetric));
        failureReason = frameResetInfo.FailureReason;
    end

    info = struct();
    info.GMSKDetectorUsed = 'official';
    info.DetectorSucceeded = detectorSucceeded;
    info.FailureReason = failureReason;
    info.ChannelCoding = char(channelCoding);
    info.CodeRate = char(string(codeRate));
    info.FramePeriodBits = templateCfg.framePeriodBits;
    if isfield(templateCfg, 'codewordLength')
        info.CodewordLength = templateCfg.codewordLength;
    end
    if ~isempty(numInformationBits)
        info.NumBitsInInformationBlock = double(numInformationBits);
    end
    if channelCoding == "ldpc"
        info.IsLDPCOnSMTF = isLDPCOnSMTF;
    elseif channelCoding == "tpc"
        info.TPCBlocksPerTF = double(tpcBlocksPerTF);
        info.TPCCodeRate = char(string(tpcCodeRate));
    end
    info.Viterbi = viterbiInfo;
    info.FrameReset = frameResetInfo;
end

function localValidateCodingMetadata(channelCoding, codeRate, ...
        numInformationBits, isLDPCOnSMTF, tpcBlocksPerTF)
    if contains(channelCoding, "convolutional") && isempty(codeRate)
        error('gmsk_ccsds_official_demodulate:MissingCodeRate', ...
            ['Convolutionally coded official GMSK requires the ', ...
             'transmitter ConvolutionalCodeRate.']);
    end

    if channelCoding == "ldpc" || channelCoding == "turbo"
        if isempty(codeRate)
            error('gmsk_ccsds_official_demodulate:MissingCodeRate', ...
                ['Official GMSK with ChannelCoding="%s" requires the ', ...
                 'transmitter CodeRate.'], char(channelCoding));
        end
        if isempty(numInformationBits) || ~isnumeric(numInformationBits) || ...
                ~isscalar(numInformationBits) || ...
                ~isfinite(double(numInformationBits)) || ...
                double(numInformationBits) <= 0 || ...
                mod(double(numInformationBits), 1) ~= 0
            error(['gmsk_ccsds_official_demodulate:', ...
                   'InvalidInformationBlockLength'], ...
                ['Official GMSK with ChannelCoding="%s" requires a ', ...
                 'positive integer NumBitsInInformationBlock.'], ...
                char(channelCoding));
        end
    end

    if channelCoding == "ldpc"
        if isLDPCOnSMTF
            error(['gmsk_ccsds_official_demodulate:', ...
                   'LDPCOnSMTFUnsupported'], ...
                ['Official GMSK currently supports ordinary TM LDPC ', ...
                 '(raw ASM + one LDPC codeword), not LDPC-on-SMTF. ', ...
                 'Legacy fallback is forbidden.']);
        end
        localValidateLDPCConfiguration( ...
            double(numInformationBits), codeRate);
    elseif channelCoding == "turbo"
        localValidateTurboConfiguration( ...
            double(numInformationBits), codeRate);
    elseif channelCoding == "tpc"
        if isempty(tpcBlocksPerTF) || ~isnumeric(tpcBlocksPerTF) || ...
                ~isscalar(tpcBlocksPerTF) || ...
                ~isfinite(double(tpcBlocksPerTF)) || ...
                double(tpcBlocksPerTF) <= 0 || ...
                mod(double(tpcBlocksPerTF), 1) ~= 0
            error(['gmsk_ccsds_official_demodulate:', ...
                   'InvalidTPCBlocksPerTF'], ...
                'TPCBlocksPerTF must be a positive integer for official GMSK.');
        end
    end
end

function localValidateLDPCConfiguration(informationBits, codeRate)
    rateKey = char(string(codeRate));
    if informationBits == 7136
        valid = strcmp(rateKey, '7/8');
    else
        valid = any(informationBits == [1024 4096 16384]) && ...
            any(strcmp(rateKey, {'1/2','2/3','4/5'}));
    end
    if ~valid
        error(['gmsk_ccsds_official_demodulate:', ...
               'InvalidLDPCConfiguration'], ...
            ['Unsupported ordinary TM LDPC configuration k=%d, ', ...
             'CodeRate="%s". Use k=1024/4096/16384 with ', ...
             '1/2, 2/3, or 4/5; or k=7136 with 7/8.'], ...
            informationBits, rateKey);
    end
end

function localValidateTurboConfiguration(informationBits, codeRate)
    rateKey = char(string(codeRate));
    valid = any(informationBits == [1784 3568 7136 8920]) && ...
        any(strcmp(rateKey, {'1/2','1/3','1/4','1/6'}));
    if ~valid
        error(['gmsk_ccsds_official_demodulate:', ...
               'InvalidTurboConfiguration'], ...
            ['Unsupported Turbo configuration k=%d, CodeRate="%s". ', ...
             'Use k=1784/3568/7136/8920 with 1/2, 1/3, 1/4, or 1/6.'], ...
            informationBits, rateKey);
    end
end

function value = localField(s, name, defaultValue)
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = defaultValue;
    end
end
