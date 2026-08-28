function [cfoHz,info] = HelperTMAPSKFourthPowerCoarseCFO(x,symbolRateHz,options)
%HELPERTMAPSKFOURTHPOWERCOARSECFO Pilotless APSK coarse-CFO acquisition.
%
%   [CFOHZ,INFO] = HelperTMAPSKFourthPowerCoarseCFO(X,RS,OPTIONS)
%
% X is a one-sample/symbol 16/32APSK stream after timing recovery.  Despite
% the historical function name, the exponent is configurable.  For a
% multi-ring APSK constellation it should be the least common multiple of
% the number of points on each ring (12 for CCSDS 16APSK and 48 for CCSDS
% 32APSK), not simply the four-fold rotational-ambiguity order.  Raising a
% unit-magnitude stream to this order removes the data phase and turns a
% carrier offset into a spectral line at PowerOrder times the CFO.
%
% OPTIONS fields:
%   AcquisitionSymbols = 4096
%   FFTLength          = 65536
%   MaxCFOHz           = 200e3
%   MinConfidenceDB    = 6
%   UseUnitMagnitude   = true
%   PowerOrder         = 4  % caller selects 12/48 for CCSDS APSK
%   RadiusMin          = -Inf
%   RadiusMax          = +Inf  % optional ring partition before x^M
%   MinSelectedSymbols = 64
%   RangeToleranceHz   = NaN   % auto = half one interpolated CFO bin
%
% The estimate is feed-forward and does not use pilots, ASM or transmitted
% bits.  A three-point parabolic interpolation around the FFT peak reduces
% bin quantization error.

if nargin < 3 || isempty(options)
    options = struct();
end

x = complex(x(:));
Rs = double(symbolRateHz);
if isempty(x) || ~isfinite(Rs) || Rs <= 0
    error('HelperTMAPSKFourthPowerCoarseCFO:InvalidInput', ...
        'X must be nonempty and symbolRateHz must be positive.');
end

nUse = min(numel(x),max(64,round(localNumber(options, ...
    'AcquisitionSymbols',4096))));
maxCFOHz = max(0,localNumber(options,'MaxCFOHz',200e3));
minConfidenceDB = localNumber(options,'MinConfidenceDB',6);
useUnitMagnitude = localLogical(options,'UseUnitMagnitude',true);
powerOrder = max(1,round(localNumber(options,'PowerOrder',4)));
radiusMin = localNumber(options,'RadiusMin',-inf);
radiusMax = localNumber(options,'RadiusMax',inf);
minSelectedSymbols = max(8,round(localNumber(options, ...
    'MinSelectedSymbols',64)));

fftLengthRequested = max(1024,round(localNumber(options,'FFTLength',65536)));
nfft = 2^nextpow2(max(fftLengthRequested,nUse));

u = x(1:nUse);
selectionMask = abs(u) >= radiusMin & abs(u) <= radiusMax;
nSelected = nnz(selectionMask);
if useUnitMagnitude
    selectedMagnitude = abs(u(selectionMask));
    if isempty(selectedMagnitude)
        amplitudeFloor = sqrt(eps);
    else
        amplitudeFloor = max(sqrt(eps),1e-3*median(selectedMagnitude));
    end
    u(selectionMask) = u(selectionMask) ./ ...
        max(abs(u(selectionMask)),amplitudeFloor);
else
    if nSelected > 0
        u(selectionMask) = u(selectionMask) / ...
            sqrt(mean(abs(u(selectionMask)).^2)+eps);
    end
end

% Ring selection is rotation invariant and therefore safe before carrier
% acquisition. Keeping the original time indices (zeros for other rings)
% preserves the carrier-tone frequency while the random gating contributes
% only a broadband floor. This avoids forcing 32APSK through x^48 merely to
% remove all three rings at once, which would collapse its unambiguous CFO
% range to roughly +/-Rs/96.
z = complex(zeros(size(u)));
z(selectionMask) = u(selectionMask).^powerOrder;
if nUse > 1
    window = 0.5 - 0.5*cos(2*pi*(0:nUse-1)'/(nUse-1));
else
    window = 1;
end
spectrum = abs(fftshift(fft(z.*window,nfft))).^2;
frequencyHz = ((-nfft/2):(nfft/2-1))'*(Rs/nfft);

unambiguousMaxCFOHz = 0.499*Rs/powerOrder;
effectiveMaxCFOHz = min(maxCFOHz,unambiguousMaxCFOHz);
maxRaisedPowerHz = powerOrder*effectiveMaxCFOHz;
searchMask = abs(frequencyHz) <= maxRaisedPowerHz;
searchIndices = find(searchMask);
if isempty(searchIndices)
    error('HelperTMAPSKFourthPowerCoarseCFO:EmptySearch', ...
        'The configured CFO search interval is empty.');
end

[peakPower,localPeak] = max(spectrum(searchIndices));
peakIndex = searchIndices(localPeak);
delta = 0;
if peakIndex > 1 && peakIndex < nfft
    left = log(max(spectrum(peakIndex-1),realmin));
    center = log(max(spectrum(peakIndex),realmin));
    right = log(max(spectrum(peakIndex+1),realmin));
    denom = left - 2*center + right;
    if isfinite(denom) && abs(denom) > eps
        delta = 0.5*(left-right)/denom;
        delta = min(max(delta,-0.5),0.5);
    end
end

raisedPowerHz = frequencyHz(peakIndex) + delta*(Rs/nfft);
cfoHz = raisedPowerHz/powerOrder;

noiseBins = spectrum(searchIndices);
guard = abs(searchIndices-peakIndex) <= 2;
noiseBins(guard) = [];
if isempty(noiseBins)
    noiseFloor = realmin;
else
    noiseFloor = median(noiseBins);
end
confidenceDB = 10*log10(max(peakPower,realmin)/max(noiseFloor,realmin));

rangeToleranceHz = localNumber(options,'RangeToleranceHz',NaN);
if ~isfinite(rangeToleranceHz) || rangeToleranceHz < 0
    rangeToleranceHz = 0.5*Rs/(nfft*powerOrder);
end
qualified = nSelected >= minSelectedSymbols && ...
    isfinite(cfoHz) && ...
    abs(cfoHz) <= effectiveMaxCFOHz + rangeToleranceHz && ...
    isfinite(confidenceDB) && confidenceDB >= minConfidenceDB;

info = struct( ...
    'Applied',true, ...
    'Qualified',qualified, ...
    'AcquisitionSymbols',nUse, ...
    'FFTLength',nfft, ...
    'MaxCFOHz',maxCFOHz, ...
    'EffectiveMaxCFOHz',effectiveMaxCFOHz, ...
    'UnambiguousMaxCFOHz',unambiguousMaxCFOHz, ...
    'RangeToleranceHz',rangeToleranceHz, ...
    'PowerOrder',powerOrder, ...
    'RaisedPowerPeakHz',raisedPowerHz, ...
    'FourthPowerPeakHz',raisedPowerHz, ...
    'CFOHz',cfoHz, ...
    'PeakPower',peakPower, ...
    'NoiseFloor',noiseFloor, ...
    'ConfidenceDB',confidenceDB, ...
    'UseUnitMagnitude',useUnitMagnitude, ...
    'RadiusMin',radiusMin, ...
    'RadiusMax',radiusMax, ...
    'SelectedSymbols',nSelected, ...
    'SelectionFraction',nSelected/max(1,nUse), ...
    'MinSelectedSymbols',minSelectedSymbols);
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
    text = lower(strtrim(string(raw)));
    value = any(text == ["true","1","yes","on"]);
end
end
