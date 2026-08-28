function results = test_tpc_common_path()
%TEST_TPC_COMMON_PATH Verify the common TPC decoder soft-bit convention.
%   Exercises the same encoded transfer frames through generic TM soft
%   metrics (positive = bit 1) and the official GMSK detector convention
%   (positive = bit 0). HelperCCSDSTMDecoder must normalize both paths and
%   recover identical transfer-frame bits.

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir, '-begin');

    rng(7, 'twister');
    numBytes = 2025;
    blocksPerTF = 8;
    numFrames = 2;
    asmBits = int8(dec2bin(hex2dec('1ACFFC1D'), 32).' - '0');
    modulations = ["BPSK"; "GMSK"];
    randomizerEnabled = [false; true; true];
    randomizerPosition = ["afterEncoding"; "beforeEncoding"; "afterEncoding"];
    numRows = numel(modulations) * numel(randomizerEnabled);
    modulationCol = strings(numRows, 1);
    randomizerEnabledCol = false(numRows, 1);
    randomizerPositionCol = strings(numRows, 1);
    errors = zeros(numRows, 1);
    comparedBits = zeros(numRows, 1);
    ber = nan(numRows, 1);

    iRow = 0;
    for iRand = 1:numel(randomizerEnabled)
        txBits = int8(randi([0 1], numBytes*8*numFrames, 1));
        encoderInput = txBits;
        if randomizerEnabled(iRand) && ...
                randomizerPosition(iRand) == "beforeEncoding"
            % tmBase defines the TPC TM randomizer period as one 64x64
            % codeword (4096 bits).  The before-encoding path repeats that
            % PRN continuously across information frames.
            encoderInput = localRepeatingBitXor(encoderInput, 64*64);
        end
        encodedBits = ccsdsTPCEncodeBits(encoderInput, true, asmBits, ...
            'TPCCodeRate', '1/2', ...
            'TPCBlocksPerTF', blocksPerTF, ...
            'TPCInterleaver', 'auto');
        if randomizerEnabled(iRand) && ...
                randomizerPosition(iRand) == "afterEncoding"
            encodedBits = localTPCEncodedPayloadXor(encodedBits, numFrames, ...
                numel(asmBits));
        end

        for iMod = 1:numel(modulations)
            iRow = iRow + 1;
            modulationCol(iRow) = modulations(iMod);
            randomizerEnabledCol(iRow) = randomizerEnabled(iRand);
            randomizerPositionCol(iRow) = randomizerPosition(iRand);
            if modulations(iMod) == "GMSK"
                softBits = 1 - 2*double(encodedBits); % official: bit 0 positive
            else
                softBits = 2*double(encodedBits) - 1; % generic: bit 1 positive
            end

            decoder = HelperCCSDSTMDecoder( ...
                'ChannelCoding', 'TPC', ...
                'Modulation', char(modulations(iMod)), ...
                'RandomizerEnabled', randomizerEnabled(iRand), ...
                'RandomizerFECPosition', char(randomizerPosition(iRand)), ...
                'HasASM', true, ...
                'NumBytesInTransferFrame', numBytes, ...
                'TPCCodeRate', '1/2', ...
                'TPCBlocksPerTF', blocksPerTF, ...
                'TPCInterleaver', 'auto', ...
                'PCMFormat', 'NRZ-L');
            cleanupDecoder = onCleanup(@() release(decoder));
            decodedBits = decoder(softBits);

            comparedBits(iRow) = min(numel(decodedBits), numel(txBits));
            if comparedBits(iRow) > 0
                errors(iRow) = nnz(int8(decodedBits(1:comparedBits(iRow))) ~= ...
                    txBits(1:comparedBits(iRow)));
                ber(iRow) = errors(iRow) / comparedBits(iRow);
            end
            clear cleanupDecoder;
        end
    end

    results = table(modulationCol, randomizerEnabledCol, ...
        randomizerPositionCol, comparedBits, errors, ber, ...
        'VariableNames', {'Modulation','RandomizerEnabled', ...
        'RandomizerFECPosition','ComparedBits','BitErrors','BER'});
    disp(results);

    assert(all(comparedBits == numel(txBits)), ...
        'TPC common-path test did not return every transfer-frame bit.');
    assert(all(errors == 0), ...
        'TPC common-path polarity regression detected.');
end

function out = localRepeatingBitXor(bits, prnLength)
    out = int8(bits(:));
    prn = int8(satcom.internal.ccsds.tmrandseq(prnLength));
    tiled = repmat(prn, ceil(numel(out)/numel(prn)), 1);
    out = bitxor(out, tiled(1:numel(out)));
end

function out = localTPCEncodedPayloadXor(bits, numFrames, asmLength)
    out = int8(bits(:));
    frameLength = floor(numel(out) / numFrames);
    payloadLength = frameLength - asmLength;
    prn = int8(satcom.internal.ccsds.tmrandseq(payloadLength));
    for iFrame = 1:numFrames
        idx = (iFrame-1)*frameLength + asmLength + (1:payloadLength);
        out(idx) = bitxor(out(idx), prn);
    end
end
