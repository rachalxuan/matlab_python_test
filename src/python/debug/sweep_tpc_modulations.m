function results = sweep_tpc_modulations(snrList, modList)
%SWEEP_TPC_MODULATIONS Sweep modulation modes with fixed TPC coding.
%
% Run from MATLAB:
%   addpath('E:\web_code\react\fft_project\react-fft\src\python','-begin')
%   addpath('E:\web_code\react\fft_project\react-fft\src\python\debug','-begin')
%   results = sweep_tpc_modulations;
%
% Optional:
%   results = sweep_tpc_modulations(0:2:12);
%   results = sweep_tpc_modulations(0:2:12, ["BPSK","QPSK","8PSK","16QAM","32QAM"]);
%
% Notes:
%   TPC uses the teacher (64,57)^2 product-code encoder/decoder.
%   This is a TM extension path, not FACM APSK.

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);
    if exist(fullfile(parentDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(parentDir, '-begin');
    end

    if nargin < 1 || isempty(snrList)
        snrList = 0:2:20;
    end
    if nargin < 2 || isempty(modList)
        modList = ["BPSK","QPSK","8PSK","GMSK","16QAM","32QAM"];
    end

    cfg = localDefaultConfig(snrList, modList);
    stamp = datestr(now,'yyyymmdd_HHMMSS');
    cfg.outputFile = fullfile(thisDir, sprintf('sweep_tpc_modulations_%s.csv', stamp));
    cfg.plotFile = fullfile(thisDir, sprintf('sweep_tpc_modulations_%s.png', stamp));

    results = localRunSweep(cfg);
    localPlotResults(results, cfg);

    fprintf('\n================ TPC MODULATION SWEEP SUMMARY ================\n');
    disp(results);
    fprintf('\nSaved CSV : %s\n', cfg.outputFile);
    fprintf('Saved Plot: %s\n', cfg.plotFile);
end

function cfg = localDefaultConfig(snrList, modList)
    infoRate = 300e6;
    cfg = struct();
    cfg.snrList = double(snrList(:).');

    common = struct( ...
        'sps', 8, ...
        'snr', 10, ...
        'cfo', 20000, ...
        'phaseOffset', 10, ...
        'delay', 0.2, ...
        'channelCoding', 'TPC', ...
        'RolloffFactor', 0.35, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'hasPilots', true, ...
        'showFigures', false, ...
        'berWarmUpFrames', 0, ...
        'berFrames', 6, ...
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'debugTPC', false);

    cfg.cases = repmat(struct('Name',"", 'Params',common, 'Note',""), 0, 1);
    for iMod = 1:numel(modList)
        name = upper(string(modList(iMod)));
        p = common;
        p.modType = char(name);
        p.symbolRate = infoRate / localBitsPerSymbol(name);
        if name == "GMSK"
            p.BandwidthTimeProduct = 0.5;
            p.symbolRate = infoRate;
        end
        cfg.cases(end+1,1) = struct( ...
            'Name', name, ...
            'Params', p, ...
            'Note', "TM TPC (64,57)^2");
    end
end

function results = localRunSweep(cfg)
    results = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), false(0,1), strings(0,1), ...
        'VariableNames', {'Modulation','Note','InputSNR_dB','BER', ...
        'EVM_post_pct','SNR_est_dB','LockRate_pct','Success','ErrorMsg'});

    fprintf('\n================ TPC MODULATION SWEEP ================\n');
    fprintf('SNR points: %s\n', mat2str(cfg.snrList));

    for iCase = 1:numel(cfg.cases)
        c = cfg.cases(iCase);
        for snrVal = cfg.snrList
            p = c.Params;
            p.snr = snrVal;

            fprintf('\n[%s | TPC | SNR %.1f dB]\n', c.Name, snrVal);
            try
                out = localDecodeOutput(run_ccsds_tm_evaluation(p));
                row = table( ...
                    string(c.Name), string(c.Note), snrVal, ...
                    localField(out,'BER',NaN), ...
                    localField(out,'EVM_post_pct',NaN), ...
                    localField(out,'SNR_est_dB',NaN), ...
                    100*localField(out,'LockRate',NaN), ...
                    localSuccess(out), localError(out), ...
                    'VariableNames', results.Properties.VariableNames);
            catch ME
                row = table( ...
                    string(c.Name), string(c.Note), snrVal, ...
                    NaN, NaN, NaN, 0, false, string(ME.message), ...
                    'VariableNames', results.Properties.VariableNames);
            end

            results = [results; row]; %#ok<AGROW>
            writetable(results, cfg.outputFile);

            if row.Success
                fprintf('  BER=%8.3g  EVM=%6.2f%%  SNRest=%6.2fdB  Lock=%6.1f%%\n', ...
                    row.BER, row.EVM_post_pct, row.SNR_est_dB, row.LockRate_pct);
            else
                fprintf(2, '  FAILED: %s\n', row.ErrorMsg);
            end
        end
    end
end

function localPlotResults(results, cfg)
    valid = isfinite(results.InputSNR_dB) & isfinite(results.BER) & results.BER >= 0;
    if ~any(valid)
        return;
    end

    mods = unique(results.Modulation, 'stable');
    colors = lines(numel(mods));
    markers = {'o','s','^','d','v','>','<'};

    fig = figure('Name','TPC Modulation Sweep', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[100 100 1500 470]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        semilogy(sub.InputSNR_dB, max(sub.BER, 1e-6), '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('BER');
    title('BER vs SNR'); ylim([1e-6 1]);
    legend(cellstr(mods), 'Location','southwest');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        plot(sub.InputSNR_dB, sub.EVM_post_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('EVM (%)');
    title('EVM vs SNR');
    legend(cellstr(mods), 'Location','northeast');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        plot(sub.InputSNR_dB, sub.LockRate_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('Frame Lock (%)');
    title('Frame Lock vs SNR'); ylim([0 105]);
    legend(cellstr(mods), 'Location','southeast');

    sgtitle('TPC coding fixed | modulation sweep');
    exportgraphics(fig, cfg.plotFile, 'Resolution', 220);
end

function bps = localBitsPerSymbol(modName)
    switch upper(string(modName))
        case "BPSK"
            bps = 1;
        case {"QPSK","OQPSK"}
            bps = 2;
        case "8PSK"
            bps = 3;
        case "16QAM"
            bps = 4;
        case "32QAM"
            bps = 5;
        otherwise
            bps = 1;
    end
end

function out = localDecodeOutput(x)
    if isstruct(x)
        out = x;
    elseif ischar(x) || isstring(x)
        out = jsondecode(char(x));
    else
        error('Unsupported run_ccsds_tm_evaluation output type: %s', class(x));
    end
end

function tf = localSuccess(out)
    tf = isfield(out,'success') && logical(out.success);
end

function msg = localError(out)
    msg = "";
    if isfield(out,'errorMsg') && ~isempty(out.errorMsg)
        msg = string(out.errorMsg);
    elseif isfield(out,'error') && ~isempty(out.error)
        msg = string(out.error);
    end
end

function v = localField(s, name, defv)
    if isfield(s, name) && ~isempty(s.(name))
        v = double(s.(name));
    else
        v = defv;
    end
end
