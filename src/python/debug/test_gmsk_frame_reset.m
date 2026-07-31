%% TEST_GMSK_FRAME_RESET
% Short, isolated validation of ASM-aided GMSK frame-state recovery.
%
% Reused production blocks:
%   1. ccsdsTMWaveformGenerator (unchanged transmitter)
%   2. The current GMSK synchronization front-end copied verbatim below
%   3. gmsk_frame_reset_demodulate (the opt-in receiver helper)
%
% This file does not run a MAT-channel sweep and does not change the legacy
% receive mode.  The long TDL sweep is provided in a separate script.

clear classes
rng(20260715, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);
addpath(debugDir);

cfg = struct();
cfg.seed = 20260715;
cfg.sps = 8;
cfg.symbolRate = 20e6;
cfg.BT = 0.5;
cfg.numFrames = 24;
cfg.numBytesTF = 1115;
cfg.hasASM = true;
cfg.RandomizerEnabled = false;
cfg.channelCoding = 'none';
cfg.cfo = 0;
cfg.delay = 0;
cfg.enableCFOEstimate = false;
cfg.asmTemplates = localHexToBits('1ACFFC1D');
cfg.asmOffsetBits = 0;
cfg.asmMaxErrors = 4;
cfg.asmMinGap = 8;
cfg.maxSearchFrames = 8;
cfg.minSearchFrames = 3;
cfg.printDebug = false;

% Reuse the current CCSDS TM transmitter.  encodedBits is used only as
% simulation ground truth; the frame-reset receiver never receives it.
txObj = ccsdsTMWaveformGenerator( ...
    'WaveformSource', 'synchronization and channel coding', ...
    'NumBytesInTransferFrame', cfg.numBytesTF, ...
    'Modulation', 'GMSK', ...
    'ChannelCoding', cfg.channelCoding, ...
    'HasASM', cfg.hasASM, ...
    'RandomizerEnabled', cfg.RandomizerEnabled, ...
    'BandwidthTimeProduct', cfg.BT, ...
    'SamplesPerSymbol', cfg.sps);

msg = int8(randi([0 1], txObj.NumInputBits * cfg.numFrames, 1));
[txWaveform, encodedBits] = txObj(msg);
encodedBits = logical(encodedBits(:));

assert(mod(numel(encodedBits), cfg.numFrames) == 0, ...
    'encodedBits is not an integer number of frames.');
cfg.framePeriodBits = numel(encodedBits) / cfg.numFrames;
assert(all(encodedBits(1:size(cfg.asmTemplates,1)) == cfg.asmTemplates), ...
    'The generated uncoded ASM is not 1ACFFC1D in the expected bit order.');

fprintf(['[GMSK short test] TX frames=%d, framePeriod=%d bits, ', ...
    'waveform=%d samples, duration=%.3f ms\n'], ...
    cfg.numFrames, cfg.framePeriodBits, numel(txWaveform), ...
    1e3*numel(txWaveform)/(cfg.symbolRate*cfg.sps));

cases = localCase('A_ideal_100dB', 100, 0, 0, false, cfg);
cases(end+1) = localCase('B_one_raw_error', 100, 5, 1, false, cfg);
cases(end+1) = localCase('C_31bit_raw_burst', 100, 5, 31, false, cfg);
cases(end+1) = localCase('D_NoH_30dB', 30, 0, 0, false, cfg);
cases(end+1) = localCase('E_short_deep_fade', 30, 0, 0, true, cfg);

results = repmat(localEmptyResult(), numel(cases), 1);
for k = 1:numel(cases)
    results(k) = localRunCase(cases(k), cfg, txWaveform, encodedBits);
end

summary = table(string({results.Name}).', ...
    [results.GridFound].', [results.TxStartFrame].', ...
    [results.LegacyBER].', [results.FrameResetBER].', ...
    [results.LegacyLock].', [results.FrameResetLock].', ...
    [results.LegacyMaxLostRun].', [results.FrameResetMaxLostRun].', ...
    'VariableNames', {'Case','GridFound','TxStartFrame','LegacyBER', ...
    'FrameResetBER','LegacyLock','FrameResetLock', ...
    'LegacyMaxLostRun','FrameResetMaxLostRun'});

disp(summary);
assignin('base', 'gmskFrameResetShortResults', results);
assignin('base', 'gmskFrameResetShortSummary', summary);

% Hard requirements for the isolated algorithm.  D/E remain channel/front-
% end observations; A-C prove state recovery and propagation containment.
assert(results(1).GridFound, 'Case A did not acquire the ASM grid.');
assert(results(1).FrameResetBER == 0, ...
    'Case A frame-reset BER must be zero before main-chain integration.');
assert(results(2).NextFrameRecovered, ...
    'Case B error propagated into the next frame after frame reset.');
assert(results(2).LegacyPropagated, ...
    'Case B did not reproduce the expected legacy state propagation.');
assert(results(3).NextFrameRecovered, ...
    'Case C burst error propagated into the next frame after frame reset.');

fprintf(['\n[GMSK short test] PASS: ideal acquisition and controlled ', ...
    'cross-frame propagation checks completed.\n']);

function c = localCase(name, snrDb, injectFrame, injectLength, fadeEnable, cfg)
    c = struct();
    c.Name = name;
    c.SNRdB = snrDb;
    c.InjectFrame = injectFrame;
    c.InjectLength = injectLength;
    c.InjectBitOffset = floor(0.55 * cfg.framePeriodBits);
    c.FadeEnable = fadeEnable;
    c.FadeTxFrame = 8;
    c.FadeBitOffset = floor(0.45 * cfg.framePeriodBits);
    c.FadeLengthBits = 400;
    c.FadeAmplitude = 0.01;
end

function result = localRunCase(testCase, cfg, txWaveform, encodedBits)
    rng(cfg.seed, 'twister');
    rxWaveform = txWaveform(:);

    if testCase.FadeEnable
        firstBit = (testCase.FadeTxFrame-1)*cfg.framePeriodBits + ...
            testCase.FadeBitOffset;
        firstSample = max(1, (firstBit-1)*cfg.sps + 1);
        lastSample = min(numel(rxWaveform), ...
            firstSample + testCase.FadeLengthBits*cfg.sps - 1);
        rxWaveform(firstSample:lastSample) = ...
            testCase.FadeAmplitude * rxWaveform(firstSample:lastSample);
    end

    rxWaveform = awgn(rxWaveform, testCase.SNRdB, 'measured');
    syncSymbols = localLegacyGMSKFrontend(rxWaveform, cfg);

    receiverCfg = localReceiverCfg(cfg);
    [frameResetSoft, frameInfo, rawMetric] = ...
        gmsk_frame_reset_experimental(syncSymbols, receiverCfg);

    if ~frameInfo.GridFound
        error('test_gmsk_frame_reset:NoGrid', ...
            '%s: %s', testCase.Name, frameInfo.FailureReason);
    end

    if testCase.InjectFrame > 0
        if testCase.InjectFrame > numel(frameInfo.FrameStarts)
            error('test_gmsk_frame_reset:InjectionFrame', ...
                'Requested injected frame is not present in recovered data.');
        end
        first = frameInfo.FrameStarts(testCase.InjectFrame) + ...
            testCase.InjectBitOffset - 1;
        indices = first + (0:testCase.InjectLength-1).';
        rawMetric(indices) = -rawMetric(indices);

        receiverCfg.inputIsRawMetric = true;
        receiverCfg.knownFrameStart = frameInfo.FrameStart;
        receiverCfg.knownAltPhase = frameInfo.AltPhase;
        [frameResetSoft, frameInfo, rawMetric] = ...
            gmsk_frame_reset_experimental(rawMetric, receiverCfg);
    end

    legacySoft = localAlignedLegacy(rawMetric, frameInfo, cfg.framePeriodBits);
    [truth, txStartFrame] = localAlignedTruth( ...
        frameResetSoft, frameInfo.FrameAccepted, encodedBits, ...
        cfg.framePeriodBits, cfg.numFrames);

    resetPerFrameBER = localPerFrameBER( ...
        frameResetSoft, truth, cfg.framePeriodBits);
    legacyPerFrameBER = localPerFrameBER( ...
        legacySoft, truth, cfg.framePeriodBits);

    resetGood = frameInfo.FrameAccepted & resetPerFrameBER == 0;
    legacyGood = legacyPerFrameBER == 0;

    result = localEmptyResult();
    result.Name = testCase.Name;
    result.GridFound = frameInfo.GridFound;
    result.FrameStart = frameInfo.FrameStart;
    result.AltPhase = frameInfo.AltPhase;
    result.TxStartFrame = txStartFrame;
    result.GridMedianASMErrors = frameInfo.GridMedianASMErrors;
    result.LegacyBER = mean((legacySoft < 0) ~= truth);
    result.FrameResetBER = mean((frameResetSoft < 0) ~= truth);
    result.LegacyLock = mean(legacyGood);
    result.FrameResetLock = mean(resetGood);
    result.LegacyMaxLostRun = localMaxConsecutive(~legacyGood);
    result.FrameResetMaxLostRun = localMaxConsecutive(~resetGood);
    result.LegacyPerFrameBER = legacyPerFrameBER;
    result.FrameResetPerFrameBER = resetPerFrameBER;
    result.FrameAccepted = frameInfo.FrameAccepted;
    result.Info = frameInfo;
    result.NextFrameRecovered = true;
    result.LegacyPropagated = false;

    if testCase.InjectFrame > 0 && testCase.InjectFrame < numel(resetGood)
        result.NextFrameRecovered = resetGood(testCase.InjectFrame+1);
        result.LegacyPropagated = any(~legacyGood(testCase.InjectFrame+1:end));
    end

    fprintf(['\n=== %s ===\nGrid start=%d, altPhase=%d, ', ...
        'median ASM err=%.2f, recovered TX frame=%d\n'], ...
        testCase.Name, result.FrameStart, result.AltPhase, ...
        result.GridMedianASMErrors, result.TxStartFrame);
    fprintf('BER legacy/frame-reset = %.6g / %.6g\n', ...
        result.LegacyBER, result.FrameResetBER);
    fprintf('Lock legacy/frame-reset = %.3f / %.3f\n', ...
        result.LegacyLock, result.FrameResetLock);
    fprintf('max lost-frame run legacy/frame-reset = %d / %d\n', ...
        result.LegacyMaxLostRun, result.FrameResetMaxLostRun);
    if any(~frameInfo.FrameAccepted)
        fprintf('ASM-rejected recovered frames: %s\n', ...
            mat2str(find(~frameInfo.FrameAccepted).'));
    end
end

function receiverCfg = localReceiverCfg(cfg)
    receiverCfg = struct();
    receiverCfg.framePeriodBits = cfg.framePeriodBits;
    receiverCfg.asmTemplates = cfg.asmTemplates;
    receiverCfg.asmOffsetBits = cfg.asmOffsetBits;
    receiverCfg.asmMaxErrors = cfg.asmMaxErrors;
    receiverCfg.asmMinGap = cfg.asmMinGap;
    receiverCfg.maxSearchFrames = cfg.maxSearchFrames;
    receiverCfg.minSearchFrames = cfg.minSearchFrames;
    receiverCfg.printDebug = cfg.printDebug;
end

function syncSymbols = localLegacyGMSKFrontend(rxWaveform, cfg)
% Copy of the current GMSK front-end in run_ccsds_tm_evaluation.m.
    rxWaveform = rxWaveform(:);
    sps = double(cfg.sps);
    fSym = double(cfg.symbolRate);
    Fs = fSym * sps;
    btVal = double(cfg.BT);

    if mod(sps, 2) ~= 0
        error('test_gmsk_frame_reset:SamplesPerSymbol', ...
            'The current GMSK front-end requires an even sps value.');
    end

    if cfg.enableCFOEstimate
        Lfft = min(length(rxWaveform), 2^17);
        Nfft = 2^nextpow2(Lfft);
        win = hamming(Lfft);
        sigSq = rxWaveform(1:Lfft).^2;
        Xsq = fftshift(fft(sigSq .* win, Nfft));
        fAx = (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);
        Psq = abs(Xsq).^2;
        posMask = fAx > fSym*0.25 & fAx < fSym*1.0;
        negMask = fAx < -fSym*0.25 & fAx > -fSym*1.0;
        [~, ip] = max(Psq .* posMask);
        [~, in] = max(Psq .* negMask);
        cfoEst = (fAx(ip) + fAx(in)) / 4;
    else
        cfoEst = double(cfg.cfo);
    end

    n = (0:length(rxWaveform)-1).';
    rxSynced = rxWaveform .* exp(-1j*2*pi*cfoEst*n/Fs);

    hGauss = gaussdesign(btVal, 4, sps);
    rxfilter = dsp.FIRDecimator( ...
        'DecimationFactor', sps/2, 'Numerator', hGauss);
    filtered = rxfilter(rxSynced);

    timingObj = comm.SymbolSynchronizer( ...
        'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
        'SamplesPerSymbol', 2, 'DetectorGain', 2.0, ...
        'Modulation', 'PAM/PSK/QAM', 'DampingFactor', 1, ...
        'NormalizedLoopBandwidth', 0.005);
    timeSynced = timingObj(filtered);

    carrierSync = comm.CarrierSynchronizer( ...
        'Modulation', 'QPSK', 'SamplesPerSymbol', 1, ...
        'DampingFactor', 1/sqrt(2), 'NormalizedLoopBandwidth', 0.005);
    syncSymbols = carrierSync(timeSynced);
    syncSymbols = syncSymbols(:);
end

function legacySoft = localAlignedLegacy(rawMetric, info, framePeriod)
    numFrames = numel(info.FrameStarts);
    legacySoft = zeros(numFrames*framePeriod, 1);
    firstAccepted = find(info.FrameAccepted, 1, 'first');
    if isempty(firstAccepted)
        return;
    end

    rawStart = info.FrameStarts(firstAccepted);
    rawStop = info.FrameStarts(end) + framePeriod - 1;
    initialState = info.SelectedInitialState(firstAccepted);
    decoded = localInverse(rawMetric(rawStart:rawStop), initialState, ...
        rawStart-1, info.AltPhase);
    outStart = (firstAccepted-1)*framePeriod + 1;
    legacySoft(outStart:end) = decoded;
end

function soft = localInverse(raw, initialState, streamStartIndex, altPhase)
    raw = raw(:);
    soft = zeros(size(raw));
    lastDecoded = logical(initialState);
    for k = 1:numel(raw)
        streamIndex = streamStartIndex + k;
        metric = raw(k);
        if mod(streamIndex + altPhase, 2) == 1
            metric = -metric;
        end
        if lastDecoded
            metric = -metric;
        end
        soft(k) = metric;
        lastDecoded = metric < 0;
    end
end

function [truth, bestTxStart] = localAlignedTruth( ...
        soft, accepted, encodedBits, framePeriod, numTxFrames)
    numRxFrames = numel(accepted);
    if numRxFrames > numTxFrames
        error('test_gmsk_frame_reset:TruthLength', ...
            'Recovered more complete frames than were transmitted.');
    end

    hard = soft(:) < 0;
    bestErrors = inf;
    bestTxStart = 1;
    for txStart = 1:(numTxFrames-numRxFrames+1)
        first = (txStart-1)*framePeriod + 1;
        last = (txStart-1+numRxFrames)*framePeriod;
        candidate = encodedBits(first:last);
        compareMask = repelem(logical(accepted(:)), framePeriod);
        if any(compareMask)
            errors = nnz(hard(compareMask) ~= candidate(compareMask));
        else
            errors = nnz(hard ~= candidate);
        end
        if errors < bestErrors
            bestErrors = errors;
            bestTxStart = txStart;
        end
    end

    first = (bestTxStart-1)*framePeriod + 1;
    last = (bestTxStart-1+numRxFrames)*framePeriod;
    truth = encodedBits(first:last);
end

function perFrameBER = localPerFrameBER(soft, truth, framePeriod)
    numFrames = numel(soft) / framePeriod;
    hard = reshape(soft(:) < 0, framePeriod, numFrames);
    reference = reshape(logical(truth(:)), framePeriod, numFrames);
    perFrameBER = mean(hard ~= reference, 1).';
end

function maxRun = localMaxConsecutive(mask)
    mask = logical(mask(:));
    maxRun = 0;
    run = 0;
    for k = 1:numel(mask)
        if mask(k)
            run = run + 1;
            maxRun = max(maxRun, run);
        else
            run = 0;
        end
    end
end

function bits = localHexToBits(hexValue)
    hexValue = upper(char(hexValue));
    bits = false(4*numel(hexValue), 1);
    out = 1;
    for k = 1:numel(hexValue)
        value = hex2dec(hexValue(k));
        bits(out:out+3) = logical(bitget(uint8(value), 4:-1:1).');
        out = out + 4;
    end
end

function result = localEmptyResult()
    result = struct('Name','', 'GridFound',false, 'FrameStart',-1, ...
        'AltPhase',0, 'TxStartFrame',NaN, 'GridMedianASMErrors',inf, ...
        'LegacyBER',NaN, 'FrameResetBER',NaN, 'LegacyLock',0, ...
        'FrameResetLock',0, 'LegacyMaxLostRun',0, ...
        'FrameResetMaxLostRun',0, 'LegacyPerFrameBER',[], ...
        'FrameResetPerFrameBER',[], 'FrameAccepted',[], 'Info',struct(), ...
        'NextFrameRecovered',false, 'LegacyPropagated',false);
end
