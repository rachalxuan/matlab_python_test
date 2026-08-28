clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32APSK'};
o.hModelCases = { ...
    'std5_Jakes', ...
    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'};

o.includeNoHBaseline = false;
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
o.RandomizerEnabled = true;
o.RandomizerFECPosition = 'beforeEncoding';
o.APSKReceiverMode = 'pilotless';
o.useTMAPSKPilots = false;

o.randomSeed = 20260824;
o.SeedMode = 'pairedChannelProfile';
o.debugCodedBoundary = true;
o.debugTPC = true;
o.collectPredecoderStats = true;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.showFigures = false;
o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/tpc_align_std5_short_v1';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
disp(T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','Status','ErrorMessage'}));
