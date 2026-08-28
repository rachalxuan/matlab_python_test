% Short raw-H link-budget A/B: only change the pre-H signal level.
clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

levels = [-10 0];
rows = cell(numel(levels),1);
for k = 1:numel(levels)
    o = struct();
    o.modTypes = {'QPSK'};
    o.hModelCases = { ...
        'std7_Corazza','E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};
    o.includeNoHBaseline = false;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = true;
    o.includeNormHScenario = false;
    o.includeNoEqualizerScenario = false;
    o.includeUncoded = true;
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
    o.inputLevelDbm = levels(k);
    o.enableConverterChain = false;
    o.enableADCEquivalent = false;
    o.AGCEnabled = false;
    o.equalizerMode = 'blind-cma-lms';
    o.randomSeed = 20260826;
    o.SeedMode = 'pairedChannelProfile';
    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 18;
    o.showFigures = false;
    o.debugHFrameStats = true;
    o.debugHFrameStatsStart = 1;
    o.debugHFrameStatsCount = 4;
    o.outputDir = sprintf(['E:/web_code/react/fft_project/react-fft/', ...
        'artifacts/ccsds/input_level_ab/qpsk_std7_raw_%+ddbm'],levels(k));
    o.Resume = false;
    o.RerunFailed = false;
    rows{k} = sweep_h_channel_short_frames(o);
end

T = vertcat(rows{:});
T.InputLevel_dBm = repelem(levels(:),cellfun(@height,rows));
disp(T(:,{'InputLevel_dBm','Scenario','ModType','BER','LockRate_pct', ...
    'FER','EVM_post_pct','MER_dB','HGain_dB','NoiseEquivalentSNR_dB', ...
    'WaveformDuration_s','HSourceDuration_s','Status'}));
