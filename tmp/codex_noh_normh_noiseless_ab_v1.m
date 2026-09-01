clearvars; clear classes; rehash;

rootDir = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(rootDir, 'src', 'python'));

o = struct();

% High-order constellations currently under diagnosis.
o.modTypes = {'16QAM','32QAM','16APSK','32APSK'};

% Existing seven receiver-ready channel traces.  This experiment applies
% only their normalized time-varying response; absolute path loss is not
% part of this diagnostic.
o.hModelCases = { ...
    'std2_TDL',       'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std3_CDL',       'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
    'std4_ITU_P681',  'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std5_Jakes',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
    'std6_CLoo',      'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
    'std7_Corazza',   'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
    'std8_Lutz',      'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};

% A0: ideal H=1 path without adaptive equalization.
% A1: ideal H=1 path through the same adaptive equalizer used by H cases.
% B : normalized H through the adaptive receiver.
o.includeNoHBaseline = true;
o.includeNoHEqualizedBaseline = true;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;

% Front-end diagnosis only: remove all FEC effects.
o.includeUncoded = true;
o.includeConvolutional = false;
o.includeRS = false;
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = false;

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 8;
o.berFrames = 120;
o.excludeBERWarmUpFrames = true;
o.channelOutOfRangeMode = 'wrap';

% Exact identity noise path.  snr is retained only as a legacy input field
% in the printed header and is not used when noiseMode='off'.
o.noiseMode = 'off';
o.snr = 100;
o.noisePlacement = 'afterChannel';
o.inputLevelDbm = -10;

% Use the current production receiver algorithms, without known-H MMSE.
o.equalizerMode = 'blind-cma-lms';
o.enableQAMBlindPhaseSearch = true;
o.enableQAMPowerGainTracker = true;
o.enableBlindReliabilityManager = false;

% CCSDS ordinary-TM APSK path: pilotless.
o.useTMAPSKPilots = false;
o.APSKReceiverMode = 'pilotless';

o.RandomizerEnabled = false;
o.randomSeed = 20260830;
o.SeedMode = 'pairedChannelProfile';

% Keep the test diagnostic: status still records the normal acceptance
% limits, but all cases continue even after a failure.
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.FailOnFailure = false;

o.debugHFrameStats = true;
o.debugHFrameStatsStart = 1;
o.debugHFrameStatsCount = 8;
o.debugASMPhase = true;
o.debugASMPhaseTimelineFrames = 128;
o.debugSynchronizationChain = true;
o.debugSyncSegmentCount = 12;
o.debugAdaptiveEqualizer = true;
o.debugQAMBPSFadeBER = true;
o.showFigures = false;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
o.outputDir = fullfile(rootDir, 'artifacts', 'ccsds', ...
    ['noh_normh_noiseless_ab_' stamp]);
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

vars = { ...
    'Scenario','ModType','BER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','ActualWaveformDuration_s', ...
    'HGain_dB','NoiseEquivalentSNR_dB','EqualizerMode','Status'};
D = T(:, vars(ismember(vars, T.Properties.VariableNames)));

fprintf('\n===== H=1 / normalized-H, exact-noise-off A/B =====\n');
disp(D);

outCsv = fullfile(o.outputDir, 'noiseless_ab_selected_columns.csv');
writetable(D, outCsv);
fprintf('Selected result CSV: %s\n', outCsv);

