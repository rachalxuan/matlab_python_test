function results = sweep_UQPSK_coding_modes(snrList)
%SWEEP_UQPSK_CODING_MODES Sweep coding modes with fixed UQPSK modulation.
%
% Run from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   results = sweep_UQPSK_coding_modes;
%
% Optional:
%   results = sweep_UQPSK_coding_modes(0:2:16);
%   results = sweep_UQPSK_coding_modes(0:2:22);
%
% Coding modes:
%   无编码, 卷积码 1/2, RS, LDPC 1/2, Turbo 1/2

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);
    if exist(fullfile(parentDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(parentDir);
    end

    if nargin < 1 || isempty(snrList)
        snrList = 0:2:26;
    end

    cfg = localDefaultConfig(snrList);
%     stamp = datestr(now,'yyyymmdd_HHMMSS');
%     outDir = fileparts(mfilename('fullpath'));
%     cfg.outputFile = fullfile(outDir, sprintf('sweep_UQPSK_coding_modes_%s.csv', stamp));
%     cfg.plotFile = fullfile(outDir, sprintf('sweep_UQPSK_coding_modes_%s.png', stamp));
% 
    results = localRunSweep(cfg);
    localPlotResults(results, cfg);

    fprintf('\n================ UQPSK CODING SWEEP SUMMARY ================\n');
    disp(results);
%     fprintf('\nSaved CSV : %s\n', cfg.outputFile);
%     fprintf('Saved Plot: %s\n', cfg.plotFile);
end

function cfg = localDefaultConfig(snrList)
    infoRate = 300e6;

    cfg = struct();
    cfg.snrList = double(snrList(:).');

    cfg.base = struct( ...
        'modType', 'UQPSK', ...
        'symbolRate', infoRate/3, ...
        'sps', 8, ...
        'snr', 12, ...
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
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false);

    cfg.cases = [
        struct('Name',"无编码", 'ChannelCoding',"none", ...
            'ConvolutionalCodeRate',"", 'CodeRate',"", ...
            'NumBitsInInformationBlock',[], 'IsLDPCOnSMTF',[], 'LDPCCodeblockSize',[])
        struct('Name',"卷积码 1/2", 'ChannelCoding',"convolutional", ...
            'ConvolutionalCodeRate',"1/2", 'CodeRate',"", ...
            'NumBitsInInformationBlock',[], 'IsLDPCOnSMTF',[], 'LDPCCodeblockSize',[])
        struct('Name',"RS", 'ChannelCoding',"RS", ...
            'ConvolutionalCodeRate',"", 'CodeRate',"", ...
            'NumBitsInInformationBlock',[], 'IsLDPCOnSMTF',[], 'LDPCCodeblockSize',[])
        struct('Name',"LDPC 1/2", 'ChannelCoding',"LDPC", ...
            'ConvolutionalCodeRate',"", 'CodeRate',"1/2", ...
            'NumBitsInInformationBlock',1024, 'IsLDPCOnSMTF',false, 'LDPCCodeblockSize',[])
        struct('Name',"Turbo 1/2", 'ChannelCoding',"Turbo", ...
            'ConvolutionalCodeRate',"", 'CodeRate',"1/2", ...
            'NumBitsInInformationBlock',1784, 'IsLDPCOnSMTF',[], 'LDPCCodeblockSize',[])
    ];
end

function results = localRunSweep(cfg)
    results = table( ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), false(0,1), strings(0,1), ...
        'VariableNames', {'Modulation','Coding','InputSNR_dB','BER', ...
        'EVM_post_pct','SNR_est_dB','LockRate_pct','Success','ErrorMsg'});

    fprintf('\n================ UQPSK CODING SWEEP ================\n');
    fprintf('Mod=UQPSK, SNR points=%s\n', mat2str(cfg.snrList));

    for iCase = 1:numel(cfg.cases)
        c = cfg.cases(iCase);
        for snrVal = cfg.snrList
            p = localApplyCodingParams(cfg.base, c);
            p.snr = snrVal;

            fprintf('\n[UQPSK | %s | SNR %.1f dB]\n', c.Name, snrVal);
            try
                out = localDecodeOutput(run_ccsds_tm_evaluation(p));
                row = table( ...
                    "UQPSK", string(c.Name), snrVal, ...
                    localField(out,'BER',NaN), ...
                    localField(out,'EVM_post_pct',NaN), ...
                    localField(out,'SNR_est_dB',NaN), ...
                    100*localField(out,'LockRate',NaN), ...
                    localSuccess(out), localError(out), ...
                    'VariableNames', results.Properties.VariableNames);
            catch ME
                row = table( ...
                    "UQPSK", string(c.Name), snrVal, ...
                    NaN, NaN, NaN, 0, false, string(ME.message), ...
                    'VariableNames', results.Properties.VariableNames);
            end

            results = [results; row]; %#ok<AGROW>
%             writetable(results, cfg.outputFile);

            if row.Success
                fprintf('  BER=%8.3g  EVM=%5.2f%%  SNRest=%5.2fdB  Lock=%5.1f%%\n', ...
                    row.BER, row.EVM_post_pct, row.SNR_est_dB, row.LockRate_pct);
            else
                fprintf(2, '  FAILED: %s\n', row.ErrorMsg);
            end
        end
    end
end

function p = localApplyCodingParams(p, c)
    p.channelCoding = char(c.ChannelCoding);

    fieldsToClear = {'ConvolutionalCodeRate','CodeRate', ...
        'NumBitsInInformationBlock','IsLDPCOnSMTF','LDPCCodeblockSize'};
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
    valid = isfinite(results.InputSNR_dB) & isfinite(results.BER) & results.BER >= 0;
    if ~any(valid)
        return;
    end

    codes = unique(results.Coding, 'stable');
    colors = [
        0.000 0.447 0.741
        0.850 0.325 0.098
        0.929 0.694 0.125
        0.494 0.184 0.556
        0.466 0.674 0.188
    ];
    markers = {'o','s','^','d','v'};

    fig = figure('Name','UQPSK Coding Sweep', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[100 100 1500 470]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    for k = 1:numel(codes)
        sub = results(results.Coding == codes(k) & valid, :);
        semilogy(sub.InputSNR_dB, max(sub.BER, 1e-6), '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('BER');
    title('BER vs SNR'); ylim([1e-6 0.5]);
    legend(cellstr(codes), 'Location','southwest');

    nexttile; hold on;
    for k = 1:numel(codes)
        sub = results(results.Coding == codes(k) & valid, :);
        plot(sub.InputSNR_dB, sub.EVM_post_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('EVM (%)');
    title('EVM vs SNR');
    legend(cellstr(codes), 'Location','northeast');

    nexttile; hold on;
    for k = 1:numel(codes)
        sub = results(results.Coding == codes(k) & valid, :);
        plot(sub.InputSNR_dB, sub.LockRate_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{k}, 'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('输入 SNR (dB)'); ylabel('锁帧率 (%)');
    title('Frame Lock vs SNR'); ylim([0 105]);
    legend(cellstr(codes), 'Location','southeast');

    sgtitle('UQPSK 编码方式对比 | 信息速率 300 Mbps');
%     exportgraphics(fig, cfg.plotFile, 'Resolution', 220);
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
