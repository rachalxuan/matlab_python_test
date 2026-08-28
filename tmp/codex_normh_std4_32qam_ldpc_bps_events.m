clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32QAM'};
o.DataPathMode = 'single';
o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';
o.TMDataSource = 'random';
o.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
o.includeNoHBaseline = false;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;
o.includeUncoded = false;
o.includeRS = false;
o.includeConvolutional = false;
o.includeLDPC = true;
o.ldpcRates = {'1/2'};
o.includeTurbo = false;
o.includeTPC = false;
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
o.equalizerMode = 'blind-cma-lms';
o.enableQAMBlindPhaseSearch = true;
o.enableQAMPowerGainTracker = true;
o.QAMBlindPhaseSearch = struct('DebugEventCount',50);
o.randomSeed = 20260824;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.debugAdaptiveEqualizer = true;
o.debugCarrierRecovery = true;
o.debugASMPhase = true;
o.splitPathDebug = false;
o.showFigures = false;
o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/normh_std4_32qam_ldpc_bps_events_v9_metrics';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:,{'BER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied','Status'}));
