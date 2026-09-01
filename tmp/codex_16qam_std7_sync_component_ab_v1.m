% Receiver-only diagnosis for the normalized std7 deep fade.
% The run is exactly noise-free and uncoded.  It compares the current
% independent HOLD policy with the shared receiver-wide HOLD policy, then
% separates magnitude and phase dynamics of the same H realization.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

cases = { ...
    'normal_hold_off',   'normal',         false; ...
    'normal_hold_on',    'normal',         true;  ...
    'magnitude_only',    'magnitude-only', true;  ...
    'phase_only',        'phase-only',     true;  ...
    'frozen_h',          'frozen',         true};

stamp = datestr(now,'yyyymmdd_HHMMSS');
rootOut = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_sync_component_ab_v1_' stamp]);
allT = table();

for k = 1:size(cases,1)
    caseName = cases{k,1};
    hMode = cases{k,2};
    sharedHold = cases{k,3};

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
    o.snr = 100; % legacy print field; ignored in exact OFF mode

    o.equalizerMode = 'blind-cma-lms';
    o.enableQAMBlindPhaseSearch = true;
    o.enableQAMPowerGainTracker = true;
    o.enableQAMPostBPSAdaptiveEqualizer = false;
    o.enableASMFramePhaseCorrection = true;
    o.debugHMatrixResponseMode = hMode;

    % The shared detector observes only pre-normalization receive power.
    % It has no H, pilot, ASM, transmitted-bit, or FEC knowledge.
    o.enableBlindReliabilityManager = sharedHold;
    o.blindReliabilityWindowSymbols = 32;
    o.blindReliabilityAcquireSymbols = 256;
    o.blindReliabilityReferenceTauSymbols = 4096;
    o.blindReliabilityFadeEnterDB = -12;
    o.blindReliabilityFadeExitDB = -8;
    o.blindReliabilityFadeEnterWindows = 2;
    o.blindReliabilityRecoverWindows = 4;
    o.blindReliabilityMaxInverseGainDB = 18;

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
    fprintf(' SYNC COMPONENT A/B: %s | H=%s | sharedHOLD=%d\n', ...
        caseName,hMode,sharedHold);
    fprintf('============================================================\n');
    T = sweep_h_channel_short_frames(o);
    T.SyncAB = repmat(string(caseName),height(T),1);
    T.HComponentMode = repmat(string(hMode),height(T),1);
    T.SharedHoldEnabled = repmat(logical(sharedHold),height(T),1);
    allT = [allT; T]; %#ok<AGROW>
end

wanted = { ...
    'SyncAB','HComponentMode','SharedHoldEnabled', ...
    'ActualWaveformDuration_s','BER','PredecoderBER', ...
    'BERInsideFade','BERRecoveryAfterFade','BEROutsideFade', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchFadeHoldBlocks', ...
    'QAMBlindPhaseSearchFadeEvents', ...
    'QAMBlindPhaseSearchFadeRecoveries', ...
    'QAMBlindPhaseSearchReacquisitions', ...
    'BlindReliabilityHoldFraction_pct', ...
    'BlindReliabilityHoldEvents','BlindReliabilityRecoverEvents','Status'};
wanted = wanted(ismember(wanted,allT.Properties.VariableNames));
D = allT(:,wanted);
disp(D);

writetable(D,fullfile(rootOut,'sync_component_ab_summary.csv'));
fprintf('\nA/B summary: %s\n', ...
    fullfile(rootOut,'sync_component_ab_summary.csv'));
