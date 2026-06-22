function [encodedBits, info] = ccsdsTPCEncodeBits(bits, hasASM, asmBits)
%CCSDSTPCENCODEBITS Encode serial bits with the teacher TPC encoder.
%   TPC code is fixed to extended Hamming product code (64,57)^2.

    m = 6;
    n = 2^m - 1;
    N = n + 1;
    k = n - m;
    genpoly = [1 0 0 0 0 1 1];
    [~, G] = hammgen(m, genpoly);

    infoLen = k * k;
    codeLen = N * N;

    bits = int8(bits(:) ~= 0);
    padBits = ceil(numel(bits)/infoLen)*infoLen - numel(bits);
    if padBits > 0
        bits = [bits; zeros(padBits, 1, 'int8')];
    end

    numBlocks = numel(bits) / infoLen;
    syncLen = numel(asmBits) * logical(hasASM);
    encodedBits = zeros((syncLen + codeLen) * numBlocks, 1, 'int8');

    for iBlock = 1:numBlocks
        inIdx = (iBlock-1)*infoLen+1:iBlock*infoLen;
        msg = reshape(double(bits(inIdx)), k, k);
        encout = TPC_encoder(msg, n, k, G, genpoly);
        cw = int8(encout(:));

        if hasASM
            outBlock = [int8(asmBits(:)); cw];
        else
            outBlock = cw;
        end
        outIdx = (iBlock-1)*(syncLen + codeLen)+1:iBlock*(syncLen + codeLen);
        encodedBits(outIdx) = outBlock;
    end

    info = struct();
    info.N = N;
    info.K = k;
    info.InfoBlockBits = infoLen;
    info.CodeBlockBits = codeLen;
    info.NumBlocks = numBlocks;
    info.PadBits = padBits;
    info.CodeRate = infoLen / codeLen;
end
