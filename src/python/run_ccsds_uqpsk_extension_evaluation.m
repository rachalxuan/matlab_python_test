function metrics = run_ccsds_uqpsk_extension_evaluation(params)
%RUN_CCSDS_UQPSK_EXTENSION_EVALUATION CCSDS TM + UQPSK extension test chain.
%
% This standalone script keeps CCSDS TM synchronization/channel coding in
% ccsdsTMWaveformGenerator, then maps the encoded bit stream onto an
% unbalanced QPSK constellation. It is intended as the first integration
% test before merging UQPSK into run_ccsds_tm_evaluation.
%
% Example:
%   p = struct('symbolRate',100e6,'sps',8,'snr',18, ...
%       'cfo',20000,'phaseOffset',10,'delay',0.1, ...
%       'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%       'RRatio',2,'ARatio',2,'showFigures',true);
%   m = run_ccsds_uqpsk_extension_evaluation(p);

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

    [txWaveform, txInfo] = buildCCSDSTMUQPSKTx(opt);

    %% Channel impairments
    rxWaveform = txWaveform;
    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', opt.cfo, ...
            'PhaseOffset', opt.phaseOffset, ...
            'SampleRate', txInfo.Fs);
        rxWaveform = pfo(rxWaveform);
    end
    if opt.delay ~= 0
        vfd = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        rxWaveform = vfd(rxWaveform, opt.delay);
    end
    rxWaveform = awgn(rxWaveform, opt.snr, 'measured');

    %% UQPSK receiver: coarse CFO, matched filter, timing sync, carrier sync
    coarseSynced = rxWaveform;
    estCFO = 0;

    if opt.enableUQPSKFFTCoarseCFO
        [coarseSynced, estCFO] = uqpskFourthPowerFFTCoarseCFO( ...
            rxWaveform, txInfo.Fs, opt.uqpskMaxCFOHz, opt.uqpskCFOFFTLen);

        if opt.debugUQPSK
            fprintf('   [UQPSK 4th-power CFO] estimated = %+.3f Hz, input = %+.3f Hz, error = %+.3f Hz\n', ...
                estCFO, opt.cfo, estCFO - opt.cfo);
        end
    end

    rxFilterDecim = max(1, round(opt.sps/2));
    rxFilter = comm.RaisedCosineReceiveFilter( ...
        'Shape','Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol', opt.sps, ...
        'DecimationFactor', rxFilterDecim);


    
    nDecimTrim = mod(numel(coarseSynced), rxFilterDecim);
    if nDecimTrim ~= 0
        coarseForFilter = coarseSynced(1:end-nDecimTrim);
    else
        coarseForFilter = coarseSynced;
    end
    filtered = rxFilter(coarseForFilter);
    spsAfterFilter = opt.sps / rxFilterDecim;

    timingSync = comm.SymbolSynchronizer( ...
        'TimingErrorDetector','Gardner (non-data-aided)', ...
        'SamplesPerSymbol', spsAfterFilter, ...
        'DetectorGain', 2.7, ...
        'Modulation','PAM/PSK/QAM', ...
        'DampingFactor', 1/sqrt(2), ...
        'NormalizedLoopBandwidth', opt.timingLoopBandwidth);
    timeSynced = timingSync(filtered);
    timeSynced = trimBestDelay(timeSynced, txInfo.txSymbols, opt.FilterSpanInSymbols + 16);
%     % =========================================================
%     % UQPSK 粗频偏估计/补偿
%     % 注意：这里使用 txInfo.txSymbols，是仿真调试版。
%     % 真实接收机应改成 ASM/导频辅助估计。
%     % =========================================================
%     estCFO = 0;
%     if opt.enableUQPSKCoarseCFO
%         [timeSynced, estCFO] = uqpskKnownSymbolCFOComp( ...
%             timeSynced, txInfo.txSymbols, opt.symbolRate, opt.uqpskCFOEstSymbols);
% 
%         if isfield(opt,'debugUQPSK') && opt.debugUQPSK
%             fprintf('   [UQPSK CFO debug] estimated coarse CFO = %.3f Hz\n', estCFO);
%         end
%     end


%     carrierSync = comm.CarrierSynchronizer( ...
%         'Modulation','QPSK', ...
%         'SamplesPerSymbol', 1, ...
%         'DampingFactor', 1/sqrt(2), ...
%         'NormalizedLoopBandwidth', opt.carrierLoopBandwidth);
%     rxSymbols = carrierSync(timeSynced);
%     rxSymbols = trimBestDelay(rxSymbols, txInfo.txSymbols, opt.FilterSpanInSymbols + 16);
%     rxSymbols = rxSymbols(1:min(numel(rxSymbols), numel(txInfo.txSymbols)));
% 
%     rxSymbols = decisionDirectedNormalize(rxSymbols, txInfo.refConst, opt.ddNormalizeIterations);
%     [rxSymbols, phaseInfo] = resolveUQPSKAmbiguity(rxSymbols, txInfo);
    % =========================================================
    % UQPSK 载波恢复
    % qpsk-sync       : 原来的 QPSK CarrierSynchronizer
    % uqpsk-teacher   : 借老师 UQPSKDem.m 的相位误差公式
    % =========================================================
    switch lower(string(opt.carrierRecoveryMode))
        case "qpsk-sync"
            carrierSync = comm.CarrierSynchronizer( ...
                'Modulation','QPSK', ...
                'SamplesPerSymbol', 1, ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', opt.carrierLoopBandwidth);
            rxSymbols = carrierSync(timeSynced);

        case "uqpsk-teacher"
            rxSymbols = uqpskCarrierRecoverTeacherStyle( ...
                timeSynced, opt.ARatio, opt.uqpskCarrierLoopBW);

        otherwise
            rxSymbols = timeSynced;
    end

    % 先用相关性粗对齐
    rxSymbols = trimBestDelay(rxSymbols, txInfo.txSymbols, opt.FilterSpanInSymbols + 64);
    rxSymbols = rxSymbols(1:min(numel(rxSymbols), numel(txInfo.txSymbols)));

    % 幅度/相位归一
    rxSymbols = decisionDirectedNormalize(rxSymbols, txInfo.refConst, opt.ddNormalizeIterations);

    % 相位/共轭模糊搜索
    [rxSymbols, phaseInfo] = resolveUQPSKAmbiguity(rxSymbols, txInfo);

    if ~isfield(opt,'debugUQPSK') || opt.debugUQPSK
        uqpskDelayDebug(rxSymbols, txInfo, 20);
        uqpskPhaseDebug(rxSymbols, txInfo);
    end

    %% UQPSK demapping and CCSDS TM decoding
    [rxSoftBits, hardBits] = uqpskDemapBits(rxSymbols, txInfo);

    nHard = min(numel(hardBits), numel(txInfo.encodedBits));
    if nHard > 0
        hardErr = sum(hardBits(1:nHard) ~= txInfo.encodedBits(1:nHard));
        hardBER = hardErr / nHard;
    else
        hardErr = 0;
        hardBER = 0.5;
    end

    [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(rxSoftBits, opt, txInfo);
    [berVal, errCount, bitsCompared, lockRate, frameInfo] = ...
        compareFrameBits(txInfo.validTxFrames, decodedBits, opt.berWarmUpFrames);

    [evmPct, merDB] = uqpskEvmMer(rxSymbols, txInfo.refConst);
    paprDB = 10*log10(max(abs(txWaveform).^2) / mean(abs(txWaveform).^2));

    metrics = struct();
    metrics.success = true;
    metrics.errorMsg = '';
    metrics.info = 'CCSDS TM coding + UQPSK extension';
    metrics.modType = 'UQPSK';
    metrics.channelCoding = char(opt.channelCoding);
    metrics.BER = berVal;
    metrics.ber = berVal;
    metrics.berWarmUpFrames = opt.berWarmUpFrames;
    metrics.berFrames = opt.berFrames;
    metrics.NumErrors = errCount;
    metrics.NumBits = bitsCompared;
    metrics.EVM_post_pct = evmPct;
    metrics.MER_dB = merDB;
    metrics.SNR_est_dB = merDB;
    metrics.PAPR_dB = paprDB;
    metrics.LockRate = lockRate;
    metrics.FrameLock_pct = 100*lockRate;
    metrics.EncodedHardBER = hardBER;
    metrics.EncodedHardErrors = hardErr;
    metrics.EncodedHardBits = nHard;
    metrics.Fs = txInfo.Fs;
    metrics.symbolRate = opt.symbolRate;
    metrics.RRatio = opt.RRatio;
    metrics.ARatio = opt.ARatio;
    metrics.snr_in = opt.snr;
    metrics.cfo_in = opt.cfo;
    metrics.phase_in = opt.phaseOffset;
    metrics.delay_in = opt.delay;
    metrics.estimatedCFO = estCFO;
    metrics.cfoError = estCFO - opt.cfo;
    metrics.ElapsedTime = toc(tStart);
    metrics.txInfo = txInfo;
    metrics.rxInfo = struct('rxWaveform',rxWaveform, ...
        'coarseSynced',coarseSynced, 'filtered',filtered, ...
        'timeSynced',timeSynced, 'rxSymbols',rxSymbols, ...
        'softBits',rxSoftBits, 'hardBits',hardBits);
    metrics.decInfo = decInfo;
    metrics.frameInfo = frameInfo;
    metrics.phaseInfo = phaseInfo;

    if opt.debugUQPSK
        fprintf('   [UQPSK DEBUG] encoded hard BER = %.6g (%d/%d)\n', ...
            hardBER, hardErr, nHard);
        fprintf('   [UQPSK DEBUG] phase resolve = %s, BER=%.6g (%d/%d)\n', ...
            phaseInfo.name, phaseInfo.ber, phaseInfo.errors, phaseInfo.bits);
        fprintf('   [UQPSK DEBUG] decoder polarity = %s\n', decInfo.SelectedSoftPolarity);
    end

    printUQPSKResults(metrics);

    if opt.showFigures
        plotUQPSKResults(metrics, txWaveform, rxWaveform);
    end
end

function opt = localDefaults(opt)
    opt = setDefault(opt, 'modType', 'UQPSK');
    opt = setDefault(opt, 'symbolRate', 100e6);
    opt = setDefault(opt, 'sps', 8);
    opt = setDefault(opt, 'snr', 18);
    opt = setDefault(opt, 'cfo', 20000);
    opt = setDefault(opt, 'phaseOffset', 10);
    opt = setDefault(opt, 'delay', 0.1);
    opt = setDefault(opt, 'channelCoding', 'convolutional');
    opt = setDefault(opt, 'ConvolutionalCodeRate', '1/2');
    opt = setDefault(opt, 'RolloffFactor', 0.35);
    opt = setDefault(opt, 'FilterSpanInSymbols', 10);
    opt = setDefault(opt, 'RRatio', 2);
    opt = setDefault(opt, 'ARatio', 2);
    opt = setDefault(opt, 'timingLoopBandwidth', 0.01);
    opt = setDefault(opt, 'carrierLoopBandwidth', 0.005);
    opt = setDefault(opt, 'carrierRecoveryMode', 'uqpsk-teacher');
    opt = setDefault(opt, 'uqpskCarrierLoopBW', 0.002);
    opt = setDefault(opt, 'ddNormalizeIterations', 4);
    opt = setDefault(opt, 'hasASM', true);
    opt = setDefault(opt, 'hasRandomizer', false);
    opt = setDefault(opt, 'NumBytesInTransferFrame', 1115);
    opt = setDefault(opt, 'berWarmUpFrames', 4);
    opt = setDefault(opt, 'berFrames', 20);
    opt = setDefault(opt, 'showFigures', true);
    opt = setDefault(opt, 'debugUQPSK', true);
    opt = setDefault(opt, 'enableUQPSKFFTCoarseCFO', false);
    
    opt.channelCoding = canonicalChannelCodingLocal(opt.channelCoding);
    opt.symbolRate = double(opt.symbolRate);
    opt.sps = max(2, round(double(opt.sps)));
    if ~isfield(opt,'uqpskMaxCFOHz') || isempty(opt.uqpskMaxCFOHz)
        opt.uqpskMaxCFOHz = 0.01 * opt.symbolRate;   % 默认 ±1% 符号率
    end
    opt = setDefault(opt, 'uqpskCFOFFTLen', 2^17);
    FsDefault = opt.symbolRate * opt.sps;
    opt.uqpskMaxCFOHz = double(opt.uqpskMaxCFOHz);
    opt.uqpskMaxCFOHz = min(opt.uqpskMaxCFOHz, 0.9 * FsDefault/8);
    opt.snr = double(opt.snr);
    opt.cfo = double(opt.cfo);
    opt.phaseOffset = double(opt.phaseOffset);
    opt.delay = double(opt.delay);
    opt.RolloffFactor = double(opt.RolloffFactor);
    opt.FilterSpanInSymbols = double(opt.FilterSpanInSymbols);
    opt.RRatio = max(1, round(double(opt.RRatio)));
    opt.ARatio = max(eps, double(opt.ARatio));
%     opt.cfoCorrectionMode = 'none';
    opt.timingLoopBandwidth = double(opt.timingLoopBandwidth);
    opt.carrierLoopBandwidth = double(opt.carrierLoopBandwidth);
    opt.uqpskCarrierLoopBW = double(opt.uqpskCarrierLoopBW);
    opt.ddNormalizeIterations = max(0, round(double(opt.ddNormalizeIterations)));
    opt.hasASM = logical(opt.hasASM);
    opt.hasRandomizer = logical(opt.hasRandomizer);
    opt.NumBytesInTransferFrame = double(opt.NumBytesInTransferFrame);
    opt.berWarmUpFrames = max(0, round(double(opt.berWarmUpFrames)));
    opt.berFrames = max(1, round(double(opt.berFrames)));
    opt.showFigures = logical(opt.showFigures);
    opt.debugUQPSK = logical(opt.debugUQPSK);
    opt.enableUQPSKFFTCoarseCFO = logical(opt.enableUQPSKFFTCoarseCFO);
    opt.uqpskMaxCFOHz = double(opt.uqpskMaxCFOHz);
    opt.uqpskCFOFFTLen = round(double(opt.uqpskCFOFFTLen));
end

function s = setDefault(s, name, value)
    if ~isfield(s, name) || isempty(s.(name))
        s.(name) = value;
    end
end

function [txWaveform, infoOut] = buildCCSDSTMUQPSKTx(opt)
    Fs = opt.symbolRate * opt.sps;

    args = { ...
        'WaveformSource', 'synchronization and channel coding', ...
        'Modulation', 'UQPSK', ...
        'ChannelCoding', opt.channelCoding, ...
        'SamplesPerSymbol', opt.sps, ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"]))
        args = [args, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}]; %#ok<AGROW>
    end
    if codeKey == "convolutional" && isfield(opt, 'ConvolutionalCodeRate')
        args = [args, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}]; %#ok<AGROW>
    end
    if any(strcmp(codeKey, ["turbo", "ldpc"]))
        if isfield(opt, 'CodeRate')
            args = [args, {'CodeRate', string(opt.CodeRate)}]; %#ok<AGROW>
        end
        if isfield(opt, 'NumBitsInInformationBlock')
            args = [args, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}]; %#ok<AGROW>
        end
    end
    if codeKey == "ldpc" && isfield(opt, 'IsLDPCOnSMTF')
        args = [args, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}]; %#ok<AGROW>
    end
    if codeKey == "ldpc" && isfield(opt, 'LDPCCodeblockSize') && ~isempty(opt.LDPCCodeblockSize)
        args = [args, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}]; %#ok<AGROW>
    end
    args = appendRSArgsLocal(args, opt);

    tmWaveGen = ccsdsTMWaveformGenerator(args{:});
    genInfo = info(tmWaveGen);

    bitsPerFrame = tmWaveGen.NumInputBits;
    totalFrames = opt.berWarmUpFrames + opt.berFrames;
    numHeaderBits = 8;
    msg = zeros(bitsPerFrame * totalFrames, 1, 'int8');
    validTxFrames = cell(totalFrames, 1);
    for iFrame = 1:totalFrames
        header = int8(de2bi(mod(iFrame-1, 256), numHeaderBits, 'left-msb').');
        payload = int8(randi([0 1], bitsPerFrame - numHeaderBits, 1));
        frameBits = [header; payload];
        idx = (iFrame-1)*bitsPerFrame + (1:bitsPerFrame);
        msg(idx) = frameBits;
        validTxFrames{iFrame} = frameBits;
    end

%     [~, encodedBits] = tmWaveGen(msg);
%     encodedBits = int8(encodedBits(:));
%     groupBits = opt.RRatio + 1;
%     padBits = mod(-numel(encodedBits), groupBits);
%     if padBits > 0
%         encodedBitsPadded = [encodedBits; zeros(padBits, 1, 'int8')];
%     else
%         encodedBitsPadded = encodedBits;
%     end
% 
%     txSymbols = uqpskMapBits(encodedBitsPadded, opt.RRatio, opt.ARatio);
%     refConst = uqpskReferenceConstellation(opt.ARatio);
% 
%     rrc = rcosdesign(opt.RolloffFactor, opt.FilterSpanInSymbols, opt.sps, 'sqrt');
%     txWaveform = upfirdn(txSymbols, rrc(:), opt.sps, 1);
%     txWaveform = complex(txWaveform(:));

    [txWaveform, encodedBits] = tmWaveGen(msg);
    txWaveform = complex(txWaveform(:));
    encodedBits = int8(encodedBits(:));

    groupBits = opt.RRatio + 1;
    padBits = mod(-numel(encodedBits), groupBits);
    if padBits > 0
        encodedBitsPadded = [encodedBits; zeros(padBits, 1, 'int8')];
    else
        encodedBitsPadded = encodedBits;
    end

    % 这里的 txSymbols 只作为仿真 debug / EVM / delay 对齐参考；
    % 真正发送波形已经由 ccsdsTMWaveformGenerator 生成。
    txSymbols = uqpskMapBits(encodedBitsPadded, opt.RRatio, opt.ARatio);
    refConst = uqpskReferenceConstellation(opt.ARatio);


    infoOut = struct();
    infoOut.Fs = Fs;
    infoOut.bitsPerFrame = bitsPerFrame;
    infoOut.validTxFrames = validTxFrames;
    infoOut.encodedBits = encodedBits;
    infoOut.encodedBitsPadded = encodedBitsPadded;
    infoOut.padBits = padBits;
    infoOut.groupBits = groupBits;
    infoOut.RRatio = opt.RRatio;
    infoOut.ARatio = opt.ARatio;
    infoOut.txSymbols = txSymbols;
    infoOut.refConst = refConst;
    infoOut.tmWaveGenInfo = genInfo;
end

function symbols = uqpskMapBits(bits, rRatio, aRatio)
    bits = int8(bits(:) ~= 0);
    groupBits = rRatio + 1;
    nGroups = floor(numel(bits) / groupBits);
    b = reshape(bits(1:nGroups*groupBits), groupBits, nGroups);

    iBits = b(1:rRatio, :);
    qBits = b(rRatio+1, :);
    iVals = 1 - 2*double(iBits(:));
    qVals = repelem(1 - 2*double(qBits(:)), rRatio);
    symbols = complex(iVals, qVals/aRatio);
    symbols = symbols / sqrt(mean(abs(symbols).^2));
end

function refConst = uqpskReferenceConstellation(aRatio)
    raw = [1+1j/aRatio; -1+1j/aRatio; 1-1j/aRatio; -1-1j/aRatio];
    refConst = raw / sqrt(mean(abs(raw).^2));
end

function [softBits, hardBits] = uqpskDemapBits(symbols, txInfo)
    symbols = symbols(:);
    rRatio = txInfo.RRatio;
    aRatio = txInfo.ARatio;
    groupBits = txInfo.groupBits;
    nGroups = floor(numel(symbols) / rRatio);
    symbols = symbols(1:nGroups*rRatio);
    symMat = reshape(symbols, rRatio, nGroups);

    iSoft = real(symMat);
    qSoft = mean(imag(symMat), 1) * aRatio;

    softMat = [iSoft; qSoft];
    softBits = double(softMat(:));
    hardBits = int8(softBits < 0);

    if txInfo.padBits > 0 && numel(softBits) >= txInfo.padBits
        softBits = softBits(1:end-txInfo.padBits);
        hardBits = hardBits(1:end-txInfo.padBits);
    end
    softBits = softBits(1:min(numel(softBits), numel(txInfo.encodedBits)));
    hardBits = hardBits(1:min(numel(hardBits), numel(txInfo.encodedBits)));
end

function [bestSymbols, bestInfo] = resolveUQPSKAmbiguity(rxSymbols, txInfo)
    rxSymbols = rxSymbols(:);
    candidates = { ...
        rxSymbols, -rxSymbols, 1j*rxSymbols, -1j*rxSymbols, ...
        conj(rxSymbols), -conj(rxSymbols), 1j*conj(rxSymbols), -1j*conj(rxSymbols)};
    names = {'x','-x','j*x','-j*x','conj(x)','-conj(x)','j*conj(x)','-j*conj(x)'};

    bestBER = inf;
    bestIdx = 1;
    bestErr = 0;
    bestBits = 0;

    for i = 1:numel(candidates)
        [~, hardBits] = uqpskDemapBits(candidates{i}, txInfo);
        n = min(numel(hardBits), numel(txInfo.encodedBits));
        if n > 0
            err = sum(hardBits(1:n) ~= txInfo.encodedBits(1:n));
            ber = err / n;
        else
            err = 0;
            ber = 0.5;
        end
        if ber < bestBER
            bestBER = ber;
            bestIdx = i;
            bestErr = err;
            bestBits = n;
        end
    end

    bestSymbols = candidates{bestIdx};
    bestInfo = struct('name',names{bestIdx}, ...
        'ber',bestBER, 'errors',bestErr, 'bits',bestBits);
end

function y = decisionDirectedNormalize(y, refConst, numIter)
    y = y(:);
    refConst = refConst(:);
    if isempty(y) || isempty(refConst) || numIter <= 0
        return;
    end

    for k = 1:numIter
        [~, idx] = min(abs(y - refConst.'), [], 2);
        dHat = refConst(idx);
        g = (dHat' * y) / max(dHat' * dHat, eps);
        if isfinite(real(g)) && isfinite(imag(g)) && abs(g) > eps
            y = y / g;
        else
            break;
        end
    end
end

function y = trimBestDelay(y, refSymbols, maxDelay)
    if isempty(y) || isempty(refSymbols)
        return;
    end

    y = y(:);
    refSymbols = refSymbols(:);
    maxDelay = min(max(0, round(maxDelay)), max(0, numel(y)-1));
    bestDelay = 0;
    bestMetric = -inf;
    nUseMax = min(5000, min(numel(y), numel(refSymbols)));

    for d = 0:maxDelay
        nUse = min(nUseMax, min(numel(y)-d, numel(refSymbols)));
        if nUse < 64
            continue;
        end
        yr = y(d+(1:nUse));
        xr = refSymbols(1:nUse);
        metric = abs(xr' * yr) / max(norm(xr) * norm(yr), eps);
        if metric > bestMetric
            bestMetric = metric;
            bestDelay = d;
        end
    end
    if bestDelay > 0
        y = y(bestDelay+1:end);
    end
end

function [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(softBits, opt, txInfo)
    candidates = {double(softBits(:)), -double(softBits(:))};
    candidateNames = {'UQPSK soft', 'inverted UQPSK soft'};
    bestBER = inf;
    bestErr = 0;
    bestBits = 0;
    bestIdx = 1;
    bestDecoded = [];
    bestLock = 0;
    bestFrameInfo = struct();

    for iCandidate = 1:numel(candidates)
        candDecoded = decodeCCSDSTMBitsOnce(candidates{iCandidate}, opt);
        [candBER, candErr, candBits, candLock, candFrameInfo] = ...
            compareFrameBits(txInfo.validTxFrames, candDecoded, opt.berWarmUpFrames);
        if candBER < bestBER || (candBER == bestBER && candLock > bestLock)
            bestBER = candBER;
            bestErr = candErr;
            bestBits = candBits;
            bestIdx = iCandidate;
            bestDecoded = candDecoded;
            bestLock = candLock;
            bestFrameInfo = candFrameInfo;
        end
    end

    decodedBits = bestDecoded;
    lockRate = bestLock;
    decInfo = struct();
    decInfo.SelectedSoftPolarity = candidateNames{bestIdx};
    decInfo.CandidateBER = bestBER;
    decInfo.CandidateErrors = bestErr;
    decInfo.CandidateBits = bestBits;
    decInfo.FrameInfo = bestFrameInfo;
end

function decodedBits = decodeCCSDSTMBitsOnce(softBits, opt)
    decArgs = {'ChannelCoding', opt.channelCoding, ...
        'Modulation', 'QPSK', ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM, ...
        'DisablePhaseAmbiguityResolution', true};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"])) || ...
            (isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF))
        decArgs = [decArgs, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}]; %#ok<AGROW>
    end
    if isfield(opt, 'ConvolutionalCodeRate')
        decArgs = [decArgs, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}]; %#ok<AGROW>
    end
    if isfield(opt, 'CodeRate') && ~strcmp(char(opt.CodeRate), 'N/A')
        decArgs = [decArgs, {'CodeRate', char(opt.CodeRate)}]; %#ok<AGROW>
    end
    if isfield(opt, 'NumBitsInInformationBlock')
        decArgs = [decArgs, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}]; %#ok<AGROW>
    end
    if isfield(opt, 'IsLDPCOnSMTF')
        decArgs = [decArgs, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}]; %#ok<AGROW>
    end
    if isfield(opt, 'LDPCCodeblockSize') && ~isempty(opt.LDPCCodeblockSize)
        decArgs = [decArgs, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}]; %#ok<AGROW>
    end
    decArgs = appendRSArgsLocal(decArgs, opt);

    decoderObj = HelperCCSDSTMDecoder(decArgs{:});
    decodedBits = decoderObj(softBits(:));
end

function [berVal, errCount, bitsCompared, lockRate, frameInfo] = compareFrameBits(validTxFrames, decodedBits, numWarmUp)
    if nargin < 3 || isempty(numWarmUp)
        numWarmUp = 0;
    end

    frameInfo = struct();
    frameInfo.numRx = 0;
    frameInfo.framesMatched = 0;
    frameInfo.firstMatched = NaN;
    frameInfo.perFrameBER = [];
    frameInfo.rxIds = [];
    frameInfo.matchedMask = [];

    if isempty(decodedBits) || isempty(validTxFrames)
        berVal = 0.5;
        errCount = 0;
        bitsCompared = 0;
        lockRate = 0;
        return;
    end

    bitsPerFrame = length(validTxFrames{1});
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k = 1:length(validTxFrames)
        fr = int8(validTxFrames{k}(:));
        id = bi2de(double(fr(1:8)).','left-msb');
        txMap(id) = fr;
    end

    decodedBits = int8(decodedBits(:) ~= 0);
    numRx = floor(length(decodedBits) / bitsPerFrame);
    frameInfo.numRx = numRx;
    frameInfo.perFrameBER = nan(1, numRx);
    frameInfo.rxIds = nan(1, numRx);
    frameInfo.matchedMask = false(1, numRx);

    errCount = 0;
    bitsCompared = 0;
    framesMatched = 0;
    hasLastId = false;
    lastRxId = 0;
    consecIdCount = 0;

    for j = 1:numRx
        idx0 = (j-1)*bitsPerFrame + 1;
        rxFr = int8(decodedBits(idx0:idx0+bitsPerFrame-1));
        rxId = bi2de(double(rxFr(1:8)).','left-msb');
        frameInfo.rxIds(j) = rxId;

        if isKey(txMap, rxId)
            framesMatched = framesMatched + 1;
            frameInfo.matchedMask(j) = true;
            txFr = int8(txMap(rxId));
            thisErrs = biterr(double(txFr(:)), double(rxFr(:)));
            frameInfo.perFrameBER(j) = thisErrs / bitsPerFrame;

            if ~hasLastId
                hasLastId = true;
                consecIdCount = 1;
            else
                expectedId = mod(lastRxId + 1, 256);
                if rxId == expectedId
                    consecIdCount = consecIdCount + 1;
                else
                    consecIdCount = 1;
                end
            end
            lastRxId = rxId;

            if consecIdCount > numWarmUp
                errCount = errCount + thisErrs;
                bitsCompared = bitsCompared + bitsPerFrame;
            end
        else
            hasLastId = false;
            consecIdCount = 0;
        end
    end

    frameInfo.framesMatched = framesMatched;
    firstMatched = find(frameInfo.matchedMask, 1, 'first');
    if ~isempty(firstMatched)
        frameInfo.firstMatched = firstMatched;
    end

    if bitsCompared > 0
        berVal = errCount / bitsCompared;
    else
        berVal = 0.5;
    end

    if numRx < 3 || framesMatched == 0
        lockRate = 0;
    elseif ~isempty(firstMatched)
        lockDenom = max(1, numRx - firstMatched + 1);
        lockRate = min(1, sum(frameInfo.matchedMask(firstMatched:end)) / lockDenom);
    else
        lockRate = min(1, framesMatched / numRx);
    end
end

function [evmPct, merDB] = uqpskEvmMer(rxSymbols, refConst)
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
    evm = sqrt(mean(abs(err).^2) / mean(abs(nearest).^2));
    evmPct = 100 * evm;
    merDB = -20*log10(max(evm, eps));
end

function code = canonicalChannelCodingLocal(value)
    s = lower(strtrim(string(value)));
    if any(strcmp(s, ["none", "no", "uncoded", "n/a"]))
        code = "none";
    elseif any(strcmp(s, ["conv", "convolutional"]))
        code = "convolutional";
    elseif strcmp(s, "rs")
        code = "RS";
    elseif strcmp(s, "concatenated")
        code = "concatenated";
    elseif strcmp(s, "turbo")
        code = "turbo";
    elseif strcmp(s, "ldpc")
        code = "LDPC";
    else
        code = string(value);
    end
end

function args = appendRSArgsLocal(args, opt)
    rsFields = {'RSMessageLength','RSInterleavingDepth', ...
        'IsRSMessageShortened','RSShortenedMessageLength'};
    for i = 1:numel(rsFields)
        f = rsFields{i};
        if isfield(opt, f) && ~isempty(opt.(f))
            args = [args, {f, opt.(f)}]; %#ok<AGROW>
        end
    end
end

function printUQPSKResults(m)
    fprintf('\n========= CCSDS TM + UQPSK 扩展链路结果 =========\n');
    fprintf(' 调制方式 : %s  (RRatio=%d, ARatio=%.3g)\n', ...
        m.modType, m.RRatio, m.ARatio);
    fprintf(' 编码方式 : %s\n', m.channelCoding);
    fprintf(' 输入 SNR : %.1f dB, CFO=%.1f Hz, Phase=%.1f deg, Delay=%.3f\n', ...
        m.snr_in, m.cfo_in, m.phase_in, m.delay_in);
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6g\n', m.BER);
    fprintf(' EVM          : %6.2f %%\n', m.EVM_post_pct);
    fprintf(' MER          : %6.2f dB\n', m.MER_dB);
    fprintf(' SNR_est      : %6.2f dB\n', m.SNR_est_dB);
    fprintf(' PAPR (Tx)    : %6.2f dB\n', m.PAPR_dB);
    fprintf(' Frame Lock   : %6.2f %%\n', 100*m.LockRate);
    fprintf(' Encoded hard BER : %.6g  (%d/%d)\n', ...
        m.EncodedHardBER, m.EncodedHardErrors, m.EncodedHardBits);
    fprintf('===============================================\n');
end

function plotUQPSKResults(m, txWaveform, rxWaveform)
    figure('Name','CCSDS TM + UQPSK extension','NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], 'Position',[120 100 1300 430]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    rxSymbols = m.rxInfo.rxSymbols;
    totalFrames = m.berWarmUpFrames + m.berFrames;
    n0 = max(1, round(numel(rxSymbols) * m.berWarmUpFrames / totalFrames));
    n1 = min(n0 + 1800, numel(rxSymbols));
    plot(real(rxSymbols(n0:n1)), imag(rxSymbols(n0:n1)), '.', ...
        'Color',[0 0.28 0.65], 'MarkerSize',5);
    hold on;
    plot(real(m.txInfo.refConst), imag(m.txInfo.refConst), 'rx', ...
        'LineWidth',1.8, 'MarkerSize',9);
    grid on; axis equal;
    xlabel('I'); ylabel('Q');
    title(sprintf('UQPSK 星座图 | EVM %.1f%%', m.EVM_post_pct));

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
    bar(categorical({'BER','EVM(%)','MER(dB)','Lock(%)'}), ...
        [max(m.BER,1e-6), m.EVM_post_pct, m.MER_dB, 100*m.LockRate]);
    grid on;
    title('核心指标');
end

function uqpskDelayDebug(rxSymbols, txInfo, maxDelay)
    rxSymbols = rxSymbols(:);
    fprintf('\n   [UQPSK delay debug]\n');

    for d = 0:maxDelay
        y = rxSymbols(d+1:end);
        [~, hardBits] = uqpskDemapBits(y, txInfo);

        n = min([numel(hardBits), numel(txInfo.encodedBits), 100000]);
        if n < 1000
            continue;
        end

        err = sum(hardBits(1:n) ~= txInfo.encodedBits(1:n));
        ber = err / n;

        fprintf('      delay=%2d symbols, hardBER=%.6g (%d/%d)\n', ...
            d, ber, err, n);
    end
end
function uqpskPhaseDebug(rxSymbols, txInfo)
    rxSymbols = rxSymbols(:);

    cands = { ...
        @(x)x, ...
        @(x)-x, ...
        @(x)1j*x, ...
        @(x)-1j*x, ...
        @(x)conj(x), ...
        @(x)-conj(x), ...
        @(x)1j*conj(x), ...
        @(x)-1j*conj(x)};

    names = {'x','-x','j*x','-j*x','conj(x)','-conj(x)','j*conj(x)','-j*conj(x)'};

    fprintf('\n   [UQPSK phase debug]\n');

    for k = 1:numel(cands)
        y = cands{k}(rxSymbols);
        [~, hardBits] = uqpskDemapBits(y, txInfo);

        n = min([numel(hardBits), numel(txInfo.encodedBits), 100000]);
        if n < 1000
            continue;
        end

        err = sum(hardBits(1:n) ~= txInfo.encodedBits(1:n));
        ber = err / n;

        fprintf('      %-10s hardBER=%.6g (%d/%d)\n', ...
            names{k}, ber, err, n);
    end
end
function y = uqpskCarrierRecoverTeacherStyle(x, aRatio, loopBW)
%UQPSKCARRIERRECOVERTEACHERSTYLE
% 借鉴老师 UQPSKDem.m 的载波相位误差：
%   e_theta = sign(I_est)*Q_est*ARatio - sign(Q_est)*I_est
%
% 输入：
%   x      : 定时同步后的符号流
%   aRatio : UQPSK Q路幅度压缩比
%   loopBW : 环路带宽，建议先 0.001 ~ 0.01 之间试
%
% 输出：
%   y      : 载波相位恢复后的符号流

    x = x(:);
    y = zeros(size(x));

    if isempty(x)
        return;
    end

    if nargin < 3 || isempty(loopBW)
        loopBW = 0.002;
    end

    % 简单 PI 环路参数
    Kp = loopBW;
    Ki = loopBW^2 / 4;

    theta = 0;
    integ = 0;

    for n = 1:numel(x)
        % 去旋转
        z = x(n) * exp(-1j*theta);
        y(n) = z;

        I = real(z);
        Q = imag(z);

        sI = sign(I);
        sQ = sign(Q);

        if sI == 0
            sI = 1;
        end
        if sQ == 0
            sQ = 1;
        end

        % 老师 UQPSK 相位误差公式
        e = sI * Q * aRatio - sQ * I;

        % PI 环路更新
        integ = integ + Ki * e;
        theta = theta + integ + Kp * e;

        % 防止 theta 数值越积越大
        if theta > pi
            theta = theta - 2*pi;
        elseif theta < -pi
            theta = theta + 2*pi;
        end
    end
end


function [y, cfo_est] = uqpskFourthPowerFFTCoarseCFO(x, Fs, maxCFOHz, fftLen)
%UQPSKFOURTHPOWERFFTCOARSECFO
% UQPSK 非数据辅助 4次幂 FFT 粗频偏估计
%
% 思路：
%   接收信号含 CFO：x(n) ≈ s(n)*exp(j*2*pi*f0*n/Fs)
%   4次幂后：x(n)^4 ≈ s(n)^4 * exp(j*2*pi*4*f0*n/Fs)
%   因此频谱峰大致出现在 4*f0，最后除以 4 得到 CFO。
%
% 注意：
%   标准 QPSK 做 4次幂时数据调制消除更彻底；
%   UQPSK 因为 I/Q 不等幅、不等速率，4次幂后仍有数据残留，
%   但通常仍能形成可检测的 CFO 谱峰。

    x = x(:);

    if nargin < 3 || isempty(maxCFOHz)
        maxCFOHz = Fs/16;
    end

    if nargin < 4 || isempty(fftLen)
        fftLen = 2^17;
    end

    if isempty(x)
        y = x;
        cfo_est = 0;
        return;
    end

    L = min(numel(x), fftLen);
    if L < 1024
        y = x;
        cfo_est = 0;
        return;
    end

    xUse = x(1:L);

    % 去直流，避免 DC 峰影响
    xUse = xUse - mean(xUse);

    % 幅度归一，减轻 RRC 包络起伏对 4次幂的影响
    mag = abs(xUse);
    mag(mag < eps) = eps;
    xUnit = xUse ./ mag;

    sig4 = xUnit.^4;

    Nfft = 2^nextpow2(L);
    win = hamming(L);

    X4 = fftshift(fft(sig4 .* win, Nfft));
    fAx = (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);

    P4 = abs(X4).^2;

    % 4次幂后峰在 4*CFO，所以搜索范围是 ±4*maxCFOHz
    searchMask = abs(fAx) <= 4*maxCFOHz;
    if ~any(searchMask)
        y = x;
        cfo_est = 0;
        return;
    end

    P4(~searchMask) = 0;

    [~, ip] = max(P4);
    fPeak = fAx(ip);

    cfo_est = fPeak / 4;

    n = (0:numel(x)-1).';
    y = x .* exp(-1j*2*pi*cfo_est/Fs*n);
end

