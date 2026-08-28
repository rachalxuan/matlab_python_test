clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Strict OFF/ON comparison for the shared blind reliability controller.
% It covers both the NoH regression and the normalized std4 fade case.
rootOut = ['E:/web_code/react/fft_project/react-fft/' ...
    'artifacts/ccsds/shared_reliability_std4_ab_v1'];

allT = table();
for enabled = [false true]
    o = struct();
    o.modTypes = {'16QAM','32QAM'};
    o.hModelCases = { ...
        'std4_ITU_P681', ...
        'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};

    o.includeNoHBaseline = true;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = false;
    o.includeNormHScenario = true;
    o.includeNoEqualizerScenario = false;

    o.includeUncoded = false;
    o.includeRS = false;
    o.includeConvolutional = false;
    o.includeLDPC = false;
    o.includeTurbo = false;
    o.includeTPC = true;
    o.tpcCases = {struct( ...
        'TPCCodeRate','1/2','TPCBlocksPerTF',8)};

    o.symbolRate = 10e6;
    o.sps = 8;
    o.berWarmUpFrames = 8;
    o.berFrames = 30;
    o.excludeBERWarmUpFrames = true;
    o.channelOutOfRangeMode = 'wrap';

    o.noisePlacement = 'afterChannel';
    o.noiseMode = 'psd';
    o.noisePSDdBmHz = -115.3;
    o.noiseBandwidthHz = [];
    o.inputLevelDbm = -10;

    o.RandomizerEnabled = false;
    o.RandomizerFECPosition = 'afterEncoding';
    o.randomSeed = 1;
    o.SeedMode = 'pairedChannelProfile';

    % Only this switch differs between the two runs.
    o.enableBlindReliabilityManager = enabled;
    o.blindReliabilityWindowSymbols = 32;
    o.blindReliabilityAcquireSymbols = 256;
    o.blindReliabilityReferenceTauSymbols = 4096;
    o.blindReliabilityFadeEnterDB = -12;
    o.blindReliabilityFadeExitDB = -8;
    o.blindReliabilityFadeEnterWindows = 2;
    o.blindReliabilityRecoverWindows = 4;
    o.blindReliabilityMaxInverseGainDB = 18;
    o.debugBlindReliabilityManager = true;

    o.collectPredecoderStats = true;
    o.debugCodedBoundary = true;
    o.debugPredecoderMaxBurstFrames = 16;
    o.debugTPC = true;
    o.debugAdaptiveEqualizer = true;
    o.debugSynchronizationChain = true;
    o.debugHFrameStats = true;
    o.debugHFrameStatsStart = 1;
    o.debugHFrameStatsCount = 40;
    o.debugSyncSegmentCount = 38;

    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 18;
    o.showFigures = false;

    tag = 'off';
    if enabled
        tag = 'on';
    end
    o.outputDir = sprintf('%s_%s',rootOut,tag);
    o.Resume = false;
    o.RerunFailed = false;

    fprintf('\n============================================================\n');
    fprintf(' SHARED RELIABILITY: %s\n',upper(tag));
    fprintf('============================================================\n');
    T = sweep_h_channel_short_frames(o);
    T.ReliabilityAB = repmat(string(upper(tag)),height(T),1);
    allT = [allT; T]; %#ok<AGROW>
end

fields = { ...
    'ReliabilityAB','Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','PredecoderSteadyBER', ...
    'PredecoderFrameBERP95','PredecoderFrameBERMax', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'BlindReliabilityApplied','BlindReliabilityFinalState', ...
    'BlindReliabilityHoldFraction_pct','BlindReliabilityHoldEvents', ...
    'BlindReliabilityRecoverEvents', ...
    'BlindReliabilityMinRelativePower_dB', ...
    'BlindReliabilityMaxInverseGain_dB','Status'};
fields = fields(ismember(fields,allT.Properties.VariableNames));
D = allT(:,fields);
disp(D);

writetable(D,[rootOut '_comparison.csv']);
fprintf('\nA/B comparison: %s_comparison.csv\n',rootOut);

