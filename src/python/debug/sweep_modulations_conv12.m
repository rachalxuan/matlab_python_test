function results = sweep_modulations_conv12(snrList)
%SWEEP_MODULATIONS_CONV12 Sweep modulations with convolutional 1/2 coding.
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   results = sweep_modulations_conv12;
%
% Optional:
%   results = sweep_modulations_conv12(0:2:16);
%
% TM modulations use CCSDS TM convolutional coding 1/2.
% 16APSK uses FACM ACM14, whose coding/rate is determined by the FACM format.

    if nargin < 1 || isempty(snrList)
        snrList = 22:2:26;
    end

    cfg = localDefaultConfig(snrList);
    stamp = datestr(now,'yyyymmdd_HHMMSS');
    outDir = fileparts(mfilename('fullpath'));
    cfg.outputFile = fullfile(outDir, sprintf('sweep_modulations_conv12_%s.csv', stamp));
    cfg.plotFile = fullfile(outDir, sprintf('sweep_modulations_conv12_%s.png', stamp));

    results = localRunSweep(cfg);
    localPlotResults(results, cfg);

    fprintf('\n================ MODULATION SWEEP SUMMARY ================\n');
    disp(results);
    fprintf('\nSaved CSV : %s\n', cfg.outputFile);
    fprintf('Saved Plot: %s\n', cfg.plotFile);
end

function cfg = localDefaultConfig(snrList)
    infoRate = 300e6;
    cfg = struct();
    cfg.snrList = double(snrList(:).');

    common = struct( ...
        'sps', 8, ...
        'snr', 16, ...
        'cfo', 20000, ...
        'phaseOffset', 10, ...
        'delay', 0, ...
        'RolloffFactor', 0.35, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'hasPilots', true, ...
        'showFigures', false, ...
        'berWarmUpFrames', 4, ...
        'berFrames', 20, ...
        'facmWarmupFrames', 7, ...
        'facmBERFrames', 20, ...
        'facmNumIterations', 10, ...
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'enableFACMEqualizer', false);

    bpsk = common;
    bpsk.modType = 'BPSK';
    bpsk.symbolRate = infoRate;
    bpsk.channelCoding = 'convolutional';
    bpsk.ConvolutionalCodeRate = '1/2';

    qpsk = common;
    qpsk.modType = 'QPSK';
    qpsk.symbolRate = infoRate/2;
    qpsk.channelCoding = 'convolutional';
    qpsk.ConvolutionalCodeRate = '1/2';

    psk8 = common;
    psk8.modType = '8PSK';
    psk8.symbolRate = infoRate/3;
    psk8.channelCoding = 'convolutional';
    psk8.ConvolutionalCodeRate = '1/2';

    gmsk = common;
    gmsk.modType = 'GMSK';
    gmsk.symbolRate = infoRate;
    gmsk.channelCoding = 'convolutional';
    gmsk.ConvolutionalCodeRate = '1/2';
    gmsk.BandwidthTimeProduct = 0.5;

    apsk16 = common;
    apsk16.modType = '16APSK';
    apsk16.symbolRate = infoRate/4;
    apsk16.channelCoding = 'none';
    apsk16.ACMFormat = 14;
    apsk16.acmFormat = 14;
    apsk16.hasPilots = true;
    apsk16.debugFACM = false;
    apsk16.facmEqualizerTaps = 11;
    apsk16.facmEqualizerReg = 1e-2;
    apsk16.pilotLSReg = 1e-2;

    cfg.cases = [
        struct('Name',"BPSK", 'Params',bpsk, 'Note',"TM convolutional 1/2")
        struct('Name',"QPSK", 'Params',qpsk, 'Note',"TM convolutional 1/2")
        struct('Name',"8PSK", 'Params',psk8, 'Note',"TM convolutional 1/2")
        struct('Name',"GMSK", 'Params',gmsk, 'Note',"TM convolutional 1/2")
        struct('Name',"16APSK", 'Params',apsk16, 'Note',"FACM ACM14")
    ];
end

function results = localRunSweep(cfg)
    results = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), false(0,1), strings(0,1), ...
        'VariableNames', {'Modulation','Note','InputSNR_dB','BER', ...
        'EVM_post_pct','SNR_est_dB','LockRate_pct','Success','ErrorMsg'});

    fprintf('\n================ MODULATION SWEEP: CONV 1/2 ================\n');

    for iCase = 1:numel(cfg.cases)
        c = cfg.cases(iCase);
        for snrVal = cfg.snrList
            p = c.Params;
            p.snr = snrVal;

            fprintf('\n[%s | SNR %.1f dB]\n', c.Name, snrVal);
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
                fprintf('  BER=%8.3g  EVM=%5.2f%%  SNRest=%5.2fdB  Lock=%5.1f%%\n', ...
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
    markers = {'o','s','^','d','v','>'};

    fig = figure('Name','Modulation Sweep Conv 1/2', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[100 100 1500 470]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        semilogy(sub.InputSNR_dB, max(sub.BER, 1e-6), '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('BER');
    title('BER vs SNR'); ylim([1e-6 1]);
    legend(cellstr(mods), 'Location','southwest');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        plot(sub.InputSNR_dB, sub.EVM_post_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('EVM (%)');
    title('EVM vs SNR');
    legend(cellstr(mods), 'Location','northeast');

    nexttile; hold on;
    for k = 1:numel(mods)
        sub = results(results.Modulation == mods(k) & valid, :);
        plot(sub.InputSNR_dB, sub.LockRate_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('锁帧率 (%)');
    title('Frame Lock vs SNR'); ylim([0 105]);
    legend(cellstr(mods), 'Location','southeast');

    sgtitle('多调制方式对比 | TM 固定卷积码 1/2，16APSK 使用 FACM ACM14');
    exportgraphics(fig, cfg.plotFile, 'Resolution', 220);
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
