clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

D = table('Size',[3,7], ...
    'VariableTypes',{'string','double','double','double','double','double','double'}, ...
    'VariableNames',{'Case','BER','LockPct','FER','EVM','MER','EqSNR'});

for k = 1:3
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
    p.noisePlacement = 'afterChannel';
    p.noiseMode = 'psd';
    p.noisePSDdBmHz = -115.3;
    p.noiseBandwidthHz = [];
    p.inputLevelDbm = -10;
    p.enableASMFramePhaseCorrection = true;
    p.asmFramePhaseCorrectionMaxError = 6;
    p.asmFramePhaseCorrectionMinGap = 4;
    p.asmFramePhaseCorrectionMinReliableFraction = 0.80;
    p.randomSeed = 20260819;
    p.showFigures = false;

    if k <= 2
        if k == 1
            label = "blind, effectively no noise";
            p.noisePSDdBmHz = -300;
        else
            label = "blind, PSD noise";
        end
        p.enableEqualizer = false;
        p.equalizerMode = 'off';
        p.enableAdaptiveFastEnvelopeTracker = true;
        p.enableAdaptiveFastPhaseTracker = false;
        p.enableQAMBlindPhaseSearch = true;
        p.QAMBlindPhaseSearch = struct( ...
            'WindowSymbols',33,'HopSymbols',4, ...
            'MetricPowerWindowSymbols',33, ...
            'MinConfidence',0.02,'FadeThresholdDB',-22, ...
            'PreserveInitialPhase',false, ...
            'DebugEventCount',16, ...
            'MaxFrequencyRadPerSymbol',0.10);
        p.enableQAMPowerGainTracker = true;
        p.QAMPowerGainTracker = struct( ...
            'MagnitudeEstimationMode','power', ...
            'UpdatePowerReference',false, ...
            'FadePowerTauSymbols',16, ...
            'EnableFadeHold',false, ...
            'Regularization',0, ...
            'MaxInverseGainDB',40);
    else
        label = "known-H MMSE, PSD noise";
        p.enableEqualizer = true;
        p.equalizerMode = 'mmse';
        p.normalizeEqualizerOutput = true;
        p.enableQAMBlindPhaseSearch = false;
    end

    p.debugAdaptiveEqualizer = (k <= 2);
    rng(p.randomSeed,'twister');
    [m,~] = run_ccsds_tm_evaluation(p);
    D(k,:) = {label,m.BER,100*m.LockRate,m.FER,m.EVM_post_pct, ...
        m.MER_dB,m.NoiseEquivalentSNR_dB};
end

disp(D);
