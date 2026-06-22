function plot_tpc_modulation_sweep_from_arrays()
%PLOT_TPC_MODULATION_SWEEP_FROM_ARRAYS Plot TPC modulation sweep from arrays.
%
% This script uses measured data pasted from MATLAB console.
% It does NOT rerun simulation and does NOT read CSV files.
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   plot_tpc_modulation_sweep_from_arrays
%
% Data source:
%   TPC modulation sweep summary
%   Note: TM TPC (64,57)^2

    clc;

    outDir = fullfile(fileparts(mfilename('fullpath')), 'report_figures', 'offline_logs');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    snr = 0:2:20;
    floorBER = 1e-6;

    % 是否屏蔽低锁帧率点参与 BER 平滑
    % false：所有点都参与平滑，完整保留低 SNR 失锁情况
    % true ：Lock < 80% 的点不参与 BER 平滑，但原始 marker 仍然显示
    maskLowLockForBERSmooth = false;

    % BER 纵轴最高值
    % 注意：这组数据里 GMSK 在 4 dB 的 BER=0.67126，超过 0.5。
    % 如果想完整显示这个点，可以改成 0.8。
    berYMax = 0.5;

    %% =========================================================
    % BER data
    % =========================================================
    ber_bpsk = [ ...
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    ber_qpsk = [ ...
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    ber_8psk = [ ...
        0.5, 0.5, 0.50471, 0, 0, 0, 0, 0, 0, 0, 0];

    ber_gmsk = [ ...
        0.49877, 0.50944, 0.67126, 0.39028, 0, 0, 0, 0, 0, 0, 0];

    ber_16qam = [ ...
        0.49903, 0.023739, 2.8027e-05, 0, 0, 0, 0, 0, 0, 0, 0];

    ber_32qam = [ ...
        0.50594, 0.50456, 0.21155, 0.12733, 0, 0, 0, 0, 0, 0, 0];

    %% =========================================================
    % EVM data (%)
    % =========================================================
    evm_bpsk = [ ...
        34.967, 27.5, 22.368, 17.796, 14.456, 11.508, 9.3532, 7.5771, 6.2508, 5.1814, 4.3523];

    evm_qpsk = [ ...
        34.304, 27.797, 22.216, 17.59, 14.137, 11.408, 9.3123, 7.4419, 6.1486, 5.0492, 4.2527];

    evm_8psk = [ ...
        45.903, 45.144, 30.414, 17.91, 14.137, 11.457, 9.1983, 7.4574, 6.0454, 4.9732, 4.1297];

    evm_gmsk = [ ...
        24.309, 19.845, 16.38, 13.01, 10.688, 8.5602, 7.1405, 5.9757, 4.9961, 4.381, 4.0157];

    evm_16qam = [ ...
        26.429, 24.198, 21.189, 17.832, 14.498, 11.883, 9.7779, 7.9757, 6.645, 6.0532, 4.8389];

    evm_32qam = [ ...
        20.962, 19.837, 18.309, 16.895, 15.025, 12.982, 11.141, 9.8064, 9.1394, 8.5314, 8.3319];

    %% =========================================================
    % SNR_est data (dB)
    % =========================================================
    snrest_bpsk = [ ...
        9.1267, 11.213, 13.007, 14.994, 16.799, 18.78, 20.581, 22.41, 24.081, 25.711, 27.226];

    snrest_qpsk = [ ...
        9.2931, 11.12, 13.067, 15.095, 16.993, 18.856, 20.619, 22.566, 24.224, 25.936, 27.427];

    snrest_8psk = [ ...
        9.3954, 7.7138, 7.0496, 14.938, 16.993, 18.818, 20.726, 22.548, 24.371, 26.067, 27.682];

    snrest_gmsk = [ ...
        12.285, 14.047, 15.714, 17.714, 19.422, 21.35, 22.925, 24.472, 26.027, 27.168, 27.925];

    snrest_16qam = [ ...
        11.59, 12.473, 13.691, 15.311, 17.056, 18.824, 20.482, 22.263, 23.867, 24.724, 26.63];

    snrest_32qam = [ ...
        13.381, 13.951, 14.811, 15.547, 16.64, 17.885, 19.239, 20.37, 20.988, 21.585, 21.769];

    %% =========================================================
    % Frame lock data (%)
    % =========================================================
    lock_bpsk = [ ...
        100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100];

    lock_qpsk = [ ...
        100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100];

    lock_8psk = [ ...
        0, 0, 100, 100, 100, 100, 100, 100, 100, 100, 100];

    lock_gmsk = [ ...
        0, 60, 75, 100, 100, 100, 100, 100, 100, 100, 100];

    lock_16qam = [ ...
        60, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100];

    lock_32qam = [ ...
        0, 60, 75, 100, 100, 100, 100, 100, 100, 100, 100];

    %% =========================================================
    % Curves
    % =========================================================
    curves = [
        struct('name',"BPSK", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_bpsk, 'evm',evm_bpsk, 'snrest',snrest_bpsk, 'lock',lock_bpsk)

        struct('name',"QPSK", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_qpsk, 'evm',evm_qpsk, 'snrest',snrest_qpsk, 'lock',lock_qpsk)

        struct('name',"8PSK", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_8psk, 'evm',evm_8psk, 'snrest',snrest_8psk, 'lock',lock_8psk)

        struct('name',"GMSK", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_gmsk, 'evm',evm_gmsk, 'snrest',snrest_gmsk, 'lock',lock_gmsk)

        struct('name',"16QAM", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_16qam, 'evm',evm_16qam, 'snrest',snrest_16qam, 'lock',lock_16qam)

        struct('name',"32QAM", 'note',"TM TPC (64,57)^2", ...
            'ber',ber_32qam, 'evm',evm_32qam, 'snrest',snrest_32qam, 'lock',lock_32qam)
    ];

    colors = [
        0.000 0.447 0.741
        0.850 0.325 0.098
        0.929 0.694 0.125
        0.494 0.184 0.556
        0.466 0.674 0.188
        0.301 0.745 0.933
    ];

    markers = {'o','s','^','d','v','>'};

    %% =========================================================
    % Plot single figures
    % =========================================================
    plotSingleMetric(snr, curves, colors, markers, "ber", ...
        "TPC BER vs SNR", "BER", true, [floorBER berYMax], ...
        fullfile(outDir, 'offline_tpc_modulation_ber_arrays'), ...
        maskLowLockForBERSmooth, berYMax);

    plotSingleMetric(snr, curves, colors, markers, "evm", ...
        "TPC EVM vs SNR", "EVM (%)", false, [0 50], ...
        fullfile(outDir, 'offline_tpc_modulation_evm_arrays'), ...
        maskLowLockForBERSmooth, berYMax);

    plotSingleMetric(snr, curves, colors, markers, "snrest", ...
        "TPC Estimated SNR vs Input SNR", "SNR_{est} (dB)", false, [0 30], ...
        fullfile(outDir, 'offline_tpc_modulation_snrest_arrays'), ...
        maskLowLockForBERSmooth, berYMax);

    plotSingleMetric(snr, curves, colors, markers, "lock", ...
        "TPC Frame Lock vs SNR", "锁帧率 (%)", false, [0 105], ...
        fullfile(outDir, 'offline_tpc_modulation_lock_arrays'), ...
        maskLowLockForBERSmooth, berYMax);

    %% =========================================================
    % Plot summary figure
    % =========================================================
    plotSummaryFigure(snr, curves, colors, markers, floorBER, outDir, ...
        maskLowLockForBERSmooth, berYMax);

    %% =========================================================
    % Write CSV
    % =========================================================
    writeArrayCSV(snr, curves, fullfile(outDir, 'offline_tpc_modulation_sweep_arrays.csv'));

    fprintf('\nSaved TPC modulation array figures to:\n%s\n', outDir);
    fprintf('Saved CSV:\n%s\n', fullfile(outDir, 'offline_tpc_modulation_sweep_arrays.csv'));
end

function plotSummaryFigure(snr, curves, colors, markers, floorBER, outDir, ...
    maskLowLockForBERSmooth, berYMax)

    fig = figure('Name','TPC Modulation Sweep Summary', ...
        'NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], ...
        'Position',[80 80 1600 520]);

    tiledlayout(1,4,'TileSpacing','compact','Padding','compact');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "ber", true, ...
        [floorBER berYMax], maskLowLockForBERSmooth, berYMax);
    title('BER vs SNR');
    ylabel('BER');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "evm", false, ...
        [0 50], maskLowLockForBERSmooth, berYMax);
    title('EVM vs SNR');
    ylabel('EVM (%)');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "snrest", false, ...
        [0 30], maskLowLockForBERSmooth, berYMax);
    title('Estimated SNR');
    ylabel('SNR_{est} (dB)');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "lock", false, ...
        [0 105], maskLowLockForBERSmooth, berYMax);
    title('Frame Lock vs SNR');
    ylabel('锁帧率 (%)');

    sgtitle('TPC 编译码调制方式对比 | TM TPC (64,57)^2');

    exportgraphics(fig, fullfile(outDir, 'offline_tpc_modulation_sweep_summary_arrays.png'), 'Resolution', 240);
    exportgraphics(fig, fullfile(outDir, 'offline_tpc_modulation_sweep_summary_arrays.pdf'), 'ContentType','vector');
end

function plotSingleMetric(snr, curves, colors, markers, metricName, titleText, yText, ...
    logY, yLim, outBase, maskLowLockForBERSmooth, berYMax)

    fig = figure('Name',char(titleText), ...
        'NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], ...
        'Position',[140 100 900 620]);

    drawMetric(gca, snr, curves, colors, markers, metricName, logY, yLim, ...
        maskLowLockForBERSmooth, berYMax);

    title(char(titleText));
    ylabel(char(yText));
    legend({curves.name}, 'Location','best');

    exportgraphics(fig, outBase + ".png", 'Resolution', 240);
    exportgraphics(fig, outBase + ".pdf", 'ContentType','vector');
end

function drawMetric(ax, snr, curves, colors, markers, metricName, logY, yLim, ...
    maskLowLockForBERSmooth, berYMax)

    axes(ax); %#ok<LAXES>
    hold on;

    xq = linspace(min(snr), max(snr), 350);
    floorBER = 1e-6;

    for k = 1:numel(curves)

        switch string(metricName)

            case "ber"
                % 原始 BER=0 不能直接用于 log 坐标，所以用 floorBER 替代
                yRawOriginal = curves(k).ber;
                yRaw = max(yRawOriginal, floorBER);

                % 画图时把超过 berYMax 的点压到 berYMax
                % 这样 BER 图最高就是 0.5
                yPlotRaw = min(max(yRaw, floorBER), berYMax);

                % 平滑用的数据
                yForSmooth = yRaw;

                % 可选：低锁帧率点不参与 BER 平滑
                if maskLowLockForBERSmooth
                    badLock = curves(k).lock < 80;
                    yForSmooth(badLock) = NaN;
                end

                % 因为 BER 是对数图，所以在 log10 域插值
                ySmooth = smoothLogMetric(snr, yForSmooth, xq, floorBER, berYMax);

            case "evm"
                yPlotRaw = curves(k).evm;
                ySmooth = interp1(snr, yPlotRaw, xq, 'pchip');
                ySmooth = max(ySmooth, 0);

            case "snrest"
                yPlotRaw = curves(k).snrest;
                ySmooth = interp1(snr, yPlotRaw, xq, 'pchip');

            case "lock"
                yPlotRaw = curves(k).lock;
                ySmooth = interp1(snr, yPlotRaw, xq, 'pchip');
                ySmooth = min(max(ySmooth, 0), 100);

            otherwise
                error('Unknown metricName: %s', metricName);
        end

        % 平滑曲线
        plot(xq, ySmooth, '-', ...
            'Color', colors(k,:), ...
            'LineWidth', 2.2, ...
            'HandleVisibility','off');

        % 原始数据点
        plot(snr, yPlotRaw, markers{k}, ...
            'Color', colors(k,:), ...
            'MarkerFaceColor','w', ...
            'MarkerSize', 7, ...
            'LineWidth', 1.6, ...
            'DisplayName', char(curves(k).name));
    end

    grid on;
    box on;
    xlabel('输入 SNR (dB)');
    xlim([min(snr) max(snr)]);

    if logY
        set(gca, 'YScale','log');
        ylim(yLim);

        yticks([1e-6 1e-5 1e-4 1e-3 1e-2 1e-1 berYMax]);
        yticklabels({'10^{-6}','10^{-5}','10^{-4}','10^{-3}','10^{-2}','10^{-1}',num2str(berYMax)});

        set(gca, 'YMinorGrid','on');
    else
        if ~isempty(yLim)
            ylim(yLim);
        end
    end

    legend({curves.name}, 'Location','best');
end

function ySmooth = smoothLogMetric(snr, yRaw, xq, floorBER, yMax)
    valid = isfinite(yRaw) & yRaw > 0;

    ySmooth = nan(size(xq));

    if nnz(valid) >= 2
        inRange = xq >= min(snr(valid)) & xq <= max(snr(valid));
        ySmooth(inRange) = 10.^interp1(snr(valid), log10(yRaw(valid)), xq(inRange), 'pchip');
    elseif nnz(valid) == 1
        [~, idx] = min(abs(xq - snr(valid)));
        ySmooth(idx) = yRaw(valid);
    end

    ySmooth = min(max(ySmooth, floorBER), yMax);
end

function writeArrayCSV(snr, curves, outFile)
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0
        warning('Cannot write CSV: %s', outFile);
        return;
    end

    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'modulation,note,snr,ber,evm,snr_est,lock\n');

    for k = 1:numel(curves)
        for i = 1:numel(snr)
            fprintf(fid, '%s,%s,%.0f,%.10g,%.10g,%.10g,%.10g\n', ...
                curves(k).name, ...
                curves(k).note, ...
                snr(i), ...
                curves(k).ber(i), ...
                curves(k).evm(i), ...
                curves(k).snrest(i), ...
                curves(k).lock(i));
        end
    end
end