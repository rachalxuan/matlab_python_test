clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

modes = {'normal','magnitude-only','phase-only','frozen'};
D = table('Size',[numel(modes),7], ...
    'VariableTypes',{'string','double','double','double','double','double','double'}, ...
    'VariableNames',{'Mode','BER','LockPct','FER','EVM','MER','ResidualCFO'});

for k = 1:numel(modes)
    p = struct();
    p.modType = '32QAM';
    p.channelCoding = 'none';
    p.symbolRate = 10e6;
    p.sps = 8;
    p.berWarmUpFrames = 8;
    p.berFrames = 24;
    p.excludeBERWarmUpFrames = true;
    p.enableHChannel = true;
    p.HMode = 'h_matrix_file';
    p.channelFilePath = ...
        'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat';
    p.channelInterpolationMethod = 'linear';
    p.channelOutOfRangeMode = 'wrap';
    p.interpolateChannelDelays = false;
    p.normalizeHChannel = true;
    p.debugHMatrixResponseMode = modes{k};
    p.enableEqualizer = false;
    p.equalizerMode = 'off';
    p.normalizeEqualizerOutput = true;
    p.noisePlacement = 'afterChannel';
    p.noiseMode = 'psd';
    p.noisePSDdBmHz = -115.3;
    p.noiseBandwidthHz = [];
    p.inputLevelDbm = -10;
    % A per-sample IIR envelope tracker follows the QAM data envelope and
    % creates nonlinear constellation compression.  This diagnostic keeps
    % amplitude tracking after timing, where it uses windowed mean power.
    p.enableAdaptiveFastEnvelopeTracker = false;
    p.enableAdaptiveFastPhaseTracker = false;
    p.enableQAMBlindPhaseSearch = true;
    p.QAMBlindPhaseSearch = struct( ...
        'WindowSymbols',33, ...
        'HopSymbols',4, ...
        'MetricPowerWindowSymbols',33, ...
        'FadeThresholdDB',-22, ...
        'PreserveInitialPhase',false);
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
    p.debugAdaptiveEqualizer = true;

    rng(p.randomSeed,'twister');
    [m,~] = run_ccsds_tm_evaluation(p);
    D(k,:) = {string(modes{k}),m.BER,100*m.LockRate,m.FER, ...
        m.EVM_post_pct,m.MER_dB,m.ResidualCFO_Hz};
end

disp(D);
