function plot_modulation_sweep_from_arrays()
%PLOT_MODULATION_SWEEP_FROM_ARRAYS Plot modulation sweep from fixed arrays.
%
% This script uses the measured data pasted from the MATLAB console and does
% not rerun simulation or read CSV files.
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   plot_modulation_sweep_from_arrays

    outDir = fullfile(fileparts(mfilename('fullpath')), 'report_figures', 'offline_logs');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    snr = 0:2:26;
    floorBER = 1e-6;

    %% BER data
    ber_bpsk = [0 0 0 0 0 0 0 0 0 0 0 0 0 0];
    ber_qpsk = [0 0 0 0 0 0 0 0 0 0 0 0 0 0];
    ber_8psk = [0.5 0.5 0 0 0 0 0 0 0 0 0 0 0 0];
    ber_gmsk = [0.5 0.50095 0.5 0.21415 0 0 0 0 0 0 0 0 0 0];
    ber_16apsk = [0.5 0.45726 0.47403 0.45892 0.42204 0.22726 0.0039396 0 0 0 0 0 0 0];

    %% EVM data (%)
    evm_bpsk = [33.886 27.434 21.909 17.602 14.070 11.368 9.0778 7.1904 5.7211 4.6154 3.7319 3.0375 2.5294 2.1309];
    evm_qpsk = [33.864 27.824 21.562 17.552 14.168 11.192 8.8995 7.1345 5.7211 4.6113 3.6896 3.0109 2.4799 2.0434];
    evm_8psk = [43.276 35.567 21.875 17.524 14.097 11.156 8.9345 7.1451 5.6795 4.6093 3.6819 2.9575 2.4478 2.0667];
    evm_gmsk = [24.647 20.645 16.963 13.724 11.108 9.1738 7.8229 6.5817 5.6223 5.0445 4.5378 4.2366 3.9891 3.8684];
    evm_16apsk = [42.540 35.380 31.237 29.693 27.836 25.554 22.707 19.507 16.300 13.262 10.674 8.5993 7.0003 5.7588];

    %% Frame lock data (%)
    lock_bpsk = [100 100 100 100 100 100 100 97.652 100 100 100 100 100 100];
    lock_qpsk = [100 100 100 100 100 100 98.652 100 100 100 100 100 100 100];
    lock_8psk = [0 0 100 100 100 100 100 100 100 100 100 100 100 100];
    lock_gmsk = [0 45.091 52.174 56.522 100 100 100 100 100 100 100 100 100 100];
    lock_16apsk = [0 100 100 100 100 100 100 100 100 100 100 100 100 100];

    curves = [
        struct('name',"BPSK", 'note',"TM convolutional 1/2", ...
            'ber',ber_bpsk, 'evm',evm_bpsk, 'lock',lock_bpsk)
        struct('name',"QPSK", 'note',"TM convolutional 1/2", ...
            'ber',ber_qpsk, 'evm',evm_qpsk, 'lock',lock_qpsk)
        struct('name',"8PSK", 'note',"TM convolutional 1/2", ...
            'ber',ber_8psk, 'evm',evm_8psk, 'lock',lock_8psk)
        struct('name',"GMSK", 'note',"TM convolutional 1/2", ...
            'ber',ber_gmsk, 'evm',evm_gmsk, 'lock',lock_gmsk)
        struct('name',"16APSK", 'note',"FACM ACM14", ...
            'ber',ber_16apsk, 'evm',evm_16apsk, 'lock',lock_16apsk)
    ];

    colors = [
        0.000 0.447 0.741
        0.850 0.325 0.098
        0.929 0.694 0.125
        0.494 0.184 0.556
        0.466 0.674 0.188
    ];
    markers = {'o','s','^','d','v'};

    plotSingleMetric(snr, curves, colors, markers, "ber", ...
        "BER vs SNR", "BER", true, [floorBER 1], ...
        fullfile(outDir, 'offline_modulation_ber_arrays'));

    plotSingleMetric(snr, curves, colors, markers, "evm", ...
        "EVM vs SNR", "EVM (%)", false, [0 50], ...
        fullfile(outDir, 'offline_modulation_evm_arrays'));

    plotSingleMetric(snr, curves, colors, markers, "lock", ...
        "Frame Lock vs SNR", "锁帧率 (%)", false, [0 100], ...
        fullfile(outDir, 'offline_modulation_lock_arrays'));

    plotSummaryFigure(snr, curves, colors, markers, floorBER, outDir);
    writeArrayCSV(snr, curves, fullfile(outDir, 'offline_modulation_sweep_arrays.csv'));

    fprintf('Saved modulation array figures to: %s\n', outDir);
end

function plotSummaryFigure(snr, curves, colors, markers, floorBER, outDir)
    fig = figure('Name','Modulation Sweep Summary', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[90 90 1500 500]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "ber", true, [floorBER 1]);
    title('BER vs SNR'); ylabel('BER');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "evm", false, [0 50]);
    title('EVM vs SNR'); ylabel('EVM (%)');

    nexttile;
    drawMetric(gca, snr, curves, colors, markers, "lock", false, [0 100]);
    title('Frame Lock vs SNR'); ylabel('锁帧率 (%)');

    sgtitle('多调制方式对比');
    exportgraphics(fig, fullfile(outDir, 'offline_modulation_sweep_summary_arrays.png'), 'Resolution', 240);
    exportgraphics(fig, fullfile(outDir, 'offline_modulation_sweep_summary_arrays.pdf'), 'ContentType','vector');
end

function plotSingleMetric(snr, curves, colors, markers, metricName, titleText, yText, logY, yLim, outBase)
    fig = figure('Name',char(titleText), ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[140 100 900 620]);

    drawMetric(gca, snr, curves, colors, markers, metricName, logY, yLim);
    title(char(titleText));
    ylabel(char(yText));
    legend({curves.name}, 'Location','best');

    exportgraphics(fig, outBase + ".png", 'Resolution', 240);
    exportgraphics(fig, outBase + ".pdf", 'ContentType','vector');
end

function drawMetric(ax, snr, curves, colors, markers, metricName, logY, yLim)
    axes(ax); %#ok<LAXES>
    hold on;
    xq = linspace(min(snr), max(snr), 240);
    floorBER = 1e-6;

    for k = 1:numel(curves)
        switch string(metricName)
            case "ber"
                yRaw = max(curves(k).ber, floorBER);
                badLock = snr >= 6 & curves(k).lock < 80;
                yRaw(badLock) = NaN;
                ySmooth = 10.^interp1(snr, log10(yRaw), xq, 'pchip');
                ySmooth = min(max(ySmooth, floorBER), 1);
            case "evm"
                yRaw = curves(k).evm;
                ySmooth = interp1(snr, yRaw, xq, 'pchip');
                ySmooth = max(ySmooth, 0);
            otherwise
                yRaw = curves(k).lock;
%                 yRaw(yRaw < 80) = NaN;
                valid = isfinite(yRaw);
                ySmooth = nan(size(xq));
                if nnz(valid) >= 2
                    inRange = xq >= min(snr(valid)) & xq <= max(snr(valid));
                    ySmooth(inRange) = interp1(snr(valid), yRaw(valid), xq(inRange), 'linear');
                elseif nnz(valid) == 1
                    [~, idx] = min(abs(xq - snr(valid)));
                    ySmooth(idx) = yRaw(valid);
                end
                ySmooth = min(max(ySmooth, 0), 100);
        end

        plot(xq, ySmooth, '-', 'Color', colors(k,:), 'LineWidth', 2.1, ...
            'HandleVisibility','off');
        plot(snr, yRaw, markers{k}, 'Color', colors(k,:), ...
            'MarkerFaceColor','w', 'MarkerSize', 7, 'LineWidth', 1.6, ...
            'DisplayName', char(curves(k).name));
    end

    grid on; box on;
    xlabel('输入 SNR (dB)');
    xlim([min(snr) max(snr)]);
    if logY
        set(gca, 'YScale','log');
        yticks(10.^(-6:0));
        set(gca, 'YMinorGrid','on');
    end
    if ~isempty(yLim)
        ylim(yLim);
    end
    legend({curves.name}, 'Location','best');
end

function writeArrayCSV(snr, curves, outFile)
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0
        warning('Cannot write CSV: %s', outFile);
        return;
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'modulation,note,snr,ber,evm,lock\n');
    for k = 1:numel(curves)
        for i = 1:numel(snr)
            fprintf(fid, '%s,%s,%.0f,%.10g,%.10g,%.10g\n', ...
                curves(k).name, curves(k).note, snr(i), ...
                curves(k).ber(i), curves(k).evm(i), curves(k).lock(i));
        end
    end
end
