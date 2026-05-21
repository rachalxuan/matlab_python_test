function H = buildTMLDPC_H_from_encoder(k, invr)
% buildTMLDPC_H_from_encoder
% 从 MATLAB CCSDS TM LDPC encoder 反推出一个可用的 parity-check matrix.
%
% 假设 tmldpcEncode 输出 systematic codeword:
%   cw = [message; parity]
%
% 则:
%   G = [I, P]
%   H = [P^T, I]
%
% 注意:
%   这个 H 数学上可用，但不一定是标准 CCSDS LDPC 的稀疏 H。

    Gc = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(k, invr);

    z = zeros(k,1,'int8');
    cw0 = int8(satcom.internal.ccsds.tmldpcEncode(z, Gc));

    n = length(cw0);
    r = n - k;

    fprintf('[build H] k=%d, n=%d, r=%d\n', k, n, r);

    % 确认 systematic layout
    testMsg = randi([0 1], k, 1, 'int8');
    testCw = int8(satcom.internal.ccsds.tmldpcEncode(testMsg, Gc));

    if sum(testCw(1:k) ~= testMsg) ~= 0
        error('tmldpcEncode output is not [message; parity]. Stop.');
    end

    % 构造 P: k x r
    % 第 i 行 = 第 i 个 message basis vector 对应的 parity bits
    P = false(k, r);

    for i = 1:k
        if mod(i,200) == 0 || i == 1 || i == k
            fprintf('[build H] basis %d / %d\n', i, k);
        end

        e = zeros(k,1,'int8');
        e(i) = 1;

        cw = int8(satcom.internal.ccsds.tmldpcEncode(e, Gc));

        % systematic: cw = [msg; parity]
        P(i,:) = logical(cw(k+1:end)).';
    end

    H = sparse([P.' speye(r)]);

    fprintf('[build H] H size = %d x %d\n', size(H,1), size(H,2));
    fprintf('[build H] nnz(H) = %d, density = %.6f\n', nnz(H), nnz(H)/numel(H));

    % 快速 sanity check: H*cw == 0
    msg = randi([0 1], k, 1, 'int8');
    cw = int8(satcom.internal.ccsds.tmldpcEncode(msg, Gc));

    syndrome = mod(H * double(cw(:)), 2);
    fprintf('[build H] syndrome weight test = %d\n', nnz(syndrome));

    if nnz(syndrome) ~= 0
        error('Constructed H failed syndrome check.');
    end
end