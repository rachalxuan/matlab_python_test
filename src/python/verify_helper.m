function verify_helper()
    % GMSK Helper 逻辑验证脚本
    clc; clear; close all;
    fprintf('======== 开始验证 HelperCCSDSTMDemodulator ========\n');

    % 1. 配置发送端 (GMSK, BT=0.5)
    bt = 0.5; sps = 8;
    gen = ccsdsTMWaveformGenerator('Modulation','GMSK','BandwidthTimeProduct',bt,...
        'SamplesPerSymbol',sps, 'ChannelCoding','none', ...
        'HasASM',false, 'HasRandomizer',false, 'NumBytesInTransferFrame', 100);
    
    msg = randi([0 1], gen.NumInputBits, 1);
    txWaveform = gen(msg);
    
    % 2. 理想接收 (直接降采样，跳过信道和同步)
    % ccsdsTMWaveformGenerator 内部 GMSKModulator 有 1 符号延迟
    rxIdeal = txWaveform(1:sps:end); 
    
    % 3. 调用你的 Helper 进行解调
    fprintf('[测试] 正在调用 HelperCCSDSTMDemodulator...\n');
    helper = HelperCCSDSTMDemodulator('Modulation','GMSK', 'ChannelCoding','none', ...
        'BandwidthTimeProduct', bt);
    
    % 解调 (输入理想的 1 SPS 信号)
    softOut = helper(rxIdeal);
    hardOut = double(softOut < 0); % LLR<0 代表比特1
    
    % 4. 对齐并计算 BER
    % comm.GMSKDemodulator 有 TracebackDepth (默认16) 的延迟
    delay = 16; 
    rxBits = hardOut(delay+1:end);
    txBits = msg(1:length(rxBits));
    
    [~, ber] = biterr(rxBits, txBits);
    
    fprintf('--------------------------------------------------\n');
    if ber == 0
        fprintf('✅ 恭喜！Helper 逻辑正确！BER = 0.0000\n');
    elseif ber > 0.4
        fprintf('❌ 失败！Helper 逻辑缺失！BER = %.4f (通常约为 0.5)\n', ber);
        fprintf('   原因：Helper 中缺少了方案2的反馈差分循环 (for loop)。\n');
    else
        fprintf('⚠️ 警告：BER = %.4f (可能存在其他相位问题)\n', ber);
    end
    fprintf('--------------------------------------------------\n');
end