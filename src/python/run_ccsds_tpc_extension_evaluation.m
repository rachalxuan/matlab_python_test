function metrics = run_ccsds_tpc_extension_evaluation(params)
%RUN_CCSDS_TPC_EXTENSION_EVALUATION Standalone CCSDS-TM + TPC link test.
%
% This script keeps TPC outside ccsdsTMWaveformGenerator for the first
% validation pass:
%   TM-like transfer frames -> TPC encode -> BPSK/QPSK/RRC waveform
%   -> channel impairments -> sync/demod -> TPC decode -> frame BER.
%
% Example:
%   p = struct('symbolRate',20e6,'sps',4,'snr',8,'cfo',20000, ...
%       'phaseOffset',10,'delay',0.1,'showFigures',true);
%   m = run_ccsds_tpc_extension_evaluation(p);

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

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);

    % TPC parameters from the provided simulator: extended Hamming (64,57)^2.
    mTPC = 6;
    nTPC = 2^mTPC - 1;
    NTPC = nTPC + 1;
    kTPC = nTPC - mTPC;
    genpoly = [1 0 0 0 0 1 1];
    [H, G] = hammgen(mTPC, genpoly);
    H = [H(:,mTPC+1:end), H(:,1:mTPC)];

    % Build TM-like frames. The first byte is a frame counter, so existing
    % frame-lock style checks remain meaningful.
    bitsPerFrame = opt.NumBytesInTransferFrame * 8;
    numFrames = opt.berWarmUpFrames + opt.berFrames;
    validTxFrames = cell(1, numFrames);
    txBits = zeros(bitsPerFrame*numFrames, 1, 'int8');
    for iFrame = 1:numFrames
        frameBits = int8(randi([0 1], bitsPerFrame, 1));
        frameBits(1:8) = int8(de2bi(mod(iFrame-1,256), 8, 'left-msb')).';
        validTxFrames{iFrame} = frameBits;
        txBits((iFrame-1)*bitsPerFrame+1:iFrame*bitsPerFrame) = frameBits;
    end

    % TPC encode stream. The teacher code is native (64,57)^2. For 1/2 and
    % 2/3 tests, use shortened payload blocks while keeping the same TPC
    % encoder/decoder core and codeword length.
    nativeInfoBlockLen = kTPC * kTPC;
    codeBlockLen = NTPC * NTPC;
    [payloadSideLen, rateLabel] = localParseTPCRate(opt.tpcCodeRate, kTPC);
    payloadBlockLen = payloadSideLen * payloadSideLen;
    padBits = ceil(numel(txBits)/payloadBlockLen)*payloadBlockLen - numel(txBits);
    txBitsPadded = [txBits; zeros(padBits,1,'int8')];
    numTPCBlocks = numel(txBitsPadded) / payloadBlockLen;

    encodedBits = zeros(numTPCBlocks*codeBlockLen, 1, 'int8');
    for iBlock = 1:numTPCBlocks
        idx = (iBlock-1)*payloadBlockLen+1:iBlock*payloadBlockLen;
        msgMat = zeros(kTPC, kTPC);
        msgMat(1:payloadSideLen, 1:payloadSideLen) = ...
            reshape(double(txBitsPadded(idx)), payloadSideLen, payloadSideLen);
        encMat = TPC_encoder(msgMat, nTPC, kTPC, G, genpoly);
        encodedBits((iBlock-1)*codeBlockLen+1:iBlock*codeBlockLen) = int8(encMat(:));
    end

    % Modulation and RRC transmit shaping.
    [txSymbols, bitsPerSymbol] = localTPCModulate(encodedBits, opt.modType);
    txFilter = comm.RaisedCosineTransmitFilter( ...
        'Shape','Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'OutputSamplesPerSymbol', opt.sps);
    txWaveform = txFilter(txSymbols);
    Fs = opt.symbolRate * opt.sps;

    % Channel impairments.
    rxWaveform = txWaveform;
    if opt.cfo ~= 0 || opt.phaseOffset ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', opt.cfo, ...
            'PhaseOffset', opt.phaseOffset, ...
            'SampleRate', Fs);
        rxWaveform = pfo(rxWaveform);
    end
    if opt.delay ~= 0
        vfd = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        rxWaveform = vfd(rxWaveform, opt.delay);
    end
    rxWaveform = awgn(rxWaveform, opt.snr, 'measured');

    % Receiver: coarse CFO, matched filter, symbol timing, carrier sync.
    coarseMod = upper(char(opt.modType));
    if ~any(strcmp(coarseMod, {'BPSK','QPSK'}))
        coarseMod = 'BPSK';
    end
    coarseSync = comm.CoarseFrequencyCompensator( ...
        'Modulation',coarseMod, ...
        'SampleRate', Fs, ...
        'FrequencyResolution', opt.coarseFrequencyResolution);
    [coarseSynced, estCFO] = coarseSync(rxWaveform);

    rxFilterDecim = max(1, opt.sps/2);
    rxFilter = comm.RaisedCosineReceiveFilter( ...
        'Shape','Square root', ...
        'RolloffFactor', opt.RolloffFactor, ...
        'FilterSpanInSymbols', opt.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol', opt.sps, ...
        'DecimationFactor', rxFilterDecim);
    filtered = rxFilter(coarseSynced);

    spsAfter = opt.sps / rxFilterDecim;
    timingSync = comm.SymbolSynchronizer( ...
        'TimingErrorDetector','Gardner (non-data-aided)', ...
        'SamplesPerSymbol', spsAfter, ...
        'DetectorGain', 2.7, ...
        'Modulation','PAM/PSK/QAM', ...
        'DampingFactor', 1/sqrt(2), ...
        'NormalizedLoopBandwidth', opt.timingLoopBandwidth);
    timeSynced = timingSync(filtered);

    carrierSync = comm.CarrierSynchronizer( ...
        'Modulation',upper(char(opt.modType)), ...
        'SamplesPerSymbol', 1, ...
        'DampingFactor', 1/sqrt(2), ...
        'NormalizedLoopBandwidth', opt.carrierLoopBandwidth);
    rxSymbols = carrierSync(timeSynced);
    if ~isempty(rxSymbols)
        rxSymbols = rxSymbols / sqrt(mean(abs(rxSymbols).^2) + eps);
    end

    % Align the soft stream to the encoded-bit stream. This is a standalone
    % validation script, so using the known encoded stream for delay choice is
    % acceptable before integrating TPC into the production decoder.
    [rxSoft, alignInfo] = localAlignTPCSoft(rxSymbols, encodedBits, opt.modType, opt.maxAlignSymbols);
    hardBits = int8(rxSoft(:) >= 0);
    nCmp = min(numel(hardBits), numel(encodedBits));
    encodedHardErrors = nnz(hardBits(1:nCmp) ~= encodedBits(1:nCmp));
    encodedHardBER = encodedHardErrors / max(nCmp,1);

    % TPC decode in 64x64 soft blocks. TPC_decoder loads err_p64.txt from
    % current folder, so temporarily switch to this script directory.
    oldDir = pwd;
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(thisDir);

    numRxBlocks = floor(numel(rxSoft) / codeBlockLen);
    numDecBlocks = min(numRxBlocks, numTPCBlocks);
    decBitsPadded = zeros(numDecBlocks*payloadBlockLen, 1, 'int8');
    for iBlock = 1:numDecBlocks
        idx = (iBlock-1)*codeBlockLen+1:iBlock*codeBlockLen;
        rxMat = reshape(double(rxSoft(idx)), NTPC, NTPC);
        [decMat, ~] = TPC_decoder(rxMat, nTPC, kTPC, H, ...
            opt.tpcLeastReliableBits, opt.tpcAlpha, opt.tpcBeta, opt.tpcIterations);
        decPayload = int8(decMat(1:payloadSideLen, 1:payloadSideLen) ~= 0);
        decBitsPadded((iBlock-1)*payloadBlockLen+1:iBlock*payloadBlockLen) = decPayload(:);
    end

    cd(oldDir);
    clear cleanupObj;

    decBits = decBitsPadded(1:min(numel(txBits), numel(decBitsPadded)));
    [berVal, numErr, numBits, lockRate, frameInfo] = ...
        localCompareFrames(validTxFrames, decBits, opt.berWarmUpFrames);

    paprDB = 10*log10(max(abs(txWaveform).^2) / mean(abs(txWaveform).^2));
    [evmPct, merDB] = localBPSKEVM(rxSoft(1:min(numel(rxSoft), numel(encodedBits))), ...
        encodedBits(1:min(numel(rxSoft), numel(encodedBits))));

    metrics = struct();
    metrics.success = true;
    metrics.errorMsg = '';
    metrics.info = sprintf('CCSDS TM-like source + TPC extension | %s', upper(char(opt.modType)));
    metrics.modType = upper(char(opt.modType));
    metrics.channelCoding = 'TPC';
    metrics.BER = berVal;
    metrics.ber = berVal;
    metrics.NumErrors = numErr;
    metrics.NumBits = numBits;
    metrics.LockRate = lockRate * 100;
    metrics.FrameLock_pct = lockRate * 100;
    metrics.EncodedHardBER = encodedHardBER;
    metrics.EncodedHardErrors = encodedHardErrors;
    metrics.EncodedHardBits = nCmp;
    metrics.EVM_post_pct = evmPct;
    metrics.MER_dB = merDB;
    metrics.SNR_est_dB = merDB;
    metrics.PAPR_dB = paprDB;
    metrics.Fs = Fs;
    metrics.snr_in = opt.snr;
    metrics.cfo_in = opt.cfo;
    metrics.cfo_est_Hz = estCFO;
    metrics.cfo_error_Hz = estCFO - opt.cfo;
    metrics.phase_in = opt.phaseOffset;
    metrics.delay_in = opt.delay;
    metrics.NumTPCBlocks = numTPCBlocks;
    metrics.DecodedTPCBlocks = numDecBlocks;
    metrics.TPCCodeRate = rateLabel;
    metrics.TPCNativeInfoBlockBits = nativeInfoBlockLen;
    metrics.TPCPayloadSideBits = payloadSideLen;
    metrics.TPCPayloadBlockBits = payloadBlockLen;
    metrics.TPCInfoBlockBits = payloadBlockLen;
    metrics.TPCCodeBlockBits = codeBlockLen;
    metrics.BitsPerSymbol = bitsPerSymbol;
    metrics.TPCRate = payloadBlockLen / codeBlockLen;
    metrics.TPCNativeRate = nativeInfoBlockLen / codeBlockLen;
    metrics.AlignInfo = alignInfo;
    metrics.FrameInfo = frameInfo;
    metrics.ElapsedTime = toc(tStart);

    localPrintMetrics(metrics);
    if opt.showFigures
        localPlotTPC(metrics, rxSoft, encodedBits, opt);
    end
end

function opt = localDefaults(opt)
    opt = localSetDefault(opt, 'modType', 'BPSK');
    opt = localSetDefault(opt, 'symbolRate', 20e6);
    opt = localSetDefault(opt, 'sps', 4);
    opt = localSetDefault(opt, 'snr', 8);
    opt = localSetDefault(opt, 'cfo', 20000);
    opt = localSetDefault(opt, 'phaseOffset', 10);
    opt = localSetDefault(opt, 'delay', 0.1);
    opt = localSetDefault(opt, 'RolloffFactor', 0.35);
    opt = localSetDefault(opt, 'FilterSpanInSymbols', 10);
    opt = localSetDefault(opt, 'NumBytesInTransferFrame', 1115);
    opt = localSetDefault(opt, 'berWarmUpFrames', 4);
    opt = localSetDefault(opt, 'berFrames', 20);
    opt = localSetDefault(opt, 'coarseFrequencyResolution', 100);
    opt = localSetDefault(opt, 'timingLoopBandwidth', 0.01);
    opt = localSetDefault(opt, 'carrierLoopBandwidth', 0.01);
    opt = localSetDefault(opt, 'maxAlignSymbols', 80);
    opt = localSetDefault(opt, 'tpcIterations', 6);
    opt = localSetDefault(opt, 'tpcLeastReliableBits', 4);
    opt = localSetDefault(opt, 'tpcAlpha', 0.5);
    opt = localSetDefault(opt, 'tpcBeta', 1);
    opt = localSetDefault(opt, 'tpcCodeRate', 'native');
    opt = localSetDefault(opt, 'showFigures', false);

    opt.modType = upper(strtrim(char(opt.modType)));
    if ~any(strcmp(opt.modType, {'BPSK','QPSK','8PSK'}))
        error('run_ccsds_tpc_extension_evaluation:UnsupportedModulation', ...
            'Standalone TPC extension currently supports BPSK, QPSK and 8PSK. Got "%s".', opt.modType);
    end
end

function [payloadSideLen, label] = localParseTPCRate(rawRate, nativeSideLen)
    if nargin < 1 || isempty(rawRate)
        rawRate = 'native';
    end

    if isnumeric(rawRate)
        payloadSideLen = round(double(rawRate));
        label = sprintf('%dx%d', payloadSideLen, payloadSideLen);
    else
        label = lower(strtrim(char(rawRate)));
        switch label
            case {'native','default','0.7932','57','57x57'}
                payloadSideLen = nativeSideLen;
                label = 'native';
            case {'1/2','half'}
                payloadSideLen = 45;
                label = '1/2';
            case {'2/3'}
                payloadSideLen = 52;
                label = '2/3';
            otherwise
                xPos = strfind(label, 'x');
                if numel(xPos) == 1
                    payloadSideLen = round(str2double(label(1:xPos-1)));
                else
                    payloadSideLen = round(str2double(label));
                end
                label = sprintf('%dx%d', payloadSideLen, payloadSideLen);
        end
    end

    if ~isfinite(payloadSideLen) || payloadSideLen < 1 || payloadSideLen > nativeSideLen
        error('run_ccsds_tpc_extension_evaluation:InvalidTPCRate', ...
            'Unsupported tpcCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end

function s = localSetDefault(s, name, value)
    if ~isfield(s, name) || isempty(s.(name))
        s.(name) = value;
    end
    if (ischar(s.(name)) || isstring(s.(name))) && ~strcmp(name, 'tpcCodeRate')
        n = str2double(strrep(string(s.(name)), ',', ''));
        if ~isnan(n)
            s.(name) = n;
        end
    end
end

function [txSymbols, bitsPerSymbol] = localTPCModulate(encodedBits, modType)
    bits = int8(encodedBits(:) ~= 0);
    modType = upper(strtrim(char(modType)));
    switch modType
        case 'BPSK'
            bitsPerSymbol = 1;
            txSymbols = complex(2*double(bits) - 1, 0);
        case 'QPSK'
            bitsPerSymbol = 2;
            n = floor(numel(bits)/2)*2;
            bits = bits(1:n);
            b = reshape(double(bits), 2, []);
            iq = 1 - 2*b;
            txSymbols = (iq(1,:).' + 1j*iq(2,:).') / sqrt(2);
        case '8PSK'
            bitsPerSymbol = 3;
            n = floor(numel(bits)/3)*3;
            bits = bits(1:n);
            modObj = comm.PSKModulator(8, pi/4, ...
                'BitInput', true, ...
                'SymbolMapping', 'Custom', ...
                'CustomSymbolMapping', [0 4 6 2 3 7 5 1]);
            txSymbols = modObj(logical(bits));
        otherwise
            error('run_ccsds_tpc_extension_evaluation:UnsupportedModulation', ...
                'Unsupported modulation "%s".', modType);
    end
end

function [rxSoft, info] = localAlignTPCSoft(rxSymbols, encodedBits, modType, maxOffsetSymbols)
    encodedBits = int8(encodedBits(:) ~= 0);
    modType = upper(strtrim(char(modType)));
    switch modType
        case 'BPSK'
            rotations = [1 -1];
            bitsPerSymbol = 1;
        case 'QPSK'
            rotations = exp(1j*pi/2*(0:3));
            bitsPerSymbol = 2;
        case '8PSK'
            rotations = exp(1j*pi/4*(0:7));
            bitsPerSymbol = 3;
        otherwise
            error('run_ccsds_tpc_extension_evaluation:UnsupportedModulation', ...
                'Unsupported modulation "%s".', modType);
    end

    bestErr = inf;
    bestOffset = 0;
    bestRot = 1;
    bestLen = 0;
    bestSoft = zeros(0,1);
    maxOffsetBits = maxOffsetSymbols * bitsPerSymbol;

    for iRot = 1:numel(rotations)
        softCand = localTPCSoftDemap(rxSymbols(:) * rotations(iRot), modType);
        hardCand = int8(softCand >= 0);
        for offset = 0:min(maxOffsetBits, max(0,numel(hardCand)-1))
            L = min(numel(encodedBits), numel(hardCand)-offset);
            if L <= 0
                continue;
            end
            err = nnz(hardCand(offset+1:offset+L) ~= encodedBits(1:L));
            if err < bestErr
                bestErr = err;
                bestOffset = offset;
                bestRot = rotations(iRot);
                bestLen = L;
                bestSoft = softCand;
            end
        end
    end
    rxSoft = bestSoft(bestOffset+1:end);
    info = struct('offsetBits',bestOffset,'rotation',bestRot, ...
        'alignedErrors',bestErr,'alignedBits',bestLen);
end

function softBits = localTPCSoftDemap(rxSymbols, modType)
    modType = upper(strtrim(char(modType)));
    rxSymbols = rxSymbols(:);
    if isempty(rxSymbols)
        softBits = zeros(0,1);
        return;
    end
    p = mean(abs(rxSymbols).^2);
    if isfinite(p) && p > 0
        rxSymbols = rxSymbols / sqrt(p);
    end

    switch modType
        case 'BPSK'
            softBits = double(real(rxSymbols));
        case 'QPSK'
            % Matches localTPCModulate: I=1-2*b1, Q=1-2*b2.
            iSoft = -real(rxSymbols);
            qSoft = -imag(rxSymbols);
            softBits = double(reshape([iSoft.'; qSoft.'], [], 1));
        case '8PSK'
            demodObj = comm.PSKDemodulator( ...
                'PhaseOffset', pi/8, ...
                'ModulationOrder', 8, ...
                'BitOutput', true, ...
                'DecisionMethod', "Approximate log-likelihood ratio", ...
                'SymbolMapping', 'Custom', ...
                'CustomSymbolMapping', [0 4 6 2 3 7 5 1]);
            softBits = -double(demodObj(rxSymbols));
        otherwise
            error('run_ccsds_tpc_extension_evaluation:UnsupportedModulation', ...
                'Unsupported modulation "%s".', modType);
    end
end

function [berVal, numErr, numBits, lockRate, frameInfo] = localCompareFrames(validTxFrames, decBits, warmup)
    bitsPerFrame = numel(validTxFrames{1});
    numRx = floor(numel(decBits) / bitsPerFrame);
    txMap = containers.Map('KeyType','double','ValueType','any');
    for i = 1:numel(validTxFrames)
        fr = validTxFrames{i};
        txMap(double(bi2de(fr(1:8).','left-msb'))) = fr;
    end

    numErr = 0;
    numBits = 0;
    locked = 0;
    perFrameBER = nan(1,numRx);
    for i = 1:numRx
        rxFrame = int8(decBits((i-1)*bitsPerFrame+1:i*bitsPerFrame) ~= 0);
        id = double(bi2de(rxFrame(1:8).','left-msb'));
        if isKey(txMap, id)
            txFrame = txMap(id);
            thisErr = nnz(rxFrame ~= txFrame);
            perFrameBER(i) = thisErr / bitsPerFrame;
            locked = locked + 1;
            if id >= warmup
                numErr = numErr + thisErr;
                numBits = numBits + bitsPerFrame;
            end
        end
    end

    if numBits > 0
        berVal = numErr / numBits;
    else
        berVal = 0.5;
    end
    lockRate = locked / max(numRx,1);
    frameInfo = struct('numRxFrames',numRx,'lockedFrames',locked, ...
        'perFrameBER',perFrameBER);
end

function [evmPct, merDB] = localBPSKEVM(rxSoft, encodedBits)
    ref = 2*double(encodedBits(:)) - 1;
    rx = double(rxSoft(:));
    L = min(numel(rx), numel(ref));
    if L <= 0
        evmPct = NaN;
        merDB = NaN;
        return;
    end
    rx = rx(1:L);
    ref = ref(1:L);
    gain = (ref' * rx) / max(rx' * rx, eps);
    rx = gain * rx;
    err = rx - ref;
    evmRms = sqrt(mean(abs(err).^2) / mean(abs(ref).^2));
    evmPct = 100 * evmRms;
    merDB = -20*log10(max(evmRms, eps));
end

function localPrintMetrics(m)
    fprintf('\n========= CCSDS TM + TPC extension result =========\n');
    fprintf(' Modulation   : %s\n', m.modType);
    fprintf(' Coding       : TPC (64,57)^2 shortened, rate %s (effective %.4f, native %.4f)\n', ...
        char(m.TPCCodeRate), m.TPCRate, m.TPCNativeRate);
    fprintf(' Input SNR    : %.1f dB, CFO=%.1f Hz, Phase=%.1f deg, Delay=%.3f\n', ...
        m.snr_in, m.cfo_in, m.phase_in, m.delay_in);
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6g\n', m.BER);
    fprintf(' Frame Lock   : %.2f %%\n', m.FrameLock_pct);
    fprintf(' Encoded BER  : %.6g (%d/%d)\n', ...
        m.EncodedHardBER, m.EncodedHardErrors, m.EncodedHardBits);
    if isfield(m,'AlignInfo')
        fprintf(' Align        : offset=%d bits, rotation=%+.1f deg\n', ...
            m.AlignInfo.offsetBits, rad2deg(angle(m.AlignInfo.rotation)));
    end
    fprintf(' EVM          : %.2f %%\n', m.EVM_post_pct);
    fprintf(' MER/SNR_est  : %.2f dB\n', m.MER_dB);
    fprintf(' PAPR (Tx)    : %.2f dB\n', m.PAPR_dB);
    fprintf(' CFO est      : %.2f Hz, error %.2f Hz\n', ...
        m.cfo_est_Hz, m.cfo_error_Hz);
    fprintf(' TPC blocks   : %d decoded / %d sent\n', ...
        m.DecodedTPCBlocks, m.NumTPCBlocks);
    fprintf(' TPC payload  : %dx%d / 64x64 (%d / %d bits per block)\n', ...
        m.TPCPayloadSideBits, m.TPCPayloadSideBits, ...
        m.TPCPayloadBlockBits, m.TPCCodeBlockBits);
    fprintf('===============================================\n');
end

function localPlotTPC(metrics, rxSoft, encodedBits, opt)
    figure('Name','TPC extension evaluation','NumberTitle','off', ...
        'Color',[0.94 0.94 0.94], 'Position',[100 100 1200 420]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    L = min(numel(rxSoft), 3000);
    plot(rxSoft(1:L), '.');
    grid on;
    xlabel('Bit index');
    ylabel('Soft value');
    title('TPC soft bits');

    nexttile;
    L = min(numel(rxSoft), numel(encodedBits));
    hard = int8(rxSoft(1:L) >= 0);
    err = double(hard ~= encodedBits(1:L));
    win = max(1, round(L/200));
    plot(movmean(err, win), 'LineWidth', 1.2);
    grid on;
    xlabel('Encoded bit index');
    ylabel('Moving hard BER');
    title('Encoded-domain errors');

    nexttile;
    vals = [metrics.BER, metrics.EncodedHardBER, metrics.FrameLock_pct/100];
    bar(vals);
    set(gca,'XTickLabel',{'Final BER','Encoded BER','Frame lock'});
    grid on;
    title(sprintf('SNR %.1f dB', opt.snr));
end
