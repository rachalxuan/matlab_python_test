clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Long regression owned by the main TM generator/demapper/decoder.
% Receiver-specific fields are intentionally not overridden: normalized-H
% QAM uses automatic BPS + power gain; APSK uses the pilotless front end.
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

% 9 coding cases/modulation/scenario: uncoded, RS, five convolutional
% puncturing rates, LDPC 1/2 and Turbo 1/2. Total = 4*8*9 = 288 cases.
o.includeUncoded = true;
o.includeRS = true;
o.includeConvolutional = true;
o.convRates = {'1/2','2/3','3/4','5/6','7/8'};
o.includeLDPC = true;
o.ldpcRates = {'1/2'};
o.includeTurbo = true;
o.turboRates = {'1/2'};
o.includeTPC = false;

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 10;
o.berFrames = 80;
o.excludeBERWarmUpFrames = true;
o.channelInterpolationMethod = 'linear';
o.channelOutOfRangeMode = 'wrap';
o.interpolateChannelDelays = false;

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

o.equalizerMode = 'blind-cma-lms';
o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';
o.randomSeed = 20260819;
o.SeedMode = 'pairedChannelProfile';

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.minCountedFrames = 1;

o.debugAdaptiveEqualizer = false;
o.debugPilotlessAPSK = false;
o.debugCodedBoundary = true;
o.collectPredecoderStats = true;
o.predecoderMaxOffsetBits = 64;
o.showFigures = false;

% Empty outputDir creates a fresh timestamped directory automatically; no
% RunId needs to be edited when the configuration changes.
o.outputDir = '';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

fprintf('\n===== Four-modulation normalized-H coded regression =====\n');
fprintf('Total=%d PASS=%d FAIL_METRIC=%d ERROR=%d\n',height(T), ...
    nnz(T.Status == "PASS"),nnz(T.Status == "FAIL_METRIC"), ...
    nnz(T.Status == "ERROR"));

bad = T.Status ~= "PASS";
disp(T(bad, { ...
    'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderSteadyBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchReliableRate_pct', ...
    'QAMPowerGainInverseMaxObserved_dB', ...
    'PilotlessAPSKBlindPhaseSearchReliableRate_pct', ...
    'PilotlessAPSKGainInverseMaxObserved_dB','Status'}));
