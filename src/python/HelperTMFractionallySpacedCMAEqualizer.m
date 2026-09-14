function [yEq, info] = HelperTMFractionallySpacedCMAEqualizer(x, refConst, options)
%HELPERTMFRACTIONALLYSPACEDCMAEQUALIZER Experimental 2-sps CMA FSE.
%   The input must be the ordinary-TM matched-filter output at exactly two
%   samples per symbol.  comm.LinearEqualizer performs fractional-spaced
%   filtering and returns one output sample per symbol.  This stage replaces
%   the Gardner -> 1-sps step for the explicit 2-sps comparison path.
%
%   The first implementation is intentionally limited to constant-envelope
%   BPSK/QPSK/8PSK.  QAM/APSK require MMA/RDE or training-assisted variants;
%   silently treating them as validated CMA paths would be misleading.

x = complex(x(:));
refConst = complex(refConst(:));
info = localEmptyInfo();

if isempty(x)
    yEq = x;
    info.Reason = 'empty input';
    return;
end
if isempty(refConst) || any(~isfinite(refConst))
    yEq = x;
    info.Reason = 'empty or invalid reference constellation';
    return;
end

modulation = upper(strtrim(string(localText(options,'modType',''))));
supported = any(modulation == ["BPSK","QPSK","8PSK"]);
if ~supported
    error('HelperTMFractionallySpacedCMAEqualizer:UnsupportedModulation', ...
        ['The first 2-sps FSE implementation supports only ', ...
         'BPSK/QPSK/8PSK; requested modulation is %s.'],char(modulation));
end

inputSPS = round(localNumber(options, ...
    'adaptiveFractionalEqualizerInputSamplesPerSymbol',2));
if inputSPS ~= 2
    error('HelperTMFractionallySpacedCMAEqualizer:InvalidInputSPS', ...
        'adaptiveFractionalEqualizerInputSamplesPerSymbol must be 2.');
end

nTaps = max(inputSPS,round(localNumber(options, ...
    'adaptiveFractionalEqualizerTaps',49)));
if mod(nTaps,2) == 0
    nTaps = nTaps + 1;
end
stepSize = localNumber(options,'adaptiveFractionalEqualizerStep',2e-4);
if ~isscalar(stepSize) || ~isfinite(stepSize) || stepSize <= 0
    error('HelperTMFractionallySpacedCMAEqualizer:InvalidStepSize', ...
        'adaptiveFractionalEqualizerStep must be a finite positive scalar.');
end
referenceTap = round(localNumber(options, ...
    'adaptiveFractionalEqualizerReferenceTap',ceil(nTaps/2)));
referenceTap = min(nTaps,max(1,referenceTap));
weightUpdatePeriod = max(1,round(localNumber(options, ...
    'adaptiveFractionalEqualizerWeightUpdatePeriod',1)));

% The System object requires complete K-sample input symbol groups.
nInput = floor(numel(x)/inputSPS)*inputSPS;
xWork = x(1:nInput);
inputPower = mean(abs(xWork).^2);
referencePower = mean(abs(refConst).^2);
if ~isfinite(inputPower) || inputPower <= realmin('double')
    error('HelperTMFractionallySpacedCMAEqualizer:NoUsableInputPower', ...
        'The 2-sps FSE input has no finite nonzero power.');
end
xWork = xWork * sqrt(referencePower/inputPower);

equalizer = comm.LinearEqualizer( ...
    'Algorithm','CMA', ...
    'NumTaps',nTaps, ...
    'StepSize',stepSize, ...
    'Constellation',refConst.', ...
    'ReferenceTap',referenceTap, ...
    'InputSamplesPerSymbol',inputSPS, ...
    'WeightUpdatePeriod',weightUpdatePeriod, ...
    'ErrorOutputPort',true);

[yEq,errorSignal] = equalizer(xWork);
yEq = complex(yEq(:));
errorSignal = double(errorSignal(:));
if isempty(yEq) || any(~isfinite(real(yEq))) || any(~isfinite(imag(yEq)))
    error('HelperTMFractionallySpacedCMAEqualizer:NonfiniteOutput', ...
        'The 2-sps CMA equalizer produced an empty or nonfinite output.');
end

outputPower = mean(abs(yEq).^2);
if isfinite(outputPower) && outputPower > realmin('double')
    yEq = yEq * sqrt(referencePower/outputPower);
end

settleSymbols = min(numel(errorSignal)-1,max(0,round(localNumber( ...
    options,'adaptiveFractionalEqualizerMetricWarmupSymbols',2000))));
metricError = errorSignal(settleSymbols+1:end);
metricError = metricError(isfinite(metricError));
if isempty(metricError)
    errorMSE = NaN;
else
    errorMSE = mean(abs(metricError).^2);
end
convergenceThreshold = localNumber(options, ...
    'adaptiveFractionalEqualizerConvergenceMSEThreshold',0.05);
if ~isscalar(convergenceThreshold) || ~isfinite(convergenceThreshold) || ...
        convergenceThreshold <= 0
    error('HelperTMFractionallySpacedCMAEqualizer:InvalidConvergenceThreshold', ...
        ['adaptiveFractionalEqualizerConvergenceMSEThreshold must be a ', ...
         'finite positive scalar.']);
end

info.Applied = true;
info.Mode = 'fractionally-spaced-2sps-cma';
info.InputSamplesPerSymbol = inputSPS;
info.NumTaps = nTaps;
info.ReferenceTap = referenceTap;
info.StepSize = stepSize;
info.WeightUpdatePeriod = weightUpdatePeriod;
info.InputSamples = nInput;
info.OutputSymbols = numel(yEq);
info.InputPower = inputPower;
info.OutputPower = mean(abs(yEq).^2);
info.ErrorMSE = errorMSE;
info.ConvergenceThreshold = convergenceThreshold;
info.Converged = all(isfinite(yEq)) && isfinite(errorMSE) && ...
    errorMSE <= convergenceThreshold;
info.Reason = ['2-sps matched-filter output -> CMA FSE -> ', ...
    '1-sps carrier recovery; Gardner bypassed'];
end

function info = localEmptyInfo()
info = struct( ...
    'Applied',false, ...
    'Mode','off', ...
    'InputSamplesPerSymbol',2, ...
    'NumTaps',0, ...
    'ReferenceTap',0, ...
    'StepSize',NaN, ...
    'WeightUpdatePeriod',0, ...
    'InputSamples',0, ...
    'OutputSymbols',0, ...
    'InputPower',NaN, ...
    'OutputPower',NaN, ...
    'ErrorMSE',NaN, ...
    'ConvergenceThreshold',NaN, ...
    'Converged',false, ...
    'Reason','disabled');
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = double(s.(name));
    if isscalar(candidate)
        value = candidate;
    end
end
end

function value = localText(s,name,defaultValue)
value = char(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = string(s.(name));
    if isscalar(candidate)
        value = char(candidate);
    end
end
end
