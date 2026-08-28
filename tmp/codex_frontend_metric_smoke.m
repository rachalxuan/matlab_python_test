clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'16QAM','16APSK'};
o.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
o.includeNoHBaseline = false;
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
o.berWarmUpFrames = 4;
o.berFrames = 12;
o.excludeBERWarmUpFrames = true;
o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.inputLevelDbm = -10;
o.equalizerMode = 'blind-cma-lms';
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';
o.outputDir = '';
o.showFigures = false;

T = sweep_h_channel_short_frames(o);
disp(T(:, {'ModType','QAMBlindPhaseSearchApplied', ...
    'QAMPowerGainApplied','QAMPowerGainRegularization', ...
    'PilotlessAPSKApplied','PilotlessAPSKBlindPhaseSearchApplied', ...
    'PilotlessAPSKGainRegularization','Status'}));

assert(T.QAMBlindPhaseSearchApplied(T.ModType == "16QAM"), ...
    'QAM BPS metric was not propagated.');
assert(T.QAMPowerGainApplied(T.ModType == "16QAM"), ...
    'QAM power-gain metric was not propagated.');
assert(T.PilotlessAPSKApplied(T.ModType == "16APSK"), ...
    'Pilotless APSK metric was not propagated.');
assert(T.PilotlessAPSKBlindPhaseSearchApplied(T.ModType == "16APSK"), ...
    'APSK BPS metric was not propagated.');
