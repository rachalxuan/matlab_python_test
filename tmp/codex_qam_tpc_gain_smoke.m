clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'16QAM'};
o.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
o.includeNoHBaseline = true;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;
o.includeUncoded = false;
o.includeRS = false;
o.includeConvolutional = false;
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = true;
o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 2;
o.berFrames = 5;
o.excludeBERWarmUpFrames = true;
o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.inputLevelDbm = -10;
o.equalizerMode = 'blind-cma-lms';
o.enableQAMBlindPhaseSearch = true;
o.enableQAMBlindPhaseSearchForTPC = false;
o.enableQAMPowerGainTracker = true;
o.adaptiveEqualizerEnableFadeHold = true;
o.adaptiveEqualizerEnableQAMWindowHold = false;
o.randomSeed = 20260827;
o.SeedMode = 'pairedChannelProfile';
o.debugAdaptiveEqualizer = true;
o.showFigures = false;
o.outputDir = 'E:/web_code/react/fft_project/react-fft/tmp/qam_tpc_gain_smoke_v2';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:,{'Scenario','ModType','ChannelCoding','BER', ...
    'QAMBlindPhaseSearchApplied','QAMPowerGainApplied', ...
    'DDHoldWindows','DDFadeHoldWindows', ...
    'DDFadeEnterEvents','DDFadeRecoverEvents','Status'}));

assert(all(~T.QAMBlindPhaseSearchApplied), ...
    'TPC diagnostic should keep QAM BPS disabled.');
assert(all(T.QAMPowerGainApplied), ...
    'QAM power gain tracking is still coupled to BPS.');
