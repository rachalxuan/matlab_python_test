clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'16QAM','32QAM'};
o.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
o.includeNoHBaseline = true;
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
o.berWarmUpFrames = 8;
o.berFrames = 50;
o.excludeBERWarmUpFrames = true;
o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;
% Isolate the new decision-free QAM front-end.  The normalized std4 file
% has one effective tap, so this A/B deliberately bypasses the legacy
% CMA/MMA+DD stage after BPS.
o.equalizerMode = 'off';
% May remain enabled globally: the receiver automatically bypasses the
% per-sample IIR envelope path when QAM BPS is selected.
o.enableAdaptiveFastEnvelopeTracker = true;
o.enableAdaptiveFastPhaseTracker = true;
o.enableQAMBlindPhaseSearch = true;
o.QAMBlindPhaseSearch = struct( ...
    'FadeThresholdDB',-22, ...
    'PreserveInitialPhase',false, ...
    'MaxFrequencyRadPerSymbol',0.05);
o.enableQAMPowerGainTracker = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','power', ...
    'UpdatePowerReference',false, ...
    'EnableFadeHold',false, ...
    'Regularization',0, ...
    'MaxInverseGainDB',40);
o.enableASMFramePhaseCorrection = true;
o.asmFramePhaseCorrectionMaxError = 6;
o.asmFramePhaseCorrectionMinGap = 4;
o.asmFramePhaseCorrectionMinReliableFraction = 0.80;
o.debugASMPhaseTimelineFrames = 80;
o.adaptiveEqualizerTaps = 11;
o.adaptiveEqualizerCMAWarmupSymbols = 2000;
o.adaptiveEqualizerCMAStep = 0.01;
o.adaptiveEqualizerDDStep = 1e-3;
o.adaptiveEqualizerDDPasses = 1;
o.adaptiveEqualizerDDWindowSymbols = 256;
o.adaptiveEqualizerDDMinWindowAcceptance = 0.75;
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.debugAdaptiveEqualizer = true;
o.debugCodedBoundary = false;
o.collectPredecoderStats = false;
o.showFigures = false;
o.outputDir = 'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/codex_qam_bps_noh_std4_nocma_v5';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:, {'Scenario','ModType','BER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','CMAMSE','DDMSE', ...
    'DDAcceptanceRate_pct','Status'}));
