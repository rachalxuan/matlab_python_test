function [T, state] = reg_run_cases(suiteName, cases, userOpts)
%REG_RUN_CASES Execute stable-ID cases with checkpoint/resume and common PASS.
%
% Required fields in every cases element:
%   Id, Name, Category, Params, Expected, Meta
%
% Important options:
%   OutputDir, RunId, PlanVersion, Resume, MaxNewCases, RerunFailed,
%   BaseSeed, SeedMode, DryRun, FailOnFailure, Verbose.
%
% Checkpoints intentionally retain only case definitions, seeds, statuses,
% scalar metrics, and errors. Large waveform/plot/pipeline arrays returned
% by run_ccsds_tm_evaluation are evaluated in memory but are not persisted.
%
% SeedMode:
%   "caseIndex"            - BaseSeed + case index (default).
%   "pairedChannelProfile" - Cases with the same transmitter/data-path
%                            metadata share one deterministic seed even
%                            when the channel profile is different.

    if nargin < 3 || isempty(userOpts)
        userOpts = struct();
    end
    suiteName = string(suiteName);
    localValidateCases(cases);

    thisDir = fileparts(mfilename('fullpath'));
    pythonDir = fileparts(thisDir);
    addpath(pythonDir);
    opts = localOptions(suiteName, thisDir, userOpts);
    caseIds = string({cases.Id})';

    if opts.DryRun
        state = localNewState(suiteName, cases, opts);
        for k = 1:numel(cases)
            state.Results(k).Seed = localCaseSeed(cases(k), opts, k);
        end
        T = localResultsTable(state.Results);
        fprintf('\n[%s] dry run: %d planned cases\n', suiteName, numel(cases));
        for k = 1:numel(cases)
            fprintf('  %3d  seed=%10u  %s  %s\n', k, ...
                uint32(state.Results(k).Seed), char(string(cases(k).Id)), ...
                char(string(cases(k).Name)));
        end
        return;
    end

    if ~isfolder(opts.OutputDir)
        mkdir(opts.OutputDir);
    end
    checkpointPath = fullfile(opts.OutputDir, 'checkpoint.mat');
    summaryPath = fullfile(opts.OutputDir, 'summary.csv');

    if exist(checkpointPath, 'file') == 2
        if ~opts.Resume
            error('reg_run_cases:CheckpointExists', ...
                ['Checkpoint already exists at "%s". Set Resume=true or ' ...
                 'choose a new OutputDir/RunId; existing results are never overwritten.'], ...
                checkpointPath);
        end
        loaded = load(checkpointPath, 'state');
        state = loaded.state;
        localValidateResumeState(state, suiteName, cases, caseIds, opts.PlanVersion);
        state.Cases = cases;
        storageNeedsUpgrade = ~isfield(state, 'CheckpointStorage') || ...
            string(state.CheckpointStorage) ~= "metricsOnly";
        [state.Results, recordsUpgraded] = ...
            localUpgradeResultRecords(state.Results);
        [state.Results, compactedCount] = ...
            localCompactResultRecords(state.Results);
        checkpointNeedsSave = storageNeedsUpgrade || recordsUpgraded || ...
            compactedCount > 0;
        for k = 1:numel(state.Results)
            if string(state.Results(k).Status) == "RUNNING"
                state.Results(k).Status = "PENDING";
                state.Results(k).Pass = false;
                state.Results(k).FailedChecks = ...
                    "previous process stopped while this case was running";
                checkpointNeedsSave = true;
            end
        end
        state.CheckpointStorage = "metricsOnly";
        if checkpointNeedsSave
            state.UpdatedAt = localTimestamp();
            reg_save_checkpoint(checkpointPath, state);
            localWriteSummary(summaryPath, state.Results);
            if opts.Verbose && compactedCount > 0
                fprintf(['[%s] compacted %d legacy result payload(s) into ', ...
                    'a metrics-only checkpoint.\n'], ...
                    char(suiteName), compactedCount);
            end
        end
    else
        state = localNewState(suiteName, cases, opts);
        reg_save_checkpoint(checkpointPath, state);
    end

    selectedIds = string(opts.CaseIds);
    newCasesRun = 0;
    for k = 1:numel(cases)
        if ~isempty(selectedIds) && ~any(caseIds(k) == selectedIds)
            continue;
        end
        if newCasesRun >= opts.MaxNewCases
            break;
        end

        previousStatus = string(state.Results(k).Status);
        isCompleted = any(previousStatus == ...
            ["PASS","EXPECTED_ERROR_PASS","FAIL_METRIC","ERROR","UNEXPECTED_PASS"]);
        if isCompleted && ~(opts.RerunFailed && ~state.Results(k).Pass)
            continue;
        end

        newCasesRun = newCasesRun + 1;
        caseDef = cases(k);
        seed = localCaseSeed(caseDef, opts, k);
        rng(seed, 'twister');

        state.Results(k) = localStartRecord(state.Results(k), seed);
        state.UpdatedAt = localTimestamp();
        reg_save_checkpoint(checkpointPath, state);
        localWriteSummary(summaryPath, state.Results);

        if opts.Verbose
            fprintf('\n[%s %03d/%03d] %s\n', char(suiteName), k, ...
                numel(cases), char(string(caseDef.Name)));
        end

        timer = tic;
        actual = struct();
        executionError = struct('Identifier', "", 'Message', "");
        try
            raw = run_ccsds_tm_evaluation(caseDef.Params);
            actual = localDecodeResult(raw);
        catch ME
            executionError.Identifier = string(ME.identifier);
            executionError.Message = string(ME.message);
        end

        verdict = reg_evaluate_result(actual, caseDef.Expected, executionError);
        state.Results(k) = localFinishRecord(state.Results(k), actual, ...
            verdict, toc(timer));
        state.UpdatedAt = localTimestamp();
        reg_save_checkpoint(checkpointPath, state);
        localWriteSummary(summaryPath, state.Results);

        if opts.Verbose
            fprintf('[%s] BER=%g Lock=%.1f%% FER=%g time=%.1fs\n', ...
                char(verdict.Status), state.Results(k).BER, ...
                100*state.Results(k).LockRate, state.Results(k).FER, ...
                state.Results(k).ElapsedTime);
            if strlength(state.Results(k).FailedChecks) > 0
                fprintf('  %s\n', char(state.Results(k).FailedChecks));
            end
        end
    end

    T = localResultsTable(state.Results);
    localWriteSummary(summaryPath, state.Results);

    if opts.Verbose
        terminal = ~ismember(T.Status, ["PENDING","RUNNING"]);
        fprintf('\n[%s] PASS=%d FAIL_METRIC=%d ERROR=%d PENDING=%d\n', ...
            char(suiteName), nnz(T.Pass), nnz(T.Status == "FAIL_METRIC"), ...
            nnz(ismember(T.Status, ["ERROR","UNEXPECTED_PASS"])), ...
            nnz(~terminal));
        fprintf('Checkpoint: %s\n', checkpointPath);
        fprintf('Summary   : %s\n', summaryPath);
    end

    if opts.FailOnFailure
        failed = ismember(T.Status, ["FAIL_METRIC","ERROR","UNEXPECTED_PASS"]);
        assert(~any(failed), 'reg_run_cases:SuiteFailed', ...
            '%s contains %d failed cases.', char(suiteName), nnz(failed));
    end
end

function opts = localOptions(suiteName, thisDir, userOpts)
    pythonDir = fileparts(thisDir);
    srcDir = fileparts(pythonDir);
    repoRoot = fileparts(srcDir);
    defaults = struct( ...
        'OutputDir', '', ...
        'RunId', char(suiteName + "_" + string(datestr(now, 'yyyymmdd_HHMMSS'))), ...
        'PlanVersion', "1", ...
        'Resume', true, ...
        'MaxNewCases', Inf, ...
        'RerunFailed', false, ...
        'BaseSeed', 1, ...
        'SeedMode', "caseIndex", ...
        'CaseIds', strings(0,1), ...
        'DryRun', false, ...
        'FailOnFailure', false, ...
        'Verbose', true);
    opts = defaults;
    names = fieldnames(userOpts);
    for k = 1:numel(names)
        opts.(names{k}) = userOpts.(names{k});
    end

    if isempty(opts.OutputDir)
        opts.OutputDir = fullfile(repoRoot, 'artifacts', 'ccsds', ...
            char(suiteName), char(string(opts.RunId)));
    end
    opts.RepoRoot = repoRoot;
    opts.OutputDir = char(opts.OutputDir);
    opts.PlanVersion = string(opts.PlanVersion);
    opts.Resume = logical(opts.Resume);
    opts.RerunFailed = logical(opts.RerunFailed);
    opts.DryRun = logical(opts.DryRun);
    opts.FailOnFailure = logical(opts.FailOnFailure);
    opts.Verbose = logical(opts.Verbose);
    opts.BaseSeed = round(double(opts.BaseSeed));
    seedModeKey = regexprep(lower(string(opts.SeedMode)), '[^a-z0-9]', '');
    if seedModeKey == "caseindex"
        opts.SeedMode = "caseIndex";
    elseif seedModeKey == "pairedchannelprofile"
        opts.SeedMode = "pairedChannelProfile";
    else
        error('reg_run_cases:InvalidSeedMode', ...
            ['SeedMode must be "caseIndex" or ', ...
             '"pairedChannelProfile"; received "%s".'], ...
            char(string(opts.SeedMode)));
    end
    opts.MaxNewCases = double(opts.MaxNewCases);
    if ~isfinite(opts.MaxNewCases)
        opts.MaxNewCases = Inf;
    else
        opts.MaxNewCases = max(0, round(opts.MaxNewCases));
    end
end

function seed = localCaseSeed(caseDef, opts, caseIndex)
    if string(opts.SeedMode) == "caseIndex"
        seed = opts.BaseSeed + caseIndex - 1;
        return;
    end

    meta = caseDef.Meta;
    required = {'DataPathMode','Modulation','Coding','Rate', ...
        'RandomizerEnabled','RandomizerFECPosition'};
    parts = strings(1, numel(required));
    for k = 1:numel(required)
        name = required{k};
        if ~isstruct(meta) || ~isfield(meta, name)
            error('reg_run_cases:MissingPairedSeedMetadata', ...
                ['SeedMode="pairedChannelProfile" requires case Meta.%s. ', ...
                 'CaseId="%s".'], name, char(string(caseDef.Id)));
        end
        parts(k) = string(name) + "=" + localSeedValueText(meta.(name));
    end
    seedKey = strjoin(parts, "|");
    seed = localStableTextSeed(opts.BaseSeed, seedKey);
end

function text = localSeedValueText(value)
    if ischar(value) || isstring(value)
        text = lower(strtrim(string(value)));
    elseif islogical(value) && isscalar(value)
        text = string(double(value));
    elseif isnumeric(value) && isscalar(value)
        text = string(value);
    else
        error('reg_run_cases:InvalidPairedSeedMetadata', ...
            'Paired-seed metadata values must be scalar text, logical, or numeric.');
    end
end

function seed = localStableTextSeed(baseSeed, seedKey)
    % Keep the result in a range accepted by rng(...,'twister') while
    % remaining stable across MATLAB sessions and case-plan subsets.
    modulus = 2147483647;
    bytes = double(unicode2native(char(seedKey), 'UTF-8'));
    hashValue = 0;
    for k = 1:numel(bytes)
        hashValue = mod(hashValue * 131 + bytes(k), modulus);
    end
    seed = round(mod(double(baseSeed) + hashValue, modulus));
end

function state = localNewState(suiteName, cases, opts)
    records = repmat(localEmptyRecord(), numel(cases), 1);
    for k = 1:numel(cases)
        records(k).CaseId = string(cases(k).Id);
        records(k).Name = string(cases(k).Name);
        records(k).Category = string(cases(k).Category);
    end
    state = struct( ...
        'SchemaVersion', 1, ...
        'CheckpointStorage', "metricsOnly", ...
        'PlanVersion', string(opts.PlanVersion), ...
        'SuiteName', string(suiteName), ...
        'RunId', string(opts.RunId), ...
        'OutputDir', string(opts.OutputDir), ...
        'StartedAt', localTimestamp(), ...
        'UpdatedAt', localTimestamp(), ...
        'MATLABVersion', string(version), ...
        'GitCommit', localGitCommit(opts.RepoRoot), ...
        'Cases', cases, ...
        'Results', records);
end

function record = localEmptyRecord()
    record = struct( ...
        'CaseId', "", ...
        'Name', "", ...
        'Category', "", ...
        'Status', "PENDING", ...
        'Pass', false, ...
        'Success', false, ...
        'Seed', NaN, ...
        'BER', NaN, ...
        'LockRate', NaN, ...
        'FER', NaN, ...
        'MER_dB', NaN, ...
        'EVM_post_pct', NaN, ...
        'CountedFrames', NaN, ...
        'MatchedFrames', NaN, ...
        'AcquisitionFrames', NaN, ...
        'ResidualCFO_Hz', NaN, ...
        'WaveformDuration_s', NaN, ...
        'ElapsedTime', NaN, ...
        'FailedChecks', "", ...
        'ErrorIdentifier', "", ...
        'ErrorMessage', "", ...
        'StartedAt', "", ...
        'FinishedAt', "", ...
        'Actual', struct());
    railFields = localRailResultFields();
    for k = 1:numel(railFields)
        record.(railFields{k}) = NaN;
    end
    decisionFields = localDecisionNumericResultFields();
    for k = 1:numel(decisionFields)
        record.(decisionFields{k}) = NaN;
    end
    record.SplitReceiverStructureSelectionMethod = "";
    record.UQPSKSymSkipSelectionMethod = "";
end

function record = localStartRecord(record, seed)
    record.Status = "RUNNING";
    record.Pass = false;
    record.Success = false;
    record.Seed = seed;
    record.FailedChecks = "";
    record.ErrorIdentifier = "";
    record.ErrorMessage = "";
    record.StartedAt = localTimestamp();
    record.FinishedAt = "";
    record.Actual = struct();
end

function record = localFinishRecord(record, actual, verdict, elapsed)
    record.Status = string(verdict.Status);
    record.Pass = logical(verdict.Pass);
    record.Success = logical(verdict.Success);
    record.BER = localNumeric(actual, 'BER', NaN);
    record.LockRate = localNumeric(actual, 'LockRate', NaN);
    record.FER = localNumeric(actual, 'FER', ...
        localNumeric(actual, 'FrameErrorRate', NaN));
    record.MER_dB = localNumeric(actual, 'MER_dB', NaN);
    record.EVM_post_pct = localNumeric(actual, 'EVM_post_pct', NaN);
    record.CountedFrames = localNumeric(actual, 'CountedFrames', NaN);
    record.MatchedFrames = localNumeric(actual, 'MatchedFrames', NaN);
    record.AcquisitionFrames = localNumeric(actual, 'AcquisitionFrames', NaN);
    record.ResidualCFO_Hz = localNumeric(actual, 'ResidualCFO_Hz', NaN);
    record.WaveformDuration_s = localWaveformDuration(actual);
    railFields = localRailResultFields();
    for k = 1:numel(railFields)
        name = railFields{k};
        record.(name) = localNumeric(actual, name, NaN);
    end
    decisionFields = localDecisionNumericResultFields();
    for k = 1:numel(decisionFields)
        name = decisionFields{k};
        record.(name) = localNumeric(actual, name, NaN);
    end
    record.SplitReceiverStructureSelectionMethod = localText( ...
        actual, 'SplitReceiverStructureSelectionMethod', "");
    record.UQPSKSymSkipSelectionMethod = localText( ...
        actual, 'UQPSKSymSkipSelectionMethod', "");
    record.ElapsedTime = elapsed;
    record.FailedChecks = string(verdict.FailedChecks);
    record.ErrorIdentifier = string(verdict.ErrorIdentifier);
    record.ErrorMessage = string(verdict.ErrorMessage);
    record.FinishedAt = localTimestamp();
    % The verdict has already consumed the full result. Keeping it here
    % would persist large spectra, constellations, and pipeline arrays once
    % per case and make every checkpoint rewrite progressively slower.
    record.Actual = struct();
end

function T = localResultsTable(records)
    n = numel(records);
    T = table( ...
        strings(n,1), strings(n,1), strings(n,1), strings(n,1), ...
        false(n,1), false(n,1), nan(n,1), nan(n,1), nan(n,1), ...
        nan(n,1), nan(n,1), nan(n,1), nan(n,1), nan(n,1), ...
        nan(n,1), nan(n,1), strings(n,1), strings(n,1), ...
        strings(n,1), strings(n,1), strings(n,1), ...
        'VariableNames', {'CaseId','Name','Category','Status','Pass','Success', ...
        'Seed','BER','LockRate','FER','MER_dB','EVM_post_pct', ...
        'CountedFrames','MatchedFrames','AcquisitionFrames','ElapsedTime', ...
        'FailedChecks','ErrorIdentifier','ErrorMessage','StartedAt','FinishedAt'});
    railFields = localRailResultFields();
    for j = 1:numel(railFields)
        T.(railFields{j}) = nan(n,1);
    end
    decisionFields = localDecisionNumericResultFields();
    for j = 1:numel(decisionFields)
        T.(decisionFields{j}) = nan(n,1);
    end
    T.SplitReceiverStructureSelectionMethod = strings(n,1);
    T.UQPSKSymSkipSelectionMethod = strings(n,1);
    for k = 1:n
        names = T.Properties.VariableNames;
        for j = 1:numel(names)
            T.(names{j})(k) = records(k).(names{j});
        end
    end
end

function names = localRailResultFields()
    names = { ...
        'I_BER','I_LockRate','I_FER','I_BitErrors','I_BitsCompared', ...
        'I_FrameErrors','I_CountedFrames','I_MatchedFrames', ...
        'I_DecodedFrames','I_AcquisitionFrames', ...
        'I_PredecoderBER','I_PredecoderOffset','I_PredecoderPolarity', ...
        'I_PredecoderBitErrors','I_PredecoderBitsCompared', ...
        'Q_BER','Q_LockRate','Q_FER','Q_BitErrors','Q_BitsCompared', ...
        'Q_FrameErrors','Q_CountedFrames','Q_MatchedFrames', ...
        'Q_DecodedFrames','Q_AcquisitionFrames', ...
        'Q_PredecoderBER','Q_PredecoderOffset','Q_PredecoderPolarity', ...
        'Q_PredecoderBitErrors','Q_PredecoderBitsCompared'};
end

function names = localDecisionNumericResultFields()
    names = { ...
        'SplitReceiverIQPhase', 'UQPSKSymSkip', ...
        'SplitReceiverStructureScore', ...
        'SplitReceiverTMValidFrames', ...
        'SplitReceiverTMMinValidFrames', ...
        'SplitReceiverTMMaxCounterRun', ...
        'SplitReceiverTMOrientationScore'};
end

function [records, changed] = localUpgradeResultRecords(records)
    defaults = localEmptyRecord();
    names = fieldnames(defaults);
    changed = false;
    for j = 1:numel(names)
        name = names{j};
        if isfield(records, name)
            continue;
        end
        defaultValue = defaults.(name);
        for k = 1:numel(records)
            records(k).(name) = defaultValue;
        end
        changed = true;
    end
end

function [records, compactedCount] = localCompactResultRecords(records)
    compactedCount = 0;
    for k = 1:numel(records)
        actual = records(k).Actual;
        if ~isstruct(actual) || ~isscalar(actual)
            if ~isempty(actual)
                compactedCount = compactedCount + 1;
            end
            records(k).Actual = struct();
            continue;
        end

        if isnan(records(k).ResidualCFO_Hz)
            records(k).ResidualCFO_Hz = ...
                localNumeric(actual, 'ResidualCFO_Hz', NaN);
        end
        if isnan(records(k).WaveformDuration_s)
            records(k).WaveformDuration_s = localWaveformDuration(actual);
        end
        decisionFields = localDecisionNumericResultFields();
        for j = 1:numel(decisionFields)
            name = decisionFields{j};
            if isnan(records(k).(name))
                records(k).(name) = localNumeric(actual, name, NaN);
            end
        end
        if strlength(string(records(k).SplitReceiverStructureSelectionMethod)) == 0
            records(k).SplitReceiverStructureSelectionMethod = localText( ...
                actual, 'SplitReceiverStructureSelectionMethod', "");
        end
        if strlength(string(records(k).UQPSKSymSkipSelectionMethod)) == 0
            records(k).UQPSKSymSkipSelectionMethod = localText( ...
                actual, 'UQPSKSymSkipSelectionMethod', "");
        end
        if ~isempty(fieldnames(actual))
            compactedCount = compactedCount + 1;
            records(k).Actual = struct();
        end
    end
end

function localWriteSummary(summaryPath, records)
    try
        T = localResultsTable(records);
        outputDir = fileparts(summaryPath);
        temporaryPath = [tempname(outputDir), '.csv'];
        cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
        writetable(T, temporaryPath);
        [ok, message] = movefile(temporaryPath, summaryPath, 'f');
        if ~ok
            warning('reg_run_cases:SummaryMoveFailed', ...
                'Could not replace summary "%s": %s', summaryPath, message);
        end
        clear cleanup;
    catch ME
        warning('reg_run_cases:SummaryWriteFailed', ...
            'Checkpoint is safe, but CSV summary write failed: %s', ME.message);
    end
end

function localValidateCases(cases)
    if ~isstruct(cases) || isempty(cases)
        error('reg_run_cases:InvalidCases', 'cases must be a nonempty struct array.');
    end
    required = {'Id','Name','Category','Params','Expected','Meta'};
    for k = 1:numel(required)
        if ~isfield(cases, required{k})
            error('reg_run_cases:InvalidCases', ...
                'Every case must contain field "%s".', required{k});
        end
    end
    ids = string({cases.Id});
    if any(strlength(ids) == 0) || numel(unique(ids)) ~= numel(ids)
        error('reg_run_cases:InvalidCaseIds', ...
            'Case IDs must be nonempty and unique.');
    end
end

function localValidateResumeState(state, suiteName, cases, caseIds, planVersion)
    if ~isfield(state, 'SchemaVersion') || state.SchemaVersion ~= 1
        error('reg_run_cases:CheckpointSchemaMismatch', ...
            'Checkpoint schema is not supported.');
    end
    if string(state.SuiteName) ~= string(suiteName)
        error('reg_run_cases:SuiteMismatch', ...
            'Checkpoint suite "%s" does not match "%s".', ...
            string(state.SuiteName), string(suiteName));
    end
    if string(state.PlanVersion) ~= string(planVersion)
        error('reg_run_cases:PlanVersionMismatch', ...
            ['Checkpoint PlanVersion="%s", current="%s". Choose a new ' ...
             'OutputDir/RunId for a changed plan.'], ...
            string(state.PlanVersion), string(planVersion));
    end
    storedIds = string({state.Cases.Id})';
    if ~isequal(storedIds, caseIds)
        error('reg_run_cases:CasePlanMismatch', ...
            ['Checkpoint case IDs/order differ from the current plan. ' ...
             'Choose a new OutputDir/RunId.']);
    end
    if ~isequaln(state.Cases, cases)
        error('reg_run_cases:CaseDefinitionMismatch', ...
            ['Checkpoint parameters, thresholds, or metadata differ from the ' ...
             'current cases. Choose a new OutputDir/RunId.']);
    end
end

function raw = localDecodeResult(raw)
    if ischar(raw) || isstring(raw)
        raw = jsondecode(char(raw));
    end
    if ~isstruct(raw) || ~isscalar(raw)
        error('reg_run_cases:UnexpectedResult', ...
            'run_ccsds_tm_evaluation must return one struct or JSON object.');
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

function value = localText(s, name, defaultValue)
    value = string(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = string(s.(name));
    end
end

function value = localWaveformDuration(actual)
    value = NaN;
    if isstruct(actual) && isscalar(actual) && ...
            isfield(actual, 'stats') && isstruct(actual.stats) && ...
            isscalar(actual.stats)
        value = localNumeric(actual.stats, 'HWaveformDuration_s', NaN);
    end
end

function timestamp = localTimestamp()
    timestamp = string(datestr(now, 'yyyy-mm-ddTHH:MM:SS.FFF'));
end

function commit = localGitCommit(repoRoot)
    commit = "unknown";
    try
        command = sprintf('git -C "%s" rev-parse HEAD', char(repoRoot));
        [status, text] = system(command);
        if status == 0
            commit = string(strtrim(text));
        end
    catch
    end
end

function localDeleteIfPresent(pathValue)
    if exist(pathValue, 'file') == 2
        delete(pathValue);
    end
end
