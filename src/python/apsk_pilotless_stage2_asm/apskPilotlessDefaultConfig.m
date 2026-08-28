function opt = apskPilotlessDefaultConfig()
%APSKPILOTLESSDEFAULTCONFIG Default options for the isolated pilotless APSK receiver.
%
%   opt = apskPilotlessDefaultConfig()
%
% The impairment field names intentionally follow run_ccsds_tm_evaluation.m
% wherever practical so that a validated standalone configuration can later
% be moved back into the main evaluator with minimal translation:
%
%   opt.cfo              frequency offset in Hz
%   opt.phaseOffset      fixed phase offset in degrees
%   opt.delay            fractional delay in INPUT samples
%   opt.noiseMode        'off' | 'psd' | 'snr'
%   opt.noisePSDdBmHz    receiver noise PSD in dBm/Hz
%   opt.noiseBandwidthHz receiver equivalent-noise bandwidth in Hz ([]=auto)
%   opt.inputLevelDbm    digital waveform reference power in dBm for PSD mode
%   opt.snr              measured SNR in dB when noiseMode='snr'
%
% IMPORTANT IMPAIRMENT NOTES
%   1) CFO + phase use comm.PhaseFrequencyOffset, as in the main evaluator.
%      MATLAB's PhaseOffset property is in DEGREES.  This standalone receiver
%      therefore passes opt.phaseOffset directly in degrees.
%
%   2) Delay uses dsp.VariableFractionalDelay with Farrow interpolation, as
%      in the main evaluator.  For intended sub-sample delays (e.g. 0.2), the
%      small-delay action is explicitly set to 'Use off-centered kernel' so
%      that the requested fractional delay is not silently clipped upward by
%      the centered Farrow kernel.
%
%   3) PSD noise uses the SAME physical-reference calculation as the main
%      evaluator: dBm/Hz -> integrated noise power -> digital variance.  The
%      MathWorks awgn() function is used only for noiseMode='snr', because
%      awgn() does not itself define the physical dBm/Hz reference plane.
%
% Defaults preserve the already-validated Stage-3 baseline: no H, no noise,
% no CFO, no phase offset, no delay, no custom APSK pilots.

%% Waveform / TM generator
opt.modType = '32APSK';                 % '16APSK' or '32APSK'
opt.symbolRate = 10e6;
opt.sps = 8;
opt.RolloffFactor = 0.35;
opt.FilterSpanInSymbols = 10;
opt.NumFrames = 60;
opt.NumBytesInTransferFrame = 1115;

opt.RandomizerEnabled = false;
opt.RandomizerFECPosition = 'afterEncoding';
opt.DataPathMode = 'single';
opt.hasASM = true;
opt.ASMHex = '1ACFFC1D';
opt.channelCoding = 'none';             % standalone Stage 1-4 scope
opt.PCMFormat = 'NRZ-L';
opt.HasTMAPSKPilots = false;             % must remain false for pilotless path

%% Controlled impairments -- names deliberately match the main evaluator
opt.cfo = 0;                             % Hz
opt.phaseOffset = 0;                     % degrees
opt.delay = 0;                           % input samples; may be fractional

% Fractional-delay implementation.  The object is still the same official
% dsp.VariableFractionalDelay/Farrow path used by the main evaluator.
opt.delayInterpolationMethod = 'Farrow';
opt.delayMaximumSamples = 100;
opt.delayFarrowSmallDelayAction = 'Use off-centered kernel';

%% Receiver noise
% Keep OFF by default so the Stage-3 noiseless golden regression remains
% reproducible.  Set noiseMode='psd' to exercise the main-evaluator PSD model.
opt.noiseMode = 'off';                   % 'off' | 'psd' | 'snr'
opt.noisePSDdBmHz = -115.3;
opt.noiseBandwidthHz = [];               % [] => min(Fs,(1+rolloff)*Rs)
opt.inputLevelDbm = -10;                 % physical reference level for PSD mode
opt.snr = Inf;                           % used only when noiseMode='snr'
opt.noisePlacement = 'afterChannel';     % reserved for migration; standalone has H off

%% H-channel placeholder
% Intentionally not enabled yet.  Keep the fields here so future migration
% does not require changing the public configuration interface.
opt.enableH = false;
opt.HModel = 'std4_ITU_P681';
opt.HFile = '';
opt.normalizeHChannel = true;

%% Matched filter / timing
opt.timingNormalizedLoopBandwidth = 0.005;
opt.timingChunkSizeSamples = 50000;

%% Pilotless APSK carrier recovery
opt.CarrierRecovery = struct();
opt.CarrierRecovery.NormalizeInputPower = true;
opt.CarrierRecovery.AcquisitionSymbols = 4096;
opt.CarrierRecovery.AcquisitionBlockSymbols = 16;
opt.CarrierRecovery.AcquisitionPhaseGridSize = 181;
opt.CarrierRecovery.AcquisitionTrimFraction = 0.10;
opt.CarrierRecovery.MaxAcquisitionCFOHz = 200e3;
opt.CarrierRecovery.RequireAcquisitionQualification = true;
% Coarse CFO is estimated before the constellation-likelihood NDA fit.  The
% old block-only fit has data-dependent kHz-level biases which can drive the
% 32APSK DD loop into a false lock (typically BER ~= 0.2).
opt.CarrierRecovery.EnableFourthPowerFFTCoarseCFO = true;
% Experimental wide-range 32APSK acquisition. OFF preserves the all-ring
% x^48 receiver. ON selects the inner+middle rings and uses x^12, expanding
% the unambiguous interval from roughly +/-Rs/96 to +/-Rs/24.
opt.CarrierRecovery.EnableWideRangeRingCoarseCFO = false;
opt.CarrierRecovery.CoarseUseInnerMiddleRings = true;
opt.CarrierRecovery.CoarsePowerOrder = [];
opt.CarrierRecovery.CoarseRangeToleranceHz = NaN;
opt.CarrierRecovery.AcquisitionRangeToleranceHz = NaN;
opt.CarrierRecovery.FourthPowerFFTLength = 65536;
opt.CarrierRecovery.FourthPowerMinConfidenceDB = 6;
opt.CarrierRecovery.FourthPowerUseUnitMagnitude = true;
opt.CarrierRecovery.RequireFourthPowerQualification = true;
opt.CarrierRecovery.UseGlobalNDAPhase = true;
% The block-fit residual is retained in diagnostics, but its data-dependent
% bias is not added back by default.  The gated DD PLL easily removes the
% remaining tens of hertz after the fourth-power FFT estimate.
opt.CarrierRecovery.ApplyNDAResidualCFO = false;
% The main H-channel adapter enables this automatically.  It remains off in
% the standalone NoH/CFO regression so that the already validated golden
% chain is unchanged.
opt.CarrierRecovery.EnableMthPowerPhaseTracker = false;
opt.CarrierRecovery.MthPowerPhaseTracker = struct( ...
    'WindowSymbols',32, ...
    'AmplitudeFloorRatio',0.05, ...
    'MinConfidence',0.10, ...
    'LoopBandwidth',0.02, ...
    'DampingFactor',1/sqrt(2), ...
    'MaxRaisedFrequencyRadPerSymbol',0.25, ...
    'InitialFrequencySymbols',512);
% Retained as an isolated diagnostic; current ITU-P681 A/B tests show that
% applying ring normalization before carrier DD makes lock worse.
opt.CarrierRecovery.EnableRingNormalizer = false;
% Generic nearest-constellation blind phase search.  This is the validated
% pilotless fine-phase path for both 16APSK and 32APSK.
opt.CarrierRecovery.EnableBlindPhaseSearch = true;
opt.CarrierRecovery.BlindPhaseSearch = struct( ...
    'NumTestPhases',61, ...
    'WindowSymbols',33, ...
    'HopSymbols',4, ...
    'MetricPowerWindowSymbols',33, ...
    'MinConfidence',0.02, ...
    'FadeThresholdDB',-22, ...
    'TrajectoryAlpha',0.85, ...
    'FrequencyAlpha',0.20, ...
    'MaxInnovationRad',deg2rad(35), ...
    'ReacquireReliableBlocks',3, ...
    'PreserveInitialPhase',false, ...
    'MaxFrequencyRadPerSymbol',0.05);
opt.CarrierRecovery.DDLoopBandwidth = 0.002;
opt.CarrierRecovery.EnableDDPhaseTracker = false;
% Experimental shared PI/NCO state machine. It remains disabled until an
% explicit A/B test enables both fields below.
opt.CarrierRecovery.UseCommonSecondOrderLoop = false;
opt.CarrierRecovery.DDAcquireLoopBandwidth = 0.01;
opt.CarrierRecovery.DDLockErrorThresholdRad = 0.12;
opt.CarrierRecovery.DDUnlockErrorThresholdRad = 0.35;
opt.CarrierRecovery.DDLockSymbols = 128;
opt.CarrierRecovery.DDUnlockSymbols = 64;
opt.CarrierRecovery.DDMinAcquireSymbols = 256;
opt.CarrierRecovery.DDErrorTauSymbols = 64;
opt.CarrierRecovery.DDIgnoreInnerRing = false;
% Optional residual-loop cycle-slip guard.  NaN keeps the historical DD
% loop unchanged.  It is useful after feed-forward BPS, where the DD loop
% should only refine a small residual phase rather than change quadrants.
opt.CarrierRecovery.DDResidualPhaseLimitRad = NaN;
opt.CarrierRecovery.DampingFactor = 1/sqrt(2);
opt.CarrierRecovery.DecisionGate = NaN;
opt.CarrierRecovery.DecisionMarginMin = 0.12;
opt.CarrierRecovery.MaxPhaseErrorRad = pi/5;
opt.CarrierRecovery.MaxResidualCFOHz = 100e3;
opt.CarrierRecovery.HoldEnterBadSymbols = 4;
opt.CarrierRecovery.RecoverGoodSymbols = 8;
opt.CarrierRecovery.EnableFadeHold = true;
opt.CarrierRecovery.FadePowerTauSymbols = 64;
opt.CarrierRecovery.FadeEnterDB = -10;
opt.CarrierRecovery.FadeExitDB = -6;
opt.CarrierRecovery.Debug = false;

%% ASM ambiguity resolver
opt.ASM = struct();
opt.ASM.ChannelCoding = 'none';
opt.ASM.PCMFormat = 'NRZ-L';
opt.ASM.NumBytesInTransferFrame = opt.NumBytesInTransferFrame;
opt.ASM.ASMHex = opt.ASMHex;
opt.ASM.DemodNoiseVariance = 0.01;
opt.ASM.MaxSearchBits = 250000;
opt.ASM.ASMMaxErr = 6;
opt.ASM.ASMMinScoreGap = 4;
opt.ASM.PeriodicCandidates = 32;
opt.ASM.PeriodicFrames = 8;
opt.ASM.ASMErrMargin = 4;
opt.ASM.AllowASMInversion = true;
opt.ASM.RequireQualification = true;
opt.ASM.Debug = false;

%% BER / pass criteria
opt.BERWarmUpFrames = 10;
opt.MinDDAcceptance = 0.95;
opt.MaxSteadyEVM_pct = 2.0;
opt.MaxSteadyBER = 1e-5;
opt.MaxPhaseErrorRMS_deg = 1.5;

%% Reproducibility / diagnostics
opt.RandomSeed = 20260819;
opt.Debug = true;
opt.DebugImpairments = true;
opt.DebugReceiver = true;
opt.ReturnWaveforms = false;
end
