function [encodedBits, info] = ccsdsTPCEncodeBits(bits, hasASM, asmBits, varargin)
%CCSDSTPCENCODEBITS Encode serial bits with the teacher TPC encoder.
%   TPC code is fixed to extended Hamming product code (64,57)^2.

    p = inputParser;
    addParameter(p, 'TPCCodeRate', 'native');
    addParameter(p, 'TPCBlocksPerTF', 1);
    parse(p, varargin{:});

    m = 6;
    n = 2^m - 1;
    N = n + 1;
    k = n - m;
    genpoly = [1 0 0 0 0 1 1];
    [~, G] = hammgen(m, genpoly);

    infoLen = k * k;
    codeLen = N * N;
    [payloadSideLen, rateLabel] = localTPCPayloadSideLength(p.Results.TPCCodeRate, k);
    payloadLen = payloadSideLen * payloadSideLen;
    blocksPerTF = localPositiveInteger(p.Results.TPCBlocksPerTF, 1);
    tfPayloadLen = payloadLen * blocksPerTF;

    bits = int8(bits(:) ~= 0);
    padBits = ceil(numel(bits)/tfPayloadLen)*tfPayloadLen - numel(bits);
    if padBits > 0
        bits = [bits; zeros(padBits, 1, 'int8')];
    end

    numTF = numel(bits) / tfPayloadLen;
    numBlocks = numTF * blocksPerTF;
    syncLen = numel(asmBits) * logical(hasASM);
    codedTFLen = syncLen + codeLen * blocksPerTF;
    encodedBits = zeros(codedTFLen * numTF, 1, 'int8');

    for iTF = 1:numTF
        codedFrame = zeros(codedTFLen, 1, 'int8');
        writePos = 1;

        if hasASM
            codedFrame(writePos:writePos+syncLen-1) = int8(asmBits(:));
            writePos = writePos + syncLen;
        end

        for jBlock = 1:blocksPerTF
            globalBlock = (iTF-1)*blocksPerTF + jBlock;
            inIdx = (globalBlock-1)*payloadLen+1:globalBlock*payloadLen;
            msg = zeros(k, k);
            msg(1:payloadSideLen, 1:payloadSideLen) = ...
                reshape(double(bits(inIdx)), payloadSideLen, payloadSideLen);
            encout = TPC_encoder(msg, n, k, G, genpoly);
            cw = int8(encout(:));

            codedFrame(writePos:writePos+codeLen-1) = cw;
            writePos = writePos + codeLen;
        end

        outIdx = (iTF-1)*codedTFLen+1:iTF*codedTFLen;
        encodedBits(outIdx) = codedFrame;
    end

    info = struct();
    info.N = N;
    info.K = k;
    info.TPCCodeRate = rateLabel;
    info.NativeInfoBlockBits = infoLen;
    info.PayloadSideBits = payloadSideLen;
    info.InfoBlockBits = payloadLen;
    info.CodeBlockBits = codeLen;
    info.TPCBlocksPerTF = blocksPerTF;
    info.NumTransferFrames = numTF;
    info.NumBlocks = numBlocks;
    info.PadBits = padBits;
    info.CodedTransferFrameBits = codedTFLen;
    info.InfoBitsPerTransferFrame = tfPayloadLen;
    info.CodeRate = payloadLen / codeLen;
    info.NativeCodeRate = infoLen / codeLen;
end

function [payloadSideLen, label] = localTPCPayloadSideLength(rawRate, nativeSideLen)
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
        error('ccsdsTPCEncodeBits:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end

function value = localPositiveInteger(rawValue, defaultValue)
    if nargin < 2
        defaultValue = 1;
    end
    if nargin < 1 || isempty(rawValue)
        value = defaultValue;
        return;
    end
    if ischar(rawValue) || isstring(rawValue)
        value = str2double(strtrim(char(rawValue)));
    else
        value = double(rawValue);
    end
    if ~isfinite(value)
        value = defaultValue;
    end
    value = max(1, round(value));
end
