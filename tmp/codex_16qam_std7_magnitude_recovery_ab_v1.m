% Exact-noise-free A/B for 16QAM radial recovery in the std7 deep fade.
% This deliberately excludes FEC and phase-only/frozen-H cases already
% resolved by codex_16qam_std7_sync_component_ab_v1.m.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

cases = { ...
    'current_decision_hold', 'decision', false, 16, 18; ...
    'power_bridge_cap18',    'power',    true, 128, 18; ...
    'power_bridge_cap30',    'power',    true, 128, 30};

stamp = datestr(now,'yyyymmdd_HHMMSS');
rootOut = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_magnitude_recovery_ab_v1_' stamp]);
allT = table();

for k = 1:size(cases,1)
    caseName = cases{k,1};
    magnitudeMode = cases{k,2};
    trackDuringFade = cases{k,3};
    powerTauSymbols = cases{k,4};
    inverseCapDB = cases{k,5};

    o = struct();
    o.modTypes = {'16QAM'};
    o.hModelCases = { ...
        'std7_Corazza', ...
        'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};
    o.includeNoHBaseline = false;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = false;
    o.includeNormHScenario = true;
    o.includeNoEqualizerScenario = false;

    o.includeUncoded = true;
    o.includeConvolutional = false;
    o.includeRS = false;
    o.includeConcatenated = false;
    o.includeLDPC = false;
    o.includeTurbo = false;
    o.includeTPC = false;

    o.symbolRate = 10e6;
    o.sps = 8;
    o.berWarmUpFrames = 8;
    o.berFrames = 60;
    o.excludeBERWarmUpFrames = true;
    o.channelOutOfRangeMode = 'wrap';
    o.noisePlacement = 'afterChannel';
    o.noiseMode = 'off';
    o.snr = 100;

    o.equalizerMode = 'blind-cma-lms';
    o.enableQAMBlindPhaseSearch = true;
    o.enableQAMPowerGainTracker = true;
    o.enableQAMPostBPSAdaptiveEqualizer = false;
    o.enableASMFramePhaseCorrection = true;
    o.enableBlindReliabilityManager = true;
    o.blindReliabilityFadeEnterDB = -12;
    o.blindReliabilityFadeExitDB = -8;
    o.blindReliabilityMaxInverseGainDB = inverseCapDB;

    o.QAMPowerGainTracker = struct( ...
        'MagnitudeEstimationMode',magnitudeMode, ...
        'TrackPowerMagnitudeDuringFade',trackDuringFade, ...
        'FadePowerTauSymbols',powerTauSymbols, ...
        'UpdatePowerReference',false, ...
        'MaxInverseGainDB',inverseCapDB, ...
        'Regularization',0, ...
        'TrackMagnitude',true, ...
        'TrackPhase',false);

    o.RandomizerEnabled = false;
    o.randomSeed = 20260829;
    o.SeedMode = 'pairedChannelProfile';
    o.debugAdaptiveEqualizer = true;
    o.debugBlindReliabilityManager = true;
    o.debugQAMBPSFadeBER = true;
    o.showFigures = false;

    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 18;
    o.outputDir = fullfile(rootOut,caseName);
    o.Resume = false;
    o.RerunFailed = false;

    fprintf('\n============================================================\n');
    fprintf([' MAGNITUDE RECOVERY A/B: %s | mode=%s | ', ...
        'fadeBridge=%d | tau=%g | cap=%g dB\n'], ...
        caseName,magnitudeMode,trackDuringFade, ...
        powerTauSymbols,inverseCapDB);
    fprintf('============================================================\n');
    T = sweep_h_channel_short_frames(o);
    T.MagnitudeAB = repmat(string(caseName),height(T),1);
    T.MagnitudeMode = repmat(string(magnitudeMode),height(T),1);
    T.TrackPowerDuringFade = repmat( ...
        logical(trackDuringFade),height(T),1);
    T.PowerTauSymbols = repmat(double(powerTauSymbols),height(T),1);
    T.InverseCap_dB = repmat(double(inverseCapDB),height(T),1);
    allT = [allT; T]; %#ok<AGROW>
end

wanted = { ...
    'MagnitudeAB','MagnitudeMode','TrackPowerDuringFade', ...
    'PowerTauSymbols','InverseCap_dB','ActualWaveformDuration_s', ...
    'BER','PredecoderBER','BERInsideFade','BERRecoveryAfterFade', ...
    'BEROutsideFade','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMPowerGainAcceptanceRate_pct', ...
    'QAMPowerGainInverseMaxObserved_dB', ...
    'BlindReliabilityHoldFraction_pct','Status'};
wanted = wanted(ismember(wanted,allT.Properties.VariableNames));
D = allT(:,wanted);
disp(D);

writetable(D,fullfile(rootOut,'magnitude_recovery_ab_summary.csv'));
fprintf('\nA/B summary: %s\n', ...
    fullfile(rootOut,'magnitude_recovery_ab_summary.csv'));
