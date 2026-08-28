clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32QAM'};
o.DataPathMode = 'dualIQ';
o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';
o.TMDataSource = 'random';

o.includeNoHBaseline = true;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = false;
o.includeNoEqualizerScenario = false;

o.includeUncoded = true;
o.includeRS = true;
o.includeConvolutional = true;
o.convRates = {'1/2'};
o.includeLDPC = true;
o.ldpcRates = {'1/2'};
o.includeTurbo = true;
o.turboRates = {'1/2'};
o.includeTPC = false;
o.ConvolutionalG1G2Mode = 'G1G2-inverted';

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 8;
o.berFrames = 30;
o.excludeBERWarmUpFrames = true;

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

o.equalizerMode = 'blind-cma-lms';
o.enableQAMBlindPhaseSearch = false;
o.enableQAMPowerGainTracker = true;

o.randomSeed = 20260824;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.collectPredecoderStats = true;
o.debugCodedBoundary = true;
o.debugSynchronizationChain = true;
o.debugASMPhase = true;
o.debugASMPhaseTimelineFrames = 64;
o.splitPathDebug = true;
o.showFigures = false;

o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/noh_split_32qam_bps_off_diag';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

disp(T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied', ...
    'Status','ErrorMessage'}));
