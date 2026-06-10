function metrics = run_ccsds_qam_extension_evaluation(params)
%RUN_CCSDS_QAM_EXTENSION_EVALUATION CCSDS TM generator with QAM receive chain.
%
% This standalone script uses ccsdsTMWaveformGenerator to generate a QAM TM
% waveform, then runs a receiver chain with coarse frequency compensation,
% matched filtering, timing synchronization, carrier synchronization, QAM
% soft demodulation, and TM channel decoding.
%
% Example:
%   p = struct('modType','16QAM','symbolRate',100e6,'sps',8, ...
%       'snr',18,'cfo',20000,'phaseOffset',10,'delay',0.2, ...
%       'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%       'RolloffFactor',0.35,'hasASM',true,'hasRandomizer',false, ...
%       'showFigures',true);
%   m = run_ccsds_qam_extension_evaluation(p);

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

    [txWaveform, txInfo] = buildCCSDSTMQAMTx(opt);
    txIdealDbg = localQAMDemodDebug(txInfo.txSymbols, txInfo, 'TX ideal symbols');

    %% Channel
    rxWaveform = txWaveform;
    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', opt.cfo, ...
            'PhaseOffset', opt.phaseOffset, ...
            'SampleRate', txInfo.Fs);
        rxWaveform = pfo(rxWaveform);
    end
    if opt.delay ~= 0
        vfd = dsp.VariableFractionalDelay('InterpolationMethod', 'Farrow');
        rxWaveform = vfd(rxWaveform, opt.delay);
    end
    rxWaveform = awgn(rxWaveform, opt.snr, 'measured');

    %% QAM receiver: coarse frequency, matched filter, timing, carrier sync
    rawDown = rxWaveform(1:opt.sps:end);
    rawDown = rawDown(1:min(numel(rawDown), numel(txInfo.txSymbols)));
    rawDbg = localQAMStageDebug(rawDown, txInfo, opt);

    coarseFreqSync = comm.CoarseFrequencyCompensator( ...
        'Modulation', 'QAM', ...
        'SampleRate', txInfo.Fs, ...
        'FrequencyResolution', opt.coarseFrequencyResolution);
    [coarseSynced, estCFO] = coarseFreqSync(rxWaveform);


    coarseDown = coarseSynced(1:opt.sps:end);
    coarseDown = coarseDown(1:min(numel(coarseDown), numel(txInfo.txSymbols)));
    coarseDbg = localQAMStageDebug(coarseDown, txInfo, opt);

    rxFilterDecimationFactor = opt.sps/2;
    rxFilter = comm.RaisedCosineReceiveFilter( ...
        'Shape', 'Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol', opt.sps, ...
        'DecimationFactor', rxFilterDecimationFactor);
    filtered = rxFilter(coarseSynced);

    spsAfterFilter = opt.sps/rxFilterDecimationFactor;
    filteredForDebug = filtered;
    if numel(filteredForDebug) > opt.FilterSpanInSymbols
        filteredForDebug = filteredForDebug(opt.FilterSpanInSymbols+1:end);
    end
    filtDown = filteredForDebug(1:spsAfterFilter:end);
    filtDown = filtDown(1:min(numel(filtDown), numel(txInfo.txSymbols)));
    filtDbg = localQAMStageDebug(filtDown, txInfo, opt);

    Kp = 1/(pi*(1-((opt.RolloffFactor^2)/4))) * cos(pi*opt.RolloffFactor/2);
    timingObj = comm.SymbolSynchronizer( ...
        'TimingErrorDetector','Gardner (non-data-aided)', ...
        'SamplesPerSymbol', spsAfterFilter, ...
        'DetectorGain', Kp, ...
        'Modulation', 'PAM/PSK/QAM', ...
        'DampingFactor', 1/sqrt(2), ...
        'NormalizedLoopBandwidth', opt.timingLoopBandwidth);
    timeSynced = timingObj(filtered);
    timeSynced = localTrimBestQAMDelay(timeSynced, txInfo.txSymbols, opt.FilterSpanInSymbols + 8);
    timeDbg = localQAMStageDebug(timeSynced(1:min(numel(timeSynced), numel(txInfo.txSymbols))), txInfo, opt);

    carrierSync = comm.CarrierSynchronizer( ...
        'Modulation', 'QAM', ...
        'SamplesPerSymbol', 1, ...
        'DampingFactor', 1/sqrt(2), ...
        'NormalizedLoopBandwidth', opt.carrierLoopBandwidth);
    rxSymbols = carrierSync(timeSynced);
    rxSymbols = localTrimBestQAMDelay(rxSymbols, txInfo.txSymbols, opt.FilterSpanInSymbols + 8);
    rxSymbols = rxSymbols(1:min(numel(rxSymbols), numel(txInfo.txSymbols)));

    % ===== 功率归一 / AGC =====
    if ~isempty(rxSymbols)
        pwr = mean(abs(rxSymbols).^2);
        if pwr > 0
            rxSymbols = rxSymbols / sqrt(pwr);
        end
    end
    rxRawDbg    = localQAMDemodDebug(rxSymbols, txInfo, 'RX raw symbols');
rxAgcDbg    = localQAMDemodDebug(rxSymbols / sqrt(mean(abs(rxSymbols).^2)+eps), txInfo, 'RX AGC symbols');
rxOracleDbg = localQAMOracleGainDebug(rxSymbols, txInfo);
    carrierDbgBeforePhase = localQAMStageDebug(rxSymbols, txInfo, opt);

    rxSymbols = localDecisionDirectedQAMNormalize(rxSymbols, txInfo.refConst, opt.qamDDNormalizeIterations);

    % QAM 相位模糊搜索
    [rxSymbols, phaseInfo] = resolveQAMPhaseAmbiguity(rxSymbols, txInfo);

    carrierDbg = localQAMStageDebug(rxSymbols, txInfo, opt);

    noiseVar = 10^(-opt.snr/10);
    llrRaw = qamdemod(rxSymbols, txInfo.M, ...
        'OutputType', 'approxllr', ...
        'UnitAveragePower', true, ...
        'NoiseVariance', noiseVar);
    if isvector(llrRaw)
        rxSoftBits = double(llrRaw(:));
    elseif size(llrRaw, 1) == numel(rxSymbols) && size(llrRaw, 2) == txInfo.bitsPerSymbol
        rxSoftBits = double(reshape(llrRaw.', [], 1));
    else
        rxSoftBits = double(llrRaw(:));
    end
    if txInfo.padBits > 0 && numel(rxSoftBits) >= txInfo.padBits
        rxSoftBits = rxSoftBits(1:end-txInfo.padBits);
    end

    hardRaw = qamdemod(rxSymbols, txInfo.M, ...
        'OutputType', 'bit', ...
        'UnitAveragePower', true);
    if isvector(hardRaw)
        hardBits = int8(hardRaw(:) ~= 0);
    elseif size(hardRaw, 1) == numel(rxSymbols) && size(hardRaw, 2) == txInfo.bitsPerSymbol
        hardBits = int8(reshape(hardRaw.', [], 1) ~= 0);
    else
        hardBits = int8(hardRaw(:) ~= 0);
    end
    if txInfo.padBits > 0 && numel(hardBits) >= txInfo.padBits
        hardBits = hardBits(1:end-txInfo.padBits);
    end

    nHard = min(numel(hardBits), numel(txInfo.encodedBits));
    if nHard > 0
        hardErr = sum(hardBits(1:nHard) ~= txInfo.encodedBits(1:nHard));
        hardBER = hardErr / nHard;
    else
        hardErr = 0;
        hardBER = 0.5;
    end

    rxInfo = struct();
    rxInfo.coarseSynced = coarseSynced;
    rxInfo.filtered = filtered;
    rxInfo.timeSynced = timeSynced;
    rxInfo.rxSymbols = rxSymbols;
    rxInfo.softBits = rxSoftBits;
    rxInfo.hardBits = hardBits;
    rxInfo.encodedHardBER = hardBER;
    rxInfo.encodedHardErrors = hardErr;
    rxInfo.encodedHardBitsCompared = nHard;
    rxInfo.estimatedCFO = estCFO;
    rxInfo.cfoInput = opt.cfo;
    rxInfo.cfoError = estCFO - opt.cfo;
    rxInfo.phaseInfo = phaseInfo;
    rxInfo.carrierDbgBeforePhase = carrierDbgBeforePhase;
    rxInfo.debugStages = struct( ...
        'rawDownsample', rawDbg, ...
        'coarseDownsample', coarseDbg, ...
        'matchedFilterDownsample', filtDbg, ...
        'timingSync', timeDbg, ...
        'carrierSync', carrierDbg);

    if opt.debugQAM
        
        fprintf('   [QAM DEBUG] raw     EVM=%6.2f%%  encBER=%8.5f  bits=%d\n', ...
            rawDbg.evmPct, rawDbg.encodedBER, rawDbg.numBits);
        fprintf('   [QAM DEBUG] coarse  EVM=%6.2f%%  encBER=%8.5f  bits=%d\n', ...
            coarseDbg.evmPct, coarseDbg.encodedBER, coarseDbg.numBits);
        fprintf('   [QAM DEBUG] filter  EVM=%6.2f%%  encBER=%8.5f  bits=%d\n', ...
            filtDbg.evmPct, filtDbg.encodedBER, filtDbg.numBits);
        fprintf('   [QAM DEBUG] timing  EVM=%6.2f%%  encBER=%8.5f  bits=%d\n', ...
            timeDbg.evmPct, timeDbg.encodedBER, timeDbg.numBits);
        fprintf('   [QAM DEBUG] carrier EVM=%6.2f%%  encBER=%8.5f  bits=%d\n', ...
            carrierDbg.evmPct, carrierDbg.encodedBER, carrierDbg.numBits);
        fprintf('   [QAM DEBUG] phase resolve = %s, BER=%.6g (%d/%d)\n', ...
            phaseInfo.name, phaseInfo.ber, phaseInfo.errors, phaseInfo.bits);
        fprintf('   [QAM DEBUG] input CFO     = %.3f Hz\n', opt.cfo);
        fprintf('   [QAM DEBUG] estimated CFO = %.3f Hz\n', estCFO);
        fprintf('   [QAM DEBUG] CFO error     = %.3f Hz\n', estCFO - opt.cfo);
        fprintf('   [QAM DEBUG] TX ideal demod BER = %.6g (%d/%d)\n', ...
    txIdealDbg.ber, txIdealDbg.errors, txIdealDbg.bits);
    end
    idealSoftA = 20 * (1 - 2*double(txInfo.encodedBits(:)));  % bit0 -> +20, bit1 -> -20

[idealDecodedBits, idealLockRate, idealDecInfo] = decodeCCSDSTMBits(idealSoftA, opt, txInfo);

[idealBER, idealErr, idealBits, idealLockRate2, ~] = ...
    compareFrameBits(txInfo.validTxFrames, idealDecodedBits, opt.berWarmUpFrames);

    [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(rxSoftBits, opt, txInfo);

    [berVal, errCount, bitsCompared, lockRate, frameInfo] = ...
    compareFrameBits(txInfo.validTxFrames, decodedBits, opt.berWarmUpFrames);
    [evmPct, merDB] = qamEvmMer(rxInfo.rxSymbols, txInfo.refConst);
    paprDB = 10*log10(max(abs(txWaveform).^2) / mean(abs(txWaveform).^2));

    metrics = struct();
    metrics.success = true;
    metrics.errorMsg = '';
    metrics.info = sprintf('CCSDS TM coding + QAM extension | %s', opt.modType);
    metrics.modType = char(opt.modType);
    metrics.channelCoding = char(opt.channelCoding);
    metrics.BER = berVal;
    metrics.ber = berVal;
    metrics.NumErrors = errCount;
    metrics.NumBits = bitsCompared;
    metrics.EVM_post_pct = evmPct;
    metrics.MER_dB = merDB;
    metrics.SNR_est_dB = merDB;
    metrics.PAPR_dB = paprDB;
    metrics.LockRate = lockRate;
    metrics.frameInfo = frameInfo;
    metrics.Fs = txInfo.Fs;
    metrics.snr_in = opt.snr;
    metrics.cfo_in = opt.cfo;
    metrics.phase_in = opt.phaseOffset;
    metrics.delay_in = opt.delay;
    metrics.ElapsedTime = toc(tStart);
    metrics.txInfo = txInfo;
    metrics.rxInfo = rxInfo;
    metrics.decInfo = decInfo;
    metrics.EncodedHardBER = rxInfo.encodedHardBER;
    metrics.EncodedHardErrors = rxInfo.encodedHardErrors;
    metrics.EncodedHardBits = rxInfo.encodedHardBitsCompared;

    printQAMTMResults(metrics);
    fprintf('   [QAM DEBUG] decoder-only BER = %.6g (%d/%d), lock=%.2f%%, polarity=%s\n', ...
    idealBER, idealErr, idealBits, 100*idealLockRate2, idealDecInfo.SelectedSoftPolarity);
    fprintf('   [QAM DEBUG] rx raw demod BER    = %.6g (%d/%d)\n', ...
    rxRawDbg.ber, rxRawDbg.errors, rxRawDbg.bits);

    fprintf('   [QAM DEBUG] rx AGC demod BER    = %.6g (%d/%d)\n', ...
        rxAgcDbg.ber, rxAgcDbg.errors, rxAgcDbg.bits);

    fprintf('   [QAM DEBUG] rx oracle-gain BER  = %.6g (%d/%d), gainMag=%.4f, gainPhase=%.2f deg\n', ...
        rxOracleDbg.ber, rxOracleDbg.errors, rxOracleDbg.bits, ...
        rxOracleDbg.gainMag, rxOracleDbg.gainPhaseDeg);
    if opt.showFigures
        plotQAMTMResults(metrics, txInfo, rxInfo, txWaveform, rxWaveform);
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
    opt = setDefault(opt, 'channelCoding', 'convolutional');
    opt = setDefault(opt, 'ConvolutionalCodeRate', '1/2');
    opt = setDefault(opt, 'RolloffFactor', 0.35);
    opt = setDefault(opt, 'FilterSpanInSymbols', 10);
    opt = setDefault(opt, 'coarseFrequencyResolution', 1000);
    opt = setDefault(opt, 'timingLoopBandwidth', 0.01);
    opt = setDefault(opt, 'carrierLoopBandwidth', 0.005);
    opt = setDefault(opt, 'qamDDNormalizeIterations', 4);
    opt = setDefault(opt, 'hasASM', true);
    opt = setDefault(opt, 'hasRandomizer', false);
    opt = setDefault(opt, 'NumBytesInTransferFrame', 1115);
    opt = setDefault(opt, 'berWarmUpFrames', 4);
    opt = setDefault(opt, 'berFrames', 20);
    opt = setDefault(opt, 'showFigures', true);
    opt = setDefault(opt, 'debugQAM', true);

    opt.modType = upper(string(opt.modType));
    opt.channelCoding = canonicalChannelCodingLocal(opt.channelCoding);
    opt.symbolRate = double(opt.symbolRate);
    opt.sps = double(opt.sps);
    opt.snr = double(opt.snr);
    opt.cfo = double(opt.cfo);
    opt.phaseOffset = double(opt.phaseOffset);
    opt.delay = double(opt.delay);
    opt.RolloffFactor = double(opt.RolloffFactor);
    opt.FilterSpanInSymbols = double(opt.FilterSpanInSymbols);
    opt.coarseFrequencyResolution = double(opt.coarseFrequencyResolution);
    opt.timingLoopBandwidth = double(opt.timingLoopBandwidth);
    opt.carrierLoopBandwidth = double(opt.carrierLoopBandwidth);
    opt.qamDDNormalizeIterations = max(0, round(double(opt.qamDDNormalizeIterations)));
    opt.hasASM = logical(opt.hasASM);
    opt.hasRandomizer = logical(opt.hasRandomizer);
    opt.NumBytesInTransferFrame = double(opt.NumBytesInTransferFrame);
    opt.berWarmUpFrames = max(0, round(double(opt.berWarmUpFrames)));
    opt.berFrames = max(1, round(double(opt.berFrames)));
    opt.showFigures = logical(opt.showFigures);
    opt.debugQAM = logical(opt.debugQAM);
end

function s = setDefault(s, name, value)
    if ~isfield(s, name) || isempty(s.(name))
        s.(name) = value;
    end
end

function [txWaveform, infoOut] = buildCCSDSTMQAMTx(opt)
    M = qamOrder(opt.modType);
    bitsPerSymbol = log2(M);
    Fs = opt.symbolRate * opt.sps;

    args = { ...
        'WaveformSource', 'synchronization and channel coding', ...
        'Modulation', char(opt.modType), ...
        'ChannelCoding', opt.channelCoding, ...
        'SamplesPerSymbol', opt.sps, ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"]))
        args = [args, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}];
    end
    if codeKey == "convolutional" && isfield(opt, 'ConvolutionalCodeRate')
        args = [args, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}];
    end
    if any(strcmp(codeKey, ["turbo", "ldpc"]))
        if isfield(opt, 'CodeRate')
            args = [args, {'CodeRate', string(opt.CodeRate)}];
        end
        if isfield(opt, 'NumBitsInInformationBlock')
            args = [args, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}];
        end
    end
    if codeKey == "ldpc" && isfield(opt, 'IsLDPCOnSMTF')
        args = [args, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}];
    end
    if codeKey == "ldpc" && isfield(opt, 'LDPCCodeblockSize')
        args = [args, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}];
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

    [txWaveform, encodedBits] = tmWaveGen(msg);
    encodedBits = int8(encodedBits(:));
    padBits = mod(-numel(encodedBits), bitsPerSymbol);
    if padBits > 0
        encodedBitsPadded = [encodedBits; zeros(padBits, 1, 'int8')];
    else
        encodedBitsPadded = encodedBits;
    end

    txSymbols = qammod(double(encodedBitsPadded), M, ...
        'InputType', 'bit', ...
        'UnitAveragePower', true);

    infoOut = struct();
    infoOut.M = M;
    infoOut.bitsPerSymbol = bitsPerSymbol;
    infoOut.Fs = Fs;
    infoOut.bitsPerFrame = bitsPerFrame;
    infoOut.validTxFrames = validTxFrames;
    infoOut.encodedBits = encodedBits;
    infoOut.encodedBitsPadded = encodedBitsPadded;
    infoOut.padBits = padBits;
    infoOut.txSymbols = txSymbols;
    infoOut.refConst = qammod((0:M-1).', M, 'UnitAveragePower', true);
    infoOut.tmWaveGenInfo = genInfo;
end

function [decodedBits, lockRate, decInfo] = decodeCCSDSTMBits(softBits, opt, txInfo)
    candidates = {double(softBits(:)), -double(softBits(:))};
    candidateNames = {'qamdemod LLR', 'inverted LLR'};

    bestBER = inf;
    bestErr = 0;
    bestBits = 0;
    bestIdx = 1;
    bestDecoded = [];
    bestLock = 0;
    bestFrameInfo = struct();

    for iCandidate = 1:numel(candidates)
        candDecoded = decodeCCSDSTMBitsOnce(candidates{iCandidate}, opt, txInfo);

        [candBER, candErr, candBits, candLock, candFrameInfo] = ...
            compareFrameBits(txInfo.validTxFrames, candDecoded, opt.berWarmUpFrames);

        % 优先选 BER 小的；BER 一样时选 lock 高的
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
    decInfo.SelectedSoftPolarityIndex = bestIdx;
    decInfo.CandidateBER = bestBER;
    decInfo.CandidateErrors = bestErr;
    decInfo.CandidateBits = bestBits;
    decInfo.FrameInfo = bestFrameInfo;
end

function decodedBits = decodeCCSDSTMBitsOnce(softBits, opt, txInfo)
    decArgs = {'ChannelCoding', opt.channelCoding, ...
        'Modulation', 'QPSK', ...
        'HasRandomizer', opt.hasRandomizer, ...
        'HasASM', opt.hasASM, ...
        'DisablePhaseAmbiguityResolution', true};

    codeKey = lower(string(opt.channelCoding));
    if any(strcmp(codeKey, ["none", "convolutional"])) || ...
            (isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF))
        decArgs = [decArgs, {'NumBytesInTransferFrame', opt.NumBytesInTransferFrame}];
    end

    if isfield(opt, 'ConvolutionalCodeRate')
        decArgs = [decArgs, {'ConvolutionalCodeRate', char(opt.ConvolutionalCodeRate)}];
    end
    if isfield(opt, 'CodeRate') && ~strcmp(char(opt.CodeRate), 'N/A')
        decArgs = [decArgs, {'CodeRate', char(opt.CodeRate)}];
    end
    if isfield(opt, 'NumBitsInInformationBlock')
        decArgs = [decArgs, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}];
    end
    if isfield(opt, 'IsLDPCOnSMTF')
        decArgs = [decArgs, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}];
    end
    if isfield(opt, 'LDPCCodeblockSize')
        decArgs = [decArgs, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}];
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
                    hasLastId = true;
                    consecIdCount = 1;
                end
            end

            lastRxId = rxId;

            % 复用 evaluation 的思想：
            % 等连续匹配帧数超过 warmup 后，再计入 BER
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

    % 和 evaluation 类似：
    % 卷积码前面可能有 traceback / ASM 缓冲，lock 从第一个匹配帧之后算更合理
    if numRx < 3 || framesMatched == 0
        lockRate = 0;
    else
        if ~isempty(firstMatched)
            lockDenom = max(1, numRx - firstMatched + 1);
            lockedFrames = sum(frameInfo.matchedMask(firstMatched:end));
            lockRate = min(1, lockedFrames / lockDenom);
        else
            lockRate = min(1, framesMatched / numRx);
        end
    end
end

function y = localTrimBestQAMDelay(y, refSymbols, maxDelay)
    if isempty(y) || isempty(refSymbols)
        return;
    end

    y = y(:);
    refSymbols = refSymbols(:);
    maxDelay = min(max(0, round(maxDelay)), max(0, numel(y)-1));

    bestDelay = 0;
    bestMetric = -inf;
    nUseMax = min(4000, min(numel(y), numel(refSymbols)));

    for d = 0:maxDelay
        nUse = min(nUseMax, min(numel(y)-d, numel(refSymbols)));
        if nUse < 32
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
function [bestSymbols, bestInfo] = resolveQAMPhaseAmbiguity(rxSymbols, txInfo)
%RESOLVEQAMPHASEAMBIGUITY 尝试 QAM 常见相位模糊，选择 encoded BER 最小的旋转

    rxSymbols = rxSymbols(:);

    candidates = { ...
        rxSymbols, ...
        -rxSymbols, ...
        1j*rxSymbols, ...
        -1j*rxSymbols, ...
        conj(rxSymbols), ...
        -conj(rxSymbols), ...
        1j*conj(rxSymbols), ...
        -1j*conj(rxSymbols)};

    names = { ...
        'x', ...
        '-x', ...
        'j*x', ...
        '-j*x', ...
        'conj(x)', ...
        '-conj(x)', ...
        'j*conj(x)', ...
        '-j*conj(x)'};

    bestBER = inf;
    bestIdx = 1;
    bestErr = 0;
    bestBits = 0;

    for i = 1:numel(candidates)
        sym = candidates{i};

        hardRaw = qamdemod(sym, txInfo.M, ...
            'OutputType', 'bit', ...
            'UnitAveragePower', true);

        if isvector(hardRaw)
            hardBits = int8(hardRaw(:) ~= 0);
        elseif size(hardRaw, 1) == numel(sym) && size(hardRaw, 2) == txInfo.bitsPerSymbol
            hardBits = int8(reshape(hardRaw.', [], 1) ~= 0);
        else
            hardBits = int8(hardRaw(:) ~= 0);
        end

        if txInfo.padBits > 0 && numel(hardBits) >= txInfo.padBits
            hardBits = hardBits(1:end-txInfo.padBits);
        end

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

    bestInfo = struct();
    bestInfo.name = names{bestIdx};
    bestInfo.ber = bestBER;
    bestInfo.errors = bestErr;
    bestInfo.bits = bestBits;
end

function y = localDecisionDirectedQAMNormalize(y, refConst, numIter)
    y = y(:);
    refConst = refConst(:);

    if isempty(y) || isempty(refConst) || numIter <= 0
        return;
    end

    for k = 1:numIter
        [~, idx] = min(abs(y - refConst.'), [], 2);
        dHat = refConst(idx);

        % Estimate y ≈ g*dHat, then remove g. This corrects residual phase
        % and gain after CarrierSynchronizer without using transmitted bits.
        g = (dHat' * y) / max(dHat' * dHat, eps);
        if isfinite(real(g)) && isfinite(imag(g)) && abs(g) > eps
            y = y / g;
        else
            break;
        end
    end
end

function dbg = localQAMStageDebug(symbols, txInfo, opt)
    symbols = symbols(:);
    symbols = symbols(1:min(numel(symbols), numel(txInfo.txSymbols)));

    if isempty(symbols)
        dbg = struct('evmPct', NaN, 'merDB', NaN, ...
            'encodedBER', 0.5, 'numErrors', 0, 'numBits', 0);
        return;
    end

    [evmPct, merDB] = qamEvmMer(symbols, txInfo.refConst);

    hardRaw = qamdemod(symbols, txInfo.M, ...
        'OutputType', 'bit', ...
        'UnitAveragePower', true);
    if isvector(hardRaw)
        hardBits = int8(hardRaw(:) ~= 0);
    elseif size(hardRaw, 1) == numel(symbols) && size(hardRaw, 2) == txInfo.bitsPerSymbol
        hardBits = int8(reshape(hardRaw.', [], 1) ~= 0);
    else
        hardBits = int8(hardRaw(:) ~= 0);
    end
    if txInfo.padBits > 0 && numel(hardBits) >= txInfo.padBits
        hardBits = hardBits(1:end-txInfo.padBits);
    end

    n = min(numel(hardBits), numel(txInfo.encodedBits));
    if n > 0
        nErr = sum(hardBits(1:n) ~= txInfo.encodedBits(1:n));
        encodedBER = nErr / n;
    else
        nErr = 0;
        encodedBER = 0.5;
    end

    dbg = struct('evmPct', evmPct, 'merDB', merDB, ...
        'encodedBER', encodedBER, 'numErrors', nErr, 'numBits', n);
end

function [evmPct, merDB] = qamEvmMer(rxSymbols, refConst)
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

function M = qamOrder(modType)
    s = upper(string(modType));
    if contains(s, "16QAM")
        M = 16;
    elseif contains(s, "32QAM")
        M = 32;
    else
        error('Unsupported QAM extension modulation: %s', modType);
    end
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
    rsFields = {'RSMessageLength','RSInterleavingDepth','IsRSMessageShortened','RSShortenedMessageLength'};
    for i = 1:numel(rsFields)
        f = rsFields{i};
        if isfield(opt, f) && ~isempty(opt.(f))
            args = [args, {f, opt.(f)}]; %#ok<AGROW>
        end
    end
end

function printQAMTMResults(m)
    fprintf('\n========= CCSDS TM + QAM 扩展链路结果 =========\n');
    fprintf(' 调制方式 : %s\n', m.modType);
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
    fprintf(' Soft polarity    : %s\n', m.decInfo.SelectedSoftPolarity);
    fprintf('===============================================\n');
end

function plotQAMTMResults(m, txInfo, rxInfo, txWaveform, rxWaveform)
    figure('Name','CCSDS TM + QAM extension','NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], 'Position',[120 100 1300 430]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    warmupSymbols = 3000;
    nShow = 1500;

    startIdx = warmupSymbols + 1;
    endIdx = min(startIdx + nShow - 1, numel(rxInfo.rxSymbols));

    symPlot = rxInfo.rxSymbols(startIdx:endIdx);
    plot(real(symPlot), imag(symPlot), '.', ...
    'Color',[0 0.28 0.65], 'MarkerSize',4);
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
    vals = [max(m.BER, 1e-6), m.EVM_post_pct, m.MER_dB, 100*m.LockRate];
    bar(categorical({'BER','EVM(%)','MER(dB)','Lock(%)'}), vals);
    grid on;
    title('核心指标');
end
function dbg = localQAMDemodDebug(symbols, txInfo, label)
%LOCALQAMDEMODDEBUG 对一组 QAM 符号直接硬判，并和 encodedBits 比较

    symbols = symbols(:);
    symbols = symbols(1:min(numel(symbols), numel(txInfo.txSymbols)));

    if isempty(symbols)
        dbg = struct('label',label,'ber',0.5,'errors',0,'bits',0);
        return;
    end

    hardRaw = qamdemod(symbols, txInfo.M, ...
        'OutputType','bit', ...
        'UnitAveragePower',true);

    if isvector(hardRaw)
        hardBits = int8(hardRaw(:) ~= 0);
    elseif size(hardRaw,1) == numel(symbols) && size(hardRaw,2) == txInfo.bitsPerSymbol
        hardBits = int8(reshape(hardRaw.', [], 1) ~= 0);
    else
        hardBits = int8(hardRaw(:) ~= 0);
    end

    if txInfo.padBits > 0 && numel(hardBits) >= txInfo.padBits
        hardBits = hardBits(1:end-txInfo.padBits);
    end

    n = min(numel(hardBits), numel(txInfo.encodedBits));

    if n > 0
        nErr = sum(hardBits(1:n) ~= txInfo.encodedBits(1:n));
        ber = nErr / n;
    else
        nErr = 0;
        ber = 0.5;
    end

    dbg = struct();
    dbg.label = label;
    dbg.ber = ber;
    dbg.errors = nErr;
    dbg.bits = n;
end
function dbg = localQAMOracleGainDebug(rxSymbols, txInfo)
%LOCALQAMORACLEGAINDEBUG 调试用：用已知发送符号估计一个最佳复数增益
% 这个不是实际接收机，只是为了判断 rxSymbols 里信息还在不在。

    y = rxSymbols(:);
    x = txInfo.txSymbols(:);

    nSym = min(numel(y), numel(x));
    y = y(1:nSym);
    x = x(1:nSym);

    if nSym < 10
        dbg = struct('ber',0.5,'errors',0,'bits',0, ...
            'gain',1,'gainMag',1,'gainPhaseDeg',0);
        return;
    end

    % 找 g，使 g*y 最接近 x
    g = (y' * x) / max(y' * y, eps);
    yEq = g * y;

    demodDbg = localQAMDemodDebug(yEq, txInfo, 'RX oracle gain symbols');

    dbg = demodDbg;
    dbg.gain = g;
    dbg.gainMag = abs(g);
    dbg.gainPhaseDeg = angle(g) * 180/pi;
end