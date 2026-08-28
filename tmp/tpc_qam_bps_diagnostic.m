clearvars; clear classes; rehash;
rootDir = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(rootDir, 'src/python'), '-begin');

base = struct();
base.modTypes = {'16QAM','32QAM'};
base.hModelCases = { ...
    'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
base.includeNoHBaseline = true;
base.includeNoHEqualizedBaseline = false;
base.includeHEqualized = false;
base.includeNormHScenario = true;
base.includeNoEqualizerScenario = false;
base.includeUncoded = false;
base.includeRS = false;
base.includeConvolutional = false;
base.includeLDPC = false;
base.includeTurbo = false;
base.includeTPC = true;
base.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
base.symbolRate = 10e6;
base.sps = 8;
base.berWarmUpFrames = 4;
base.berFrames = 10;
base.excludeBERWarmUpFrames = true;
base.noisePlacement = 'afterChannel';
base.noiseMode = 'psd';
base.noisePSDdBmHz = -115.3;
base.noiseBandwidthHz = [];
base.inputLevelDbm = -10;
base.channelOutOfRangeMode = 'wrap';
base.equalizerMode = 'blind-cma-lms';
base.RandomizerEnabled = false;
base.RandomizerFECPosition = 'afterEncoding';
base.randomSeed = 20260824;
base.SeedMode = 'pairedChannelProfile';
base.maxGoodBER = 1e-5;
base.maxGoodFER = 0;
base.minGoodLockPct = 90;
base.minGoodMERdB = 0;
base.collectPredecoderStats = true;
base.debugCodedBoundary = false;
base.showFigures = false;
base.clearFunctionCache = false;
base.Resume = false;
base.RerunFailed = false;

rows = table();
for enabled = [true false]
    o = base;
    o.enableQAMBlindPhaseSearch = enabled;
    o.enableQAMBlindPhaseSearchForTPC = enabled;
    o.outputDir = fullfile(rootDir, 'artifacts/ccsds/tpc_qam_bps_diagnostic', ...
        sprintf('bps_%s', string(enabled)));
    T = sweep_h_channel_short_frames(o);
    T.QAMBPS = repmat(enabled, height(T), 1);
    rows = [rows; T]; %#ok<AGROW>
end

D = rows(:, {'QAMBPS','Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'Status'});
disp(D);
writetable(D, fullfile(rootDir, ...
    'artifacts/ccsds/tpc_qam_bps_diagnostic/summary_ab.csv'));
