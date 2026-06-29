function [decodedBits, info] = ccsdsTPCDecodeSoft(cwSoft, varargin)
%CCSDSTPCDECODESOFT Decode serial soft TPC codeblocks with teacher decoder.
%   Input soft convention follows the existing receiver: bit 1 positive,
%   bit 0 negative.

    p = inputParser;
    addParameter(p, 'Iterations', 6);
    addParameter(p, 'LeastReliableBits', 4);
    addParameter(p, 'Alpha', 0.5);
    addParameter(p, 'Beta', 1);
    addParameter(p, 'TPCCodeRate', 'native');
    addParameter(p, 'TPCInterleaver', 'auto');
    parse(p, varargin{:});

    m = 6;
    n = 2^m - 1;
    N = n + 1;
    k = n - m;
    genpoly = [1 0 0 0 0 1 1];
    [H, ~] = hammgen(m, genpoly);
    H = [H(:,m+1:end), H(:,1:m)];

    infoLen = k * k;
    codeLen = N * N;
    [payloadSideLen, rateLabel] = localTPCPayloadSideLength(p.Results.TPCCodeRate, k);
    payloadLen = payloadSideLen * payloadSideLen;
    payloadIdx = localTPCPayloadIndices(rateLabel, payloadSideLen, k);
    interleaverMode = localTPCInterleaverMode(p.Results.TPCInterleaver, rateLabel);
    interleaverIdx = localTPCInterleaverIndices(codeLen, interleaverMode);
    cwSoft = double(cwSoft(:));
    numBlocks = floor(numel(cwSoft) / codeLen);
    decodedBits = zeros(numBlocks * payloadLen, 1, 'int8');

    oldDir = pwd;
    tpcDir = fileparts(which('TPC_decoder.m'));
    cleanupObj = onCleanup(@() cd(oldDir));
    if ~isempty(tpcDir)
        cd(tpcDir);
    end

    for iBlock = 1:numBlocks
        idx = (iBlock-1)*codeLen+1:iBlock*codeLen;
        deinterleavedSoft = zeros(codeLen, 1);
        deinterleavedSoft(interleaverIdx) = cwSoft(idx);
        rxMat = reshape(deinterleavedSoft, N, N);
        [decout, ~] = TPC_decoder(rxMat, n, k, H, ...
            p.Results.LeastReliableBits, p.Results.Alpha, ...
            p.Results.Beta, p.Results.Iterations);
        decPayload = int8(decout(payloadIdx) ~= 0);
        decodedBits((iBlock-1)*payloadLen+1:iBlock*payloadLen) = decPayload(:);
    end

    clear cleanupObj;

    info = struct();
    info.N = N;
    info.K = k;
    info.TPCCodeRate = rateLabel;
    info.NativeInfoBlockBits = infoLen;
    info.PayloadSideBits = payloadSideLen;
    info.PayloadMaskMode = localTPCPayloadMaskMode(rateLabel);
    info.TPCInterleaver = interleaverMode;
    info.InfoBlockBits = payloadLen;
    info.CodeBlockBits = codeLen;
    info.NumBlocks = numBlocks;
    info.CodeRate = payloadLen / codeLen;
    info.NativeCodeRate = infoLen / codeLen;
end

function idx = localTPCPayloadIndices(rateLabel, payloadSideLen, nativeSideLen)
    mask = false(nativeSideLen, nativeSideLen);
    mask(1:payloadSideLen, 1:payloadSideLen) = true;
    idx = find(mask);
end

function mode = localTPCPayloadMaskMode(rateLabel)
    mode = 'top-left-square';
    if strcmp(rateLabel, '1/2')
        mode = 'top-left-square-with-codeword-interleaver';
    end
end

function mode = localTPCInterleaverMode(rawMode, rateLabel)
    if nargin < 1 || isempty(rawMode)
        rawMode = 'auto';
    end
    mode = lower(strtrim(char(rawMode)));
    switch mode
        case {'auto','default'}
            if strcmp(rateLabel, '1/2')
                mode = 'block';
            else
                mode = 'none';
            end
        case {'none','off','bypass'}
            mode = 'none';
        case {'block','codeword','on'}
            mode = 'block';
        otherwise
            error('ccsdsTPCDecodeSoft:InvalidTPCInterleaver', ...
                'Unsupported TPCInterleaver="%s". Use auto, none, or block.', ...
                char(string(rawMode)));
    end
end

function idx = localTPCInterleaverIndices(codeLen, mode)
    idx = (1:codeLen).';
    if strcmp(mode, 'block')
        step = 257;
        idx = mod((0:codeLen-1).' * step, codeLen) + 1;
    end
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
        error('ccsdsTPCDecodeSoft:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end
