function metrics = run_qam_extension_evaluation(params)
%RUN_QAM_EXTENSION_EVALUATION 16QAM/32QAM extension simulation.
%
% This is an extension link, not an official CCSDS TM modulation mode.
% It keeps the familiar evaluation style while using a custom QAM
% modulator/demodulator path.
%
% Example:
%   p = struct('modType','16QAM','symbolRate',100e6,'sps',8, ...
%       'snr',18,'cfo',20000,'phaseOffset',10,'delay',0.2, ...
%       'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%       'RolloffFactor',0.35,'showFigures',true);
%   m = run_qam_extension_evaluation(p);

    if nargin < 1 || isempty(params)
        params = struct();
    end
    if ischar(params) || isstring(params)
        opt = jsondecode(char(params));
    else
        opt = params;
    end

    opt = localDefaults(opt);
    tStart = tic;

    [txWaveform, txInfo] = qamExtensionModulator(opt);
    [rxWaveform, chanInfo] = qamExtensionChannel(txWaveform, opt, txInfo.Fs);
    [rxBits, rxInfo] = qamExtensionDemodulator(rxWaveform, opt, txInfo);

    nBits = min(numel(txInfo.infoBits), numel(rxBits));
    if nBits > 0
        err = sum(txInfo.infoBits(1:nBits) ~= rxBits(1:nBits));
        ber = err / nBits;
    else
        err = 0;
        ber = 0.5;
    end

    [evmPct, merDB] = localEvmMer(rxInfo.rxSymbols, txInfo.refConst);
    paprDB = 10*log10(max(abs(txWaveform).^2) / mean(abs(txWaveform).^2));

    metrics = struct();
    metrics.success = true;
    metrics.errorMsg = '';
    metrics.modType = char(opt.modType);
    metrics.channelCoding = char(opt.channelCoding);
    metrics.BER = ber;
    metrics.ber = ber;
    metrics.NumErrors = err;
    metrics.NumBits = nBits;
    metrics.EVM_post_pct = evmPct;
    metrics.MER_dB = merDB;
    metrics.SNR_est_dB = merDB;
    metrics.PAPR_dB = paprDB;
    metrics.LockRate = double(nBits > 0);
    metrics.Fs = txInfo.Fs;
    metrics.symbolRate = opt.symbolRate;
    metrics.snr_in = opt.snr;
    metrics.cfo_in = opt.cfo;
    metrics.phase_in = opt.phaseOffset;
    metrics.delay_in = opt.delay;
    metrics.ElapsedTime = toc(tStart);
    metrics.txInfo = txInfo;
    metrics.rxInfo = rxInfo;
    metrics.chanInfo = chanInfo;

    printQAMMetrics(metrics);
    if opt.showFigures
        plotQAMExtension(metrics, txInfo, rxInfo, txWaveform, rxWaveform);
    end
end

function opt = localDefaults(opt)
    opt = setDefault(opt, 'modType', '16QAM');
    opt = setDefault(opt, 'symbolRate', 100e6);
    opt = setDefault(opt, 'sps', 8);
    opt = setDefault(opt, 'snr', 18);
    opt = setDefault(opt, 'cfo', 0);
    opt = setDefault(opt, 'phaseOffset', 0);
    opt = setDefault(opt, 'delay', 0);
    opt = setDefault(opt, 'channelCoding', 'none');
    opt = setDefault(opt, 'ConvolutionalCodeRate', '1/2');
    opt = setDefault(opt, 'RolloffFactor', 0.35);
    opt = setDefault(opt, 'FilterSpanInSymbols', 10);
    opt = setDefault(opt, 'numFrames', 40);
    opt = setDefault(opt, 'bitsPerFrame', 4096);
    opt = setDefault(opt, 'showFigures', true);

    opt.modType = upper(string(opt.modType));
    opt.channelCoding = lower(string(opt.channelCoding));
    opt.symbolRate = double(opt.symbolRate);
    opt.sps = double(opt.sps);
    opt.snr = double(opt.snr);
    opt.cfo = double(opt.cfo);
    opt.phaseOffset = double(opt.phaseOffset);
    opt.delay = double(opt.delay);
    opt.RolloffFactor = double(opt.RolloffFactor);
    opt.FilterSpanInSymbols = double(opt.FilterSpanInSymbols);
    opt.numFrames = double(opt.numFrames);
    opt.bitsPerFrame = double(opt.bitsPerFrame);
    opt.showFigures = logical(opt.showFigures);
end

function s = setDefault(s, name, value)
    if ~isfield(s, name) || isempty(s.(name))
        s.(name) = value;
    end
end

function [txWaveform, info] = qamExtensionModulator(opt)
    M = qamOrder(opt.modType);
    k = log2(M);
    Fs = opt.symbolRate * opt.sps;

    nInfoBits = max(k, opt.numFrames * opt.bitsPerFrame);
    nInfoBits = nInfoBits - mod(nInfoBits, k);
    infoBits = int8(randi([0 1], nInfoBits, 1));

    [codedBits, encInfo] = qamExtensionEncode(infoBits, opt);
    codedBits = codedBits(:);
    padBits = mod(-numel(codedBits), k);
    if padBits > 0
        codedBits = [codedBits; zeros(padBits, 1, 'int8')];
    end

    txSymbols = qammod(double(codedBits), M, ...
        'InputType', 'bit', ...
        'UnitAveragePower', true);

    txFilter = comm.RaisedCosineTransmitFilter( ...
        'Shape', 'Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'OutputSamplesPerSymbol', opt.sps);

    txWaveform = txFilter(txSymbols);

    info = struct();
    info.M = M;
    info.bitsPerSymbol = k;
    info.Fs = Fs;
    info.infoBits = infoBits;
    info.codedBits = int8(codedBits);
    info.padBits = padBits;
    info.txSymbols = txSymbols;
    info.refConst = qammod((0:M-1).', M, 'UnitAveragePower', true);
    info.encInfo = encInfo;
end

function [codedBits, encInfo] = qamExtensionEncode(infoBits, opt)
    code = lower(string(opt.channelCoding));
    encInfo = struct('coding', char(code));

    if code == "convolutional"
        trellis = poly2trellis(7, [171 133]);
        if isfield(opt, 'ConvolutionalCodeRate')
            rate = string(opt.ConvolutionalCodeRate);
        else
            rate = "1/2";
        end

        if rate ~= "1/2"
            warning('QAM extension currently uses convolutional 1/2 for unsupported rate %s.', rate);
            rate = "1/2";
        end

        enc = comm.ConvolutionalEncoder( ...
            'TrellisStructure', trellis, ...
            'TerminationMethod', 'Terminated');
        codedBits = int8(enc(logical(infoBits)));
        encInfo.trellis = trellis;
        encInfo.rate = char(rate);
        encInfo.puncture = [];
        encInfo.tracebackDepth = 35;
    else
        codedBits = int8(infoBits);
        encInfo.rate = '1';
    end
end

function [rxWaveform, chanInfo] = qamExtensionChannel(txWaveform, opt, Fs)
    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', opt.cfo, ...
            'PhaseOffset', opt.phaseOffset, ...
            'SampleRate', Fs);
        rxWaveform = pfo(txWaveform);
    else
        rxWaveform = txWaveform;
    end

    if opt.delay ~= 0
        vfd = dsp.VariableFractionalDelay('InterpolationMethod', 'Farrow');
        rxWaveform = vfd(rxWaveform, opt.delay);
    end

    rxWaveform = awgn(rxWaveform, opt.snr, 'measured');
    chanInfo = struct('Fs', Fs);
end

function [rxBits, rxInfo] = qamExtensionDemodulator(rxWaveform, opt, txInfo)
    M = txInfo.M;
    Fs = txInfo.Fs;

    % This extension demo uses known CFO/phase compensation so that the QAM
    % modulator/demodulator path can be validated before adding a blind loop.
    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', -opt.cfo, ...
            'PhaseOffset', -opt.phaseOffset, ...
            'SampleRate', Fs);
        rxWaveform = pfo(rxWaveform);
    end

    rxFilter = comm.RaisedCosineReceiveFilter( ...
        'Shape', 'Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol', opt.sps, ...
        'DecimationFactor', opt.sps);

    rxSymbolsAll = rxFilter(rxWaveform);
    groupDelaySymbols = opt.FilterSpanInSymbols;
    if numel(rxSymbolsAll) > groupDelaySymbols
        rxSymbols = rxSymbolsAll(groupDelaySymbols+1:end);
    else
        rxSymbols = rxSymbolsAll;
    end
    rxSymbols = rxSymbols(1:min(numel(rxSymbols), numel(txInfo.txSymbols)));

    demodBits = qamdemod(rxSymbols, M, ...
        'OutputType', 'bit', ...
        'UnitAveragePower', true);
    demodBits = int8(demodBits(:));

    if txInfo.padBits > 0 && numel(demodBits) >= txInfo.padBits
        demodBits = demodBits(1:end-txInfo.padBits);
    end

    rxBits = qamExtensionDecode(demodBits, txInfo.encInfo, numel(txInfo.infoBits));

    rxInfo = struct();
    rxInfo.rxSymbols = rxSymbols;
    rxInfo.demodBits = demodBits;
end

function rxBits = qamExtensionDecode(demodBits, encInfo, nInfoBits)
    if string(encInfo.coding) == "convolutional"
        dec = comm.ViterbiDecoder( ...
            'TrellisStructure', encInfo.trellis, ...
            'InputFormat', 'Hard', ...
            'TerminationMethod', 'Terminated', ...
            'TracebackDepth', encInfo.tracebackDepth);
        decBits = int8(dec(logical(demodBits)));
        rxBits = decBits(1:min(numel(decBits), nInfoBits));
    else
        rxBits = int8(demodBits(1:min(numel(demodBits), nInfoBits)));
    end
end

function M = qamOrder(modType)
    s = upper(string(modType));
    if contains(s, "16QAM")
        M = 16;
    elseif contains(s, "32QAM")
        M = 32;
    else
        error('Unsupported QAM modulation: %s. Use 16QAM or 32QAM.', modType);
    end
end

function [evmPct, merDB] = localEvmMer(rxSymbols, refConst)
    if isempty(rxSymbols)
        evmPct = NaN;
        merDB = NaN;
        return;
    end

    rxSymbols = rxSymbols(:);
    [~, idx] = min(abs(rxSymbols - refConst.'), [], 2);
    nearest = refConst(idx);

    gain = (nearest' * rxSymbols) / max(rxSymbols' * rxSymbols, eps);
    aligned = gain * rxSymbols;
    err = aligned - nearest;

    evmRms = sqrt(mean(abs(err).^2) / mean(abs(nearest).^2));
    evmPct = 100 * evmRms;
    merDB = -20 * log10(max(evmRms, eps));
end

function printQAMMetrics(m)
    fprintf('\n========= QAM 扩展链路评估结果 =========\n');
    fprintf(' 调制方式 : %s\n', m.modType);
    fprintf(' 编码方式 : %s\n', m.channelCoding);
    fprintf(' 输入 SNR : %.1f dB, CFO=%.1f Hz, Phase=%.1f deg, Delay=%.3f samples\n', ...
        m.snr_in, m.cfo_in, m.phase_in, m.delay_in);
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6g\n', m.BER);
    fprintf(' EVM          : %6.2f %%\n', m.EVM_post_pct);
    fprintf(' MER          : %6.2f dB\n', m.MER_dB);
    fprintf(' SNR_est      : %6.2f dB\n', m.SNR_est_dB);
    fprintf(' PAPR (Tx)    : %6.2f dB\n', m.PAPR_dB);
    fprintf('========================================\n');
end

function plotQAMExtension(m, txInfo, rxInfo, txWaveform, rxWaveform)
    figure('Name','QAM extension evaluation','NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], 'Position',[120 100 1300 430]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    nShow = min(2500, numel(rxInfo.rxSymbols));
    plot(real(rxInfo.rxSymbols(1:nShow)), imag(rxInfo.rxSymbols(1:nShow)), '.', ...
        'Color',[0 0.28 0.65], 'MarkerSize',5);
    hold on;
    plot(real(txInfo.refConst), imag(txInfo.refConst), 'rx', 'LineWidth',1.8, 'MarkerSize',8);
    grid on; axis equal;
    xlabel('I'); ylabel('Q');
    title(sprintf('%s 星座图 | EVM %.1f%%', m.modType, m.EVM_post_pct));

    nexttile;
    [ptx, f] = periodogram(txWaveform, [], 4096, m.Fs, 'centered');
    [prx, ~] = periodogram(rxWaveform, [], 4096, m.Fs, 'centered');
    plot(f/1e6, 10*log10(ptx/max(ptx)), 'b', 'LineWidth',1.2);
    hold on;
    plot(f/1e6, 10*log10(prx/max(prx)), 'r', 'LineWidth',1.0);
    grid on;
    xlabel('频率 (MHz)'); ylabel('归一化 PSD (dB)');
    title('发送/接收频谱');
    legend({'Tx','Rx'}, 'Location','best');

    nexttile;
    bar(categorical({'BER','EVM(%)','MER(dB)'}), [max(m.BER, 1e-6), m.EVM_post_pct, m.MER_dB]);
    grid on;
    title('核心指标');
end
