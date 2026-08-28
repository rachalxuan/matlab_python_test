clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

minConfidence = [0 0.005 0.02 0.05];
fadeThreshold = [-40 -30 -22 -12];
D = table('Size',[numel(minConfidence),8], ...
    'VariableTypes',repmat({'double'},1,8), ...
    'VariableNames',{'MinConfidence','FadeThresholdDB','BER','LockPct', ...
    'FER','EVM','MER','ResidualCFO'});

for k = 1:numel(minConfidence)
    p = struct();
    p.modType = '32QAM';
    p.channelCoding = 'none';
    p.symbolRate = 10e6;
    p.sps = 8;
    p.berWarmUpFrames = 8;
    p.berFrames = 50;
    p.excludeBERWarmUpFrames = true;
    p.enableHChannel = true;
    p.HMode = 'h_matrix_file';
    p.channelFilePath = ...
        'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat';
    p.channelInterpolationMethod = 'linear';
    p.channelOutOfRangeMode = 'wrap';
    p.interpolateChannelDelays = false;
    p.normalizeHChannel = true;
    p.enableEqualizer = false;
    p.equalizerMode = 'off';
    p.noisePlacement = 'afterChannel';
    p.noiseMode = 'psd';
    p.noisePSDdBmHz = -115.3;
    p.noiseBandwidthHz = [];
    p.inputLevelDbm = -10;
    p.enableAdaptiveFastEnvelopeTracker = true;
    p.enableAdaptiveFastPhaseTracker = false;
    p.enableQAMBlindPhaseSearch = true;
    p.QAMBlindPhaseSearch = struct( ...
        'NumTestPhases',61, ...
        'WindowSymbols',33, ...
        'HopSymbols',4, ...
        'MetricPowerWindowSymbols',33, ...
        'MinConfidence',minConfidence(k), ...
        'FadeThresholdDB',fadeThreshold(k), ...
        'TrajectoryAlpha',0.85, ...
        'FrequencyAlpha',0.20, ...
        'MaxInnovationRad',deg2rad(35), ...
        'ReacquireReliableBlocks',3, ...
        'PreserveInitialPhase',false, ...
        'MaxFrequencyRadPerSymbol',0.10);
    p.enableQAMPowerGainTracker = true;
    p.QAMPowerGainTracker = struct( ...
        'MagnitudeEstimationMode','power', ...
        'UpdatePowerReference',false, ...
        'FadePowerTauSymbols',16, ...
        'EnableFadeHold',false, ...
        'MaxInverseGainDB',24);
    p.enableASMFramePhaseCorrection = true;
    p.asmFramePhaseCorrectionMaxError = 6;
    p.asmFramePhaseCorrectionMinGap = 4;
    p.asmFramePhaseCorrectionMinReliableFraction = 0.80;
    p.randomSeed = 20260819;
    p.showFigures = false;
    p.debugAdaptiveEqualizer = false;

    rng(p.randomSeed,'twister');
    [m,~] = run_ccsds_tm_evaluation(p);
    D(k,:) = {minConfidence(k),fadeThreshold(k),m.BER, ...
        100*m.LockRate,m.FER,m.EVM_post_pct,m.MER_dB,m.ResidualCFO_Hz};
end

disp(D);
