function metrics = run_ccsds_tm_evaluation(params)
% RUN_CCSDS_TM_EVALUATION  独立评估副本，不参与前端调用
%   - 输入与 run_ccsds_tm_modulation 相同：JSON 字符串 或 struct
%   - 输出：弹出多张分析图 + 命令行打印指标表 + 返回 metrics 结构体
%
% 用法（在 MATLAB 命令行）：
%   1) 用结构体快速调
%   p = struct('modType','QPSK','symbolRate',1e6,'sps',8, ...
%              'snr',12,'cfo',2000,'phaseOffset',30, ...
%              'channelCoding','none','RolloffFactor',0.35);
%  p = struct('modType','16APSK','symbolRate',1e6,'sps',8, ...
%               'snr',12,'cfo',2000,'phaseOffset',30, ...
%               'channelCoding','none','RolloffFactor',0.35,'hasASM',true,'hasPilots',true);
%   m = run_ccsds_tm_evaluation(p);
%
%   2) 用前端的 JSON 直接粘进来调（验一致性）
%   m = run_ccsds_tm_evaluation('{"modType":"QPSK","symbolRate":1e6,"sps":8,"snr":12,"cfo":0,"phaseOffset":0,"channelCoding":"none","RolloffFactor":0.35}');
%
%   3) BER vs SNR 扫描（把 .snrSweep 设成数组，会跑一条曲线）
%   p.snrSweep = 0:2:14;  m = run_ccsds_tm_evaluation(p);

tStart = tic;

if nargin < 1 || isempty(params)
    params = struct('modType','QPSK','symbolRate',1e6,'sps',8, ...
                    'snr',12,'cfo',0,'phaseOffset',0,'delay',0, ...
                    'channelCoding','none','RolloffFactor',0.35);
end
if ischar(params) || isstring(params)
    opt = jsondecode(char(params));
else
    opt = params;
end

try   % ===== 顶层 try/catch: 任何崩溃都返回 success=false 给前端 =====

    % ======== 是否做扫描 ========
    if isfield(opt,'snrSweep') && ~isempty(opt.snrSweep)
        metrics = doSNRSweep(opt);
        return;
    end

    % ======== 单点仿真 ========
    [res, ctx] = runOneShot(opt);

    % showFigures 默认 true; 矩阵测试或前端调用时设 false 跳过出图
    showFigures = true;
    if isfield(opt,'showFigures'), showFigures = logical(opt.showFigures); end

    printMetrics(res, opt);
    if showFigures
        plotAll(res, ctx, opt);
        plotPipeline(res, ctx, opt);     % 损伤恢复管线图
        plotDamageBudget(res, ctx, opt); % 损伤预算图: 输入 vs 残余
    end

    % ======== 给前端打包: 频谱 / 星座 / 管线 / 残余损伤 ========
    fe = buildFrontendArrays(ctx, res);

    % ======== 编码信息归一化 (码率字符串 → 数值) ========
    realRate = codeRateNum(opt);

    % ======== 组装 frontResult ========
    frontResult = struct();
    frontResult.success  = true;
    frontResult.errorMsg = '';

    % info: 前端 normalize 读 modType, 这里给一个完整摘要也存上
    codeStr = '-';
    if isfield(opt,'channelCoding'), codeStr = char(opt.channelCoding); end
    rateStr = '-';
    if isfield(opt,'ConvolutionalCodeRate'), rateStr = char(opt.ConvolutionalCodeRate);
    elseif isfield(opt,'CodeRate'),          rateStr = char(opt.CodeRate); end
    frontResult.info = sprintf('CCSDS TM | %s | coding=%s | rate=%s', ...
                               res.modType, codeStr, rateStr);

    % --- 核心指标 (前端 normalize 直接读这些 PascalCase 字段) ---
    frontResult.modType      = res.modType;
    frontResult.BER          = res.BER;
    frontResult.ber          = res.BER;     % 兼容老 main 字段(小写)
    frontResult.EVM_post_pct = res.EVM_post_pct;
    frontResult.EVM_pre_pct  = res.EVM_pre_pct;
    frontResult.MER_dB       = res.MER_dB;
    frontResult.SNR_est_dB   = res.SNR_est_dB;
    frontResult.PAPR_dB      = res.PAPR_dB;
    frontResult.LockRate     = res.LockRate;
    frontResult.Fs           = res.Fs;
    if isfield(res,'ACMFormat'), frontResult.ACMFormat = res.ACMFormat; end

    % --- 输入回显 ---
    frontResult.snr_in   = res.snr_in;
    frontResult.cfo_in   = res.cfo_in;
    frontResult.phase_in = res.phase_in;
    frontResult.delay_in = res.delay_in;

    % --- 残余损伤 (同步链路压制后的剩余) ---
    frontResult.residCFO_Hz    = fe.residCFO;
    frontResult.residPhase_deg = fe.residPhase;

    % --- 前端绘图数据 (这是之前没传, 前端拿不到的) ---
    frontResult.spectrum             = fe.spectrum;
    frontResult.constellation_raw    = fe.constRaw;
    frontResult.constellation_synced = fe.constSync;
    frontResult.pipeline             = fe.pipeline;   % 4 阶段星座 + 标签

    % --- 编码信息透传 ---
    if isfield(opt,'ConvolutionalCodeRate'), frontResult.ConvolutionalCodeRate = opt.ConvolutionalCodeRate; end
    if isfield(res,'CodeRate'), frontResult.CodeRate = res.CodeRate;
    elseif isfield(opt,'CodeRate') && ~strcmp(char(opt.CodeRate),'N/A'), frontResult.CodeRate = opt.CodeRate; end
    if isfield(opt,'channelCoding'),         frontResult.channelCoding = opt.channelCoding; end

    % --- 时间 + stats 嵌套 (兼容 server.py 读 stats.matlabTime + 旧 main 格式) ---
    elapsed = toc(tStart);
    frontResult.ElapsedTime = elapsed;
    frontResult.stats = struct( ...
        'Fs',          res.Fs, ...
        'CodeRate',    realRate, ...
        'ElapsedTime', elapsed, ...
        'matlabTime',  elapsed);

    metrics = jsonencode(frontResult);

catch ME
    errMsg = ME.message;
    if ~isempty(ME.stack)
        errMsg = sprintf('%s (at %s line %d)', errMsg, ME.stack(1).name, ME.stack(1).line);
    end
    fprintf(2, '[run_ccsds_tm_evaluation ERROR] %s\n', errMsg);
    err = struct( ...
        'success',  false, ...
        'error',    errMsg, ...
        'errorMsg', errMsg, ...
        'BER', -2, 'ber', -2, ...
        'ElapsedTime', toc(tStart));
    metrics = jsonencode(err);
end
end

% =========================================================
% 单次仿真：复用主脚本的处理链路 + 提取所有中间信号
% =========================================================
function [res, ctx] = runOneShot(opt)

    makeNum = @(f) str2double(strrep(string(f), ',', ''));
    if ischar(opt.symbolRate), fSym = makeNum(opt.symbolRate); else, fSym = double(opt.symbolRate); end
    if ischar(opt.sps),        sps  = makeNum(opt.sps);        else, sps  = double(opt.sps);        end
    hasRandomizer = false; if isfield(opt,'hasRandomizer'), hasRandomizer = opt.hasRandomizer; end
    hasASM        = false; if isfield(opt,'hasASM'),        hasASM        = opt.hasASM;        end

    numBytesTF = 1115;
    if isfield(opt,'NumBytesInTransferFrame') && ~isempty(opt.NumBytesInTransferFrame)
        numBytesTF = double(opt.NumBytesInTransferFrame);
    end

    args = {'SamplesPerSymbol', sps, 'HasRandomizer', hasRandomizer, 'HasASM', hasASM};
    isAPSK = contains(opt.modType,'APSK');
    modStr = string(opt.modType);

    if useFACMEvaluation(opt, modStr)
        [res, ctx] = runFACMOneShot(opt, fSym, sps);
        return;
    end

    if isAPSK
        if isfield(opt,'acmFormat'), acmFmt = double(opt.acmFormat); else, acmFmt = 14; end
%         args = [args, {'WaveformSource','flexible advanced coding and modulation', ...
%                        'ACMFormat', acmFmt, 'NumBytesInTransferFrame', 1115, ...
%                        'PulseShapingFilter','Root Raised Cosine'}];
        args = [args, {'WaveformSource','flexible advanced coding and modulation', ...
                       'ACMFormat', acmFmt, 'NumBytesInTransferFrame', numBytesTF, ...
                       'PulseShapingFilter','Root Raised Cosine'}];
        rolloff = 0.35;
    else
%         args = [args, {'WaveformSource','synchronization and channel coding', ...
%                        'NumBytesInTransferFrame', 1115, 'Modulation', modStr}];
        if isfield(opt,'channelCoding'), codeStr = canonicalChannelCoding(opt.channelCoding); else, codeStr = 'none'; end
        codeKey = lower(string(codeStr));
        isLDPCOnSMTF = contains(codeKey,'ldpc') && isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF);
        args = [args, {'WaveformSource','synchronization and channel coding', ...
                       'Modulation', modStr}];
        if ~contains(codeKey,'ldpc') || isLDPCOnSMTF
            args = [args, {'NumBytesInTransferFrame', numBytesTF}];
        end
        args = [args, {'ChannelCoding', codeStr}];
        args = appendRSArgs(args, opt);
        
        if contains(codeKey,'convolutional') && isfield(opt,'ConvolutionalCodeRate')
            rate = char(opt.ConvolutionalCodeRate);
            if ~strcmp(rate,'N/A')
                args = [args, {'ConvolutionalCodeRate', rate}];
            end
        end

        if isfield(opt,'RolloffFactor'), rolloff = str2double(string(opt.RolloffFactor)); else, rolloff = 0.5; end
        btVal = 0.5;
        if isfield(opt,'BandwidthTimeProduct')
            if ischar(opt.BandwidthTimeProduct) || isstring(opt.BandwidthTimeProduct)
                btVal = makeNum(opt.BandwidthTimeProduct);
            else
                btVal = double(opt.BandwidthTimeProduct);
            end
        end

        if contains(modStr,'GMSK')
            args = [args, {'BandwidthTimeProduct', btVal}];
        else
            args = [args, {'RolloffFactor', rolloff}];
        end
        switch modStr
            case {'BPSK','QPSK','8PSK','OQPSK'}
                args = [args, {'FilterSpanInSymbols', 10}];
        end
        if contains(codeKey,{'turbo','ldpc'}) && isfield(opt,'CodeRate')
            args = [args, {'CodeRate', string(opt.CodeRate)}];
        end
        if contains(codeKey,{'turbo','ldpc'}) && isfield(opt,'NumBitsInInformationBlock')
            args = [args, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}];
        end
        if contains(codeKey,'ldpc') && isfield(opt,'IsLDPCOnSMTF')
            args = [args, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}];
        end
        if contains(codeKey,'ldpc') && isfield(opt,'LDPCCodeblockSize')
            args = [args, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}];
        end
    end

    tmWaveGen = ccsdsTMWaveformGenerator(args{:});
    disp(tmWaveGen)
    disp(info(tmWaveGen))
    fprintf('[TX LDPC] NumInputBits=%d, ActualCodeRate=%.6f\n', ...
        tmWaveGen.NumInputBits, info(tmWaveGen).ActualCodeRate);
    Fs = fSym * sps;
    bitsPerFrame = tmWaveGen.NumInputBits;
    fprintf('[Actual TF] NumInputBits=%d, NumInputBytes=%.3f\n', ...
             tmWaveGen.NumInputBits, tmWaveGen.NumInputBits/8);
    numHeaderBits = 8;
    numWarmUp = 8; numRealFrames = 100; totalFrames = numWarmUp + numRealFrames;

    msg = []; validTxFrames = {};
    for i = 1:totalFrames
        header = de2bi(mod(i-1,256), numHeaderBits, 'left-msb')';
        payload = int8(randi([0 1], bitsPerFrame - numHeaderBits, 1));
        currentFrame = [header; payload];
        msg = [msg; currentFrame];
        validTxFrames{end+1} = currentFrame; %#ok<AGROW>
    end
    txWaveform = tmWaveGen(msg);

    % ===== 信道损伤 =====
    cfo_val   = getf(opt,'cfo',0);
    phase_val = getf(opt,'phaseOffset',0) * pi/180;
    delay_val = getf(opt,'delay',0);
    snr_val   = getf(opt,'snr',100);

    if cfo_val~=0 || phase_val~=0
        pfo = comm.PhaseFrequencyOffset('FrequencyOffset',cfo_val,'PhaseOffset',phase_val,'SampleRate',Fs);
        txWithCFO = pfo(txWaveform);
    else
        txWithCFO = txWaveform;
    end
    if delay_val ~= 0
        varDelay = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        txWithDelay = varDelay(txWithCFO, delay_val);
    else
        txWithDelay = txWithCFO;
    end
    rxWaveform = awgn(txWithDelay, snr_val, 'measured');

    % ===== 接收链路（与主脚本一致，简化版） =====
    if contains(modStr,'GMSK')
        % --- 1) 基于 x^2 的 GMSK 粗 CFO 估计 ---
        % MSK/GMSK 信号平方后频谱有两条边带：±fSym/2 + 2*CFO
        % 取两条边带中点 = 2*CFO，再除以 2
        Lfft   = min(length(rxWaveform), 2^17);
        Nfft   = 2^nextpow2(Lfft);
        win    = hamming(Lfft);
        sigSq  = rxWaveform(1:Lfft).^2;
        Xsq    = fftshift(fft(sigSq .* win, Nfft));
        fAx    = (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);
        Psq    = abs(Xsq).^2;
        posMask = fAx >  fSym*0.25 & fAx <  fSym*1.0;
        negMask = fAx < -fSym*0.25 & fAx > -fSym*1.0;
        [~,ip]  = max(Psq .* posMask);
        [~,in]  = max(Psq .* negMask);
        cfo_est = (fAx(ip) + fAx(in)) / 4;          % 2*CFO = 中点*2 → CFO = /4
        nIdx    = (0:length(rxWaveform)-1).';
        rxSynced = rxWaveform .* exp(-1j*2*pi*cfo_est*nIdx/Fs);
        coarseSynced = rxSynced;   % 统一变量名,供管线图使用

        % --- 2) 高斯匹配滤波（用真正的 btVal,不再写死 0.5）+ 抽到 2 sps ---
        rxFilterDecimationFactor = sps/2;
        hGauss   = gaussdesign(btVal, 4, sps);
        rxfilter = dsp.FIRDecimator('DecimationFactor',rxFilterDecimationFactor, ...
                                    'Numerator',hGauss);
        filtered = rxfilter(rxSynced);

        % --- 3) 符号定时同步 ---
        timingObj = comm.SymbolSynchronizer('TimingErrorDetector','Early-Late (non-data-aided)', ...
            'SamplesPerSymbol',2,'DetectorGain',2.0,'Modulation','PAM/PSK/QAM', ...
            'DampingFactor',1,'NormalizedLoopBandwidth',0.005);
        TimeSynced = timingObj(filtered);

        % --- 4) 细载波同步：QPSK 模式 + 1 sps（OQPSK 模式要求 sps 为偶数，不能用 1 sps）
        % 粗 CFO 已用 x^2 法基本去掉，残余偏移小，QPSK PED 足以兜住
        carrierSync = comm.CarrierSynchronizer('Modulation','QPSK','SamplesPerSymbol',1, ...
            'DampingFactor',1/sqrt(2),'NormalizedLoopBandwidth',0.005);
        fineSynced = carrierSync(TimeSynced);

        fprintf('   [GMSK coarse CFO] estimated = %+.1f Hz (input = %+.1f Hz)\n', ...
                cfo_est, getf(opt,'cfo',0));
    else
        if contains(modStr,'BPSK')
            coarseMod = 'BPSK';
        elseif contains(modStr,'8PSK')
            coarseMod = '8PSK';
        elseif contains(modStr,'OQPSK')
            coarseMod = 'OQPSK';
        elseif contains(modStr,'QPSK')
            coarseMod = 'QPSK';
        elseif contains(modStr,'APSK')
            coarseMod = 'QPSK';
        else
            coarseMod = 'QAM';
        end

        if contains(modStr,'OQPSK')
            % =================================================================
            % OQPSK 新链路 (推荐方案 2): FFT CFO + CarrierSync('OQPSK') +
            % comm.OQPSKDemodulator (MF+timing+soft LLR 一体化, 在 tryOneRotation 中调用)
            % -----------------------------------------------------------------
            % 弃用原来的 RRC + SymbolSync('OQPSK') + CarrierSync('QPSK') 三段式,
            % 因为它在 SNR=25 + CFO=20kHz + 长信号下 TED 漂走 → 锁不住.
            % 这里把 MF+timing 全甩给官方 comm.OQPSKDemodulator,
            % 本函数只负责粗 CFO 估计 + 载波相位锁定.
            % =================================================================

            % --- 1) 4 次幂 FFT 粗 CFO 估计 (实测残余 ~4Hz, 已经够) ---
            Lfft = min(length(rxWaveform), 2^17);
            Nfft = 2^nextpow2(Lfft);
            win  = hamming(Lfft);
            sig4 = rxWaveform(1:Lfft).^4;
            X4   = fftshift(fft(sig4 .* win, Nfft));
            fAx  = (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);
            P4   = abs(X4).^2;
            searchMask = abs(fAx) < Fs/4;
            P4(~searchMask) = 0;
            [~, ip] = max(P4);
            cfo_est = fAx(ip) / 4;
            nIdx = (0:length(rxWaveform)-1).';
            coarseSynced = rxWaveform .* exp(-1j*2*pi*cfo_est*nIdx/Fs);
            fprintf('   [OQPSK coarse CFO] FFT = %+.1f Hz (输入 = %+.1f Hz)\n', ...
                    cfo_est, getf(opt,'cfo',0));

            % --- 2) 载波相位锁定: 在 sps=sps 上直接跑 (官方 OQPSK 模式 CarrierSync) ---
            carrierSync = comm.CarrierSynchronizer( ...
                'Modulation','OQPSK', ...
                'SamplesPerSymbol',sps, ...
                'DampingFactor',1/sqrt(2), ...
                'NormalizedLoopBandwidth',0.005);
            fineSyncedHi = carrierSync(coarseSynced);

            % --- 3) BER 路径: 把 sps=sps 复信号传给 tryOneRotation,
            %        在那里调用 comm.OQPSKDemodulator 一次性完成 MF+timing+LLR ---
            fineSyncedForBER = fineSyncedHi;

            % --- 4) 可视化路径 (仅用于星座图/EVM 显示, 不参与 BER) ---
            try
                rxFilterDecimationFactor = sps/2;
                rxfilterDisp = comm.RaisedCosineReceiveFilter( ...
                    'RolloffFactor', rolloff, ...
                    'InputSamplesPerSymbol', sps, ...
                    'DecimationFactor', rxFilterDecimationFactor);
                filteredDisp = rxfilterDisp(fineSyncedHi);
                sps_after_disp = sps / rxFilterDecimationFactor;
                timingDisp = comm.SymbolSynchronizer( ...
                    'TimingErrorDetector','Gardner (non-data-aided)', ...
                    'SamplesPerSymbol', sps_after_disp, ...
                    'Modulation','OQPSK', ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',0.005);
                TimeSynced = timingDisp(filteredDisp);
                fineSynced = TimeSynced;
            catch
                TimeSynced = fineSyncedHi(1:sps:end);
                fineSynced = TimeSynced;
            end
        else
            % Common path for BPSK / QPSK / 8PSK / APSK.
            coarseFreqSync = comm.CoarseFrequencyCompensator( ...
                'Modulation', coarseMod, ...
                'SampleRate', Fs, ...
                'FrequencyResolution', 1e3);

            coarseSynced = coarseFreqSync(rxWaveform);

            rxFilterDecimationFactor = sps/2;
            rxfilter = comm.RaisedCosineReceiveFilter( ...
                'RolloffFactor', rolloff, ...
                'InputSamplesPerSymbol', sps, ...
                'DecimationFactor', rxFilterDecimationFactor);

            filtered = rxfilter(coarseSynced);
            sps_after = sps / rxFilterDecimationFactor;

            SyncMod = 'PAM/PSK/QAM';
            Kp = 1/(pi*(1-((rolloff^2)/4))) * cos(pi*rolloff/2);

            timingObj = comm.SymbolSynchronizer( ...
                'TimingErrorDetector','Gardner (non-data-aided)', ...
                'SamplesPerSymbol', sps_after, ...
                'DetectorGain', Kp, ...
                'Modulation', SyncMod, ...
                'NormalizedLoopBandwidth', 0.01);

            TimeSynced = timingObj(filtered);

            if contains(modStr,'8PSK') || contains(modStr,'APSK')
                fineLoopBW = 0.005;
            else
                fineLoopBW = 0.01;
            end

            if contains(modStr,'APSK')
                carrierSync = comm.CarrierSynchronizer( ...
                    'Modulation','QPSK', ...
                    'SamplesPerSymbol',1, ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',0.005);
            else
                carrierSync = comm.CarrierSynchronizer( ...
                    'Modulation',char(modStr), ...
                    'SamplesPerSymbol',1, ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',fineLoopBW);
            end

            fineSynced = carrierSync(TimeSynced);
        end
    end
    if ~exist('fineSyncedForBER','var')
        fineSyncedForBER = fineSynced;
    end

    % ===== 功率归一 =====

    if ~isempty(fineSynced)
        pwr = mean(abs(fineSynced).^2);
        if pwr>0, fineSynced = fineSynced/sqrt(pwr); end
    end

    if ~isempty(fineSyncedForBER)
        pwrBER = mean(abs(fineSyncedForBER).^2);
        if pwrBER>0
            fineSyncedForBER = fineSyncedForBER/sqrt(pwrBER);
        end
    end

    % ===== 计算所有指标 =====
    isGMSKMod = contains(upper(string(modStr)),'GMSK');
    if isGMSKMod
        refConst = [];
    else
        refConst = getReferenceConstellation(modStr);
    end

    % 同步前的"原始抽样"用作对比（按 sps 抽 1 个）
    rawSym = rxWaveform(1:sps:end);
    if ~isempty(rawSym)
        rawSym = rawSym / sqrt(mean(abs(rawSym).^2)+eps);
    end
    
    % 同步前的evm
    if isGMSKMod
        [evm_pre,  ~] = computeGMSKIQRoughMetrics(rawSym);
    else
        [evm_pre,  ~] = computeEVM(rawSym, refConst);
    end
    % EVM/MER/SNR_est 先用未旋转的算一份占位,稍后用 best 旋转后的覆盖

    % 同步后的evm
    if isGMSKMod
        [evm_post, mer_post] = computeGMSKIQRoughMetrics(fineSynced);
    else
        [evm_post, mer_post] = computeEVM(fineSynced, refConst);
    end

    % 基于星座误差估计的等效 SNR，不等于输入 SNR
    if isGMSKMod
        snr_est = mer_post;
    else
        snr_est = computeSNRest(fineSynced, refConst);
    end

    % 峰均功率比
    papr_dB = 10*log10(max(abs(txWaveform).^2)/mean(abs(txWaveform).^2));

    % BER + Frame Lock（沿用主脚本逻辑的简化版）
    [berVal, lockRate, bestRot] = computeBER(fineSyncedForBER, validTxFrames, modStr, opt, hasRandomizer, hasASM, btVal, numWarmUp);

    % 用 BER 评估挑出来的 best 旋转把 fineSynced 转回参考相位,星座图视觉对齐
    if isGMSKMod
        fineSyncedAligned = fineSynced;
        [evm_post, mer_post] = computeGMSKIQRoughMetrics(fineSyncedAligned);
        snr_est = mer_post;
    else
        fineSyncedAligned = fineSynced * exp(1j*bestRot);
        [evm_post, mer_post] = computeEVM(fineSyncedAligned, refConst);
        snr_est              = computeSNRest(fineSyncedAligned, refConst);
    end

    % ===== 打包返回 =====
    res = struct();
    res.modType  = char(modStr);
    res.snr_in   = snr_val;
    res.cfo_in   = cfo_val;
    res.phase_in = getf(opt,'phaseOffset',0);
    res.delay_in = delay_val;
    res.BER         = berVal;
    res.EVM_pre_pct = evm_pre;
    res.EVM_post_pct= evm_post;
    res.MER_dB      = mer_post;
    res.SNR_est_dB  = snr_est;
    res.PAPR_dB     = papr_dB;
    res.LockRate    = lockRate;
    res.Fs          = Fs;
    

    %传给前端

    % 给绘图用 — fineSynced 应用 best 旋转后再画,星座视觉对齐参考
    ctx.txWaveform   = txWaveform;
    ctx.rxWaveform   = rxWaveform;
    ctx.coarseSynced = coarseSynced;
    ctx.TimeSynced   = TimeSynced;
    ctx.fineSynced   = fineSyncedAligned;
    ctx.rawSym       = rawSym;
    ctx.refConst     = refConst;
    ctx.Fs           = Fs;
    ctx.sps          = sps;
    ctx.bestRot      = bestRot;
end

% =========================================================
% 工具函数
% =========================================================
function v = getf(s, name, defv)
    if isfield(s,name) && ~isempty(s.(name)), v = double(s.(name)); else, v = defv; end
end

% 参考星座点
function refConst = getReferenceConstellation(modStr)
    s = upper(string(modStr));
    if contains(s,'BPSK')
        refConst = pskmod((0:1).', 2);
    elseif contains(s,'8PSK')
        refConst = pskmod((0:7).', 8, pi/8, 'gray');
    elseif contains(s,'OQPSK') || contains(s,'QPSK')
        refConst = pskmod((0:3).', 4, pi/4, 'gray');
    elseif contains(s,'GMSK')
        refConst = pskmod((0:3).', 4, pi/4, 'gray');  % 近似，载波同步后大致 QPSK
    elseif contains(s,'16APSK')
        gamma = 2.85;
        inner = exp(1j*((0:3)*pi/2 + pi/4));
        outer = gamma * exp(1j*((0:11)*pi/6 + pi/12));
        refConst = [inner outer].';
    else
        refConst = pskmod((0:3).', 4, pi/4, 'gray');
    end
    refConst = refConst / sqrt(mean(abs(refConst).^2));  % 归一
end

% 计算evm
function [evm_pct, mer_dB] = computeEVM(rxSym, refConst)
    if isempty(rxSym) || isempty(refConst), evm_pct=NaN; mer_dB=NaN; return; end
    %按列处理
    rxSym = rxSym(:);
    L = min(length(rxSym), 5000);
    rxSym = rxSym(end-L+1:end);   % 取尾段，避开瞬态,保证一定收敛了
    % 对每个接收点找最近理想星座点
    [~, idx] = min(abs(rxSym - refConst.'), [], 2);
    ideal = refConst(idx);
    err   = rxSym - ideal;
    evm_pct = sqrt(mean(abs(err).^2) / mean(abs(refConst).^2)) * 100;
    mer_dB  = -20*log10(evm_pct/100 + eps);
end

function [evm_pct, mer_dB] = computeGMSKIQRoughMetrics(rxSym)
    if isempty(rxSym), evm_pct=NaN; mer_dB=NaN; return; end
    rxSym = rxSym(:);
    L = min(length(rxSym), 5000);
    rxSym = rxSym(end-L+1:end);
    rxSym = rxSym ./ sqrt(mean(abs(rxSym).^2) + eps);
    ampErr = abs(rxSym) - 1;
    evm_pct = sqrt(mean(ampErr.^2)) * 100;
    mer_dB  = -20*log10(evm_pct/100 + eps);
end

function snr_est = computeSNRest(rxSym, refConst)
    if isempty(rxSym) || isempty(refConst), snr_est=NaN; return; end
    rxSym = rxSym(:);
    L = min(length(rxSym), 5000);
    rxSym = rxSym(end-L+1:end);
    [~, idx] = min(abs(rxSym - refConst.'), [], 2);
    ideal = refConst(idx);
    Ps = mean(abs(ideal).^2);
    Pn = mean(abs(rxSym - ideal).^2);
    snr_est = 10*log10(Ps / (Pn+eps));
end

function [berVal, lockRate, bestRot] = computeBER(fineSynced, validTxFrames, modStr, opt, hasRandomizer, hasASM, btVal, numWarmUp)
    berVal = -1; lockRate = 0; bestRot = 0;
    try
        tmMod = char(modStr); if contains(tmMod,'GMSK'), tmMod='GMSK'; end
        if isfield(opt,'channelCoding'), tmCode=char(canonicalChannelCoding(opt.channelCoding)); else, tmCode='none'; end
        tmCodeKey = lower(string(tmCode));
        if contains(tmCodeKey,{'turbo'}), return; end

        % --- 解算载波相位 M 重模糊：试每个等价旋转，挑帧匹配最多的 ---
        if contains(tmMod,'BPSK')
            rotations = [1, -1];
        elseif contains(tmMod,'8PSK')
            rotations = exp(1j*pi/4 * (0:7));
        elseif contains(tmMod,'GMSK')
            % GMSK 内部 exp(-j*pi/2*n) 去自旋的起始 n 受符号定时器漂移影响,
            % 任意 0~3 的偏移都可能,等价于乘 exp(j*pi/2*k); 必须 4 重枚举
            rotations = exp(1j*pi/2 * (0:3));
        else                      % QPSK/OQPSK/APSK
            rotations = exp(1j*pi/2 * (0:3));
        end

        bestBer = inf;
        bestLock = -1;
        bestRot = 0;
        bitErrorsBest = 0;
        bitsComparedBest = 0;
        bestShift = 0;
        
        for ii = 1:length(rotations)
            r = rotations(ii);
            rxRot = fineSynced * r;
        
            [ber, lock, errs, bitsComp] = tryOneRotation( ...
                rxRot, validTxFrames, tmMod, tmCode, ...
                opt, hasRandomizer, hasASM, btVal, numWarmUp);
        
            fprintf('   [候选角度] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                rad2deg(angle(r)), ber, lock*100, errs, bitsComp);
        
            % 新规则：
            % 只要锁帧率还可以，就优先选择 BER 最低的角度
            if lock >= 0.80 && bitsComp > 0
                if ber < bestBer
                    bestBer = ber;
                    bestLock = lock;
                    bestRot = angle(r);
                    bitErrorsBest = errs;
                    bitsComparedBest = bitsComp;
%                     bestShift = shiftBits;
                end
            else
                % 如果还没有找到可靠候选，则暂时保留 lock 最高的
                if isinf(bestBer) && lock > bestLock
                    bestBer = ber;
                    bestLock = lock;
                    bestRot = angle(r);
                    bitErrorsBest = errs;
                    bitsComparedBest = bitsComp;
%                     bestShift = shiftBits;
                end
            end
        end
        
        berVal = bestBer;
        lockRate = max(bestLock, 0);
        
        fprintf('   [Phase ambiguity] best rotation = %+5.1f deg, lockRate=%.1f%%\n', ...
            rad2deg(bestRot), lockRate*100);
    catch ME_BER
        berVal = -2; lockRate = 0;
        fprintf(2,'\n[computeBER ERROR] %s\n', ME_BER.message);
        if ~isempty(ME_BER.stack)
            for s = 1:min(3, length(ME_BER.stack))
                fprintf(2,'   at %s (line %d)\n', ME_BER.stack(s).name, ME_BER.stack(s).line);
            end
        end
    end
end

function [berVal, lockRate, errs, bitsComp] = tryOneRotation(fineSynced, validTxFrames, tmMod, tmCode, opt, hasRandomizer, hasASM, btVal, numWarmUp)
    berVal = 0.5; lockRate = 0;
    errs = 0;
    bitsComp = 0;
    numBytesTF = 1151;
    if isfield(opt,'NumBytesInTransferFrame') && ~isempty(opt.NumBytesInTransferFrame)
        numBytesTF = double(opt.NumBytesInTransferFrame);
    end
    if strcmp(tmMod,'OQPSK')
        % ===== OQPSK 新路径: 官方 comm.OQPSKDemodulator (MF + timing + soft LLR) =====
        % 输入 fineSynced 在这里是 sps=sps 复信号 (不再是 1 sps).
        % OQPSKDemodulator 内部做 RRC 匹配滤波 + I/Q 半符号对齐 + 定时恢复 + 软 LLR 输出,
        % 完全替代之前手写的 RRC + SymbolSync('OQPSK') + PSKDemodulator 三段式.
        if isfield(opt,'sps')
            spsLocal = double(opt.sps);
        else
            spsLocal = 8;
        end
        if isfield(opt,'RolloffFactor')
            rolloffLocal = str2double(string(opt.RolloffFactor));
        else
            rolloffLocal = 0.35;
        end
        demodobj = HelperCCSDSTMDemodulator( ...
            'Modulation', tmMod, ...
            'ChannelCoding', tmCode, ...
            'SamplesPerSymbol', spsLocal, ...
            'RolloffFactor', rolloffLocal);
    
        demodData = demodobj(fineSynced);
%         oqpskDemod = comm.OQPSKDemodulator( ...
%             'PulseShape','Root raised cosine', ...
%             'RolloffFactor', rolloffLocal, ...
%             'SamplesPerSymbol', spsLocal, ...
%             'BitOutput', true);
%         demodData = oqpskDemod(fineSynced);
%         % 内置 OQPSKDemodulator 默认是 Gray 映射, CCSDS 用 CustomMapping [0;2;3;1],
%         % 推导出两者差别正好是 "每对 bit 内部交换" (i.e. (b0,b1) <-> (b1,b0)).
%         % 把 LLR 按对调换:
%         if mod(length(demodData), 2) == 0
%             demodData = reshape(demodData, 2, []);
%             demodData = demodData([2 1], :);
%             demodData = demodData(:);
%         end
%         % LLR 符号: comm.OQPSKDemodulator 输出 >0 表示 bit=0,
%         % HelperCCSDSTMDecoder 里的 Viterbi 期望 >0 表示 bit=1 (跟 QPSK 路径一致, 那里有 y=-1*y),
%         % 所以这里也翻号.
%         demodBits = demodData(:) > 0;
%         demodData = -5 * ones(size(demodBits));
%         demodData(demodBits) = 5;
    elseif contains(tmMod,'GMSK')
        demodobj = HelperCCSDSTMDemodulator('Modulation',tmMod,'ChannelCoding',tmCode,'BandwidthTimeProduct',btVal);
        demodData = demodobj(fineSynced);
        demodData = real(demodData);
    else
        demodobj = HelperCCSDSTMDemodulator('Modulation',tmMod,'ChannelCoding',tmCode);
        demodData = demodobj(fineSynced);
    end

%     decArgs = {'ChannelCoding',tmCode,'Modulation',tmMod, ...
%                'NumBytesInTransferFrame',1115, ...
%                'HasRandomizer',hasRandomizer,'HasASM',hasASM};
    isLDPCOnSMTF = contains(lower(string(tmCode)),'ldpc') && isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF);
    decArgs = {'ChannelCoding',tmCode,'Modulation',tmMod, ...
               'HasRandomizer',hasRandomizer,'HasASM',hasASM};
    if ~contains(lower(string(tmCode)),'ldpc') || isLDPCOnSMTF
        decArgs = [decArgs, {'NumBytesInTransferFrame',numBytesTF}];
    end
    decArgs = appendRSArgs(decArgs, opt);
    if contains(lower(string(tmCode)),'convolutional')
        if isfield(opt,'ConvolutionalCodeRate')
            rate = char(opt.ConvolutionalCodeRate);
            if ~strcmp(rate,'N/A'), decArgs=[decArgs,{'ConvolutionalCodeRate',rate}]; end
        else
            decArgs=[decArgs,{'ConvolutionalCodeRate','1/2'}];
        end
    end
    if contains(lower(string(tmCode)),'ldpc')
        if isfield(opt,'CodeRate') && ~strcmp(char(opt.CodeRate),'N/A')
            decArgs = [decArgs, {'CodeRate', string(opt.CodeRate)}];
        end
        if isfield(opt,'NumBitsInInformationBlock')
            decArgs = [decArgs, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}];
        end
        if isfield(opt,'IsLDPCOnSMTF')
            decArgs = [decArgs, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}];
        end
        if isfield(opt,'LDPCCodeblockSize')
            decArgs = [decArgs, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}];
        end
    end
    decoderobj = HelperCCSDSTMDecoder(decArgs{:});
    decodedBits = decoderobj(demodData);

    if contains(tmMod,'GMSK') && length(decodedBits)>100
        check = decodedBits(40:140);
        if sum(check)/length(check) > 0.9, decodedBits = ~decodedBits; end
    end

    bitsPerFrame = length(validTxFrames{1});
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k=1:length(validTxFrames)
        fr = validTxFrames{k}; id = bi2de(fr(1:8)','left-msb'); txMap(id)=fr;
    end

    numRx = floor(length(decodedBits)/bitsPerFrame);

    % DEBUG: OQPSK 锁不住时, 打印解码后的头 12 个帧 ID, 帮判断 Viterbi 输出是
    % (a) 完全随机 (~uniform 0~255), (b) 全 0 / 全 255 (LLR 卡死),
    % (c) 有结构但 ID 在 108~255 (帧边界对齐 / ASM 检测错位)
    if contains(tmMod,'OQPSK') && numRx > 0
        sample = min(12, numRx);
        ids = zeros(1,sample);
        for jj=1:sample
            rxFr_dbg = double(decodedBits((jj-1)*bitsPerFrame+1:jj*bitsPerFrame));
            ids(jj) = bi2de(rxFr_dbg(1:8)','left-msb');
        end
        fprintf('   [OQPSK DEBUG] decodedBits len=%d, numRx=%d, 头 %d 帧 ID = [%s]\n', ...
            length(decodedBits), numRx, sample, num2str(ids));
    end

%     errs=0;
%     bitsComp=0;
    hasLastId = false;
    lastRxId = 0;
    consecIdCount = 0;

    framesMatched=0;
    perFrameBER = nan(1,numRx);

    % 从 decodedBits 里按 bitsPerFrame 切一帧。
    % 取这一帧前 8 bit，转成 rxId。
    % 如果这个 ID 在发送帧 Map 里，说明"认为这帧锁到了"。
    % 用 biterr() 比较接收帧和对应发送帧。
    % 如果 rxId >= numWarmUp，才计入 BER。
    for j=1:numRx
        rxFr = double(decodedBits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
        rxId = bi2de(rxFr(1:8)','left-msb');
        if isKey(txMap,rxId)
            framesMatched = framesMatched + 1;          % 所有匹配帧计入 lockRate
            thisErrs = biterr(txMap(rxId), rxFr);
            perFrameBER(j) = thisErrs / bitsPerFrame;
%             if rxId >= numWarmUp                          % 只用稳态帧算 BER
%                 errs = errs + thisErrs;
%                 bitsComp = bitsComp + bitsPerFrame;
%             end
            % 保证连续帧 不会出现错的帧的id也恰好在map里
            if ~hasLastId
                % 第一个匹配到的帧 没有上一帧
                hasLastId = true;
                consecIdCount = 1;
            else
                % 连续的
                expectedId = mod(lastRxId + 1, 256);
                if rxId == expectedId
                    consecIdCount  = consecIdCount + 1;
                else
                    hasLastId = false;
                end

            end
            lastRxId = rxId;
            counted = consecIdCount >= numWarmUp;

%             fprintf('\n   [FrameCheck] j=%d, rxId=%d, perBER=%.3f, counted=%d', ...
%                 j, rxId, perFrameBER(j), counted);
        
            if counted
                errs = errs + thisErrs;
                bitsComp = bitsComp + bitsPerFrame;
            end
                end
    end
    if bitsComp>0, berVal = errs/bitsComp; else, berVal = 0.5; end
    % numRx 太少说明解码器同步失败,只输出了 1 帧 zeros (header=0 偶然命中 warmup 帧 0),
    % 这种"虚假 100% lockRate"不能参与竞选,直接置零
    if numRx < 3
        lockRate = 0;
    else
        lockRate = framesMatched / numRx;
    end

    % --- 诊断：打印各帧 BER（仅当本次旋转匹配率 > 50%，避免误判旋转的帧）---
    if lockRate > 0.5
        fprintf('   [Per-frame BER] ');
        for j=1:min(numRx, 25)
            if isnan(perFrameBER(j)), fprintf('  -   ');
            else, fprintf('%5.3f ', perFrameBER(j)); end
            if mod(j,10)==0 && j<numRx, fprintf('\n                   '); end
        end
        fprintf('\n');
    end
end

% =========================================================
% 打印 + 出图
% =========================================================
% function printMetrics(res, opt)
%     fprintf('\n========= CCSDS 评估结果 =========\n');
%     fprintf(' 调制方式 : %s\n', res.modType);
%     fprintf(' 输入 SNR : %.1f dB,  CFO=%.1f Hz,  Phase=%.1f deg,  Delay=%.3f\n', ...
%         res.snr_in, res.cfo_in, res.phase_in, res.delay_in);
%     fprintf(' --------------------------------\n');
%     fprintf(' BER          : %.6f\n', res.BER);
%     fprintf(' EVM (sync前) : %6.2f %%\n', res.EVM_pre_pct);
%     fprintf(' EVM (sync后) : %6.2f %%\n', res.EVM_post_pct);
%     fprintf(' MER (sync后) : %6.2f dB\n', res.MER_dB);
%     fprintf(' SNR_est      : %6.2f dB  (输入是 %.1f dB)\n', res.SNR_est_dB, res.snr_in);
%     fprintf(' PAPR (Tx)    : %6.2f dB\n', res.PAPR_dB);
%     fprintf(' Frame Lock   : %6.2f %%\n', res.LockRate*100);
%     fprintf('==================================\n\n');
% end
function printMetrics(res, opt)
    isGMSK = contains(upper(string(res.modType)), 'GMSK');

    fprintf('\n========= CCSDS 评估结果 =========\n');
    fprintf(' 调制方式 : %s\n', res.modType);
    fprintf(' 输入 SNR : %.1f dB,  CFO=%.1f Hz,  Phase=%.1f deg,  Delay=%.3f\n', ...
        res.snr_in, res.cfo_in, res.phase_in, res.delay_in);
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6f\n', res.BER);

    if isGMSK
        fprintf(' 包络误差(sync前) : %6.2f %%\n', res.EVM_pre_pct);
        fprintf(' 包络误差(sync后) : %6.2f %%\n', res.EVM_post_pct);
        fprintf(' 包络MER(sync后)  : %6.2f dB\n', res.MER_dB);
        fprintf(' 等效SNR指标      : %6.2f dB  (输入是 %.1f dB)\n', ...
            res.SNR_est_dB, res.snr_in);
    else
        fprintf(' EVM (sync前) : %6.2f %%\n', res.EVM_pre_pct);
        fprintf(' EVM (sync后) : %6.2f %%\n', res.EVM_post_pct);
        fprintf(' MER (sync后) : %6.2f dB\n', res.MER_dB);
        fprintf(' SNR_est      : %6.2f dB  (输入是 %.1f dB)\n', ...
            res.SNR_est_dB, res.snr_in);
    end

    fprintf(' PAPR (Tx)    : %6.2f dB\n', res.PAPR_dB);
    fprintf(' Frame Lock   : %6.2f %%\n', res.LockRate*100);
    fprintf('==================================\n\n');
end

function plotAll(res, ctx, opt)
    if contains(upper(string(res.modType)),'GMSK')
        plotGMSKAll(res, ctx, opt);
        return;
    end
    figure('Name','CCSDS 评估','NumberTitle','off','Position',[100 100 1200 800]);

    % 1. 同步前星座
    subplot(2,3,1);
    plotConstellation(ctx.rawSym, ctx.refConst, '同步前 (raw)');

    % 2. 同步后星座 + EVM 圈
    subplot(2,3,2);
    plotConstellation(ctx.fineSynced, ctx.refConst, ...
        sprintf('同步后  EVM=%.2f%%  MER=%.2fdB', res.EVM_post_pct, res.MER_dB));

    % 3. 频谱
    subplot(2,3,3);
    [Pxx_tx, f_axis] = pwelch(ctx.txWaveform,[],[],1024,ctx.Fs,'centered');
    [Pxx_rx, ~]      = pwelch(ctx.rxWaveform,[],[],1024,ctx.Fs,'centered');
    plot(f_axis/1e3, 10*log10(Pxx_tx),'b','LineWidth',1.2); hold on;
    plot(f_axis/1e3, 10*log10(Pxx_rx),'r','LineWidth',1.0);
    grid on; xlabel('频率 (kHz)'); ylabel('PSD (dB/Hz)');
    legend('Tx','Rx'); title('功率谱');

    % 4. 时域 IQ
    subplot(2,3,4);
    Nt = min(2000, length(ctx.rxWaveform));
    t = (0:Nt-1)/ctx.Fs * 1e6;
    plot(t, real(ctx.rxWaveform(1:Nt)),'b'); hold on;
    plot(t, imag(ctx.rxWaveform(1:Nt)),'r');
    grid on; xlabel('时间 (us)'); ylabel('幅度');
    legend('I','Q'); title('Rx 时域 IQ');

    % 5. 眼图（仅 PSK，GMSK/APSK 跳过）
    subplot(2,3,5);
    try
        if contains(upper(string(res.modType)),'PSK') && ~contains(upper(string(res.modType)),'OQPSK')
            Neye = min(1000, length(ctx.fineSynced));
            seg = real(ctx.fineSynced(end-Neye+1:end));
            % 简单眼图：把每 2 个符号叠在一起画
            spsEye = 2;
            seg = seg(1:floor(length(seg)/spsEye)*spsEye);
            mat = reshape(seg, spsEye, []);
            plot(mat,'b'); grid on; title('眼图 (I 路简化)');
        else
            text(0.3,0.5,sprintf('%s 眼图省略', res.modType));
            axis off;
        end
    catch
        axis off;
    end

    % 6. 指标条形图
    subplot(2,3,6);
    vals = [res.EVM_post_pct, res.MER_dB, res.SNR_est_dB, res.PAPR_dB, res.LockRate*100];
    names = {'EVM%','MER dB','SNRest dB','PAPR dB','Lock%'};
    bar(vals); set(gca,'XTickLabel',names); grid on;
    title(sprintf('BER=%.2e', res.BER));
end

function plotGMSKAll(res, ctx, opt) %#ok<INUSD>
    figure('Name','CCSDS GMSK 评估','NumberTitle','off','Position',[100 100 1200 800]);

    subplot(2,3,1);
    plotIQTrajectory(ctx.fineSynced, 'GMSK 同步后 IQ 轨迹');

    subplot(2,3,2);
    phi = unwrap(angle(ctx.fineSynced(:)));
    L = min(3000, length(phi));
    if L > 0
        plot(phi(1:L), 'b');
        grid on; xlabel('样点索引'); ylabel('相位 (rad)');
        title('GMSK 相位轨迹');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,3);
    dphi = angle(ctx.fineSynced(2:end) .* conj(ctx.fineSynced(1:end-1)));
    L = min(3000, length(dphi));
    if L > 0
        plot(dphi(1:L), 'b');
        grid on; xlabel('样点索引'); ylabel('\Delta 相位 (rad)');
        title('GMSK 差分相位判决量');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,4);
    if ~isempty(dphi)
        histogram(dphi, 80);
        grid on; xlabel('\Delta 相位 (rad)'); ylabel('数量');
        title('GMSK 差分相位分布');
    else
        text(0.3,0.5,'无数据'); axis off;
    end

    subplot(2,3,5);
    [P1, fA] = pwelch(ctx.rxWaveform, [], [], 4096, ctx.Fs, 'centered');
    [P2, ~]  = pwelch(ctx.coarseSynced, [], [], 4096, ctx.Fs, 'centered');
    plot(fA/1e3, 10*log10(P1), 'r', 'LineWidth', 1.0); hold on;
    plot(fA/1e3, 10*log10(P2), 'b', 'LineWidth', 1.0);
    grid on; 
    legend('接收信号/含CFO','粗频偏校正后','Location','best');
    xlabel('频率 (kHz)'); ylabel('功率谱密度 (dB/Hz)');
    title('GMSK 频谱：CFO校正前后');

    subplot(2,3,6);
    vals = [res.BER, res.LockRate*100, res.PAPR_dB, res.EVM_post_pct, res.MER_dB];
    names = {'BER','锁帧率%','PAPR dB','包络误差%','包络MER dB'};
    bar(vals); set(gca,'XTickLabel',names); grid on;
    title('GMSK 核心指标');

    sgtitle(sprintf('GMSK | SNR=%.0fdB CFO=%.0fHz Phase=%.0f deg | BER=%.2e Lock=%.0f%%', ...
        res.snr_in, res.cfo_in, res.phase_in, res.BER, res.LockRate*100));
end

function plotIQTrajectory(sym, ttl)
    if isempty(sym)
        text(0.3,0.5,'no data'); axis off; return;
    end
    L = min(length(sym), 5000);
    s = sym(1:L);
    plot(real(s), imag(s), 'b.', 'MarkerSize', 4);
    axis equal; grid on; xlabel('I'); ylabel('Q'); title(ttl);
end

function plotConstellation(sym, refConst, ttl)
    if isempty(sym)
        text(0.3,0.5,'no data'); axis off; return;
    end
    L = min(length(sym), 1500);
    s = sym(end-L+1:end);
    plot(real(s), imag(s),'b.','MarkerSize',4); hold on;
    plot(real(refConst), imag(refConst),'rx','MarkerSize',12,'LineWidth',2);
    grid on; axis equal;
    lim = max(1.5, max(abs(s))*1.1);
    xlim([-lim lim]); ylim([-lim lim]);
    xlabel('I'); ylabel('Q'); title(ttl);
end

% =========================================================
% 接收链路损伤恢复管线图
% =========================================================
function plotPipeline(res, ctx, opt) 
    if contains(upper(string(res.modType)),'GMSK')
        plotGMSKPipeline(res, ctx, opt);
        return;
    end
    figure('Name','接收链路损伤恢复 (Pipeline)','NumberTitle','off','Position',[100 80 1500 720]);

    % --- 各阶段符号: 都归一到单位平均功率,1 sample/symbol ---
    s1 = normPwr(ctx.rxWaveform(1:ctx.sps:end));         % ① 信道损伤后(无任何同步)
    s2 = normPwr(ctx.coarseSynced(1:ctx.sps:end));       % ② 粗频偏后
    s3 = normPwr(ctx.TimeSynced);                        % ③ 定时同步后(还有相位旋转)
    s4 = ctx.fineSynced;                                 % ④ 载波同步后(已 best-rotation 对齐)

    stages = {s1, s2, s3, s4};
    titles = {'① 信道损伤后','② 粗频偏校正','③ 定时同步','④ 载波同步(终态)'};
    evms = zeros(1,4);
    for k = 1:4
        subplot(2,4,k);
        plotConstellation(stages{k}, ctx.refConst, titles{k});
        if ~isempty(stages{k})
            [evms(k), ~] = computeEVM(stages{k}, ctx.refConst);
        else
            evms(k) = NaN;
        end
        xlabel(sprintf('EVM=%.1f%%', evms(k)));
    end

    % --- 5: EVM 逐级条形 ---
    subplot(2,4,5);
    bar(evms,'FaceColor',[0.3 0.6 0.9]);
    set(gca,'XTickLabel',{'①','②','③','④'});
    ylabel('EVM (%)'); title('损伤逐级降低');
    grid on;
    yl = ylim; ylim([0, max(yl(2)*1.15, 5)]);
    for k = 1:4
        text(k, evms(k)+max(evms)*0.03, sprintf('%.1f', evms(k)), ...
             'HorizontalAlignment','center','FontSize',9);
    end

    % --- 6: 相位轨迹 (raw vs final) ---
    subplot(2,4,6);
    Lphase = min(1500, length(s1));
    if ~isempty(s1) && ~isempty(s4)
        Ls4 = min(Lphase, length(s4));
        plot(unwrap(angle(s1(1:Lphase))),'r','LineWidth',1.0); hold on;
        plot(unwrap(angle(s4(1:Ls4))),'b','LineWidth',1.2);
        legend('① 含 CFO/相偏','④ 同步后','Location','best');
    end
    grid on; xlabel('符号 idx'); ylabel('相位 (rad)');
    title(sprintf('相位轨迹 (输入 CFO=%+.0fHz)', res.cfo_in));

    % --- 7: 频谱 (Rx vs 粗频偏后) ---
    subplot(2,4,7);
    [P1, fA] = pwelch(ctx.rxWaveform,   [],[],1024,ctx.Fs,'centered');
    [P2, ~]  = pwelch(ctx.coarseSynced, [],[],1024,ctx.Fs,'centered');
    plot(fA/1e3, 10*log10(P1),'r','LineWidth',1.0); hold on;
    plot(fA/1e3, 10*log10(P2),'b','LineWidth',1.0);
    legend('Rx (含 CFO)','粗频偏后','Location','best');
    grid on; xlabel('频率 (kHz)'); ylabel('PSD (dB/Hz)');
    title('频域: CFO 校正前后');

    % --- 8: 总体压缩对比 ---
    subplot(2,4,8);
    barData = [evms(1), evms(4)];
    b = bar(barData); b.FaceColor='flat';
    b.CData(1,:) = [0.85 0.33 0.10];   % 红
    b.CData(2,:) = [0.20 0.65 0.40];   % 绿
    set(gca,'XTickLabel',{'同步前','同步后'});
    ylabel('EVM (%)');
    if evms(1) > 0
        ratio = evms(1)/max(evms(4),eps);
        title(sprintf('总压缩 %.1f%% → %.1f%%  (×%.0f)', evms(1), evms(4), ratio));
    else
        title('总压缩对比');
    end
    grid on;
    for k=1:2
        text(k, barData(k)+max(barData)*0.03, sprintf('%.1f', barData(k)), ...
             'HorizontalAlignment','center','FontSize',10);
    end

    sgtitle(sprintf('%s | 输入: SNR=%.0fdB CFO=%.0fHz Phase=%.0f° | 输出: BER=%.2e MER=%.1fdB Lock=%.0f%%', ...
        res.modType, res.snr_in, res.cfo_in, res.phase_in, ...
        res.BER, res.MER_dB, res.LockRate*100));
end

function plotGMSKPipeline(res, ctx, opt) %#ok<INUSD>
    figure('Name','GMSK 接收链路恢复过程','NumberTitle','off','Position',[100 80 1500 720]);

    s1 = normPwr(ctx.rxWaveform(1:ctx.sps:end));
    s2 = normPwr(ctx.coarseSynced(1:ctx.sps:end));
    s3 = normPwr(ctx.TimeSynced);
    s4 = normPwr(ctx.fineSynced);
    stages = {s1, s2, s3, s4};
    titles = {'① 接收IQ轨迹','② 粗频偏校正后','③ 定时同步后','④ 载波同步后'};
    evms = zeros(1,4);

    for k = 1:4
        subplot(2,4,k);
        plotIQTrajectory(stages{k}, titles{k});
        [evms(k), ~] = computeGMSKIQRoughMetrics(stages{k});
        xlabel(sprintf('包络误差=%.1f%%', evms(k)));
    end

    subplot(2,4,5);
    s = ctx.fineSynced(:);
    dphi = angle(s(2:end) .* conj(s(1:end-1)));
    if ~isempty(dphi)
        histogram(dphi, 80);
        grid on; xlabel('\Delta phase (rad)'); ylabel('Count');
        title('差分相位分布');
    else
        text(0.3,0.5,'no data'); axis off;
    end

    subplot(2,4,6);
    phi1 = unwrap(angle(s1(:)));
    phi4 = unwrap(angle(s4(:)));
    L1 = min(1500, length(phi1));
    L4 = min(1500, length(phi4));
    if L1 > 0, plot(phi1(1:L1),'r','LineWidth',1.0); hold on; end
    if L4 > 0, plot(phi4(1:L4),'b','LineWidth',1.2); end
    grid on; 
    legend('接收信号/含CFO相偏','同步后','Location','best');
    xlabel('样点索引');
    ylabel('相位 (rad)');
    title(sprintf('GMSK 相位轨迹 (输入CFO=%+.0fHz)', res.cfo_in));

    subplot(2,4,7);
    [P1, fA] = pwelch(ctx.rxWaveform, [], [], 4096, ctx.Fs, 'centered');
    [P2, ~]  = pwelch(ctx.coarseSynced, [], [], 4096, ctx.Fs, 'centered');
    plot(fA/1e3, 10*log10(P1),'r','LineWidth',1.0); hold on;
    plot(fA/1e3, 10*log10(P2),'b','LineWidth',1.0);
    legend('接收信号/含CFO','粗频偏校正后','Location','best');
    xlabel('频率 (kHz)');
    ylabel('功率谱密度 (dB/Hz)');
    title('频谱：CFO校正前后');

    subplot(2,4,8);
    vals = [res.BER, res.LockRate*100, res.PAPR_dB, evms(4)];
    names = {'BER','锁帧率%','PAPR dB','包络误差%'};
    bar(vals); set(gca,'XTickLabel',names); grid on;
    title('GMSK 核心指标');

    sgtitle(sprintf('GMSK | SNR=%.0fdB CFO=%.0fHz 相偏=%.0f° | BER=%.2e 锁帧=%.0f%%', ...
        res.snr_in, res.cfo_in, res.phase_in, res.BER, res.LockRate*100));
end

function y = normPwr(x)
    if isempty(x), y = x; return; end
    p = mean(abs(x).^2);
    if p > 0, y = x / sqrt(p); else, y = x; end
end

% =========================================================
% 损伤预算图: 输入损伤 vs 残余损伤
% =========================================================
function plotDamageBudget(res, ctx, opt) %#ok<INUSD>
    if contains(upper(string(res.modType)),'GMSK')
        return;
    end
    figure('Name','损伤预算 (Damage Budget)','NumberTitle','off','Position',[140 120 1100 460]);

    % --- 残余 CFO/相偏估计 (决策导向: 先把数据相位剥掉) ---
    % fineSynced 是 QPSK/8PSK 符号串,直接取 angle 会在数据相位簇之间跳,
    % unwrap 也救不回(因为跳变 < 2π),所以必须先除以最近理想星座点,
    % 得到的 s./ideal 相位才是纯净的"残余相位",再 polyfit 才有意义。
    s = ctx.fineSynced;
    residCFO_Hz = NaN; residPhase_deg = NaN; phErr = [];
    if ~isempty(s) && length(s) > 50
        L = min(length(s), 5000);
        s_use = s(end-L+1:end);                            % 用收敛后的尾段
        refC  = ctx.refConst(:).';
        [~, idx] = min(abs(s_use - refC), [], 2);
        ideal = ctx.refConst(idx);
        phErr = unwrap(angle(s_use ./ ideal));             % 残余相位误差,接近 0 附近
        n = (0:L-1).';
        fSym = ctx.Fs / ctx.sps;
        coef = polyfit(n, phErr, 1);
        residCFO_Hz   = coef(1) * fSym / (2*pi);           % 斜率 → 残余频偏
        residPhase_deg = rad2deg(coef(2));                 % 截距 → 残余常相位
    end

    % --- 子图 1: CFO 输入 vs 残余 ---
    subplot(1,3,1);
    barCFO = [abs(res.cfo_in), abs(residCFO_Hz)];
    b = bar(barCFO); b.FaceColor='flat';
    b.CData(1,:) = [0.85 0.33 0.10];
    b.CData(2,:) = [0.20 0.65 0.40];
    set(gca,'XTickLabel',{'输入 CFO','残余 CFO'});
    ylabel('|频偏| (Hz)'); grid on;
    if barCFO(1) > 0
        title(sprintf('CFO 抑制  %.0fHz → %.1fHz  (×%.0f)', barCFO(1), barCFO(2), barCFO(1)/max(barCFO(2),eps)));
    else
        title('CFO 抑制 (输入=0)');
    end
    ylim([0, chooseBudgetAxisMax(barCFO, 1)]);
    for k=1:2, text(k, barCFO(k)+max(barCFO)*0.03, sprintf('%.1f', barCFO(k)), 'HorizontalAlignment','center'); end

    % --- 子图 2: 相位偏置 输入 vs 残余 ---
    subplot(1,3,2);
    barPh = [abs(res.phase_in), abs(residPhase_deg)];
    b = bar(barPh); b.FaceColor='flat';
    b.CData(1,:) = [0.85 0.33 0.10];
    b.CData(2,:) = [0.20 0.65 0.40];
    set(gca,'XTickLabel',{'输入相偏','残余相偏'});
    ylabel('|相位| (deg)'); grid on;
    if barPh(1) > 0
        title(sprintf('相偏抑制  %.1f° → %.2f°', barPh(1), barPh(2)));
    else
        title('相偏抑制 (输入=0)');
    end
    ylim([0, chooseBudgetAxisMax(barPh, 1)]);
    for k=1:2, text(k, barPh(k)+max(barPh)*0.03, sprintf('%.2f', barPh(k)), 'HorizontalAlignment','center'); end

    % --- 子图 3: 整体性能与噪声底 ---
    subplot(1,3,3);
    snrInput = res.snr_in;
    snrPostMF_theory = snrInput + 10*log10(ctx.sps);   % 匹配滤波处理增益
    snrPostMF_meas   = res.SNR_est_dB;
    barSNR = [snrInput, snrPostMF_theory, snrPostMF_meas];
    b = bar(barSNR); b.FaceColor='flat';
    b.CData(1,:) = [0.50 0.50 0.50];
    b.CData(2,:) = [0.30 0.50 0.85];
    b.CData(3,:) = [0.20 0.65 0.40];
    set(gca,'XTickLabel',{'输入 SNR','理论 MF 增益后','实测 SNR_{est}'});
    ylabel('SNR (dB)'); grid on;
    title(sprintf('噪声底  (BER=%.2e)', res.BER));
    for k=1:3, text(k, barSNR(k)+max(abs(barSNR))*0.03, sprintf('%.1f', barSNR(k)), 'HorizontalAlignment','center'); end

    sgtitle(sprintf('损伤预算: 输入 vs 残余  (%s, 锁帧率=%.0f%%)', res.modType, res.LockRate*100));
end

function ymax = chooseBudgetAxisMax(vals, minScale)
    vals = vals(isfinite(vals));
    if isempty(vals)
        ymax = minScale;
        return;
    end

    vmax = max(abs(vals));
    if vmax <= 0
        ymax = minScale;
    else
        ymax = max(minScale, vmax * 1.2);
    end
end

% =========================================================
% BER vs SNR 扫描
% =========================================================
function metrics = doSNRSweep(opt)
    snrs = opt.snrSweep;
    bers = nan(size(snrs));
    evms = nan(size(snrs));
    mers = nan(size(snrs));
    fprintf('\n[SNR Sweep] %s, points = %d\n', opt.modType, numel(snrs));
    for k = 1:numel(snrs)
        opt2 = opt; opt2.snr = snrs(k); opt2 = rmfield(opt2,'snrSweep');
        r = runOneShot(opt2);
        bers(k)=r.BER; evms(k)=r.EVM_post_pct; mers(k)=r.MER_dB;
        fprintf('  SNR=%5.1f dB  BER=%.4e  EVM=%.2f%%  MER=%.2fdB\n', ...
                snrs(k), bers(k), evms(k), mers(k));
    end
    figure('Name','SNR 扫描','NumberTitle','off','Position',[120 120 900 400]);
    subplot(1,2,1);
    semilogy(snrs, max(bers,1e-6),'o-','LineWidth',1.5);
    grid on; xlabel('SNR (dB)'); ylabel('BER'); title(sprintf('%s BER vs SNR', opt.modType));
    subplot(1,2,2);
    yyaxis left;  plot(snrs, evms,'o-'); ylabel('EVM (%)');
    yyaxis right; plot(snrs, mers,'s-'); ylabel('MER (dB)');
    xlabel('SNR (dB)'); grid on; title('EVM / MER vs SNR');
    metrics = struct('snr',snrs,'BER',bers,'EVM',evms,'MER',mers);
end

% =========================================================
% 给前端打包数据: 频谱 / 星座 / 4 阶段管线 / 残余损伤
% =========================================================
function fe = buildFrontendArrays(ctx, res) %#ok<INUSD>
    Fs = ctx.Fs; sps = ctx.sps;
    isGMSKMod = contains(upper(string(res.modType)),'GMSK');

    % --- 频谱 (Tx + Rx, 1024 点, 中心对称) ---
    [Pxx_tx, f_axis] = pwelch(ctx.txWaveform, [], [], 1024, Fs, 'centered');
    [Pxx_rx, ~]      = pwelch(ctx.rxWaveform, [], [], 1024, Fs, 'centered');
    fe.spectrum = struct( ...
        'f',    reshape(f_axis,            1, []), ...
        'p_tx', reshape(10*log10(Pxx_tx),  1, []), ...
        'p_rx', reshape(10*log10(Pxx_rx),  1, []));

    % --- 星座: 修复前 (raw, 信道损伤后, 无任何同步) ---
    fe.constRaw  = sampleConst(ctx.rawSym,     1500);
    % --- 星座: 修复后 (载波同步对齐到参考相位) ---
    fe.constSync = sampleConst(ctx.fineSynced, 1500);

    % --- 4 阶段管线星座 (供前端做"损伤逐级被吃掉"的展示) ---
    s1 = normPwr(ctx.rxWaveform(1:sps:end));     % ① 信道损伤后
    s2 = normPwr(ctx.coarseSynced(1:sps:end));   % ② 粗频偏后
    s3 = normPwr(ctx.TimeSynced);                % ③ 定时同步后
    s4 = ctx.fineSynced;                         % ④ 载波同步后(终态)

    % 各阶段 EVM (相对参考星座)
    if isGMSKMod
        [evm1,~] = computeGMSKIQRoughMetrics(s1);
        [evm2,~] = computeGMSKIQRoughMetrics(s2);
        [evm3,~] = computeGMSKIQRoughMetrics(s3);
        [evm4,~] = computeGMSKIQRoughMetrics(s4);
    else
        [evm1,~] = computeEVM(s1, ctx.refConst);
        [evm2,~] = computeEVM(s2, ctx.refConst);
        [evm3,~] = computeEVM(s3, ctx.refConst);
        [evm4,~] = computeEVM(s4, ctx.refConst);
    end

    fe.pipeline = struct( ...
        'stage1',     sampleConst(s1, 800), ...
        'stage2',     sampleConst(s2, 800), ...
        'stage3',     sampleConst(s3, 800), ...
        'stage4',     sampleConst(s4, 800), ...
        'evms',       [evm1, evm2, evm3, evm4], ...
        'labels',     {{'信道损伤后','粗频偏后','定时同步后','载波同步后'}});

    % --- 残余 CFO / 相偏 (决策导向: 剥掉数据相位再线性回归) ---
    fe.residCFO = NaN; fe.residPhase = NaN;
    s = ctx.fineSynced;
    if isGMSKMod && ~isempty(s) && length(s) > 50
        L = min(length(s), 5000);
        s_use = s(end-L+1:end);
        ph = unwrap(angle(s_use));
        n = (0:L-1).';
        fSym = Fs / sps;
        coef = polyfit(n, ph, 1);
        fe.residCFO   = coef(1) * fSym / (2*pi);
        fe.residPhase = rad2deg(coef(2));
    elseif ~isempty(s) && length(s) > 50
        L = min(length(s), 5000);
        s_use = s(end-L+1:end);
        refC  = ctx.refConst(:).';
        [~, idx] = min(abs(s_use - refC), [], 2);
        ideal = ctx.refConst(idx);
        phErr = unwrap(angle(s_use ./ ideal));
        n = (0:L-1).';
        fSym = Fs / sps;
        coef = polyfit(n, phErr, 1);
        fe.residCFO   = coef(1) * fSym / (2*pi);
        fe.residPhase = rad2deg(coef(2));
    end
end

function out = sampleConst(s, Lmax)
    if isempty(s), out = struct('i', [], 'q', []); return; end
    s = s(:);
    if length(s) > Lmax, s = s(end-Lmax+1:end); end
    out = struct('i', reshape(real(s),1,[]), 'q', reshape(imag(s),1,[]));
end

function tf = useFACMEvaluation(opt, modStr)
    tf = isfield(opt,'acmFormat') || contains(upper(string(modStr)),'APSK');
end

function [res, ctx] = runFACMOneShot(opt, fSym, sps)
    acmFmt = resolveFACMFormat(opt);
    snr_val = getf(opt,'snr',20);
    cfo_val = getf(opt,'cfo',0);
    delay_val = getf(opt,'delay',0);
    phase_deg = getf(opt,'phaseOffset',0);

    cfg = struct();
    cfg.SamplesPerSymbol = sps;
    cfg.NumBytesInTransferFrame = 1115;
    cfg.RolloffFactor = getf(opt,'RolloffFactor',0.35);
    cfg.FilterSpanInSymbols = 10;
    cfg.ScramblingCodeNumber = 1;
    cfg.HasPilots = getLogicalField(opt,'hasPilots',true);
    cfg.PulseShapingFilter = 'Root Raised Cosine';
    cfg.ACMFormat = acmFmt;

    simParams = struct();
    simParams.SymbolRate = fSym;
    simParams.SPS = sps;
    simParams.EsNodB = snr_val + 10*log10(sps);
    simParams.CFO = cfo_val;
    simParams.DisableCFO = (cfo_val == 0);
    simParams.SRO = 0;
    simParams.DisableSRO = true;
    simParams.PeakDoppler = 0;
    simParams.DopplerRate = 0;
    simParams.DisableDoppler = true;
    simParams.DisablePhaseNoise = true;
    simParams.DisableRFImpairments = false;
    simParams.InitalSyncFrames = getf(opt,'facmWarmupFrames',7);
    simParams.NumFramesForBER = getf(opt,'facmBERFrames',100);
    simParams.NumPLFrames = simParams.InitalSyncFrames + simParams.NumFramesForBER;
    simParams.AttenuationFactor = 1;

    [bits, txWaveform, rxIn, phyParams, rxParams] = HelperCCSDSFACMRxInputGenerate(cfg, simParams);

    if delay_val ~= 0
        varDelay = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        rxWaveform = varDelay(rxIn, delay_val);
    else
        rxWaveform = rxIn;
    end
    if phase_deg ~= 0
        rxWaveform = rxWaveform .* exp(1j*deg2rad(phase_deg));
    end

    Fs = fSym*sps;
    [fineSynced, payloadSym, decodedTFBits, rxWork, syncSym, decodedFrames, snrFrame] = ...
        facmReceiveAndDecode(rxWaveform, cfg, rxParams, phyParams, simParams, fSym, acmFmt);

    refConst = HelperCCSDSFACMReferenceConstellation(acmFmt);
    refConst = refConst(:) / sqrt(mean(abs(refConst(:)).^2));

    rawSym = rxWaveform(1:sps:end);
    rawSym = normPwr(rawSym);
    fineSynced = normPwr(fineSynced);
    payloadSym = normPwr(payloadSym);

    [berVal, lockRate] = computeFACMBER(decodedTFBits, bits, simParams, decodedFrames);
    [evm_pre, ~] = computeEVM(rawSym, refConst);
    [evm_post, mer_post] = computeEVM(fineSynced, refConst);
    snr_est = computeSNRest(fineSynced, refConst);
    if isfinite(snrFrame) && snrFrame > 0
        snr_est = 10*log10(snrFrame);
    end
    papr_dB = 10*log10(max(abs(txWaveform).^2)/mean(abs(txWaveform).^2));

    res = struct();
    res.modType = facmModulationName(acmFmt);
    res.ACMFormat = acmFmt;
    res.CodeRate = facmCodeRate(acmFmt);
    res.snr_in = snr_val;
    res.cfo_in = cfo_val;
    res.phase_in = phase_deg;
    res.delay_in = delay_val;
    res.BER = berVal;
    res.EVM_pre_pct = evm_pre;
    res.EVM_post_pct = evm_post;
    res.MER_dB = mer_post;
    res.SNR_est_dB = snr_est;
    res.PAPR_dB = papr_dB;
    res.LockRate = lockRate;
    res.Fs = Fs;

    ctx.txWaveform = txWaveform;
    ctx.rxWaveform = rxWaveform;
    ctx.coarseSynced = rxWork;
    ctx.TimeSynced = syncSym;
    ctx.fineSynced = fineSynced;
    ctx.rawSym = rawSym;
    ctx.refConst = refConst;
    ctx.Fs = Fs;
    ctx.sps = sps;
    ctx.bestRot = 0;
end

function [fineSynced, payloadAll, decodedTFBits, filteredRx, syncSym, decodedFrames, snrMean] = facmReceiveAndDecode(rxWaveform, cfg, rxParams, phyParams, simParams, fSym, acmFmt)
    sps = cfg.SamplesPerSymbol;
    rrcfilt = comm.RaisedCosineReceiveFilter( ...
        'RolloffFactor', cfg.RolloffFactor, ...
        'FilterSpanInSymbols', cfg.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol', sps, ...
        'DecimationFactor', 1);
    b = coeffs(rrcfilt);
    rrcfilt.Gain = sum(b.Numerator);

    Kp = 1/(pi*(1-((cfg.RolloffFactor^2)/4)))*sin(pi*cfg.RolloffFactor/2);
    symsyncobj = comm.SymbolSynchronizer( ...
        'DampingFactor', 1/sqrt(2), ...
        'DetectorGain', Kp, ...
        'TimingErrorDetector', 'Gardner (non-data-aided)', ...
        'Modulation', 'PAM/PSK/QAM', ...
        'NormalizedLoopBandwidth', 0.005, ...
        'SamplesPerSymbol', sps);

    filteredRx = rrcfilt(rxWaveform);
    [syncSym, ~] = symsyncobj(filteredRx);
    syncidx = HelperCCSDSFACMFrameSync(syncSym, rxParams.RefFM);

    fineSynced = [];
    payloadAll = [];
    decodedTFBits = [];
    decodedFrames = 0;
    snrVals = [];
    if isempty(syncidx)
        snrMean = NaN;
        return;
    end

    fll = HelperCCSDSFACMFLL('SampleRate', fSym, 'K1', 0.17, 'K2', 0);
    fineCFOSync = comm.PhaseFrequencyOffset('SampleRate', fSym);
    G = 1;
    currentIdx = syncidx(1);
    frameIndex = 1;
    plFrameSize = rxParams.plFrameSize;
    scrambler = rxParams.PLRandomSymbols(:);
    extraBits = [];
    numIter = 3;

    while (currentIdx + plFrameSize - 1) <= length(syncSym)
        oneFrame = syncSym(currentIdx:(currentIdx + plFrameSize - 1));
        [fllOut, ~] = fll(oneFrame);
        cfoEst = HelperCCSDSFACMFMFrequencyEstimate(fllOut(1:256), rxParams.RefFM, fSym);
        fineCFOSync.FrequencyOffset = -cfoEst;
        cfoCorrected = fineCFOSync(fllOut);

        frameSNR = HelperCCSDSFACMSNREstimate(cfoCorrected(1:256), rxParams.RefFM);
        if ~isfinite(frameSNR) || frameSNR <= 0
            frameSNR = 10^(20/10);
        end
        snrVals(end+1,1) = frameSNR; %#ok<AGROW>

        if cfg.HasPilots
            try
                [payload, frameDescriptor] = HelperCCSDSFACMPhaseRecovery(cfoCorrected, rxParams.PilotSeq, rxParams.RefFM);
                agcIn = [frameDescriptor; payload];
                [agcOut, G] = HelperDigitalAutomaticGainControl(agcIn, frameSNR, G);
                payload = agcOut(65:end);
                fineSynced = [fineSynced; agcOut]; %#ok<AGROW>
            catch
                payload = cfoCorrected(321:min(end,320+8100*16));
                [payload, G] = HelperDigitalAutomaticGainControl(payload, frameSNR, G);
                fineSynced = [fineSynced; payload]; %#ok<AGROW>
            end
        else
            phaseFixed = compensateFACMFrameMarkerPhase(cfoCorrected, rxParams.RefFM);
            [agcOut, G] = HelperDigitalAutomaticGainControl(phaseFixed, frameSNR, G);
            payload = agcOut(321:min(end,320+8100*16));
            fineSynced = [fineSynced; agcOut]; %#ok<AGROW>
        end

        payload = payload(:);
        if length(payload) >= 8100*16
            payload = payload(1:8100*16);
            payloadDescrambled = payload .* conj(scrambler(1:length(payload)));
            payloadAll = [payloadAll; payloadDescrambled]; %#ok<AGROW>
            nVar = max(1/frameSNR, 1e-6);
            fullFrameDecoded = zeros(16*phyParams.K,1);
            for iBlk = 1:16
                idx = (iBlk-1)*8100 + (1:8100);
                softBits = HelperCCSDSFACMDemodulate(payloadDescrambled(idx), acmFmt, nVar);
                decoded = HelperSCCCDecode(softBits(:), acmFmt, numIter);
                fullFrameDecoded((iBlk-1)*phyParams.K+1:iBlk*phyParams.K) = decoded;
            end

            try
                [fdACMFormat, fdHasPilots, decFail] = HelperCCSDSFACMFDRecover(fineSynced(end-length(payload)-63:end-length(payload)));
            catch
                fdACMFormat = acmFmt;
                fdHasPilots = cfg.HasPilots;
                decFail = false;
            end

            if ~decFail && fdACMFormat == acmFmt && fdHasPilots == cfg.HasPilots
                [~, decodedBuffer, extraBits] = HelperCCSDSFACMTFSynchronize( ...
                    [extraBits; fullFrameDecoded], phyParams.ASM, phyParams.NumInputBits);
                if ~isempty(decodedBuffer)
                    prnSeq = satcom.internal.ccsds.tmrandseq(phyParams.NumInputBits);
                    finalBits = xor(decodedBuffer(33:end,:) > 0, prnSeq);
                    if frameIndex > simParams.InitalSyncFrames
                        decodedTFBits = [decodedTFBits, finalBits]; %#ok<AGROW>
                    end
                end
            end
            decodedFrames = decodedFrames + 1;
        end

        currentIdx = currentIdx + plFrameSize;
        frameIndex = frameIndex + 1; %#ok<NASGU>
    end

    if isempty(payloadAll)
        payloadAll = fineSynced;
    end
    if isempty(snrVals)
        snrMean = NaN;
    else
        snrMean = mean(snrVals);
    end
end

function y = compensateFACMFrameMarkerPhase(x, refFM)
    y = x;
    if length(x) < 256
        return;
    end
    Tm0 = angle(sum(x(1:16).*conj(refFM(1:16))));
    Tm1 = angle(sum(x(241:256).*conj(refFM(end-15:end))));
    phases = wrapToPi(Tm0 + (wrapToPi(Tm1-Tm0)/257)*(1:length(x)));
    y = x(:).*exp(-1j*phases(:));
end

function [berVal, lockRate] = computeFACMBER(decodedTFBits, txBits, simParams, decodedFrames)
    berVal = 0.5;
    lockRate = min(1, decodedFrames/max(simParams.NumFramesForBER,1));
    if isempty(decodedTFBits)
        lockRate = 0;
        return;
    end

    berinfo = struct('NumBitsInError',0,'TotalNumBits',0,'BitErrorRate',0);
    berinfo = HelperBitErrorRate(txBits, decodedTFBits, berinfo);
    berVal = berinfo.BitErrorRate;
end

function acmFmt = resolveFACMFormat(opt)
    if isfield(opt,'acmFormat')
        acmFmt = double(opt.acmFormat);
    else
        modStr = upper(string(opt.modType));
        if contains(modStr,'64APSK')
            acmFmt = 24;
        elseif contains(modStr,'32APSK')
            acmFmt = 21;
        elseif contains(modStr,'16APSK')
            acmFmt = 14;
        elseif contains(modStr,'8PSK')
            acmFmt = 9;
        else
            acmFmt = 3;
        end
    end
    acmFmt = max(1, min(27, round(acmFmt)));
end

function name = facmModulationName(acmFmt)
    mVals = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
    switch mVals(acmFmt)
        case 2
            name = 'QPSK';
        case 3
            name = '8PSK';
        case 4
            name = '16APSK';
        case 5
            name = '32APSK';
        otherwise
            name = '64APSK';
    end
end

function r = facmCodeRate(acmFmt)
    mVals = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
    kVals = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
        19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
        35998;33358;35998;38638;41038;43678];
    r = kVals(acmFmt)/(mVals(acmFmt)*8100);
end

function v = getLogicalField(s, name, defv)
    if isfield(s,name) && ~isempty(s.(name))
        v = logical(s.(name));
    else
        v = defv;
    end
end

function code = canonicalChannelCoding(value)
    key = lower(strtrim(string(value)));
    switch key
        case {'none','no','off'}
            code = 'none';
        case {'rs','reed-solomon','reed solomon'}
            code = 'RS';
        case {'convolutional','conv'}
            code = 'convolutional';
        case {'concatenated','concat','rs+conv','rs-conv'}
            code = 'concatenated';
        case {'turbo'}
            code = 'turbo';
        case {'ldpc'}
            code = 'LDPC';
        otherwise
            code = char(value);
    end
end

function args = appendRSArgs(args, opt)
    if isfield(opt,'RSMessageLength') && ~isempty(opt.RSMessageLength)
        args = [args, {'RSMessageLength', double(opt.RSMessageLength)}];
    end
    if isfield(opt,'RSInterleavingDepth') && ~isempty(opt.RSInterleavingDepth)
        args = [args, {'RSInterleavingDepth', double(opt.RSInterleavingDepth)}];
    end
    if isfield(opt,'IsRSMessageShortened') && ~isempty(opt.IsRSMessageShortened)
        args = [args, {'IsRSMessageShortened', logical(opt.IsRSMessageShortened)}];
    end
    if isfield(opt,'RSShortenedMessageLength') && ~isempty(opt.RSShortenedMessageLength)
        args = [args, {'RSShortenedMessageLength', double(opt.RSShortenedMessageLength)}];
    end
end

function r = codeRateNum(opt)
    r = 1.0;
    if isfield(opt,'acmFormat')
        acmFmt = double(opt.acmFormat);
        mVals = [2;2;2;2;2;2;3;3;3;3;3;3;4;4;4;4;4;5;5;5;5;5;6;6;6;6;6];
        kVals = [5758;6958;8398;9838;11278;13198;11278;13198;14878;17038;...
            19198;21358;19198;21358;23518;25918;28318;25918;28318;30958;33358;...
            35998;33358;35998;38638;41038;43678];
        if acmFmt >= 1 && acmFmt <= numel(kVals)
            r = kVals(acmFmt)/(mVals(acmFmt)*8100);
            return;
        end
    end
    rateStr = '';
    if isfield(opt,'ConvolutionalCodeRate'), rateStr = char(opt.ConvolutionalCodeRate);
    elseif isfield(opt,'CodeRate'),          rateStr = char(opt.CodeRate);
    end
    convRate = rateStringToNum(rateStr);
    if isfield(opt,'channelCoding')
        code = canonicalChannelCoding(opt.channelCoding);
        if any(strcmp(code, {'RS','concatenated'}))
            rsK = 239;
            if isfield(opt,'RSMessageLength') && ~isempty(opt.RSMessageLength)
                rsK = double(opt.RSMessageLength);
            end
            rsShortK = rsK;
            if isfield(opt,'RSShortenedMessageLength') && ~isempty(opt.RSShortenedMessageLength)
                rsShortK = double(opt.RSShortenedMessageLength);
            end
            isShortened = false;
            if isfield(opt,'IsRSMessageShortened') && ~isempty(opt.IsRSMessageShortened)
                isShortened = logical(opt.IsRSMessageShortened);
            end
            if isShortened
                rsRate = rsShortK / (255 - rsK + rsShortK);
            else
                rsRate = rsK / 255;
            end
            if strcmp(code,'concatenated')
                r = rsRate * convRate;
            else
                r = rsRate;
            end
            return;
        end
    end
    if convRate > 0
        r = convRate;
        return;
    end
end

function r = rateStringToNum(rateStr)
    switch rateStr
        case '1/2', r = 0.5;
        case '2/3', r = 2/3;
        case '3/4', r = 3/4;
        case '5/6', r = 5/6;
        case '7/8', r = 7/8;
        case '1/3', r = 1/3;
        case '1/4', r = 1/4;
        case '1/6', r = 1/6;
        case '4/5', r = 4/5;
        otherwise,  r = 0;
    end
end
