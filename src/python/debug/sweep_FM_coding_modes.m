function results = sweep_FM_coding_modes(snrList)
%SWEEP_FM_CODING_MODES Sweep coding modes with fixed FM modulation.
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   results = sweep_FM_coding_modes;
%
% Optional:
%   results = sweep_FM_coding_modes(0:2:14);
%   results = sweep_FM_coding_modes(0:1:12);
%
% Coding modes:
%   无编码, 卷积码 1/2, RS, LDPC 1/2, Turbo 1/2
%
% Notes:
%   FM 当前不统计星座 EVM / MER / SNR_est。
%   重点看 BER 和 LockRate。

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);

    % 如果脚本放在子目录，自动把上一级加入路径
    if exist(fullfile(parentDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(parentDir, '-begin');
    end

    % 如果脚本和主函数同目录，也把当前目录加进去
    if exist(fullfile(thisDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(thisDir, '-begin');
    end

    if nargin < 1 || isempty(snrList)
        snrList = 0:2:14;
    end

    cfg = localDefaultConfig(snrList);

    stamp = datestr(now,'yyyymmdd_HHMMSS');
    outDir = fileparts(mfilename('fullpath'));
    cfg.outputFile = fullfile(outDir, sprintf('sweep_FM_coding_modes_%s.csv', stamp));
    cfg.plotFile   = fullfile(outDir, sprintf('sweep_FM_coding_modes_%s.png', stamp));

    results = localRunSweep(cfg);
    localPlotResults(results, cfg);

    fprintf('\n================ FM CODING SWEEP SUMMARY ================\n');
    disp(results);

    fprintf('\nSaved CSV : %s\n', cfg.outputFile);
    fprintf('Saved Plot: %s\n', cfg.plotFile);
end


function cfg = localDefaultConfig(snrList)

    cfg = struct();
    cfg.snrList = double(snrList(:).');

    % =========================================================
    % FM 固定参数
    %
    % 这里先用你已经验证过的一组参数：
    %   symbolRate = 20 MHz
    %   sps        = 4
    %   Fs         = 80 MHz
    %   CFO        = 2 MHz
    %   phase      = 10 deg
    %   delay      = 0.1 sample
    %
    % 如果想先看纯 AWGN，可以把 cfo 改成 0。
    % =========================================================
    cfg.base = struct( ...
        'modType', 'FM', ...
        'symbolRate', 20e6, ...
        'sps', 4, ...
        'snr', 12, ...
        'cfo', 2e6, ...
        'phaseOffset', 10, ...
        'delay', 0.1, ...
        'RolloffFactor', 0.5, ...
        'TZZS', 0.715, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'showFigures', false, ...
        'debugFM', false, ...
        'berWarmUpFrames', 4, ...
        'berFrames', 20, ...
        'enableHChannel', false, ...
        'enableEqualizer', false);

    % =========================================================
    % 编码方式
    % =========================================================
    cfg.cases = [
        struct('Name',"无编码", ...
            'ChannelCoding',"none", ...
            'ConvolutionalCodeRate',"", ...
            'CodeRate',"", ...
            'NumBitsInInformationBlock',[], ...
            'IsLDPCOnSMTF',[], ...
            'LDPCCodeblockSize',[])

        struct('Name',"卷积码 1/2", ...
            'ChannelCoding',"convolutional", ...
            'ConvolutionalCodeRate',"1/2", ...
            'CodeRate',"", ...
            'NumBitsInInformationBlock',[], ...
            'IsLDPCOnSMTF',[], ...
            'LDPCCodeblockSize',[])

        struct('Name',"RS", ...
            'ChannelCoding',"RS", ...
            'ConvolutionalCodeRate',"", ...
            'CodeRate',"", ...
            'NumBitsInInformationBlock',[], ...
            'IsLDPCOnSMTF',[], ...
            'LDPCCodeblockSize',[])

        struct('Name',"LDPC 1/2", ...
            'ChannelCoding',"LDPC", ...
            'ConvolutionalCodeRate',"", ...
            'CodeRate',"1/2", ...
            'NumBitsInInformationBlock',1024, ...
            'IsLDPCOnSMTF',false, ...
            'LDPCCodeblockSize',[])

        struct('Name',"Turbo 1/2", ...
            'ChannelCoding',"Turbo", ...
            'ConvolutionalCodeRate',"", ...
            'CodeRate',"1/2", ...
            'NumBitsInInformationBlock',1784, ...
            'IsLDPCOnSMTF',[], ...
            'LDPCCodeblockSize',[])
    ];
end


function results = localRunSweep(cfg)

    results = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), false(0,1), strings(0,1), ...
        'VariableNames', { ...
            'Modulation', ...
            'Coding', ...
            'InputSNR_dB', ...
            'BER', ...
            'LockRate_pct', ...
            'DetectedFMFrames', ...
            'TotalFMFrames', ...
            'Success', ...
            'ErrorMsg'});

    fprintf('\n================ FM CODING SWEEP ================\n');
    fprintf('Mod=FM, SNR points=%s\n', mat2str(cfg.snrList));
    fprintf('CFO=%.3f MHz, phase=%.1f deg, delay=%.3f sample\n', ...
        cfg.base.cfo/1e6, cfg.base.phaseOffset, cfg.base.delay);

    for iCase = 1:numel(cfg.cases)
        c = cfg.cases(iCase);

        for snrVal = cfg.snrList
            p = localApplyCodingParams(cfg.base, c);
            p.snr = snrVal;

            fprintf('\n[FM | %s | SNR %.1f dB]\n', c.Name, snrVal);

            try
                raw = run_ccsds_tm_evaluation(p);
                out = localDecodeOutput(raw);

                berVal  = localField(out, 'BER', NaN);
                lockPct = 100 * localField(out, 'LockRate', NaN);

                [detectedFMFrames, totalFMFrames] = localGetFMFrames(out);

                row = table( ...
                    "FM", ...
                    string(c.Name), ...
                    snrVal, ...
                    berVal, ...
                    lockPct, ...
                    detectedFMFrames, ...
                    totalFMFrames, ...
                    localSuccess(out), ...
                    localError(out), ...
                    'VariableNames', results.Properties.VariableNames);

            catch ME
                row = table( ...
                    "FM", ...
                    string(c.Name), ...
                    snrVal, ...
                    NaN, ...
                    0, ...
                    NaN, ...
                    NaN, ...
                    false, ...
                    string(ME.message), ...
                    'VariableNames', results.Properties.VariableNames);
            end

            results = [results; row]; %#ok<AGROW>
            writetable(results, cfg.outputFile);

            if row.Success
                fprintf('  BER=%8.3g  Lock=%5.1f%%  FMFrames=%g/%g\n', ...
                    row.BER, row.LockRate_pct, row.DetectedFMFrames, row.TotalFMFrames);
            else
                fprintf(2, '  FAILED: %s\n', row.ErrorMsg);
            end
        end
    end
end


function p = localApplyCodingParams(p, c)

    p.channelCoding = char(c.ChannelCoding);

    fieldsToClear = { ...
        'ConvolutionalCodeRate', ...
        'CodeRate', ...
        'NumBitsInInformationBlock', ...
        'IsLDPCOnSMTF', ...
        'LDPCCodeblockSize'};

    for i = 1:numel(fieldsToClear)
        if isfield(p, fieldsToClear{i})
            p = rmfield(p, fieldsToClear{i});
        end
    end

    if strlength(c.ConvolutionalCodeRate) > 0
        p.ConvolutionalCodeRate = char(c.ConvolutionalCodeRate);
    end

    if strlength(c.CodeRate) > 0
        p.CodeRate = char(c.CodeRate);
    end

    if ~isempty(c.NumBitsInInformationBlock)
        p.NumBitsInInformationBlock = c.NumBitsInInformationBlock;
    end

    if ~isempty(c.IsLDPCOnSMTF)
        p.IsLDPCOnSMTF = logical(c.IsLDPCOnSMTF);
    end

    if ~isempty(c.LDPCCodeblockSize)
        p.LDPCCodeblockSize = c.LDPCCodeblockSize;
    end
end


function localPlotResults(results, cfg)

    valid = isfinite(results.InputSNR_dB) & ...
            isfinite(results.BER) & ...
            results.BER >= 0 & ...
            results.Success;

    if ~any(valid)
        warning('没有有效结果，跳过绘图。');
        return;
    end

    codes = unique(results.Coding, 'stable');

    colors = [
        0.000 0.447 0.741
        0.850 0.325 0.098
        0.929 0.694 0.125
        0.494 0.184 0.556
        0.466 0.674 0.188
        0.301 0.745 0.933
        0.635 0.078 0.184
    ];

    markers = {'o','s','^','d','v','>','<'};

    fig = figure('Name','FM Coding Sweep', ...
        'NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], ...
        'Position',[100 100 1200 470]);

    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    % =========================================================
    % BER vs SNR
    % =========================================================
    nexttile;
    hold on;

    for k = 1:numel(codes)
        sub = results(results.Coding == codes(k) & valid, :);
        if isempty(sub)
            continue;
        end

        sub = sortrows(sub, 'InputSNR_dB');

        colorIdx = mod(k-1, size(colors,1)) + 1;
        markerIdx = mod(k-1, numel(markers)) + 1;

        semilogy(sub.InputSNR_dB, max(sub.BER, 1e-6), '-', ...
            'Color', colors(colorIdx,:), ...
            'LineWidth', 2.0, ...
            'Marker', markers{markerIdx}, ...
            'MarkerSize', 6, ...
            'MarkerFaceColor','w');
    end

    grid on;
    box on;
    xlabel('输入 SNR (dB)');
    ylabel('BER');
    title('FM: BER vs SNR');
    ylim([1e-6 1]);
    legend(cellstr(codes), 'Location','southwest');

    % =========================================================
    % Frame Lock vs SNR
    % =========================================================
    nexttile;
    hold on;

    for k = 1:numel(codes)
        sub = results(results.Coding == codes(k) & valid, :);
        if isempty(sub)
            continue;
        end

        sub = sortrows(sub, 'InputSNR_dB');

        colorIdx = mod(k-1, size(colors,1)) + 1;
        markerIdx = mod(k-1, numel(markers)) + 1;

        plot(sub.InputSNR_dB, sub.LockRate_pct, '-', ...
            'Color', colors(colorIdx,:), ...
            'LineWidth', 2.0, ...
            'Marker', markers{markerIdx}, ...
            'MarkerSize', 6, ...
            'MarkerFaceColor','w');
    end

    grid on;
    box on;
    xlabel('输入 SNR (dB)');
    ylabel('锁帧率 (%)');
    title('FM: Frame Lock vs SNR');
    ylim([0 105]);
    legend(cellstr(codes), 'Location','southeast');

    sgtitle(sprintf('FM 编码方式对比 | Rs=%.1f MBaud | CFO=%.1f MHz | phase=%.1f° | delay=%.2f', ...
        cfg.base.symbolRate/1e6, ...
        cfg.base.cfo/1e6, ...
        cfg.base.phaseOffset, ...
        cfg.base.delay));

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

    if isfield(out,'success')
        tf = logical(out.success);
    else
        % 如果主函数没有 success 字段，只要有 BER 就认为本次运行成功
        tf = isfield(out,'BER') && ~isempty(out.BER);
    end
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


function [detected, totalFrames] = localGetFMFrames(out)

    detected = NaN;
    totalFrames = NaN;

    % 顶层字段：如果你在 metrics 里加了这两个字段，会优先用它们
    if isfield(out,'fmDetectedFrames') && ~isempty(out.fmDetectedFrames)
        detected = double(out.fmDetectedFrames);
    end

    if isfield(out,'fmTotalFrames') && ~isempty(out.fmTotalFrames)
        totalFrames = double(out.fmTotalFrames);
    end

    % 嵌套字段：兼容 fmRxInfo / fmInfo
    if isnan(detected) && isfield(out,'fmRxInfo') && isstruct(out.fmRxInfo)
        if isfield(out.fmRxInfo,'detectedFrames') && ~isempty(out.fmRxInfo.detectedFrames)
            detected = double(out.fmRxInfo.detectedFrames);
        end
    end

    if isnan(totalFrames) && isfield(out,'fmInfo') && isstruct(out.fmInfo)
        if isfield(out.fmInfo,'NFrame') && ~isempty(out.fmInfo.NFrame)
            totalFrames = double(out.fmInfo.NFrame);
        elseif isfield(out.fmInfo,'TotalFrames') && ~isempty(out.fmInfo.TotalFrames)
            totalFrames = double(out.fmInfo.TotalFrames);
        end
    end
end