function R = run_tm_agc_contract_tests(opts)
%RUN_TM_AGC_CONTRACT_TESTS Verify the four supported TM AGC time constants.
%
% This is a short synthetic test.  It does not run a channel model or a
% complete TM sweep; it verifies the shared AGC equation and public contract.
%
% Example:
%   addpath('E:/web_code/react/fft_project/react-fft/src/python');
%   addpath('regression');
%   R = run_tm_agc_contract_tests(struct('WriteJSON',true));

    if nargin < 1 || isempty(opts), opts = struct(); end
    fs = localNumeric(opts, 'SampleRateHz', 10000);
    taus = [1 10 100 1000];
    if isfield(opts, 'TimeConstantsMs') && ~isempty(opts.TimeConstantsMs)
        taus = double(opts.TimeConstantsMs(:).');
    end
    writeJson = localLogical(opts, 'WriteJSON', true);

    if ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('run_tm_agc_contract_tests:InvalidSampleRate', ...
            'SampleRateHz must be a positive scalar.');
    end
    if any(~ismember(taus, [1 10 100 1000]))
        error('run_tm_agc_contract_tests:InvalidTimeConstants', ...
            'TimeConstantsMs must contain only [1 10 100 1000].');
    end

    cases = repmat(localEmptyCase(), numel(taus), 1);
    for k = 1:numel(taus)
        tauMs = taus(k);
        n = max(100, ceil(8 * tauMs * 1e-3 * fs));
        n1 = floor(n/2);
        % A two-level envelope: the AGC must settle after each transition.
        x = [0.5*ones(n1,1); ones(n-n1,1)];
        cfg = struct( ...
            'Enabled',true, ...
            'SampleRateHz',fs, ...
            'TimeConstantMs',tauMs, ...
            'TargetSignalPower',1, ...
            'MinGainDB',-40, ...
            'MaxGainDB',40, ...
            'InitialPowerEstimate',1, ...
            'TraceMaxPoints',256);

        [y, state, info] = HelperTMAGC(x, struct(), cfg);
        offCfg = cfg;
        offCfg.Enabled = false;
        yOff = HelperTMAGC(x, struct(), offCfg);

        tail = max(1, floor(n/8));
        tailPower = mean(abs(y(end-tail+1:end)).^2);
        alphaExpected = exp(-1/(fs*tauMs*1e-3));

        cases(k).TimeConstantMs = tauMs;
        cases(k).NumSamples = n;
        cases(k).Alpha = info.Alpha;
        cases(k).ExpectedAlpha = alphaExpected;
        cases(k).TailOutputPower = tailPower;
        cases(k).FinalGain_dB = info.FinalGain_dB;
        cases(k).WaveformDurationOverTau = info.WaveformDurationOverTau;
        cases(k).SufficientObservation = info.SufficientObservation;
        cases(k).FiniteOutput = all(isfinite(y));
        cases(k).FiniteState = isfinite(state.PowerEstimate) && ...
            isfinite(state.Gain);
        cases(k).AGCOffExact = isequal(yOff, x);
        cases(k).AlphaMatch = abs(info.Alpha - alphaExpected) <= 10*eps;
        cases(k).Settled = abs(tailPower - 1) <= 0.05;
        cases(k).Status = ternary(all([cases(k).FiniteOutput, ...
            cases(k).FiniteState, cases(k).AGCOffExact, ...
            cases(k).AlphaMatch, cases(k).Settled]), 'PASS', 'FAIL');
    end

    R = struct();
    R.Test = 'TM AGC time-constant contract';
    R.SampleRateHz = fs;
    R.AllowedTimeConstantsMs = taus;
    R.Cases = cases;
    R.Pass = nnz(strcmp({cases.Status}, 'PASS'));
    R.Fail = nnz(strcmp({cases.Status}, 'FAIL'));
    R.Total = numel(cases);
    R.Status = ternary(R.Fail == 0, 'PASS', 'FAIL');
    R.Timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));

    fprintf('TM AGC contract: PASS=%d FAIL=%d TOTAL=%d\n', ...
        R.Pass, R.Fail, R.Total);
    disp(struct2table(cases));

    if writeJson
        outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            '..', '..', 'artifacts', 'ccsds', 'agc');
        if ~isfolder(outDir), mkdir(outDir); end
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        jsonPath = fullfile(outDir, ...
            ['tm_agc_contract_' stamp '.json']);
        fid = fopen(jsonPath, 'w');
        if fid < 0
            error('run_tm_agc_contract_tests:OpenJSONFailed', ...
                'Cannot open JSON output: %s', jsonPath);
        end
        fwrite(fid, jsonencode(R), 'char');
        fclose(fid);
        fprintf('JSON: %s\n', jsonPath);
        R.JSON = jsonPath;
    end
end

function c = localEmptyCase()
    c = struct('TimeConstantMs',NaN,'NumSamples',NaN,'Alpha',NaN, ...
        'ExpectedAlpha',NaN,'TailOutputPower',NaN,'FinalGain_dB',NaN, ...
        'WaveformDurationOverTau',NaN,'SufficientObservation',false, ...
        'FiniteOutput',false,'FiniteState',false,'AGCOffExact',false, ...
        'AlphaMatch',false,'Settled',false,'Status','ERROR');
end

function v = localNumeric(s, name, defaultValue)
    v = defaultValue;
    if isfield(s,name) && ~isempty(s.(name))
        v = double(s.(name));
    end
end

function v = localLogical(s, name, defaultValue)
    v = logical(defaultValue);
    if isfield(s,name) && ~isempty(s.(name))
        v = logical(s.(name));
    end
end

function out = ternary(condition, yesValue, noValue)
    if condition, out = yesValue; else, out = noValue; end
end
