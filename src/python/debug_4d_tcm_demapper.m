function results = debug_4d_tcm_demapper(effList, nGroups)
%DEBUG_4D_TCM_DEMAPPER 定位 4D-8PSK-TCM 本地 demapper 是否匹配官方调制器。
%
% 用法:
%   debug_4d_tcm_demapper
%   debug_4d_tcm_demapper([2 2.25], 12)
%
% 这个脚本不走信道、不同步、不译码帧，只做最小闭环:
%   原始 bit -> 官方 4D-TCM 调制器 -> HelperCCSDSTMDemodulator -> bit 比较
%
% 如果这里某个效率已经 BER=0.5, 那说明问题不在 timing/CFO/ASM,
% 而在本地 4D-TCM Viterbi demapper 的高效率映射或状态机。
%
% 同时比较两个 MathWorks 内部调制入口:
%   1. fourD8PSKTCMMod
%   2. cg_fourD8PSKTCMMod_int8
%
% 如果两个入口输出不同, 说明本地 demapper 必须明确对齐当前发射器实际使用的入口。

    if nargin < 1 || isempty(effList)
        effList = [2 2.25 2.5 2.75];
    end
    if nargin < 2 || isempty(nGroups)
        nGroups = 10;
    end

    rng(1);

    results = table( ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'Eff','NumBits','Err_fourD','Err_cg','FirstErr_fourD','FirstErr_cg','CG_vs_fourD'});

    fprintf('\n================ DEBUG 4D-TCM DEMAPPER ================\n');
    fprintf('nGroups=%d. This test bypasses channel, sync, ASM, and frame decoding.\n', nGroups);

    for iEff = 1:numel(effList)
        eff = double(effList(iEff));
        nBitsPerGroup = round(4 * eff);
        nBits = nGroups * nBitsPerGroup;

        txBits = int8(randi([0 1], nBits, 1));
        conv0 = zeros(6, 1, 'int8');
        diff0 = zeros(3, 1, 'int8');

        [symFourD, convFourD, diffFourD] = satcom.internal.ccsds.fourD8PSKTCMMod( ...
            txBits, eff, conv0, diff0);

        [symCG, convCG, diffCG] = satcom.internal.ccsds.cg_fourD8PSKTCMMod_int8( ...
            txBits, eff, conv0, diff0);

        demod = HelperCCSDSTMDemodulator( ...
            'Modulation', '4D-8PSK-TCM', ...
            'ChannelCoding', 'none', ...
            'ModulationEfficiency', eff);

        rxFourD = int8(demod(symFourD) > 0);
        release(demod);

        demod = HelperCCSDSTMDemodulator( ...
            'Modulation', '4D-8PSK-TCM', ...
            'ChannelCoding', 'none', ...
            'ModulationEfficiency', eff);
        rxCG = int8(demod(symCG) > 0);

        LFourD = min(numel(rxFourD), nBits);
        LCG = min(numel(rxCG), nBits);

        errFourD = nnz(rxFourD(1:LFourD) ~= txBits(1:LFourD));
        errCG = nnz(rxCG(1:LCG) ~= txBits(1:LCG));

        firstErrFourD = firstMismatch(rxFourD, txBits);
        firstErrCG = firstMismatch(rxCG, txBits);

        if numel(symFourD) == numel(symCG) && max(abs(symFourD(:) - symCG(:))) < 1e-12 && ...
                isequal(convFourD, convCG) && isequal(diffFourD, diffCG)
            cgVsFourD = "same";
        else
            cgVsFourD = "different";
        end

        fprintf('\neff=%.2f, bits/group=%d, nBits=%d\n', eff, nBitsPerGroup, nBits);
        fprintf('  fourD mod -> local demapper: err=%d/%d, firstErr=%d\n', ...
            errFourD, LFourD, firstErrFourD);
        fprintf('  cg mod    -> local demapper: err=%d/%d, firstErr=%d\n', ...
            errCG, LCG, firstErrCG);
        fprintf('  cg vs fourD mod output: %s\n', cgVsFourD);

        results = [results; {eff, nBits, errFourD, errCG, firstErrFourD, firstErrCG, cgVsFourD}]; %#ok<AGROW>
    end

    fprintf('\n================ SUMMARY ================\n');
    disp(results);
end

function idx = firstMismatch(a, b)
    L = min(numel(a), numel(b));
    d = find(int8(a(1:L)) ~= int8(b(1:L)), 1, 'first');
    if isempty(d)
        idx = 0;
    else
        idx = d;
    end
end
