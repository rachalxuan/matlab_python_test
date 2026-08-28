function [y,state,info] = HelperTMSecondOrderCarrierLoop(x,phaseDetector,options)
%HELPERTMSECONDORDERCARRIERLOOP Reusable decision-directed PI carrier loop.
%
%   [Y,STATE,INFO] = HelperTMSecondOrderCarrierLoop(X,DETECTOR,OPTIONS)
%
% X is a complex one-sample/symbol stream. DETECTOR is a function handle
% with the contract
%
%   [phaseErrorRad,reliable,metric] = detector(z,n)
%
% where Z is the current NCO-corrected symbol and N is its one-based index.
% The modulation-specific detector owns only its phase-error equation and
% reliability decision. This helper owns the common second-order PI loop,
% NCO phase/frequency states, ACQUIRE/TRACK/HOLD transitions, fade holdover,
% recovery and diagnostics.
%
% Important OPTIONS fields (defaults):
%   SymbolRateHz                = 1
%   AcquireLoopBandwidth       = 0.01
%   TrackLoopBandwidth         = 0.002
%   DampingFactor              = 1/sqrt(2)
%   InitialPhaseRad            = 0
%   InitialFrequencyHz         = 0
%   MaxFrequencyHz             = 0.05*SymbolRateHz
%   MaxPhaseErrorRad           = pi/3
%   LockErrorThresholdRad      = 0.12
%   UnlockErrorThresholdRad    = 0.35
%   LockSymbols                = 128
%   UnlockSymbols              = 64
%   MinAcquireSymbols          = 256
%   ErrorTauSymbols            = 64
%   HoldEnterBadSymbols        = 4
%   RecoverGoodSymbols         = 8
%   EnableFadeHold             = true
%   FadePowerTauSymbols        = 64
%   FadeEnterDB                = -10
%   FadeExitDB                 = -6
%   PowerReference             = mean(abs(X).^2)
%   ResidualPhaseLimitRad      = inf
%   CollectTrace               = false
%   Debug                      = false
%   DebugLabel                 = 'carrier'
%
% The loop is deliberately a fine tracker. A wide feed-forward frequency
% estimator must first put the residual CFO inside MaxFrequencyHz. HOLD does
% not invent carrier information: it coasts with the last valid frequency
% state and returns to ACQUIRE only after reliable observations reappear.

if nargin < 2 || isempty(phaseDetector) || ~isa(phaseDetector,'function_handle')
    error('HelperTMSecondOrderCarrierLoop:InvalidDetector', ...
        'phaseDetector must be a function handle.');
end
if nargin < 3 || isempty(options)
    options = struct();
end

x = complex(x(:));
y = complex(zeros(size(x)));
info = localEmptyInfo();
state = localEmptyState();
if isempty(x)
    info.Reason = 'empty input';
    return;
end
if any(~isfinite(real(x))) || any(~isfinite(imag(x)))
    error('HelperTMSecondOrderCarrierLoop:NonfiniteInput', ...
        'Input contains NaN or Inf.');
end

Rs = localNumber(options,'SymbolRateHz',1);
if ~isscalar(Rs) || ~isfinite(Rs) || Rs <= 0
    error('HelperTMSecondOrderCarrierLoop:InvalidSymbolRate', ...
        'SymbolRateHz must be a finite positive scalar.');
end

acquireBW = localNumber(options,'AcquireLoopBandwidth',0.01);
trackBW = localNumber(options,'TrackLoopBandwidth',0.002);
damping = localNumber(options,'DampingFactor',1/sqrt(2));
if ~isscalar(acquireBW) || ~isfinite(acquireBW) || ...
        acquireBW <= 0 || acquireBW > 0.2
    error('HelperTMSecondOrderCarrierLoop:InvalidAcquireBandwidth', ...
        'AcquireLoopBandwidth must be in (0,0.2].');
end
if ~isscalar(trackBW) || ~isfinite(trackBW) || ...
        trackBW <= 0 || trackBW > acquireBW
    error('HelperTMSecondOrderCarrierLoop:InvalidTrackBandwidth', ...
        'TrackLoopBandwidth must be in (0,AcquireLoopBandwidth].');
end
if ~isscalar(damping) || ~isfinite(damping) || damping <= 0
    error('HelperTMSecondOrderCarrierLoop:InvalidDamping', ...
        'DampingFactor must be a finite positive scalar.');
end
[acquireAlpha,acquireBeta] = localLoopGains(acquireBW,damping);
[trackAlpha,trackBeta] = localLoopGains(trackBW,damping);

maxFrequencyHz = max(0,localNumber(options, ...
    'MaxFrequencyHz',0.05*Rs));
maxOmega = 2*pi*maxFrequencyHz/Rs;
maxPhaseError = localNumber(options,'MaxPhaseErrorRad',pi/3);
maxPhaseError = min(max(maxPhaseError,deg2rad(1)),pi);
phaseLimit = localNumber(options,'ResidualPhaseLimitRad',inf);
if ~isfinite(phaseLimit) || phaseLimit <= 0
    phaseLimit = inf;
else
    phaseLimit = min(phaseLimit,pi);
end

lockThreshold = max(0,localNumber(options, ...
    'LockErrorThresholdRad',0.12));
unlockThreshold = max(lockThreshold,localNumber(options, ...
    'UnlockErrorThresholdRad',0.35));
lockSymbols = max(1,round(localNumber(options,'LockSymbols',128)));
unlockSymbols = max(1,round(localNumber(options,'UnlockSymbols',64)));
minAcquireSymbols = max(lockSymbols,round(localNumber(options, ...
    'MinAcquireSymbols',256)));
errorTau = max(1,localNumber(options,'ErrorTauSymbols',64));
errorAlpha = exp(-1/errorTau);
holdEnterBad = max(1,round(localNumber(options, ...
    'HoldEnterBadSymbols',4)));
recoverGood = max(1,round(localNumber(options, ...
    'RecoverGoodSymbols',8)));

enableFadeHold = localLogical(options,'EnableFadeHold',true);
fadeTau = max(4,localNumber(options,'FadePowerTauSymbols',64));
fadeEnterDB = localNumber(options,'FadeEnterDB',-10);
fadeExitDB = localNumber(options,'FadeExitDB',-6);
if fadeExitDB <= fadeEnterDB
    error('HelperTMSecondOrderCarrierLoop:InvalidFadeHysteresis', ...
        'FadeExitDB must be greater than FadeEnterDB.');
end
fadeEnterRatio = 10^(fadeEnterDB/10);
fadeExitRatio = 10^(fadeExitDB/10);
fadeAlpha = 1-exp(-1/fadeTau);

powerReference = localNumber(options,'PowerReference',NaN);
if ~isfinite(powerReference) || powerReference <= 0
    powerReference = mean(abs(x).^2)+eps;
end
pInit = min(max(16,round(fadeTau/2)),numel(x));
powerIIR = mean(abs(x(1:pInit)).^2)+eps;

phaseState = localWrapPi(localNumber(options,'InitialPhaseRad',0));
frequencyHz = localNumber(options,'InitialFrequencyHz',0);
if ~isfinite(frequencyHz), frequencyHz = 0; end
omegaState = min(max(2*pi*frequencyHz/Rs,-maxOmega),maxOmega);

mode = "ACQUIRE";
locked = false;
acquireAge = 0;
goodCount = 0;
badCount = 0;
unlockCount = 0;
errorState = unlockThreshold;
holdEvents = 0;
recoverEvents = 0;
lockTransitions = 0;
reacquisitions = 0;
cycleSlipRejects = 0;
inPowerFade = false;

accepted = false(size(x));
reliableMask = false(size(x));
holdMask = false(size(x));
fadeMask = false(size(x));
phaseError = NaN(size(x));
detectorMetric = NaN(size(x));
frequencyTrace = NaN(size(x));
phaseTrace = NaN(size(x));

for n = 1:numel(x)
    phaseBefore = phaseState;
    omegaBefore = omegaState;
    z = x(n)*exp(-1j*phaseState);
    y(n) = z;

    [err,detectorReliable,metric] = localCallDetector(phaseDetector,z,n);
    phaseError(n) = err;
    detectorMetric(n) = metric;

    powerIIR = (1-fadeAlpha)*powerIIR + fadeAlpha*abs(x(n))^2;
    powerRatio = powerIIR/(powerReference+eps);
    if enableFadeHold
        if ~inPowerFade && powerRatio < fadeEnterRatio
            inPowerFade = true;
        elseif inPowerFade && powerRatio > fadeExitRatio
            inPowerFade = false;
        end
    else
        inPowerFade = false;
    end
    fadeMask(n) = inPowerFade;

    reliable = detectorReliable && isfinite(err) && ...
        abs(err) <= maxPhaseError && ~inPowerFade;
    reliableMask(n) = reliable;

    if mode == "HOLD"
        holdMask(n) = true;
        phaseState = phaseState + omegaState;
        if reliable
            goodCount = goodCount + 1;
        else
            goodCount = 0;
        end
        if goodCount >= recoverGood
            mode = "ACQUIRE";
            locked = false;
            acquireAge = 0;
            goodCount = 0;
            badCount = 0;
            unlockCount = 0;
            recoverEvents = recoverEvents + 1;
            reacquisitions = reacquisitions + 1;
        end
    else
        acquireAge = acquireAge + ~locked;
        if locked
            alpha = trackAlpha;
            beta = trackBeta;
        else
            alpha = acquireAlpha;
            beta = acquireBeta;
        end

        if reliable
            accepted(n) = true;
            badCount = 0;
            omegaState = omegaState + beta*err;
            omegaState = min(max(omegaState,-maxOmega),maxOmega);
            phaseState = phaseState + omegaState + alpha*err;
            errorState = errorAlpha*errorState + ...
                (1-errorAlpha)*abs(err);

            if ~locked
                if errorState <= lockThreshold
                    goodCount = goodCount + 1;
                else
                    goodCount = 0;
                end
                if acquireAge >= minAcquireSymbols && goodCount >= lockSymbols
                    locked = true;
                    mode = "TRACK";
                    lockTransitions = lockTransitions + 1;
                    goodCount = 0;
                end
            else
                if errorState >= unlockThreshold
                    unlockCount = unlockCount + 1;
                else
                    unlockCount = 0;
                end
                if unlockCount >= unlockSymbols
                    locked = false;
                    mode = "ACQUIRE";
                    acquireAge = 0;
                    goodCount = 0;
                    unlockCount = 0;
                    reacquisitions = reacquisitions + 1;
                end
            end
        else
            phaseState = phaseState + omegaState;
            badCount = badCount + 1;
            goodCount = 0;
            unlockCount = unlockCount + locked;
            if badCount >= holdEnterBad || inPowerFade
                mode = "HOLD";
                locked = false;
                holdEvents = holdEvents + 1;
                goodCount = 0;
            end
        end
    end

    phaseState = localWrapPi(phaseState);
    if abs(phaseState) > phaseLimit
        phaseState = phaseBefore;
        omegaState = omegaBefore;
        accepted(n) = false;
        holdMask(n) = true;
        if mode ~= "HOLD"
            holdEvents = holdEvents + 1;
        end
        mode = "HOLD";
        locked = false;
        goodCount = 0;
        badCount = 0;
        cycleSlipRejects = cycleSlipRejects + 1;
    end

    frequencyTrace(n) = omegaState*Rs/(2*pi);
    phaseTrace(n) = phaseState;
end

validErr = phaseError(accepted & isfinite(phaseError));
if isempty(validErr)
    rmsErr = NaN;
    meanAbsErr = NaN;
else
    rmsErr = sqrt(mean(validErr.^2));
    meanAbsErr = mean(abs(validErr));
end

state.Mode = char(mode);
state.Locked = locked;
state.PhaseRad = phaseState;
state.FrequencyRadPerSymbol = omegaState;
state.FrequencyHz = omegaState*Rs/(2*pi);
state.ErrorStateRad = errorState;
state.PowerIIR = powerIIR;
state.PowerFade = inPowerFade;

info.Applied = true;
info.Reason = 'modulation-specific detector + reusable second-order PI/NCO';
info.SymbolRateHz = Rs;
info.AcquireLoopBandwidth = acquireBW;
info.TrackLoopBandwidth = trackBW;
info.DampingFactor = damping;
info.AcquireAlpha = acquireAlpha;
info.AcquireBeta = acquireBeta;
info.TrackAlpha = trackAlpha;
info.TrackBeta = trackBeta;
info.AcceptedUpdates = nnz(accepted);
info.AcceptanceRate = mean(accepted);
info.ReliableFraction = mean(reliableMask);
info.HoldSymbols = nnz(holdMask);
info.HoldFraction = mean(holdMask);
info.FadeSymbols = nnz(fadeMask);
info.FadeFraction = mean(fadeMask);
info.HoldEvents = holdEvents;
info.RecoverEvents = recoverEvents;
info.LockTransitions = lockTransitions;
info.Reacquisitions = reacquisitions;
info.CycleSlipRejects = cycleSlipRejects;
info.PhaseErrorRMS_deg = rad2deg(rmsErr);
info.MeanAbsPhaseError_deg = rad2deg(meanAbsErr);
info.FinalFrequencyHz = state.FrequencyHz;
info.FinalPhase_deg = rad2deg(state.PhaseRad);
info.FinalMode = state.Mode;
info.Locked = state.Locked;
info.AcceptedMask = accepted;
info.ReliableMask = reliableMask;
info.HoldMask = holdMask;
info.FadeMask = fadeMask;
info.PhaseErrorRad = phaseError;
info.DetectorMetric = detectorMetric;
if localLogical(options,'CollectTrace',false)
    info.FrequencyTraceHz = frequencyTrace;
    info.PhaseTraceRad = phaseTrace;
else
    info.FrequencyTraceHz = zeros(0,1);
    info.PhaseTraceRad = zeros(0,1);
end

if localLogical(options,'Debug',false)
    label = char(string(localText(options,'DebugLabel','carrier')));
    fprintf('\n[TM common second-order carrier loop: %s]\n',label);
    fprintf('  mode/locked     : %s / %d\n',state.Mode,state.Locked);
    fprintf('  BW acquire/track: %.6g / %.6g\n',acquireBW,trackBW);
    fprintf('  PI acquire      : alpha=%.6g beta=%.6g\n', ...
        acquireAlpha,acquireBeta);
    fprintf('  PI track        : alpha=%.6g beta=%.6g\n', ...
        trackAlpha,trackBeta);
    fprintf('  accept/reliable : %.2f%% / %.2f%%\n', ...
        100*info.AcceptanceRate,100*info.ReliableFraction);
    fprintf('  HOLD/fade       : %.2f%% / %.2f%%, events=%d recoveries=%d\n', ...
        100*info.HoldFraction,100*info.FadeFraction, ...
        holdEvents,recoverEvents);
    fprintf('  lock/reacquire  : %d / %d\n', ...
        lockTransitions,reacquisitions);
    fprintf('  phase RMS/final : %.3f / %+.3f deg\n', ...
        info.PhaseErrorRMS_deg,info.FinalPhase_deg);
    fprintf('  final frequency : %+.3f Hz\n\n',state.FrequencyHz);
end
end

function [err,reliable,metric] = localCallDetector(detector,z,n)
err = NaN;
reliable = false;
metric = NaN;
try
    [err,reliable,metric] = detector(z,n);
catch ME
    if contains(ME.message,'Too many output arguments')
        [err,reliable] = detector(z,n);
    else
        rethrow(ME);
    end
end
err = double(err(1));
reliable = logical(reliable(1));
if isempty(metric)
    metric = NaN;
else
    metric = double(metric(1));
end
end

function [alpha,beta] = localLoopGains(Bn,zeta)
theta = Bn/(zeta + 1/(4*zeta));
den = 1 + 2*zeta*theta + theta^2;
alpha = (4*zeta*theta)/den;
beta = (4*theta^2)/den;
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
if islogical(raw) || isnumeric(raw)
    value = logical(raw(1));
else
    value = any(lower(strtrim(string(raw))) == ["true","1","yes","on"]);
end
end

function value = localText(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = char(string(s.(name)));
end
end

function y = localWrapPi(x)
y = mod(x+pi,2*pi)-pi;
end

function state = localEmptyState()
state = struct('Mode','UNINITIALIZED','Locked',false, ...
    'PhaseRad',0,'FrequencyRadPerSymbol',0,'FrequencyHz',0, ...
    'ErrorStateRad',NaN,'PowerIIR',NaN,'PowerFade',false);
end

function info = localEmptyInfo()
info = struct('Applied',false,'Reason','', ...
    'SymbolRateHz',NaN,'AcquireLoopBandwidth',NaN, ...
    'TrackLoopBandwidth',NaN,'DampingFactor',NaN, ...
    'AcquireAlpha',NaN,'AcquireBeta',NaN, ...
    'TrackAlpha',NaN,'TrackBeta',NaN, ...
    'AcceptedUpdates',0,'AcceptanceRate',NaN, ...
    'ReliableFraction',NaN,'HoldSymbols',0,'HoldFraction',NaN, ...
    'FadeSymbols',0,'FadeFraction',NaN,'HoldEvents',0, ...
    'RecoverEvents',0,'LockTransitions',0,'Reacquisitions',0, ...
    'CycleSlipRejects',0,'PhaseErrorRMS_deg',NaN, ...
    'MeanAbsPhaseError_deg',NaN,'FinalFrequencyHz',NaN, ...
    'FinalPhase_deg',NaN,'FinalMode','UNINITIALIZED','Locked',false, ...
    'AcceptedMask',false(0,1),'ReliableMask',false(0,1), ...
    'HoldMask',false(0,1),'FadeMask',false(0,1), ...
    'PhaseErrorRad',zeros(0,1),'DetectorMetric',zeros(0,1), ...
    'FrequencyTraceHz',zeros(0,1),'PhaseTraceRad',zeros(0,1));
end
