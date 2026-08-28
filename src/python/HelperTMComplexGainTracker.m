function [yOut,state,info] = HelperTMComplexGainTracker(x,referenceConstellation,options)
%HELPERTMCOMPLEXGAINTRACKER Gated one-tap DD complex-gain equalizer.
%
%   [Y,STATE,INFO] = HelperTMComplexGainTracker(X,REF,OPTIONS)
%
% X and Y are one-sample/symbol complex streams.  REF is the exact project
% constellation used by the demapper.  The helper estimates the scalar
% channel in
%
%       x(k) = h(k)d(k) + n(k)
%
% from reliable nearest-constellation decisions and applies a regularized
% inverse.  During a deep fade or a run of unreliable decisions, coefficient
% updates are held; the last reliable estimate is retained.  On fade exit,
% only the magnitude is re-seeded from the decision-free power estimate so a
% stale amplitude estimate cannot prevent decision-directed recovery.
%
% This is deliberately a separate one-tap mode.  It is not CMA/RDE and it
% does not pretend to solve a multipath channel.  The interface is shared by
% APSK and QAM so the validated block can later be reused by the main TM
% receiver without changing its demapper/FEC boundary.
%
% Important OPTIONS (defaults)
%   StepSize                    0.02
%   Regularization             1e-3
%   MaxInverseGainDB           18
%   DecisionGate               0.45*minimum constellation distance
%   DecisionMarginMin          0.10
%   HoldEnterBadSymbols        4
%   RecoverGoodSymbols         8
%   EnableFadeHold             true
%   FadePowerTauSymbols        32
%   FadeReferenceTauSymbols    4096
%   FadeEnterDB                -8
%   FadeExitDB                 -5
%   InitialGainMagnitude       1
%   PowerReference             1
%   NormalizeInputPower        false
%   TrackMagnitude             true
%   TrackPhase                 true
%   MagnitudeEstimationMode    'decision' ('power' uses filtered envelope)
%   UpdatePowerReference       true
%   ExternalHoldMask          [] (shared receiver reliability mask)
%   Debug                      false

if nargin < 2
    referenceConstellation = [];
end
if nargin < 3 || isempty(options)
    options = struct();
end

x = complex(x(:));
ref = complex(referenceConstellation(:));
if isempty(x)
    yOut = x;
    state = localEmptyState();
    info = localEmptyInfo();
    info.Reason = 'empty input';
    return;
end
if isempty(ref) || any(~isfinite(ref))
    error('HelperTMComplexGainTracker:InvalidReference', ...
        'referenceConstellation must contain finite complex symbols.');
end
if any(~isfinite(real(x))) || any(~isfinite(imag(x)))
    error('HelperTMComplexGainTracker:InvalidInput', ...
        'Input contains NaN or Inf.');
end

ref = ref/sqrt(mean(abs(ref).^2)+eps);
refPower = mean(abs(ref).^2);
dmin = localMinimumDistance(ref);

mu = localNumber(options,'StepSize',0.02);
lambda = localNumber(options,'Regularization',1e-3);
maxInverseGainDB = localNumber(options,'MaxInverseGainDB',18);
decisionGate = localNumber(options,'DecisionGate',NaN);
if ~isfinite(decisionGate) || decisionGate <= 0
    decisionGate = 0.45*dmin;
end
marginMin = min(max(localNumber(options,'DecisionMarginMin',0.10),0),0.95);
holdEnterBad = max(1,round(localNumber(options,'HoldEnterBadSymbols',4)));
recoverGood = max(1,round(localNumber(options,'RecoverGoodSymbols',8)));
enableFadeHold = localLogical(options,'EnableFadeHold',true);
fadeTau = max(2,localNumber(options,'FadePowerTauSymbols',32));
referenceTau = max(fadeTau,localNumber(options,'FadeReferenceTauSymbols',4096));
fadeEnterDB = localNumber(options,'FadeEnterDB',-8);
fadeExitDB = localNumber(options,'FadeExitDB',-5);
normalizeInput = localLogical(options,'NormalizeInputPower',false);
trackMagnitude = localLogical(options,'TrackMagnitude',true);
trackPhase = localLogical(options,'TrackPhase',true);
magnitudeMode = lower(strtrim(string(localText( ...
    options,'MagnitudeEstimationMode','decision'))));
if ~any(magnitudeMode == ["decision","power"])
    error('HelperTMComplexGainTracker:InvalidMagnitudeMode', ...
        'MagnitudeEstimationMode must be decision or power.');
end
updatePowerReference = localLogical(options,'UpdatePowerReference',true);
debugEnabled = localLogical(options,'Debug',false);
[externalHoldMask,externalHoldProvided] = ...
    localExternalHoldMask(options,numel(x));

if ~isscalar(mu) || ~isfinite(mu) || mu <= 0 || mu > 1
    error('HelperTMComplexGainTracker:InvalidStep', ...
        'StepSize must be in (0,1].');
end
if ~isscalar(lambda) || ~isfinite(lambda) || lambda < 0
    error('HelperTMComplexGainTracker:InvalidRegularization', ...
        'Regularization must be a finite nonnegative scalar.');
end
if fadeExitDB <= fadeEnterDB
    error('HelperTMComplexGainTracker:InvalidFadeHysteresis', ...
        'FadeExitDB must be greater than FadeEnterDB.');
end

inputPower = mean(abs(x).^2)+eps;
if normalizeInput
    xWork = x*sqrt(refPower/inputPower);
else
    xWork = x;
end

initCount = min(numel(xWork),max(32,round(referenceTau/8)));
initialPower = median(abs(xWork(1:initCount)).^2)+eps;
initialMagnitude = max(eps,localNumber(options,'InitialGainMagnitude',1));

hHat = complex(initialMagnitude,0);
powerIIR = initialPower;
powerReference = max(eps,localNumber(options,'PowerReference',refPower));
fastAlpha = 1-exp(-1/fadeTau);
slowAlpha = 1-exp(-1/referenceTau);
fadeEnterRatio = 10^(fadeEnterDB/10);
fadeExitRatio = 10^(fadeExitDB/10);
maxInverseGain = 10^(maxInverseGainDB/20);

yOut = complex(zeros(size(xWork)));
hTrace = complex(zeros(size(xWork)));
inverseGainTrace = zeros(size(xWork));
accepted = false(size(xWork));
holdMask = false(size(xWork));
fadeMask = false(size(xWork));
distanceTrace = NaN(size(xWork));
marginTrace = NaN(size(xWork));

mode = "TRACK";
inFade = false;
badCount = 0;
goodCount = 0;
holdEvents = 0;
recoverEvents = 0;
coefficientUpdates = 0;

for k = 1:numel(xWork)
    powerIIR = (1-fastAlpha)*powerIIR + fastAlpha*abs(xWork(k))^2;
    powerRatio = powerIIR/max(powerReference,eps);
    wasInFade = inFade;
    if enableFadeHold
        if ~inFade && powerRatio < fadeEnterRatio
            inFade = true;
        elseif inFade && powerRatio > fadeExitRatio
            inFade = false;
        end
    else
        inFade = false;
    end
    % A shared pre-normalization detector is authoritative.  Local power or
    % decision confidence may add protection, but cannot reopen updates
    % while the common receiver state is HOLD/RECOVER.
    inFade = inFade || externalHoldMask(k);
    fadeMask(k) = inFade;

    % For a scalar time-varying channel, a filtered envelope estimate is
    % decision-free and remains usable when APSK points temporarily cross
    % ring decision boundaries.  This mode is intentionally opt-in because
    % the historical DD estimate is still preferable for multipath or an
    % unknown absolute-power reference.
    % HOLD must freeze every adaptive coefficient owner.  Previously the
    % power-mode branch continued replacing |hHat| inside a fade even though
    % the DD state machine reported HOLD.  That made the inverse follow the
    % noise floor and could apply tens of dB of meaningless gain.
    if magnitudeMode == "power" && trackMagnitude && ~inFade
        powerMagnitude = sqrt(max(powerIIR,eps)/refPower);
        hHat = powerMagnitude*exp(1j*angle(hHat));
    end

    % A fade exit gets a decision-free magnitude re-seed.  The phase of the
    % last reliable channel estimate is preserved.
    if wasInFade && ~inFade
        reseedMagnitude = sqrt(max(powerIIR,eps)/refPower);
        hHat = reseedMagnitude*exp(1j*angle(hHat));
    end

    inverseCoeff = conj(hHat)/(abs(hHat)^2+lambda);
    if abs(inverseCoeff) > maxInverseGain
        inverseCoeff = maxInverseGain*exp(1j*angle(inverseCoeff));
    end
    z = inverseCoeff*xWork(k);
    yOut(k) = z;

    [dHat,d1,d2] = localNearestTwo(z,ref);
    margin = max(0,(d2-d1)/(d2+eps));
    reliable = d1 <= decisionGate && margin >= marginMin && ~inFade;
    distanceTrace(k) = d1;
    marginTrace(k) = margin;

    switch mode
        case "TRACK"
            if reliable
                accepted(k) = true;
                badCount = 0;
                goodCount = min(goodCount+1,recoverGood);

                hObservation = xWork(k)*conj(dHat)/(abs(dHat)^2+eps);
                if magnitudeMode == "power"
                    hObservation = abs(hHat)*exp(1j*angle(hObservation));
                elseif ~trackMagnitude
                    hObservation = abs(hHat)*exp(1j*angle(hObservation));
                end
                if ~trackPhase
                    hObservation = abs(hObservation)*exp(1j*angle(hHat));
                end
                hHat = (1-mu)*hHat + mu*hObservation;
                coefficientUpdates = coefficientUpdates+1;
            else
                badCount = badCount+1;
                goodCount = 0;
                if badCount >= holdEnterBad || inFade
                    mode = "HOLD";
                    holdEvents = holdEvents+1;
                end
            end

        case "HOLD"
            holdMask(k) = true;
            if reliable
                goodCount = goodCount+1;
            else
                goodCount = 0;
            end
            if goodCount >= recoverGood
                mode = "TRACK";
                recoverEvents = recoverEvents+1;
                badCount = 0;
                goodCount = 0;
            end
    end

    % The slow reference follows only reliable, non-faded operation.
    if updatePowerReference && reliable && ~inFade
        powerReference = (1-slowAlpha)*powerReference + ...
            slowAlpha*abs(xWork(k))^2;
    end
    hTrace(k) = hHat;
    inverseGainTrace(k) = abs(inverseCoeff);
end

info = localEmptyInfo();
info.Applied = true;
info.Reason = 'gated one-tap DD complex-gain tracking with fade hold';
info.InputPower = inputPower;
info.WorkingInputPower = mean(abs(xWork).^2);
info.OutputPower = mean(abs(yOut).^2);
info.ReferenceMinimumDistance = dmin;
info.StepSize = mu;
info.Regularization = lambda;
info.MaxInverseGainDB = maxInverseGainDB;
info.MagnitudeEstimationMode = char(magnitudeMode);
info.UpdatePowerReference = updatePowerReference;
info.DecisionGate = decisionGate;
info.DecisionMarginMin = marginMin;
info.AcceptedDecisions = nnz(accepted);
info.CoefficientUpdates = coefficientUpdates;
info.AcceptanceRate = mean(accepted);
info.HoldSymbols = nnz(holdMask);
info.HoldFraction = mean(holdMask);
info.HoldEvents = holdEvents;
info.RecoverEvents = recoverEvents;
info.FadeSymbols = nnz(fadeMask);
info.FadeFraction = mean(fadeMask);
info.ExternalHoldMaskProvided = externalHoldProvided;
info.ExternalHoldSymbols = nnz(externalHoldMask);
info.ExternalHoldFraction = mean(externalHoldMask);
info.FinalGainMagnitude = abs(hHat);
info.FinalGainMagnitude_dB = 20*log10(max(abs(hHat),eps));
info.FinalGainPhase_deg = rad2deg(angle(hHat));
info.EstimatedGainMin_dB = 20*log10(max(min(abs(hTrace)),eps));
info.EstimatedGainMax_dB = 20*log10(max(max(abs(hTrace)),eps));
info.InverseGainMaxObserved_dB = 20*log10(max(max(inverseGainTrace),eps));
info.MeanDecisionDistance = mean(distanceTrace(isfinite(distanceTrace)));
info.MeanDecisionMargin = mean(marginTrace(isfinite(marginTrace)));

state = struct( ...
    'Mode',char(mode), ...
    'Gain',hHat, ...
    'PowerIIR',powerIIR, ...
    'PowerReference',powerReference, ...
    'PowerFade',inFade, ...
    'BadCounter',badCount, ...
    'GoodCounter',goodCount);

if debugEnabled
    fprintf('\n[TM one-tap complex gain tracker]\n');
    fprintf('  magnitude mode  : %s, update reference=%d\n', ...
        info.MagnitudeEstimationMode,info.UpdatePowerReference);
    fprintf('  applied/update  : %d, %d updates\n',info.Applied,info.CoefficientUpdates);
    fprintf('  DD accept       : %d/%d = %.2f%%, gate=%.5g margin>=%.3f\n', ...
        info.AcceptedDecisions,numel(xWork),100*info.AcceptanceRate, ...
        info.DecisionGate,info.DecisionMarginMin);
    fprintf('  HOLD/fade       : %d/%d symbols (%.2f/%.2f%%), events=%d recoveries=%d\n', ...
        info.HoldSymbols,info.FadeSymbols,100*info.HoldFraction, ...
        100*info.FadeFraction,info.HoldEvents,info.RecoverEvents);
    fprintf('  shared HOLD     : provided=%d, symbols=%d (%.2f%%)\n', ...
        info.ExternalHoldMaskProvided,info.ExternalHoldSymbols, ...
        100*info.ExternalHoldFraction);
    fprintf('  h final         : %+.3f dB, %+.3f deg; range=[%+.3f,%+.3f] dB\n', ...
        info.FinalGainMagnitude_dB,info.FinalGainPhase_deg, ...
        info.EstimatedGainMin_dB,info.EstimatedGainMax_dB);
    fprintf('  inverse max     : %+.3f dB (configured cap %+.3f dB)\n', ...
        info.InverseGainMaxObserved_dB,info.MaxInverseGainDB);
    fprintf('  power in/out    : %.5g / %.5g\n\n', ...
        info.WorkingInputPower,info.OutputPower);
end
end

function [dHat,d1,d2] = localNearestTwo(z,ref)
dist = abs(z-ref);
[s,idx] = sort(dist,'ascend');
dHat = ref(idx(1));
d1 = s(1);
if numel(s) >= 2
    d2 = s(2);
else
    d2 = inf;
end
end

function dmin = localMinimumDistance(ref)
dmin = inf;
for k = 1:numel(ref)
    d = abs(ref(k)-ref);
    d(k) = inf;
    dmin = min(dmin,min(d));
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

function value = localText(s,name,defaultValue)
value = string(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = string(s.(name));
    value = value(1);
end
end

function [mask,provided] = localExternalHoldMask(options,n)
mask = false(n,1);
provided = isstruct(options) && isfield(options,'ExternalHoldMask') && ...
    ~isempty(options.ExternalHoldMask);
if ~provided
    return;
end
raw = logical(options.ExternalHoldMask(:));
if numel(raw) ~= n
    error('HelperTMComplexGainTracker:ExternalHoldMaskLength', ...
        'ExternalHoldMask has %d symbols; expected %d.',numel(raw),n);
end
mask = raw;
end

function state = localEmptyState()
state = struct('Mode','UNINITIALIZED','Gain',complex(1,0), ...
    'PowerIIR',NaN,'PowerReference',NaN,'PowerFade',false, ...
    'BadCounter',0,'GoodCounter',0);
end

function info = localEmptyInfo()
info = struct( ...
    'Applied',false,'Reason','', ...
    'InputPower',NaN,'WorkingInputPower',NaN,'OutputPower',NaN, ...
    'ReferenceMinimumDistance',NaN, ...
    'StepSize',NaN,'Regularization',NaN,'MaxInverseGainDB',NaN, ...
    'MagnitudeEstimationMode','decision','UpdatePowerReference',true, ...
    'DecisionGate',NaN,'DecisionMarginMin',NaN, ...
    'AcceptedDecisions',0,'CoefficientUpdates',0,'AcceptanceRate',NaN, ...
    'HoldSymbols',0,'HoldFraction',NaN,'HoldEvents',0,'RecoverEvents',0, ...
    'FadeSymbols',0,'FadeFraction',NaN, ...
    'ExternalHoldMaskProvided',false,'ExternalHoldSymbols',0, ...
    'ExternalHoldFraction',0, ...
    'FinalGainMagnitude',NaN,'FinalGainMagnitude_dB',NaN, ...
    'FinalGainPhase_deg',NaN,'EstimatedGainMin_dB',NaN, ...
    'EstimatedGainMax_dB',NaN,'InverseGainMaxObserved_dB',NaN, ...
    'MeanDecisionDistance',NaN,'MeanDecisionMargin',NaN);
end
