function ccsdsEvalPlotFigures(kind, res, ctx, opt)
%CCSDSEVALPLOTFIGURES Optional plots for run_ccsds_tm_evaluation.
% This file is intentionally visualization-only. The communication chain,
% synchronization, demodulation, decoding, and BER logic stay in the main
% evaluation script.

if nargin < 1 || isempty(kind)
    kind = 'summary';
end

kind = lower(char(kind));
switch kind
    case {'summary', 'all'}
        plotSummary(res, ctx, opt);
    case 'pipeline'
        plotPipeline(res, ctx, opt);
    case {'damagebudget', 'damage_budget', 'budget'}
        plotDamageBudget(res, ctx, opt);
    otherwise
        error('Unknown CCSDS plot kind: %s', kind);
end
end

function plotSummary(res, ctx, opt) %#ok<INUSD>
    isGMSK = contains(upper(string(res.modType)), 'GMSK');
    if isGMSK
        plotGMSKSummary(res, ctx);
        return;
    end

    figure('Name','CCSDS 评估总览','NumberTitle','off', ...
        'Position',[100 100 1200 780]);

    subplot(2,3,1);
    plotConstellation(ctx.rawSym, ctx.refConst, '同步前星座图');

    subplot(2,3,2);
    plotConstellation(ctx.fineSynced, ctx.refConst, ...
        sprintf('同步后星座图 | EVM %.2f%% | MER %.2f dB', ...
        res.EVM_post_pct, res.MER_dB));

    subplot(2,3,3);
    plotPSDPair(ctx.txWaveform, ctx.rxWaveform, ctx.Fs, 'Tx', 'Rx');
    title('功率谱');

    subplot(2,3,4);
    n = min(2000, numel(ctx.rxWaveform));
    tUs = (0:n-1) / ctx.Fs * 1e6;
    plot(tUs, real(ctx.rxWaveform(1:n)), 'b'); hold on;
    plot(tUs, imag(ctx.rxWaveform(1:n)), 'r');
    grid on; xlabel('时间 (us)'); ylabel('幅度');
    legend('I','Q','Location','best');
    title('接收端 IQ 波形');

    subplot(2,3,5);
    plotSimpleEye(ctx.fineSynced, res.modType);

    subplot(2,3,6);
    vals = [res.EVM_post_pct, res.MER_dB, res.SNR_est_dB, ...
        res.PAPR_dB, res.LockRate*100];
    names = {'EVM %','MER dB','SNR估计 dB','PAPR dB','锁帧率 %'};
    bar(vals); grid on; set(gca,'XTickLabel',names);
    title(sprintf('BER %.2e', res.BER));
end

function plotGMSKSummary(res, ctx)
    figure('Name','CCSDS GMSK 评估总览','NumberTitle','off', ...
        'Position',[100 100 1200 780]);

    subplot(2,3,1);
    plotIQTrajectory(ctx.fineSynced, '同步后 IQ 轨迹');

    subplot(2,3,2);
    phaseTrace = unwrap(angle(ctx.fineSynced(:)));
    n = min(3000, numel(phaseTrace));
    if n > 0
        plot(phaseTrace(1:n), 'b'); grid on;
        xlabel('样点索引'); ylabel('相位 (rad)');
        title('相位轨迹');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,3);
    dphi = angle(ctx.fineSynced(2:end) .* conj(ctx.fineSynced(1:end-1)));
    n = min(3000, numel(dphi));
    if n > 0
        plot(dphi(1:n), 'b'); grid on;
        xlabel('样点索引'); ylabel('差分相位 (rad)');
        title('差分相位判决量');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,4);
    if ~isempty(dphi)
        histogram(dphi, 80); grid on;
        xlabel('差分相位 (rad)'); ylabel('数量');
        title('差分相位分布');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,5);
    plotPSDPair(ctx.rxWaveform, ctx.coarseSynced, ctx.Fs, ...
        '频偏校正前', '频偏校正后');
    title('频偏校正前后频谱');

    subplot(2,3,6);
    vals = [res.BER, res.LockRate*100, res.PAPR_dB, ...
        res.EVM_post_pct, res.MER_dB];
    names = {'BER','锁帧率 %','PAPR dB','IQ误差 %','IQ MER dB'};
    bar(vals); grid on; set(gca,'XTickLabel',names);
    title('核心指标');

    sgtitle(sprintf('GMSK | SNR %.1f dB | CFO %.0f Hz | BER %.2e | 锁帧率 %.0f%%', ...
        res.snr_in, res.cfo_in, res.BER, res.LockRate*100));
end

function plotPipeline(res, ctx, opt) %#ok<INUSD>
    isGMSK = contains(upper(string(res.modType)), 'GMSK');
    if isGMSK
        plotGMSKPipeline(res, ctx);
        return;
    end

    figure('Name','CCSDS 恢复过程','NumberTitle','off', ...
        'Position',[100 80 1500 720]);

    s1 = normalizePower(ctx.rxWaveform(1:ctx.sps:end));
    s2 = normalizePower(ctx.coarseSynced(1:ctx.sps:end));
    s3 = normalizePower(ctx.TimeSynced);
    s4 = normalizePower(ctx.fineSynced);
    stages = {s1, s2, s3, s4};
    labels = {'信道输出','频偏校正后','定时同步后','载波同步后'};

    evms = nan(1,4);
    for k = 1:4
        subplot(2,4,k);
        plotConstellation(stages{k}, ctx.refConst, labels{k});
        evms(k) = localEVM(stages{k}, ctx.refConst);
        xlabel(sprintf('EVM %.1f%%', evms(k)));
    end

    subplot(2,4,5);
    bar(evms, 'FaceColor', [0.3 0.6 0.9]);
    set(gca,'XTickLabel',{'1','2','3','4'});
    ylabel('EVM (%)'); title('各阶段 EVM'); grid on;

    subplot(2,4,6);
    plotPhaseCompare(s1, s4, res.cfo_in);

    subplot(2,4,7);
    plotPSDPair(ctx.rxWaveform, ctx.coarseSynced, ctx.Fs, ...
        '频偏校正前', '频偏校正后');
    title('频偏校正前后频谱');

    subplot(2,4,8);
    barData = [evms(1), evms(4)];
    b = bar(barData); b.FaceColor = 'flat';
    b.CData(1,:) = [0.85 0.33 0.10];
    b.CData(2,:) = [0.20 0.65 0.40];
    set(gca,'XTickLabel',{'恢复前','恢复后'});
    ylabel('EVM (%)'); grid on;
    title('整体恢复效果');

    sgtitle(sprintf('%s | SNR %.1f dB | CFO %.0f Hz | BER %.2e | 锁帧率 %.0f%%', ...
        res.modType, res.snr_in, res.cfo_in, res.BER, res.LockRate*100));
end

function plotGMSKPipeline(res, ctx)
    figure('Name','GMSK 恢复过程','NumberTitle','off', ...
        'Position',[100 80 1500 720]);

    s1 = normalizePower(ctx.rxWaveform(1:ctx.sps:end));
    s2 = normalizePower(ctx.coarseSynced(1:ctx.sps:end));
    s3 = normalizePower(ctx.TimeSynced);
    s4 = normalizePower(ctx.fineSynced);
    stages = {s1, s2, s3, s4};
    labels = {'接收 IQ','频偏校正后','定时同步后','载波同步后'};
    errs = nan(1,4);

    for k = 1:4
        subplot(2,4,k);
        plotIQTrajectory(stages{k}, labels{k});
        errs(k) = localGMSKIQError(stages{k});
        xlabel(sprintf('IQ误差 %.1f%%', errs(k)));
    end

    subplot(2,4,5);
    s = ctx.fineSynced(:);
    dphi = angle(s(2:end) .* conj(s(1:end-1)));
    if ~isempty(dphi)
        histogram(dphi, 80); grid on;
        xlabel('差分相位 (rad)'); ylabel('数量');
        title('差分相位分布');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,4,6);
    plotPhaseCompare(s1, s4, res.cfo_in);

    subplot(2,4,7);
    plotPSDPair(ctx.rxWaveform, ctx.coarseSynced, ctx.Fs, ...
        '频偏校正前', '频偏校正后');
    title('频偏校正前后频谱');

    subplot(2,4,8);
    vals = [res.BER, res.LockRate*100, res.PAPR_dB, errs(4)];
    names = {'BER','锁帧率 %','PAPR dB','IQ误差 %'};
    bar(vals); grid on; set(gca,'XTickLabel',names);
    title('核心指标');

    sgtitle(sprintf('GMSK | SNR %.1f dB | CFO %.0f Hz | BER %.2e | 锁帧率 %.0f%%', ...
        res.snr_in, res.cfo_in, res.BER, res.LockRate*100));
end

function plotDamageBudget(res, ctx, opt) %#ok<INUSD>
    if contains(upper(string(res.modType)), 'GMSK') || ...
            ~isfield(ctx,'refConst') || isempty(ctx.refConst)
        return;
    end

    figure('Name','CCSDS 损伤预算','NumberTitle','off', ...
        'Position',[140 120 1100 460]);

    [residCFO_Hz, residPhase_deg] = estimateResidualCarrier(ctx);

    subplot(1,3,1);
    barCFO = [abs(res.cfo_in), abs(residCFO_Hz)];
    barWithColors(barCFO);
    set(gca,'XTickLabel',{'输入频偏','残余频偏'});
    ylabel('|频偏| (Hz)'); grid on;
    title('频偏抑制');

    subplot(1,3,2);
    barPhase = [abs(res.phase_in), abs(residPhase_deg)];
    barWithColors(barPhase);
    set(gca,'XTickLabel',{'输入相偏','残余相偏'});
    ylabel('|相位| (deg)'); grid on;
    title('相偏抑制');

    subplot(1,3,3);
    snrInput = res.snr_in;
    snrPostMF = snrInput + 10*log10(ctx.sps);
    barSNR = [snrInput, snrPostMF, res.SNR_est_dB];
    bar(barSNR); grid on;
    set(gca,'XTickLabel',{'输入 SNR','匹配滤波理论值','SNR估计'});
    ylabel('SNR (dB)');
    title(sprintf('噪声预算 | BER %.2e', res.BER));

    sgtitle(sprintf('损伤预算 | %s | 锁帧率 %.0f%%', ...
        res.modType, res.LockRate*100));
end

function plotConstellation(sym, refConst, ttl)
    if isempty(sym)
        text(0.3,0.5,'无数据'); axis off; return;
    end
    s = sym(:);
    if numel(s) > 1500
        s = s(end-1499:end);
    end
    plot(real(s), imag(s), 'b.', 'MarkerSize', 5); hold on;
    if ~isempty(refConst)
        plot(real(refConst), imag(refConst), 'rx', 'MarkerSize', 10, 'LineWidth', 2);
    end
    grid on; axis equal; xlabel('I'); ylabel('Q'); title(ttl);
    lim = max(1.5, max(abs(s))*1.1);
    if isfinite(lim) && lim > 0
        xlim([-lim lim]); ylim([-lim lim]);
    end
end

function plotIQTrajectory(sym, ttl)
    if isempty(sym)
        text(0.3,0.5,'无数据'); axis off; return;
    end
    s = sym(:);
    if numel(s) > 5000
        s = s(1:5000);
    end
    plot(real(s), imag(s), 'b.', 'MarkerSize', 4);
    grid on; axis equal; xlabel('I'); ylabel('Q'); title(ttl);
end

function plotPSDPair(x1, x2, Fs, label1, label2)
    [P1, f] = pwelch(x1, [], [], 2048, Fs, 'centered');
    [P2, ~] = pwelch(x2, [], [], 2048, Fs, 'centered');
    plot(f/1e3, 10*log10(P1 + eps), 'b', 'LineWidth', 1.1); hold on;
    plot(f/1e3, 10*log10(P2 + eps), 'r', 'LineWidth', 1.0);
    grid on; xlabel('频率 (kHz)'); ylabel('PSD (dB/Hz)');
    legend(label1, label2, 'Location', 'best');
end

function plotSimpleEye(sym, modType)
    if isempty(sym) || ~contains(upper(string(modType)), 'PSK') || ...
            contains(upper(string(modType)), 'OQPSK')
        text(0.3,0.5,sprintf('%s 眼图省略', modType));
        axis off; return;
    end
    n = min(1000, numel(sym));
    seg = real(sym(end-n+1:end));
    spsEye = 2;
    seg = seg(1:floor(numel(seg)/spsEye)*spsEye);
    if isempty(seg)
        text(0.3,0.5,'无数据'); axis off; return;
    end
    plot(reshape(seg, spsEye, []), 'b');
    grid on; title('简化眼图');
end

function plotPhaseCompare(s1, s4, cfoIn)
    n1 = min(1500, numel(s1));
    n4 = min(1500, numel(s4));
    if n1 > 0
        plot(unwrap(angle(s1(1:n1))), 'r', 'LineWidth', 1.0); hold on;
    end
    if n4 > 0
        plot(unwrap(angle(s4(1:n4))), 'b', 'LineWidth', 1.2);
    end
    grid on; xlabel('符号索引'); ylabel('相位 (rad)');
    legend('恢复前','恢复后','Location','best');
    title(sprintf('相位轨迹 | 输入频偏 %.0f Hz', cfoIn));
end

function y = normalizePower(x)
    if isempty(x)
        y = x;
        return;
    end
    p = mean(abs(x).^2);
    if p > 0
        y = x / sqrt(p);
    else
        y = x;
    end
end

function evmPct = localEVM(rxSym, refConst)
    evmPct = NaN;
    if isempty(rxSym) || isempty(refConst)
        return;
    end
    rxSym = rxSym(:);
    refConst = refConst(:).';
    [~, idx] = min(abs(rxSym - refConst), [], 2);
    nearest = refConst(idx).';
    evmRms = sqrt(mean(abs(rxSym - nearest).^2) / mean(abs(nearest).^2));
    evmPct = evmRms * 100;
end

function iqErrPct = localGMSKIQError(sym)
    iqErrPct = NaN;
    if isempty(sym)
        return;
    end
    sym = sym(:);
    ampErr = abs(abs(sym) - mean(abs(sym)));
    iqErrPct = sqrt(mean(ampErr.^2)) / (mean(abs(sym)) + eps) * 100;
end

function [residCFO_Hz, residPhase_deg] = estimateResidualCarrier(ctx)
    residCFO_Hz = NaN;
    residPhase_deg = NaN;
    if ~isfield(ctx,'fineSynced') || isempty(ctx.fineSynced) || ...
            ~isfield(ctx,'refConst') || isempty(ctx.refConst) || numel(ctx.fineSynced) < 50
        return;
    end
    nUse = min(numel(ctx.fineSynced), 5000);
    s = ctx.fineSynced(end-nUse+1:end);
    refConst = ctx.refConst(:).';
    [~, idx] = min(abs(s(:) - refConst), [], 2);
    ideal = refConst(idx).';
    phErr = unwrap(angle(s(:) ./ ideal));
    n = (0:nUse-1).';
    fSym = ctx.Fs / ctx.sps;
    coef = polyfit(n, phErr, 1);
    residCFO_Hz = coef(1) * fSym / (2*pi);
    residPhase_deg = rad2deg(coef(2));
end

function barWithColors(values)
    b = bar(values);
    b.FaceColor = 'flat';
    b.CData(1,:) = [0.85 0.33 0.10];
    b.CData(2,:) = [0.20 0.65 0.40];
end
