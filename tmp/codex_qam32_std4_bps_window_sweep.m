clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

windows = [9 17 33];
hops = [1 2 4];
D = table('Size',[numel(windows),7], ...
    'VariableTypes',{'double','double','double','double','double','double','double'}, ...
    'VariableNames',{'Window','Hop','BER','LockPct','FER','EVM','MER'});

for k = 1:numel(windows)
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
        'WindowSymbols',windows(k), ...
        'HopSymbols',hops(k), ...
        'MetricPowerWindowSymbols',windows(k), ...
        'MinConfidence',0.02, ...
        'FadeThresholdDB',-22, ...
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
    D(k,:) = {windows(k),hops(k),m.BER,100*m.LockRate,m.FER, ...
        m.EVM_post_pct,m.MER_dB};
end

disp(D);
