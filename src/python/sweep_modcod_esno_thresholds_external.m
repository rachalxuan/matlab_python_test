function [results, summary] = sweep_modcod_esno_thresholds_external(userOpts)
%SWEEP_MODCOD_ESNO_THRESHOLDS_EXTERNAL Measure MODCOD Es/N0 thresholds.
%
% This is an external wrapper around run_ccsds_tm_evaluation.  It does not
% modify the evaluator or waveform generator.  The wrapper also hides the
% current interface difference between ordinary-TM and FACM noise input:
%
%   ordinary TM: evaluator snr = requested Es/N0 - 10*log10(sps)
%   FACM:        evaluator snr = requested Es/N0
%
% In both paths noiseMode='measured' is forced so an Es/N0 sweep really
% changes the AWGN level instead of using the evaluator's PSD default.
%
% Quick waterfall screening:
%   [T,S] = sweep_modcod_esno_thresholds_external;
%
% Longer confirmation run:
%   opt = struct('Profile','confirm','TargetBER',1e-6, ...
%                'TargetFER',1e-3,'MinLockRate',0.99);
%   [T,S] = sweep_modcod_esno_thresholds_external(opt);
%
% Run selected modes only:
%   opt = struct('OnlyModes',{{'QPSK_3_4','8PSK_2_3'}});
%   [T,S] = sweep_modcod_esno_thresholds_external(opt);
%
% One-point smoke test without writing CSV files:
%   opt = struct('OnlyModes',{{'QPSK_3_4'}},'EsNoOverride',8, ...
%       'BERWarmUpFrames',1,'BERFrames',2,'WriteFiles',false);
%   [T,S] = sweep_modcod_esno_thresholds_external(opt);
%
% Important:
% - The default five cases are implementation profiles supported by the
%   current project.  BPSK/QPSK/8PSK use ordinary TM convolutional coding;
%   16APSK/32APSK use CCSDS 131.2 FACM formats 14 and 18.  They are not one
%   single CCSDS waveform family.
% - A screening run locates the waterfall.  A contractual BER/FER claim
%   still requires enough bits/frames and confidence-interval reporting.

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end
    if ~isstruct(userOpts)
        error('sweep_modcod_esno_thresholds_external:InvalidOptions', ...
            'userOpts must be a struct.');
    end

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);

    cfg = localConfig(thisDir, userOpts);
    cases = localCases();
    cases = localSelectCases(cases, cfg.OnlyModes);

    rows = repmat(localEmptyRow(), 0, 1);
    fprintf('\n================ MODCOD Es/N0 SWEEP ================\n');
    fprintf('Profile=%s, target BER<=%.3g, FER<=%.3g, lock>=%.2f%%\n', ...
        cfg.Profile, cfg.TargetBER, cfg.TargetFER, 100*cfg.MinLockRate);
    fprintf('Main evaluator is read-only; AWGN mode is forced to measured.\n');

    for iCase = 1:numel(cases)
        c = cases(iCase);
        esNoGrid = c.EsNoGrid;
        if ~isempty(cfg.EsNoOverride)
            esNoGrid = double(cfg.EsNoOverride(:).');
        elseif strcmpi(cfg.Profile, 'confirm')
            esNoGrid = localConfirmGrid(c);
        end

        for iPoint = 1:numel(esNoGrid)
            requestedEsNo = esNoGrid(iPoint);
            p = localEvaluationParams(c, cfg, requestedEsNo);
            rng(cfg.BaseSeed + iCase, 'twister');

            if cfg.Verbose
                fprintf('\n[%s | requested Es/N0 = %.2f dB | main snr = %.2f dB]\n', ...
                    c.Id, requestedEsNo, p.snr);
            end

            row = localEmptyRow();
            row.ModeId = string(c.Id);
            row.Modulation = string(c.Modulation);
            row.WaveformMode = string(c.WaveformMode);
            row.Coding = string(c.CodingLabel);
            row.CodeRate = c.ActualCodeRate;
            row.ACMFormat = c.ACMFormat;
            row.SymbolRate_MBd = cfg.SymbolRate/1e6;
            row.SPS = cfg.SamplesPerSymbol;
            row.RequestedEsNo_dB = requestedEsNo;
            row.MainSnrInput_dB = p.snr;

            try
                raw = run_ccsds_tm_evaluation(p);
                out = localDecodeOutput(raw);
                row.Success = localLogicalField(out, 'success', true);
                row.ErrorMsg = localTextField(out, 'errorMsg', "");
                row.BER = localNumericField(out, 'BER', NaN);
                row.FER = localNumericField(out, 'FER', NaN);
                row.LockRate = localNumericField(out, 'LockRate', NaN);
                row.FrameErrors = localNumericField(out, 'FrameErrors', NaN);
                row.CountedFrames = localNumericField(out, 'CountedFrames', NaN);
                row.NoiseEquivalentSNR_dB = ...
                    localNumericField(out, 'NoiseEquivalentSNR_dB', NaN);
            catch ME
                row.Success = false;
                row.ErrorMsg = string(ME.message);
            end

            row.PassBER = row.Success && isfinite(row.BER) && ...
                row.BER <= cfg.TargetBER;
            % FACM currently does not return FER.  In that path BER and
            % lock rate screen the threshold, and FER remains NaN.
            row.PassFER = row.Success && ...
                (~isfinite(row.FER) || row.FER <= cfg.TargetFER);
            row.PassLock = row.Success && isfinite(row.LockRate) && ...
                row.LockRate >= cfg.MinLockRate;
            row.Pass = row.PassBER && row.PassFER && row.PassLock;
            rows(end+1,1) = row; %#ok<AGROW>

            fprintf('  BER=%9.3g  FER=%9.3g  lock=%6.2f%%  pass=%d\n', ...
                row.BER, row.FER, 100*row.LockRate, row.Pass);
            if ~row.Success
                fprintf(2, '  ERROR: %s\n', row.ErrorMsg);
            end
        end
    end

    results = struct2table(rows);
    if ~isempty(results)
        results = sortrows(results, {'ModeId','RequestedEsNo_dB'});
    end
    summary = localThresholdSummary(results, cfg);

    fprintf('\n================ THRESHOLD SUMMARY ================\n');
    disp(summary);
    fprintf(['A finite value is the first tested Es/N0 for which that point ', ...
        'and every higher tested point pass.\n']);

    if cfg.WriteFiles
        if ~exist(cfg.OutputDir, 'dir')
            mkdir(cfg.OutputDir);
        end
        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        resultsPath = fullfile(cfg.OutputDir, ...
            sprintf('modcod_esno_points_%s.csv', stamp));
        summaryPath = fullfile(cfg.OutputDir, ...
            sprintf('modcod_esno_summary_%s.csv', stamp));
        writetable(results, resultsPath);
        writetable(summary, summaryPath);
        fprintf('Points CSV : %s\n', resultsPath);
        fprintf('Summary CSV: %s\n', summaryPath);
    end
end

function cfg = localConfig(thisDir, userOpts)
    cfg = struct( ...
        'Profile', 'screen', ...
        'OnlyModes', strings(0,1), ...
        'EsNoOverride', [], ...
        'SymbolRate', 1e6, ...
        'SamplesPerSymbol', 8, ...
        'RolloffFactor', 0.35, ...
        'BERWarmUpFrames', [], ...
        'BERFrames', [], ...
        'FACMWarmUpFrames', [], ...
        'FACMBERFrames', [], ...
        'FACMNumIterations', 10, ...
        'TargetBER', 1e-5, ...
        'TargetFER', 1e-3, ...
        'MinLockRate', 0.99, ...
        'LinkCN0_dBHz', 85.802301894, ...
        'LinkSymbolRate', 20e6, ...
        'UnmodeledLoss_dB', 1, ...
        'RequiredMargin_dB', 3, ...
        'ReferenceDistance_km', 9000, ...
        'BaseSeed', 20260823, ...
        'WriteFiles', true, ...
        'OutputDir', fullfile(thisDir, 'sweep_results', 'modcod_esno_external'), ...
        'Verbose', true);

    names = fieldnames(userOpts);
    for i = 1:numel(names)
        if ~isfield(cfg, names{i})
            error('sweep_modcod_esno_thresholds_external:UnknownOption', ...
                'Unknown option "%s".', names{i});
        end
        cfg.(names{i}) = userOpts.(names{i});
    end

    cfg.Profile = char(lower(string(cfg.Profile)));
    if ~any(strcmp(cfg.Profile, {'screen','confirm'}))
        error('sweep_modcod_esno_thresholds_external:InvalidProfile', ...
            'Profile must be screen or confirm.');
    end
    if isempty(cfg.BERWarmUpFrames)
        cfg.BERWarmUpFrames = 4 + 12*strcmp(cfg.Profile, 'confirm');
    end
    if isempty(cfg.BERFrames)
        cfg.BERFrames = 20 + 180*strcmp(cfg.Profile, 'confirm');
    end
    if isempty(cfg.FACMWarmUpFrames)
        cfg.FACMWarmUpFrames = 7 + 8*strcmp(cfg.Profile, 'confirm');
    end
    if isempty(cfg.FACMBERFrames)
        cfg.FACMBERFrames = 20 + 180*strcmp(cfg.Profile, 'confirm');
    end
    cfg.OnlyModes = string(cfg.OnlyModes(:));
end

function cases = localCases()
    blank = struct( ...
        'Id', '', 'Modulation', '', 'WaveformMode', '', ...
        'CodingLabel', '', 'ConvolutionalCodeRate', '', ...
        'ACMFormat', NaN, 'ActualCodeRate', NaN, ...
        'EsNoGrid', []);
    cases = repmat(blank, 5, 1);

    cases(1) = blank;
    cases(1).Id = 'BPSK_1_2';
    cases(1).Modulation = 'BPSK';
    cases(1).WaveformMode = 'ordinaryTM';
    cases(1).CodingLabel = 'convolutional 1/2';
    cases(1).ConvolutionalCodeRate = '1/2';
    cases(1).ActualCodeRate = 1/2;
    cases(1).EsNoGrid = -4:1:7;

    cases(2) = blank;
    cases(2).Id = 'QPSK_3_4';
    cases(2).Modulation = 'QPSK';
    cases(2).WaveformMode = 'ordinaryTM';
    cases(2).CodingLabel = 'convolutional 3/4';
    cases(2).ConvolutionalCodeRate = '3/4';
    cases(2).ActualCodeRate = 3/4;
    cases(2).EsNoGrid = 0:1:10;

    cases(3) = blank;
    cases(3).Id = '8PSK_2_3';
    cases(3).Modulation = '8PSK';
    cases(3).WaveformMode = 'ordinaryTM';
    cases(3).CodingLabel = 'convolutional 2/3';
    cases(3).ConvolutionalCodeRate = '2/3';
    cases(3).ActualCodeRate = 2/3;
    cases(3).EsNoGrid = 3:1:14;

    cases(4) = blank;
    cases(4).Id = '16APSK_FACM14';
    cases(4).Modulation = '16APSK';
    cases(4).WaveformMode = 'FACM';
    cases(4).CodingLabel = 'CCSDS 131.2 SCCC ACM14';
    cases(4).ACMFormat = 14;
    cases(4).ActualCodeRate = 21358/(4*8100);
    cases(4).EsNoGrid = 5:1:16;

    cases(5) = blank;
    cases(5).Id = '32APSK_FACM18';
    cases(5).Modulation = '32APSK';
    cases(5).WaveformMode = 'FACM';
    cases(5).CodingLabel = 'CCSDS 131.2 SCCC ACM18';
    cases(5).ACMFormat = 18;
    cases(5).ActualCodeRate = 25918/(5*8100);
    cases(5).EsNoGrid = 7:1:19;
end

function cases = localSelectCases(cases, onlyModes)
    if isempty(onlyModes)
        return;
    end
    ids = string({cases.Id});
    missing = onlyModes(~ismember(onlyModes, ids));
    if ~isempty(missing)
        error('sweep_modcod_esno_thresholds_external:UnknownMode', ...
            'Unknown mode id(s): %s', strjoin(missing, ', '));
    end
    cases = cases(ismember(ids, onlyModes));
end

function grid = localConfirmGrid(c)
    switch c.Id
        case 'BPSK_1_2'
            grid = -2.0:0.25:4.0;
        case 'QPSK_3_4'
            grid = 3.0:0.25:7.0;
        case '8PSK_2_3'
            grid = 7.0:0.25:11.5;
        case '16APSK_FACM14'
            grid = 7.0:0.25:13.0;
        case '32APSK_FACM18'
            grid = 9.0:0.25:17.0;
        otherwise
            grid = c.EsNoGrid;
    end
end

function p = localEvaluationParams(c, cfg, requestedEsNo)
    p = struct( ...
        'modType', c.Modulation, ...
        'WaveformMode', c.WaveformMode, ...
        'symbolRate', cfg.SymbolRate, ...
        'sps', cfg.SamplesPerSymbol, ...
        'snr', requestedEsNo, ...
        'noiseMode', 'measured', ...
        'noisePlacement', 'afterChannel', ...
        'cfo', 0, ...
        'phaseOffset', 0, ...
        'delay', 0, ...
        'RolloffFactor', cfg.RolloffFactor, ...
        'hasASM', true, ...
        'RandomizerEnabled', true, ...
        'RandomizerFECPosition', 'afterEncoding', ...
        'DataPathMode', 'single', ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'enableConverterChain', false, ...
        'enableADCEquivalent', false, ...
        'AGCEnabled', false, ...
        'showFigures', false, ...
        'showPipelineFigure', false, ...
        'showPowerFigure', false, ...
        'showDamageBudgetFigure', false, ...
        'berWarmUpFrames', cfg.BERWarmUpFrames, ...
        'berFrames', cfg.BERFrames, ...
        'facmWarmupFrames', cfg.FACMWarmUpFrames, ...
        'facmBERFrames', cfg.FACMBERFrames, ...
        'facmNumIterations', cfg.FACMNumIterations, ...
        'debugFACM', false);

    if strcmpi(c.WaveformMode, 'ordinaryTM')
        p.channelCoding = 'convolutional';
        p.ConvolutionalCodeRate = c.ConvolutionalCodeRate;
        % Ordinary TM currently passes snr straight to awgn(...,'measured').
        p.snr = requestedEsNo - 10*log10(cfg.SamplesPerSymbol);
    else
        p.channelCoding = 'none';
        p.ACMFormat = c.ACMFormat;
        p.acmFormat = c.ACMFormat;
        p.hasPilots = true;
        p.enableFACMEqualizer = false;
        % FACM currently performs the sps conversion inside the evaluator.
        p.snr = requestedEsNo;
    end
end

function out = localDecodeOutput(raw)
    if isstruct(raw)
        out = raw;
    elseif ischar(raw) || isstring(raw)
        out = jsondecode(char(raw));
    else
        error('Unsupported evaluator output type: %s', class(raw));
    end
end

function summary = localThresholdSummary(results, cfg)
    emptySummary = table(strings(0,1), strings(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), false(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'ModeId','Modulation','ThresholdEsNo_dB', ...
        'LowerTestedFail_dB','UpperTestedPass_dB', ...
        'AvailableEsNoAtReference_dB','LinkMarginAtReference_dB', ...
        'RequiredMargin_dB','MeetsReferenceDistance', ...
        'MaxDistance_km','MaxSymbolRate_MBd','Status'});
    if isempty(results)
        summary = emptySummary;
        return;
    end

    ids = unique(results.ModeId, 'stable');
    summary = emptySummary;
    for i = 1:numel(ids)
        sub = results(results.ModeId == ids(i), :);
        sub = sortrows(sub, 'RequestedEsNo_dB');
        stableIdx = NaN;
        for j = 1:height(sub)
            if sub.Pass(j) && all(sub.Pass(j:end))
                stableIdx = j;
                break;
            end
        end

        threshold = NaN;
        lowerFail = NaN;
        upperPass = NaN;
        status = "not reached";
        if isfinite(stableIdx)
            threshold = sub.RequestedEsNo_dB(stableIdx);
            upperPass = threshold;
            priorFail = find(~sub.Pass(1:stableIdx-1), 1, 'last');
            if ~isempty(priorFail)
                lowerFail = sub.RequestedEsNo_dB(priorFail);
                status = "bracketed";
            else
                status = "at or below first point";
            end
        end

        availableEsNo = cfg.LinkCN0_dBHz - 10*log10(cfg.LinkSymbolRate);
        linkMargin = NaN;
        maxDistance = NaN;
        maxSymbolRate = NaN;
        meetsReference = false;
        if isfinite(threshold)
            linkMargin = availableEsNo - threshold - cfg.UnmodeledLoss_dB;
            meetsReference = linkMargin >= cfg.RequiredMargin_dB;
            maxDistance = cfg.ReferenceDistance_km * ...
                10.^((linkMargin-cfg.RequiredMargin_dB)/20);
            maxSymbolRate = 10.^((cfg.LinkCN0_dBHz-threshold- ...
                cfg.UnmodeledLoss_dB-cfg.RequiredMargin_dB)/10)/1e6;
        end

        row = table(ids(i), sub.Modulation(1), threshold, lowerFail, ...
            upperPass, availableEsNo, linkMargin, cfg.RequiredMargin_dB, ...
            meetsReference, maxDistance, maxSymbolRate, status, ...
            'VariableNames', summary.Properties.VariableNames);
        summary = [summary; row]; %#ok<AGROW>
    end
end

function row = localEmptyRow()
    row = struct( ...
        'ModeId', "", ...
        'Modulation', "", ...
        'WaveformMode', "", ...
        'Coding', "", ...
        'CodeRate', NaN, ...
        'ACMFormat', NaN, ...
        'SymbolRate_MBd', NaN, ...
        'SPS', NaN, ...
        'RequestedEsNo_dB', NaN, ...
        'MainSnrInput_dB', NaN, ...
        'NoiseEquivalentSNR_dB', NaN, ...
        'BER', NaN, ...
        'FER', NaN, ...
        'LockRate', NaN, ...
        'FrameErrors', NaN, ...
        'CountedFrames', NaN, ...
        'PassBER', false, ...
        'PassFER', false, ...
        'PassLock', false, ...
        'Pass', false, ...
        'Success', false, ...
        'ErrorMsg', "");
end

function value = localNumericField(s, name, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = double(s.(name));
    end
end

function value = localLogicalField(s, name, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function value = localTextField(s, name, defaultValue)
    value = string(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = string(s.(name));
    end
end
