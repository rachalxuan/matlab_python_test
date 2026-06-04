clc;
clear;

rEff = 2;
nGroups = 50;
nBitsPerGroup = round(4*rEff);
nBits = nGroups * nBitsPerGroup;

modin = int8(randi([0 1], nBits, 1));

conv0 = zeros(6,1,'int8');
diff0 = zeros(3,1,'int8');

fprintf('Testing internal cg_fourD8PSKTCMMod_int8 + local Viterbi\n');
fprintf('rEff=%g, nGroups=%d, nBits=%d\n', rEff, nGroups, nBits);

[sym, convEnd, diffEnd] = satcom.internal.ccsds.cg_fourD8PSKTCMMod_int8( ...
    modin, double(rEff), conv0, diff0);

fprintf('length(sym)=%d\n', length(sym));
fprintf('convEnd = %s\n', mat2str(convEnd.'));
fprintf('diffEnd = %s\n', mat2str(diffEnd.'));

bitsHat = fourD8PSKTCMViterbiDemod(sym, rEff);

L = min(length(bitsHat), length(modin));
err = nnz(int8(bitsHat(1:L)) ~= int8(modin(1:L)));

fprintf('err = %d / %d\n', err, L);