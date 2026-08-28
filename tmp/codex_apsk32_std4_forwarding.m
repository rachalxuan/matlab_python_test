clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32APSK'};
o.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
o.includeNoHBaseline = false;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;
o.includeUncoded = true;
o.includeRS = false;
o.includeConvolutional = true;
o.convRates = {'1/2'};
o.includeLDPC = false;
o.includeTurbo = true;
o.turboRates = {'1/2'};
o.includeTPC = false;
o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 12;
o.berFrames = 80;
o.excludeBERWarmUpFrames = true;
o.channelInterpolationMethod = 'linear';
o.channelOutOfRangeMode = 'wrap';
o.interpolateChannelDelays = false;
o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;
o.APSKReceiverMode = 'pilotless';
o.useTMAPSKPilots = false;
o.equalizerMode = 'off';
o.enablePilotlessAPSKComplexGainTracker = true;
o.PilotlessAPSKCarrierRecovery = struct( ...
    'AcquisitionSymbols',16384, ...
    'AcquisitionBlockSymbols',32, ...
    'FourthPowerFFTLength',131072, ...
    'EnablePreDDGainTracker',false, ...
    'RecoverGoodSymbols',1, ...
    'MthPowerPhaseTracker',struct( ...
        'WindowSymbols',32, ...
        'MinConfidence',0.10, ...
        'LoopBandwidth',0.02, ...
        'DampingFactor',1/sqrt(2), ...
        'MaxRaisedFrequencyRadPerSymbol',0.25, ...
        'InitialFrequencySymbols',512));
o.enableASMFramePhaseCorrection = true;
o.asmFramePhaseCorrectionMaxError = 6;
o.asmFramePhaseCorrectionMinGap = 4;
o.asmFramePhaseCorrectionMinReliableFraction = 0.80;
o.debugASMPhaseTimelineFrames = 128;
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.debugPilotlessAPSK = true;
o.debugCodedBoundary = true;
o.collectPredecoderStats = true;
o.debugPerFrameBERSummary = true;
o.debugASMPhase = false;
o.debugHFrameStats = false;
o.debugAdaptiveEqualizer = false;
o.showFigures = false;
o.outputDir = 'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/codex_apsk32_std4_forwarding';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','PredecoderSteadyBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','ASMFramePhaseCorrectionApplied', ...
    'ASMFramePhaseCorrectionFrames','ASMFramePhaseCorrectionReliableFrames', ...
    'ASMFramePhaseCycleSlipsBefore','ASMFramePhaseCycleSlipsAfter','Status'}));
