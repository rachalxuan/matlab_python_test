%% plot_coding_ber_vs_snr_arrays_colors.m
% 直接使用整理好的数组作图，不读取 CSV
% 每种编码一条线，颜色用 MATLAB lines 自动分配，平滑曲线+原始点

clc;
clear;
close all;

%% 横轴：SNR
snr = 0:2:16;

%% BER 数据
ber_ldpc = [ ...
    0.5, 0.5, 0.5, 5.97e-4, 5.10e-5, 0, 0, 0, 0];
ber_rs = [ ...
    0.5, 0.5, 0.5, 0, 0, 0, 0, 0, 0];
ber_conv12 = [ ...
    0.5, 0.5, 0, 0, 0, 0, 0, 0, 0];
ber_uncoded = [ ...
    0.5, 0.5, 3.19e-2, 2.36e-2, 3.09e-5, 0, 0, 0, 0];

%% 如果你想把卷积码在 8 dB 的低锁定率异常点去掉
% ber_conv12(5) = NaN;   % SNR = 8 dB

%% 绘图下限
berFloor = 1e-6;

y_ldpc    = max(ber_ldpc, berFloor);
y_rs      = max(ber_rs, berFloor);
y_conv12  = ber_conv12;
y_uncoded = max(ber_uncoded, berFloor);

idx = isfinite(y_conv12);
y_conv12(idx) = max(y_conv12(idx), berFloor);

%% 颜色分配
codes = {'无编码','卷积编码 1/2','RS','LDPC 1/2'};
colors = lines(numel(codes));

%% 画图
figure('Name','Coding BER vs SNR', 'NumberTitle','off', 'Position',[200 120 960 580]);
hold on; grid on; box on;

snrFine = linspace(min(snr), max(snr), 300);

plotSmoothBER(snr, y_uncoded, snrFine, berFloor, '-', 'o', codes{1}, colors(1,:));
plotSmoothBER(snr, y_conv12,  snrFine, berFloor, '--','s', codes{2}, colors(2,:));
plotSmoothBER(snr, y_rs,      snrFine, berFloor, '-', '^', codes{3}, colors(3,:));
plotSmoothBER(snr, y_ldpc,    snrFine, berFloor, '-', 'd', codes{4}, colors(4,:));

xlabel('输入 SNR (dB)');
ylabel('BER');
title('编码 BER 对比');
legend('Location','southwest');
xlim([min(snr) max(snr)]);
ylim([berFloor 0.5]);

%% 保存
outName = 'coding_ber_vs_snr_arrays_colors.png';
exportgraphics(gcf, outName, 'Resolution', 300);
fprintf('已保存图片: %s\n', outName);

%% ===========================
function plotSmoothBER(snr, ber, snrFine, berFloor, lineStyle, markerStyle, name, color)
    valid = isfinite(ber);
    x = snr(valid);
    y = ber(valid);

    if numel(x) < 2
        return;
    end

    % BER=0 压到底线
    yPlot = max(y, berFloor);

    if numel(x) >= 3
        logy = log10(yPlot);
        logyFine = interp1(x, logy, snrFine, 'pchip');
        logyFine = min(logyFine, log10(0.5));
        logyFine = max(logyFine, log10(berFloor));
        yFine = 10.^logyFine;
        semilogy(snrFine, yFine, 'LineStyle', lineStyle, 'Color', color, ...
            'LineWidth', 2.0, 'DisplayName', name);
    else
        semilogy(x, yPlot, 'LineStyle', lineStyle, 'Color', color, ...
            'LineWidth', 2.0, 'DisplayName', name);
    end

    % 原始点
    semilogy(x, yPlot, 'LineStyle', 'none', 'Marker', markerStyle, ...
        'Color', color, 'MarkerEdgeColor', color, 'MarkerSize', 8, ...
        'LineWidth', 1.5, 'HandleVisibility','off');
end