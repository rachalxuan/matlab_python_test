function [yOut,state,info] = HelperTMAPSKRingNormalizer(x,referenceConstellation,options)
%HELPERTMAPSKRINGNORMALIZER Pilotless scalar RDE amplitude tracker for APSK.
%
%   [Y,STATE,INFO] = HelperTMAPSKRingNormalizer(X,REF,OPTIONS)
%
% The magnitude-only tracker runs after feed-forward carrier acquisition and
% before the gated DD phase loop.  It uses only the known APSK ring radii;
% symbol angle, transmitted bits, ASM and pilots are not used.  This makes
% it suitable for stabilizing the nearest-point phase detector under a
% one-tap time-varying fading channel.
% EstimatorMode='power-window' (default) uses the known unit average APSK
% power over a causal window and has no decision-error propagation.  The
% explicit 'rde' mode below remains available for controlled A/B tests.

if nargin < 3 || isempty(options)
    options = struct();
end
x = complex(x(:));
ref = complex(referenceConstellation(:));
if isempty(x)
    yOut = x;
    state = struct('Mode','UNINITIALIZED','Amplitude',1);
    info = localEmptyInfo();
    info.Reason = 'empty input';
    return;
end
if isempty(ref)
    error('HelperTMAPSKRingNormalizer:InvalidReference', ...
        'referenceConstellation must not be empty.');
end
ref = ref/sqrt(mean(abs(ref).^2)+eps);
radii = localUniqueRadii(abs(ref));
if numel(radii) < 2
    error('HelperTMAPSKRingNormalizer:InvalidRings', ...
        'At least two distinct APSK ring radii are required.');
end

mu = localNumber(options,'StepSize',0.04);
estimatorMode = lower(strtrim(string(localText( ...
    options,'EstimatorMode','power-window'))));
gate = localNumber(options,'RingGate',NaN);
minRingSpacing = min(diff(radii));
if ~isfinite(gate) || gate <= 0
    gate = 0.45*minRingSpacing;
end
marginMin = min(max(localNumber(options,'RingMarginMin',0.05),0),0.95);
maxInverseGainDB = localNumber(options,'MaxInverseGainDB',18);
regularization = localNumber(options,'Regularization',1e-3);
fadeTau = max(2,localNumber(options,'FadePowerTauSymbols',32));
fadeEnterDB = localNumber(options,'FadeEnterDB',-8);
fadeExitDB = localNumber(options,'FadeExitDB',-5);
recoverGood = max(1,round(localNumber(options,'RecoverGoodSymbols',1)));
enableFadeHold = localLogical(options,'EnableFadeHold',true);
debugEnabled = localLogical(options,'Debug',false);
[externalHoldMask,externalHoldProvided] = ...
    localExternalHoldMask(options,numel(x));

if mu <= 0 || mu > 1 || ~isfinite(mu)
    error('HelperTMAPSKRingNormalizer:InvalidStep','StepSize must be in (0,1].');
end
if fadeExitDB <= fadeEnterDB
    error('HelperTMAPSKRingNormalizer:InvalidFadeHysteresis', ...
        'FadeExitDB must be greater than FadeEnterDB.');
end

powerReference = max(eps,localNumber(options,'PowerReference',1));
amplitude = max(eps,localNumber(options,'InitialAmplitude',1));
initCount = min(numel(x),max(32,round(fadeTau)));
powerIIR = median(abs(x(1:initCount)).^2)+eps;
powerAlpha = 1-exp(-1/fadeTau);
fadeEnterRatio = 10^(fadeEnterDB/10);
fadeExitRatio = 10^(fadeExitDB/10);
maxInverseGain = 10^(maxInverseGainDB/20);

if any(estimatorMode == ["power-window","window","envelope"])
    windowSymbols = max(4,round(localNumber(options,'PowerWindowSymbols',64)));
    p = abs(x).^2;
    cs = [0; cumsum(p)];
    localPower = zeros(size(p));
    for k = 1:numel(p)
        first = max(1,k-windowSymbols+1);
        localPower(k) = (cs(k+1)-cs(first))/max(1,k-first+1);
    end
    amplitudeTrace = sqrt(max(localPower,eps)/powerReference);
    inverseGainTrace = amplitudeTrace./(amplitudeTrace.^2+regularization);
    inverseGainTrace = min(inverseGainTrace,maxInverseGain);
    for k = 2:numel(inverseGainTrace)
        if externalHoldMask(k)
            inverseGainTrace(k) = inverseGainTrace(k-1);
        end
    end
    yOut = x.*inverseGainTrace;
    fadeMask = localPower/powerReference < fadeEnterRatio | ...
        externalHoldMask;

    info = localEmptyInfo();
    info.Applied = true;
    info.Reason = 'pilotless causal power-window APSK amplitude normalization';
    info.EstimatorMode = 'power-window';
    info.Radii = radii(:);
    info.MinRingSpacing = minRingSpacing;
    info.StepSize = NaN;
    info.RingGate = gate;
    info.RingMarginMin = marginMin;
    info.AcceptedUpdates = numel(x);
    info.AcceptanceRate = 1;
    info.HoldSymbols = nnz(fadeMask);
    info.HoldFraction = mean(fadeMask);
    info.FadeSymbols = nnz(fadeMask);
    info.FadeFraction = mean(fadeMask);
    info.HoldEvents = nnz(diff([false; fadeMask]) == 1);
    info.RecoverEvents = nnz(diff([fadeMask; false]) == -1);
    info.ExternalHoldMaskProvided = externalHoldProvided;
    info.ExternalHoldSymbols = nnz(externalHoldMask);
    info.ExternalHoldFraction = mean(externalHoldMask);
    info.FinalAmplitude = amplitudeTrace(end);
    info.FinalAmplitude_dB = 20*log10(max(amplitudeTrace(end),eps));
    info.AmplitudeMin_dB = 20*log10(max(min(amplitudeTrace),eps));
    info.AmplitudeMax_dB = 20*log10(max(max(amplitudeTrace),eps));
    info.OutputPower = mean(abs(yOut).^2);
    state = struct('Mode','TRACK','Amplitude',amplitudeTrace(end), ...
        'PowerIIR',localPower(end),'PowerFade',fadeMask(end), ...
        'GoodCounter',0);
    if debugEnabled
        fprintf('\n[TM APSK power-window normalizer]\n');
        fprintf('  window/fade      : %d symbols / %.2f%%\n', ...
            windowSymbols,100*info.FadeFraction);
        fprintf('  amplitude        : final=%+.3f dB range=[%+.3f,%+.3f] dB\n', ...
            info.FinalAmplitude_dB,info.AmplitudeMin_dB,info.AmplitudeMax_dB);
        fprintf('  output power     : %.5g\n\n',info.OutputPower);
    end
    return;
elseif estimatorMode ~= "rde"
    error('HelperTMAPSKRingNormalizer:InvalidEstimatorMode', ...
        'EstimatorMode must be ''power-window'' or ''rde''.');
end

yOut = complex(zeros(size(x)));
accepted = false(size(x));
fadeMask = false(size(x));
holdMask = false(size(x));
amplitudeTrace = zeros(size(x));
mode = "TRACK";
inFade = false;
goodCount = 0;
holdEvents = 0;
recoverEvents = 0;

for k = 1:numel(x)
    powerIIR = (1-powerAlpha)*powerIIR + powerAlpha*abs(x(k))^2;
    powerRatio = powerIIR/powerReference;
    wasInFade = inFade;
    if enableFadeHold
        if ~inFade && powerRatio < fadeEnterRatio
            inFade = true;
            mode = "HOLD";
            holdEvents = holdEvents+1;
        elseif inFade && powerRatio > fadeExitRatio
            inFade = false;
        end
    else
        inFade = false;
    end
    inFade = inFade || externalHoldMask(k);
    if wasInFade && ~inFade
        amplitude = sqrt(max(powerIIR,eps)/mean(abs(ref).^2));
    end
    fadeMask(k) = inFade;

    inverseGain = amplitude/(amplitude^2+regularization);
    inverseGain = min(inverseGain,maxInverseGain);
    z = x(k)*inverseGain;
    yOut(k) = z;

    radialDistance = abs(abs(z)-radii);
    [sorted,idx] = sort(radialDistance,'ascend');
    rHat = radii(idx(1));
    d1 = sorted(1);
    d2 = sorted(min(2,numel(sorted)));
    margin = max(0,(d2-d1)/(d2+eps));
    reliable = d1 <= gate && margin >= marginMin && ~inFade;

    if mode == "TRACK"
        if reliable
            observation = abs(x(k))/max(rHat,eps);
            amplitude = (1-mu)*amplitude + mu*observation;
            accepted(k) = true;
        end
    else
        holdMask(k) = true;
        if reliable
            goodCount = goodCount+1;
        else
            goodCount = 0;
        end
        if goodCount >= recoverGood
            mode = "TRACK";
            recoverEvents = recoverEvents+1;
            goodCount = 0;
        end
    end
    amplitudeTrace(k) = amplitude;
end

info = localEmptyInfo();
info.Applied = true;
info.Reason = 'pilotless ring-decision amplitude normalization';
info.EstimatorMode = 'rde';
info.Radii = radii(:);
info.MinRingSpacing = minRingSpacing;
info.StepSize = mu;
info.RingGate = gate;
info.RingMarginMin = marginMin;
info.AcceptedUpdates = nnz(accepted);
info.AcceptanceRate = mean(accepted);
info.HoldSymbols = nnz(holdMask);
info.HoldFraction = mean(holdMask);
info.FadeSymbols = nnz(fadeMask);
info.FadeFraction = mean(fadeMask);
info.HoldEvents = holdEvents;
info.RecoverEvents = recoverEvents;
info.ExternalHoldMaskProvided = externalHoldProvided;
info.ExternalHoldSymbols = nnz(externalHoldMask);
info.ExternalHoldFraction = mean(externalHoldMask);
info.FinalAmplitude = amplitude;
info.FinalAmplitude_dB = 20*log10(max(amplitude,eps));
info.AmplitudeMin_dB = 20*log10(max(min(amplitudeTrace),eps));
info.AmplitudeMax_dB = 20*log10(max(max(amplitudeTrace),eps));
info.OutputPower = mean(abs(yOut).^2);

state = struct('Mode',char(mode),'Amplitude',amplitude, ...
    'PowerIIR',powerIIR,'PowerFade',inFade,'GoodCounter',goodCount);

if debugEnabled
    fprintf('\n[TM APSK RDE ring normalizer]\n');
    fprintf('  rings            : %s\n',mat2str(radii.',5));
    fprintf('  update accept    : %d/%d = %.2f%%, gate=%.5g margin>=%.3f\n', ...
        info.AcceptedUpdates,numel(x),100*info.AcceptanceRate,gate,marginMin);
    fprintf('  HOLD/fade        : %d/%d symbols (%.2f/%.2f%%), events=%d recoveries=%d\n', ...
        info.HoldSymbols,info.FadeSymbols,100*info.HoldFraction, ...
        100*info.FadeFraction,holdEvents,recoverEvents);
    fprintf('  amplitude        : final=%+.3f dB range=[%+.3f,%+.3f] dB\n\n', ...
        info.FinalAmplitude_dB,info.AmplitudeMin_dB,info.AmplitudeMax_dB);
end
end

function radii = localUniqueRadii(values)
values = sort(real(values(:)));
radii = values(1);
for k = 2:numel(values)
    if abs(values(k)-radii(end)) > 1e-6*max(1,values(k))
        radii(end+1,1) = values(k); %#ok<AGROW>
    end
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
value = char(string(defaultValue));
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = char(string(s.(name)));
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
    error('HelperTMAPSKRingNormalizer:ExternalHoldMaskLength', ...
        'ExternalHoldMask has %d symbols; expected %d.',numel(raw),n);
end
mask = raw;
end

function info = localEmptyInfo()
info = struct('Applied',false,'Reason','','EstimatorMode','off', ...
    'Radii',zeros(0,1),'MinRingSpacing',NaN, ...
    'StepSize',NaN,'RingGate',NaN,'RingMarginMin',NaN, ...
    'AcceptedUpdates',0,'AcceptanceRate',NaN, ...
    'HoldSymbols',0,'HoldFraction',NaN,'FadeSymbols',0, ...
    'FadeFraction',NaN,'HoldEvents',0,'RecoverEvents',0, ...
    'ExternalHoldMaskProvided',false,'ExternalHoldSymbols',0, ...
    'ExternalHoldFraction',0, ...
    'FinalAmplitude',NaN,'FinalAmplitude_dB',NaN, ...
    'AmplitudeMin_dB',NaN,'AmplitudeMax_dB',NaN,'OutputPower',NaN);
end
