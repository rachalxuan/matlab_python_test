function [y, state, info] = HelperTMAGC(x, state, cfg)
%HELPERTMAGC First-order, time-constant controlled digital AGC.
%
% This helper is shared by ordinary TM receive paths.  The public controls
% are cfg.Enabled and cfg.TimeConstantMs; all other fields are internal
% receiver parameters.  State is explicit so repeated calls do not share
% hidden persistent state.

    if nargin < 2 || isempty(state), state = struct(); end
    if nargin < 3 || isempty(cfg), cfg = struct(); end

    originalSize = size(x);
    x = x(:);

    enabled = localLogical(cfg, 'Enabled', true);
    fs = localNumeric(cfg, 'SampleRateHz', NaN);
    tauMs = localNumeric(cfg, 'TimeConstantMs', 10);
    targetPower = localNumeric(cfg, 'TargetSignalPower', NaN);
    minGainDb = localNumeric(cfg, 'MinGainDB', -40);
    maxGainDb = localNumeric(cfg, 'MaxGainDB', 40);
    powerFloor = localNumeric(cfg, 'PowerFloor', 1e-12);
    % NaN means: bootstrap from the beginning of this burst.  A caller can
    % still provide a positive fixed estimate for deterministic unit tests.
    initialPower = localNumeric(cfg, 'InitialPowerEstimate', NaN);
    traceMax = max(0, round(localNumeric(cfg, 'TraceMaxPoints', 2000)));

    allowedTau = [1 10 100 1000];
    if ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('HelperTMAGC:InvalidSampleRate', ...
            'SampleRateHz must be a positive finite scalar.');
    end
    if ~isscalar(tauMs) || ~isfinite(tauMs) || ~ismember(tauMs, allowedTau)
        error('HelperTMAGC:InvalidTimeConstantMs', ...
            'TimeConstantMs must be one of [1 10 100 1000].');
    end
    if ~isscalar(targetPower) || ...
            (~isnan(targetPower) && ...
             (~isfinite(targetPower) || targetPower <= 0))
        error('HelperTMAGC:InvalidTargetPower', ...
            'TargetSignalPower must be positive or NaN for auto bootstrap.');
    end
    if ~isscalar(powerFloor) || ~isfinite(powerFloor) || powerFloor <= 0
        error('HelperTMAGC:InvalidPowerFloor', ...
            'PowerFloor must be positive.');
    end
    if ~isscalar(minGainDb) || ~isscalar(maxGainDb) || ...
            ~isfinite(minGainDb) || ~isfinite(maxGainDb) || ...
            minGainDb >= maxGainDb
        error('HelperTMAGC:InvalidGainLimits', ...
            'MinGainDB must be smaller than MaxGainDB.');
    end

    tauSec = tauMs * 1e-3;
    updateWeight = -expm1(-1 / (fs * tauSec));
    alpha = 1 - updateWeight;
    minGain = 10^(minGainDb/20);
    maxGain = 10^(maxGainDb/20);

    n = numel(x);
    if isfield(state, 'PowerEstimate') && ~isempty(state.PowerEstimate)
        powerEstimate = double(state.PowerEstimate);
    elseif isfinite(initialPower) && initialPower > 0
        powerEstimate = initialPower;
    else
        bootstrapSamples = min(n, max(32, round(fs*1e-3)));
        if bootstrapSamples > 0
            powerEstimate = mean(abs(x(1:bootstrapSamples)).^2);
        else
            powerEstimate = 1;
        end
    end
    if ~isfinite(powerEstimate) || powerEstimate <= 0
        powerEstimate = 1;
    end
    powerEstimate = max(powerEstimate, powerFloor);

    if isnan(targetPower)
        targetPower = powerEstimate;
    end

    if isfield(state, 'Gain') && ~isempty(state.Gain) && ...
            isfinite(state.Gain) && state.Gain > 0
        gain = double(state.Gain);
    else
        gain = sqrt(targetPower / powerEstimate);
    end
    gain = min(max(gain, minGain), maxGain);

    durationSec = n / fs;
    inputPower = localMeanPower(x);

    if ~enabled
        y = reshape(x, originalSize);
        state.PowerEstimate = powerEstimate;
        state.Gain = gain;
        state.SampleRateHz = fs;
        state.TimeConstantMs = tauMs;
        info = localInfo(false, tauMs, fs, alpha, updateWeight, gain, gain, ...
            gain, gain, inputPower, inputPower, powerEstimate, durationSec, ...
            tauSec, zeros(0,1), zeros(0,1), zeros(0,1));
        return;
    end

    y = zeros(size(x), 'like', x);
    traceCount = min(n, traceMax);
    if traceCount > 0
        traceIndex = unique(round(linspace(1, n, traceCount))).';
        traceGain = zeros(numel(traceIndex), 1);
        tracePower = zeros(numel(traceIndex), 1);
    else
        traceIndex = zeros(0,1);
        traceGain = zeros(0,1);
        tracePower = zeros(0,1);
    end

    inputEnergy = 0;
    outputEnergy = 0;
    firstGain = gain;
    minObservedGain = gain;
    maxObservedGain = gain;
    traceCursor = 1;

    for k = 1:n
        samplePower = abs(x(k)).^2;
        powerEstimate = alpha * powerEstimate + updateWeight * samplePower;
        powerEstimate = max(powerEstimate, powerFloor);
        gain = sqrt(targetPower / powerEstimate);
        gain = min(max(gain, minGain), maxGain);
        y(k) = gain * x(k);

        inputEnergy = inputEnergy + samplePower;
        outputEnergy = outputEnergy + abs(y(k)).^2;
        minObservedGain = min(minObservedGain, gain);
        maxObservedGain = max(maxObservedGain, gain);

        if traceCursor <= numel(traceIndex) && k == traceIndex(traceCursor)
            traceGain(traceCursor) = gain;
            tracePower(traceCursor) = powerEstimate;
            traceCursor = traceCursor + 1;
        end
    end

    state.PowerEstimate = powerEstimate;
    state.Gain = gain;
    state.SampleRateHz = fs;
    state.TimeConstantMs = tauMs;
    if n > 0
        inputPower = inputEnergy / n;
        outputPower = outputEnergy / n;
    else
        outputPower = NaN;
    end

    info = localInfo(true, tauMs, fs, alpha, updateWeight, firstGain, gain, ...
        minObservedGain, maxObservedGain, inputPower, outputPower, ...
        powerEstimate, durationSec, tauSec, traceIndex, traceGain, tracePower);
    y = reshape(y, originalSize);
end

function info = localInfo(enabled, tauMs, fs, alpha, updateWeight, ...
        firstGain, finalGain, minGain, maxGain, inputPower, outputPower, ...
        finalPower, durationSec, tauSec, traceIndex, traceGain, tracePower)
    info = struct( ...
        'Enabled', logical(enabled), ...
        'TimeConstantMs', tauMs, ...
        'ProcessingRateHz', fs, ...
        'Alpha', alpha, ...
        'UpdateWeight', updateWeight, ...
        'InitialGain_dB', 20*log10(max(firstGain, eps)), ...
        'FinalGain_dB', 20*log10(max(finalGain, eps)), ...
        'MinGain_dB', 20*log10(max(minGain, eps)), ...
        'MaxGain_dB', 20*log10(max(maxGain, eps)), ...
        'InputPower', inputPower, ...
        'OutputPower', outputPower, ...
        'FinalPowerEstimate', finalPower, ...
        'WaveformDuration_s', durationSec, ...
        'WaveformDurationOverTau', durationSec/max(tauSec, eps), ...
        'Expected63PercentTime_s', tauSec, ...
        'ExpectedSettlingTime_s', 5*tauSec, ...
        'SufficientObservation', durationSec >= 5*tauSec, ...
        'TraceSampleIndex', traceIndex, ...
        'TraceTime_s', traceIndex/max(fs, eps), ...
        'TraceGain_dB', 20*log10(max(traceGain, eps)), ...
        'TracePowerEstimate', tracePower, ...
        'TracePowerEstimate_dB', 10*log10(max(tracePower, eps)));
end

function v = localNumeric(cfg, name, defaultValue)
    v = defaultValue;
    if ~isfield(cfg, name) || isempty(cfg.(name)), return; end
    raw = cfg.(name);
    if isnumeric(raw) || islogical(raw)
        v = double(raw);
    else
        parsed = str2double(string(raw));
        if isfinite(parsed), v = parsed; end
    end
end

function v = localLogical(cfg, name, defaultValue)
    v = logical(defaultValue);
    if ~isfield(cfg, name) || isempty(cfg.(name)), return; end
    raw = cfg.(name);
    if isnumeric(raw) || islogical(raw)
        v = logical(raw);
    else
        v = any(lower(strtrim(string(raw))) == ["1" "true" "yes" "on"]);
    end
end

function p = localMeanPower(x)
    if isempty(x), p = NaN; else, p = mean(abs(x).^2); end
end
