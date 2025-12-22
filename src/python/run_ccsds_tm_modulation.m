function json_str = run_ccsds_tm_modulation(paramsJson)
    % run_ccsds_tm_modulation 
    % 发送端：智能切换 FACM/TM 模式
    % 接收端：仿照 CCSDS TM 官方例程构建同步链路
    
    tStart = tic;
    try
        %% 1. 解析参数
        if nargin < 1 || isempty(paramsJson)
            error('No parameters received');
        end
        opt = jsondecode(paramsJson);
        
        % 基础参数转换
        makeNum = @(f) str2double(strrep(string(f), ',', '')); 
        if ischar(opt.symbolRate), fSym = makeNum(opt.symbolRate); else, fSym = double(opt.symbolRate); end
        if ischar(opt.sps), sps = makeNum(opt.sps); else, sps = double(opt.sps); end
        
        hasRandomizer = false; if isfield(opt, 'hasRandomizer'), hasRandomizer = opt.hasRandomizer; end
        hasASM = false; if isfield(opt, 'hasASM'), hasASM = opt.hasASM; end

        %% 2. 发送端：智能路由 (Smart Routing)
        % 目的：为了生成波形。因为 TM 模式无法生成 APSK，所以如果是 APSK，我们必须用 FACM 生成。
        
        args = {
            'SamplesPerSymbol', sps, ...
            'HasRandomizer', hasRandomizer, ...
            'HasASM', hasASM
        };
        
        isAPSK = contains(opt.modType, 'APSK');
        
        if isAPSK
            % --- 分支 A: APSK (使用 FACM 生成) ---
            % 即使我们想测试 TM 接收机，发送端也得先能发出 APSK 信号才行
            if isfield(opt, 'acmFormat')
                acmFmt = double(opt.acmFormat);
            else
                acmFmt = 14; 
            end
            args = [args, { ...
                'WaveformSource', 'flexible advanced coding and modulation', ...
                'ACMFormat', acmFmt, ...
                'NumBytesInTransferFrame', 1115, ... % FACM 帧长
                'PulseShapingFilter', 'Root Raised Cosine' ... % 必须开滤波器
            }];
            % 这里的 Rolloff 默认是 0.35
            rolloff = 0.35;
        else
            % --- 分支 B: PSK/QAM (使用 TM 生成) ---
            args = [args, {'WaveformSource', 'synchronization and channel coding'}];
            args = [args, {'NumBytesInTransferFrame', 1115}]; % TM 帧长
            
            modStr = string(opt.modType);
            args = [args, {'Modulation', modStr}];
            
            % 编码参数
            if isfield(opt, 'channelCoding')
                codeStr = lower(string(opt.channelCoding));
            else
                codeStr = 'none';
            end
            args = [args, {'ChannelCoding', codeStr}];
            
            % 滚降系数处理
            if isfield(opt, 'RolloffFactor')
                rolloff = double(opt.RolloffFactor);
            else
                rolloff = 0.5; % TM 标准常用 0.5，FACM 常用 0.35
            end
            args = [args, {'RolloffFactor', rolloff}];
            
            % 针对 BPSK/QPSK 等补充参数
            switch modStr
                case {'BPSK', 'QPSK', '8PSK', 'OQPSK'}
                    args = [args, {'FilterSpanInSymbols', 10}];
            end
             
             % 补充 LDPC/Turbo 参数 (略，保持你原有的逻辑)
             if contains(codeStr, {'turbo', 'ldpc'}) && isfield(opt, 'CodeRate')
                 args = [args, {'CodeRate', string(opt.CodeRate)}];
             end
        end
        
        % 初始化生成器
        tmWaveGen = ccsdsTMWaveformGenerator(args{:});
        
        %% 3. 生成数据与波形
        Fs = fSym * sps;
        
        % 动态获取输入比特长度
        bitsPerFrame = tmWaveGen.NumInputBits;
        
        % 定义帧头 (用于可视化检查)
        numHeaderBits = 8; % 使用 32 位 ASM 作为简单的视觉标记
        numMessagesInBlock = 2^numHeaderBits;
        numPayloadBits = bitsPerFrame - numHeaderBits;
        
        
        % 生成 4 帧数据
        numFrames = 4;
        msg = [];
        
        for i = 1:numFrames
                % 简单的计数器头
                header = de2bi(mod(i-1, numMessagesInBlock), numHeaderBits, 'left-msb')'; 
                payload = int8(randi([0 1], numPayloadBits, 1));
                msg = [msg; header; payload];
        end
        % 生成发送波形
        txWaveform = tmWaveGen(msg);
        
        %% 4. 信道损伤 (Channel Impairments)
         % ==========================================
        % 1. 引入 载波频率偏移 (CFO)
        % ==========================================
        % 获取用户输入的频偏，默认为 0
        if isfield(opt, 'cfo')
            cfo_val = double(opt.cfo);
        else
            cfo_val = 0; 
        end
        % 相位偏移
        if isfield(opt, 'phaseOffset')
            phase_val = double(opt.phaseOffset) * (pi/180); % 前端输入角度，转弧度
        else
            %phase_val = 0; 
             phase_val = pi/8;      % 固定 pi/8
        end
        if cfo_val ~= 0 || phase_val ~= 0
            % 创建频偏对象 (使用 comm.PhaseFrequencyOffset)
            pfo = comm.PhaseFrequencyOffset(...
                'FrequencyOffset', cfo_val, ...
                'PhaseOffset', phase_val, ...
                'SampleRate', Fs);
            
            % 应用频偏
            txWithCFO = pfo(txWaveform);
        else
            txWithCFO = txWaveform;
        end
        
        % ==========================================
        % 2. 引入 定时偏差 (Timing Delay)
        % ==========================================
        % 获取用户输入的延时（可以是小数，例如 0.5 个采样点）
        if isfield(opt, 'delay')
            delay_val = double(opt.delay);
        else
            delay_val = 0; 
        end
        
        if delay_val ~= 0
            % 创建分数倍延时对象 (使用 dsp.VariableFractionalDelay)
            % 它可以模拟非整数倍的采样延迟，非常真实
            varDelay = dsp.VariableFractionalDelay(...
                'InterpolationMethod', 'Farrow');
            
            % 应用延时 (注意：varDelay需要列向量处理逻辑，有时需要重置)
            % 这里简单处理：
            txWithDelay = varDelay(txWithCFO, delay_val);
        else
            txWithDelay = txWithCFO;
        end
        
        % ==========================================
        % 3. 添加 高斯白噪声 (AWGN)
        % ==========================================
        if isfield(opt, 'snr')
            snr_val = double(opt.snr);
        else
            snr_val = 100; % 默认极其纯净
        end
        
        % 最终的接收信号 rxWaveform
        rxWaveform = awgn(txWithDelay, snr_val, 'measured');
        
        %% 5. 接收机处理 
        % -------------------------------------------------------------
        % 修复版：针对 GMSK 增加"保底逻辑"，防止同步器无法锁定导致空图
        % -------------------------------------------------------------
        
        modStr = string(opt.modType);
        
        % --- A. 粗频偏同步 (Coarse Frequency Synchronization) ---
        if contains(modStr, 'BPSK')
            coarseMod = 'BPSK';
        elseif contains(modStr, '8PSK')
            coarseMod = '8PSK';
        elseif contains(modStr, 'QPSK') || contains(modStr, 'OQPSK')
            coarseMod = 'QPSK';
        else
            coarseMod = 'QAM'; 
        end
        
        coarseFreqSync = comm.CoarseFrequencyCompensator( ...
            'Modulation', coarseMod, ... 
            'SampleRate', Fs, ...
            'FrequencyResolution', 1e3); 
        
        % GMSK 跳过粗频偏，防止误判
        if contains(modStr, 'GMSK')
            coarseSynced = rxWaveform;
        else
            coarseSynced = coarseFreqSync(rxWaveform);
        end
        
        % --- B. 接收滤波 (Rx Filter) ---
        rxFilterDecimationFactor = sps/2;
        
        rxfilter = comm.RaisedCosineReceiveFilter( ...
            'RolloffFactor', rolloff, ... 
            'InputSamplesPerSymbol', sps, ...
            'DecimationFactor', rxFilterDecimationFactor); 
        
        b = coeffs(rxfilter);
        rxfilter.Gain = sum(b.Numerator);
        
        filtered = rxfilter(coarseSynced);
        
        % --- C. 符号定时同步 (Symbol Timing Synchronization) ---
        
        if contains(modStr, 'GMSK')
            % 【GMSK 关键修复】
            % Gardner 算法无法锁定恒包络的 GMSK 信号，会导致输出为空。
            % 策略：对于 GMSK，直接进行盲下采样 (Blind Decimation)。
            % 我们知道经过滤波后是 2 SPS (因为 DecimationFactor=sps/2)
            % 所以每隔 2 个点取一个即可得到 1 SPS。
            
            % 简单的中心采样
            TimeSynced = filtered(1:2:end); 
            
        else
            % 非 GMSK 模式：正常使用 Gardner
            if contains(modStr, 'OQPSK')
                SyncMod = 'OQPSK';
            else
                SyncMod = 'PAM/PSK/QAM'; 
            end
            
            Kp = 1/(pi*(1-((rolloff^2)/4)))*cos(pi*rolloff/2);
            
            symsyncobj = comm.SymbolSynchronizer( ...
                'TimingErrorDetector', 'Gardner (non-data-aided)', ...
                'SamplesPerSymbol', sps/rxFilterDecimationFactor, ...
                'DetectorGain', Kp, ...
                'Modulation', SyncMod, ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', 0.01);
                
            TimeSynced = symsyncobj(filtered);
        end
        
        % --- D. 精细频偏与相位跟踪 (Fine Frequency Synchronization) ---
        
        if contains(modStr, 'GMSK')
            % 【GMSK 关键修复】
            % GMSK 自带旋转相位，不能用 QPSK 的 PLL 去锁，否则会破坏数据。
            % 策略：直接透传。
            fineSynced = TimeSynced;
            
        else
            % 非 GMSK 模式：正常处理
            fineMod = modStr; 
            if contains(modStr, 'OQPSK'), fineMod = 'QPSK'; end
            if contains(modStr, 'APSK'), fineMod = 'QAM'; end
            
            fineFreqSync = comm.CarrierSynchronizer( ...
                'Modulation', fineMod, ... 
                'SamplesPerSymbol', 1, ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', 0.01);
            
            fineSynced = fineFreqSync(TimeSynced);
        end
        
        %% 6. 数据提取与可视化
        
        %% 6. 数据提取与可视化
        
        % 1. 频谱图
        [Pxx_rx, f_axis] = pwelch(rxWaveform, [], [], 1024, Fs, 'centered');
        Pxx_rx_dB = 10*log10(Pxx_rx);
        [Pxx_tx, ~] = pwelch(txWaveform, [], [], 1024, Fs, 'centered');
        Pxx_tx_dB = 10*log10(Pxx_tx);
        
        % 2. 星座图抽取
        L_max = 1000;
        
        % --- A. 修复前 (Raw) ---
        raw_idx = 1 : sps : length(rxWaveform);
        raw_pts = rxWaveform(raw_idx);
        raw_pts = raw_pts(1:min(L_max, end));
        
        % 归一化 Raw 数据
        avgPowerRaw = mean(abs(raw_pts).^2);
        if avgPowerRaw > 0
            raw_pts = raw_pts / sqrt(avgPowerRaw);
        end
        
        % --- B. 修复后 (Synced) ---
        if isempty(fineSynced)
             synced_pts = complex(0); 
        else
             synced_data = fineSynced(end-min(L_max, length(fineSynced))+1 : end);
             
             % 1. GMSK 去旋转 (Derotation)
             if contains(modStr, 'GMSK')
               synced_data = synced_data;
             end

             % 2. 【关键修复】强制功率归一化 (Power Normalization)
             % 无论之前的滤波器增益是多少，这里统一压回单位圆
             avgPowerSynced = mean(abs(synced_data).^2);
             if avgPowerSynced > 0
                 scaleFactor = 1 / sqrt(avgPowerSynced);
                 synced_pts = synced_data * scaleFactor;
             else
                 synced_pts = synced_data;
             end
             
             % 3. 相位对齐 (让星座图转正，方便观察)
             if ~isempty(synced_pts) && avgPowerSynced > 0
                 % 使用四次方去旋转算法找主轴
                 phase_bias = angle(mean(synced_pts.^4))/4;
                 synced_pts = synced_pts * exp(-1j * phase_bias);
                 
                 % 再次微调：GMSK 有时需要额外转 45 度看起来才像 QPSK
                 if contains(modStr, 'GMSK')
                     % 这一步可选，看视觉效果决定
                     % synced_pts = synced_pts * exp(-1j * pi/4); 
                 end
             end
        end

        % 3. 构造 JSON
        makeRow = @(x) reshape(x, 1, []);
        result = struct();
        result.success = true;
        result.info = sprintf("Generated: %s via %s (Rx Chain: TM Standard)", opt.modType, ifelse(isAPSK,'FACM','TM'));
        
        result.spectrum = struct('f', makeRow(f_axis), 'p_rx', makeRow(Pxx_rx_dB), 'p_tx', makeRow(Pxx_tx_dB));
        result.constellation_raw = struct('i', makeRow(real(raw_pts)), 'q', makeRow(imag(raw_pts)));
        result.constellation_synced = struct('i', makeRow(real(synced_pts)), 'q', makeRow(imag(synced_pts)));
        
        % 统计信息
        result.stats = struct('Fs', Fs, 'CodeRate', 0, 'ElapsedTime', toc(tStart));
        
        json_str = jsonencode(result);
        
    catch ME
        err = struct('success', false, 'error', ME.message, 'stack', ME.stack(1).name, 'line', ME.stack(1).line);
        json_str = jsonencode(err);
    end
end

% 简单的辅助函数
function out = ifelse(condition, trueVal, falseVal)
    if condition
        out = trueVal;
    else
        out = falseVal;
    end
end