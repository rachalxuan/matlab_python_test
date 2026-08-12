function [y, state, info] = HelperTMAGC(x, state, cfg)
%HELPERTMAGC Time-constant controlled ordinary-TM AGC.
%
%   [Y,STATE,INFO] = HelperTMAGC(X,STATE,CFG)
%
% Required CFG fields:
%   Enabled
%   SampleRateHz
%   TimeConstantMs
%
% Internal CFG fields:
%   TargetSignalPower
%   MinGainDB
%   MaxGainDB
%   PowerFloor
%   InitialPowerEstimate
%   TraceMaxPoints
%   ChunkSizeSamples
%
% Time-constant definition:
%
%   Pest(k) = alpha * Pest(k-1) ...
%           + (1-alpha) * abs(x(k))^2
%
%   alpha = exp(-1 / (Fs*tau))
%
% After one tau, Pest completes approximately 63.2 percent
% of a power step.
%
% STATE is explicit and contains no persistent state.

    if nargin < 2 || isempty(state)
        state = struct();
    end

    if nargin < 3 || isempty(cfg)
        cfg = struct();
    end

    inputSize = size(x);
    x = x(:);

    enabled = localCfgLogical(cfg, ...
        'Enabled', true);

    sampleRateHz = localCfgNumeric(cfg, ...
        'SampleRateHz', NaN);

    timeConstantMs = localCfgNumeric(cfg, ...
        'TimeConstantMs', 10);

    targetPower = localCfgNumeric(cfg, ...
        'TargetSignalPower', NaN);

    minGainDB = localCfgNumeric(cfg, ...
        'MinGainDB', -40);

    maxGainDB = localCfgNumeric(cfg, ...
        'MaxGainDB', 40);

    powerFloor = localCfgNumeric(cfg, ...
        'PowerFloor', 1e-12);

    traceMaxPoints = round(localCfgNumeric(cfg, ...
        'TraceMaxPoints', 2000));

    chunkSize = round(localCfgNumeric(cfg, ...
        'ChunkSizeSamples', 1e6));

    allowedTimeConstantsMs = [1, 10, 100, 1000];

    if ~isscalar(sampleRateHz) || ...
            ~isfinite(sampleRateHz) || ...
            sampleRateHz <= 0

        error('HelperTMAGC:InvalidSampleRate', ...
            'SampleRateHz must be a positive finite scalar.');
    end

    if ~isscalar(timeConstantMs) || ...
            ~isfinite(timeConstantMs) || ...
            ~ismember(timeConstantMs, ...
                allowedTimeConstantsMs)

        error('HelperTMAGC:InvalidTimeConstantMs', ...
            ['TimeConstantMs must be one of ', ...
             '[1 10 100 1000].']);
    end

    if ~isscalar(targetPower) || ...
            (~isnan(targetPower) && ...
             (~isfinite(targetPower) || targetPower <= 0))

        error('HelperTMAGC:InvalidTargetPower', ...
            'TargetSignalPower must be positive or NaN for auto bootstrap.');
    end

    if ~isscalar(powerFloor) || ...
            ~isfinite(powerFloor) || ...
            powerFloor <= 0

        error('HelperTMAGC:InvalidPowerFloor', ...
            'PowerFloor must be positive.');
    end

    if minGainDB >= maxGainDB
        error('HelperTMAGC:InvalidGainLimits', ...
            'MinGainDB must be smaller than MaxGainDB.');
    end

    traceMaxPoints = max(0, traceMaxPoints);
    chunkSize = max(1, chunkSize);

    tauSec = timeConstantMs * 1e-3;

    % Numerically stable implementation of:
    % beta = 1 - exp(-1/(Fs*tau))
    beta = -expm1( ...
        -1 / (sampleRateHz * tauSec));

    alpha = 1 - beta;

    minGain = 10^(minGainDB/20);
    maxGain = 10^(maxGainDB/20);

    numSamples = numel(x);
    if isfield(state,'PowerEstimate') && ...
            ~isempty(state.PowerEstimate)

        powerEstimate = ...
            double(state.PowerEstimate);
    elseif isfinite(localCfgNumeric(cfg, 'InitialPowerEstimate', NaN)) && ...
            localCfgNumeric(cfg, 'InitialPowerEstimate', NaN) > 0
        powerEstimate = localCfgNumeric(cfg, 'InitialPowerEstimate', NaN);
    else
        bootstrapSamples = min(numSamples, max(32, round(sampleRateHz*1e-3)));
        if bootstrapSamples > 0
            powerEstimate = mean(abs(x(1:bootstrapSamples)).^2);
        else
            powerEstimate = 1;
        end
    end

    if ~isfinite(powerEstimate) || powerEstimate <= 0
        powerEstimate = 1;
    end
    powerEstimate = max( ...
        powerEstimate, powerFloor);

    if isnan(targetPower)
        targetPower = powerEstimate;
    end

    calculatedInitialGain = sqrt( ...
        targetPower / powerEstimate);

    calculatedInitialGain = min(max( ...
        calculatedInitialGain, minGain), ...
        maxGain);

    if isfield(state,'Gain') && ...
            ~isempty(state.Gain) && ...
            isfinite(state.Gain) && ...
            state.Gain > 0

        initialGain = double(state.Gain);
    else
        initialGain = calculatedInitialGain;
    end

    initialGain = min(max( ...
        initialGain, minGain), maxGain);

    durationSec = numSamples / sampleRateHz;
    durationOverTau = durationSec / tauSec;

    if ~enabled
        y = reshape(x, inputSize);

        state.PowerEstimate = powerEstimate;
        state.Gain = initialGain;
        state.SampleRateHz = sampleRateHz;
        state.TimeConstantMs = timeConstantMs;

        inputPower = localMeanPower(x);

        info = struct( ...
            'Enabled',false, ...
            'TimeConstantMs',timeConstantMs, ...
            'ProcessingRateHz',sampleRateHz, ...
            'Alpha',alpha, ...
            'UpdateWeight',beta, ...
            'InitialGain_dB',20*log10(max(initialGain,eps)), ...
            'FinalGain_dB',20*log10(max(initialGain,eps)), ...
            'MinGain_dB',20*log10(max(initialGain,eps)), ...
            'MaxGain_dB',20*log10(max(initialGain,eps)), ...
            'ConfiguredMinGain_dB',minGainDB, ...
            'ConfiguredMaxGain_dB',maxGainDB, ...
            'InputPower',inputPower, ...
            'OutputPower',inputPower, ...
            'FinalPowerEstimate',powerEstimate, ...
            'WaveformDuration_s',durationSec, ...
            'WaveformDurationOverTau',durationOverTau, ...
            'Expected63PercentTime_s',tauSec, ...
            'ExpectedSettlingTime_s',5*tauSec, ...
            'SufficientObservation',durationOverTau >= 5, ...
            'TraceSampleIndex',zeros(0,1), ...
            'TraceTime_s',zeros(0,1), ...
            'TraceGain_dB',zeros(0,1), ...
            'TracePowerEstimate',zeros(0,1), ...
            'TracePowerEstimate_dB',zeros(0,1));

        return;
    end

    y = zeros(size(x), 'like', x);

    traceCount = min( ...
        numSamples, traceMaxPoints);

    if traceCount > 0
        traceIndices = unique(round(linspace( ...
            1, numSamples, traceCount))).';

        tracePower = zeros( ...
            numel(traceIndices), 1);

        traceGain = zeros( ...
            numel(traceIndices), 1);
    else
        traceIndices = zeros(0,1);
        tracePower = zeros(0,1);
        traceGain = zeros(0,1);
    end

    % For:
    % y(k) = beta*x(k) + alpha*y(k-1)
    %
    % filter initial state is alpha * y(0).
    filterState = alpha * powerEstimate;

    lastPowerEstimate = powerEstimate;
    lastGain = initialGain;

    minObservedGain = initialGain;
    maxObservedGain = initialGain;

    inputEnergy = 0;
    outputEnergy = 0;

    for firstIndex = 1:chunkSize:numSamples

        lastIndex = min( ...
            firstIndex + chunkSize - 1, ...
            numSamples);

        indexRange = firstIndex:lastIndex;

        instantaneousPower = ...
            abs(x(indexRange)).^2;

        [powerChunk, filterState] = filter( ...
            beta, ...
            [1, -alpha], ...
            instantaneousPower, ...
            filterState);

        gainChunk = sqrt( ...
            targetPower ./ ...
            max(powerChunk, powerFloor));

        gainChunk = min(max( ...
            gainChunk, minGain), ...
            maxGain);

        yChunk = x(indexRange) .* gainChunk;
        y(indexRange) = yChunk;

        inputEnergy = inputEnergy + ...
            sum(instantaneousPower);

        outputEnergy = outputEnergy + ...
            sum(abs(yChunk).^2);

        lastPowerEstimate = powerChunk(end);
        lastGain = gainChunk(end);

        minObservedGain = min( ...
            minObservedGain, min(gainChunk));

        maxObservedGain = max( ...
            maxObservedGain, max(gainChunk));

        traceMask = ...
            traceIndices >= firstIndex & ...
            traceIndices <= lastIndex;

        if any(traceMask)
            localTraceIndices = ...
                traceIndices(traceMask) ...
                - firstIndex + 1;

            tracePower(traceMask) = ...
                powerChunk(localTraceIndices);

            traceGain(traceMask) = ...
                gainChunk(localTraceIndices);
        end
    end

    state.PowerEstimate = lastPowerEstimate;
    state.Gain = lastGain;
    state.SampleRateHz = sampleRateHz;
    state.TimeConstantMs = timeConstantMs;

    y = reshape(y, inputSize);

    if numSamples > 0
        inputPower = inputEnergy / numSamples;
        outputPower = outputEnergy / numSamples;
    else
        inputPower = NaN;
        outputPower = NaN;
    end

    info = struct( ...
        'Enabled',true, ...
        'TimeConstantMs',timeConstantMs, ...
        'ProcessingRateHz',sampleRateHz, ...
        'Alpha',alpha, ...
        'UpdateWeight',beta, ...
        'InitialGain_dB',20*log10(max(initialGain,eps)), ...
        'FinalGain_dB',20*log10(max(lastGain,eps)), ...
        'MinGain_dB',20*log10(max(minObservedGain,eps)), ...
        'MaxGain_dB',20*log10(max(maxObservedGain,eps)), ...
        'ConfiguredMinGain_dB',minGainDB, ...
        'ConfiguredMaxGain_dB',maxGainDB, ...
        'InputPower',inputPower, ...
        'OutputPower',outputPower, ...
        'FinalPowerEstimate',lastPowerEstimate, ...
        'WaveformDuration_s',durationSec, ...
        'WaveformDurationOverTau',durationOverTau, ...
        'Expected63PercentTime_s',tauSec, ...
        'ExpectedSettlingTime_s',5*tauSec, ...
        'SufficientObservation',durationOverTau >= 5, ...
        'TraceSampleIndex',traceIndices, ...
        'TraceTime_s',traceIndices/sampleRateHz, ...
        'TraceGain_dB',20*log10(max(traceGain,eps)), ...
        'TracePowerEstimate',tracePower, ...
        'TracePowerEstimate_dB', ...
            10*log10(max(tracePower,powerFloor)));
end

function value = localCfgNumeric(cfg, name, defaultValue)
    value = defaultValue;

    if ~isfield(cfg,name) || isempty(cfg.(name))
        return;
    end

    raw = cfg.(name);

    if isnumeric(raw) || islogical(raw)
        value = double(raw);
    else
        converted = str2double(string(raw));

        if isfinite(converted)
            value = double(converted);
        end
    end
end

function value = localCfgLogical(cfg, name, defaultValue)
    value = logical(defaultValue);

    if ~isfield(cfg,name) || isempty(cfg.(name))
        return;
    end

    raw = cfg.(name);

    if islogical(raw) || isnumeric(raw)
        value = logical(raw);
        return;
    end

    key = lower(strtrim(string(raw)));

    value = any(key == [ ...
        "1","true","yes","on"]);
end

function powerValue = localMeanPower(x)
    if isempty(x)
        powerValue = NaN;
    else
        powerValue = mean(abs(x(:)).^2);
    end
end
