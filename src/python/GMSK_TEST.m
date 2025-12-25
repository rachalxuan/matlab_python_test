% GMSK_TEST.m
% GMSK 专项隔离测试脚本 (真相大白版 - 确定性载荷)
clc; clear; close all;

fprintf('======================================================\n');
fprintf('🚀 GMSK 专项隔离测试启动 (Payload Pattern Mode)...\n');

% 1. 核心参数 
sps = 8;
bt = 0.5;
numFrames = 20; % 帧数少一点，方便看
snr_val = 100;   

try
    %% A. 发送端 (Tx)
    % 生成器配置
    gen = ccsdsTMWaveformGenerator(...
        'WaveformSource', 'synchronization and channel coding', ...
        'Modulation', 'GMSK', ...
        'BandwidthTimeProduct', bt, ...
        'SamplesPerSymbol', sps, ...
        'ChannelCoding', 'none', ...
        'NumBytesInTransferFrame', 223, ... 
        'HasASM', true, ...                 
        'HasRandomizer', false); % 必须关掉随机化，否则载荷会被加扰！
    
    msg = [];
    validTxFrames = {};
    numHeaderBits = 8;
    numPayloadBits = gen.NumInputBits - numHeaderBits;
    
    % 【关键】构造特征极其鲜明的帧
    % 帧头：计数器 (0, 1, 2...)
    % 载荷：全 0 (这样解出来应该是一大片 0)
    for i = 1:numFrames
        header = de2bi(mod(i-1, 256), numHeaderBits, 'left-msb')';
        payload = zeros(numPayloadBits, 1); % 全 0 载荷
        currentFrame = [header; payload];
        msg = [msg; currentFrame];
        validTxFrames{end+1} = currentFrame;
    end
    
    txWaveform = gen(msg);
    Fs = 1e6; 
    
    %% B. 信道 (Channel)
    fprintf('[Ch] 添加高斯白噪声 (SNR=%d dB)...\n', snr_val);
    rxWaveform = awgn(txWaveform, snr_val, 'measured');
    pfo = comm.PhaseFrequencyOffset('FrequencyOffset', 200, 'SampleRate', Fs);
    rxWaveform = pfo(rxWaveform);

    %% C. 接收机同步 (Rx Sync)
    fprintf('[Rx] 开始同步处理...\n');
    dPhi = angle(rxWaveform(2:end) .* conj(rxWaveform(1:end-1)));
    estCFO = median(dPhi) / (2*pi) * Fs;
    pfo_corrector = comm.PhaseFrequencyOffset('FrequencyOffset', -estCFO, 'SampleRate', Fs);
    rxSynced = pfo_corrector(rxWaveform);
    
    rxFilterDecimationFactor = sps/2;
    rxfilter = comm.RaisedCosineReceiveFilter('RolloffFactor', 0.5, 'InputSamplesPerSymbol', sps, 'DecimationFactor', rxFilterDecimationFactor); 
    filtered = rxfilter(rxSynced);
    
    timingObj = comm.SymbolSynchronizer(...
        'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
        'SamplesPerSymbol', 2, 'DetectorGain', 5.0, ...          
        'Modulation', 'PAM/PSK/QAM', 'DampingFactor', 1, 'NormalizedLoopBandwidth', 0.05); 
    fineSynced = timingObj(filtered);
    
    %% D. 解调 (Demod)
    fprintf('[Rx] 调用 HelperCCSDSTMDemodulator...\n');
    demodobj = HelperCCSDSTMDemodulator('Modulation', 'GMSK', 'ChannelCoding', 'none', 'BandwidthTimeProduct', bt);
    demodData = demodobj(fineSynced);
    
    %% E. ASM 智能纠错与诊断
    asmBits = [0 0 0 1 1 0 1 0 1 1 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 1 1 1 0 1]';
    asmBipolar = 2*double(asmBits) - 1; 
    
    chkLen = min(5000, length(demodData));
    snippet = demodData(1:chkLen);
    bitsRaw = double(snippet < 0); 
    
    calcCorr = @(seq) max(abs(xcorr(2*seq-1, asmBipolar)));
    s0=bitsRaw; s1=~bitsRaw; s2=bitsRaw; s2(2:2:end)=~s2(2:2:end); s3=bitsRaw; s3(1:2:end)=~s3(1:2:end);
    [maxVal, idx] = max([calcCorr(s0), calcCorr(s1), calcCorr(s2), calcCorr(s3)]);
    
    modes = {'Normal', 'Inverted', 'AltA', 'AltB'};
    fprintf('  [诊断] ASM 模式: %s (Idx=%d), 峰值: %.1f\n', modes{idx}, idx, maxVal);
    
    % 应用修复
    fullHardBits = double(demodData < 0);
    if idx==2, fullHardBits = ~fullHardBits;
    elseif idx==3, fullHardBits(2:2:end) = ~fullHardBits(2:2:end);
    elseif idx==4, fullHardBits(1:2:end) = ~fullHardBits(1:2:end);
    end

    %% F. 译码与肉眼诊断
    decoderobj = HelperCCSDSTMDecoder('ChannelCoding', 'none', 'Modulation', 'GMSK', ...
        'NumBytesInTransferFrame', 223, 'HasASM', true,'HasRandomizer', false);
    
    % 送入硬比特
    decodedBits = decoderobj(double(fullHardBits));
    
    fprintf('  [肉眼诊断] 打印解调出的前 200 个比特:\n');
    % 我们期望看到： [帧头1] [00000...] [帧头2] [00000...]
    dispStr = sprintf('%d', decodedBits(1:min(200, end)));
    % 每 80 个字符换行，方便看
    for k = 1:80:length(dispStr)
        eIdx = min(k+79, length(dispStr));
        fprintf('  %s\n', dispStr(k:eIdx));
    end
    
    % 检查全0比例
    zeroRatio = sum(decodedBits == 0) / length(decodedBits);
    fprintf('  [统计] 0 的比例: %.2f%% (期望接近 100%%，因为载荷是全0)\n', zeroRatio*100);
    
    % 自动 BER 计算 (仅当载荷正确时有效)
    if zeroRatio > 0.9
        fprintf('  ✅ 载荷正确！大部分都是 0。\n');
    else
        fprintf('  ❌ 载荷错误！看起来像乱码。\n');
    end

catch ME
    fprintf('⚠️ 发生错误: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('   File: %s, Line: %d\n', ME.stack(1).name, ME.stack(1).line);
    end
end