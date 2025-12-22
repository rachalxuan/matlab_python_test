function json_str = run_ccsds_FACM_modulation(paramsJson)
    % run_ccsds_tm_modulation CCSDS 发送端仿真核心入口
    tStart = tic;
    try
        %% 1. 解析前端参数
        if nargin < 1 || isempty(paramsJson)
            error('No parameters received');
        end
        opt = jsondecode(paramsJson);
        
        % 基础数值转换 (防止逗号报错)
        makeNum = @(f) str2double(strrep(string(f), ',', '')); 
        if ischar(opt.symbolRate), fSym = makeNum(opt.symbolRate); else, fSym = double(opt.symbolRate); end
        if ischar(opt.sps), sps = makeNum(opt.sps); else, sps = double(opt.sps); end
        
        % 布尔值处理
        hasRandomizer = false; if isfield(opt, 'hasRandomizer'), hasRandomizer = opt.hasRandomizer; end
        hasASM = false; if isfield(opt, 'hasASM'), hasASM = opt.hasASM; end
        hasPilots = false; if isfield(opt, 'hasPilots'), hasPilots = opt.hasPilots; end

        %% 2. 构建配置结构体
        cfg = struct();
        cfg.SamplesPerSymbol = sps;
        cfg.NumBytesInTransferFrame = 1115;
        
        if isfield(opt, 'RolloffFactor'), cfg.RolloffFactor = double(opt.RolloffFactor);
        else, cfg.RolloffFactor = 0.35; end
        
        cfg.FilterSpanInSymbols = 10;
        cfg.ScramblingCodeNumber = 1;
        cfg.HasRandomizer = hasRandomizer;
        cfg.HasASM = hasASM;
        cfg.PulseShapingFilter = 'Root Raised Cosine';
        
        % 确定 ACM 格式 (统一 FACM 模式)
        modStr = string(opt.modType);
        if contains(modStr, 'QPSK')
            defaultFmt = 1; 
        elseif contains(modStr, '8PSK')
            defaultFmt = 7;
        elseif contains(modStr, '16APSK')
            defaultFmt = 14; 
        elseif contains(modStr, '32APSK')
            defaultFmt = 19;
        else
            defaultFmt = 14; 
        end
        
        if isfield(opt, 'acmFormat')
            cfg.ACMFormat = double(opt.acmFormat);
        else
            cfg.ACMFormat = defaultFmt;
        end
        
        % 导频设置
        cfg.HasPilots = hasPilots; 

        % 仿真参数
        simParams = struct();
        simParams.SymbolRate = fSym;
        simParams.SPS = sps;
        
        % SNR 转换
        if isfield(opt, 'snr'), snr_val = double(opt.snr); else, snr_val = 20; end
        simParams.EsNodB = snr_val + 10*log10(sps);
        
        % 频偏
        if isfield(opt, 'cfo'), simParams.CFO = double(opt.cfo); else, simParams.CFO = 0; end
        simParams.DisableCFO = (simParams.CFO == 0);
        
        % 关闭复杂损伤
        simParams.SRO = 0; 
        simParams.DisableSRO = true; 
        simParams.PeakDoppler = 0;
        simParams.DopplerRate = 0;
        simParams.DisableDoppler = true;
        simParams.DisablePhaseNoise = true; 
        simParams.DisableRFImpairments = false; 
        
        simParams.InitalSyncFrames = 15;  % 前 15 帧用于让接收机收敛（热身）
        simParams.NumFramesForBER = 5;    % 后 5 帧用于提取数据画图
        simParams.NumPLFrames = simParams.InitalSyncFrames + simParams.NumFramesForBER;
    
        simParams.AttenuationFactor = 1;

        %% 3. 调用 Helper 生成波形
        [bits, txWaveform, rxIn, phyParams, rxParams] = HelperCCSDSFACMRxInputGenerate(cfg, simParams);
        
        %% 4. 补充损伤
        if isfield(opt, 'delay') && double(opt.delay) ~= 0
            delay_val = double(opt.delay);
            varDelay = dsp.VariableFractionalDelay('InterpolationMethod', 'Farrow');
            rxWaveform = varDelay(rxIn, delay_val);
        else
            rxWaveform = rxIn;
        end
        
        if isfield(opt, 'phaseOffset') && double(opt.phaseOffset) ~= 0
            phase_deg = double(opt.phaseOffset);
            rxWaveform = rxWaveform .* exp(1j * deg2rad(phase_deg));
        end

        Fs = fSym * sps;

       %% 5. 接收机配置
        
        % 创建SRRC接受滤波器
        rxFilterDecimationFactor = 1; 
        rrcfilt = comm.RaisedCosineReceiveFilter( ...
            'RolloffFactor', cfg.RolloffFactor, ...
            'FilterSpanInSymbols', cfg.FilterSpanInSymbols, ...
            'InputSamplesPerSymbol', sps, ...
            'DecimationFactor', rxFilterDecimationFactor);
        b = coeffs(rrcfilt);

        % 根据标准[1]第6节，对于|f| < fN(1-alpha)，|H(f)| = 1
        rrcfilt.Gain = sum(b.Numerator);

        % 创建符号定时同步系统对象 `comm.SymbolSynchronizer`
        Kp = 1/(pi*(1-((cfg.RolloffFactor^2)/4)))*sin(pi*cfg.RolloffFactor/2);
        
        symsyncobj = comm.SymbolSynchronizer( ...
            'DampingFactor', 1/sqrt(2), ...
            'DetectorGain', Kp, ...
            'TimingErrorDetector', 'Gardner (non-data-aided)', ...
            'Modulation', 'PAM/PSK/QAM', ...
            'NormalizedLoopBandwidth', 0.005, ... % 官方设得很小以保证稳定
            'SamplesPerSymbol', sps);

        % 初始FLL
        fll = HelperCCSDSFACMFLL('SampleRate', fSym, 'K1', 0.17, 'K2', 0);
       

        %% 6. 同步与数据恢复
        % =========================================================================
        % A. RRC 接收滤波器 (匹配滤波)
        % 先对整个波形滤波
        filteredRx = rrcfilt(rxWaveform);

        % B. 符号定时同步 (Gardner Algorithm) 
        % 执行同步，输出 1 SPS 的符号流 
        [syncsym, ~] = symsyncobj(filteredRx);

        
        %  帧同步 (Frame Synchronization)
        % =========================================================================
        % 寻找帧头 (ASM) 位置，作为后续处理的基准
        syncidx = HelperCCSDSFACMFrameSync(syncsym, rxParams.RefFM);

        % 准备输出容器
        rx_final = []; 
        
        if isempty(syncidx)
            % 如果找不到帧头，无法进行高级处理，回退到仅符号同步的数据
            rx_final = syncsym;
        else
            % =====================================================================
            % 步骤 3: 逐帧处理循环 (Frame-by-Frame Loop)
            % 包含: FLL -> Fine Freq -> Phase Recovery -> DAGC
            % =====================================================================
            
            % 初始化官方例程需要的对象
            
            fineCFOSync = comm.PhaseFrequencyOffset('SampleRate', fSym);
            
            % 状态变量初始化
            plFrameSize = rxParams.plFrameSize; % 每帧符号数
            G = 1; % DAGC 初始增益
            SNREstVec = zeros(6,1); % SNR 平滑缓冲区
            idxTemp = 0;
            frameIndex = 1;
            
            % 从第一个找到的帧头开始，一帧一帧往后切
            currentIdx = syncidx(1);
            
            while (currentIdx + plFrameSize - 1) <= length(syncsym)
                
                % --- A. 提取当前帧 ---
                oneFrame = syncsym(currentIdx : (currentIdx + plFrameSize - 1));
                
                % --- B. 锁频环 (FLL) ---
                % 跟踪并消除粗频偏和多普勒
                [fllOut, ~] = fll(oneFrame);
                
                % --- C. 精细频偏估计 (Fine CFO) ---
                % 利用帧头 (Frame Marker, 前256个符号) 计算残留频偏
                cfoEst = HelperCCSDSFACMFMFrequencyEstimate(fllOut(1:256), rxParams.RefFM, fSym);
                
                % 补偿精细频偏
                fineCFOSync.FrequencyOffset = -cfoEst;
                fqysyncedFM = fineCFOSync(fllOut);
                
                % --- D. 导频相位恢复 (Phase Recovery) ---
                if cfg.HasPilots
                    try
                        % 利用导频消除相位旋转
                        % 输出: frameDescriptor + payload (去除了导频的纯数据)
                        [noPilotsSym, frameDescriptor] = HelperCCSDSFACMPhaseRecovery(fqysyncedFM, rxParams.PilotSeq, rxParams.RefFM);
                        agcIn = [frameDescriptor; noPilotsSym];
                    catch
                        % 失败回退
                        agcIn = fqysyncedFM;
                    end
                else
                    % 不开导频时，跳过相位恢复
                    agcIn = fqysyncedFM;
                end
                
                % --- E. 信噪比估计 (SNR Estimation) ---
                currentSNREst = HelperCCSDSFACMSNREstimate(fqysyncedFM(1:256), rxParams.RefFM);
                SNREstVec(idxTemp + 1) = currentSNREst;
                
                % 计算平均 SNR
                if frameIndex < 6
                    finalSNREst = mean(SNREstVec(1:frameIndex));
                else
                    finalSNREst = mean(SNREstVec);
                end
                idxTemp = mod(idxTemp + 1, 6);
                
                % --- F. 数字自动增益控制 (DAGC) ---
                % 这一步非常重要！它把幅度归一化到 1，保证星座图大小标准
                [agcRecovered, G] = HelperDigitalAutomaticGainControl(agcIn, finalSNREst, G);
                
                % --- G. 收集结果 ---
                rx_final = [rx_final; agcRecovered];
                
                % 移动到下一帧
                currentIdx = currentIdx + plFrameSize;
                frameIndex = frameIndex + 1;
            end
            
            % 如果循环没跑进去（比如数据不够一帧），回退
            if isempty(rx_final)
                rx_final = syncsym;
            end
        end

%% 6. 数据提取与输出 (Output)
        L_max = 1000;
        
        % 1. 修复前 (Raw) - 展示带损伤的原始波形
        % 下采样以减少数据量，展示轨迹
        raw_idx = 1 : sps : length(rxWaveform);
        const_raw_pts = rxWaveform(raw_idx);
        raw_pts_vis = const_raw_pts(1:min(L_max, end));
        
        % 2. 修复后 (Synced) - 已经是完美的符号流
        synced_pts_vis = rx_final(1:min(L_max, end));
        
        % 3. 归一化 (Raw 数据需要归一化以便和 Synced 同比例对比)
        % Synced 数据经过 DAGC 已经是归一化的了，不需要再动
        scale_raw = 1 / sqrt(mean(abs(const_raw_pts).^2));
        if isinf(scale_raw), scale_raw = 1; end
        
        const_raw_i = real(raw_pts_vis * scale_raw);
        const_raw_q = imag(raw_pts_vis * scale_raw);
        
        const_sync_i = real(synced_pts_vis);
        const_sync_q = imag(synced_pts_vis);
        
        % 4. 频谱
        [Pxx_tx, ~] = pwelch(txWaveform, [], [], 1024, Fs, 'centered');
        Pxx_tx_dB = 10*log10(Pxx_tx);

        [Pxx, f_axis] = pwelch(rxWaveform, [], [], 1024, Fs, 'centered');
        Pxx_rx_dB = 10*log10(Pxx);
        makeRow = @(x) reshape(x, 1, []);

        

        % 5. 构造 JSON
        result = struct();
        result.success = true;
        result.info = sprintf("Generated: %s (FACM Standard)", opt.modType);
        
        result.spectrum = struct(...
            'f', makeRow(f_axis), ...
            'p_rx', makeRow(Pxx_rx_dB), ... % 接收功率谱
            'p_tx', makeRow(Pxx_tx_dB) ...  % 发送功率谱
        );
        result.constellation_raw = struct('i', makeRow(const_raw_i), 'q', makeRow(const_raw_q));
        result.constellation_synced = struct('i', makeRow(const_sync_i), 'q', makeRow(const_sync_q));
        
        try
            if exist('phyParams', 'var') && isfield(phyParams, 'ActualCodeRate')
                 codeRate = phyParams.ActualCodeRate;
            else
                 codeRate = 0;
            end
            result.stats = struct('Fs', Fs, 'CodeRate', codeRate, 'ElapsedTime', toc(tStart));
        catch
            result.stats = struct('Fs', Fs, 'CodeRate', 0, 'ElapsedTime', toc(tStart));
        end
        
        json_str = jsonencode(result);
        
    catch ME
        err = struct('success', false, 'error', ME.message, 'stack', ME.stack(1).name, 'line', ME.stack(1).line);
        json_str = jsonencode(err);
    end
end