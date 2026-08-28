clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Long receiver regression for the three changes introduced on 2026-08-27:
%   1) QAM magnitude tracking is independent of blind phase search (BPS).
%   2) Every common CMA/DD equalizer path uses fade HOLD/recovery hysteresis.
%   3) Pilotless APSK uses RDE ring normalization before BPS/DD on H cases.
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

% NoH protects the historical baseline; normalized H isolates time-varying
% fading/synchronization from the still-unsettled absolute link budget.
o.includeNoHBaseline = true;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;

% Uncoded identifies receiver-front-end errors.  TPC explicitly exercises
% the former QAM bug, because QAM BPS is intentionally disabled for TPC.
o.includeUncoded = true;
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

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

% Common blind equalizer and common DD fade state machine.
o.equalizerMode = 'blind-cma-lms';
o.adaptiveEqualizerEnableFadeHold = true;
o.adaptiveEqualizerFadeHoldDB = -10;
o.adaptiveEqualizerFadeRecoverDB = -6;
o.adaptiveEqualizerFadeDetectorSymbols = 32;
o.adaptiveEqualizerFadeRecoverWindows = 2;
% This switch controls only the QAM acceptance-window rollback.  It no
% longer disables the power-fade HOLD state machine.
o.adaptiveEqualizerEnableQAMWindowHold = false;

% QAM phase and magnitude stages are deliberately independent.
o.enableQAMBlindPhaseSearch = true;
o.enableQAMBlindPhaseSearchForTPC = false;
o.enableQAMPowerGainTracker = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','power', ...
    'UpdatePowerReference',false, ...
    'EnableFadeHold',true, ...
    'FadeEnterDB',-10, ...
    'FadeExitDB',-6, ...
    'HoldEnterBadSymbols',8, ...
    'RecoverGoodSymbols',4, ...
    'NormalizeInputPower',true, ...
    'TrackMagnitude',true, ...
    'TrackPhase',false);

% CCSDS ordinary-TM APSK remains pilotless.  RDE is before the APSK BPS/DD
% stages.  The production adapter enables it only for H cases, so the NoH
% baseline is unchanged.  Add 'EnableRingNormalizer',false here for an
% explicit H-path rollback.
o.APSKReceiverMode = 'pilotless';
o.useTMAPSKPilots = false;
o.PilotlessAPSKCarrierRecovery = struct( ...
    'RingNormalizer',struct( ...
        'EstimatorMode','rde', ...
        'StepSize',0.04, ...
        'RingMarginMin',0.05, ...
        'EnableFadeHold',true, ...
        'FadePowerTauSymbols',32, ...
        'FadeEnterDB',-10, ...
        'FadeExitDB',-6, ...
        'RecoverGoodSymbols',1, ...
        'Regularization',1e-3, ...
        'MaxInverseGainDB',18));

o.randomSeed = 20260827;
o.SeedMode = 'pairedChannelProfile';
o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.debugAdaptiveEqualizer = true;
o.debugPilotlessAPSK = true;
o.collectPredecoderStats = true;
o.debugCodedBoundary = false;
o.showFigures = false;

% Fixed directory permits true resume.  If any test parameter is changed,
% change only this final v1 suffix before running the modified matrix.
o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/qam_apsk_fade_rde_7normh_v1';
o.Resume = true;
o.RerunFailed = false;
o.MaxNewCases = Inf;

T = sweep_h_channel_short_frames(o);

columns = { ...
    'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER', ...
    'EVM_post_pct','EVMRadial_pct','EVMTangential_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied','QAMPowerGainApplied', ...
    'DDHoldWindows','DDFadeHoldWindows', ...
    'DDFadeEnterEvents','DDFadeRecoverEvents', ...
    'PilotlessAPSKRingNormalizerApplied', ...
    'PilotlessAPSKRingEstimatorMode', ...
    'PilotlessAPSKRingAcceptanceRate_pct', ...
    'PilotlessAPSKRingHoldFraction_pct', ...
    'PilotlessAPSKRingFadeFraction_pct','Status'};
columns = columns(ismember(columns,T.Properties.VariableNames));
D = T(:,columns);
disp(D);

F = D(string(D.Status) ~= "PASS",:);
writetable(F,fullfile(o.outputDir,'failed_cases_with_fade_rde_debug.csv'));
