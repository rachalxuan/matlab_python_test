clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Production-default smoke test: the receiver algorithm options below are
% deliberately not overridden.  This verifies the sweep/main entry points,
% rather than a hand-tuned laboratory configuration.
o = struct();
o.modTypes = {'16QAM','32QAM','16APSK','32APSK'};
o.hModelCases = { ...
    'std4_ITU_P681', ...
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
o.channelInterpolationMethod = 'linear';
o.channelOutOfRangeMode = 'wrap';
o.interpolateChannelDelays = false;

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

% Keep the public historical mode name.  QAM-BPS owns the QAM front end and
% automatically bypasses its incompatible legacy CMA/envelope stages;
% pilotless APSK owns its own phase/gain front end.
o.equalizerMode = 'blind-cma-lms';
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.debugAdaptiveEqualizer = true;
o.debugPilotlessAPSK = true;
o.debugASMPhase = false;
o.showFigures = false;
o.outputDir = '';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

disp(T(:, { ...
    'Scenario','ModType','BER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied', ...
    'QAMBlindPhaseSearchReliableRate_pct', ...
    'QAMPowerGainApplied','QAMPowerGainRegularization', ...
    'QAMPowerGainInverseMaxObserved_dB', ...
    'PilotlessAPSKApplied', ...
    'PilotlessAPSKBlindPhaseSearchApplied', ...
    'PilotlessAPSKBlindPhaseSearchReliableRate_pct', ...
    'PilotlessAPSKGainRegularization', ...
    'PilotlessAPSKGainInverseMaxObserved_dB','Status'}));
