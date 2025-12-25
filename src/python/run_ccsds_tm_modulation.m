function json_str = run_ccsds_tm_modulation(paramsJson)
    % run_ccsds_tm_modulation 
    % 【最终修复版】
    % 1. 解决 0.026 误码率：引入 5 帧“热身数据”，消除同步环路建立时的误差
    % 2. 解决 GMSK 0.5 误码率：ASM 自动极性纠正 + 优化 GMSK 同步策略
    
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

        %% 2. 发送端：智能路由
        args = {
            'SamplesPerSymbol', sps, ...
            'HasRandomizer', hasRandomizer, ...
            'HasASM', hasASM
        };
        
        isAPSK = contains(opt.modType, 'APSK');
        modStr = string(opt.modType);
        
        if isAPSK
            % --- 分支 A: APSK ---
            if isfield(opt, 'acmFormat'), acmFmt = double(opt.acmFormat); else, acmFmt = 14; end
            args = [args, { ...
                'WaveformSource', 'flexible advanced coding and modulation', ...
                'ACMFormat', acmFmt, ...
                'NumBytesInTransferFrame', 1115, ... 
                'PulseShapingFilter', 'Root Raised Cosine' ...
            }];
            rolloff = 0.35;
        else
            % --- 分支 B: PSK/QAM/GMSK ---
            args = [args, {'WaveformSource', 'synchronization and channel coding'}];
            args = [args, {'NumBytesInTransferFrame', 1115}];
            args = [args, {'Modulation', modStr}];
            
            if isfield(opt, 'channelCoding'), codeStr = lower(string(opt.channelCoding)); else, codeStr = 'none'; end
            args = [args, {'ChannelCoding', codeStr}];
            
            % 【参数修正】GMSK 不设置 RolloffFactor
            % 统一获取前端传来的系数 (默认0.5)
            if isfield(opt, 'RolloffFactor')
                rolloff = str2double(string(opt.RolloffFactor)); % 防止格式报错
            else
                rolloff = 0.5; 
            end
            btVal = 0.5;
        if isfield(opt, 'BandwidthTimeProduct')
            if ischar(opt.BandwidthTimeProduct) || isstring(opt.BandwidthTimeProduct)
                btVal = makeNum(opt.BandwidthTimeProduct);
            else
                btVal = double(opt.BandwidthTimeProduct);
            end
        end

            % 【关键修正】显式设置 BT 值
            if contains(modStr, 'GMSK')
                 % GMSK 使用 BandwidthTimeProduct 参数
                 args = [args, {'BandwidthTimeProduct', btVal}]; 
            else
                 % 其他调制使用 RolloffFactor
                 args = [args, {'RolloffFactor', rolloff}];
            end
            

            switch modStr
                case {'BPSK', 'QPSK', '8PSK', 'OQPSK'}
                    args = [args, {'FilterSpanInSymbols', 10}];
            end
             
             if contains(codeStr, {'turbo', 'ldpc'}) && isfield(opt, 'CodeRate')
                 args = [args, {'CodeRate', string(opt.CodeRate)}];
             end
        end
        
        % 初始化生成器
        tmWaveGen = ccsdsTMWaveformGenerator(args{:});
        
        if contains(modStr, 'GMSK')
            infoStruct = get(tmWaveGen);
            fprintf('[CHECK] 发送端 GMSK BT 值 = %.4f (目标是 0.5000)\n', infoStruct.BandwidthTimeProduct);
        end
        
        %% 3. 生成数据与波形 (含热身帧)
        Fs = fSym * sps;
        bitsPerFrame = tmWaveGen.NumInputBits;
        numHeaderBits = 8; 
        numPayloadBits = bitsPerFrame - numHeaderBits;
        
        % 【关键修改】增加 5 帧作为“热身”(Warm-up)，不计入 BER 统计
        numWarmUp = 5; 
        numRealFrames = 20; 
        totalFrames = numWarmUp + numRealFrames;
        
        msg = [];
        % 我们需要保留“有效帧”的副本用于 BER 对比
        validTxFrames = {}; 
        
        for i = 1:totalFrames
                header = de2bi(mod(i-1, 256), numHeaderBits, 'left-msb')'; 
                payload = int8(randi([0 1], numPayloadBits, 1));
                currentFrame = [header; payload];
                msg = [msg; currentFrame];
                
                % 只有热身之后的帧才算“有效帧”
                if i > numWarmUp
                    validTxFrames{end+1} = double(currentFrame);
                end
        end
        txWaveform = tmWaveGen(msg);
        
        %% 4. 信道损伤
        if isfield(opt, 'cfo'), cfo_val = double(opt.cfo); else, cfo_val = 0; end
        if isfield(opt, 'phaseOffset'), phase_val = double(opt.phaseOffset) * (pi/180); else, phase_val = 0; end
        
        if cfo_val ~= 0 || phase_val ~= 0
            pfo = comm.PhaseFrequencyOffset('FrequencyOffset', cfo_val, 'PhaseOffset', phase_val, 'SampleRate', Fs);
            txWithCFO = pfo(txWaveform);
        else
            txWithCFO = txWaveform;
        end
        
        if isfield(opt, 'delay'), delay_val = double(opt.delay); else, delay_val = 0; end
        if delay_val ~= 0
            varDelay = dsp.VariableFractionalDelay('InterpolationMethod', 'Farrow');
            txWithDelay = varDelay(txWithCFO, delay_val);
        else
            txWithDelay = txWithCFO;
        end
        
        if isfield(opt, 'snr'), snr_val = double(opt.snr); else, snr_val = 100; end
        rxWaveform = awgn(txWithDelay, snr_val, 'measured');
        
        %% 5. 接收机同步处理
        modStr = string(opt.modType);
        
        % A. 粗频偏同步
        if contains(modStr, 'BPSK'), coarseMod = 'BPSK';
        elseif contains(modStr, '8PSK'), coarseMod = '8PSK';
        elseif contains(modStr, 'QPSK') || contains(modStr, 'OQPSK'), coarseMod = 'QPSK';
        else, coarseMod = 'QAM'; end
        
        coarseFreqSync = comm.CoarseFrequencyCompensator( ...
            'Modulation', coarseMod, ... 
            'SampleRate', Fs, ...
            'FrequencyResolution', 1e3); 
        coarseSynced = coarseFreqSync(rxWaveform);
        
        % B. 接收滤波
        rxFilterDecimationFactor = sps/2;
        rxfilter = comm.RaisedCosineReceiveFilter( ...
            'RolloffFactor', rolloff, ... 
            'InputSamplesPerSymbol', sps, ...
            'DecimationFactor', rxFilterDecimationFactor); 
        
        b_coeffs = coeffs(rxfilter);
        rxfilter.Gain = sum(b_coeffs.Numerator);
        filtered = rxfilter(coarseSynced);
        
        % C. 符号定时同步
        if contains(modStr, 'OQPSK'), SyncMod = 'OQPSK'; else, SyncMod = 'PAM/PSK/QAM'; end
        Kp = 1/(pi*(1-((rolloff^2)/4)))*cos(pi*rolloff/2);
        
        symsyncobj = comm.SymbolSynchronizer( ...
            'TimingErrorDetector', 'Gardner (non-data-aided)', ...
            'SamplesPerSymbol', sps/rxFilterDecimationFactor, ...
            "DetectorGain",Kp, ...
            "Modulation",SyncMod, ...
            'DampingFactor', 1/sqrt(2), ...
            'NormalizedLoopBandwidth', 0.01);
        TimeSynced = symsyncobj(filtered);
        
        % D. 精细频偏 (GMSK 建议跳过此步或参数调宽，因为它不是 QPSK)
        fineMod = modStr; 
        if contains(modStr, 'OQPSK'), fineMod = 'QPSK'; 
        elseif contains(modStr, 'APSK'), fineMod = 'QAM';
        elseif contains(modStr, 'GMSK'), fineMod = 'SKIP'; end % GMSK 差分检测不需要 QPSK 锁相环
        
        if strcmp(fineMod, 'SKIP')
            fineSynced = TimeSynced; % GMSK 跳过 CarrierSync
        else
            fineFreqSync = comm.CarrierSynchronizer( ...
                'Modulation', fineMod, ... 
                'SamplesPerSymbol', 1, ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', 0.01);
            fineSynced = fineFreqSync(TimeSynced);
        end
        
       %% 6. 解调与误码率计算 (BER)
        berVal = -1;
        errorMsg = "";
        
        try
            % 0. 功率归一化
            if ~isempty(fineSynced)
                pwr = mean(abs(fineSynced).^2);
                if pwr > 0, fineSynced = fineSynced / sqrt(pwr); end
            end

            tmMod = char(modStr);
            if contains(tmMod,'GMSK'), tmMod='GMSK'; end
            
            if isfield(opt, 'channelCoding'), tmCode = char(opt.channelCoding); else, tmCode='none'; end
            if strcmpi(tmCode, 'none'), tmCode = 'Uncoded'; end
            
            isHelperSupported = ~contains(tmCode, {'Turbo', 'LDPC'}, 'IgnoreCase', true);

            if isHelperSupported
                % A. 创建解调器 (移除无效参数)
                demodobj = HelperCCSDSTMDemodulator('Modulation', tmMod, 'ChannelCoding', tmCode);
                
                % B. 解调
                demodData = demodobj(fineSynced);
                
                % ==========================================================
                % 【关键】ASM 极性/相位自动纠正 (Auto-Polarity Correction)
                % ==========================================================
                if hasASM && ~isempty(demodData)
                    asmBits = [0 0 0 1 1 0 1 0 1 1 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 1 1 1 0 1]';
                    asmBipolar = 2*double(asmBits) - 1;
                    chkLen = min(5000, length(demodData));
                    snippet = double(demodData(1:chkLen));
                    
                    max_norm = max(abs(xcorr(snippet, asmBipolar)));
                    max_inv  = max(abs(xcorr(snippet, -asmBipolar)));
                    
                    if max_inv > max_norm * 1.2
                         demodData = -1 * demodData; % 强制翻转
                    end
                end
                
                % C. 创建译码器
                decArgs = {'ChannelCoding', tmCode, 'Modulation', tmMod, ...
                           'NumBytesInTransferFrame', 1115, ...
                           'HasRandomizer', hasRandomizer, ...
                           'HasASM', hasASM};
                if contains(tmCode, 'Convolutional', 'IgnoreCase',true) && isfield(opt, 'ConvolutionalCodeRate')
                     rate = char(opt.ConvolutionalCodeRate); if ~strcmp(rate,'N/A'), decArgs=[decArgs, {'ConvolutionalCodeRate', rate}]; end
                end
                if isfield(opt, 'RSInterleavingDepth'), decArgs=[decArgs, {'RSInterleavingDepth', opt.RSInterleavingDepth}]; end
                
                decoderobj = HelperCCSDSTMDecoder(decArgs{:});
                
                % D. 译码
                decodedBits = decoderobj(demodData);
                
                % E. 计算 BER (仅基于有效帧)
                if ~isempty(decodedBits)
                    % 1. 建立 "有效帧" 查找表 (跳过热身帧)
                    txMap = containers.Map('KeyType','double','ValueType','any');
                    for k = 1:length(validTxFrames)
                         fr = validTxFrames{k};
                         id = bi2de(fr(1:8)', 'left-msb');
                         txMap(id) = fr;
                    end
                    
                    % 2. 遍历接收到的帧
                    numRx = floor(length(decodedBits)/bitsPerFrame);
                    errs = 0; bitsComp = 0;
                    
                    for j=1:numRx
                        rxFr = double(decodedBits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
                        rxId = bi2de(rxFr(1:8)', 'left-msb');
                        
                        % 只有当 ID 在有效帧列表中时，才计算误码
                        % 这样就自动忽略了前面可能出错的热身帧
                        if isKey(txMap, rxId)
                            errs = errs + biterr(txMap(rxId), rxFr);
                            bitsComp = bitsComp + bitsPerFrame;
                        end
                    end
                    
                    if bitsComp > 0
                        berVal = errs / bitsComp;
                    else
                        % 如果跑了半天连一个有效帧都没对上 (说明同步完全没锁住)
                        berVal = 0.5; 
                    end
                else
                    berVal = 0.5;
                end
                
            else
                % Fallback (略，保持你之前的逻辑，或者设为 -1)
                berVal = -1; 
            end
            
        catch ME_BER
            berVal = -2; 
            errorMsg = ME_BER.message;
        end

        %% 7. 数据提取与可视化 (保持不变)
        [Pxx_rx, f_axis] = pwelch(rxWaveform, [], [], 1024, Fs, 'centered');
        Pxx_rx_dB = 10*log10(Pxx_rx);
        [Pxx_tx, ~] = pwelch(txWaveform, [], [], 1024, Fs, 'centered');
        Pxx_tx_dB = 10*log10(Pxx_tx);
        
        L_max = 1000;
        raw_idx = 1 : sps : length(rxWaveform);
        raw_pts = rxWaveform(raw_idx);
        raw_pts = raw_pts(1:min(L_max, end));
        scale_raw = 1 / sqrt(mean(abs(raw_pts).^2));
        raw_pts = raw_pts * scale_raw;
        
        if isempty(fineSynced)
            synced_pts = complex(0);
        else
            synced_pts = fineSynced(end-min(L_max, length(fineSynced))+1 : end);
        end
        
        makeRow = @(x) reshape(x, 1, []);
        result = struct();
        result.success = true;
        result.info = sprintf("Generated: %s via %s", opt.modType, ifelse(isAPSK,'FACM','TM'));
        result.ber = berVal; 
        result.errorMsg = errorMsg;
        
        result.spectrum = struct('f', makeRow(f_axis), 'p_rx', makeRow(Pxx_rx_dB), 'p_tx', makeRow(Pxx_tx_dB));
        result.constellation_raw = struct('i', makeRow(real(raw_pts)), 'q', makeRow(imag(raw_pts)));
        result.constellation_synced = struct('i', makeRow(real(synced_pts)), 'q', makeRow(imag(synced_pts)));
        
        realRate = 1.0;
        if contains(codeStr, 'Convolutional', 'IgnoreCase',true) && isfield(opt, 'ConvolutionalCodeRate')
             r=char(opt.ConvolutionalCodeRate); if ~strcmp(r,'N/A'), eval(['realRate=' r ';']); end
        elseif contains(codeStr, {'Turbo','LDPC'}, 'IgnoreCase',true) && isfield(opt, 'CodeRate')
             r=char(opt.CodeRate); if ~strcmp(r,'N/A'), eval(['realRate=' r ';']); end
        end
        
        result.stats = struct('Fs', Fs, 'CodeRate', realRate, 'ElapsedTime', toc(tStart));
        json_str = jsonencode(result);
        
    catch ME
        errMsg = ME.message;
        if ~isempty(ME.stack)
             errMsg = sprintf('%s (File: %s, Line: %d)', errMsg, ME.stack(1).name, ME.stack(1).line);
        end
        err = struct('success', false, 'error', errMsg);
        json_str = jsonencode(err);
    end
end

function out = ifelse(condition, trueVal, falseVal)
    if condition, out = trueVal; else, out = falseVal; end
end