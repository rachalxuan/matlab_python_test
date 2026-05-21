clc;
clear;

% 默认 TM LDPC 配置
tmWaveGen = ccsdsTMWaveformGenerator( ...
    'ChannelCoding','LDPC', ...
    'Modulation','QPSK', ...
    'HasASM',true, ...
    'HasRandomizer',false);

s = info(tmWaveGen);

k = tmWaveGen.NumInputBits;
rate = s.ActualCodeRate;
n = round(k / rate);
invr = n / k;

fprintf('CodeRate property = %s/n', string(tmWaveGen.CodeRate));
fprintf('ActualCodeRate    = %.9f/n', rate);
fprintf('k=%d, n=%d, r=%d, invr=%.12f/n', k, n, n-k, invr);

H = buildTMLDPC_H_from_encoder(k, invr);

save('E:/web_code/react/fft_project/react-fft/src/python/tm_ldpc_H_k7136_n8160.mat','H','k','n','invr','-v7.3');

fprintf('Saved: tm_ldpc_H_k7136_n8160.mat\n');