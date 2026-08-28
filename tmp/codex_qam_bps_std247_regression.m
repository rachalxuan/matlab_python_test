clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();

% BPS phase-branch / fade-HOLD regression scope.
o.modTypes = {'16QAM','32QAM'};
o.DataPathMode = 'single';
o.TMDataSource = 'random';
o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';

o.hModelCases = { ...
    'std2_TDL',      'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std4_ITU_P681', 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std7_Corazza',  'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};

% NoH is the regression guard; normalized H exercises the BPS path.
o.includeNoHBaseline = true;
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
% Do not force BPS in NoH. The production auto-routing enables it only for
% the normalized-H single-QAM cases below.
o.enableQAMPowerGainTracker = true;
o.QAMBlindPhaseSearch = struct('DebugEventCount',12);

o.randomSeed = 20260824;
o.SeedMode = 'pairedChannelProfile';

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.collectPredecoderStats = true;
o.debugCodedBoundary = false;
o.debugCarrierRecovery = true;
o.debugASMPhase = true;
o.debugAdaptiveEqualizer = false;
o.showFigures = false;

o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/qam_bps_std247_regression_v2';
% v2 已经跑过；重复执行时读取 checkpoint，不覆盖已有结果。
o.Resume = true;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

D = T(:, { ...
    'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','QAMBlindPhaseSearchApplied', ...
    'QAMBlindPhaseSearchFadeHoldBlocks', ...
    'QAMBlindPhaseSearchFadeEvents', ...
    'QAMBlindPhaseSearchFadeRecoveries', ...
    'QAMBlindPhaseSearchReacquisitions','Status'});
disp(D);

writetable(D, fullfile(o.outputDir, 'qam_bps_std247_result.csv'));
