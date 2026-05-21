clc;
clear;

tests = {
    1024, "1/2";
    1024, "2/3";
    1024, "4/5";
};

for iCase = 1:size(tests,1)
    kReq = tests{iCase,1};
    rateReq = tests{iCase,2};

    fprintf('\n==============================\n');
    fprintf('Build and test k=%d, CodeRate=%s\n', kReq, rateReq);
    fprintf('==============================\n');

    tmWaveGen = ccsdsTMWaveformGenerator( ...
        'ChannelCoding','LDPC', ...
        'Modulation','QPSK', ...
        'HasASM',true, ...
        'HasRandomizer',false, ...
        'NumBitsInInformationBlock',kReq, ...
        'CodeRate',rateReq, ...
        'IsLDPCOnSMTF',false);

    s = info(tmWaveGen);

    k = tmWaveGen.NumInputBits;
    rate = s.ActualCodeRate;
    n = round(k / rate);
    invr = n / k;

    fprintf('CodeRate property = %s\n', string(tmWaveGen.CodeRate));
    fprintf('ActualCodeRate    = %.9f\n', rate);
    fprintf('k=%d, n=%d, parity=%d, invr=%.12f\n', k, n, n-k, invr);

    H = buildTMLDPC_H_from_encoder(k, invr);

    Gc = satcom.internal.ccsds.getTMLDPCGeneratorMatrix(k, invr);

    % 1. syndrome 验证
    for tt = 1:5
        msg = randi([0 1], k, 1, 'int8');
        cw = int8(satcom.internal.ccsds.tmldpcEncode(msg, Gc));

        syn = mod(H * double(cw(:)), 2);
        fprintf('  syndrome test %d: weight=%d\n', tt, nnz(syn));

        if nnz(syn) ~= 0
            error('Syndrome check failed: k=%d, rate=%s', k, rateReq);
        end
    end

    % 2. ldpcDecode 无噪声验证
    ldpcCfg = ldpcDecoderConfig(sparse(logical(H)));

    for tt = 1:5
        msg = randi([0 1], k, 1, 'int8');
        cw = int8(satcom.internal.ccsds.tmldpcEncode(msg, Gc));

        % MATLAB ldpcDecode: bit 0 -> 正 LLR, bit 1 -> 负 LLR
        llr = 20 * double(1 - 2*double(cw(:)));

        dec = ldpcDecode(llr, ldpcCfg, 20, 'OutputFormat','whole');
        msgHat = int8(dec(1:k));

        err = sum(msgHat ~= msg);

        fprintf('  decode test %d: msgErr=%d\n', tt, err);

        if err ~= 0
            error('Noiseless decode failed: k=%d, rate=%s', k, rateReq);
        end
    end

    % 3. 保存
    tag = rateTagForFile(rateReq);
    saveName = sprintf('tm_ldpc_H_k%d_%s.mat', k, tag);
    save(saveName, 'H', 'k', 'n', 'invr', '-v7.3');

    fprintf('PASS and saved: %s\n', saveName);
end

fprintf('\nAll tests passed.\n');

function tag = rateTagForFile(rateReq)
    switch string(rateReq)
        case "1/2"
            tag = 'r1_2';
        case "2/3"
            tag = 'r2_3';
        case "4/5"
            tag = 'r4_5';
        otherwise
            error('Unsupported rate: %s', rateReq);
    end
end