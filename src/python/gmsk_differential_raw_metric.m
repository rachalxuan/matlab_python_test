function [rawMetric, info] = gmsk_differential_raw_metric(inputWaveform, cfg)
%GMSK_DIFFERENTIAL_RAW_METRIC Phase-invariant GMSK precoder metric.
%
% This is an open-loop alternative to carrier-phase tracking.  It removes
% a constant carrier phase by differential multiplication and combines all
% samples in one symbol.  Consequently a bad channel sample can damage only
% the local metric; there is no phase/frequency state that can carry the
% error into later symbols.
%
% Output convention is the raw-precoder convention used by
% gmsk_frame_reset_demodulate: positive -> raw bit 0, negative -> raw bit 1.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end

x = complex(inputWaveform(:));
sps = max(1,round(double(localField(cfg,'SamplesPerSymbol',8))));
outputScale = max(eps,double(localField(cfg,'OutputScale',5)));

info = struct( ...
    'Mode','one-symbol', ...
    'SamplesPerSymbol',sps, ...
    'InputSamples',numel(x), ...
    'TimingPhaseSamples',0, ...
    'TimingScore',NaN, ...
    'OutputSymbols',0, ...
    'MetricScale',NaN, ...
    'NearZeroMetrics',0);

if numel(x) < 2*sps
    rawMetric = zeros(0,1);
    return;
end

differential = x(1+sps:end).*conj(x(1:end-sps));

% A complete-symbol integral is insensitive to an integer sample choice in
% the ideal link, but channel transients and fractional delay break that
% equality.  Select the phase with the clearest binary separation.  This is
% feed-forward and uses no transmitted data or true H.
bestMetric = zeros(0,1);
bestScore = -Inf;
bestPhase = 0;
for phase = 0:sps-1
    first = phase+1;
    nSymbols = floor((numel(differential)-phase)/sps);
    if nSymbols < 1
        continue;
    end
    block = reshape(differential(first:first+nSymbols*sps-1),sps,nSymbols);
    candidate = sum(imag(block),1).';
    rmsValue = sqrt(mean(candidate.^2)+eps);
    score = median(abs(candidate))/rmsValue;
    if isfinite(score) && score > bestScore
        bestScore = score;
        bestPhase = phase;
        bestMetric = candidate;
    end
end

if isempty(bestMetric)
    rawMetric = zeros(0,1);
    return;
end

metricScale = median(abs(bestMetric));
if ~isfinite(metricScale) || metricScale <= eps
    metricScale = sqrt(mean(bestMetric.^2)+eps);
end

% The production transmitter maps bipolar precoder symbol p to the frame
% reset raw convention as -p.  The discriminator metric has the sign of p.
rawMetric = -outputScale*double(bestMetric)/max(metricScale,eps);
rawMetric = max(min(rawMetric,20),-20);

info.TimingPhaseSamples = bestPhase;
info.TimingScore = bestScore;
info.OutputSymbols = numel(rawMetric);
info.MetricScale = metricScale;
info.NearZeroMetrics = nnz(abs(rawMetric) < 0.25*outputScale);
end

function value = localField(s,name,defaultValue)
if isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
