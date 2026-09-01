% Do not call "clear classes" from inside a script executed by run().
% MATLAB's run helper owns an onCleanup instance while this line executes,
% so clearing classes here only produces a harmless warning.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.modTypes = {'16QAM'};
o.hModelCases = { ...
    'std7_Corazza', ...
    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};

% NoH protects the known-good baseline; normalized std7 exercises the
% burst isolated by the BPS HOLD diagnostics.
o.includeNoHBaseline = true;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;

% Six-way comparison. The concatenated path is opt-in and does not change
% any existing coding default.
o.includeUncoded = true;
o.includeConvolutional = true;
o.convRates = {'1/2'};
o.includeRS = true;
o.rsInterleavingDepths = [1 8];
o.includeConcatenated = true;
o.concatenatedConvRates = {'1/2'};
o.concatenatedRSInterleavingDepths = [1 8];
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = false;

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 8;
o.berFrames = 100;
o.excludeBERWarmUpFrames = true;

% Receiver-algorithm isolation: exact identity noise path.  This A/B asks
% only whether coding/interleaving can contain the deterministic burst
% caused by normalized time-varying H.  Link-budget/PSD tests belong in a
% separate experiment.
o.noisePlacement = 'afterChannel';
o.noiseMode = 'off';
o.snr = 100; % printed legacy field only; noiseMode='off' is exact noiseless

o.equalizerMode = 'blind-cma-lms';
o.enableQAMBlindPhaseSearch = true;
o.enableQAMPowerGainTracker = true;
o.enableBlindReliabilityManager = false;
o.enableASMFramePhaseCorrection = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','ring-directed', ...
    'RingMagnitudeStep',1, ...
    'RingMagnitudeMaxStepDB',0.5, ...
    'TrackPowerMagnitudeDuringFade',true, ...
    'MaxInverseGainDB',30, ...
    'Regularization',0, ...
    'TrackMagnitude',true, ...
    'TrackPhase',false);

o.RandomizerEnabled = false;
o.ConvolutionalG1G2Mode = 'G1G2-inverted';
o.randomSeed = 20260829;
o.SeedMode = 'pairedChannelProfile';

o.debugCodedBoundary = true;
o.collectPredecoderStats = true;
o.debugASMPhase = true;
o.debugASMPhaseTimelineFrames = 110;
o.debugQAMBPSFadeBER = true;
o.showFigures = false;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

% Checkpoints are intentionally immutable.  Give every fresh A/B run its
% own directory so an earlier result can never make the script fail or be
% overwritten accidentally.
stamp = datestr(now,'yyyymmdd_HHMMSS');
o.outputDir = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_burst_fec_ab_v1_' stamp]);
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

wanted = { ...
    'Scenario','ModType','ChannelCoding','Rate', ...
    'ActualWaveformDuration_s','BER','PredecoderBER', ...
    'BERInsideFade','BERRecoveryAfterFade','BEROutsideFade', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB','Status'};
wanted = wanted(ismember(wanted, T.Properties.VariableNames));
D = T(:, wanted);
disp(D);

writetable(D, fullfile(o.outputDir, 'burst_fec_ab_summary.csv'));
