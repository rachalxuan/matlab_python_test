function T = run_smoke_regression(userOpts)
%RUN_SMOKE_REGRESSION Run the formal 20-case resumable smoke suite.
%
% List cases only:
%   T = run_smoke_regression(struct('DryRun',true));
%
% Run one short case:
%   opts = struct('RunId','smoke_check', ...
%       'CaseIds',"smoke.qpsk.none.single",'FailOnFailure',true);
%   T = run_smoke_regression(opts);
%
% Run/resume the complete suite:
%   opts = struct('RunId','smoke_baseline_v2','Resume',true);
%   T = run_smoke_regression(opts);

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end
    if ~isstruct(userOpts)
        error('run_smoke_regression:InvalidOptions', ...
            'userOpts must be a struct.');
    end

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);
    addpath(fileparts(thisDir));

    opts = struct( ...
        'OutputDir','', ...
        'RunId','smoke_baseline_v3', ...
        'PlanVersion','ccsds-smoke-v3', ...
        'Resume',true, ...
        'MaxNewCases',Inf, ...
        'RerunFailed',false, ...
        'BaseSeed',20260729, ...
        'CaseIds',strings(0,1), ...
        'DryRun',false, ...
        'FailOnFailure',true, ...
        'Verbose',true);
    names = fieldnames(userOpts);
    for k = 1:numel(names)
        if ~isfield(opts, names{k})
            error('run_smoke_regression:UnknownOption', ...
                'Unknown option "%s".', names{k});
        end
        opts.(names{k}) = userOpts.(names{k});
    end

    cases = reg_build_smoke_cases();
    [T, state] = reg_run_cases("smoke", cases, opts);
    T = localAttachMetadata(T, cases);

    if ~opts.DryRun
        summaryPath = fullfile(char(state.OutputDir), 'smoke_summary.csv');
        localWriteTable(T, summaryPath);
    end
end

function T = localAttachMetadata(T, cases)
    n = height(T);
    T.Modulation = strings(n,1);
    T.Coding = strings(n,1);
    T.DataPathMode = strings(n,1);
    T.WaveformMode = strings(n,1);
    for k = 1:n
        T.Modulation(k) = cases(k).Meta.Modulation;
        T.Coding(k) = cases(k).Meta.Coding;
        T.DataPathMode(k) = cases(k).Meta.DataPathMode;
        T.WaveformMode(k) = cases(k).Meta.WaveformMode;
    end
    leading = {'CaseId','Status','Pass','Category','Modulation','Coding', ...
        'DataPathMode','WaveformMode'};
    T = movevars(T, leading, 'Before', 1);
end

function localWriteTable(T, pathValue)
    outputDir = fileparts(pathValue);
    temporaryPath = [tempname(outputDir), '.csv'];
    cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
    writetable(T, temporaryPath);
    [ok, message] = movefile(temporaryPath, pathValue, 'f');
    if ~ok
        warning('run_smoke_regression:SummaryWriteFailed', ...
            'Could not write "%s": %s', pathValue, message);
    end
    clear cleanup;
end

function localDeleteIfPresent(pathValue)
    if exist(pathValue, 'file') == 2
        delete(pathValue);
    end
end
