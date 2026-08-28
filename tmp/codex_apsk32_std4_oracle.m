clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

p = struct();
p.modType = '32APSK';
p.channelCoding = 'none';
p.symbolRate = 10e6;
p.sps = 8;
p.berWarmUpFrames = 12;
p.berFrames = 50;
p.excludeBERWarmUpFrames = true;
p.enableHChannel = true;
p.HMode = 'h_matrix_file';
p.channelFilePath = 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat';
p.channelInterpolationMethod = 'linear';
p.channelOutOfRangeMode = 'wrap';
p.interpolateChannelDelays = false;
p.normalizeHChannel = true;
p.enableEqualizer = true;
p.equalizerMode = 'mmse';
p.normalizeEqualizerOutput = true;
p.noisePlacement = 'afterChannel';
p.noiseMode = 'psd';
p.noisePSDdBmHz = -115.3;
p.noiseBandwidthHz = [];
p.inputLevelDbm = -10;
p.APSKReceiverMode = 'pilotless';
p.HasTMAPSKPilots = false;
p.enablePilotlessAPSKComplexGainTracker = true;
p.PilotlessAPSKCarrierRecovery = struct( ...
    'EnableMthPowerPhaseTracker',false, ...
    'EnableBlindPhaseSearch',false, ...
    'EnableDDPhaseTracker',true, ...
    'RecoverGoodSymbols',1);
p.enableASMFramePhaseCorrection = true;
p.asmFramePhaseCorrectionMaxError = 6;
p.asmFramePhaseCorrectionMinGap = 4;
p.asmFramePhaseCorrectionMinReliableFraction = 0.80;
p.debugASMPhaseTimelineFrames = 80;
p.randomSeed = 20260819;
p.showFigures = false;
p.debugPilotlessAPSK = true;
p.debugEqualizerStats = true;
p.debugASMPhase = false;

[m,~] = run_ccsds_tm_evaluation(p);
fprintf('\nORACLE MMSE: BER=%.12g Lock=%.3f%% FER=%.12g EVM=%.3f%% MER=%.3f dB\n', ...
    m.BER,100*m.LockRate,m.FER,m.EVM_post_pct,m.MER_dB);
