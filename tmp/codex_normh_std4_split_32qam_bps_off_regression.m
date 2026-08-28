clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'32QAM'};
o.DataPathMode = 'dualIQ';
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
o.channelOutOfRangeMode = 'wrap';

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

o.equalizerMode = 'blind-cma-lms';
% Diagnostic A/B: keep every setting identical and disable only QAM BPS.
o.enableQAMBlindPhaseSearch = false;
o.enableQAMPowerGainTracker = true;

o.randomSeed = 20260824;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.collectPredecoderStats = true;
o.debugCodedBoundary = false;
o.debugSynchronizationChain = false;
o.debugASMPhase = true;
o.splitPathDebug = true;
o.showFigures = false;

o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/normh_std4_split_32qam_bps_off_regression';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

D = T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied', ...
    'QAMBlindPhaseSearchReliableRate_pct', ...
    'QAMBlindPhaseSearchFinalCorrection_deg', ...
    'Status','ErrorMessage'});
disp(D);
