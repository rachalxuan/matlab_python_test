function json_str = run_ccsds_tm_modulation(paramsJson)

   
    tStart = tic;
    debugLog = ""; % 初始化日志缓冲区

    % --- 内部日志函数 ---
    function log(fmt, varargin)
        try
            msg = sprintf(fmt, varargin{:});
            debugLog = debugLog + msg; % 拼接到日志
        catch
            debugLog = debugLog + "Log Error";
        end
    end
    % -------------------

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

        log("======================================================\n");
        log("[DEBUG] Start Sim: Mod=%s, SPS=%d\n", opt.modType, sps);

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
            log('[CHECK] 发送端 GMSK BT 值 = %.4f (目标是 0.5000)\n', infoStruct.BandwidthTimeProduct);
        end
        
        %% 3. 生成数据与波形 (含热身帧)
        Fs = fSym * sps;
        bitsPerFrame = tmWaveGen.NumInputBits;
        numHeaderBits = 8; 
        numPayloadBits = bitsPerFrame - numHeaderBits;
        
        % 增加 5 帧作为“热身”(Warm-up)，不计入 BER 统计
        numWarmUp = 5; 
        numRealFrames = 20; 
        totalFrames = numWarmUp + numRealFrames;
        
        msg = [];
        % 保留“有效帧”的副本用于 BER 对比
        validTxFrames = {}; 
        
        for i = 1:totalFrames
                header = de2bi(mod(i-1, 256), numHeaderBits, 'left-msb')'; 
                payload = int8(randi([0 1], numPayloadBits, 1));
                currentFrame = [header; payload];
                msg = [msg; currentFrame];
                
                % 只有热身之后的帧才算“有效帧”
                
                    validTxFrames{end+1} = currentFrame;
                
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
        
        if contains(modStr, 'GMSK')
            
            % 频偏消除 
            coarseSync = comm.CoarseFrequencyCompensator(...
                'Modulation', 'OQPSK', ...        % GMSK 近似于 OQPSK
                'SampleRate', Fs, ...             
                'FrequencyResolution', 1);        % 1Hz 高精度
            
            [rxSynced, estCFO] = coarseSync(rxWaveform);
            log('  [同步] GMSK 估算频偏: %.2f Hz\n', estCFO);
            
            % 接收滤波 (高斯滤波)
            rxFilterDecimationFactor = sps/2;
            hGauss = gaussdesign(0.5, 4, sps); 
            rxfilter = dsp.FIRDecimator(...
                    'DecimationFactor', rxFilterDecimationFactor, ...
                    'Numerator', hGauss);
            filtered = rxfilter(rxSynced);
            
            %  符号同步 (Early-Late)
            gmskTimingObj = comm.SymbolSynchronizer(...
                'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
                'SamplesPerSymbol', 2, ...
                'DetectorGain', 2.0, ... 
                'Modulation', 'PAM/PSK/QAM', ...
                'DampingFactor', 1, ...
                'NormalizedLoopBandwidth', 0.01); 
            
            fineSynced_Time = gmskTimingObj(filtered);
            
            % 载波相位同步
            carrierSync = comm.CarrierSynchronizer(...
                'Modulation', 'QPSK', ...       
                'SamplesPerSymbol', 1, ...      
                'DampingFactor', 0.707, ...     
                'NormalizedLoopBandwidth', 0.01); 
            
            [fineSynced, ~] = carrierSync(fineSynced_Time);
            log('  [相位] 载波环路已介入...\n');
        else
            % ============================
            % QPSK/PSK 专用 (标准流程)
            % ============================
            % 1. 粗频偏
            if contains(modStr, 'BPSK'), coarseMod = 'BPSK';
            elseif contains(modStr, '8PSK'), coarseMod = '8PSK';
            elseif contains(modStr, 'GMSK'), coarseMod = 'QPSK';
            elseif contains(modStr, 'QPSK') || contains(modStr, 'OQPSK'), coarseMod = 'QPSK';
            else, coarseMod = 'QAM'; end

            if contains(modStr,'GMSK'),FrequencyResolution = 10;
            else,FrequencyResolution = 1e3;end
            
            coarseFreqSync = comm.CoarseFrequencyCompensator('Modulation', coarseMod, 'SampleRate', Fs, 'FrequencyResolution', FrequencyResolution); 
            [coarseSynced, estCFO] = coarseFreqSync(rxWaveform);
            log('  [同步] 估算频偏: %.2f Hz\n', estCFO);

            % 2. 接收滤波
    
           if contains(modStr, 'GMSK')
               % GMSK 必须用高斯滤波器
               rxFilterDecimationFactor = sps/2;
               hGauss = gaussdesign(0.5, 4, sps);
               rxfilter = dsp.FIRDecimator('DecimationFactor', rxFilterDecimationFactor, 'Numerator', hGauss);
               filtered = rxfilter(coarseSynced);
           else
               % PSK/QAM 必须用升余弦滤波器 (RRC)
               rxFilterDecimationFactor = sps/2;
               rxfilter = comm.RaisedCosineReceiveFilter(...
                   'RolloffFactor', rolloff, ...
                   'InputSamplesPerSymbol', sps, ...
                   'DecimationFactor', rxFilterDecimationFactor);
               filtered = rxfilter(coarseSynced);
           end
            
            % 3. 符号同步 (Gardner)
            % 经过滤波器后，SPS 变了，需要重新计算
            sps_after_filter = sps / rxFilterDecimationFactor; 
            
            if contains(modStr, 'GMSK')
                % GMSK ： Early-Late
                timingObj = comm.SymbolSynchronizer(...
                    'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
                    'SamplesPerSymbol', sps_after_filter, ...
                    'DetectorGain', 2.0, ...
                    'Modulation', 'PAM/PSK/QAM', ...
                    'NormalizedLoopBandwidth', 0.01);
            else
                % PSK ： Gardner
                if contains(modStr, 'OQPSK'), SyncMod = 'OQPSK'; else, SyncMod = 'PAM/PSK/QAM'; end
                Kp = 1/(pi*(1-((rolloff^2)/4)))*cos(pi*rolloff/2); % Gardner 增益公式
                timingObj = comm.SymbolSynchronizer(...
                    'TimingErrorDetector', 'Gardner (non-data-aided)', ...
                    'SamplesPerSymbol', sps_after_filter, ...
                    'DetectorGain', Kp, ...
                    'Modulation', SyncMod, ...
                    'NormalizedLoopBandwidth', 0.01);
            end
            TimeSynced = timingObj(filtered);
            
            % 4. 精细频偏 (Carrier Sync) - QPSK 必须有这个
            fineMod = modStr; 
            if contains(modStr, 'OQPSK')|| contains(modStr, 'GMSK'), fineMod = 'QPSK'; end
            if contains(modStr, 'APSK'), fineMod = 'QAM'; end
            carrierSyncObj = comm.CarrierSynchronizer('Modulation', fineMod, 'SamplesPerSymbol', 1, 'DampingFactor', 1/sqrt(2), 'NormalizedLoopBandwidth', 0.01);
            fineSynced = carrierSyncObj(TimeSynced);
        end
        
       %% 6. 解调与误码率计算 (BER)
        berVal = -1;
        errorMsg = "";
        
        try
            % 0. Power Normalization
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
                % A. Create Demodulator
                % ------------------------------------------------
                if contains(tmMod, 'GMSK')
                    demodobj = HelperCCSDSTMDemodulator('Modulation', tmMod, 'ChannelCoding', tmCode, 'BandwidthTimeProduct', btVal);
                else
                    demodobj = HelperCCSDSTMDemodulator('Modulation', tmMod, 'ChannelCoding', tmCode);
                end
                
                % B. Demodulate
                % ------------------------------------------------
                demodData = demodobj(fineSynced);
                
                % GMSK 极性处理
                % 直接把实部取出来作为软信息喂给译码器。
                if contains(tmMod, 'GMSK')
                     demodData = real(demodData); 
                end
                

                % 译码
                decArgs = {'ChannelCoding', tmCode, 'Modulation', tmMod, ...
                           'NumBytesInTransferFrame', 1115, ...
                           'HasRandomizer', hasRandomizer, ...
                           'HasASM', hasASM};
                
                % 确保卷积码率被传递 (如果是 Convolutional)
                if contains(tmCode, 'Convolutional', 'IgnoreCase',true)
                     if isfield(opt, 'ConvolutionalCodeRate')
                        rate = char(opt.ConvolutionalCodeRate); 
                        if ~strcmp(rate,'N/A'), decArgs=[decArgs, {'ConvolutionalCodeRate', rate}]; end
                     else
                        % 默认给 1/2
                        decArgs=[decArgs, {'ConvolutionalCodeRate', '1/2'}];
                     end
                end
                if isfield(opt, 'RSInterleavingDepth'), decArgs=[decArgs, {'RSInterleavingDepth', opt.RSInterleavingDepth}]; end
                
                decoderobj = HelperCCSDSTMDecoder(decArgs{:});
                
                % D. Decode
                % ------------------------------------------------
                decodedBits = decoderobj(demodData);
                
                % 防止译码器输出反相 (Rx全1)
                if contains(tmMod, 'GMSK') && length(decodedBits) > 100
                    check_slice = decodedBits(40:140); % 跳过开头可能的延迟
                    if sum(check_slice) / length(check_slice) > 0.9
                        log('  ！！！！检测到输出反相，执行翻转...\n');
                        decodedBits = ~decodedBits;
                    end
                end
                
                % ==========================================================
                % E. BER Calculation (Split Logic for GMSK vs PSK)
                % ==========================================================
                if ~isempty(decodedBits)
                    % 1. Build Reference Map
                    txMap = containers.Map('KeyType','double','ValueType','any');
                    for k = 1:length(validTxFrames)
                         fr = validTxFrames{k};
                         id = bi2de(fr(1:8)', 'left-msb');
                         txMap(id) = fr;
                    end
                    
                    if contains(tmMod, 'GMSK')
                        % --- GMSK Path: Targeted Header Search (Sliding Window) ---
                        % Because GMSK often has bit slips, we must scan to find the exact frame start.
                        bitsPerFrame = length(validTxFrames{1});
                        currBitsSeq = decodedBits;

                        searchLen = min(10000, length(currBitsSeq)-bitsPerFrame); 
                        
                        foundLock = false;
                        lockedHeaderID = -1;
                        totalErrs = 0; totalBits = 0;
                        
                        for shift = 0 : searchLen
                            candHeader = currBitsSeq(shift+1 : shift+8);
                            rxId = bi2de(candHeader', 'left-msb');
                            
                            % If we find a valid ID that isn't a warmup frame
                            if isKey(txMap, rxId)
                                % Validate further by checking the first few payload bits to ensure it's not a coincidence
                                refFr = txMap(rxId);
                                rxFrCheck = currBitsSeq(shift+1 : shift+bitsPerFrame);
                                if isequal(rxFrCheck(1:20), refFr(1:20))
                                    foundLock = true;
                                    lockedHeaderID = rxId;
                
                                    log('   在偏移 %d 处锁定帧头 (ID=%d)\n', shift, rxId);
                                    log('foundLock = %d\n', foundLock)
                                    
                                    % Lock acquired! Now calculate BER for all subsequent frames
                                    numRx = floor((length(currBitsSeq)-shift)/bitsPerFrame);
                                    for j=1:numRx
                                        startIdx = shift + (j-1)*bitsPerFrame + 1;
                                        endIdx = startIdx + bitsPerFrame - 1;
                                        if endIdx > length(currBitsSeq), break; end
                                        
                                        rxFr = double(currBitsSeq(startIdx:endIdx));
                                        thisId = bi2de(rxFr(1:8)', 'left-msb');
                                        
                                        if isKey(txMap, thisId) && thisId >numWarmUp
                                            totalErrs = totalErrs + biterr(txMap(thisId), rxFr);
                                            totalBits = totalBits + bitsPerFrame;
                                        end
                                    end
                                    break; % Stop searching once locked
                                end
                            end
                        end
                        
                        if foundLock && totalBits > 0
                            berVal = totalErrs / totalBits;
                        else
                            berVal = 0.5; % Sync failed
                        end
                        
                    else
                        % --- PSK Path: Standard Calculation ---
                        % PSK usually syncs cleanly, so simple frame iteration works.
                        numRx = floor(length(decodedBits)/bitsPerFrame);
                        errs = 0; bitsComp = 0;
                        
                        for j=1:numRx
                            rxFr = double(decodedBits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
                            rxId = bi2de(rxFr(1:8)', 'left-msb');
                            
                            if isKey(txMap, rxId)
                                errs = errs + biterr(txMap(rxId), rxFr);
                                bitsComp = bitsComp + bitsPerFrame;
                            end
                        end
                        
                        if bitsComp > 0
                            berVal = errs / bitsComp;
                        else
                            berVal = 0.5;
                        end
                    end
                else
                    berVal = 0.5;
                end
                
            else
                % Helper not supported (Turbo/LDPC)
                berVal = -1; 
            end
            
        catch ME_BER
            berVal = -2; 
            errorMsg = ME_BER.message;
        end

        %% 7. 数据提取与可视化 (保持不变)
        log("[Result] Final BER: %.6f\n", berVal);
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

        result.debugLog = debugLog;
        
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