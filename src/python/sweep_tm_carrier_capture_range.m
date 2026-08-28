function [T, S] = sweep_tm_carrier_capture_range(userOpts)
%SWEEP_TM_CARRIER_CAPTURE_RANGE Measure static carrier acquisition range.
%   Runs independent main-receiver cases over a configured CFO grid.  This
%   is intentionally separate from the full modulation/coding/H matrix so
%   CFO acquisition failures are not confused with equalizer failures.
%
%   The device manual specifies a nominal +/-2 MHz carrier capture range.
%   The default grid therefore includes both endpoints.  At low symbol
%   rates some M-th-power estimators have a smaller unambiguous normalized
%   range; the result table records the actual pass/fail boundary.

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);
    opts = localDefaults();
    opts = localMerge(opts, userOpts);

    if isempty(opts.outputDir)
        repoRoot = fileparts(fileparts(thisDir));
        opts.outputDir = fullfile(repoRoot, 'artifacts', 'ccsds', ...
            'carrier_capture_range', ...
            ['carrier_capture_' datestr(now,'yyyymmdd_HHMMSS')]);
    end
    if ~isfolder(opts.outputDir)
        mkdir(opts.outputDir);
    end
    checkpointPath = fullfile(opts.outputDir, 'carrier_capture_checkpoint.mat');
    csvPath = fullfile(opts.outputDir, 'carrier_capture_sweep.csv');

    T = table();
    if opts.Resume && isfile(checkpointPath)
        loaded = load(checkpointPath, 'T');
        if isfield(loaded, 'T')
            T = loaded.T;
        end
    end

    scenarios = localScenarios(opts);
    total = numel(scenarios) * numel(opts.modTypes) * numel(opts.cfoHz);
    newCases = 0;
    ordinal = 0;
    for iScenario = 1:numel(scenarios)
        sc = scenarios(iScenario);
        for iMod = 1:numel(opts.modTypes)
            modType = char(opts.modTypes{iMod});
            for iCFO = 1:numel(opts.cfoHz)
                ordinal = ordinal + 1;
                cfoHz = double(opts.cfoHz(iCFO));
                key = sprintf('%s|%s|%+.3f', sc.Name, modType, cfoHz);
                if ~isempty(T) && any(string(T.CaseKey) == string(key))
                    continue;
                end
                if newCases >= opts.MaxNewCases
                    break;
                end

                fprintf('\n[capture %03d/%03d] %s | %s | CFO=%+.3f kHz\n', ...
                    ordinal, total, sc.Name, modType, cfoHz/1e3);
                p = localParams(opts, sc, modType, cfoHz);
                t0 = tic;
                try
                    rng(opts.randomSeed + ordinal, 'twister');
                    [m,~] = run_ccsds_tm_evaluation(p);
                    if isfield(m,'success') && ~logical(m.success)
                        ber = NaN; lockPct = NaN; fer = NaN; evm = NaN;
                        mer = NaN; residual = NaN; acquisitionFrames = NaN;
                        ok = false;
                        status = "ERROR";
                        errorId = string(localTextField(m, ...
                            'errorIdentifier','run_ccsds_tm_evaluation:Failed'));
                        errorMessage = string(localTextField(m, ...
                            'errorMessage',localTextField(m,'error','')));
                    else
                        ber = localField(m,'BER',NaN);
                        lockPct = 100*localField(m,'LockRate',NaN);
                        fer = localField(m,'FER',NaN);
                        evm = localField(m,'EVM_post_pct',NaN);
                        mer = localField(m,'MER_dB',NaN);
                        residual = localField(m,'ResidualCFO_Hz',NaN);
                        acquisitionFrames = localField(m,'AcquisitionFrames',NaN);
                        matchedFrames = localField(m,'MatchedFrames',NaN);
                        % A capture-range test must not reject a receiver
                        % merely because its finite acquisition transient is
                        % included in a very short average LockRate. Require
                        % good post-warm-up data, a bounded acquisition time,
                        % and enough matched frames. The optional strict flag
                        % restores the historical average-lock verdict.
                        ok = isfinite(ber) && ber <= opts.maxGoodBER && ...
                            isfinite(fer) && fer <= opts.maxGoodFER && ...
                            isfinite(acquisitionFrames) && ...
                            acquisitionFrames <= opts.maxAcquisitionFrames && ...
                            isfinite(matchedFrames) && ...
                            matchedFrames >= opts.minMatchedFrames;
                        if opts.requireAverageLockRateForPass
                            ok = ok && isfinite(lockPct) && ...
                                lockPct >= opts.minGoodLockPct;
                        end
                        status = string(localIf(ok,'PASS','FAIL_METRIC'));
                        errorId = "";
                        errorMessage = "";
                    end
                catch ME
                    ber = NaN; lockPct = NaN; fer = NaN; evm = NaN;
                    mer = NaN; residual = NaN; acquisitionFrames = NaN;
                    ok = false;
                    status = "ERROR";
                    errorId = string(ME.identifier);
                    errorMessage = string(ME.message);
                end

                row = table(string(key), string(sc.Name), string(modType), ...
                    cfoHz, double(opts.carrierCaptureRangeHz), ...
                    ber, lockPct, fer, evm, mer, residual, ...
                    acquisitionFrames, logical(ok), status, errorId, ...
                    errorMessage, toc(t0), ...
                    'VariableNames', {'CaseKey','Scenario','ModType', ...
                    'RequestedCFO_Hz','ConfiguredCaptureRange_Hz', ...
                    'BER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
                    'ResidualCFO_Hz','AcquisitionFrames','Passed','Status', ...
                    'ErrorIdentifier','ErrorMessage','Runtime_s'});
                if isempty(T)
                    T = row;
                else
                    T = [T; row]; %#ok<AGROW>
                end
                newCases = newCases + 1;
                save(checkpointPath, 'T', 'opts');
                writetable(T, csvPath);
            end
            if newCases >= opts.MaxNewCases, break; end
        end
        if newCases >= opts.MaxNewCases, break; end
    end

    S = localSummary(T);
    summaryPath = fullfile(opts.outputDir, 'carrier_capture_summary.csv');
    writetable(S, summaryPath);
    fprintf('\n===== Static carrier capture range result =====\n');
    fprintf('CSV     : %s\n', csvPath);
    fprintf('Summary : %s\n', summaryPath);
    if ~isempty(S), disp(S); end
end

function opts = localDefaults()
    opts = struct();
    opts.outputDir = '';
    opts.Resume = true;
    opts.MaxNewCases = Inf;
    opts.modTypes = { ...
        'BPSK','QPSK','OQPSK','UQPSK','8PSK', ...
        '16QAM','32QAM','16APSK','32APSK','MSK','GMSK'};
    opts.cfoHz = [-2e6 -1.5e6 -1e6 -500e3 -200e3 -50e3 0 ...
                  50e3 200e3 500e3 1e6 1.5e6 2e6];
    opts.carrierCaptureRangeHz = 2e6;
    opts.includeNormalizedH = false;
    opts.normalizedHName = 'std4_ITU_P681';
    opts.normalizedHFile = ...
        'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat';
    opts.symbolRate = 10e6;
    opts.sps = 8;
    opts.channelCoding = 'none';
    opts.NumBytesInTransferFrame = 256;
    opts.RandomizerEnabled = false;
    opts.RandomizerFECPosition = 'afterEncoding';
    opts.DataPathMode = 'single';
    opts.berWarmUpFrames = 6;
    opts.berFrames = 16;
    opts.noiseMode = 'psd';
    opts.noisePSDdBmHz = -115.3;
    opts.inputLevelDbm = -10;
    opts.maxGoodBER = 1e-5;
    opts.minGoodLockPct = 90;
    opts.maxGoodFER = 0;
    opts.maxAcquisitionFrames = 12;
    opts.minMatchedFrames = 8;
    opts.requireAverageLockRateForPass = false;
    opts.randomSeed = 20260824;
    opts.debugCarrierRecovery = false;
    opts.enableUQPSKFFTCoarseCFO = true;
    opts.uqpskCFOFFTLen = 131072;
    opts.PilotlessAPSKCarrierRecovery = struct();
end

function scenarios = localScenarios(opts)
    scenarios = struct('Name','NoH','EnableH',false,'File','');
    if opts.includeNormalizedH
        scenarios(end+1) = struct( ... %#ok<AGROW>
            'Name',['normH_' char(opts.normalizedHName)], ...
            'EnableH',true,'File',char(opts.normalizedHFile));
    end
end

function p = localParams(opts, sc, modType, cfoHz)
    p = struct( ...
        'modType',modType, ...
        'symbolRate',opts.symbolRate, ...
        'sps',opts.sps, ...
        'channelCoding',opts.channelCoding, ...
        'NumBytesInTransferFrame',opts.NumBytesInTransferFrame, ...
        'hasASM',true, ...
        'RandomizerEnabled',logical(opts.RandomizerEnabled), ...
        'RandomizerFECPosition',opts.RandomizerFECPosition, ...
        'DataPathMode',opts.DataPathMode, ...
        'cfo',cfoHz, ...
        'phaseOffset',0, ...
        'delay',0, ...
        'carrierCaptureRangeHz',opts.carrierCaptureRangeHz, ...
        'berWarmUpFrames',opts.berWarmUpFrames, ...
        'berFrames',opts.berFrames, ...
        'excludeBERWarmUpFrames',true, ...
        'noisePlacement','afterChannel', ...
        'noiseMode',opts.noiseMode, ...
        'noisePSDdBmHz',opts.noisePSDdBmHz, ...
        'inputLevelDbm',opts.inputLevelDbm, ...
        'showFigures',false, ...
        'debugCarrierRecovery',logical(opts.debugCarrierRecovery), ...
        'debugUQPSK',logical(opts.debugCarrierRecovery), ...
        'debugPilotlessAPSK',logical(opts.debugCarrierRecovery), ...
        'enableUQPSKFFTCoarseCFO',logical(opts.enableUQPSKFFTCoarseCFO), ...
        'uqpskMaxCFOHz',opts.carrierCaptureRangeHz, ...
        'uqpskCFOFFTLen',opts.uqpskCFOFFTLen, ...
        'HasTMAPSKPilots',false, ...
        'APSKReceiverMode','pilotless');
    if isstruct(opts.PilotlessAPSKCarrierRecovery) && ...
            ~isempty(fieldnames(opts.PilotlessAPSKCarrierRecovery))
        p.PilotlessAPSKCarrierRecovery = ...
            opts.PilotlessAPSKCarrierRecovery;
    end
    if sc.EnableH
        p.enableHChannel = true;
        p.channelFilePath = sc.File;
        p.HMode = 'h_matrix_file';
        p.normalizeHChannel = true;
        p.enableEqualizer = true;
        p.equalizerMode = 'blind-cma-lms';
        p.channelOutOfRangeMode = 'wrap';
    else
        p.enableHChannel = false;
    end
end

function S = localSummary(T)
    if isempty(T)
        S = table();
        return;
    end
    groups = unique(T(:, {'Scenario','ModType'}), 'rows', 'stable');
    rows = cell(height(groups), 7);
    for i = 1:height(groups)
        mask = string(T.Scenario) == string(groups.Scenario(i)) & ...
            string(T.ModType) == string(groups.ModType(i));
        sub = T(mask,:);
        passedCFO = sub.RequestedCFO_Hz(sub.Passed);
        if isempty(passedCFO)
            minPass = NaN; maxPass = NaN; zeroPass = false;
        else
            minPass = min(passedCFO);
            maxPass = max(passedCFO);
            zeroPass = any(passedCFO == 0);
        end
        rows(i,:) = {groups.Scenario(i), groups.ModType(i), ...
            height(sub), nnz(sub.Passed), minPass, maxPass, zeroPass};
    end
    S = cell2table(rows, 'VariableNames', {'Scenario','ModType', ...
        'TestedPoints','PassedPoints','MinimumPassedCFO_Hz', ...
        'MaximumPassedCFO_Hz','ZeroCFOPassed'});
end

function opts = localMerge(opts, userOpts)
    if ~isstruct(userOpts)
        error('sweep_tm_carrier_capture_range:InvalidOptions', ...
            'userOpts must be a struct.');
    end
    names = fieldnames(userOpts);
    for i = 1:numel(names)
        opts.(names{i}) = userOpts.(names{i});
    end
end

function v = localField(s, name, defaultValue)
    v = defaultValue;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        v = double(s.(name));
    end
end

function v = localTextField(s, name, defaultValue)
    v = defaultValue;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        v = char(string(s.(name)));
    end
end

function out = localIf(condition, yesValue, noValue)
    if condition, out = yesValue; else, out = noValue; end
end
