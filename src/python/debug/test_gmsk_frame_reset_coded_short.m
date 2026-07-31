%% TEST_GMSK_FRAME_RESET_CODED_SHORT
% Short 100 dB encoded-bit validation for every supported convolutional rate.
% This does not run the channel MAT files or the CCSDS decoder.

clear classes
rng(20260715, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

rates = {'1/2','2/3','3/4','5/6','7/8'};
numFrames = 12;
sps = 8;
symbolRate = 20e6;
rows = cell(numel(rates), 7);

for rateIndex = 1:numel(rates)
    rate = rates{rateIndex};
    numBytesTF = localFrameBytes(rate);
    tx = ccsdsTMWaveformGenerator( ...
        'WaveformSource', 'synchronization and channel coding', ...
        'NumBytesInTransferFrame', numBytesTF, ...
        'Modulation', 'GMSK', ...
        'ChannelCoding', 'convolutional', ...
        'ConvolutionalCodeRate', rate, ...
        'HasASM', true, 'RandomizerEnabled', false, ...
        'BandwidthTimeProduct', 0.5, 'SamplesPerSymbol', sps);

    msg = int8(randi([0 1], tx.NumInputBits*numFrames, 1));
    [txWaveform, encodedBits] = tx(msg);
    encodedBits = logical(encodedBits(:));

    markerCfg = gmsk_frame_reset_asm_config( ...
        'convolutional', rate, numBytesTF, [], 'NRZ-L');
    assert(~isempty(markerCfg.asmTemplates), ...
        'Aligned rate %s did not produce a rectangular ASM template.', rate);
    assert(mod(numel(encodedBits), markerCfg.framePeriodBits) == 0, ...
        'Encoded stream is not an integer number of configured periods.');

    rng(20260715, 'twister');
    rxWaveform = awgn(txWaveform, 100, 'measured');
    syncSymbols = localFrontend(rxWaveform, sps, symbolRate, 0.5);

    receiverCfg = struct();
    receiverCfg.framePeriodBits = markerCfg.framePeriodBits;
    receiverCfg.asmTemplates = markerCfg.asmTemplates;
    receiverCfg.asmOffsetBits = markerCfg.asmOffsetBits;
    receiverCfg.asmMaxErrors = max(2, ceil(0.20*size(markerCfg.asmTemplates,1)));
    receiverCfg.asmMinGap = max(3, ceil(0.25*size(markerCfg.asmTemplates,1)));
    receiverCfg.maxSearchFrames = 8;
    receiverCfg.minSearchFrames = 3;

    [soft, info] = gmsk_frame_reset_demodulate(syncSymbols, receiverCfg);
    assert(info.GridFound, 'ASM grid was not found for rate %s.', rate);
    [truth, txStart] = localTruth(soft, info.FrameAccepted, ...
        encodedBits, markerCfg.framePeriodBits);
    ber = mean((soft < 0) ~= truth);
    lock = mean(info.FrameAccepted & ...
        localPerFrameBER(soft, truth, markerCfg.framePeriodBits) == 0);

    rows(rateIndex,:) = {rate, numBytesTF, markerCfg.framePeriodBits, ...
        info.FrameStart, txStart, ber, lock};
    fprintf(['rate=%s, TF=%d bytes, period=%d, gridStart=%d, ', ...
        'TXstart=%d, BER=%.6g, Lock=%.1f%%\n'], ...
        rate, numBytesTF, markerCfg.framePeriodBits, info.FrameStart, ...
        txStart, ber, 100*lock);

    assert(ber == 0 && lock == 1, ...
        'Coded short frame-reset validation failed for rate %s.', rate);
end

summary = cell2table(rows, 'VariableNames', ...
    {'Rate','NumBytesTF','FramePeriodBits','GridStart', ...
     'TxStartFrame','EncodedBER','EncodedLock'});
disp(summary);
assignin('base', 'gmskFrameResetCodedShortSummary', summary);
fprintf('[GMSK coded frame reset short test] PASS\n');

function n = localFrameBytes(rate)
    n = 1115;
    if strcmp(rate, '5/6')
        n = 1116;
    elseif strcmp(rate, '7/8')
        n = 1123;
    end
end

function symbols = localFrontend(rxWaveform, sps, symbolRate, bt)
    hGauss = gaussdesign(bt, 4, sps);
    rxfilter = dsp.FIRDecimator( ...
        'DecimationFactor', sps/2, 'Numerator', hGauss);
    filtered = rxfilter(rxWaveform(:));
    timingObj = comm.SymbolSynchronizer( ...
        'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
        'SamplesPerSymbol', 2, 'DetectorGain', 2.0, ...
        'Modulation', 'PAM/PSK/QAM', 'DampingFactor', 1, ...
        'NormalizedLoopBandwidth', 0.005);
    timeSynced = timingObj(filtered);
    carrierSync = comm.CarrierSynchronizer( ...
        'Modulation', 'QPSK', 'SamplesPerSymbol', 1, ...
        'DampingFactor', 1/sqrt(2), 'NormalizedLoopBandwidth', 0.005);
    symbols = carrierSync(timeSynced);
    symbols = symbols(:);
    if isempty(symbols)
        error('test_gmsk_frame_reset_coded_short:Frontend', ...
            'The current GMSK front-end returned no symbols at %.3f MHz.', ...
            symbolRate/1e6);
    end
end

function [truth, bestTxStart] = localTruth(soft, accepted, encoded, framePeriod)
    numRxFrames = numel(accepted);
    numTxFrames = numel(encoded)/framePeriod;
    hard = soft(:) < 0;
    mask = repelem(logical(accepted(:)), framePeriod);
    bestErrors = inf;
    bestTxStart = 1;
    for txStart = 1:(numTxFrames-numRxFrames+1)
        first = (txStart-1)*framePeriod + 1;
        last = (txStart-1+numRxFrames)*framePeriod;
        candidate = encoded(first:last);
        errors = nnz(hard(mask) ~= candidate(mask));
        if errors < bestErrors
            bestErrors = errors;
            bestTxStart = txStart;
        end
    end
    first = (bestTxStart-1)*framePeriod + 1;
    last = (bestTxStart-1+numRxFrames)*framePeriod;
    truth = encoded(first:last);
end

function ber = localPerFrameBER(soft, truth, framePeriod)
    numFrames = numel(soft)/framePeriod;
    hard = reshape(soft(:)<0, framePeriod, numFrames);
    reference = reshape(logical(truth(:)), framePeriod, numFrames);
    ber = mean(hard ~= reference, 1).';
end
