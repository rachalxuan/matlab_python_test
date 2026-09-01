function [yOut,info,state] = HelperTMAPSKPilotlessFrontEnd(x,modulation,options)
%HELPERTMAPSKPILOTLESSFRONTEND Experimental pilotless APSK front-end adapter.
%
%   [Y,INFO,STATE] = HelperTMAPSKPilotlessFrontEnd(X,MODULATION,OPTIONS)
%
% Stable integration boundary for run_ccsds_tm_evaluation:
%   input  X : one sample/symbol after the main SRRC/Gardner stage
%   output Y : carrier/gain synchronized APSK symbols, still containing ASM
%
% The helper deliberately does not demap or decode.  Consequently the main
% evaluator remains the owner of CCSDS mapping, ASM/frame handling, soft
% demodulation, randomizer placement and FEC decoding.  The experimental
% implementation stays in apsk_pilotless_stage2_asm and can be removed or
% replaced without perturbing those established interfaces.
%
% OPTIONS accepts main-evaluator fields:
%   symbolRate
%   PilotlessAPSKCarrierRecovery (or CarrierRecovery)
%   enablePilotlessAPSKComplexGainTracker
%   PilotlessAPSKComplexGainTracker
%   debugPilotlessAPSK

if nargin < 2 || isempty(modulation)
    modulation = '32APSK';
end
if nargin < 3 || isempty(options)
    options = struct();
end

x = complex(x(:));
modulation = upper(strtrim(char(string(modulation))));
if ~any(strcmp(modulation,{'16APSK','32APSK'}))
    error('HelperTMAPSKPilotlessFrontEnd:UnsupportedModulation', ...
        'Only 16APSK and 32APSK are supported.');
end

% Keep the laboratory implementation isolated, but make this root-level
% adapter self-contained for callers that add only src/python to the path.
rootDir = fileparts(mfilename('fullpath'));
stageDir = fullfile(rootDir,'apsk_pilotless_stage2_asm');
if exist('HelperTMAPSKCarrierRecovery','file') ~= 2
    if exist(fullfile(stageDir,'HelperTMAPSKCarrierRecovery.m'),'file') ~= 2
        error('HelperTMAPSKPilotlessFrontEnd:MissingImplementation', ...
            'Pilotless APSK implementation directory is missing: %s',stageDir);
    end
    addpath(stageDir);
end

defaultCfg = apskPilotlessDefaultConfig();
carrierOpt = defaultCfg.CarrierRecovery;
if isfield(options,'CarrierRecovery') && isstruct(options.CarrierRecovery)
    carrierOpt = localMerge(carrierOpt,options.CarrierRecovery);
end
if isfield(options,'PilotlessAPSKCarrierRecovery') && ...
        isstruct(options.PilotlessAPSKCarrierRecovery)
    carrierOpt = localMerge(carrierOpt,options.PilotlessAPSKCarrierRecovery);
end
globalPhaseExplicit = ...
    (isfield(options,'CarrierRecovery') && ...
     isstruct(options.CarrierRecovery) && ...
     isfield(options.CarrierRecovery,'UseGlobalNDAPhase')) || ...
    (isfield(options,'PilotlessAPSKCarrierRecovery') && ...
     isstruct(options.PilotlessAPSKCarrierRecovery) && ...
     isfield(options.PilotlessAPSKCarrierRecovery,'UseGlobalNDAPhase'));
if localLogical(options,'enableHChannel',false) && ~globalPhaseExplicit
    % A single phase fitted across thousands of symbols is appropriate for
    % fixed CFO, but it smears a genuinely time-varying H phase trajectory.
    % The H path therefore starts from the local block trajectory unless the
    % caller explicitly asks for the global estimator.
    carrierOpt.UseGlobalNDAPhase = false;
end
if localLogical(options,'enableHChannel',false)
    if ~localCarrierFieldExplicit(options,'AcquisitionSymbols')
        carrierOpt.AcquisitionSymbols = max(16384, ...
            localNumber(carrierOpt,'AcquisitionSymbols',4096));
    end
    if ~localCarrierFieldExplicit(options,'AcquisitionBlockSymbols')
        carrierOpt.AcquisitionBlockSymbols = 32;
    end
    if ~localCarrierFieldExplicit(options,'FourthPowerFFTLength')
        carrierOpt.FourthPowerFFTLength = max(131072, ...
            localNumber(carrierOpt,'FourthPowerFFTLength',65536));
    end
    residualCFOExplicit = ...
        (isfield(options,'CarrierRecovery') && ...
         isstruct(options.CarrierRecovery) && ...
         isfield(options.CarrierRecovery,'ApplyNDAResidualCFO')) || ...
        (isfield(options,'PilotlessAPSKCarrierRecovery') && ...
         isstruct(options.PilotlessAPSKCarrierRecovery) && ...
         isfield(options.PilotlessAPSKCarrierRecovery, ...
         'ApplyNDAResidualCFO'));
    if ~residualCFOExplicit
        % With a time-varying H, x^M FFT removes the dominant Doppler while
        % the local NDA block trajectory provides a useful residual-CFO
        % estimate.  Leaving that kHz-level term to the phase tracker makes
        % its moving average decorrelate and creates 2*pi/M branch slips.
        carrierOpt.ApplyNDAResidualCFO = true;
    end
    mthExplicit = ...
        (isfield(options,'CarrierRecovery') && ...
         isstruct(options.CarrierRecovery) && ...
         isfield(options.CarrierRecovery,'EnableMthPowerPhaseTracker')) || ...
        (isfield(options,'PilotlessAPSKCarrierRecovery') && ...
         isstruct(options.PilotlessAPSKCarrierRecovery) && ...
         isfield(options.PilotlessAPSKCarrierRecovery, ...
         'EnableMthPowerPhaseTracker'));
    if ~mthExplicit
        carrierOpt.EnableMthPowerPhaseTracker = false;
    end
    if ~localCarrierFieldExplicit(options,'EnableBlindPhaseSearch')
        carrierOpt.EnableBlindPhaseSearch = true;
    end
    if ~isfield(carrierOpt,'BlindPhaseSearch') || ...
            ~isstruct(carrierOpt.BlindPhaseSearch)
        carrierOpt.BlindPhaseSearch = struct();
    end
    % The APSK BPS shares the QAM phase-search engine, but its metric gate is
    % scaled by the APSK minimum distance.  These H-only defaults leave the
    % validated standalone/NoH receiver unchanged.
    if ~isfield(carrierOpt.BlindPhaseSearch,'EnableFadeHold')
        carrierOpt.BlindPhaseSearch.EnableFadeHold = true;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch,'FadeEnterDB')
        carrierOpt.BlindPhaseSearch.FadeEnterDB = -10;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch,'FadeExitDB')
        carrierOpt.BlindPhaseSearch.FadeExitDB = -7;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch, ...
            'ReliableMetricOverridesFadeHold')
        carrierOpt.BlindPhaseSearch.ReliableMetricOverridesFadeHold = true;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch,'FadeOverrideMaxMetric') && ...
            ~isfield(carrierOpt.BlindPhaseSearch, ...
            'FadeOverrideMaxMetricFraction')
        carrierOpt.BlindPhaseSearch.FadeOverrideMaxMetricFraction = 0.05;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch,'FadeOverrideMinConfidence')
        carrierOpt.BlindPhaseSearch.FadeOverrideMinConfidence = 0.20;
    end
    if ~isfield(carrierOpt.BlindPhaseSearch,'FadeOverrideRecoverBlocks')
        carrierOpt.BlindPhaseSearch.FadeOverrideRecoverBlocks = 16;
    end
    if ~localCarrierFieldExplicit(options,'EnableDDPhaseTracker')
        carrierOpt.EnableDDPhaseTracker = false;
    end
    if ~localCarrierFieldExplicit(options,'RecoverGoodSymbols')
        % One trustworthy symbol is enough to leave HOLD.  Requiring eight
        % consecutive symbols made the narrow 32APSK gate self-lock after a
        % fade even while the NDA phase estimate was already usable.
        carrierOpt.RecoverGoodSymbols = 1;
    end
    if ~localCarrierFieldExplicit(options,'EnableRingNormalizer')
        % Normalized H keeps its local envelope trajectory.  Stabilize APSK
        % ring radii before BPS/DD, while leaving the validated NoH path
        % unchanged.  An explicit false remains a strict A/B rollback.
        carrierOpt.EnableRingNormalizer = true;
    end
    if ~localCarrierFieldExplicit(options,'RingNormalizer')
        carrierOpt.RingNormalizer = struct( ...
            'EstimatorMode','rde', ...
            'StepSize',0.04, ...
            'RingMarginMin',0.05, ...
            'EnableFadeHold',true, ...
            'FadePowerTauSymbols',32, ...
            'FadeEnterDB',-10, ...
            'FadeExitDB',-6, ...
            'RecoverGoodSymbols',1, ...
            'Regularization',1e-3, ...
            'MaxInverseGainDB',18);
    end
end
carrierOpt.SymbolRateHz = localNumber(options,'symbolRate',10e6);
sharedHoldMask = false(numel(x),1);
sharedHoldProvided = isfield(options,'BlindReliabilityExternalHoldMask') && ...
    ~isempty(options.BlindReliabilityExternalHoldMask);
sharedMaxInverseGainDB = localNumber(options, ...
    'blindReliabilityMaxInverseGainDB',18);
if sharedHoldProvided
    sharedHoldMask = logical(options.BlindReliabilityExternalHoldMask(:));
    if numel(sharedHoldMask) ~= numel(x)
        error('HelperTMAPSKPilotlessFrontEnd:ReliabilityMaskLength', ...
            'BlindReliabilityExternalHoldMask has %d symbols; expected %d.', ...
            numel(sharedHoldMask),numel(x));
    end
    if ~isfield(carrierOpt,'PreDDGainTracker') || ...
            ~isstruct(carrierOpt.PreDDGainTracker)
        carrierOpt.PreDDGainTracker = struct();
    end
    carrierOpt.PreDDGainTracker.ExternalHoldMask = sharedHoldMask;
    carrierOpt.PreDDGainTracker.MaxInverseGainDB = min( ...
        localNumber(carrierOpt.PreDDGainTracker,'MaxInverseGainDB', ...
        sharedMaxInverseGainDB),sharedMaxInverseGainDB);
    if ~isfield(carrierOpt,'RingNormalizer') || ...
            ~isstruct(carrierOpt.RingNormalizer)
        carrierOpt.RingNormalizer = struct();
    end
    carrierOpt.RingNormalizer.ExternalHoldMask = sharedHoldMask;
    carrierOpt.RingNormalizer.MaxInverseGainDB = min( ...
        localNumber(carrierOpt.RingNormalizer,'MaxInverseGainDB', ...
        sharedMaxInverseGainDB),sharedMaxInverseGainDB);
    if ~isfield(carrierOpt,'BlindPhaseSearch') || ...
            ~isstruct(carrierOpt.BlindPhaseSearch)
        carrierOpt.BlindPhaseSearch = struct();
    end
    if isfield(carrierOpt.BlindPhaseSearch,'ExternalHoldMask') && ...
            ~isempty(carrierOpt.BlindPhaseSearch.ExternalHoldMask)
        existingBPSHold = logical( ...
            carrierOpt.BlindPhaseSearch.ExternalHoldMask(:));
        if numel(existingBPSHold) ~= numel(sharedHoldMask)
            error('HelperTMAPSKPilotlessFrontEnd:BPSHoldMaskLength', ...
                ['BlindPhaseSearch.ExternalHoldMask has %d symbols; ', ...
                 'expected %d.'],numel(existingBPSHold),numel(sharedHoldMask));
        end
        carrierOpt.BlindPhaseSearch.ExternalHoldMask = ...
            existingBPSHold | sharedHoldMask;
    else
        carrierOpt.BlindPhaseSearch.ExternalHoldMask = sharedHoldMask;
    end
    % This top-level mask is consumed by the optional APSK DD carrier loop.
    % BPS, DD, ring normalization and both scalar gain stages now observe the
    % same physical fade state.
    carrierOpt.ExternalHoldMask = sharedHoldMask;
end
if isfield(options,'carrierCaptureRangeHz') && ...
        ~isempty(options.carrierCaptureRangeHz)
    captureRangeHz = double(options.carrierCaptureRangeHz);
    if ~isscalar(captureRangeHz) || ~isfinite(captureRangeHz) || ...
            captureRangeHz <= 0
        error('HelperTMAPSKPilotlessFrontEnd:InvalidCaptureRange', ...
            'carrierCaptureRangeHz must be a finite positive scalar.');
    end
    carrierOpt.MaxAcquisitionCFOHz = captureRangeHz;
end
debugEnabled = localLogical(options,'debugPilotlessAPSK',false) || ...
    localLogical(options,'debugCarrierRecovery',false);
carrierOpt.Debug = debugEnabled || localLogical(carrierOpt,'Debug',false);

[carrierOut,carrierState,carrierInfo] = ...
    HelperTMAPSKCarrierRecovery(x,modulation,carrierOpt);

if ~carrierInfo.Applied || ~carrierInfo.AcquisitionQualified
    error('HelperTMAPSKPilotlessFrontEnd:CarrierAcquisitionFailed', ...
        'Pilotless carrier acquisition failed: %s',carrierInfo.Reason);
end

enableGain = localLogical(options, ...
    'enablePilotlessAPSKComplexGainTracker',true);
gainInfo = localEmptyGainInfo();
gainState = struct();
yOut = carrierOut;
if enableGain
    gainOpt = struct();
    if isfield(options,'PilotlessAPSKComplexGainTracker') && ...
            isstruct(options.PilotlessAPSKComplexGainTracker)
        gainOpt = options.PilotlessAPSKComplexGainTracker;
    end
    if ~isfield(gainOpt,'TrackPhase')
        % The preceding APSK DD PLL owns phase/frequency.  The one-tap
        % tracker starts as an amplitude/fade equalizer so the two loops do
        % not integrate the same phase error in cascade.
        gainOpt.TrackPhase = false;
    end
    if ~isfield(gainOpt,'MagnitudeEstimationMode')
        if sharedHoldProvided
            % In the H-channel path the preceding APSK RDE/BPS stages can
            % leave a time-varying scalar magnitude at this boundary.  A
            % frozen power estimate then keeps the whole deep-fade interval
            % at one stale scale and moves only the radial APSK bit-planes
            % across their thresholds.  Ring-directed magnitude tracking
            % removes data-ring power without borrowing transmitted bits.
            gainOpt.MagnitudeEstimationMode = 'ring-directed';
        else
            % Preserve the established static/no-H receiver default.
            gainOpt.MagnitudeEstimationMode = 'power';
        end
    end
    if ~isfield(gainOpt,'TrackPowerMagnitudeDuringFade')
        % HOLD protects phase/DD state.  The pilotless magnitude observer is
        % still valid in a noiseless time-varying fade and must keep moving;
        % otherwise recovery cannot occur because the radial thresholds see
        % the stale pre-fade scale.  The inverse-gain cap remains the safety
        % boundary once additive noise is introduced.
        gainOpt.TrackPowerMagnitudeDuringFade = sharedHoldProvided;
    end
    if ~isfield(gainOpt,'UpdatePowerReference')
        gainOpt.UpdatePowerReference = false;
    end
    if ~isfield(gainOpt,'FadePowerTauSymbols')
        gainOpt.FadePowerTauSymbols = 16;
    end
    if ~isfield(gainOpt,'EnableFadeHold')
        gainOpt.EnableFadeHold = true;
    end
    if ~isfield(gainOpt,'FadeEnterDB')
        gainOpt.FadeEnterDB = -10;
    end
    if ~isfield(gainOpt,'FadeExitDB')
        gainOpt.FadeExitDB = -6;
    end
    if ~isfield(gainOpt,'Regularization')
        gainOpt.Regularization = 0;
    end
    if ~isfield(gainOpt,'MaxInverseGainDB')
        gainOpt.MaxInverseGainDB = 40;
    end
    if sharedHoldProvided
        gainOpt.ExternalHoldMask = sharedHoldMask;
        gainOpt.MaxInverseGainDB = min( ...
            localNumber(gainOpt,'MaxInverseGainDB', ...
            sharedMaxInverseGainDB),sharedMaxInverseGainDB);
    end
    if ~isfield(gainOpt,'TrackMagnitude')
        gainOpt.TrackMagnitude = true;
    end
    if ~isfield(gainOpt,'DecisionGate')
        gainOpt.DecisionGate = 0.35;
    end
    if ~isfield(gainOpt,'DecisionMarginMin')
        gainOpt.DecisionMarginMin = 0;
    end
    if ~isfield(gainOpt,'RecoverGoodSymbols')
        gainOpt.RecoverGoodSymbols = 1;
    end
    if ~isfield(gainOpt,'HoldEnterBadSymbols')
        gainOpt.HoldEnterBadSymbols = 16;
    end
    if ~isfield(gainOpt,'InitialGainMagnitude')
        gainOpt.InitialGainMagnitude = 1;
    end
    if ~isfield(gainOpt,'PowerReference')
        % HelperTMAPSKCarrierRecovery supplies a unit-average-power stream.
        % Use that known internal reference instead of treating a faded
        % acquisition prefix as the nominal power.
        gainOpt.PowerReference = 1;
    end
    gainOpt.Debug = debugEnabled || localLogical(gainOpt,'Debug',false);
    ref = localReference(modulation);
    [yOut,gainState,gainInfo] = ...
        HelperTMComplexGainTracker(carrierOut,ref,gainOpt);
end

info = struct();
info.Applied = true;
info.Mode = 'pilotless-xM-nda-dd-one-tap';
info.Reason = 'pilotless APSK carrier recovery followed by optional one-tap complex gain tracking';
info.Modulation = modulation;
info.InputSymbols = numel(x);
info.OutputSymbols = numel(yOut);
info.Carrier = carrierInfo;
info.ComplexGain = gainInfo;
info.ComplexGainEnabled = enableGain;
info.FourthPowerCFO_Hz = carrierInfo.FourthPowerCFO_Hz;
info.FourthPowerConfidence_dB = carrierInfo.FourthPowerConfidence_dB;
info.CoarsePowerOrder = carrierInfo.CoarsePowerOrder;
info.NDAResidualCFO_Hz = carrierInfo.NDAResidualCFO_Hz;
info.NDAResidualCFOApplied = carrierInfo.NDAResidualCFOApplied;
info.MthPowerPhaseTrackerApplied = ...
    carrierInfo.MthPowerPhaseTrackerApplied;
info.MthPowerPhaseFinalCorrection_deg = ...
    carrierInfo.MthPowerPhaseFinalCorrection_deg;
info.MthPowerPhaseMedianConfidence = ...
    carrierInfo.MthPowerPhaseMedianConfidence;
info.BlindPhaseSearchApplied = carrierInfo.BlindPhaseSearchApplied;
info.BlindPhaseSearchReliableFraction = ...
    carrierInfo.BlindPhaseSearchReliableFraction;
info.BlindPhaseSearchMedianMetric = ...
    carrierInfo.BlindPhaseSearchMedianMetric;
info.BlindPhaseSearchFinalCorrection_deg = ...
    carrierInfo.BlindPhaseSearchFinalCorrection_deg;
info.PreDDGainTrackerApplied = carrierInfo.PreDDGainTrackerApplied;
info.PreDDGainAcceptanceRate = carrierInfo.PreDDGainAcceptanceRate;
info.PreDDGainHoldFraction = carrierInfo.PreDDGainHoldFraction;
info.PreDDGainFadeFraction = carrierInfo.PreDDGainFadeFraction;
info.PreDDGainFinalMagnitude_dB = ...
    carrierInfo.PreDDGainFinalMagnitude_dB;
info.RingNormalizerApplied = carrierInfo.RingNormalizerApplied;
info.RingEstimatorMode = carrierInfo.RingEstimatorMode;
info.RingAcceptanceRate = carrierInfo.RingAcceptanceRate;
info.RingHoldFraction = carrierInfo.RingHoldFraction;
info.RingFadeFraction = carrierInfo.RingFadeFraction;
info.RingFinalAmplitude_dB = carrierInfo.RingFinalAmplitude_dB;
info.CarrierAcceptanceRate = carrierInfo.AcceptanceRate;
info.CarrierHoldFraction = carrierInfo.HoldFraction;
info.CarrierFadeFraction = carrierInfo.FadeFraction;
info.CarrierPhaseErrorRMS_deg = carrierInfo.PhaseErrorRMS_deg;
info.FinalResidualFrequency_Hz = carrierInfo.FinalResidualFrequency_Hz;
info.GainAcceptanceRate = gainInfo.AcceptanceRate;
info.GainHoldFraction = gainInfo.HoldFraction;
info.GainFadeFraction = gainInfo.FadeFraction;
info.FinalGainMagnitude_dB = gainInfo.FinalGainMagnitude_dB;
info.FinalGainPhase_deg = gainInfo.FinalGainPhase_deg;
info.GainRegularization = gainInfo.Regularization;
info.GainMaxInverseGainDB = gainInfo.MaxInverseGainDB;
info.GainInverseMaxObserved_dB = gainInfo.InverseGainMaxObserved_dB;
info.SharedReliabilityMaskProvided = sharedHoldProvided;
info.SharedReliabilityHoldSymbols = nnz(sharedHoldMask);
info.SharedReliabilityHoldFraction = mean(sharedHoldMask);

state = struct('Carrier',carrierState,'ComplexGain',gainState);

if debugEnabled
    fprintf('\n[TM pilotless APSK front-end adapter]\n');
    fprintf('  mode             : %s\n',info.Mode);
    fprintf('  symbols in/out   : %d / %d\n',info.InputSymbols,info.OutputSymbols);
    fprintf('  x^M CFO/conf     : M=%g, %+.3f Hz / %.2f dB\n', ...
        carrierInfo.CoarsePowerOrder,info.FourthPowerCFO_Hz, ...
        info.FourthPowerConfidence_dB);
    fprintf('  carrier accept   : %.2f%%, HOLD=%.2f%%, fade=%.2f%%\n', ...
        100*info.CarrierAcceptanceRate,100*info.CarrierHoldFraction, ...
        100*info.CarrierFadeFraction);
    fprintf('  pre-DD gain      : applied=%d accept=%.2f%% HOLD=%.2f%% fade=%.2f%%\n', ...
        info.PreDDGainTrackerApplied, ...
        100*info.PreDDGainAcceptanceRate, ...
        100*info.PreDDGainHoldFraction, ...
        100*info.PreDDGainFadeFraction);
    fprintf(['  pre-DD APSK ring : mode=%s applied=%d accept=%.2f%% ', ...
        'HOLD=%.2f%% fade=%.2f%% finalAmp=%+.2f dB\n'], ...
        info.RingEstimatorMode,info.RingNormalizerApplied, ...
        100*info.RingAcceptanceRate,100*info.RingHoldFraction, ...
        100*info.RingFadeFraction,info.RingFinalAmplitude_dB);
    fprintf('  blind phase BPS  : applied=%d reliable=%.2f%% metric=%.5g final=%+.2f deg\n', ...
        info.BlindPhaseSearchApplied, ...
        100*info.BlindPhaseSearchReliableFraction, ...
        info.BlindPhaseSearchMedianMetric, ...
        info.BlindPhaseSearchFinalCorrection_deg);
    fprintf('  gain enabled     : %d, accept=%.2f%%, HOLD=%.2f%%, fade=%.2f%%\n', ...
        info.ComplexGainEnabled,100*info.GainAcceptanceRate, ...
        100*info.GainHoldFraction,100*info.GainFadeFraction);
    fprintf('  inverse gain     : max=%+.2f dB, cap=%+.2f dB, regularization=%g\n', ...
        info.GainInverseMaxObserved_dB,info.GainMaxInverseGainDB, ...
        info.GainRegularization);
    fprintf('  shared HOLD      : provided=%d, symbols=%d (%.2f%%)\n', ...
        info.SharedReliabilityMaskProvided, ...
        info.SharedReliabilityHoldSymbols, ...
        100*info.SharedReliabilityHoldFraction);
    fprintf('  main boundary    : symbols still contain ASM; demap/FEC not performed here\n\n');
end
end

function ref = localReference(modulation)
if strcmpi(modulation,'16APSK')
    ref = HelperCCSDSFACMReferenceConstellation(14);
else
    ref = HelperCCSDSFACMReferenceConstellation(21);
end
ref = complex(ref(:));
ref = ref/sqrt(mean(abs(ref).^2)+eps);
end

function out = localMerge(base,override)
out = base;
names = fieldnames(override);
for k = 1:numel(names)
    out.(names{k}) = override.(names{k});
end
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    raw = s.(name);
    if isnumeric(raw) || islogical(raw)
        value = double(raw(1));
    else
        value = str2double(string(raw));
    end
end
end

function value = localLogical(s,name,defaultValue)
value = logical(defaultValue);
if ~(isstruct(s) && isfield(s,name) && ~isempty(s.(name)))
    return;
end
raw = s.(name);
if isnumeric(raw) || islogical(raw)
    value = logical(raw(1));
else
    value = any(lower(strtrim(string(raw))) == ["true","1","yes","on"]);
end
end

function tf = localCarrierFieldExplicit(options,name)
tf = (isstruct(options) && isfield(options,'CarrierRecovery') && ...
      isstruct(options.CarrierRecovery) && ...
      isfield(options.CarrierRecovery,name)) || ...
     (isstruct(options) && ...
      isfield(options,'PilotlessAPSKCarrierRecovery') && ...
      isstruct(options.PilotlessAPSKCarrierRecovery) && ...
      isfield(options.PilotlessAPSKCarrierRecovery,name));
end

function info = localEmptyGainInfo()
info = struct('Applied',false,'AcceptanceRate',NaN, ...
    'HoldFraction',NaN,'FadeFraction',NaN, ...
    'FinalGainMagnitude_dB',NaN,'FinalGainPhase_deg',NaN, ...
    'Regularization',NaN,'MaxInverseGainDB',NaN, ...
    'InverseGainMaxObserved_dB',NaN);
end
