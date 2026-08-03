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
    case {'channelpower', 'channel_power', 'power', 'rfpower', 'rf_power'}
        plotChannelPowerAndSpectrum(res, ctx, opt);
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

function plotChannelPowerAndSpectrum(res, ctx, opt)
    if isfield(ctx,'channelInput') && ~isempty(ctx.channelInput)
        sigIn = ctx.channelInput(:);
    else
        sigIn = ctx.txWaveform(:);
    end

    if isfield(ctx,'channelOutput') && ~isempty(ctx.channelOutput)
        sigOut = ctx.channelOutput(:);
        outLabel = '信道输出';
    elseif isfield(ctx,'rxNoisyWaveform') && ~isempty(ctx.rxNoisyWaveform)
        sigOut = ctx.rxNoisyWaveform(:);
        outLabel = '加噪后接收信号';
    else
        sigOut = ctx.rxWaveform(:);
        outLabel = '接收端波形';
    end

    if isempty(sigIn) || isempty(sigOut)
        return;
    end

    Fs = ctx.Fs;
    inputLevelDbm = getPlotNumeric(opt, ...
        {'inputLevelDbm','input_level_dbm','outputPowerDbm','output_power_dbm'}, 0);
    centerHz = getPlotNumeric(res, ...
        {'centerFrequencyHz','centerFrequency','centerFreqHz','IFHz','carrierFreqHz'}, ...
        getPlotNumeric(opt, {'centerFrequencyHz','centerFrequency','centerFreqHz','IFHz','carrierFreqHz'}, 0));

    inputColor = [0.00 0.28 0.85];
    outputColor = [0.90 0.22 0.05];

    fig = figure('Name','CCSDS 信道功率与频谱','NumberTitle','off', ...
        'Position',[120 90 1250 760]);
    set(fig, 'DefaultAxesFontName', 'Microsoft YaHei', ...
        'DefaultTextFontName', 'Microsoft YaHei');

    subplot(2,1,1);
    sampleCount = min([5000, numel(sigIn), numel(sigOut)]);
    tMs = (0:sampleCount-1) / Fs * 1000;
    pInDbm = calibratedPowerDbm(sigIn(1:sampleCount), sigIn, inputLevelDbm);
    pOutDbm = calibratedPowerDbm(sigOut(1:sampleCount), sigIn, inputLevelDbm);
    avgInDbm = calibratedAveragePowerDbm(sigIn, sigIn, inputLevelDbm);
    avgOutDbm = calibratedAveragePowerDbm(sigOut, sigIn, inputLevelDbm);

    hOut = plot(tMs, pOutDbm, 'Color', outputColor, 'LineWidth', 0.75); hold on;
    hIn = plot(tMs, pInDbm, 'Color', inputColor, 'LineWidth', 1.05);
    hAvgIn = line([tMs(1) tMs(end)], [avgInDbm avgInDbm], ...
        'Color', inputColor, 'LineStyle', '--', 'LineWidth', 1.2);
    hAvgOut = line([tMs(1) tMs(end)], [avgOutDbm avgOutDbm], ...
        'Color', outputColor, 'LineStyle', ':', 'LineWidth', 1.4);
    grid on;
    xlabel('时间 (ms)');
    ylabel('瞬时功率 (dBm)');
    title(sprintf('信道输入/输出瞬时功率 | 输出-输入 = %+0.2f dB', ...
        avgOutDbm - avgInDbm));
    legend([hIn hOut hAvgIn hAvgOut], ...
        '信道输入瞬时功率', [outLabel '瞬时功率'], ...
        sprintf('输入平均 %.2f dBm', avgInDbm), ...
        sprintf('输出平均 %.2f dBm', avgOutDbm), ...
        'Location','best');

    % An RRC-shaped baseband waveform contains occasional samples extremely
    % close to zero. In dBm those become about -3000 dBm (realmin), which
    % expands the automatic axis and hides a real 10--20 dB channel gain.
    % This only clips the display window; signals and metrics are unchanged.
    displayFloorDbm = min(avgInDbm,avgOutDbm) - 50;
    displayCeilingDbm = max(avgInDbm,avgOutDbm) + 10;
    ylim([displayFloorDbm displayCeilingDbm]);

    subplot(2,1,2);
    fftCount = min(65536, 2^nextpow2(max(16, min([numel(sigIn), numel(sigOut), 65536]))));
    specInSeg = sigIn(1:min(numel(sigIn), fftCount));
    specOutSeg = sigOut(1:min(numel(sigOut), fftCount));
    winIn = localRaisedCosineWindow(numel(specInSeg));
    winOut = localRaisedCosineWindow(numel(specOutSeg));
    specIn = fftshift(fft(specInSeg(:).*winIn(:), fftCount));
    specOut = fftshift(fft(specOutSeg(:).*winOut(:), fftCount));
    psdIn = calibratedPsdDbmHz(specIn, winIn, Fs, sigIn, inputLevelDbm);
    psdOut = calibratedPsdDbmHz(specOut, winOut, Fs, sigIn, inputLevelDbm);
    fHz = (-fftCount/2:fftCount/2-1).' / fftCount * Fs + centerHz;
    hPsdOut = plot(fHz/1e6, psdOut, 'Color', outputColor, 'LineWidth', 0.85); hold on;
    hPsdIn = plot(fHz/1e6, psdIn, 'Color', inputColor, 'LineWidth', 1.15);
    grid on;
    xlabel('频率 (MHz)');
    ylabel('功率谱密度 (dBm/Hz)');
    if centerHz > 0
        title(sprintf('频谱对比 | 中心频率 %.6g MHz', centerHz/1e6));
    else
        title('基带频谱对比');
    end
    legend([hPsdIn hPsdOut], '信道输入 PSD', [outLabel ' PSD'], 'Location','best');
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

function powerDbm = calibratedPowerDbm(x, referenceSignal, totalPowerDbm)
    referencePower = mean(abs(referenceSignal(:)).^2);
    if ~isfinite(referencePower) || referencePower <= 0
        referencePower = 1;
    end
    relativePower = abs(x(:)).^2 / referencePower;
    powerDbm = totalPowerDbm + 10*log10(max(relativePower, realmin));
end

function avgDbm = calibratedAveragePowerDbm(x, referenceSignal, totalPowerDbm)
    referencePower = mean(abs(referenceSignal(:)).^2);
    if ~isfinite(referencePower) || referencePower <= 0
        referencePower = 1;
    end
    relativePower = mean(abs(x(:)).^2) / referencePower;
    avgDbm = totalPowerDbm + 10*log10(max(relativePower, realmin));
end

function psdDbmHz = calibratedPsdDbmHz(spec, window, sampleRateHz, referenceSignal, totalPowerDbm)
    windowPower = max(sum(abs(window(:)).^2), eps);
    relativePsdHz = abs(spec(:)).^2/(sampleRateHz * windowPower);
    referencePower = mean(abs(referenceSignal(:)).^2);
    if ~isfinite(referencePower) || referencePower <= 0
        referencePower = 1;
    end
    normalizedPsdHz = relativePsdHz / referencePower;
    psdDbmHz = totalPowerDbm + 10*log10(max(normalizedPsdHz, realmin));
end

function window = localRaisedCosineWindow(n)
    if n <= 1
        window = ones(n, 1);
    else
        idx = (0:n-1).';
        window = 0.5 - 0.5*cos(2*pi*idx/(n-1));
    end
end

function value = getPlotNumeric(s, names, defaultValue)
    value = defaultValue;
    if nargin < 3
        defaultValue = NaN;
        value = defaultValue;
    end
    if isempty(s)
        return;
    end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                raw = str2double(strrep(string(raw), ',', ''));
            end
            raw = double(raw);
            raw = raw(1);
            if isfinite(raw)
                value = raw;
                return;
            end
        end
    end
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
