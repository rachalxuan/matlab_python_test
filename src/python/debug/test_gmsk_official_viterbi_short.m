%% TEST_GMSK_OFFICIAL_VITERBI_SHORT
% Isolated compatibility test for the production GMSK transmitter,
% comm.GMSKDemodulator, and the existing ASM frame-state recovery.
%
% No MAT channel is used here.  The test must pass at 100 dB before the
% official detector is allowed into a real-H A/B sweep.

clear classes
rng(20260716, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

cases = { ...
    'none',          'none'; ...
    'convolutional', '1/2';  ...
    'convolutional', '2/3';  ...
    'convolutional', '3/4';  ...
    'convolutional', '5/6';  ...
    'convolutional', '7/8'   ...
};

numFrames = 12;
sps = 8;
bt = 0.5;
tracebackDepth = 32;
rows = cell(size(cases, 1), 11);

for caseIndex = 1:size(cases, 1)
    coding = cases{caseIndex, 1};
    rate = cases{caseIndex, 2};
    numBytesTF = localFrameBytes(rate);

    txArgs = { ...
        'WaveformSource', 'synchronization and channel coding', ...
        'NumBytesInTransferFrame', numBytesTF, ...
        'Modulation', 'GMSK', ...
        'ChannelCoding', coding, ...
        'HasASM', true, ...
        'HasRandomizer', false, ...
        'BandwidthTimeProduct', bt, ...
        'SamplesPerSymbol', sps};
    if strcmp(coding, 'convolutional')
        txArgs = [txArgs, {'ConvolutionalCodeRate', rate}];
    end
    tx = ccsdsTMWaveformGenerator(txArgs{:});

    msg = int8(randi([0 1], tx.NumInputBits*numFrames, 1));
    [txWaveform, encodedBits] = tx(msg);
    encodedBits = logical(encodedBits(:));

    rng(20260716, 'twister');
    rxWaveform = awgn(txWaveform(:), 100, 'measured');

    officialCfg = struct( ...
        'SamplesPerSymbol', sps, ...
        'BandwidthTimeProduct', bt, ...
        'TracebackDepth', tracebackDepth, ...
        'OutputScale', 5);
    [rawMetric, officialInfo] = ...
        gmsk_official_viterbi_raw_metric(rxWaveform, officialCfg);

    markerCfg = gmsk_frame_reset_asm_config( ...
        coding, rate, numBytesTF, [], 'NRZ-L');
    assert(~isempty(markerCfg.asmTemplates), ...
        'No rectangular ASM template for %s %s.', coding, rate);

    resetCfg = struct();
    resetCfg.framePeriodBits = markerCfg.framePeriodBits;
    resetCfg.asmTemplates = markerCfg.asmTemplates;
    resetCfg.asmOffsetBits = markerCfg.asmOffsetBits;
    resetCfg.asmMaxErrors = max(2, ...
        ceil(0.20*size(markerCfg.asmTemplates, 1)));
    resetCfg.asmMinGap = max(3, ...
        ceil(0.25*size(markerCfg.asmTemplates, 1)));
    resetCfg.maxSearchFrames = 8;
    resetCfg.minSearchFrames = 3;
    resetCfg.inputIsRawMetric = true;

    [soft, frameInfo] = ...
        gmsk_frame_reset_demodulate(rawMetric, resetCfg);
    assert(frameInfo.GridFound, ...
        'Official Viterbi ASM grid not found for %s %s: %s', ...
        coding, rate, frameInfo.FailureReason);

    [truth, txStartFrame] = localTruth(soft, frameInfo.FrameAccepted, ...
        encodedBits, markerCfg.framePeriodBits);
    perFrameBER = localPerFrameBER( ...
        soft, truth, markerCfg.framePeriodBits);
    accepted = logical(frameInfo.FrameAccepted(:));
    acceptedBER = perFrameBER(accepted);
    if isempty(acceptedBER)
        encodedBER = NaN;
    else
        encodedBER = mean(acceptedBER);
    end
    perfectFrameRate = mean(accepted & perFrameBER == 0);

    rows(caseIndex,:) = {coding, rate, numBytesTF, ...
        markerCfg.framePeriodBits, officialInfo.TracebackDepth, ...
        officialInfo.OutputSymbols, frameInfo.FrameStart, ...
        txStartFrame, encodedBER, perfectFrameRate, ...
        frameInfo.AcceptedFrames};

    fprintf(['%s %s | period=%d, output=%d, grid=%d, TXstart=%d, ', ...
        'BER=%.6g, perfect=%.1f%%, accepted=%d/%d\n'], ...
        coding, rate, markerCfg.framePeriodBits, ...
        officialInfo.OutputSymbols, frameInfo.FrameStart, txStartFrame, ...
        encodedBER, 100*perfectFrameRate, frameInfo.AcceptedFrames, ...
        frameInfo.TotalFrames);

    assert(encodedBER == 0 && all(perFrameBER(accepted) == 0), ...
        'Official Viterbi ideal-link validation failed for %s %s.', ...
        coding, rate);
end

summary = cell2table(rows, 'VariableNames', { ...
    'ChannelCoding','Rate','NumBytesTF','FramePeriodBits', ...
    'TracebackDepth','OutputSymbols','GridStart','TxStartFrame', ...
    'EncodedBER','PerfectFrameRate','AcceptedFrames'});
disp(summary);
assignin('base', 'gmskOfficialViterbiShortSummary', summary);
fprintf('[GMSK official Viterbi short test] PASS\n');

function n = localFrameBytes(rate)
    n = 1115;
    if strcmp(rate, '5/6')
        n = 1116;
    elseif strcmp(rate, '7/8')
        n = 1123;
    end
end

function [truth, bestTxStart] = localTruth( ...
        soft, accepted, encoded, framePeriod)
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
