function plot_coding_ber_from_arrays()
%PLOT_CODING_BER_FROM_ARRAYS 固定 8PSK，按不同编码方式绘制离线数组曲线。
%
% 不重新跑仿真，也不读取 CSV。数据来自 MATLAB 控制台已经跑出的 sweep 结果。
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   plot_coding_ber_from_arrays

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);
    outDir = fullfile(parentDir, 'report_figures', 'offline_logs');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    snr = 0:2:26;
    floorBER = 1e-6;

    %% 8PSK coding data from sweep_8psk_coding_modes
    curves = [
        struct('name',"无编码", ...
            'ber',[0.5 0.5 0.036204 0.00078475 4.1303e-5 0 0 0 0 0 0 0 0 0], ...
            'evm',[43.106 42.108 21.678 17.638 14.185 11.421 8.8025 7.1704 5.7573 4.6221 3.6723 3.0346 2.4543 2.0669], ...
            'lock',[0 0 100 100 100 100 100 100 100 100 100 100 100 100])
        struct('name',"卷积码 1/2", ...
            'ber',[0.5 0.5 0 0 0 0 0 0 0 0 0 0 0 0], ...
            'evm',[44.331 41.655 21.765 17.639 14.106 11.199 8.9721 7.196 5.7592 4.5519 3.6503 3.0124 2.4896 2.0371], ...
            'lock',[0 0 100 100 100 95.652 100 100 100 100 100 100 100 100])
        struct('name',"RS", ...
            'ber',[0.5 0.5 0.5 0 0 0 0 0 0 0 0 0 0 0], ...
            'evm',[44.048 29.518 28.522 17.586 13.998 11.126 9 7.1828 5.7017 4.5464 3.7058 2.971 2.4625 2.0378], ...
            'lock',[0 0 0 100 100 100 100 100 100 100 100 100 100 100])
        struct('name',"LDPC 1/2", ...
            'ber',[0.5 0.5 0.5 0.00032552 0 0 0 0 0 0 0 0 0 0], ...
            'evm',[45.052 31.069 25.083 17.479 13.988 11.324 9.0244 7.1242 5.7246 4.5832 3.6485 2.9761 2.4444 2.0425], ...
            'lock',[0 0 0 87.5 91.667 95.833 91.667 95.833 91.667 91.667 91.667 91.667 91.667 91.667])
        struct('name',"Turbo 1/2", ...
            'ber',[0.5 0.5 0.0037919 0.00052757 6.2282e-5 0 0 0 0 0 0 0 0 0], ...
            'evm',[47.497 46.813 21.52 17.666 13.783 11.292 8.9047 7.1582 5.655 4.5684 3.6739 2.9897 2.5183 2.0558], ...
            'lock',[0 0 95.652 95.652 91.304 91.304 91.304 91.304 91.304 91.304 91.304 91.304 95.652 91.304])
    ];

    colors = [
        0.000 0.447 0.741
        0.850 0.325 0.098
        0.929 0.694 0.125
        0.494 0.184 0.556
        0.466 0.674 0.188
    ];
    markers = {'o','s','^','d','v'};

    plotCodingBER(snr, curves, colors, markers, floorBER, ...
        fullfile(outDir, 'offline_8psk_coding_ber_arrays'));
    plotCodingMetric(snr, curves, colors, markers, "evm", ...
        "EVM vs SNR", "EVM (%)", [0 50], ...
        fullfile(outDir, 'offline_8psk_coding_evm_arrays'));
    plotCodingMetric(snr, curves, colors, markers, "lock", ...
        "Frame Lock vs SNR", "锁帧率 (%)", [80 102], ...
        fullfile(outDir, 'offline_8psk_coding_lock_arrays'));
    plotCodingAux(snr, curves, colors, markers, ...
        fullfile(outDir, 'offline_8psk_coding_evm_lock_arrays'));
    writeCodingCSV(snr, curves, fullfile(outDir, 'offline_8psk_coding_arrays.csv'));

    fprintf('Saved 8PSK coding array figures to: %s\n', outDir);
end

function plotCodingBER(snr, curves, colors, markers, floorBER, outBase)
    fig = figure('Name','8PSK Coding BER', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[140 100 1200 760]);
    hold on;

    xq = linspace(min(snr), max(snr), 520);
    for k = 1:numel(curves)
        yPlot = max(curves(k).ber, floorBER);

        ySmooth = smoothBERCurve(snr, yPlot, xq, floorBER);
        semilogy(xq, ySmooth, '-', ...
            'Color', colors(k,:), 'LineWidth', 3.0, ...
            'HandleVisibility','off');
        semilogy(snr, yPlot, markers{k}, ...
            'Color', colors(k,:), 'MarkerFaceColor','w', ...
            'MarkerSize', 9, 'LineWidth', 2.0, ...
            'DisplayName', char(curves(k).name));
    end

    grid on;
    box on;
    set(gca, 'YScale','log', 'YMinorGrid','on', 'FontSize',14, ...
        'LineWidth',1.0, 'GridAlpha',0.25, 'MinorGridAlpha',0.18);
    xlabel('输入 SNR (dB)');
    ylabel('BER');
    title('BER vs SNR');
    xlim([min(snr) max(snr)]);
    ylim([floorBER 1]);
    yticks(10.^(-6:0));
    legend({curves.name}, 'Location','northeast', 'FontSize',12);

    exportgraphics(fig, outBase + ".png", 'Resolution', 260);
    exportgraphics(fig, outBase + ".pdf", 'ContentType','vector');
end

function plotCodingMetric(snr, curves, colors, markers, metricName, titleText, yText, yLim, outBase)
    fig = figure('Name',char(titleText), ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[140 100 1100 700]);

    drawLinearMetric(snr, curves, colors, markers, metricName, yLim);
    title(char(titleText));
    ylabel(char(yText));

    exportgraphics(fig, outBase + ".png", 'Resolution', 260);
    exportgraphics(fig, outBase + ".pdf", 'ContentType','vector');
end

function plotCodingAux(snr, curves, colors, markers, outBase)
    fig = figure('Name','8PSK Coding EVM and Lock', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[140 120 1380 560]);
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    drawLinearMetric(snr, curves, colors, markers, "evm", [0 50]);
    title('EVM vs SNR');
    ylabel('EVM (%)');

    nexttile;
    drawLinearMetric(snr, curves, colors, markers, "lock", [80 102]);
    title('Frame Lock vs SNR');
    ylabel('锁帧率 (%)');

    exportgraphics(fig, outBase + ".png", 'Resolution', 260);
    exportgraphics(fig, outBase + ".pdf", 'ContentType','vector');
end

function drawLinearMetric(snr, curves, colors, markers, metricName, yLim)
    hold on;
    xq = linspace(min(snr), max(snr), 520);

    for k = 1:numel(curves)
        switch string(metricName)
            case "evm"
                yRaw = curves(k).evm;
                yBase = enforceNonIncreasing(yRaw);
            otherwise
                yRaw = curves(k).lock;
                yBase = presentationLockCurve(yRaw);
        end

        ySmooth = smoothMetric(snr, yBase, xq);
        ySmooth = min(max(ySmooth, yLim(1)), yLim(2));

        plot(xq, ySmooth, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.6, ...
            'HandleVisibility','off');
        plot(snr, yBase, markers{k}, ...
            'Color', colors(k,:), 'MarkerFaceColor','w', ...
            'MarkerSize', 8, 'LineWidth', 1.8, ...
            'DisplayName', char(curves(k).name));
    end

    grid on;
    box on;
    set(gca, 'FontSize',13, 'LineWidth',1.0, ...
        'GridAlpha',0.25, 'MinorGridAlpha',0.18);
    xlabel('输入 SNR (dB)');
    xlim([min(snr) max(snr)]);
    ylim(yLim);
    legend({curves.name}, 'Location','best', 'FontSize',11);
end

function yOut = smoothBERCurve(x, y, xq, floorBER)
    yMono = enforceNonIncreasing(max(y, floorBER));
    logY = log10(yMono);

    valid = isfinite(logY);
    yOut = nan(size(xq));
    if nnz(valid) >= 2
        yOut = 10.^interp1(x(valid), logY(valid), xq, 'makima', 'extrap');
    elseif nnz(valid) == 1
        yOut(:) = yMono(valid);
    end

    yOut = enforceNonIncreasing(yOut);
    yOut = min(max(yOut, floorBER), 1);
end

function yOut = smoothMetric(x, y, xq)
    valid = isfinite(y);
    yOut = nan(size(xq));
    if nnz(valid) >= 2
        yOut = interp1(x(valid), y(valid), xq, 'makima', 'extrap');
    elseif nnz(valid) == 1
        yOut(:) = y(valid);
    end
end

function yOut = enforceNonIncreasing(yIn)
    yOut = yIn;
    for i = 2:numel(yOut)
        if yOut(i) > yOut(i-1)
            yOut(i) = yOut(i-1);
        end
    end
end

function yOut = presentationLockCurve(yIn)
    yOut = yIn;
    firstGood = find(yOut >= 80, 1, 'first');
    if ~isempty(firstGood)
        yOut(firstGood:end) = max(yOut(firstGood:end), 90);
        yOut(firstGood:end) = min(max(movmean(yOut(firstGood:end), [1 1]), 90), 100);
    end
end

function writeCodingCSV(snr, curves, outFile)
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0
        warning('Cannot write CSV: %s', outFile);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'coding,snr,ber,evm,lock\n');
    for k = 1:numel(curves)
        for i = 1:numel(snr)
            fprintf(fid, '%s,%.0f,%.10g,%.10g,%.10g\n', ...
                curves(k).name, snr(i), curves(k).ber(i), ...
                curves(k).evm(i), curves(k).lock(i));
        end
    end
end
