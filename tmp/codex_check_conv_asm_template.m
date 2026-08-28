clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

asm = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
hardcoded = int8([1;0;0;0;0;0;0;1;1;1;0;0;1;0;0;1;0;1;1;1;0;0;0;1;1;0;1; ...
    0;1;0;1;0;0;1;1;1;0;0;1;1;1;1;0;1;0;0;1;1;1;1;1;0]);

base = poly2trellis(7,[171 133]);
[trellis, mode] = ccsdsTMConvolutionalOutputTrellis(base, 'G1G2-inverted', '1/2');
enc = comm.ConvolutionalEncoder('TrellisStructure', trellis);
y = int8(enc(asm));
built = y(13:end);

encOld = comm.ConvolutionalEncoder('TrellisStructure', base);
yOld = int8(encOld(asm));
yOld(2:2:end) = int8(~logical(yOld(2:2:end)));
builtOld = yOld(13:end);

fprintf('mode=%s len=%d hardcoded-vs-new errors=%d, hardcoded-vs-old errors=%d, new-vs-old errors=%d\n', ...
    mode, numel(built), nnz(hardcoded ~= built), nnz(hardcoded ~= builtOld), nnz(built ~= builtOld));
fprintf('corr hardcoded/new=%+.6f hardcoded/old=%+.6f\n', ...
    mean((2*double(hardcoded)-1).*(2*double(built)-1)), ...
    mean((2*double(hardcoded)-1).*(2*double(builtOld)-1)));
