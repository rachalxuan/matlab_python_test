function [y, info] = HelperTMConverterGain(x, cfg)
%HELPERTMCONVERTERGAIN Equivalent up/down-converter gain stage.
%   The waveform uses voltage-like complex samples, so a power gain in dB
%   is applied with 10^(gainDB/20).  The stage keeps the physical reference
%   plane in INFO instead of silently normalizing the waveform.

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end

    x = x(:);
    enabled = localLogical(cfg, 'Enabled', false);
    stageName = char(localText(cfg, 'StageName', "converter"));
    inputSignalLevelDBm = localNumeric(cfg, 'InputSignalLevelDBm', -10);
    inputTotalLevelDBm = localNumeric(cfg, 'InputTotalLevelDBm', inputSignalLevelDBm);
    fixedGainDB = localNumeric(cfg, 'FixedGainDB', 31);
    requestedAttenuationDB = localNumeric(cfg, 'AttenuationDB', 0);
    autoAttenuation = localLogical(cfg, 'AutoAttenuation', false);
    targetOutputTotalLevelDBm = localNumeric( ...
        cfg, 'TargetOutputTotalLevelDBm', 0);
    attenuationStepDB = localNumeric(cfg, 'AttenuationStepDB', 0.5);
    maxAttenuationDB = localNumeric(cfg, 'MaxAttenuationDB', 30);
    outputP1dBDBm = localNumeric(cfg, 'OutputP1dBDBm', 11);
    inputMinimumDBm = localNumeric(cfg, 'InputMinimumDBm', -60);
    inputMaximumDBm = localNumeric(cfg, 'InputMaximumDBm', -10);
    enableCompression = localLogical(cfg, 'EnableCompression', false);
    rappSmoothness = localNumeric(cfg, 'RappSmoothness', 3);

    localRequireFiniteScalar(inputSignalLevelDBm, 'InputSignalLevelDBm');
    localRequireFiniteScalar(inputTotalLevelDBm, 'InputTotalLevelDBm');
    localRequireFiniteScalar(fixedGainDB, 'FixedGainDB');
    localRequireFiniteScalar(requestedAttenuationDB, 'AttenuationDB');
    localRequireFiniteScalar(targetOutputTotalLevelDBm, ...
        'TargetOutputTotalLevelDBm');
    localRequirePositiveScalar(attenuationStepDB, 'AttenuationStepDB');
    localRequireNonnegativeScalar(maxAttenuationDB, 'MaxAttenuationDB');
    localRequireFiniteScalar(outputP1dBDBm, 'OutputP1dBDBm');
    localRequireFiniteScalar(inputMinimumDBm, 'InputMinimumDBm');
    localRequireFiniteScalar(inputMaximumDBm, 'InputMaximumDBm');
    localRequirePositiveScalar(rappSmoothness, 'RappSmoothness');

    if autoAttenuation
        requestedAttenuationDB = fixedGainDB + inputTotalLevelDBm - ...
            targetOutputTotalLevelDBm;
    elseif requestedAttenuationDB < 0 || requestedAttenuationDB > maxAttenuationDB
        error('HelperTMConverterGain:AttenuationOutOfRange', ...
            '%s attenuation must be in [0, %.3f] dB.', ...
            stageName, maxAttenuationDB);
    end

    boundedAttenuationDB = min(max(requestedAttenuationDB, 0), ...
        maxAttenuationDB);
    appliedAttenuationDB = attenuationStepDB * ...
        round(boundedAttenuationDB / attenuationStepDB);
    netGainDB = fixedGainDB - appliedAttenuationDB;
    idealOutputSignalLevelDBm = inputSignalLevelDBm + netGainDB;
    idealOutputTotalLevelDBm = inputTotalLevelDBm + netGainDB;
    inputPAPRDB = 10*log10(max(abs(x).^2) / ...
        max(mean(abs(x).^2), realmin));
    idealPeakOutputLevelDBm = idealOutputTotalLevelDBm + inputPAPRDB;

    info = struct( ...
        'Enabled', logical(enabled), ...
        'StageName', stageName, ...
        'InputSignalLevelDBm', inputSignalLevelDBm, ...
        'InputTotalLevelDBm', inputTotalLevelDBm, ...
        'FixedGainDB', fixedGainDB, ...
        'AutoAttenuation', logical(autoAttenuation), ...
        'TargetOutputTotalLevelDBm', targetOutputTotalLevelDBm, ...
        'RequestedAttenuationDB', requestedAttenuationDB, ...
        'AppliedAttenuationDB', appliedAttenuationDB, ...
        'AttenuationStepDB', attenuationStepDB, ...
        'MaxAttenuationDB', maxAttenuationDB, ...
        'ConfiguredNetGainDB', netGainDB, ...
        'NetGainDB', enabled * netGainDB, ...
        'InputMinimumDBm', inputMinimumDBm, ...
        'InputMaximumDBm', inputMaximumDBm, ...
        'InputWithinTypicalRange', logical(enabled && ...
            inputSignalLevelDBm >= inputMinimumDBm && ...
            inputSignalLevelDBm <= inputMaximumDBm), ...
        'OutputP1dBDBm', outputP1dBDBm, ...
        'IdealOutputSignalLevelDBm', inputSignalLevelDBm, ...
        'IdealOutputTotalLevelDBm', inputTotalLevelDBm, ...
        'IdealPeakOutputLevelDBm', inputTotalLevelDBm + inputPAPRDB, ...
        'OutputSignalLevelDBm', inputSignalLevelDBm, ...
        'OutputTotalLevelDBm', inputTotalLevelDBm, ...
        'CompressionEnabled', logical(enableCompression), ...
        'EstimatedCompressionDB', 0, ...
        'CompressionRisk', false, ...
        'PeakClipFraction', 0);

    if ~enabled || isempty(x)
        y = x;
        return;
    end

    info.IdealOutputSignalLevelDBm = idealOutputSignalLevelDBm;
    info.IdealOutputTotalLevelDBm = idealOutputTotalLevelDBm;
    info.IdealPeakOutputLevelDBm = idealPeakOutputLevelDBm;

    amplitudeGain = 10.^(netGainDB/20);
    yIdeal = x .* amplitudeGain;
    y = yIdeal;

    if enableCompression && any(abs(x) > 0)
        inputTotalPowerW = 1e-3 * 10.^(inputTotalLevelDBm/10);
        inputDigitalPower = mean(abs(x).^2);
        digitalUnitsPerSqrtWatt = sqrt(inputDigitalPower / ...
            max(inputTotalPowerW, realmin));
        yIdealPhysical = yIdeal ./ max(digitalUnitsPerSqrtWatt, realmin);

        outputP1dBW = 1e-3 * 10.^(outputP1dBDBm/10);
        amplitudeAtP1dB = sqrt(outputP1dBW);
        p = rappSmoothness;
        ratioAtP1dB = (10.^(p/10) - 1).^(1/(2*p));
        saturationAmplitude = amplitudeAtP1dB / max(ratioAtP1dB, realmin);
        normalizedAmplitude = abs(yIdealPhysical) ./ ...
            max(saturationAmplitude, realmin);
        compressionDenominator = ...
            (1 + normalizedAmplitude.^(2*p)).^(1/(2*p));
        yPhysical = yIdealPhysical ./ compressionDenominator;
        y = yPhysical .* digitalUnitsPerSqrtWatt;

        actualOutputTotalPowerW = mean(abs(yPhysical).^2);
        actualOutputTotalLevelDBm = 10*log10( ...
            max(actualOutputTotalPowerW, realmin) / 1e-3);
        compressionDB = max(0, ...
            idealOutputTotalLevelDBm - actualOutputTotalLevelDBm);
        actualNetGainDB = netGainDB - compressionDB;
        info.OutputTotalLevelDBm = actualOutputTotalLevelDBm;
        info.OutputSignalLevelDBm = inputSignalLevelDBm + actualNetGainDB;
        info.EstimatedCompressionDB = compressionDB;
        info.PeakClipFraction = mean(normalizedAmplitude >= 1);
    else
        info.OutputSignalLevelDBm = idealOutputSignalLevelDBm;
        info.OutputTotalLevelDBm = idealOutputTotalLevelDBm;
    end

    info.CompressionRisk = logical(enabled && ...
        idealPeakOutputLevelDBm >= outputP1dBDBm);
end

function value = localNumeric(s, name, defaultValue)
    value = defaultValue;
    if isfield(s, name) && ~isempty(s.(name))
        value = double(s.(name));
        value = value(1);
    end
end

function value = localLogical(s, name, defaultValue)
    value = defaultValue;
    if isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
        value = value(1);
    end
end

function value = localText(s, name, defaultValue)
    value = defaultValue;
    if isfield(s, name) && ~isempty(s.(name))
        value = string(s.(name));
        value = value(1);
    end
end

function localRequireFiniteScalar(value, name)
    if ~isscalar(value) || ~isfinite(value)
        error('HelperTMConverterGain:InvalidParameter', ...
            '%s must be a finite scalar.', name);
    end
end

function localRequirePositiveScalar(value, name)
    localRequireFiniteScalar(value, name);
    if value <= 0
        error('HelperTMConverterGain:InvalidParameter', ...
            '%s must be positive.', name);
    end
end

function localRequireNonnegativeScalar(value, name)
    localRequireFiniteScalar(value, name);
    if value < 0
        error('HelperTMConverterGain:InvalidParameter', ...
            '%s must be nonnegative.', name);
    end
end
