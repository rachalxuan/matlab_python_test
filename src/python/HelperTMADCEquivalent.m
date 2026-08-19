function [y, info] = HelperTMADCEquivalent(x, cfg)
%HELPERTMADCEQUIVALENT Optional complex-baseband ADC clipping/quantization.
%   FullScalePowerDBm is the configured reference power at which the
%   normalized complex waveform has unit RMS.  Actual RF/IF ADC full-scale
%   must be supplied from the board data sheet or calibration; therefore the
%   caller should leave this model disabled until that value is known.

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end
    x = x(:);
    enabled = localLogical(cfg, 'Enabled', false);
    bits = round(localNumeric(cfg, 'Bits', 12));
    fullScalePowerDBm = localNumeric(cfg, 'FullScalePowerDBm', 0);
    inputTotalLevelDBm = localNumeric(cfg, 'InputTotalLevelDBm', NaN);

    info = struct( ...
        'Enabled', logical(enabled), ...
        'Bits', bits, ...
        'FullScalePowerDBm', fullScalePowerDBm, ...
        'InputTotalLevelDBm', inputTotalLevelDBm, ...
        'RMSBackoffDB', NaN, ...
        'ClipFraction', 0, ...
        'QuantizationSNRDB', Inf);

    if ~enabled || isempty(x)
        y = x;
        return;
    end
    if bits < 2 || bits > 32
        error('HelperTMADCEquivalent:InvalidBits', ...
            'Bits must be an integer in [2, 32].');
    end
    if ~isfinite(fullScalePowerDBm) || ~isfinite(inputTotalLevelDBm)
        error('HelperTMADCEquivalent:InvalidLevel', ...
            'FullScalePowerDBm and InputTotalLevelDBm must be finite.');
    end

    inputDigitalPower = mean(abs(x).^2);
    if inputDigitalPower <= realmin
        y = zeros(size(x));
        return;
    end

    rmsRelativeToFullScale = 10.^((inputTotalLevelDBm-fullScalePowerDBm)/20);
    z = x ./ sqrt(inputDigitalPower) .* rmsRelativeToFullScale;
    maxCode = 2^(bits-1)-1;
    maxNormalized = 1;
    minNormalized = -1;

    if isreal(z)
        clipMask = z > maxNormalized | z < minNormalized;
        zClipped = min(max(z, minNormalized), maxNormalized);
        zQuantized = round(zClipped .* maxCode) ./ maxCode;
    else
        clipMask = abs(real(z)) > maxNormalized | ...
            abs(imag(z)) > maxNormalized;
        iClipped = min(max(real(z), minNormalized), maxNormalized);
        qClipped = min(max(imag(z), minNormalized), maxNormalized);
        zQuantized = round(iClipped .* maxCode) ./ maxCode + ...
            1j .* round(qClipped .* maxCode) ./ maxCode;
    end

    y = zQuantized;
    quantizationError = zQuantized - z;
    info.RMSBackoffDB = fullScalePowerDBm - inputTotalLevelDBm;
    info.ClipFraction = mean(clipMask);
    info.QuantizationSNRDB = 10*log10( ...
        mean(abs(z).^2) / max(mean(abs(quantizationError).^2), realmin));
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
