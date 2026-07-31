function verdict = reg_evaluate_result(actual, expected, executionError)
%REG_EVALUATE_RESULT Apply one common PASS contract to a regression result.
%
% verdict fields:
%   Status       PASS | FAIL_METRIC | ERROR | EXPECTED_ERROR_PASS |
%                UNEXPECTED_PASS
%   Pass         logical terminal verdict
%   Success      whether the evaluated simulation completed successfully
%   FailedChecks semicolon-separated reasons
%   ErrorIdentifier / ErrorMessage

    if nargin < 1 || isempty(actual)
        actual = struct();
    end
    if nargin < 2 || isempty(expected)
        expected = struct();
    end
    if nargin < 3 || isempty(executionError)
        executionError = struct('Identifier', "", 'Message', "");
    end

    expected = localExpectedDefaults(expected);
    [errorIdentifier, errorMessage] = localErrorDetails(actual, executionError);
    actualSuccess = localLogical(actual, 'success', false);
    hasError = strlength(errorIdentifier) > 0 || strlength(errorMessage) > 0 || ...
        (isfield(actual, 'success') && ~actualSuccess);

    verdict = struct( ...
        'Status', "ERROR", ...
        'Pass', false, ...
        'Success', actualSuccess, ...
        'FailedChecks', "", ...
        'ErrorIdentifier', errorIdentifier, ...
        'ErrorMessage', errorMessage);

    if strlength(expected.ExpectedErrorIdentifier) > 0 || ...
            strlength(expected.ExpectedErrorMessage) > 0
        if ~hasError
            verdict.Status = "UNEXPECTED_PASS";
            verdict.FailedChecks = "expected an error, but the case succeeded";
            return;
        end

        idMatches = strlength(expected.ExpectedErrorIdentifier) == 0 || ...
            contains(errorIdentifier, expected.ExpectedErrorIdentifier);
        messageMatches = strlength(expected.ExpectedErrorMessage) == 0 || ...
            contains(errorMessage, expected.ExpectedErrorMessage, 'IgnoreCase', true);
        if idMatches && messageMatches
            verdict.Status = "EXPECTED_ERROR_PASS";
            verdict.Pass = true;
            verdict.FailedChecks = "";
        else
            verdict.Status = "ERROR";
            verdict.FailedChecks = strjoin(localNonEmpty([ ...
                localMismatch("error identifier", errorIdentifier, expected.ExpectedErrorIdentifier), ...
                localMismatch("error message", errorMessage, expected.ExpectedErrorMessage)]), "; ");
        end
        return;
    end

    if strlength(string(executionError.Message)) > 0
        verdict.Status = "ERROR";
        verdict.FailedChecks = "simulation raised an exception";
        return;
    end
    if ~actualSuccess
        verdict.Status = "ERROR";
        verdict.FailedChecks = "simulation returned success=false";
        return;
    end

    infrastructureFailures = strings(0, 1);
    metricFailures = strings(0, 1);

    for k = 1:numel(expected.RequiredMetrics)
        metricName = char(expected.RequiredMetrics(k));
        metricValue = localNumeric(actual, metricName, NaN);
        if ~isfinite(metricValue)
            infrastructureFailures(end+1, 1) = ...
                "required metric " + string(metricName) + " is missing or non-finite"; %#ok<AGROW>
        end
    end

    ber = localNumeric(actual, 'BER', NaN);
    lockRate = localNumeric(actual, 'LockRate', NaN);
    fer = localNumeric(actual, 'FER', localNumeric(actual, 'FrameErrorRate', NaN));
    mer = localNumeric(actual, 'MER_dB', NaN);
    countedFrames = localNumeric(actual, 'CountedFrames', NaN);

    if isfinite(ber) && ber < 0
        infrastructureFailures(end+1, 1) = ...
            "BER contains an error sentinel (" + string(ber) + ")"; %#ok<AGROW>
    end
    if ~isempty(expected.MaxBER) && (~isfinite(ber) || ber > expected.MaxBER)
        metricFailures(end+1, 1) = localUpperFailure("BER", ber, expected.MaxBER); %#ok<AGROW>
    end
    if ~isempty(expected.MinLockRate) && ...
            (~isfinite(lockRate) || lockRate < expected.MinLockRate)
        metricFailures(end+1, 1) = ...
            localLowerFailure("LockRate", lockRate, expected.MinLockRate); %#ok<AGROW>
    end
    if ~isempty(expected.MaxFER) && (~isfinite(fer) || fer > expected.MaxFER)
        metricFailures(end+1, 1) = localUpperFailure("FER", fer, expected.MaxFER); %#ok<AGROW>
    end
    if ~isempty(expected.MinMERdB) && (~isfinite(mer) || mer < expected.MinMERdB)
        metricFailures(end+1, 1) = localLowerFailure("MER_dB", mer, expected.MinMERdB); %#ok<AGROW>
    end
    if ~isempty(expected.MinCountedFrames) && ...
            (~isfinite(countedFrames) || countedFrames < expected.MinCountedFrames)
        metricFailures(end+1, 1) = ...
            localLowerFailure("CountedFrames", countedFrames, expected.MinCountedFrames); %#ok<AGROW>
    end

    metricFailures = [metricFailures; ...
        localEchoFailure(actual, 'DataPathMode', expected.ExpectedDataPathMode); ...
        localEchoFailure(actual, 'WaveformMode', expected.ExpectedWaveformMode); ...
        localEchoFailure(actual, 'RandomizerFECPosition', expected.ExpectedRandomizerFECPosition); ...
        localEchoFailure(actual, 'GMSKDetectorUsed', expected.ExpectedGMSKDetector)];

    if ~isempty(expected.ExpectedRandomizerEnabled)
        if ~isfield(actual, 'RandomizerEnabled') || ...
                logical(actual.RandomizerEnabled) ~= logical(expected.ExpectedRandomizerEnabled)
            metricFailures(end+1, 1) = ...
                "RandomizerEnabled echo does not match expected value"; %#ok<AGROW>
        end
    end

    infrastructureFailures = localNonEmpty(infrastructureFailures);
    metricFailures = localNonEmpty(metricFailures);
    if ~isempty(infrastructureFailures)
        verdict.Status = "ERROR";
        verdict.FailedChecks = strjoin(infrastructureFailures, "; ");
    elseif ~isempty(metricFailures)
        verdict.Status = "FAIL_METRIC";
        verdict.FailedChecks = strjoin(metricFailures, "; ");
    else
        verdict.Status = "PASS";
        verdict.Pass = true;
        verdict.FailedChecks = "";
    end
end

function expected = localExpectedDefaults(expected)
    defaults = struct( ...
        'RequiredMetrics', ["BER", "LockRate"], ...
        'MaxBER', [], ...
        'MinLockRate', [], ...
        'MaxFER', [], ...
        'MinMERdB', [], ...
        'MinCountedFrames', [], ...
        'ExpectedDataPathMode', "", ...
        'ExpectedWaveformMode', "", ...
        'ExpectedRandomizerFECPosition', "", ...
        'ExpectedRandomizerEnabled', [], ...
        'ExpectedGMSKDetector', "", ...
        'ExpectedErrorIdentifier', "", ...
        'ExpectedErrorMessage', "");
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(expected, names{k})
            expected.(names{k}) = defaults.(names{k});
        end
    end
    expected.RequiredMetrics = string(expected.RequiredMetrics);
    stringFields = {'ExpectedDataPathMode','ExpectedWaveformMode', ...
        'ExpectedRandomizerFECPosition','ExpectedGMSKDetector', ...
        'ExpectedErrorIdentifier','ExpectedErrorMessage'};
    for k = 1:numel(stringFields)
        expected.(stringFields{k}) = string(expected.(stringFields{k}));
    end
end

function [identifier, message] = localErrorDetails(actual, executionError)
    identifier = string(executionError.Identifier);
    message = string(executionError.Message);
    if strlength(identifier) == 0 && isstruct(actual) && ...
            isfield(actual, 'errorIdentifier') && ~isempty(actual.errorIdentifier)
        identifier = string(actual.errorIdentifier);
    end
    if strlength(message) == 0 && isstruct(actual)
        if isfield(actual, 'errorMsg') && ~isempty(actual.errorMsg)
            message = string(actual.errorMsg);
        elseif isfield(actual, 'error') && ~isempty(actual.error)
            message = string(actual.error);
        end
    end
end

function value = localNumeric(s, name, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        candidate = double(s.(name));
        if isscalar(candidate)
            value = candidate;
        end
    end
end

function value = localLogical(s, name, defaultValue)
    value = logical(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function message = localUpperFailure(name, actual, limit)
    message = string(sprintf('%s=%g exceeds maximum %g', name, actual, limit));
end

function message = localLowerFailure(name, actual, limit)
    message = string(sprintf('%s=%g is below minimum %g', name, actual, limit));
end

function failure = localEchoFailure(actual, fieldName, expectedValue)
    failure = "";
    if strlength(string(expectedValue)) == 0
        return;
    end
    if ~isfield(actual, fieldName) || isempty(actual.(fieldName))
        failure = string(fieldName) + " echo is missing";
    elseif ~strcmpi(string(actual.(fieldName)), string(expectedValue))
        failure = string(fieldName) + "=" + string(actual.(fieldName)) + ...
            " does not match expected " + string(expectedValue);
    end
end

function message = localMismatch(label, actual, expected)
    message = "";
    if strlength(string(expected)) > 0 && ~contains(string(actual), string(expected))
        message = string(label) + " mismatch: actual='" + string(actual) + ...
            "', expected to contain '" + string(expected) + "'";
    end
end

function values = localNonEmpty(values)
    values = string(values(:));
    values = values(strlength(values) > 0);
end
