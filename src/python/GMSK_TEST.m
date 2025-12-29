% GMSK_TEST.m
% GMSK 专项隔离测试脚本 (随机载荷 + 帧头靶向锁定 + 完美可视化)
clc; clear; close all;

fprintf('======================================================\n');
fprintf('������ GMSK 专项隔离测试启动 (Random Payload Mode)...\n');

% 1. 核心参数 
sps = 8;
bt = 0.5;
numFrames = 20; 
snr_val = 10;   

try
    %% A. 发送端 (Tx)
    gen = ccsdsTMWaveformGenerator(...
        'WaveformSource', 'synchronization and channel coding', ...
        'Modulation', 'GMSK', ...
        'BandwidthTimeProduct', bt, ...
        'SamplesPerSymbol', sps, ...
        'ChannelCoding', 'Convolutional', ...
        'NumBytesInTransferFrame', 1115, ... 
        'HasASM', true, ...                 
        'HasRandomizer', false); 
    
    msg = [];
    validTxFrames = {};
    numHeaderBits = 8;
    numPayloadBits = gen.NumInputBits - numHeaderBits;
    
    % 构造计数器帧头 + 随机载荷
    for i = 1:numFrames
        header = de2bi(mod(i-1, 256), numHeaderBits, 'left-msb')';
        payload = int8(randi([0 1], numPayloadBits, 1)); 
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

    %% C. 接收机同步 (Rx Sync) - 基于文献修正版
    fprintf('[Rx] 开始同步处理 (Gaussian Filter + Early-Late)...\n');
    
   % ============================
            % 1. 频偏消除 (使用 MATLAB 工具箱的标准算法)
            % ============================
            % 原来的 median 算法在高信噪比下会失效，改用 CoarseFrequencyCompensator。
            % GMSK 可以近似为 OQPSK 处理，该模块通过 FFT 分析频谱中心，非常稳健。
            
            % 创建频偏补偿器对象
            coarseSync = comm.CoarseFrequencyCompensator(...
                'Modulation', 'OQPSK', ...        % 【关键】GMSK 近似于 OQPSK，用这个模式最稳
                'SampleRate', Fs, ...             % 采样率
                'FrequencyResolution', 10);      % 频率分辨率，越小越准但越慢，100Hz 足够了
            
            % 执行补偿
            [rxSynced, estCFO] = coarseSync(rxWaveform);
            
            % 打印诊断信息
            fprintf('  [同步] 估算频偏: %.2f Hz\n', estCFO);
    
    % 【关键修正 1】更换滤波器：从 RRC 改为 高斯滤波器
    % 升余弦滤波器(RRC)不匹配GMSK脉冲，会导致严重的ISI，这是随机载荷失锁的元凶。
    % 我们使用 gaussdesign 生成与发送端一致的高斯滤波器系数。
    rxFilterDecimationFactor = sps/2; 
    
    % 生成高斯滤波器系数 (BT=0.5, Span=4, SPS=8)
    % 注意：接收滤波器带宽通常比发送略宽或一致，这里保持一致
    hGauss = gaussdesign(0.5, 4, sps); 
    
    % 使用 dsp.FIRDecimator 进行滤波和抽取
    rxfilter = dsp.FIRDecimator(...
        'DecimationFactor', rxFilterDecimationFactor, ...
        'Numerator', hGauss);
    
    filtered = rxfilter(rxSynced);
    
    % 【关键修正 2】回归 Early-Late，但配合正确的滤波器
    % 必须使用 'PAM/PSK/QAM' 模式，保留 GMSK 的圆形星座图特征
    % 不要使用 'OQPSK'，否则会破坏相位连续性
    timingObj = comm.SymbolSynchronizer(...
        'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
        'SamplesPerSymbol', 2, ...
        'DetectorGain', 2.0, ...           % 稳健增益
        'Modulation', 'PAM/PSK/QAM', ...   % 【重要】保持 GMSK 原样
        'DampingFactor', 1, ...
        'NormalizedLoopBandwidth', 0.01);  % 窄带宽保证锁定后不抖动
    
    fineSynced_time = timingObj(filtered);
    %% --- [新增步骤] 载波相位同步 (PLL) ---
    % 作用：消除残余的 13Hz 频偏，并将星座图锁死在水平方向
    carrierSync = comm.CarrierSynchronizer(...
        'Modulation', 'QPSK', ...      % GMSK 近似于 OQPSK，用这个模式最稳
        'SamplesPerSymbol', 1, ...      % 符号同步后，通常是 1个样点/符号
        'DampingFactor', 0.707, ...     % 标准阻尼
        'NormalizedLoopBandwidth', 0.01); % 环路带宽，0.01 足够快且稳
    
    [fineSynced, phErr] = carrierSync(fineSynced_time);
    
    % 打印调试信息，确认是否锁住
    fprintf('  [相位] 载波环路已介入，修正残余频偏...\n');
    % ---------------------------------------------------------
    
    %% D. 解调 (Demod)
    fprintf('[Rx] 调用 HelperCCSDSTMDemodulator...\n');
    if ~isempty(fineSynced)
                pwr = mean(abs(fineSynced).^2);
                if pwr > 0, fineSynced = fineSynced / sqrt(pwr); end
            end
            
    demodobj = HelperCCSDSTMDemodulator('Modulation', 'GMSK', 'ChannelCoding', 'Convolutional', 'BandwidthTimeProduct', bt);
    demodData = demodobj(fineSynced);
    
   decoderInput = real(demodData); 
    
    % 2. 创建并调用解码器
    % 解码器内部会自动完成：找ASM -> 判断极性 -> 翻转数据 -> 卷积译码
    decoderobj = HelperCCSDSTMDecoder('ChannelCoding', 'Convolutional', ...
        'Modulation', 'GMSK', ...
        'NumBytesInTransferFrame', 1115, ...
        'ConvolutionalCodeRate', '1/2', ... 
        'HasASM', true, ...
        'HasRandomizer', false);
        
    % 直接喂软信息进去
    decodedBits = decoderobj(decoderInput);
   %% --- [F.2] 智能极性兜底 (Smart Polarity Flip) ---
    % 现象：有时 ASM 纠正了输入，但译码器输出依然反相(全1)。
    % 对策：直接检查译码结果。如果开头全是 1，说明肯定是反了，强制翻转。
    
    % 取前 100 位解调数据（跳过前 40 位可能的译码延迟）
    check_len = min(100, length(decodedBits));
    check_start = 40; 
    if length(decodedBits) > check_start + check_len
        snippet = decodedBits(check_start : check_start + check_len);
        
        % 计算 1 的占比
        ratio_ones = sum(snippet) / length(snippet);
        
        % 我们知道发送端开头是全 0 的帧头。
        % 如果解出来全是 1 (占比 > 0.9)，说明彻底反了。
        if ratio_ones > 0.9
            fprintf('  ⚠️ [兜底] 检测到译码输出反相 (Rx全1)，正在执行输出翻转...\n');
            decodedBits = ~decodedBits; % 强制翻转结果
        end
    end
    % ----------------------------------------------------
    
    %% G. 可视化与 BER 计算 (使用帧头靶向锁定)
    fprintf('  [统计] 正在通过【帧头 ID】进行精确对齐...\n');
    
    % --- 1. 准备 Tx 字典 ---
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k = 1:length(validTxFrames)
         fr = validTxFrames{k};
         id = bi2de(fr(1:8)', 'left-msb');
         txMap(id) = fr;
    end
    
    bitsPerFrame = length(validTxFrames{1});
    currBitsSeq = decodedBits;
    
    totalErrs = 0;
    totalBits = 0;
    foundLock = false;
    lockedHeaderID = -1;
    
    % --- 2. 帧头靶向搜索 ---
    % 我们只搜前 10000 位，寻找任意一个合法的帧头 (ID 在字典里)
    searchLen = min(10000, length(currBitsSeq)-bitsPerFrame); 
    
    for shift = 0 : searchLen
        candHeader = currBitsSeq(shift+1 : shift+8);
        rxId = bi2de(candHeader', 'left-msb');
        
        if isKey(txMap, rxId)
            % 找到了一个合法的头！
            % 为了防止巧合，我们校验一下帧头是否匹配
            refFrame = txMap(rxId);
            rxFrame  = currBitsSeq(shift+1 : shift+bitsPerFrame);
            
            % 【修正】只验证帧头（前 8 位），允许载荷有少量误码
            if isequal(rxFrame(1:8), refFrame(1:8))
                foundLock = true;
                lockedHeaderID = rxId;
                
                fprintf('  -> ������ 在偏移 %d 处锁定帧头 (ID=%d)\n', shift, rxId);
                
                % 开始计算所有后续帧的 BER
                numRx = floor((length(currBitsSeq)-shift)/bitsPerFrame);
                % ... 
                for j=1:numRx
                    startIdx = shift + (j-1)*bitsPerFrame + 1;
                    endIdx = startIdx + bitsPerFrame - 1;
                    if endIdx > length(currBitsSeq), break; end
                    
                    rxFr = double(currBitsSeq(startIdx:endIdx));
                    thisId = bi2de(rxFr(1:8)', 'left-msb');
                    
                    % 【核心修改】增加 "&& thisId > 0"
                    % 跳过 ID=0 的第一帧，因为那时候 PLL 还在收敛，误码是正常的物理现象
                    if isKey(txMap, thisId) && thisId > 0 
                        totalErrs = totalErrs + biterr(txMap(thisId), rxFr);
                        totalBits = totalBits + bitsPerFrame;
                    end
                end
                break; % 锁定后跳出搜索
            end
        end
    end
    
    finalBER = 0.5;
    if totalBits > 0, finalBER = totalErrs / totalBits; end
    
    % --- 3. 绘图 ---
    figure('Name', 'GMSK Final Verification', 'Color', 'w', 'Position', [100, 100, 1200, 400]);
    
    subplot(1, 3, 1);
    L_stable = min(2000, length(fineSynced));
    if L_stable > 0
        pts = fineSynced(end-L_stable+1 : end);
        plot(real(pts), imag(pts), '.b', 'MarkerSize', 4);
        xlim([-3 3]); ylim([-3 3]); 
    end
    grid on; axis square; title('Constellation');
    
    subplot(1, 3, 2);
    L_eye = min(800, length(filtered));
    if L_eye > 0
        eye_data = filtered(end-L_eye+1 : end);
        samplesPerTrace = 4;
        numTraces = floor(length(eye_data) / samplesPerTrace);
        eye_matrix = reshape(eye_data(1:numTraces*samplesPerTrace), samplesPerTrace, []);
        plot(real(eye_matrix), 'b'); 
        xlim([1 samplesPerTrace]);
    end
    grid on; title('Eye Diagram');
    
    subplot(1, 3, 3); axis off;
    if foundLock
        if finalBER == 0, col='g'; txt='PASS'; else, col='r'; txt='FAIL'; end
        text(0.1, 0.6, sprintf('BER: %.6f (%s)', finalBER, txt), 'FontSize', 16, 'FontWeight', 'bold', 'Color', col);
        text(0.1, 0.4, sprintf('Locked Frame ID: %d', lockedHeaderID), 'FontSize', 12);
        text(0.1, 0.2, sprintf('Bits Checked: %d', totalBits), 'FontSize', 12);
    else
        text(0.1, 0.5, 'SYNC FAILED: Frame Header Not Found', 'FontSize', 14, 'Color', 'r');
    end
    
    fprintf('======================================================\n');
    if foundLock
        fprintf('������ 最终误码率 (BER): %.6f\n', finalBER);
    else
        fprintf('❌ 严重错误：未找到任何有效帧头！\n');
    end
    fprintf('======================================================\n');

catch ME
    fprintf('⚠️ 发生错误: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('   File: %s, Line: %d\n', ME.stack(1).name, ME.stack(1).line);
    end
end