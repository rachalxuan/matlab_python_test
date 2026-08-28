clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32APSK'};
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
o.berWarmUpFrames = 2;
o.berFrames = 6;
o.excludeBERWarmUpFrames = true;
o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.inputLevelDbm = -10;
o.APSKReceiverMode = 'pilotless';
o.useTMAPSKPilots = false;
o.equalizerMode = 'off';
o.enablePilotlessAPSKComplexGainTracker = true;
o.randomSeed = 20260827;
o.SeedMode = 'pairedChannelProfile';
o.debugPilotlessAPSK = true;
o.showFigures = false;
o.outputDir = 'E:/web_code/react/fft_project/react-fft/tmp/apsk_auto_rde_smoke';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:,{'Scenario','BER','LockRate_pct','EVM_post_pct', ...
    'PilotlessAPSKRingNormalizerApplied', ...
    'PilotlessAPSKRingEstimatorMode', ...
    'PilotlessAPSKRingAcceptanceRate_pct', ...
    'PilotlessAPSKRingHoldFraction_pct','Status'}));

isNoH = T.Scenario == "NoH_baseline";
assert(all(~T.PilotlessAPSKRingNormalizerApplied(isNoH)), ...
    'NoH pilotless APSK baseline unexpectedly enabled RDE.');
assert(all(T.PilotlessAPSKRingNormalizerApplied(~isNoH)), ...
    'Normalized-H pilotless APSK path did not auto-enable RDE.');
assert(all(T.PilotlessAPSKRingEstimatorMode(~isNoH) == "rde"), ...
    'Normalized-H pilotless APSK did not use the requested RDE mode.');

