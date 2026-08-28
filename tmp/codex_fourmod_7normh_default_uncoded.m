clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'16QAM','32QAM','16APSK','32APSK'};
o.hModelCases = { ...
    'std2_TDL',      'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std3_CDL',      'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
    'std4_ITU_P681', 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std5_Jakes',    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
    'std6_CLoo',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
    'std7_Corazza',  'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
    'std8_Lutz',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};
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
o.inputLevelDbm = -10;
o.equalizerMode = 'blind-cma-lms';
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.debugAdaptiveEqualizer = false;
o.debugPilotlessAPSK = false;
o.debugCodedBoundary = false;
o.collectPredecoderStats = false;
o.debugHFrameStats = false;
o.showFigures = false;
o.outputDir = '';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:, {'Scenario','ModType','BER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied', ...
    'PilotlessAPSKBlindPhaseSearchApplied','Status'}));
assert(height(T) == 32,'Expected exactly 32 cases.');
assert(all(T.Status == "PASS"),'At least one normalized-H case failed.');
