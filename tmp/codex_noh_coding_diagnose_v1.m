function T = codex_noh_coding_diagnose_v1(caseName, outputTag, frameSyncASMErrorThreshold)
%CODEX_NOH_CODING_DIAGNOSE_V1 Focused, read-only NoH coding diagnostics.
%   This script changes no receiver algorithm.  It only selects one failed
%   system-profile case and enables existing boundary/rail debug output.

    if nargin < 1 || isempty(caseName)
        caseName = 'conv_16qam_split_after';
    end
    if nargin < 2 || isempty(outputTag)
        outputTag = char(string(caseName));
    end
    if nargin < 3
        frameSyncASMErrorThreshold = [];
    end

    rootDir = 'E:/web_code/react/fft_project/react-fft';
    addpath(fullfile(rootDir, 'src/python'), '-begin');
    o = struct();
    o.modTypes = {'16QAM'};
    o.hModelCases = {};
    o.includeNoHBaseline = true;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = false;
    o.includeNormHScenario = false;
    o.includeNoEqualizerScenario = false;
    o.includeUncoded = false;
    o.includeRS = false;
    o.includeConvolutional = false;
    o.includeLDPC = false;
    o.includeTurbo = false;
    o.includeTPC = false;
    o.symbolRate = 10e6;
    o.sps = 8;
    o.berWarmUpFrames = 8;
    o.berFrames = 30;
    o.excludeBERWarmUpFrames = true;
    o.noisePlacement = 'afterChannel';
    o.noiseMode = 'psd';
    o.noisePSDdBmHz = -115.3;
    o.noiseBandwidthHz = [];
    o.inputLevelDbm = -10;
    o.RandomizerEnabled = false;
    o.RandomizerFECPosition = 'afterEncoding';
    o.DataPathMode = 'single';
    o.ConvolutionalG1G2Mode = 'G1G2-inverted';
    o.GMSKDetectionMode = 'official-viterbi-frame-reset';
    o.useTMAPSKPilots = false;
    o.APSKReceiverMode = 'pilotless';
    o.enableQAMBlindPhaseSearch = true;
    o.enableQAMPowerGainTracker = true;
    o.randomSeed = 20260824;
    o.SeedMode = 'pairedChannelProfile';
    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 0;
    o.collectPredecoderStats = true;
    o.debugCodedBoundary = true;
    o.debugCodedFrameSyncPrintLimit = 4;
    o.debugResetCodedFrameSyncPerSplitCandidate = true;
    o.predecoderMaxOffsetBits = 64;
    o.debugFrameCheck = true;
    o.debugFrameCheckCount = 40;
    o.debugAllPerFrameBER = true;
    o.splitPathDebug = true;
    o.debugTPC = true;
    o.debugConvolutionalG1G2 = true;
    o.showFigures = false;
    o.clearFunctionCache = false;
    o.Resume = false;
    o.RerunFailed = false;
    if ~isempty(frameSyncASMErrorThreshold)
        o.FrameSyncASMErrorThreshold = double(frameSyncASMErrorThreshold);
    end

    switch lower(string(caseName))
        case "conv_16qam_split_after"
            o.modTypes = {'16QAM'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'afterEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_16apsk_split_before"
            o.modTypes = {'16APSK'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'beforeEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_16apsk_split_after"
            o.modTypes = {'16APSK'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'afterEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_32apsk_split_off"
            o.modTypes = {'32APSK'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = false;
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_32apsk_split_after"
            o.modTypes = {'32APSK'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'afterEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_32qam_split_before"
            o.modTypes = {'32QAM'};
            o.DataPathMode = 'dualIQ';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'beforeEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "conv_16qam_single_after"
            o.modTypes = {'16QAM'};
            o.DataPathMode = 'single';
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'afterEncoding';
            o.includeConvolutional = true;
            o.convRates = {'1/2'};
        case "tpc_gmsk_off"
            o.modTypes = {'GMSK'};
            o.includeTPC = true;
            o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
        case "tpc_gmsk_after"
            o.modTypes = {'GMSK'};
            o.RandomizerEnabled = true;
            o.RandomizerFECPosition = 'afterEncoding';
            o.includeTPC = true;
            o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
        case "tpc_16qam_off"
            o.modTypes = {'16QAM'};
            o.includeTPC = true;
            o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
        case "tpc_32qam_off"
            o.modTypes = {'32QAM'};
            o.includeTPC = true;
            o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
        otherwise
            error('codex_noh_coding_diagnose_v1:UnknownCase', ...
                'Unknown caseName: %s', char(string(caseName)));
    end

    o.outputDir = fullfile(rootDir, 'artifacts', 'ccsds', ...
        ['noh_coding_diag_' char(string(outputTag))]);
    T = sweep_h_channel_short_frames(o);
    disp(T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
        'BER','PredecoderBER','LockRate_pct','FER','CountedFrames', ...
        'MatchedFrames','Status'}));
end
