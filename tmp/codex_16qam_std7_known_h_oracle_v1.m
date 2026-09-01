% Known-H upper bound for the exact same 16QAM/std7/noiseless segment used
% by codex_16qam_std7_magnitude_recovery_ab_v1.m.  This is diagnostic only:
% the receiver is given the simulated time-varying H coefficient.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

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

% Exact identity noise path.  With zero manual regularization, MMSE reduces
% to the known-H zero-noise inverse wherever H is nonzero.
o.noisePlacement = 'afterChannel';
o.noiseMode = 'off';
o.snr = 100;
o.equalizerMode = 'mmse';
o.equalizerReg = 0;
o.equalizerDenomFloor = eps;
o.normalizeEqualizerOutput = true;
o.debugHMatrixEqualizerStats = true;

% Keep the same downstream QAM carrier and radial stages as the blind A/B.
% After successful known-H inversion their corrections should stay near
% unity; they are not given H themselves.
o.enableQAMBlindPhaseSearch = true;
o.enableQAMPowerGainTracker = true;
o.enableQAMPostBPSAdaptiveEqualizer = false;
o.enableASMFramePhaseCorrection = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','power', ...
    'TrackPowerMagnitudeDuringFade',true, ...
    'FadePowerTauSymbols',128, ...
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

stamp = datestr(now,'yyyymmdd_HHMMSS');
o.outputDir = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_known_h_oracle_v1_' stamp]);
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);
wanted = { ...
    'Scenario','ActualWaveformDuration_s','BER','PredecoderBER', ...
    'BERInsideFade','BERRecoveryAfterFade','BEROutsideFade', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMPowerGainInverseMaxObserved_dB','Status'};
wanted = wanted(ismember(wanted,T.Properties.VariableNames));
D = T(:,wanted);
disp(D);
writetable(D,fullfile(o.outputDir,'known_h_oracle_summary.csv'));
fprintf('\nKnown-H summary: %s\n', ...
    fullfile(o.outputDir,'known_h_oracle_summary.csv'));
