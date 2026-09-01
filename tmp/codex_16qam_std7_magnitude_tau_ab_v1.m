% Tune only the causal decision-free QAM magnitude estimator after the
% known-H oracle proved the std7/noiseless segment is exactly recoverable.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

tauCases = [16 32 64 128];
stamp = datestr(now,'yyyymmdd_HHMMSS');
rootOut = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_magnitude_tau_ab_v1_' stamp]);
allT = table();

for k = 1:numel(tauCases)
    tauSymbols = tauCases(k);
    caseName = sprintf('power_tau_%03d',tauSymbols);

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
    o.blindReliabilityMaxInverseGainDB = 30;
    o.QAMPowerGainTracker = struct( ...
        'MagnitudeEstimationMode','power', ...
        'TrackPowerMagnitudeDuringFade',true, ...
        'FadePowerTauSymbols',tauSymbols, ...
        'UpdatePowerReference',false, ...
        'MaxInverseGainDB',30, ...
        'Regularization',0, ...
        'TrackMagnitude',true, ...
        'TrackPhase',false);

    o.RandomizerEnabled = false;
    o.randomSeed = 20260829;
    o.SeedMode = 'pairedChannelProfile';
    o.debugAdaptiveEqualizer = true;
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
    fprintf(' MAGNITUDE TAU A/B: tau=%d symbols | cap=30 dB\n', ...
        tauSymbols);
    fprintf('============================================================\n');
    T = sweep_h_channel_short_frames(o);
    T.PowerTauSymbols = repmat(double(tauSymbols),height(T),1);
    allT = [allT; T]; %#ok<AGROW>
end

wanted = { ...
    'PowerTauSymbols','ActualWaveformDuration_s','BER','PredecoderBER', ...
    'BERInsideFade','BERRecoveryAfterFade','BEROutsideFade', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMPowerGainAcceptanceRate_pct', ...
    'QAMPowerGainInverseMaxObserved_dB','Status'};
wanted = wanted(ismember(wanted,allT.Properties.VariableNames));
D = sortrows(allT(:,wanted),'PowerTauSymbols');
disp(D);
writetable(D,fullfile(rootOut,'magnitude_tau_ab_summary.csv'));
fprintf('\nA/B summary: %s\n', ...
    fullfile(rootOut,'magnitude_tau_ab_summary.csv'));
