clc;
clear;

load('tm_ldpc_H_k7136_n8160.mat','H','k','n','invr');

Gc = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(k, invr);

msg = randi([0 1], k, 1, 'int8');
cw = int8(satcom.internal.ccsds.tmldpcEncode(msg, Gc));

fprintf('k=%d, n=%d, parity=%d\n', k, n, n-k);

syn = mod(H * double(cw(:)), 2);
fprintf('syndrome weight = %d\n', nnz(syn));

ldpcCfg = ldpcDecoderConfig(sparse(logical(H)));

% LLR 约定测试：
% A: bit 0 -> 正，bit 1 -> 负
% B: 反过来
llrA =  20 * double(1 - 2*double(cw));
llrB = -20 * double(1 - 2*double(cw));

fprintf('Start LDPC decode A...\n');
decA = ldpcDecode(llrA, ldpcCfg, 5, 'OutputFormat','whole');

fprintf('Start LDPC decode B...\n');
decB = ldpcDecode(llrB, ldpcCfg, 5, 'OutputFormat','whole');

msgA = int8(decA(1:k));
msgB = int8(decB(1:k));

errA = sum(msgA ~= msg);
errB = sum(msgB ~= msg);

errA_inv = sum(int8(~logical(msgA)) ~= msg);
errB_inv = sum(int8(~logical(msgB)) ~= msg);

fprintf('errA     = %d\n', errA);
fprintf('errB     = %d\n', errB);
fprintf('errA_inv = %d\n', errA_inv);
fprintf('errB_inv = %d\n', errB_inv);