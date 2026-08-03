function R = run_tm_msk_bit_contract()
%RUN_TM_MSK_BIT_CONTRACT
% 只验证标准 MSK 调制、官方解调和项目 soft metric 的 bit 对齐。
% 不经过 TM 帧、ASM、FEC、信道或同步。

    thisDir = fileparts(mfilename('fullpath'));
    sourceDir = fileparts(thisDir);
    addpath(sourceDir);

    rng(20260803, 'twister');

    numBits = 20000;
    txBits = logical(randi([0 1], numBits, 1));

    %% ---------- 1 SPS MSK ----------
    modObj = comm.MSKModulator( ...
        'BitInput',true, ...
        'InitialPhaseOffset',0, ...
        'SamplesPerSymbol',1);

    tx = modObj(txBits);

    %% ---------- 官方 MSK Demodulator ----------
    official = comm.MSKDemodulator( ...
        'BitOutput',true, ...
        'InitialPhaseOffset',0, ...
        'SamplesPerSymbol',1, ...
        'TracebackDepth',16);

    officialBits = logical(official(tx));
    tb = official.TracebackDepth;

    nOfficial = min(numel(txBits)-tb, numel(officialBits)-tb);

    officialBER = biterr( ...
        txBits(1:nOfficial), ...
        officialBits(tb+1:tb+nOfficial)) / nOfficial;

    %% ---------- 项目 MSK soft metric ----------
    helper = HelperCCSDSTMDemodulator( ...
        'Modulation','MSK', ...
        'ChannelCoding','none', ...
        'PCMFormat','NRZ-L');

    softBits = real(helper(tx));
    hardBits = softBits < 0;

    %% ---------- 只在测试中搜索固定 offset ----------
    offsets = -4:4;
    berByOffset = nan(size(offsets));

    for k = 1:numel(offsets)
        off = offsets(k);

        if off >= 0
            n = min(numel(txBits), numel(hardBits)-off);
            ref = txBits(1:n);
            got = hardBits(1+off:off+n);
        else
            d = -off;
            n = min(numel(txBits)-d, numel(hardBits));
            ref = txBits(1+d:d+n);
            got = hardBits(1:n);
        end

        berByOffset(k) = biterr(ref, got) / n;
    end

    [manualBER, idx] = min(berByOffset);
    bestOffset = offsets(idx);

    R = table( ...
        officialBER, manualBER, bestOffset, ...
        'VariableNames', { ...
        'OfficialBER','ManualBER','ManualBestOffset'});

    disp(R);

    fprintf('\nMSK manual offset table:\n');
    disp(table(offsets(:), berByOffset(:), ...
        'VariableNames',{'Offset','BER'}));

    assert(officialBER == 0, ...
        '官方 MSK 解调的无噪声 BER 不为 0：%.6g', officialBER);

    assert(manualBER == 0, ...
        '项目 MSK soft metric 的无噪声 BER 不为 0：%.6g', manualBER);
end