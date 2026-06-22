function [decodedBits, info] = ccsdsTPCDecodeSoft(cwSoft, varargin)
%CCSDSTPCDECODESOFT Decode serial soft TPC codeblocks with teacher decoder.
%   Input soft convention follows the existing receiver: bit 1 positive,
%   bit 0 negative.

    p = inputParser;
    addParameter(p, 'Iterations', 6);
    addParameter(p, 'LeastReliableBits', 4);
    addParameter(p, 'Alpha', 0.5);
    addParameter(p, 'Beta', 1);
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
    cwSoft = double(cwSoft(:));
    numBlocks = floor(numel(cwSoft) / codeLen);
    decodedBits = zeros(numBlocks * infoLen, 1, 'int8');

    oldDir = pwd;
    tpcDir = fileparts(which('TPC_decoder.m'));
    cleanupObj = onCleanup(@() cd(oldDir));
    if ~isempty(tpcDir)
        cd(tpcDir);
    end

    for iBlock = 1:numBlocks
        idx = (iBlock-1)*codeLen+1:iBlock*codeLen;
        rxMat = reshape(cwSoft(idx), N, N);
        [decout, ~] = TPC_decoder(rxMat, n, k, H, ...
            p.Results.LeastReliableBits, p.Results.Alpha, ...
            p.Results.Beta, p.Results.Iterations);
        decodedBits((iBlock-1)*infoLen+1:iBlock*infoLen) = int8(decout(:) ~= 0);
    end

    clear cleanupObj;

    info = struct();
    info.N = N;
    info.K = k;
    info.InfoBlockBits = infoLen;
    info.CodeBlockBits = codeLen;
    info.NumBlocks = numBlocks;
    info.CodeRate = infoLen / codeLen;
end
