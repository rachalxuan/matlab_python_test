clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

allT = table();
for enabled = [false true]
    o = struct();
    o.modTypes = {'16QAM'};
    o.hModelCases = {'std4_ITU_P681', ...
        'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
    o.includeNoHBaseline = false;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = false;
    o.includeNormHScenario = true;
    o.includeNoEqualizerScenario = false;
    o.includeUncoded = true;
    o.includeRS = false;
    o.includeConvolutional = false;
    o.includeLDPC = false;
    o.includeTurbo = false;
    o.includeTPC = false;
    o.symbolRate = 10e6;
    o.sps = 8;
    o.berWarmUpFrames = 4;
    o.berFrames = 52;
    o.excludeBERWarmUpFrames = true;
    o.noisePlacement = 'afterChannel';
    o.noiseMode = 'psd';
    o.noisePSDdBmHz = -115.3;
    o.inputLevelDbm = -10;
    o.RandomizerEnabled = false;
    o.randomSeed = 1;
    o.SeedMode = 'pairedChannelProfile';
    o.enableBlindReliabilityManager = enabled;
    o.debugBlindReliabilityManager = true;
    o.debugAdaptiveEqualizer = true;
    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 18;
    o.showFigures = false;
    tag = 'off';
    if enabled
        tag = 'on';
    end
    o.outputDir = sprintf(['E:/web_code/react/fft_project/react-fft/' ...
        'artifacts/ccsds/shared_reliability_std4_uncoded_ab_v1_%s'],tag);
    o.Resume = false;
    o.RerunFailed = false;
    T = sweep_h_channel_short_frames(o);
    T.ReliabilityAB = repmat(string(upper(tag)),height(T),1);
    allT = [allT; T]; %#ok<AGROW>
end

fields = {'ReliabilityAB','Scenario','ModType','BER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','BlindReliabilityApplied', ...
    'BlindReliabilityFinalState','BlindReliabilityHoldFraction_pct', ...
    'BlindReliabilityHoldEvents','BlindReliabilityRecoverEvents', ...
    'BlindReliabilityMinRelativePower_dB','Status'};
fields = fields(ismember(fields,allT.Properties.VariableNames));
D = allT(:,fields);
disp(D);
writetable(D,['E:/web_code/react/fft_project/react-fft/artifacts/ccsds/' ...
    'shared_reliability_std4_uncoded_ab_v1_comparison.csv']);

