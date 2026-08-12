function [y, info] = HelperTMFastComplexGainTracker(x, refConst, options, mode)
%HELPERTMFASTCOMPLEXGAINTRACKER Fixed internal envelope/complex-gain tracker.
%
% This helper is intentionally not a user-facing mode.  The ordinary TM
% receiver calls it at two fixed points when the blind adaptive path is
% enabled and an H channel is present:
%   envelope : after the matched filter, before Gardner timing
%   complex  : amplitude/phase tracker for constant-envelope PSK
%   phase    : confidence-gated phase-only tracker for QAM/APSK
%
% The envelope stage is decision free.  The complex stage uses a gated
% nearest-constellation decision and a normalized complex LMS update.  It
% is deliberately conservative: a bad decision is rejected instead of
% letting a deep fade or a cycle slip drive the gain estimate unstable.

if nargin < 4 || isempty(mode)
    mode = 'complex';
end
mode = lower(string(mode));
x = x(:);
if nargin < 2 || isempty(refConst)
    refConst = 1;
end
refConst = complex(refConst(:));

info = localInfo(mode, numel(x));
if isempty(x)
    y = x;
    return;
end

switch mode
    case "envelope"
        [y, info] = localEnvelope(x, refConst, options, info);
    case "complex"
        [y, info] = localComplexGain(x, refConst, options, info);
    case "phase"
        [y, info] = localDecisionDirectedPhase(x, refConst, options, info);
    otherwise
        error('HelperTMFastComplexGainTracker:InvalidMode', ...
            'mode must be ''envelope'', ''complex'', or ''phase''.');
end

function [y, info] = localDecisionDirectedPhase(x, refConst, options, info)
% Phase-only tracking avoids the false-radius lock that a scalar complex LMS
% can enter on QAM/APSK.  Updates are accepted only well inside the nearest
% neighbour boundary; rejected symbols use holdover and cannot move the loop.
n = numel(x);
mu = localNumber(options, 'FastPhaseStep', 0.08);
if ~isfinite(mu) || mu <= 0, mu = 0.08; end
mu = min(mu, 0.5);
frequencyMu = localNumber(options, 'FastPhaseFrequencyStep', 0.002);
if ~isfinite(frequencyMu) || frequencyMu < 0, frequencyMu = 0.002; end
frequencyMu = min(frequencyMu, 0.05);
maxFrequency = localNumber(options, ...
    'FastPhaseMaxFrequencyRadPerSymbol', 0.05);
if ~isfinite(maxFrequency) || maxFrequency <= 0, maxFrequency = 0.05; end
gateScale = localNumber(options, 'FastPhaseDecisionGate', 0.35);
if ~isfinite(gateScale) || gateScale <= 0, gateScale = 0.35; end
gate = max(gateScale*localMinimumDistance(refConst), 1e-3);

phaseState = 0;
frequencyState = 0;
y = zeros(size(x));
accepted = false(n,1);
errors = NaN(n,1);
gainTrace = complex(zeros(n,1));
for k = 1:n
    % Second-order holdover predicts through low-confidence fade samples.
    % A first-order loop freezes there and can cross the next 90-degree
    % equilibrium before decisions become reliable again.
    phaseState = phaseState + frequencyState;
    z = x(k)*exp(-1j*phaseState);
    [d, distance] = localNearest(z, refConst);
    if isfinite(distance) && distance <= gate && ...
            isfinite(real(z)) && isfinite(imag(z)) && abs(z) > 1e-10
        phaseError = angle(z*conj(d));
        if isfinite(phaseError)
            phaseState = phaseState + mu*phaseError;
            frequencyState = frequencyState + frequencyMu*phaseError;
            frequencyState = min(max(frequencyState, ...
                -maxFrequency), maxFrequency);
            accepted(k) = true;
            errors(k) = abs(d-z)^2;
            z = x(k)*exp(-1j*phaseState);
        end
    end
    y(k) = z;
    gainTrace(k) = exp(-1j*phaseState);
end

info.Applied = true;
info.FinalGain = gainTrace(end);
info.FinalMagnitude = 1;
info.FinalMagnitude_dB = 0;
info.FinalPhase_deg = angle(info.FinalGain)*180/pi;
info.AcceptedDecisions = nnz(accepted);
info.RejectedDecisions = n-info.AcceptedDecisions;
info.AcceptanceRate = info.AcceptedDecisions/max(n,1);
info.DecisionGate = gate;
info.DDMSE = localFiniteMean(errors);
info.GainTrace = gainTrace;
info.GainMin_dB = 0;
info.GainMax_dB = 0;
end
end

function [y, info] = localEnvelope(x, refConst, options, info)
% Causal power tracking.  By default the target is estimated from the
% leading samples and then held.  The ordinary-TM H front end supplies an
% explicit unit-power target because the downstream timing/carrier loop
% detector gains are calibrated for a normalized constellation.  This is
% still receiver observable: only the received power estimate is used to
% calculate the gain.
n = numel(x);
sampleRate = localNumber(options, 'FastEnvelopeSampleRateHz', NaN);
if ~isfinite(sampleRate) || sampleRate <= 0
    sampleRate = 1;
end
tauSymbols = localNumber(options, 'FastEnvelopeTauSymbols', 16);
if ~isfinite(tauSymbols) || tauSymbols <= 0
    tauSymbols = 16;
end
sps = max(1, localNumber(options, 'FastEnvelopeSamplesPerSymbol', 2));
alpha = exp(-1/max(tauSymbols*sps,1));

nInit = min(n, max(32, round(32*sps)));
initialPower = mean(abs(x(1:nInit)).^2);
if ~isfinite(initialPower) || initialPower <= 0
    initialPower = mean(abs(refConst).^2);
end
initialPower = max(initialPower, 1e-12);
targetPower = localNumber(options, 'FastEnvelopeTargetPower', initialPower);
if ~isfinite(targetPower) || targetPower <= 0
    targetPower = initialPower;
end
powerState = initialPower;
minGain = 10^(localNumber(options, 'FastEnvelopeMinGainDB', -20)/20);
maxGain = 10^(localNumber(options, 'FastEnvelopeMaxGainDB', 20)/20);
if ~(isfinite(minGain) && minGain > 0), minGain = 0.1; end
if ~(isfinite(maxGain) && maxGain >= minGain), maxGain = 10; end

y = zeros(size(x));
gain = 1;
gains = zeros(n,1);
for k = 1:n
    p = abs(x(k)).^2;
    if isfinite(p)
        powerState = alpha*powerState + (1-alpha)*max(p,0);
    end
    gain = sqrt(targetPower/max(powerState, 1e-12));
    gain = min(max(gain, minGain), maxGain);
    y(k) = gain*x(k);
    gains(k) = gain;
end

info.Applied = true;
info.TargetPower = targetPower;
info.InitialPower = initialPower;
info.FinalPower = powerState;
info.FinalMagnitude = gains(end);
info.FinalMagnitude_dB = 20*log10(max(gains(end),eps));
info.AcceptanceRate = 1;
info.SamplesPerSymbol = sps;
info.TauSymbols = tauSymbols;
info.SampleRateHz = sampleRate;
info.GainMin_dB = 20*log10(max(min(gains),eps));
info.GainMax_dB = 20*log10(max(max(gains),eps));
end

function [y, info] = localComplexGain(x, refConst, options, info)
% Constant-envelope PSK has a data-independent m-th-power phase error.
% Use it for the fixed internal PSK path; nearest-point decisions are only
% used for multi-amplitude constellations where m-th-power cancellation is
% not valid.
if localIsConstantEnvelope(refConst)
    [y, info] = localConstantEnvelopeGain(x, refConst, options, info);
    return;
end

n = numel(x);
mu = localNumber(options, 'FastComplexGainStep', 0.05);
if ~isfinite(mu) || mu <= 0, mu = 0.05; end
mu = min(mu, 0.5);
gateScale = localNumber(options, 'FastComplexGainDecisionGate', 0.60);
if ~isfinite(gateScale) || gateScale <= 0, gateScale = 0.60; end
maxGainDB = localNumber(options, 'FastComplexGainMaxMagnitudeDB', 24);
if ~isfinite(maxGainDB) || maxGainDB <= 0, maxGainDB = 24; end
maxGain = 10^(maxGainDB/20);
minDistance = localMinimumDistance(refConst);
if ~isfinite(minDistance) || minDistance <= 0
    minDistance = 1;
end
gate = max(gateScale*minDistance, 1e-3);

g = complex(1,0);
y = zeros(size(x));
accepted = false(n,1);
errors = zeros(n,1);
gainTrace = zeros(n,1);
for k = 1:n
    z = g*x(k);
    y(k) = z;
    [d, distance] = localNearest(z, refConst);
    if isfinite(distance) && distance <= gate && isfinite(x(k))
        e = d-z;
        denom = abs(x(k)).^2 + 1e-8;
        gCandidate = g + mu*conj(x(k))*e/denom;
        if isfinite(real(gCandidate)) && isfinite(imag(gCandidate)) && ...
                abs(gCandidate) >= 1/maxGain && abs(gCandidate) <= maxGain
            g = gCandidate;
            accepted(k) = true;
            errors(k) = abs(e).^2;
            y(k) = g*x(k);
        end
    end
    gainTrace(k) = g;
end

info.Applied = true;
info.FinalGain = g;
info.FinalMagnitude = abs(g);
info.FinalMagnitude_dB = 20*log10(max(abs(g),eps));
info.FinalPhase_deg = angle(g)*180/pi;
info.AcceptedDecisions = nnz(accepted);
info.RejectedDecisions = n-info.AcceptedDecisions;
info.AcceptanceRate = nnz(accepted)/max(n,1);
info.DecisionGate = gate;
info.DDMSE = localFiniteMean(errors);
info.GainTrace = gainTrace;
info.GainMin_dB = 20*log10(max(min(abs(gainTrace)),eps));
info.GainMax_dB = 20*log10(max(max(abs(gainTrace)),eps));
end

function [y, info] = localConstantEnvelopeGain(x, refConst, options, info)
n = numel(x);
m = localConstellationOrder(refConst);
phaseMu = localNumber(options,'FastComplexGainPhaseStep',0.08);
if ~isfinite(phaseMu) || phaseMu <= 0, phaseMu = 0.08; end
phaseMu = min(phaseMu,0.5);
powerMu = localNumber(options,'FastComplexGainPowerStep',0.04);
if ~isfinite(powerMu) || powerMu <= 0, powerMu = 0.04; end
powerMu = min(powerMu,0.5);
maxGainDB = localNumber(options,'FastComplexGainMaxMagnitudeDB',24);
if ~isfinite(maxGainDB) || maxGainDB <= 0, maxGainDB = 24; end
maxGain = 10^(maxGainDB/20);
minGain = 1/maxGain;
targetPower = mean(abs(refConst).^2);
if ~isfinite(targetPower) || targetPower <= 0, targetPower = 1; end
initialPower = mean(abs(x(1:min(n,max(32,4*m))).^2));
if ~isfinite(initialPower) || initialPower <= 0, initialPower = targetPower; end
powerState = initialPower;
phaseState = 0;
phaseTarget = refConst(1)^m;

y = zeros(size(x));
accepted = false(n,1);
phaseErrors = zeros(n,1);
gainTrace = zeros(n,1);
for k = 1:n
    p = abs(x(k)).^2;
    if isfinite(p)
        powerState = (1-powerMu)*powerState + powerMu*max(p,0);
    end
    magnitude = sqrt(targetPower/max(powerState,1e-12));
    magnitude = min(max(magnitude,minGain),maxGain);
    z = magnitude*x(k)*exp(-1j*phaseState);
    if isfinite(real(z)) && isfinite(imag(z)) && abs(z) > 1e-8
        phaseError = angle((z^m)*conj(phaseTarget))/m;
        if isfinite(phaseError)
            phaseState = phaseState + phaseMu*phaseError;
            accepted(k) = true;
            phaseErrors(k) = phaseError;
        end
    end
    g = magnitude*exp(-1j*phaseState);
    y(k) = g*x(k);
    gainTrace(k) = g;
end

info.Applied = true;
info.FinalGain = gainTrace(end);
info.FinalMagnitude = abs(gainTrace(end));
info.FinalMagnitude_dB = 20*log10(max(info.FinalMagnitude,eps));
info.FinalPhase_deg = angle(info.FinalGain)*180/pi;
info.AcceptedDecisions = nnz(accepted);
info.RejectedDecisions = n-info.AcceptedDecisions;
info.AcceptanceRate = nnz(accepted)/max(n,1);
info.DecisionGate = 0;
info.DDMSE = localFiniteMean(phaseErrors.^2);
info.GainTrace = gainTrace;
info.GainMin_dB = 20*log10(max(min(abs(gainTrace)),eps));
info.GainMax_dB = 20*log10(max(max(abs(gainTrace)),eps));
end

function tf = localIsConstantEnvelope(refConst)
p = abs(refConst).^2;
tf = numel(refConst) >= 2 && all(isfinite(p)) && ...
    max(p)-min(p) <= max(1e-8,1e-3*mean(p));
end

function m = localConstellationOrder(refConst)
n = numel(refConst);
if n <= 2
    m = 2;
elseif n <= 4
    m = 4;
elseif n <= 8
    m = 8;
else
    m = n;
end
end

function [d, distance] = localNearest(z, refConst)
[distance, idx] = min(abs(z-refConst));
d = refConst(idx);
end

function d = localMinimumDistance(refConst)
if numel(refConst) < 2
    d = 1;
    return;
end
v = abs(refConst-refConst.');
v(v == 0) = inf;
d = min(v(:));
if ~isfinite(d), d = 1; end
end

function v = localNumber(options, name, defaultValue)
v = defaultValue;
if nargin >= 1 && isstruct(options) && isfield(options,name) && ...
        ~isempty(options.(name))
    raw = options.(name);
    if isnumeric(raw) || islogical(raw)
        raw = raw(1);
        if isfinite(double(raw)), v = double(raw); end
    end
end
end

function m = localFiniteMean(x)
x = x(isfinite(x));
if isempty(x), m = NaN; else, m = mean(x); end
end

function info = localInfo(mode, n)
info = struct( ...
    'Mode',char(mode), ...
    'Applied',false, ...
    'NumSamples',n, ...
    'TargetPower',NaN, ...
    'InitialPower',NaN, ...
    'FinalPower',NaN, ...
    'FinalGain',complex(1,0), ...
    'FinalMagnitude',1, ...
    'FinalMagnitude_dB',0, ...
    'FinalPhase_deg',0, ...
    'AcceptedDecisions',0, ...
    'RejectedDecisions',0, ...
    'AcceptanceRate',NaN, ...
    'DecisionGate',NaN, ...
    'DDMSE',NaN, ...
    'GainTrace',zeros(0,1), ...
    'GainMin_dB',NaN, ...
    'GainMax_dB',NaN, ...
    'SamplesPerSymbol',NaN, ...
    'TauSymbols',NaN, ...
    'SampleRateHz',NaN);
end
