function symbols = uqpskMapBitsLocal(bitsIn, rRatio, aRatio)
%UQPSKMAPBITSLOCAL UQPSK 固定映射
% RRatio=2 时：每 3 bit -> 2 个符号
%   b1 -> 第 1 个符号 I 路
%   b2 -> 第 2 个符号 I 路
%   b3 -> 两个符号共用的 Q 路

    bitsIn = int8(bitsIn(:));

    bitsPerGroup = rRatio + 1;
    nGroups = floor(numel(bitsIn) / bitsPerGroup);

    if nGroups <= 0
        symbols = complex(zeros(0,1));
        return;
    end

    bitsIn = bitsIn(1:nGroups * bitsPerGroup);
    b = reshape(bitsIn, bitsPerGroup, nGroups);

    iBits = b(1:rRatio, :);
    qBits = b(rRatio + 1, :);

    iVals = 1 - 2 * double(iBits(:));
    qVals = repelem(1 - 2 * double(qBits(:)), rRatio);

    symbols = complex(iVals, qVals / aRatio);

    symbols = symbols / sqrt(mean(abs(symbols).^2) + eps);
end