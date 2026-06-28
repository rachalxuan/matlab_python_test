function metrics = run_ccsds_tm_evaluation(params)
% RUN_CCSDS_TM_EVALUATION  独立评估副本
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
% p = struct('modType','QPSK','symbolRate',1e6,'sps',8, ...
%            'snr',20,'cfo',2000,'phaseOffset',15,'delay',0.2, ...
%            'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%            'RolloffFactor',0.35,'hasASM',true,'hasRandomizer',true, ...
%            'NumBytesInTransferFrame',1115, ...
%            'SpacecraftID',1,'VirtualChannelID',0, ...
%            'HasSecondaryHeader',false,'HasOCF',false,'HasFECF',false, ...
%            'showFigures',false);
% p.debugTMFrame = true;
% m = run_ccsds_tm_evaluation(p);

%   2) 用前端的 JSON 直接粘进来调（验一致性）
%   m = run_ccsds_tm_evaluation('{"modType":"QPSK","symbolRate":1e6,"sps":8,"snr":12,"cfo":0,"phaseOffset":0,"channelCoding":"none","RolloffFactor":0.35}');
%

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
    % ======== Single point simulation ========
    [res, ctx] = runOneShot(opt);
    res = attachResidualMetrics(res, ctx);

    % showFigures 默认 true; 矩阵测试或前端调用时设 false 跳过出图
    showFigures = false;
    if isfield(opt,'showFigures'), showFigures = logical(opt.showFigures); end

    printMetrics(res, opt);
    if showFigures
        ccsdsEvalPlotFigures('summary', res, ctx, opt);
        if getLogicalField(opt, 'showPipelineFigure', true)
            ccsdsEvalPlotFigures('pipeline', res, ctx, opt);
        end
        if getLogicalField(opt, 'showDamageBudgetFigure', false)
            ccsdsEvalPlotFigures('damageBudget', res, ctx, opt);
        end
    end

    % ======== Frontend plot arrays: spectrum / constellation / pipeline ========
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
    elseif isfield(opt,'CodeRate'),          rateStr = char(opt.CodeRate);
    elseif isfield(opt,'TPCCodeRate'),       rateStr = char(opt.TPCCodeRate);
    elseif isfield(opt,'tpcCodeRate'),       rateStr = char(opt.tpcCodeRate); end
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
    if isfield(res,'FER'), frontResult.FER = res.FER; end
    if isfield(res,'FrameErrorRate'), frontResult.FrameErrorRate = res.FrameErrorRate; end
    if isfield(res,'FrameErrors'), frontResult.FrameErrors = res.FrameErrors; end
    if isfield(res,'CountedFrames'), frontResult.CountedFrames = res.CountedFrames; end
    if isfield(res,'MatchedFrames'), frontResult.MatchedFrames = res.MatchedFrames; end
    if isfield(res,'DecodedFrames'), frontResult.DecodedFrames = res.DecodedFrames; end
    if isfield(res,'AcquisitionFrames'), frontResult.AcquisitionFrames = res.AcquisitionFrames; end
    if isfield(res,'AcquisitionTime_s'), frontResult.AcquisitionTime_s = res.AcquisitionTime_s; end
    frontResult.Fs           = res.Fs;
    if isfield(res,'cfo_est_Hz'),    frontResult.cfo_est_Hz = res.cfo_est_Hz; end
    if isfield(res,'IFHz'),          frontResult.IFHz = res.IFHz; end
    if isfield(res,'centerFrequencyHz'), frontResult.centerFrequencyHz = res.centerFrequencyHz; end
    if isfield(res,'carrierFreqHz'), frontResult.carrierFreqHz = res.carrierFreqHz; end
    if isfield(res,'ACMFormat'), frontResult.ACMFormat = res.ACMFormat; end
    if isfield(res,'fmDetectedFrames'), frontResult.fmDetectedFrames = res.fmDetectedFrames; end
    if isfield(res,'fmTotalFrames'),    frontResult.fmTotalFrames = res.fmTotalFrames; end

    % --- 输入回显 ---
    frontResult.snr_in   = res.snr_in;
    frontResult.cfo_in   = res.cfo_in;
    frontResult.phase_in = res.phase_in;
    frontResult.delay_in = res.delay_in;

    % --- 残余损伤 (同步链路压制后的剩余) ---
    frontResult.residCFO_Hz    = getfieldnumeric(res, 'residCFO_Hz', NaN);
    frontResult.residPhase_deg = getfieldnumeric(res, 'residPhase_deg', NaN);
    frontResult.ResidualCFO_Hz = getfieldnumeric(res, 'ResidualCFO_Hz', NaN);
    frontResult.ResidualPhase_deg = getfieldnumeric(res, 'ResidualPhase_deg', NaN);
    frontResult.ResidualCFO_valid = isfinite(frontResult.ResidualCFO_Hz);
    frontResult.ResidualPhase_valid = isfinite(frontResult.ResidualPhase_deg);

    % --- 前端绘图数据 (这是之前没传, 前端拿不到的) ---
    frontResult.spectrum             = fe.spectrum;
    frontResult.constellation_tx     = fe.constTx;
    frontResult.constellation_raw    = fe.constRaw;
    frontResult.constellation_synced = fe.constSync;
    frontResult.pipeline             = fe.pipeline;   % 4 阶段星座 + 标签

    % --- 编码信息透传 ---
    if isfield(opt,'ConvolutionalCodeRate'), frontResult.ConvolutionalCodeRate = opt.ConvolutionalCodeRate; end
    if isfield(opt,'TPCCodeRate'), frontResult.TPCCodeRate = opt.TPCCodeRate;
    elseif isfield(opt,'tpcCodeRate'), frontResult.TPCCodeRate = opt.tpcCodeRate; end
    if isfield(opt,'TPCBlocksPerTF'), frontResult.TPCBlocksPerTF = opt.TPCBlocksPerTF;
    elseif isfield(opt,'tpcBlocksPerTF'), frontResult.TPCBlocksPerTF = opt.tpcBlocksPerTF; end
    if isfield(res,'CodeRate'), frontResult.CodeRate = res.CodeRate;
    elseif isfield(opt,'CodeRate') && ~strcmp(char(opt.CodeRate),'N/A'), frontResult.CodeRate = opt.CodeRate; end
    if isfield(opt,'channelCoding'),         frontResult.channelCoding = opt.channelCoding; end

    % --- 时间 + stats 嵌套 (兼容 server.py 读 stats.matlabTime + 旧 main 格式) ---
    elapsed = toc(tStart);
    frontResult.ElapsedTime = elapsed;
    frontResult.stats = struct( ...
        'Fs',          res.Fs, ...
        'CodeRate',    realRate, ...
        'centerFrequencyHz', getCenterFrequencyHz(res, 0), ...
        'IFHz',        getCenterFrequencyHz(res, 0), ...
        'FER',         getfieldnumeric(frontResult, 'FER', NaN), ...
        'ResidualCFO_Hz', getfieldnumeric(frontResult, 'ResidualCFO_Hz', NaN), ...
        'ResidualCFO_valid', isfinite(getfieldnumeric(frontResult, 'ResidualCFO_Hz', NaN)), ...
        'ResidualPhase_deg', getfieldnumeric(frontResult, 'ResidualPhase_deg', NaN), ...
        'ResidualPhase_valid', isfinite(getfieldnumeric(frontResult, 'ResidualPhase_deg', NaN)), ...
        'AcquisitionFrames', getfieldnumeric(frontResult, 'AcquisitionFrames', NaN), ...
        'AcquisitionTime_s', getfieldnumeric(frontResult, 'AcquisitionTime_s', NaN), ...
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
    randomizerModeRaw = getfieldwithdefault(opt, 'RandomizerMode', 'standard');
    randomizerMode = lower(strtrim(char(randomizerModeRaw)));
    validRandomizerModes = {'standard','beforecoding','aftercoding','bypass'};
    if ~any(strcmp(randomizerMode, validRandomizerModes))
        error('run_ccsds_tm_evaluation:InvalidRandomizerMode', ...
            'Unsupported RandomizerMode="%s". Use standard, beforeCoding, afterCoding, or bypass.', ...
            randomizerMode);
    end

    if strcmp(randomizerMode, 'bypass')
        hasRandomizer = false;
    end

    if isfield(opt,'channelCoding')
        initialCodeStr = canonicalChannelCoding(opt.channelCoding);
    else
        initialCodeStr = 'none';
    end
    initialCodeKey = lower(string(initialCodeStr));
    tpcBlocksPerTF = 1;
    if isfield(opt,'TPCBlocksPerTF') && ~isempty(opt.TPCBlocksPerTF)
        tpcBlocksPerTF = max(1, round(makeNum(opt.TPCBlocksPerTF)));
    elseif isfield(opt,'tpcBlocksPerTF') && ~isempty(opt.tpcBlocksPerTF)
        tpcBlocksPerTF = max(1, round(makeNum(opt.tpcBlocksPerTF)));
    end

    numBytesTF = 1115;
    if isfield(opt,'NumBytesInTransferFrame') && ~isempty(opt.NumBytesInTransferFrame)
        numBytesTF = double(opt.NumBytesInTransferFrame);
    end
    if contains(initialCodeKey, 'tpc')
        tpcPayloadBits = localTPCPayloadBits(localTPCCodeRateValue(opt));
        tpcTFBits = tpcPayloadBits * tpcBlocksPerTF;
        if mod(tpcTFBits, 8) ~= 0
            error('run_ccsds_tm_evaluation:TPCFrameLengthNotOctetAligned', ...
                'TPC frame length is not byte aligned: payloadBits=%d, TPCBlocksPerTF=%d.', ...
                tpcPayloadBits, tpcBlocksPerTF);
        end
        numBytesTF = tpcTFBits / 8;
        opt.NumBytesInTransferFrame = numBytesTF;
        opt.TPCBlocksPerTF = tpcBlocksPerTF;
        fprintf('[TPC TF setup] TPCBlocksPerTF=%d, TPC payload=%d bits, NumBytesInTransferFrame=%d\n', ...
            tpcBlocksPerTF, tpcPayloadBits, numBytesTF);
    end

    args = {'SamplesPerSymbol', sps, 'HasRandomizer', hasRandomizer, 'HasASM', hasASM};
    if ~strcmp(randomizerMode, 'standard')
        args = [args, {'RandomizerMode', char(randomizerMode)}];
    end
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
        usesTransferFrameBytes = any(strcmp(codeKey, ["none", "convolutional", "tpc"])) || isLDPCOnSMTF;
        if usesTransferFrameBytes
            args = [args, {'NumBytesInTransferFrame', numBytesTF}];
        end
        args = [args, {'ChannelCoding', codeStr}];
        args = appendRSArgs(args, opt);

        pcmFormatAdded = false;
        if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
            args = [args, {'PCMFormat', string(opt.PCMFormat)}];
            pcmFormatAdded = true;
        end
        
        if contains(codeKey,'convolutional') && isfield(opt,'ConvolutionalCodeRate')
            rate = char(opt.ConvolutionalCodeRate);
            if ~strcmp(rate,'N/A')
                args = [args, {'ConvolutionalCodeRate', rate}];
            end
        end
        if contains(codeKey,'tpc')
            args = [args, {'TPCCodeRate', localTPCCodeRateValue(opt), ...
                           'TPCBlocksPerTF', tpcBlocksPerTF}];
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
        elseif HelperCCSDSTMPCMDemodulator.supports(modStr)
            if isfield(opt,'ModulationIndex') && ~isempty(opt.ModulationIndex)
                args = [args, {'ModulationIndex', double(opt.ModulationIndex)}];
            end
            if strcmp(string(modStr), "PCM/PSK/PM")
                if ~pcmFormatAdded && isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
                    args = [args, {'PCMFormat', string(opt.PCMFormat)}];
                end
                if isfield(opt,'SubcarrierWaveform') && ~isempty(opt.SubcarrierWaveform)
                    args = [args, {'SubcarrierWaveform', string(opt.SubcarrierWaveform)}];
                end
                if isfield(opt,'SubcarrierToSymbolRateRatio') && ~isempty(opt.SubcarrierToSymbolRateRatio)
                    args = [args, {'SubcarrierToSymbolRateRatio', double(opt.SubcarrierToSymbolRateRatio)}];
                end
            end
        else
            args = [args, {'RolloffFactor', rolloff}];
        end
        if contains(modStr,'4D-8PSK-TCM') && isfield(opt,'ModulationEfficiency')
            args = [args, {'ModulationEfficiency', double(opt.ModulationEfficiency)}];
        end
        switch modStr
            case {'BPSK','QPSK','8PSK','OQPSK','16QAM','32QAM'}
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
%% 创建发送端波形

    tmWaveGen = ccsdsTMWaveformGenerator(args{:});
    disp(tmWaveGen)
    disp(info(tmWaveGen))
    % TM发送端内部一帧需要多少bit
    fprintf('[TX %s] NumInputBits=%d, ActualCodeRate=%.6f\n', ...
        char(codeStr), tmWaveGen.NumInputBits, info(tmWaveGen).ActualCodeRate);
    Fs = fSym * sps;
    bitsPerFrame = tmWaveGen.NumInputBits;
    fprintf('[Actual TF] NumInputBits=%d, NumInputBytes=%.3f\n', ...
             tmWaveGen.NumInputBits, tmWaveGen.NumInputBits/8);
    % 缓冲帧
    numWarmUp = 8;
    if isfield(opt,'berWarmUpFrames') && ~isempty(opt.berWarmUpFrames)
        numWarmUp = max(0, round(double(opt.berWarmUpFrames)));
    end
    numRealFrames = 100;
    if isfield(opt,'berFrames') && ~isempty(opt.berFrames)
        numRealFrames = max(1, round(double(opt.berFrames)));
    end
    totalFrames = numWarmUp + numRealFrames;

    if mod(bitsPerFrame, 8) ~= 0
        error('run_ccsds_tm_evaluation:TMFrameLengthNotOctetAligned', ...
            'TM Transfer Frame length must be an integer number of octets. NumInputBits=%d', bitsPerFrame);
    end
    numBytesActualTF = bitsPerFrame / 8;

    % 发送端输入现在按 CCSDS TM Transfer Frame 生成：
    % Primary Header + Data Field + 可选 Secondary Header/OCF/FECF。
    % 这里不加 ASM，ASM 仍由 ccsdsTMWaveformGenerator 按配置处理。
    msg = zeros(bitsPerFrame * totalFrames, 1, 'int8');
    validTxFrames = cell(totalFrames, 1);
    validTxFrameInfo = cell(totalFrames, 1);
    validTxFrameBytes = cell(totalFrames, 1);
    for i = 1:totalFrames
        tfOpt = struct();
        tfOpt.FrameLengthBytes = numBytesActualTF;
        tfOpt.TransferFrameVersionNumber = getf(opt, 'TransferFrameVersionNumber', 0);
        tfOpt.SpacecraftID = getf(opt, 'SpacecraftID', 1);
        tfOpt.VirtualChannelID = getf(opt, 'VirtualChannelID', 0);
        tfOpt.MasterChannelFrameCount = mod(i-1, 256);
        tfOpt.VirtualChannelFrameCount = mod(i-1, 256);
        tfOpt.HasSecondaryHeader = getLogicalField(opt, 'HasSecondaryHeader', false);
        tfOpt.HasOCF = getLogicalField(opt, 'HasOCF', false);
        tfOpt.HasFECF = getLogicalField(opt, 'HasFECF', false);
        if tfOpt.HasSecondaryHeader
            tfOpt.SecondaryHeader = uint8(getfieldwithdefault(opt, 'SecondaryHeader', uint8([])));
        end
        if tfOpt.HasOCF
            tfOpt.OCF = uint8(getfieldwithdefault(opt, 'OCF', zeros(1,4,'uint8')));
        end
        tfOpt.AllowTruncate = true;
        tfOpt.IdleFillByte = uint8(getf(opt, 'IdleFillByte', hex2dec('55')));

        payloadBytes = uint8(randi([0 255], 1, numBytesActualTF));
        [frameBits, frameBytes, frameInfo] = make_ccsds_tm_transfer_frame(payloadBytes, tfOpt);
        currentFrame = int8(frameBits(:));
        if numel(currentFrame) ~= bitsPerFrame
            error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                'Generated TM frame length mismatch: got %d bits, expected %d bits.', ...
                numel(currentFrame), bitsPerFrame);
        end

        idx = (i-1)*bitsPerFrame + (1:bitsPerFrame);
        msg(idx) = currentFrame;
        validTxFrames{i} = currentFrame;
        validTxFrameInfo{i} = frameInfo;
        validTxFrameBytes{i} = frameBytes;
    end
    if getLogicalField(opt, 'debugTMFrame', false)
        localPrintTMFrameInfo(validTxFrameInfo{1}, validTxFrameBytes{1}, 1);
        if totalFrames >= 2
            localPrintTMFrameInfo(validTxFrameInfo{2}, validTxFrameBytes{2}, 2);
        end
    end
    [txWaveform, encodedBits] = tmWaveGen(msg);
    if contains(lower(string(codeStr)), 'tpc') && isfield(opt,'debugTPC') && logical(opt.debugTPC)
        assignin('base', 'debugTPC_encodedBits', int8(encodedBits(:) ~= 0));
        fprintf('[TPC DEBUG] stored tx encodedBits for boundary check: %d bits\n', numel(encodedBits));
    end
    fmInfo = [];
    if contains(modStr,'FM')
        fmParams = makeFMParams(opt, fSym, Fs, sps, rolloff);
        fmParams.fmPayloadBitsPerFrame = numel(encodedBits);
        fmInfo = ccsdsFMBuildInfo(encodedBits, fmParams);
    end

%     上变频
%     IFHz     = double(getf(opt,'IFHz',Fs/4));
%     txBasebandForMetric = txWaveform;   % 保留原始复基带，用于后面 PAPR/绘图
%
%      if abs(IFHz) >= Fs/2
%         warning('IFHz=%.3f MHz >= Fs/2=%.3f MHz，数字实中频会混叠，建议 IFHz < Fs/2。', ...
%             IFHz/1e6, Fs/2/1e6);
%     end
%
%     nIF = (1:numel(txWaveform)).';
%
%     实中频上变频
%     txWaveform = real(txWaveform(:) .* exp(1j*2*pi*IFHz/Fs*nIF));
%%  ===== 信道损伤 =====

    cfo_val   = getf(opt,'cfo',0);
    phase_val = getf(opt,'phaseOffset',0) * pi/180;
    delay_val = getf(opt,'delay',0);
    snr_val   = getf(opt,'snr',100);
    cfo_est = NaN;

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

    [txAfterH, hInfo] = applyHChannelDamage(txWithDelay, opt);

    rxWaveform = awgn(txAfterH, snr_val, 'measured');

    rxWaveform = applyKnownHMMSEEqualizer(rxWaveform, opt, snr_val, false);
%% ===== 接收链路 =====
    isPCMPhaseMod = HelperCCSDSTMPCMDemodulator.supports(modStr);

    if isPCMPhaseMod
        % PCM/PM 类波形不是普通星座调制, 不能交给官方 CarrierSynchronizer。
        % 这里先做相位检波/双相码恢复, 输出 soft bits 直接用于后面的帧同步/译码。
        coarseSynced = rxWaveform;
        [softBitsPCM, phaseMetricPCM] = HelperCCSDSTMPCMDemodulator.demodulate( ...
            modStr, rxWaveform, opt, Fs, fSym, sps);
        TimeSynced = phaseMetricPCM(:);
        fineSynced = complex(softBitsPCM(:), 0);
        fineSyncedForBER = softBitsPCM(:);

    elseif contains(modStr,'FM')
        fmParams = makeFMParams(opt, fSym, Fs, sps, rolloff);
        [~, rxSoftFM, fmRxInfo] = HelperCCSDSTMDemodulator.demodulateFM( ...
            rxWaveform, fmParams, fmInfo);
        coarseSynced = rxWaveform;
        TimeSynced = complex(rxSoftFM(:), 0);
        fineSynced = TimeSynced;
        fineSyncedForBER = rxSoftFM(:);
        cfo_est = cfo_val;
        if isfield(opt,'debugFM') && logical(opt.debugFM)
            fprintf('   [FM DEBUG] detected FM frames = %d/%d, soft bits = %d\n', ...
                fmRxInfo.detectedFrames, fmRxInfo.totalFrames, numel(rxSoftFM));
        end

    elseif contains(modStr,'GMSK')
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
    elseif contains(modStr,'4D-8PSK-TCM')
        % 4D-8PSK-TCM 专用同步分支。
        % 不能把 "4D-8PSK-TCM" 直接交给官方 CarrierSynchronizer,
        % 因为官方对象只接受 BPSK/QPSK/OQPSK/8PSK/PAM/QAM 等普通调制名。
        if abs(getf(opt,'cfo',0)) > 0
            % 4D-TCM 的符号仍落在 8PSK 星座点上, 因此粗频偏阶段用官方
            % 8PSK CoarseFrequencyCompensator。后面的 4D Viterbi 解调仍由
            % HelperCCSDSTMDemodulator 处理, 这里不把 4D 名称交给官方同步器。
            coarseFreqSync4D = comm.CoarseFrequencyCompensator( ...
                'Modulation','8PSK', ...
                'SampleRate', Fs, ...
                'FrequencyResolution', 1e3);
            coarseSynced = coarseFreqSync4D(rxWaveform);
        else
            coarseSynced = rxWaveform;
        end

        rxfilter4D = comm.RaisedCosineReceiveFilter( ...
            'RolloffFactor', rolloff, ...
            'InputSamplesPerSymbol', sps, ...
            'DecimationFactor', 1);
        matched4D = rxfilter4D(coarseSynced);

        totalRRCGroupDelaySym = getf(opt,'tcmRRCGroupDelaySymbols',10);
        drop4D = max(0, round(totalRRCGroupDelaySym));
        searchOffset4D = isfield(opt,'tcmSampleOffsetSearchAll') && logical(opt.tcmSampleOffsetSearchAll);

        ref4D = getReferenceConstellation(modStr);
        bestOffset4D = 0;
        bestMetric4D = inf;
        bestTimeSynced4D = [];
        bestFineSynced4D = [];
        bestTheta4D = 0;

        if searchOffset4D
            offsetList4D = 0:(sps-1);
        else
            offsetList4D = max(0, min(sps-1, round(getf(opt,'tcmSampleOffset',0))));
        end

        for off = offsetList4D
            sampledTmp = matched4D(off+1:sps:end);
            if length(sampledTmp) > drop4D
                timeTmp = sampledTmp(drop4D+1:end);
            else
                timeTmp = sampledTmp;
            end

            if abs(getf(opt,'phaseOffset',0)) > 0 || abs(getf(opt,'cfo',0)) > 0
                carrierTmp = comm.CarrierSynchronizer( ...
                    'Modulation','8PSK', ...
                    'SamplesPerSymbol',1, ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',0.002);
                fineTmp = carrierTmp(timeTmp);
            else
                fineTmp = timeTmp;
            end

            if ~isempty(fineTmp)
                fineTmp = fineTmp ./ sqrt(mean(abs(fineTmp).^2) + eps);
            end

            [evmTmp, ~, ~, thetaTmp] = computeEVMPhaseAligned(fineTmp, ref4D);
            if searchOffset4D
                fprintf('   [4D timing search] sampleOffset=%d, EVM=%.3f%%\n', off, evmTmp);
            end

            if evmTmp < bestMetric4D
                bestMetric4D = evmTmp;
                bestOffset4D = off;
                bestTimeSynced4D = timeTmp;
                bestFineSynced4D = fineTmp;
                bestTheta4D = thetaTmp;
            end
        end

        if searchOffset4D
            fprintf('   [4D timing search] best sampleOffset=%d, best EVM=%.3f%%\n', ...
                bestOffset4D, bestMetric4D);
        end

        TimeSynced = bestTimeSynced4D;
        fineSynced = bestFineSynced4D;
        fineSyncedForBER = bestFineSynced4D * exp(1j*bestTheta4D);
        fineSyncedMetricPhase = bestTheta4D;
        bestTCMSampleOffset = bestOffset4D;

    elseif contains(modStr,'UQPSK')
            % =========================================================
            % UQPSK 专用接收链路
            % 4次幂 FFT 粗 CFO + RRC 匹配滤波 + Gardner 定时同步
            % + UQPSK 专用载波恢复
            % =========================================================

            enableUQPSKFFTCoarseCFO = true;
            if isfield(opt,'enableUQPSKFFTCoarseCFO') && ~isempty(opt.enableUQPSKFFTCoarseCFO)
                enableUQPSKFFTCoarseCFO = logical(opt.enableUQPSKFFTCoarseCFO);
            end

            uqpskMaxCFOHz = 0.01 * fSym;   % 默认搜索 ±1% 符号率
            if isfield(opt,'uqpskMaxCFOHz') && ~isempty(opt.uqpskMaxCFOHz)
                uqpskMaxCFOHz = double(opt.uqpskMaxCFOHz);
            end
            uqpskMaxCFOHz = min(uqpskMaxCFOHz, 0.9 * Fs / 8);

            uqpskCFOFFTLen = 2^17;
            if isfield(opt,'uqpskCFOFFTLen') && ~isempty(opt.uqpskCFOFFTLen)
                uqpskCFOFFTLen = round(double(opt.uqpskCFOFFTLen));
            end

            if enableUQPSKFFTCoarseCFO
                [coarseSynced, cfo_est] = uqpskFourthPowerFFTCoarseCFO( ...
                    rxWaveform, Fs, uqpskMaxCFOHz, uqpskCFOFFTLen);

                if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK)
                    fprintf('   [UQPSK 4th-power CFO] estimated = %+.3f Hz, input = %+.3f Hz, error = %+.3f Hz\n', ...
                        cfo_est, cfo_val, cfo_est - cfo_val);
                end
            else
                coarseSynced = rxWaveform;
                cfo_est = 0;
            end

            rxFilterDecimationFactor = max(1, round(sps/2));
            rxfilter = comm.RaisedCosineReceiveFilter( ...
                'Shape','Square root', ...
                'RolloffFactor', rolloff, ...
                'FilterSpanInSymbols', 10, ...
                'InputSamplesPerSymbol', sps, ...
                'DecimationFactor', rxFilterDecimationFactor);

            nDecimTrim = mod(numel(coarseSynced), rxFilterDecimationFactor);
            if nDecimTrim ~= 0
                coarseForFilter = coarseSynced(1:end-nDecimTrim);
            else
                coarseForFilter = coarseSynced;
            end

            filtered = rxfilter(coarseForFilter);
            sps_after = sps / rxFilterDecimationFactor;

            timingObj = comm.SymbolSynchronizer( ...
                'TimingErrorDetector','Gardner (non-data-aided)', ...
                'SamplesPerSymbol', sps_after, ...
                'DetectorGain', 2.7, ...
                'Modulation','PAM/PSK/QAM', ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', 0.01);

            TimeSynced = timingObj(filtered);

            uqpskCarrierLoopBW = 0.002;
            if isfield(opt,'uqpskCarrierLoopBW') && ~isempty(opt.uqpskCarrierLoopBW)
                uqpskCarrierLoopBW = double(opt.uqpskCarrierLoopBW);
            end

            fineSynced = uqpskCarrierRecover( ...
                TimeSynced, 2, uqpskCarrierLoopBW);

            fineSyncedForBER = fineSynced;
            fineSyncedMetricPhase = 0;

    else
        if contains(modStr,'BPSK')
            coarseMod = 'BPSK';
        elseif contains(modStr,'8PSK')
            coarseMod = '8PSK';
        elseif contains(modStr,'OQPSK')
            coarseMod = 'OQPSK';
        elseif contains(modStr,'QPSK')
            coarseMod = 'QPSK';
        elseif contains(modStr,'QAM')
            coarseMod = 'QAM';    
        else
            coarseMod = 'QAM';
        end

        if contains(modStr,'OQPSK')
            % =================================================================
            % OQPSK 新链路 (推荐方案 2): FFT CFO + CarrierSync('OQPSK') +
            % comm.OQPSKDemodulator (MF+timing+soft LLR 一体化, 在 tryOneRotation 中调用)
            % -----------------------------------------------------------------
            % 弃用原来的 RRC + SymbolSync('OQPSK') + CarrierSync('QPSK') 三段式,
            % 本函数只负责粗 CFO 估计 + 载波相位锁定.
            % =================================================================

            % --- 1) 4 次幂 FFT 粗 CFO 估计 (实测残余 ~4Hz, 已经够) ---
            % 当前使用四次幂 FFT 方法。它属于非数据辅助 FFT-based CFO 估计,
            % 与官方 CoarseFrequencyCompensator 的思想相近, 但不是官方 OQPSK
            % 的完整双谱峰算法。
            %
            % 官方 OQPSK 粗频偏补偿器理论上可用, 但直接替换后曾出现
            % CFO 估计准确而帧锁失败的情况。因此当前先保留已验证链路。
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

            if contains(modStr,'4D-8PSK-TCM')
                carrierSync = comm.CarrierSynchronizer( ...
                    'Modulation','8PSK', ...
                    'SamplesPerSymbol',1, ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',fineLoopBW);
%             elseif contains(modStr,'APSK')
%                 carrierSync = comm.CarrierSynchronizer( ...
%                     'Modulation','QPSK', ...
%                     'SamplesPerSymbol',1, ...
%                     'DampingFactor',1/sqrt(2), ...
%                     'NormalizedLoopBandwidth',0.005);
            elseif contains(modStr,'QAM')
                carrierSync = comm.CarrierSynchronizer( ...
                    'Modulation','QAM', ...
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
    isFMMod = contains(upper(string(modStr)),'FM');
    if isGMSKMod || isPCMPhaseMod || isFMMod
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
    if isFMMod
        evm_pre = NaN;
    elseif isGMSKMod
        [evm_pre,  ~] = computeGMSKIQRoughMetrics(rawSym);
    else
        [evm_pre,  ~] = computeEVM(rawSym, refConst);
    end
    % EVM/MER/SNR_est 先用未旋转的算一份占位,稍后用 best 旋转后的覆盖

    % 同步后的evm
    if isFMMod
        evm_post = NaN;
        mer_post = NaN;
    elseif isGMSKMod
        [evm_post, mer_post] = computeGMSKIQRoughMetrics(fineSynced);
    else
        [evm_post, mer_post] = computeEVM(fineSynced, refConst);
    end

    % 基于星座误差估计的等效 SNR，不等于输入 SNR
    if isFMMod
        snr_est = NaN;
    elseif isGMSKMod
        snr_est = mer_post;
    else
        snr_est = computeSNRest(fineSynced, refConst);
    end

    % 峰均功率比
    papr_dB = 10*log10(max(abs(txWaveform).^2)/mean(abs(txWaveform).^2));

    % BER + Frame Lock（沿用主脚本逻辑的简化版）
    [berVal, lockRate, bestRot, berStats] = computeBER(fineSyncedForBER, validTxFrames, modStr, opt, hasRandomizer, hasASM, btVal, numWarmUp);

    % 用 BER 评估挑出来的 best 旋转把 fineSynced 转回参考相位,星座图视觉对齐
    if isFMMod
        fineSyncedAligned = fineSynced;
        evm_post = NaN;
        mer_post = NaN;
        snr_est = NaN;
    elseif isGMSKMod
        fineSyncedAligned = fineSynced;
        [evm_post, mer_post] = computeGMSKIQRoughMetrics(fineSyncedAligned);
        snr_est = mer_post;
    else
        metricPhase = 0;
        if exist('fineSyncedMetricPhase','var') && ~isempty(fineSyncedMetricPhase)
            metricPhase = fineSyncedMetricPhase;
        end
        fineSyncedAligned = fineSynced * exp(1j*(metricPhase + bestRot));
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
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.cfo_est_Hz = cfo_est;
    res.BER         = berVal;
    res.EVM_pre_pct = evm_pre;
    res.EVM_post_pct= evm_post;
    res.MER_dB      = mer_post;
    res.SNR_est_dB  = snr_est;
    res.PAPR_dB     = papr_dB;
    res.LockRate    = lockRate;
    res.FER         = berStats.FER;
    res.FrameErrorRate = berStats.FER;
    res.FrameErrors = berStats.FrameErrors;
    res.CountedFrames = berStats.CountedFrames;
    res.MatchedFrames = berStats.MatchedFrames;
    res.DecodedFrames = berStats.NumRxFrames;
    res.AcquisitionFrames = berStats.AcquisitionFrames;
    res.AcquisitionTime_s = berStats.AcquisitionTime_s;
    res.Fs          = Fs;
    res.HEnabled    = hInfo.Enabled;
    res.HMode       = char(hInfo.Mode);
    res.HNumTaps    = hInfo.NumTaps;
    res.HEffectiveTaps = hInfo.EffectiveTaps;
    res.HGain_dB    = hInfo.Gain_dB;
    if exist('fmRxInfo','var')
        res.fmRxInfo = fmRxInfo;
        res.fmDetectedFrames = fmRxInfo.detectedFrames;
        res.fmTotalFrames = fmRxInfo.totalFrames;
    end
    

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

function v = getfieldnumeric(s, name, defv)
    v = defv;
    if isfield(s, name) && ~isempty(s.(name))
        raw = s.(name);
        if isnumeric(raw) || islogical(raw)
            v = double(raw);
        else
            tmp = str2double(string(raw));
            if isfinite(tmp)
                v = double(tmp);
            end
        end
    end
end

function res = attachResidualMetrics(res, ctx)
    residCFO_Hz = NaN;
    residPhase_deg = NaN;

    isFACM = isfield(res,'ACMFormat') || ...
        (isfield(res,'modType') && contains(upper(string(res.modType)), 'APSK'));

    if isFACM
        if isfield(res,'FACMResidualCFO_Hz') && isfinite(res.FACMResidualCFO_Hz)
            residCFO_Hz = double(res.FACMResidualCFO_Hz);
        end
    else
        [residCFO_Hz, residPhase_deg] = estimateResidualCarrierMetrics(ctx, res);
    end

    res.residCFO_Hz = residCFO_Hz;
    res.ResidualCFO_Hz = residCFO_Hz;
    res.residPhase_deg = residPhase_deg;
    res.ResidualPhase_deg = residPhase_deg;
    res.ResidualCFO_valid = isfinite(residCFO_Hz);
    res.ResidualPhase_valid = isfinite(residPhase_deg);
end

function [residCFO_Hz, residPhase_deg] = estimateResidualCarrierMetrics(ctx, res)
    residCFO_Hz = NaN;
    residPhase_deg = NaN;
    if ~isfield(ctx,'fineSynced') || isempty(ctx.fineSynced) || ...
            ~isfield(ctx,'Fs') || ~isfield(ctx,'sps') || isempty(ctx.sps)
        return;
    end

    s = ctx.fineSynced(:);
    if length(s) <= 50
        return;
    end

    L = min(length(s), 5000);
    s_use = s(end-L+1:end);
    n = (0:L-1).';
    fSym = ctx.Fs / ctx.sps;

    isGMSKMod = isfield(res,'modType') && contains(upper(string(res.modType)),'GMSK');
    if isGMSKMod
        % GMSK is continuous-phase modulation. A direct phase-slope fit on
        % the synchronized waveform measures data phase as well as carrier
        % phase, so it can report a large fake residual CFO even when BER is 0.
        % Leave this metric invalid unless a GMSK-specific estimator is added.
        residCFO_Hz = NaN;
        residPhase_deg = NaN;
    elseif isfield(ctx,'refConst') && ~isempty(ctx.refConst)
        refC = ctx.refConst(:).';
        [~, idx] = min(abs(s_use - refC), [], 2);
        ideal = ctx.refConst(idx);
        phErr = unwrap(angle(s_use ./ ideal));
        coef = polyfit(n, phErr, 1);
        residCFO_Hz = coef(1) * fSym / (2*pi);
        residPhase_deg = rad2deg(coef(2));
    end
end

function fc = getCenterFrequencyHz(s, defv)
    names = {'centerFrequencyHz','centerFrequency','centerFreqHz', ...
        'IFHz','carrierFreqHz','intermediateFrequencyHz'};
    fc = defv;
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                raw = str2double(strrep(string(raw), ',', ''));
            end
            raw = double(raw);
            if isfinite(raw)
                fc = raw;
                return;
            end
        end
    end
end

function fmParams = makeFMParams(opt, fSym, Fs, sps, rolloff)
    fmParams = struct();
    fmParams.symbolRate = double(fSym);
    fmParams.fs = double(Fs);
    fmParams.sps = double(sps);
    fmParams.RolloffFactor = double(rolloff);
    fmParams.TZZS = double(getf(opt, 'TZZS', 0.715));
    fmParams.fmPayloadBitsPerFrame = double(getf(opt, 'fmPayloadBitsPerFrame', 10000));
    fmParams.fmWarmupBits = double(getf(opt, 'fmWarmupBits', 100));
end

function [yOut, hInfo] = applyHChannelDamage(xIn, opt)
    % H 信道损伤入口。
    % 当前主链路仍然是单发单收/单路接收, 所以这里先支持 SISO 多径 FIR:
    %   H = [h0 h1 h2 ...]
    % 表示:
    %   y[n] = h0*x[n] + h1*x[n-1] + h2*x[n-2] + ...
    % 后续如果要做 SIMO/MIMO, 可以在这里继续扩展, 主接收链路不用改。
    xIn = xIn(:);

    hInfo = struct( ...
        'Enabled', false, ...
        'Mode', "", ...
        'NumTaps', 0, ...
        'EffectiveTaps', 0, ...
        'Gain_dB', 0);

    if ~isfield(opt,'enableHChannel') || ~logical(opt.enableHChannel)
        yOut = xIn;
        return;
    end

    if ~isfield(opt,'H') || isempty(opt.H)
        yOut = xIn;
        return;
    end

    H = opt.H;
    if isstruct(H) && isfield(H,'real') && isfield(H,'imag')
        H = double(H.real) + 1j*double(H.imag);
    else
        H = double(H);
    end

    mode = "auto";
    if isfield(opt,'HMode') && ~isempty(opt.HMode)
        mode = lower(string(opt.HMode));
    end
    if mode == "auto"
        mode = "siso_multipath";
    end

    switch mode
        case "siso_multipath"
            h = H(:).';
            y = filter(h, 1, xIn);

        otherwise
            error('Unsupported HMode: %s', mode);
    end

    inPower = mean(abs(xIn).^2) + eps;
    outPower = mean(abs(y).^2) + eps;
    gain_dB = 10*log10(outPower / inPower);

    if ~isfield(opt,'normalizeHChannel') || logical(opt.normalizeHChannel)
        y = y / sqrt(outPower) * sqrt(inPower);
    end

    yOut = y(:);
    hInfo.Enabled = true;
    hInfo.Mode = mode;
    hInfo.NumTaps = numel(H);
    hInfo.EffectiveTaps = nnz(abs(H(:)) > 1e-12);
    hInfo.Gain_dB = gain_dB;
end

% 参考星座点
function yOut = applyKnownHMMSEEqualizer(yIn, opt, snrForReg_dB, defaultEnable)
    yOut = yIn(:);
    enableEq = logical(defaultEnable);
    if isfield(opt,'enableEqualizer') && ~isempty(opt.enableEqualizer)
        enableEq = logical(opt.enableEqualizer);
    end
    if ~enableEq || ~isfield(opt,'enableHChannel') || ~logical(opt.enableHChannel) || ...
            ~isfield(opt,'H') || isempty(opt.H)
        return;
    end

    if isfield(opt,'modType') && contains(upper(string(opt.modType)),'APSK') && ...
            ~(isfield(opt,'enableKnownHPreEqualizer') && logical(opt.enableKnownHPreEqualizer))
        return;
    end

    H = opt.H;
    if isstruct(H) && isfield(H,'real') && isfield(H,'imag')
        h = double(H.real(:)) + 1j*double(H.imag(:));
    else
        h = double(H(:));
    end
    if isempty(h) || nnz(abs(h) > 1e-12) <= 1
        return;
    end

    mode = "mmse";
    if isfield(opt,'equalizerMode') && ~isempty(opt.equalizerMode)
        mode = lower(string(opt.equalizerMode));
    end
    if ~any(strcmp(mode, ["mmse", "zf", "knownh", "known-h"]))
        return;
    end

    n = length(yOut);
    nfft = 2^nextpow2(n + numel(h) + 1024);
    maxNfft = 2^22;
    if nfft > maxNfft
        if isfield(opt,'debugEqualizer') && logical(opt.debugEqualizer)
            fprintf('   [Known-H EQ] skipped: nfft=%d exceeds limit=%d\n', nfft, maxNfft);
        end
        return;
    end
    Hf = fft(h, nfft);
    Yf = fft(yOut, nfft);

    switch mode
        case "zf"
            reg = 1e-4;
        otherwise
            reg = 10.^(-double(snrForReg_dB)/10);
    end
    if isfield(opt,'equalizerReg') && ~isempty(opt.equalizerReg)
        reg = max(0, double(opt.equalizerReg));
    end

    Xhat = ifft(Yf .* conj(Hf) ./ (abs(Hf).^2 + reg), nfft);
    yEq = Xhat(1:n);

    if ~isfield(opt,'normalizeEqualizerOutput') || logical(opt.normalizeEqualizerOutput)
        inPower = mean(abs(yOut).^2) + eps;
        outPower = mean(abs(yEq).^2) + eps;
        yEq = yEq / sqrt(outPower) * sqrt(inPower);
    end

    if isfield(opt,'debugEqualizer') && logical(opt.debugEqualizer)
        fprintf('   [Known-H EQ] mode=%s, taps=%d, reg=%.4g\n', mode, numel(h), reg);
    end

    yOut = yEq(:);
end

function refConst = getReferenceConstellation(modStr)
    s = upper(string(modStr));
    if contains(s,'BPSK')
        refConst = pskmod((0:1).', 2);
    elseif contains(s,'UQPSK')
        aRatio = 2;
        refConst = [ ...
            1 + 1j/aRatio;
            -1 + 1j/aRatio;
            1 - 1j/aRatio;
            -1 - 1j/aRatio];
    elseif contains(s,'4D-8PSK-TCM')
        refConst = [ ...
            1+0j; ...
            (1+1j)/sqrt(2); ...
            0+1j; ...
            (-1+1j)/sqrt(2); ...
            -1+0j; ...
            (-1-1j)/sqrt(2); ...
            0-1j; ...
            (1-1j)/sqrt(2)];
    elseif contains(s,'UQPSK')
        aRatio = 2;
        refConst = [ ...
            1 + 1j/aRatio;
            -1 + 1j/aRatio;
            1 - 1j/aRatio;
            -1 - 1j/aRatio];
    elseif contains(s,'8PSK')
        refConst = pskmod((0:7).', 8, pi/8, 'gray');
    elseif contains(s,'OQPSK') || contains(s,'QPSK')
        refConst = pskmod((0:3).', 4, pi/4, 'gray');
    elseif contains(s,'16QAM')
        refConst = qammod((0:15).', 16, 'UnitAveragePower', true);
    elseif contains(s,'32QAM')
        refConst = qammod((0:31).', 32, 'UnitAveragePower', true);
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

function [evm_pct, mer_dB, snr_est, bestTheta] = computeEVMPhaseAligned(rxSym, refConst)
    % 4D-TCM timing search 用的 EVM 计算。
    % 4D 分支在搜索抽样点时可能还存在固定相位旋转, 直接算 EVM 会误判。
    % 这里在一个小相位网格里找最小 EVM, 再返回对应相位补偿角。
    if isempty(rxSym) || isempty(refConst)
        evm_pct = NaN;
        mer_dB = NaN;
        snr_est = NaN;
        bestTheta = 0;
        return;
    end

    rxSym = rxSym(:);
    L = min(length(rxSym), 5000);
    rxSym = rxSym(end-L+1:end);
    rxSym = rxSym ./ sqrt(mean(abs(rxSym).^2) + eps);

    refConst = refConst(:);
    refConst = refConst ./ sqrt(mean(abs(refConst).^2) + eps);

    thetaGrid = linspace(-pi/8, pi/8, 181);
    bestEVM = inf;
    bestTheta = 0;
    bestErr = [];
    bestIdeal = [];

    for ii = 1:numel(thetaGrid)
        theta = thetaGrid(ii);
        z = rxSym * exp(1j*theta);
        [~, idx] = min(abs(z - refConst.'), [], 2);
        ideal = refConst(idx);
        err = z - ideal;
        evmNow = sqrt(mean(abs(err).^2) / mean(abs(refConst).^2)) * 100;
        if evmNow < bestEVM
            bestEVM = evmNow;
            bestTheta = theta;
            bestErr = err;
            bestIdeal = ideal;
        end
    end

    evm_pct = bestEVM;
    mer_dB = -20*log10(evm_pct/100 + eps);
    snr_est = 10*log10(mean(abs(bestIdeal).^2) / (mean(abs(bestErr).^2) + eps));
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

function [berVal, lockRate, bestRot, berStats] = computeBER(fineSynced, validTxFrames, modStr, opt, hasRandomizer, hasASM, btVal, numWarmUp)
    berVal = -1; lockRate = 0; bestRot = 0; berStats = localEmptyBERStats();
    try
        tmMod = char(modStr); if contains(tmMod,'GMSK'), tmMod='GMSK'; end
        if isfield(opt,'channelCoding'), tmCode=char(canonicalChannelCoding(opt.channelCoding)); else, tmCode='none'; end
        tmCodeKey = lower(string(tmCode));

        % --- 解算载波相位 M 重模糊：试每个等价旋转，挑帧匹配最多的 ---
        if HelperCCSDSTMPCMDemodulator.supports(tmMod)
            rotations = [1, -1];
        elseif contains(tmMod,'FM')
            rotations = [1, -1];
        elseif contains(tmMod,'BPSK')
            rotations = [1, -1];
        elseif contains(tmMod,'8PSK')
            % 8PSK 的 CCSDS 自定义映射和接收端载波同步之间常见一个 -45 度等价相位。
            % 优先测试 -45 度和 0 度, 可以让 ideal/RS/H 等常见 case 更快命中并早停。
            rotations = exp(1j*pi/4 * [-1 0 1 2 3 4 -3 -2]);
        elseif contains(tmMod,'UQPSK')
            rotations = [1, -1, 1j, -1j];
        elseif contains(tmMod,'GMSK')
            % GMSK 内部 exp(-j*pi/2*n) 去自旋的起始 n 受符号定时器漂移影响,
            % 任意 0~3 的偏移都可能,等价于乘 exp(j*pi/2*k); 必须 4 重枚举
            rotations = exp(1j*pi/2 * (0:3));
        else                      % QPSK/OQPSK/APSK
            rotations = exp(1j*pi/2 * (0:3));
        end

        phaseResolveMode = "asm";
        if isfield(opt,'phaseResolveMode') && ~isempty(opt.phaseResolveMode)
            phaseResolveMode = lower(string(opt.phaseResolveMode));
        end

        rotationOrder = 1:length(rotations);
        asmResolveInfo = struct('enabled', false, 'selectedIdx', rotationOrder, ...
            'fallbackToBER', false, 'message', "");
        if phaseResolveMode ~= "ber"
            [rotationOrder, asmResolveInfo] = selectRotationsByASM( ...
                fineSynced, rotations, tmMod, tmCode, opt, btVal);
            if asmResolveInfo.enabled
                fprintf('   [ASM phase] %s\n', asmResolveInfo.message);
            end
        end

        bestBer = inf;
        bestLock = -1;
        bestRot = 0;
        bitErrorsBest = 0;
        bitsComparedBest = 0;
        bestStats = localEmptyBERStats();
        bestShift = 0;
        evaluated = false(size(rotations));
        
        for iiOrder = 1:length(rotationOrder)
            ii = rotationOrder(iiOrder);
            r = rotations(ii);
            evaluated(ii) = true;
            rxRot = fineSynced * r;
        
            [ber, lock, errs, bitsComp, stats] = tryOneRotation( ...
                rxRot, validTxFrames, tmMod, tmCode, ...
                opt, hasRandomizer, hasASM, btVal, numWarmUp);
        
            fprintf('   [候选角度] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                rad2deg(angle(r)), ber, lock*100, errs, bitsComp);
        
            % 新规则：
            % 只要锁帧率还可以，就优先选择 BER 最低的角度
            isUsableCandidate = (bitsComp > 0) && ...
                (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
            if isUsableCandidate
                if ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock)
                    bestBer = ber;
                    bestLock = lock;
                    bestRot = angle(r);
                    bitErrorsBest = errs;
                    bitsComparedBest = bitsComp;
                    bestStats = stats;
%                     bestShift = shiftBits;
                end
                % 如果已经找到完美候选, 后面的等价旋转没有必要继续跑。
                % 这对 4D-8PSK-TCM 特别重要, 因为每个候选都会触发一次 4D Viterbi 解调。
                if ber == 0 && (lock >= 0.999 || (strcmp(tmCodeKey,'tpc') && lock >= 0.50)) && bitsComp > 0
                    break;
                end
            else
                % 如果还没有找到可靠候选，则暂时保留 lock 最高的
                if isinf(bestBer) && lock > bestLock
                    bestBer = ber;
                    bestLock = lock;
                    bestRot = angle(r);
                    bitErrorsBest = errs;
                    bitsComparedBest = bitsComp;
                    bestStats = stats;
%                     bestShift = shiftBits;
                end
            end
        end

        fallbackEnabled = ~isfield(opt,'phaseResolveFallback') || logical(opt.phaseResolveFallback);
        fallbackBER = 1e-2;
        if isfield(opt,'phaseResolveFallbackBER') && ~isempty(opt.phaseResolveFallbackBER)
            fallbackBER = double(opt.phaseResolveFallbackBER);
        end
        needFallback = fallbackEnabled && phaseResolveMode ~= "ber" && ...
            any(~evaluated) && (bestLock < 0.80 || bitsComparedBest <= 0 || bestBer >= fallbackBER);
        if needFallback
            fprintf('   [ASM phase] selected candidates failed; fallback to remaining rotations.\n');
            for ii = find(~evaluated)
                r = rotations(ii);
                rxRot = fineSynced * r;

                [ber, lock, errs, bitsComp, stats] = tryOneRotation( ...
                    rxRot, validTxFrames, tmMod, tmCode, ...
                    opt, hasRandomizer, hasASM, btVal, numWarmUp);

                fprintf('   [候选角度] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                    rad2deg(angle(r)), ber, lock*100, errs, bitsComp);

                isUsableCandidate = (bitsComp > 0) && ...
                    (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
                if isUsableCandidate
                    if ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock)
                        bestBer = ber;
                        bestLock = lock;
                        bestRot = angle(r);
                        bitErrorsBest = errs;
                        bitsComparedBest = bitsComp;
                        bestStats = stats;
                    end
                    if ber == 0 && (lock >= 0.999 || (strcmp(tmCodeKey,'tpc') && lock >= 0.50)) && bitsComp > 0
                        break;
                    end
                else
                    if isinf(bestBer) && lock > bestLock
                        bestBer = ber;
                        bestLock = lock;
                        bestRot = angle(r);
                        bitErrorsBest = errs;
                        bitsComparedBest = bitsComp;
                        bestStats = stats;
                    end
                end
            end
        end
        
        berVal = bestBer;
        lockRate = max(bestLock, 0);
        berStats = bestStats;
        
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

function [selectedIdx, info] = selectRotationsByASM(fineSynced, rotations, tmMod, tmCode, opt, btVal)
    info = struct('enabled', false, 'selectedIdx', 1:length(rotations), ...
        'fallbackToBER', false, 'message', "");
    selectedIdx = 1:length(rotations);

    if isempty(rotations) || isempty(fineSynced)
        info.message = "empty input; use BER rotation search";
        return;
    end

    maxErr = 6;
    minGap = 4;
    maxCandidates = 2;
    maxSearchBits = 250000;
    if contains(upper(string(tmMod)), '8PSK')
        maxCandidates = 4;
    end
    if isfield(opt,'phaseResolveASMMaxErr'), maxErr = double(opt.phaseResolveASMMaxErr); end
    if isfield(opt,'phaseResolveASMMinGap'), minGap = double(opt.phaseResolveASMMinGap); end
    if isfield(opt,'phaseResolveMaxCandidates'), maxCandidates = max(1, round(double(opt.phaseResolveMaxCandidates))); end
    if isfield(opt,'phaseResolveASMSearchBits'), maxSearchBits = max(1024, round(double(opt.phaseResolveASMSearchBits))); end

    [asmTemplates, asmPeriodBits] = localASMTemplatesForPhaseResolve(tmMod, tmCode, opt);
    scores = -inf(1, length(rotations));
    bestErrs = inf(1, length(rotations));
    bestPos = zeros(1, length(rotations));
    meanErrs = inf(1, length(rotations));
    periodicFrames = zeros(1, length(rotations));

    for ii = 1:length(rotations)
        try
            demodData = localDemodForASM(fineSynced * rotations(ii), tmMod, tmCode, opt, btVal);
            if isempty(demodData)
                continue;
            end
            hardBits = int8(real(demodData(:)) > 0);
            if numel(hardBits) > maxSearchBits
                hardBits = hardBits(1:maxSearchBits);
            end
            [bestErrs(ii), bestPos(ii), meanErrs(ii), periodicFrames(ii), scores(ii)] = ...
                localBestASMPeriodicScore(hardBits, asmTemplates, asmPeriodBits, opt);
        catch
            scores(ii) = -inf;
            bestErrs(ii) = inf;
        end
    end

    finiteMask = isfinite(scores);
    if ~any(finiteMask)
        info.message = "ASM scores unavailable; use BER rotation search";
        return;
    end

    [sortedScores, order] = sort(scores, 'descend');
    sortedErrs = bestErrs(order);
    sortedPos = bestPos(order);
    bestScore = sortedScores(1);
    secondScore = -inf;
    if numel(sortedScores) >= 2
        secondScore = sortedScores(2);
    end
    gap = bestScore - secondScore;

    info.enabled = true;
    info.selectedIdx = order;
    info.scores = scores;
    info.bestErrs = bestErrs;
    info.bestPos = bestPos;
    info.meanErrs = meanErrs;
    info.periodicFrames = periodicFrames;

    if sortedErrs(1) <= maxErr && gap >= minGap
        selectedIdx = order(1);
        info.message = sprintf('selected 1 rotation by periodic ASM: rot=%+.1f deg, err=%d, mean=%.2f, frames=%d, pos=%d, gap=%.1f', ...
            rad2deg(angle(rotations(selectedIdx(1)))), sortedErrs(1), ...
            meanErrs(selectedIdx(1)), periodicFrames(selectedIdx(1)), sortedPos(1), gap);
        return;
    end

    nPick = min(maxCandidates, numel(order));
    selectedIdx = order(1:nPick);
    info.message = sprintf('periodic ASM ambiguous; decode top %d rotations: best rot=%+.1f deg err=%d mean=%.2f frames=%d, second err=%d, gap=%.1f', ...
        nPick, rad2deg(angle(rotations(selectedIdx(1)))), sortedErrs(1), ...
        meanErrs(selectedIdx(1)), periodicFrames(selectedIdx(1)), ...
        sortedErrs(min(2,numel(sortedErrs))), gap);
end

function stats = localEmptyBERStats()
    stats = struct( ...
        'FER', NaN, ...
        'FrameErrors', 0, ...
        'CountedFrames', 0, ...
        'MatchedFrames', 0, ...
        'NumRxFrames', 0, ...
        'AcquisitionFrames', NaN, ...
        'AcquisitionTime_s', NaN);
end

function t = localAcquisitionTimeSeconds(acquisitionFrames, bitsPerFrame, tmMod, tmCode, opt)
    t = NaN;
    if isempty(acquisitionFrames) || ~isfinite(acquisitionFrames) || acquisitionFrames <= 0
        return;
    end
    symbolRate = 1;
    if isfield(opt,'symbolRate') && ~isempty(opt.symbolRate)
        symbolRate = double(opt.symbolRate);
    end
    if ~isfinite(symbolRate) || symbolRate <= 0
        return;
    end

    bitsPerSymbol = localNominalBitsPerSymbol(tmMod);
    codeRate = localNominalCodeRate(tmCode, opt);
    codedBitsPerFrame = double(bitsPerFrame) / max(codeRate, eps);
    symbolsPerFrame = codedBitsPerFrame / max(bitsPerSymbol, eps);
    t = double(acquisitionFrames) * symbolsPerFrame / symbolRate;
end

function bps = localNominalBitsPerSymbol(tmMod)
    s = upper(string(tmMod));
    if contains(s,'UQPSK')
        bps = 1.5;
    elseif contains(s,'32QAM') || contains(s,'32APSK')
        bps = 5;
    elseif contains(s,'16QAM') || contains(s,'16APSK')
        bps = 4;
    elseif contains(s,'8PSK') || contains(s,'4D-8PSK-TCM')
        bps = 3;
    elseif contains(s,'QPSK') || contains(s,'OQPSK')
        bps = 2;
    else
        bps = 1;
    end
end

function rate = localNominalCodeRate(tmCode, opt)
    codeKey = lower(string(tmCode));
    rate = 1;
    if contains(codeKey,'convolutional')
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            rate = localRateStringToDouble(opt.ConvolutionalCodeRate, 1/2);
        else
            rate = 1/2;
        end
    elseif contains(codeKey,'turbo') || contains(codeKey,'ldpc')
        if isfield(opt,'CodeRate') && ~isempty(opt.CodeRate)
            rate = localRateStringToDouble(opt.CodeRate, 1/2);
        else
            rate = 1/2;
        end
    elseif contains(codeKey,'tpc')
        rate = localTPCEffectiveRate(getfieldwithdefault(opt, 'TPCCodeRate', ...
            getfieldwithdefault(opt, 'tpcCodeRate', 'native')));
    elseif contains(codeKey,'concatenated')
        rate = localRateStringToDouble(getfieldwithdefault(opt,'ConvolutionalCodeRate','1/2'), 1/2) * 223/255;
    elseif contains(codeKey,'rs')
        rate = 223/255;
    end
end

function rate = localRateStringToDouble(rawRate, defaultRate)
    rate = defaultRate;
    if isnumeric(rawRate)
        rate = double(rawRate);
        return;
    end
    txt = char(string(rawRate));
    if contains(txt,'/')
        parts = split(string(txt), '/');
        if numel(parts) == 2
            num = str2double(parts(1));
            den = str2double(parts(2));
            if isfinite(num) && isfinite(den) && den ~= 0
                rate = num / den;
            end
        end
    else
        v = str2double(txt);
        if isfinite(v)
            rate = v;
        end
    end
end

function value = localTPCCodeRateValue(opt)
    value = getfieldwithdefault(opt, 'TPCCodeRate', ...
        getfieldwithdefault(opt, 'tpcCodeRate', 'native'));
    if isstring(value)
        value = char(value);
    end
end

function rate = localTPCEffectiveRate(rawRate)
    side = localTPCPayloadSideLength(rawRate);
    rate = (side * side) / (64 * 64);
end

function bits = localTPCPayloadBits(rawRate)
    side = localTPCPayloadSideLength(rawRate);
    bits = side * side;
end

function side = localTPCPayloadSideLength(rawRate)
    if nargin < 1 || isempty(rawRate)
        rawRate = 'native';
    end

    if isnumeric(rawRate)
        side = round(double(rawRate));
    else
        key = lower(strtrim(char(rawRate)));
        switch key
            case {'native','default','0.7932','57','57x57'}
                side = 57;
            case {'1/2','half'}
                side = 45;
            case {'2/3'}
                side = 52;
            otherwise
                xPos = strfind(key, 'x');
                if numel(xPos) == 1
                    side = round(str2double(key(1:xPos-1)));
                else
                    side = round(str2double(key));
                end
        end
    end

    if ~isfinite(side) || side < 1 || side > 57
        error('run_ccsds_tm_evaluation:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end

function v = getfieldwithdefault(s, name, defv)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defv;
    end
end

function demodData = localDemodForASM(fineSynced, tmMod, tmCode, opt, btVal)
    if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
        pcmFormatRx = string(opt.PCMFormat);
    else
        pcmFormatRx = "NRZ-L";
    end

    if HelperCCSDSTMPCMDemodulator.supports(tmMod)
        demodData = real(fineSynced(:));
    elseif contains(tmMod,'FM')
        demodData = double(real(fineSynced(:)));
    elseif contains(tmMod,'UQPSK')
        demodobj = HelperCCSDSTMDemodulator( ...
            'Modulation', tmMod, ...
            'ChannelCoding', tmCode, ...
            'PCMFormat', pcmFormatRx);
        demodData = demodobj(fineSynced);
    elseif strcmp(tmMod,'OQPSK')
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
            'PCMFormat', pcmFormatRx, ...
            'SamplesPerSymbol', spsLocal, ...
            'RolloffFactor', rolloffLocal);
        demodData = demodobj(fineSynced);
    elseif contains(tmMod,'GMSK')
        demodobj = HelperCCSDSTMDemodulator( ...
            'Modulation', tmMod, ...
            'ChannelCoding', tmCode, ...
            'PCMFormat', pcmFormatRx, ...
            'BandwidthTimeProduct', btVal);
        demodData = real(demodobj(fineSynced));
    else
        demodArgs = {'Modulation', tmMod, 'ChannelCoding', tmCode, 'PCMFormat', pcmFormatRx};
        if contains(tmMod,'4D-8PSK-TCM')
            demodArgs = [demodArgs, {'ModulationEfficiency', getf(opt,'ModulationEfficiency',2)}];
        end
        demodobj = HelperCCSDSTMDemodulator(demodArgs{:});
        demodData = demodobj(fineSynced);
    end
end

function asmBits = localTMASM()
    asmBits = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
end

function [asmTemplates, periodBits] = localASMTemplatesForPhaseResolve(tmMod, tmCode, opt)
    asmBits = localTMASM();
    codeKey = lower(string(tmCode));
    pcmFormat = "NRZ-L";
    if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
        pcmFormat = upper(string(opt.PCMFormat));
    end

    if contains(codeKey, 'convolutional')
        rateStr = "1/2";
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            rateStr = string(opt.ConvolutionalCodeRate);
        end
        [baseTemplate, puncturePattern, offsetLength, flipSecondBranch] = localConvASMTemplateByRate(rateStr);
        if any(strcmp(pcmFormat, ["NRZ-M","NRZ-S"]))
            trellis = poly2trellis(7, [171 133]);
            sync0 = localBuildConvEncodedASMSync(asmBits, 0, pcmFormat, trellis, puncturePattern, offsetLength, flipSecondBranch);
            sync1 = localBuildConvEncodedASMSync(asmBits, 1, pcmFormat, trellis, puncturePattern, offsetLength, flipSecondBranch);
            asmTemplates = [sync0(:), sync1(:)];
        else
            asmTemplates = baseTemplate(:);
        end
    else
        asmTemplates = asmBits(:);
    end

    periodBits = localASMPeriodBits(tmMod, tmCode, opt);
end

function [asmTemplate, puncturePattern, offsetLength, flipSecondBranch] = localConvASMTemplateByRate(rateStr)
    rateStr = string(rateStr);
    puncturePattern = [1;1];
    offsetLength = 12;
    flipSecondBranch = false;

    switch char(rateStr)
        case '1/2'
            asmTemplate = int8([1;0;0;0;0;0;0;1;1;1;0;0;1;0;0;1;0;1;1;1;0;0;0;1;1;0;1; ...
                0;1;0;1;0;0;1;1;1;0;0;1;1;1;1;0;1;0;0;1;1;1;1;1;0]);
            puncturePattern = [1;1];
            offsetLength = 12;
        case '2/3'
            asmTemplate = int8([1;1;0;1;0;1;0;1;1;1;0;0;0;0;0;1;0; ...
                1;1;1;1;1;1;0;0;0;0;1;0;1;0;0;0;1;0;1;0;1]);
            puncturePattern = [1;1;0;1];
            offsetLength = 10;
        case '3/4'
            puncturePattern = [1;1;0;1;1;0];
            offsetLength = 7;
            asmTemplate = localBuildConvEncodedASMSync(localTMASM(), 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        case '5/6'
            puncturePattern = [1;1;0;1;1;0;0;1;1;0];
            offsetLength = 9;
            asmTemplate = localBuildConvEncodedASMSync(localTMASM(), 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        case '7/8'
            puncturePattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];
            offsetLength = 7;
            asmTemplate = localBuildConvEncodedASMSync(localTMASM(), 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        otherwise
            asmTemplate = localBuildConvEncodedASMSync(localTMASM(), 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
    end
end

function periodBits = localASMPeriodBits(tmMod, tmCode, opt)
    numBytesTF = 1115;
    if isfield(opt,'NumBytesInTransferFrame') && ~isempty(opt.NumBytesInTransferFrame)
        numBytesTF = double(opt.NumBytesInTransferFrame);
    end
    hasASM = true;
    if isfield(opt,'hasASM')
        hasASM = logical(opt.hasASM);
    end
    asmLen = 32 * double(hasASM);
    codeKey = lower(string(tmCode));

    if contains(codeKey, 'convolutional')
        rate = localNominalCodeRate(tmCode, opt);
        periodBits = round((numBytesTF*8 + asmLen) / max(rate, eps));
    elseif contains(codeKey, 'ldpc') || contains(codeKey, 'turbo')
        k = 1024;
        if isfield(opt,'NumBitsInInformationBlock') && ~isempty(opt.NumBitsInInformationBlock)
            k = double(opt.NumBitsInInformationBlock);
        end
        rate = localNominalCodeRate(tmCode, opt);
        periodBits = round(k / max(rate, eps)) + asmLen;
    elseif contains(codeKey, 'tpc')
        periodBits = 64*64 + asmLen;
    elseif contains(codeKey, 'rs')
        periodBits = 255*8 + asmLen;
    else
        periodBits = numBytesTF*8 + asmLen;
    end

    if contains(upper(string(tmMod)), 'UQPSK')
        periodBits = round(periodBits);
    end
end

function syncASM = localBuildConvEncodedASMSync(asmBits, initState, pcmFormat, trellis, puncturePattern, offsetLength, flipSecondBranch)
    asmBits = int8(asmBits(:) ~= 0);
    pcmFormat = upper(string(pcmFormat));
    if any(strcmp(pcmFormat, ["NRZ-M","NRZ-S"]))
        diffBits = zeros(size(asmBits), 'int8');
        state = int8(initState ~= 0);
        for k = 1:numel(asmBits)
            inBit = asmBits(k);
            if strcmp(pcmFormat, "NRZ-S")
                inBit = int8(~logical(inBit));
            end
            state = int8(xor(logical(state), logical(inBit)));
            diffBits(k) = state;
        end
        asmBits = diffBits;
    end

    enc = comm.ConvolutionalEncoder('TrellisStructure', trellis);
    motherBits = int8(enc(asmBits));
    if flipSecondBranch
        motherBits(2:2:end) = int8(~logical(motherBits(2:2:end)));
    end

    p = puncturePattern(:);
    pp = repmat(p, ceil(length(motherBits)/length(p)), 1);
    pp = pp(1:length(motherBits));
    codedASM = motherBits(logical(pp));
    offsetLength = min(offsetLength, length(codedASM)-1);
    syncASM = int8(codedASM(offsetLength+1:end));
end

function [bestErr, bestPos] = localBestASMError(hardBits, asmBits)
    hardBits = int8(hardBits(:));
    asmBits = int8(asmBits(:));
    asmLen = numel(asmBits);
    bestErr = inf;
    bestPos = 0;
    if numel(hardBits) < asmLen
        return;
    end

    asmInv = int8(~logical(asmBits));
    maxStart = numel(hardBits) - asmLen + 1;
    for iPos = 1:maxStart
        seg = hardBits(iPos:iPos+asmLen-1);
        err0 = nnz(seg ~= asmBits);
        err1 = nnz(seg ~= asmInv);
        errNow = min(err0, err1);
        if errNow < bestErr
            bestErr = errNow;
            bestPos = iPos;
            if bestErr == 0
                break;
            end
        end
    end
end

function [bestErr, bestPos, meanErr, nFrames, score] = localBestASMPeriodicScore(hardBits, asmTemplates, periodBits, opt)
    hardBits = int8(hardBits(:));
    asmTemplates = int8(asmTemplates);
    if isempty(asmTemplates)
        asmTemplates = localTMASM();
    end

    bestErr = inf;
    bestPos = 0;
    meanErr = inf;
    nFrames = 0;
    score = -inf;

    nTop = 32;
    maxFrames = 8;
    errMargin = 4;
    if isfield(opt,'phaseResolveASMPeriodicCandidates')
        nTop = max(1, round(double(opt.phaseResolveASMPeriodicCandidates)));
    end
    if isfield(opt,'phaseResolveASMPeriodicFrames')
        maxFrames = max(1, round(double(opt.phaseResolveASMPeriodicFrames)));
    end
    if isfield(opt,'phaseResolveASMErrMargin')
        errMargin = max(0, round(double(opt.phaseResolveASMErrMargin)));
    end

    for iTpl = 1:size(asmTemplates, 2)
        tpl = asmTemplates(:, iTpl);
        [errVec, posVec] = localASMErrorVector(hardBits, tpl);
        if isempty(errVec)
            continue;
        end

        [sortedErr, order] = sort(errVec, 'ascend');
        keep = min(nTop, numel(order));
        if isfinite(sortedErr(1))
            keep = min(numel(order), max(keep, nnz(sortedErr <= sortedErr(1) + errMargin)));
        end

        for kk = 1:keep
            posNow = posVec(order(kk));
            errNow = sortedErr(kk);
            [meanNow, framesNow] = localPeriodicASMMeanError(hardBits, tpl, posNow, periodBits, maxFrames);
            if framesNow <= 0
                meanNow = errNow;
                framesNow = 1;
            end

            scoreNow = (numel(tpl) - meanNow) + 0.75*min(framesNow, maxFrames) - 0.10*errNow;
            if scoreNow > score
                score = scoreNow;
                bestErr = errNow;
                bestPos = posNow;
                meanErr = meanNow;
                nFrames = framesNow;
            end
        end
    end
end

function [errVec, posVec] = localASMErrorVector(hardBits, asmBits)
    hardBits = int8(hardBits(:));
    asmBits = int8(asmBits(:) ~= 0);
    asmLen = numel(asmBits);
    maxStart = numel(hardBits) - asmLen + 1;
    if maxStart < 1
        errVec = [];
        posVec = [];
        return;
    end

    asmInv = int8(~logical(asmBits));
    errVec = inf(maxStart, 1);
    posVec = (1:maxStart).';
    for iPos = 1:maxStart
        seg = hardBits(iPos:iPos+asmLen-1);
        err0 = nnz(seg ~= asmBits);
        err1 = nnz(seg ~= asmInv);
        errVec(iPos) = min(err0, err1);
    end
end

function [meanErr, nFrames] = localPeriodicASMMeanError(hardBits, asmBits, firstPos, periodBits, maxFrames)
    hardBits = int8(hardBits(:));
    asmBits = int8(asmBits(:) ~= 0);
    asmInv = int8(~logical(asmBits));
    asmLen = numel(asmBits);
    meanErr = inf;
    nFrames = 0;
    if ~isfinite(periodBits) || periodBits <= 0 || firstPos <= 0
        return;
    end

    errs = [];
    pos = firstPos;
    while pos + asmLen - 1 <= numel(hardBits) && numel(errs) < maxFrames
        seg = hardBits(pos:pos+asmLen-1);
        err0 = nnz(seg ~= asmBits);
        err1 = nnz(seg ~= asmInv);
        errs(end+1) = min(err0, err1); %#ok<AGROW>
        pos = pos + periodBits;
    end

    if ~isempty(errs)
        meanErr = mean(errs);
        nFrames = numel(errs);
    end
end

function [berVal, lockRate, errs, bitsComp, frameStats] = tryOneRotation(fineSynced, validTxFrames, tmMod, tmCode, opt, hasRandomizer, hasASM, btVal, numWarmUp)
    berVal = 0.5; lockRate = 0;

    randomizerModeRaw = getfieldwithdefault(opt, 'RandomizerMode', 'standard');
    randomizerMode = lower(strtrim(char(randomizerModeRaw)));
    validRandomizerModes = {'standard','beforecoding','aftercoding','bypass'};
    if ~any(strcmp(randomizerMode, validRandomizerModes))
        error('run_ccsds_tm_evaluation:InvalidRandomizerMode', ...
            'Unsupported RandomizerMode="%s". Use standard, beforeCoding, afterCoding, or bypass.', ...
            randomizerMode);
    end


    errs = 0;
    bitsComp = 0;
    frameStats = localEmptyBERStats();
    numBytesTF = 1115;
    if isfield(opt,'NumBytesInTransferFrame') && ~isempty(opt.NumBytesInTransferFrame)
        numBytesTF = double(opt.NumBytesInTransferFrame);
    end

    enableUQPSKGroupSearch = contains(tmMod,'UQPSK') && ...
        (~isfield(opt,'uqpskSkipInternal') || ~logical(opt.uqpskSkipInternal));

    if enableUQPSKGroupSearch
        bestLocalBer = inf;
        bestLocalLock = -1;
        bestLocalErrs = 0;
        bestLocalBits = 0;
        bestLocalStats = localEmptyBERStats();
        bestLocalSkip = 0;

        optLocal = opt;
        optLocal.uqpskSkipInternal = true;

        for symSkip = 0:1
            if symSkip > 0
                rxCandidate = fineSynced(symSkip+1:end);
            else
                rxCandidate = fineSynced;
            end

            [candBer, candLock, candErrs, candBits, candStats] = tryOneRotation( ...
                rxCandidate, validTxFrames, tmMod, tmCode, optLocal, ...
                hasRandomizer, hasASM, btVal, numWarmUp);

            if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK)
                fprintf('      [UQPSK group] symSkip=%d, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d\n', ...
                    symSkip, candBer, candLock*100, candErrs, candBits);
            end

            if candLock >= 0.80 && candBits > 0
                if candBer < bestLocalBer
                    bestLocalBer = candBer;
                    bestLocalLock = candLock;
                    bestLocalErrs = candErrs;
                    bestLocalBits = candBits;
                    bestLocalStats = candStats;
                    bestLocalSkip = symSkip;
                end
                if candBer == 0 && candLock >= 0.999
                    break;
                end
            elseif isinf(bestLocalBer) && ...
                    (candLock > bestLocalLock || (candLock == bestLocalLock && candBits > bestLocalBits))
                bestLocalBer = candBer;
                bestLocalLock = candLock;
                bestLocalErrs = candErrs;
                bestLocalBits = candBits;
                bestLocalStats = candStats;
                bestLocalSkip = symSkip;
            end
        end

        if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK)
            fprintf('      [UQPSK group] selected symSkip=%d\n', bestLocalSkip);
        end

        berVal = bestLocalBer;
        lockRate = max(bestLocalLock, 0);
        errs = bestLocalErrs;
        bitsComp = bestLocalBits;
        frameStats = bestLocalStats;
        return;
    end
    enable4DGroupSearch = isfield(opt,'tcmSearchAll') && logical(opt.tcmSearchAll);

    if enable4DGroupSearch && contains(tmMod,'4D-8PSK-TCM') && ...
            (~isfield(opt,'tcmSkipInternal') || ~logical(opt.tcmSkipInternal))
        if isfield(opt,'tcmSymbolSkip') && ~isempty(opt.tcmSymbolSkip)
            symbolSkips = max(0, min(3, round(double(opt.tcmSymbolSkip))));
        else
            symbolSkips = 0:3;
            % 4D-TCM Viterbi 每 4 个 8PSK 符号组成一个分支。
            % 前端同步可能只差 0..3 个符号的组起点, 星座 EVM 仍然很好,
            % 但组边界错了会导致 Viterbi 输出接近随机, 所以这里单独搜索。
            symbolSkips = 0:3;
        end

        bestLocalBer = inf;
        bestLocalLock = -1;
        bestLocalErrs = 0;
        bestLocalBits = 0;
        bestLocalStats = localEmptyBERStats();
        bestLocalSkip = 0;
        optLocal = opt;
        optLocal.tcmSkipInternal = true;

        for iSkip = 1:numel(symbolSkips)
            symSkip = symbolSkips(iSkip);
            if symSkip > 0
                rxCandidate = fineSynced(symSkip+1:end);
            else
                rxCandidate = fineSynced;
            end

            [candBer, candLock, candErrs, candBits, candStats] = tryOneRotation( ...
                rxCandidate, validTxFrames, tmMod, tmCode, optLocal, ...
                hasRandomizer, hasASM, btVal, numWarmUp);

            fprintf('      [4D group] symSkip=%d, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d\n', ...
                symSkip, candBer, candLock*100, candErrs, candBits);

            if candLock >= 0.80 && candBits > 0
                if candBer < bestLocalBer
                    bestLocalBer = candBer;
                    bestLocalLock = candLock;
                    bestLocalErrs = candErrs;
                    bestLocalBits = candBits;
                    bestLocalStats = candStats;
                    bestLocalSkip = symSkip;
                end
                if candBer == 0 && candLock >= 0.999
                    break;
                end
            elseif isinf(bestLocalBer) && candLock > bestLocalLock
                bestLocalBer = candBer;
                bestLocalLock = candLock;
                bestLocalErrs = candErrs;
                bestLocalBits = candBits;
                bestLocalStats = candStats;
                bestLocalSkip = symSkip;
            end
        end

        fprintf('      [4D group] selected symSkip=%d\n', bestLocalSkip);
        berVal = bestLocalBer;
        lockRate = max(bestLocalLock, 0);
        errs = bestLocalErrs;
        bitsComp = bestLocalBits;
        frameStats = bestLocalStats;
        return;
    end

    if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
        pcmFormatRx = string(opt.PCMFormat);
    else
        pcmFormatRx = "NRZ-L";
    end

    if HelperCCSDSTMPCMDemodulator.supports(tmMod)
        demodData = real(fineSynced(:));
    elseif contains(tmMod,'FM')
        demodData = double(real(fineSynced(:)));
    elseif contains(tmMod,'UQPSK')
    demodobj = HelperCCSDSTMDemodulator( ...
        'Modulation', tmMod, ...
        'ChannelCoding', tmCode, ...
        'PCMFormat', pcmFormatRx);

    demodData = demodobj(fineSynced);
    elseif strcmp(tmMod,'OQPSK')
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
            'PCMFormat', pcmFormatRx, ...
            'SamplesPerSymbol', spsLocal, ...
            'RolloffFactor', rolloffLocal);
    
        demodData = demodobj(fineSynced);

    elseif contains(tmMod,'GMSK')
        demodobj = HelperCCSDSTMDemodulator( ...
            'Modulation',tmMod, ...
            'ChannelCoding',tmCode, ...
            'PCMFormat', pcmFormatRx, ...
            'BandwidthTimeProduct',btVal);
        demodData = demodobj(fineSynced);
        debugGMSK = isfield(opt,'debugGMSK') && logical(opt.debugGMSK);
        if ~debugGMSK
            codeKeyDbg = lower(string(tmCode));
            debugGMSK = contains(codeKeyDbg,'rs') || contains(codeKeyDbg,'ldpc') || ...
                contains(codeKeyDbg,'convolutional');
        end
        if debugGMSK
            hard0 = demodData(:) < 0;
            fprintf('   [GMSK DEBUG] demodData len=%d, mean=%+.3f, std=%.3f, min=%+.3f, max=%+.3f, ones=%.1f%%\n', ...
                numel(demodData), mean(demodData(:)), std(demodData(:)), ...
                min(demodData(:)), max(demodData(:)), 100*mean(hard0));
        end
        demodData = real(demodData);
    else
        demodArgs = {'Modulation',tmMod,'ChannelCoding',tmCode,'PCMFormat',pcmFormatRx};
        if contains(tmMod,'4D-8PSK-TCM')
            demodArgs = [demodArgs, {'ModulationEfficiency', getf(opt,'ModulationEfficiency',2)}];
        end
        demodobj = HelperCCSDSTMDemodulator(demodArgs{:});
        demodData = demodobj(fineSynced);
    end

    if contains(tmMod,'4D-8PSK-TCM') && isfield(opt,'debug4D') && logical(opt.debug4D)
        fprintf('   [4D DEBUG] rxSymbols=%d, demodSoftBits=%d, ModulationEfficiency=%.2f\n', ...
            length(fineSynced), length(demodData), double(getf(opt,'ModulationEfficiency',2)));
        if evalin('base','exist(''debug4D_tx_modin'',''var'')')
            txModIn = evalin('base','debug4D_tx_modin');
            rxHard = int8(demodData(:) > 0);
            Ldbg = min(numel(rxHard), numel(txModIn));
            dbgErr = nnz(rxHard(1:Ldbg) ~= int8(txModIn(1:Ldbg)));
            firstErr = find(rxHard(1:Ldbg) ~= int8(txModIn(1:Ldbg)), 1, 'first');
            if isempty(firstErr), firstErr = 0; end
            fprintf('   [4D DEBUG] demod-vs-txModIn err=%d/%d, firstErr=%d, txModInLen=%d\n', ...
                dbgErr, Ldbg, firstErr, numel(txModIn));
            maxOffset = min(200, max(0, numel(txModIn) - numel(rxHard)));
            bestOffset = 0;
            bestOffsetErr = inf;
            bestOffsetLen = 0;
            for offBits = 0:maxOffset
                Loff = min(numel(rxHard), numel(txModIn) - offBits);
                if Loff <= 0
                    continue;
                end
                errOff = nnz(rxHard(1:Loff) ~= int8(txModIn(offBits+1:offBits+Loff)));
                if errOff < bestOffsetErr
                    bestOffsetErr = errOff;
                    bestOffset = offBits;
                    bestOffsetLen = Loff;
                end
            end
            fprintf('   [4D DEBUG] best txModIn bit offset=%d, aligned err=%d/%d\n', ...
            bestOffset, bestOffsetErr, bestOffsetLen);
        end
    end

    if strcmpi(string(tmCode), "TPC") && isfield(opt,'debugTPC') && logical(opt.debugTPC)
        fprintf('   [TPC DEBUG] demod soft: len=%d, mean=%+.4g, std=%.4g, min=%+.4g, max=%+.4g, hard1=%.1f%%\n', ...
            numel(demodData), mean(double(demodData(:))), std(double(demodData(:))), ...
            min(double(demodData(:))), max(double(demodData(:))), 100*mean(demodData(:) > 0));
        if evalin('base','exist(''debugTPC_encodedBits'',''var'')')
            txEnc = evalin('base','debugTPC_encodedBits');
            localTPCPrintEncodedBoundaryDebug(demodData, txEnc, tmMod);
        end
    end

    if strcmpi(string(tmCode), "TPC") && hasASM && ~isempty(demodData)
        asmBits = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
        asmLen = numel(asmBits);
        tpcFullFrameLen = 64*64*getfieldwithdefault(opt, 'TPCBlocksPerTF', 1) + asmLen;
        searchLimit = min(numel(demodData) - asmLen + 1, tpcFullFrameLen);
        if searchLimit > 0
            bestPos = 1;
            bestErr = asmLen + 1;
            bestMeanErr = inf;
            bestFrames = 0;
            hardBits = int8(demodData(:) > 0);
            for iPos = 1:searchLimit
                errNow = nnz(hardBits(iPos:iPos+asmLen-1) ~= asmBits);
                errsPeriodic = errNow;
                nPeriodic = 1;
                nextPos = iPos + tpcFullFrameLen;
                while nextPos + asmLen - 1 <= numel(hardBits) && nPeriodic < 8
                    errsPeriodic(end+1,1) = nnz(hardBits(nextPos:nextPos+asmLen-1) ~= asmBits); %#ok<AGROW>
                    nPeriodic = nPeriodic + 1;
                    nextPos = nextPos + tpcFullFrameLen;
                end
                meanErr = mean(errsPeriodic);
                if meanErr < bestMeanErr || ...
                        (abs(meanErr - bestMeanErr) < 1e-12 && errNow < bestErr)
                    bestMeanErr = meanErr;
                    bestErr = errNow;
                    bestPos = iPos;
                    bestFrames = nPeriodic;
                end
            end
            if isfield(opt,'debugTPC') && logical(opt.debugTPC)
                fprintf('   [TPC DEBUG] pre-decoder ASM scan pos=%d err=%d mean=%.2f frames=%d, demodBits=%d (no external trim)\n', ...
                    bestPos, bestErr, bestMeanErr, bestFrames, numel(demodData));
            end
        end
    end

%     decArgs = {'ChannelCoding',tmCode,'Modulation',tmMod, ...
%                'NumBytesInTransferFrame',1115, ...
%                'HasRandomizer',hasRandomizer,'HasASM',hasASM};
    isLDPCOnSMTF = contains(lower(string(tmCode)),'ldpc') && isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF);
    decoderMod = tmMod;
    if contains(tmMod,'UQPSK')
        decoderMod = 'QPSK';
    elseif contains(tmMod,'FM')
        decoderMod = 'BPSK';
    end
    decArgs = {'ChannelCoding',tmCode,'Modulation',decoderMod, ...
               'HasRandomizer',hasRandomizer,'HasASM',hasASM};
    if ~strcmp(randomizerMode, 'standard')
        decArgs = [decArgs, {'RandomizerMode', char(randomizerMode)}];
    end
    if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
        decArgs = [decArgs, {'PCMFormat', string(opt.PCMFormat)}];
    end
    if isfield(opt,'debugPCMFormat') && logical(opt.debugPCMFormat)
        decArgs = [decArgs, {'DebugPCMFormat', true}];
    end
    if contains(tmMod,'UQPSK') || contains(tmMod,'FM')
        decArgs = [decArgs, {'DisablePhaseAmbiguityResolution', true}];
    end
    tmCodeKey = lower(string(tmCode));
    usesTransferFrameBytes = any(strcmp(tmCodeKey, ["none", "convolutional", "tpc"])) || isLDPCOnSMTF;
    if contains(tmCodeKey,'tpc')
        decArgs = [decArgs, {'TPCCodeRate', localTPCCodeRateValue(opt), ...
                             'TPCBlocksPerTF', getfieldwithdefault(opt, 'TPCBlocksPerTF', 1)}];
    end
    if usesTransferFrameBytes
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
    if contains(lower(string(tmCode)), {'turbo','ldpc'})
        if isfield(opt,'CodeRate') && ~strcmp(char(opt.CodeRate),'N/A')
            decArgs = [decArgs, {'CodeRate', string(opt.CodeRate)}];
        end
        if isfield(opt,'NumBitsInInformationBlock')
            decArgs = [decArgs, {'NumBitsInInformationBlock', double(opt.NumBitsInInformationBlock)}];
        end
    end
    if contains(lower(string(tmCode)),'ldpc')
        if isfield(opt,'IsLDPCOnSMTF')
            decArgs = [decArgs, {'IsLDPCOnSMTF', logical(opt.IsLDPCOnSMTF)}];
        end
        if isfield(opt,'LDPCCodeblockSize')
            decArgs = [decArgs, {'LDPCCodeblockSize', double(opt.LDPCCodeblockSize)}];
        end
    end
    decoderobj = HelperCCSDSTMDecoder(decArgs{:});
    decodedBits = decoderobj(demodData);

    bitsPerFrame = length(validTxFrames{1});
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k=1:length(validTxFrames)
        fr = validTxFrames{k};
        id = localTMFrameID(fr);
        txMap(id)=fr;
    end

    if contains(tmMod,'GMSK') && length(decodedBits) >= bitsPerFrame
        debugGMSKPolarity = isfield(opt,'debugGMSK') && logical(opt.debugGMSK);
        if ~debugGMSKPolarity
            codeKeyDbg = lower(string(tmCode));
            debugGMSKPolarity = contains(codeKeyDbg,'rs') || contains(codeKeyDbg,'ldpc') || ...
                contains(codeKeyDbg,'convolutional');
        end
        [match0, run0] = scoreFrameIds(decodedBits, bitsPerFrame, txMap);
        [match1, run1] = scoreFrameIds(~decodedBits, bitsPerFrame, txMap);
        if match1 > match0 || (match1 == match0 && run1 > run0)
            decodedBits = ~decodedBits;
            if debugGMSKPolarity
                fprintf('   [GMSK DEBUG] inverted decodedBits by frame-ID score: orig matched=%d/run=%d, inv matched=%d/run=%d\n', ...
                    match0, run0, match1, run1);
            end
        elseif debugGMSKPolarity
            fprintf('   [GMSK DEBUG] kept decodedBits by frame-ID score: orig matched=%d/run=%d, inv matched=%d/run=%d\n', ...
                match0, run0, match1, run1);
        end
    end

    if strcmpi(string(tmCode), "TPC") && length(decodedBits) >= bitsPerFrame
        maxShift = min(bitsPerFrame-1, max(0, length(decodedBits)-bitsPerFrame));
        bestShift = 0;
        bestMatched = -1;
        bestRun = -1;
        for sh = 0:maxShift
            [matchedNow, runNow] = scoreFrameIds(decodedBits(sh+1:end), bitsPerFrame, txMap);
            if matchedNow > bestMatched || (matchedNow == bestMatched && runNow > bestRun)
                bestMatched = matchedNow;
                bestRun = runNow;
                bestShift = sh;
            end
        end
        if bestShift > 0 && bestMatched > 0
            decodedBits = decodedBits(bestShift+1:end);
        end
        if isfield(opt,'debugTPC') && logical(opt.debugTPC)
            fprintf('   [TPC DEBUG] decoded bit-align shift=%d, matched=%d, run=%d\n', ...
                bestShift, bestMatched, bestRun);
        end
    end

    numRx = floor(length(decodedBits)/bitsPerFrame);

    debugGMSKFrames = contains(tmMod,'GMSK') && isfield(opt,'debugGMSK') && logical(opt.debugGMSK);
    if contains(tmMod,'GMSK') && ~debugGMSKFrames
        codeKeyDbg = lower(string(tmCode));
        debugGMSKFrames = contains(codeKeyDbg,'rs') || contains(codeKeyDbg,'ldpc') || ...
            contains(codeKeyDbg,'convolutional');
    end
    if debugGMSKFrames
        sample = min(12, numRx);
        ids = nan(1, sample);
        for jj = 1:sample
            rxFr_dbg = double(decodedBits((jj-1)*bitsPerFrame+1:jj*bitsPerFrame));
            ids(jj) = localTMFrameID(rxFr_dbg);
        end

        maxShift = min(64, max(0, bitsPerFrame-1));
        bestShiftDbg = 0;
        bestMatchedDbg = -1;
        bestRunDbg = -1;
        bestFirstIdsDbg = [];
        for sh = 0:maxShift
            nShiftRx = floor((length(decodedBits)-sh)/bitsPerFrame);
            matchedShift = 0;
            runShift = 0;
            maxRunShift = 0;
            lastIdShift = [];
            idsShift = nan(1, min(8, nShiftRx));
            for jj = 1:nShiftRx
                idx0 = sh + (jj-1)*bitsPerFrame + 1;
                rxFr_dbg = double(decodedBits(idx0:idx0+bitsPerFrame-1));
                rxId_dbg = localTMFrameID(rxFr_dbg);
                if jj <= numel(idsShift)
                    idsShift(jj) = rxId_dbg;
                end
                if isKey(txMap, rxId_dbg)
                    matchedShift = matchedShift + 1;
                    if isempty(lastIdShift) || rxId_dbg == mod(lastIdShift + 1, 256)
                        runShift = runShift + 1;
                    else
                        runShift = 1;
                    end
                    maxRunShift = max(maxRunShift, runShift);
                    lastIdShift = rxId_dbg;
                else
                    runShift = 0;
                    lastIdShift = [];
                end
            end
            if matchedShift > bestMatchedDbg || ...
                    (matchedShift == bestMatchedDbg && maxRunShift > bestRunDbg)
                bestMatchedDbg = matchedShift;
                bestRunDbg = maxRunShift;
                bestShiftDbg = sh;
                bestFirstIdsDbg = idsShift;
            end
        end

        fprintf('   [GMSK DEBUG] decodedBits len=%d, bitsPerFrame=%d, numRx=%d, first IDs=[%s]\n', ...
            length(decodedBits), bitsPerFrame, numRx, num2str(ids));
        fprintf('   [GMSK DEBUG] best bit shift=%d, matched=%d, maxConsec=%d, first IDs@shift=[%s]\n', ...
            bestShiftDbg, bestMatchedDbg, bestRunDbg, num2str(bestFirstIdsDbg));
    end

    % DEBUG: OQPSK 锁不住时, 打印解码后的头 12 个帧 ID, 帮判断 Viterbi 输出是
    % (a) 完全随机 (~uniform 0~255), (b) 全 0 / 全 255 (LLR 卡死),
    % (c) 有结构但 ID 在 108~255 (帧边界对齐 / ASM 检测错位)
    if contains(tmMod,'OQPSK') && numRx > 0
        sample = min(12, numRx);
        ids = zeros(1,sample);
        for jj=1:sample
            rxFr_dbg = double(decodedBits((jj-1)*bitsPerFrame+1:jj*bitsPerFrame));
            ids(jj) = localTMFrameID(rxFr_dbg);
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
    countedFrames = 0;
    frameErrors = 0;
    acquisitionFrames = NaN;

    % 从 decodedBits 里按 bitsPerFrame 切一帧。
    % 取 TM Primary Header 中 bit 25~32 的 Virtual Channel Frame Count，
    % 转成 rxId。如果这个 ID 在发送帧 Map 里，说明"认为这帧锁到了"。
    % 用 biterr() 比较接收帧和对应发送帧。
    for j=1:numRx
        rxFr = double(decodedBits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
        rxId = localTMFrameID(rxFr);
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
                if isnan(acquisitionFrames)
                    acquisitionFrames = j;
                end
                countedFrames = countedFrames + 1;
                if thisErrs > 0
                    frameErrors = frameErrors + 1;
                end
                errs = errs + thisErrs;
                bitsComp = bitsComp + bitsPerFrame;
            end
                end
    end
    if bitsComp>0, berVal = errs/bitsComp; else, berVal = 0.5; end
    frameStats.NumRxFrames = numRx;
    frameStats.MatchedFrames = framesMatched;
    frameStats.CountedFrames = countedFrames;
    frameStats.FrameErrors = frameErrors;
    if countedFrames > 0
        frameStats.FER = frameErrors / countedFrames;
    else
        frameStats.FER = NaN;
    end
    frameStats.AcquisitionFrames = acquisitionFrames;
    frameStats.AcquisitionTime_s = localAcquisitionTimeSeconds(acquisitionFrames, bitsPerFrame, tmMod, tmCode, opt);
    % numRx 太少说明解码器同步失败,只输出了 1 帧 zeros (header=0 偶然命中 warmup 帧 0),
    % 这种"虚假 100% lockRate"不能参与竞选,直接置零
    if numRx < 3
        lockRate = 0;
    else
        lockDenom = numRx;
        lockedFrames = framesMatched;
        codeKeyForLock = lower(string(tmCode));
        if contains(codeKeyForLock,'convolutional') || contains(codeKeyForLock,'concatenated')
            % 卷积码译码器前几帧会受 traceback / ASM 缓冲影响, 常表现为开头若干帧
            % 没有可用 frame ID。它们不代表稳态锁帧失败, 因此从第一个匹配帧开始计算 lock。
            firstMatched = find(~isnan(perFrameBER), 1, 'first');
            if ~isempty(firstMatched)
                lockDenom = max(1, numRx - firstMatched + 1);
                lockedFrames = sum(~isnan(perFrameBER(firstMatched:end)));
            end
        end
        lockRate = min(1, lockedFrames / lockDenom);
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


function [matched, maxRun] = scoreFrameIds(bits, bitsPerFrame, txMap)
    matched = 0;
    maxRun = 0;
    runLen = 0;
    lastId = [];
    numRx = floor(length(bits) / bitsPerFrame);
    for j = 1:numRx
        rxFr = double(bits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
        rxId = localTMFrameID(rxFr);
        if isKey(txMap, rxId)
            matched = matched + 1;
            if isempty(lastId) || rxId == mod(lastId + 1, 256)
                runLen = runLen + 1;
            else
                runLen = 1;
            end
            maxRun = max(maxRun, runLen);
            lastId = rxId;
        else
            runLen = 0;
            lastId = [];
        end
    end
end

function localTPCPrintEncodedBoundaryDebug(demodData, txEncodedBits, tmMod)
    rxHard0 = int8(demodData(:) > 0);
    txBits = int8(txEncodedBits(:) ~= 0);
    if isempty(rxHard0) || isempty(txBits)
        return;
    end

    maxOffset = min(256, max(0, numel(rxHard0)-1));
    best = struct('err', inf, 'offset', 0, 'polarity', 1, 'len', 0);
    for polarity = [1 -1]
        if polarity > 0
            rxHard = rxHard0;
        else
            rxHard = int8(~logical(rxHard0));
        end
        for offset = 0:maxOffset
            L = min(numel(txBits), numel(rxHard)-offset);
            if L <= 0
                continue;
            end
            err = nnz(rxHard(offset+1:offset+L) ~= txBits(1:L));
            if err < best.err
                best.err = err;
                best.offset = offset;
                best.polarity = polarity;
                best.len = L;
            end
        end
    end

    if best.len > 0
        fprintf('   [TPC DEBUG] demod-vs-encoded (%s): bestOffset=%d bits, polarity=%+d, hardBER=%.6g (%d/%d)\n', ...
            char(tmMod), best.offset, best.polarity, best.err / best.len, best.err, best.len);
    end
end

function id = localTMFrameID(frameBits)
    frameBits = uint8(frameBits(:) ~= 0);
    if numel(frameBits) < 32
        error('run_ccsds_tm_evaluation:FrameTooShortForVCFC', ...
            'TM frame is too short to read Virtual Channel Frame Count.');
    end
    vcfcBits = frameBits(25:32);
    id = bi2de(double(vcfcBits(:).'), 'left-msb');
end

function localPrintTMFrameInfo(fields, frameBytes, frameIndex)
    if isempty(fields) || isempty(frameBytes)
        return;
    end
    primaryHeader = frameBytes(1:min(6, numel(frameBytes)));
    primaryHeaderHex = strtrim(sprintf('%02X ', primaryHeader));

    fprintf('\n[TM FRAME DEBUG] frame=%d\n', frameIndex);
    fprintf('  Primary Header bytes : %s\n', primaryHeaderHex);
    fprintf('  TFVN=%d, SCID=%d, VCID=%d, OCF=%d\n', ...
        fields.TransferFrameVersionNumber, fields.SpacecraftID, ...
        fields.VirtualChannelID, fields.HasOCF);
    fprintf('  MCFC=%d, VCFC=%d\n', ...
        fields.MasterChannelFrameCount, fields.VirtualChannelFrameCount);
    fprintf('  SHF=%d, SyncFlag=%d, PacketOrder=%d, SLID=%d, FHP=%d\n', ...
        fields.HasSecondaryHeader, fields.SynchronizationFlag, ...
        fields.PacketOrderFlag, fields.SegmentLengthID, fields.FirstHeaderPointer);
    fprintf('  Length: frame=%d bytes, primary=%d, secondary=%d, data=%d, OCF=%d, FECF=%d\n', ...
        fields.FrameLengthBytes, fields.PrimaryHeaderLengthBytes, ...
        fields.SecondaryHeaderLengthBytes, fields.TransferFrameDataFieldLengthBytes, ...
        fields.OperationalControlFieldLengthBytes, fields.FrameErrorControlFieldLengthBytes);
end

function printMetrics(res, opt)
    isGMSK = contains(upper(string(res.modType)), 'GMSK');

    fprintf('\n========= CCSDS 评估结果 =========\n');
    fprintf(' 调制方式 : %s\n', res.modType);
    if isfield(res,'centerFrequencyHz') && isfinite(res.centerFrequencyHz) && res.centerFrequencyHz > 0
        fprintf(' 中心频率 : %.3f MHz\n', res.centerFrequencyHz/1e6);
    end
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
    if isfield(res,'ResidualCFO_Hz') && isfinite(res.ResidualCFO_Hz)
        fprintf(' Residual CFO : %8.3f Hz\n', res.ResidualCFO_Hz);
    else
        fprintf(' Residual CFO : N/A\n');
    end
    fprintf(' PAPR (Tx)    : %6.2f dB\n', res.PAPR_dB);
    fprintf(' Frame Lock   : %6.2f %%\n', res.LockRate*100);
    if isfield(res,'FER')
        fprintf(' FER          : %.6f', res.FER);
        if isfield(res,'FrameErrors') && isfield(res,'CountedFrames')
            fprintf('  (%d/%d frames)', res.FrameErrors, res.CountedFrames);
        end
        fprintf('\n');
    end
    if isfield(res,'AcquisitionFrames') && isfinite(res.AcquisitionFrames)
        fprintf(' Acquisition  : %.0f frames', res.AcquisitionFrames);
        if isfield(res,'AcquisitionTime_s') && isfinite(res.AcquisitionTime_s)
            fprintf('  (%.6g s)', res.AcquisitionTime_s);
        end
        fprintf('\n');
    end
    if isfield(res,'HEnabled') && res.HEnabled
        fprintf(' H channel    : %s, taps=%d, effective taps=%d, gain=%+.2f dB\n', ...
            res.HMode, res.HNumTaps, res.HEffectiveTaps, res.HGain_dB);
    end
    fprintf('==================================\n\n');
end

function fe = buildFrontendArrays(ctx, res) %#ok<INUSD>
    Fs = ctx.Fs; sps = ctx.sps;
    isGMSKMod = contains(upper(string(res.modType)),'GMSK');

    % --- 频谱 (Tx + Rx, 1024 点, 中心对称) ---
    [Pxx_tx, f_axis] = pwelch(ctx.txWaveform, [], [], 1024, Fs, 'centered');
    [Pxx_rx, ~]      = pwelch(ctx.rxWaveform, [], [], 1024, Fs, 'centered');
    [Pxx_cfo, ~]     = pwelch(ctx.coarseSynced, [], [], 1024, Fs, 'centered');
    fe.spectrum = struct( ...
        'f',    reshape(f_axis,            1, []), ...
        'p_tx', reshape(10*log10(Pxx_tx),  1, []), ...
        'p_rx', reshape(10*log10(Pxx_rx),  1, []), ...
        'p_cfo',reshape(10*log10(Pxx_cfo), 1, []), ...
        'centerFrequencyHz', getCenterFrequencyHz(res, 0), ...
        'IFHz', getCenterFrequencyHz(res, 0));
    fe.spectrum.cfo_estimator = buildCFOEstimatorSpectrum(ctx, res);
    % --- 星座: 发送端兜底显示（未经过信道损伤）---
    fe.constTx   = sampleConst(normPwr(ctx.txWaveform(1:sps:end)), 1500);
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
    fe.residCFO = getfieldnumeric(res, 'ResidualCFO_Hz', NaN);
    fe.residPhase = getfieldnumeric(res, 'ResidualPhase_deg', NaN);
end

function out = sampleConst(s, Lmax)
    if isempty(s), out = struct('i', [], 'q', []); return; end
    s = s(:);
    if length(s) > Lmax
        idx = unique(round(linspace(1, length(s), Lmax)));
        s = s(idx);
    end
    out = struct('i', reshape(real(s),1,[]), 'q', reshape(imag(s),1,[]));
end

function y = normPwr(x)
    if isempty(x), y = x; return; end
    p = mean(abs(x).^2);
    if p > 0
        y = x / sqrt(p);
    else
        y = x;
    end
end

function spec = buildCFOEstimatorSpectrum(ctx, res)
    spec = struct('valid', false);
    if ~isfield(ctx,'rxWaveform') || isempty(ctx.rxWaveform) || ...
            ~isfield(ctx,'coarseSynced') || isempty(ctx.coarseSynced)
        return;
    end

    Fs = ctx.Fs;
    L = min([length(ctx.rxWaveform), length(ctx.coarseSynced), 2^20]);
    if L < 1024
        return;
    end
    segLen = min(2^16, 2^floor(log2(L)));
    overlap = floor(0.75 * segLen);
    nfft = max(2^17, 2^nextpow2(segLen));

    rxSig = normPwr(ctx.rxWaveform(1:L));
    coSig = normPwr(ctx.coarseSynced(1:L));
    [Prx, f] = pwelch(rxSig, hamming(segLen), overlap, nfft, Fs, 'centered');
    [Pco, ~] = pwelch(coSig, hamming(segLen), overlap, nfft, Fs, 'centered');

    fEst = f(:);
    pRx = 10*log10(Prx(:) + eps);
    pCo = 10*log10(Pco(:) + eps);
    pRx = pRx - max(pRx);
    pCo = pCo - max(pCo);

    spanHz = max(5e6, 10*abs(res.cfo_in));
    mask = abs(fEst) <= spanHz;
    if nnz(mask) < 16
        mask = true(size(fEst));
    end

    [~, iRx] = max(pRx(mask));
    [~, iCo] = max(pCo(mask));
    fLocal = fEst(mask);

    spec = struct( ...
        'valid', true, ...
        'f_hz', reshape(fLocal,1,[]), ...
        'p_rx', reshape(pRx(mask),1,[]), ...
        'p_corrected', reshape(pCo(mask),1,[]), ...
        'peak_rx_hz', fLocal(iRx), ...
        'peak_corrected_hz', fLocal(iCo));
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
    % The official helper is used for FACM waveform and receiver parameter
    % generation. Channel impairments are applied below so that custom H
    % channel/equalizer tests see exactly one CFO/phase/delay/AWGN pass.
    simParams.EsNodB = 100;
    simParams.CFO = 0;
    simParams.DisableCFO = true;
    simParams.SRO = 0;
    simParams.DisableSRO = true;
    simParams.PeakDoppler = 0;
    simParams.DopplerRate = 0;
    simParams.DisableDoppler = true;
    simParams.DisablePhaseNoise = true;
    simParams.DisableRFImpairments = true;
    simParams.DisableAWGN = true;
    simParams.InitalSyncFrames = getf(opt,'facmWarmupFrames',15);
    simParams.NumFramesForBER = getf(opt,'facmBERFrames',30);
    simParams.NumPLFrames = simParams.InitalSyncFrames + simParams.NumFramesForBER;
    simParams.AttenuationFactor = 1;

    fprintf('[FACM] generating %d PL frames: warmup=%d, berFrames=%d, ACM=%d, sps=%d ...\n', ...
        simParams.NumPLFrames, simParams.InitalSyncFrames, simParams.NumFramesForBER, acmFmt, sps);
    [bits, txWaveform, ~, phyParams, rxParams] = HelperCCSDSFACMRxInputGenerate(cfg, simParams);
    fprintf('[FACM] waveform generated: %d samples\n', length(txWaveform));

    Fs = fSym*sps;
    rxWaveform = txWaveform;
    if cfo_val ~= 0 || phase_deg ~= 0
        pfo = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', cfo_val, ...
            'PhaseOffset', phase_deg, ...
            'SampleRate', Fs);
        rxWaveform = pfo(rxWaveform);
    end
    if delay_val ~= 0
        varDelay = dsp.VariableFractionalDelay('InterpolationMethod','Farrow');
        rxWaveform = varDelay(rxWaveform, delay_val);
    end

    [rxWaveform, hInfo] = applyHChannelDamage(rxWaveform, opt);
    rxSNRForAWGN = snr_val - 10*log10(sps);
    rxWaveform = awgn(rxWaveform, rxSNRForAWGN, 'measured');
    % APSK/FACM has its own frame-marker/pilot aided equalizer below.
    % Do not run the generic known-H FFT equalizer on the whole FACM waveform:
    % it can allocate a huge FFT buffer and it also disturbs FACM phase recovery.
    if isfield(opt,'enableKnownHPreEqualizer') && logical(opt.enableKnownHPreEqualizer)
        rxWaveform = applyKnownHMMSEEqualizer(rxWaveform, opt, rxSNRForAWGN, false);
    end

    [fineSynced, payloadSym, decodedTFBits, rxWork, syncSym, decodedFrames, snrFrame, facmStats] = ...
        facmReceiveAndDecode(rxWaveform, cfg, rxParams, phyParams, simParams, fSym, acmFmt, opt);

    refConst = HelperCCSDSFACMReferenceConstellation(acmFmt);
    refConst = refConst(:) / sqrt(mean(abs(refConst(:)).^2));

    rawSym = rxWaveform(1:sps:end);
    rawSym = normPwr(rawSym);
    fineSynced = normPwr(fineSynced);
    payloadSym = normPwr(payloadSym);

    [berVal, lockRate] = computeFACMBER(decodedTFBits, bits, simParams, decodedFrames, opt);
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
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.BER = berVal;
    res.EVM_pre_pct = evm_pre;
    res.EVM_post_pct = evm_post;
    res.MER_dB = mer_post;
    res.SNR_est_dB = snr_est;
    res.PAPR_dB = papr_dB;
    res.LockRate = lockRate;
    res.Fs = Fs;
    if isfield(facmStats,'cfo_est_Hz')
        res.cfo_est_Hz = facmStats.cfo_est_Hz;
        res.FACMCFOEstimates_Hz = facmStats.cfoEstimates_Hz;
    end
    if isfield(facmStats,'residualCFO_Hz')
        res.FACMResidualCFO_Hz = facmStats.residualCFO_Hz;
        res.FACMResidualCFOEstimates_Hz = facmStats.residualCFOEstimates_Hz;
    end
    if isfield(facmStats,'FDOK'), res.FDOK = facmStats.FDOK; end
    if isfield(facmStats,'FDFail'), res.FDFail = facmStats.FDFail; end
    if isfield(facmStats,'TFOK'), res.TFOK = facmStats.TFOK; end
    if isfield(facmStats,'TFEmpty'), res.TFEmpty = facmStats.TFEmpty; end
    if isfield(facmStats,'AcquisitionFrames')
        res.AcquisitionFrames = facmStats.AcquisitionFrames;
        res.AcquisitionTime_s = facmStats.AcquisitionTime_s;
    end
    res.HEnabled = hInfo.Enabled;
    res.HMode = char(hInfo.Mode);
    res.HNumTaps = hInfo.NumTaps;
    res.HEffectiveTaps = hInfo.EffectiveTaps;
    res.HGain_dB = hInfo.Gain_dB;

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

function [fineSynced, payloadAll, decodedTFBits, filteredRx, syncSym, decodedFrames, snrMean, facmStats] = facmReceiveAndDecode(rxWaveform, cfg, rxParams, phyParams, simParams, fSym, acmFmt, opt)
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

    filteredRx = [];
    syncSym = [];

    fineSynced = [];
    payloadAll = [];
    decodedTFBits = [];
    decodedFrames = 0;
    snrVals = [];
    cfoEstVals = [];
    residualCFOVals = [];
    acquisitionFrame = NaN;
    facmStats = struct();
    debugFACM = isfield(opt,'debugFACM') && logical(opt.debugFACM);
    dbgPhaseOK = 0;
    dbgPhaseFail = 0;
    dbgFDOK = 0;
    dbgFDFail = 0;
    dbgTFOK = 0;
    dbgTFEmpty = 0;
    dbgBERFrames = 0;
    dbgPayloadShort = 0;
    fll = HelperCCSDSFACMFLL('SampleRate', fSym, 'K1', 0.17, 'K2', 0);
    fineCFOSync = comm.PhaseFrequencyOffset('SampleRate', fSym);
    G = 1;
    plFrameSize = rxParams.plFrameSize;
    scrambler = rxParams.PLRandomSymbols(:);
    extraBits = [];
    numIter = 10;
    if isfield(opt,'facmNumIterations') && ~isempty(opt.facmNumIterations)
        numIter = max(1, round(double(opt.facmNumIterations)));
    end

    stIdx = 0;
    endIdx = min(stIdx + plFrameSize*sps, length(rxWaveform));
    rxData = rxWaveform(stIdx+1:endIdx);
    stIdx = endIdx;
    filteredChunk = rrcfilt(rxData);
    filteredRx = [filteredRx; filteredChunk]; %#ok<AGROW>
    syncChunk = symsyncobj(filteredChunk);
    syncSym = [syncSym; syncChunk]; %#ok<AGROW>
    syncidx = HelperCCSDSFACMFrameSync(syncChunk, rxParams.RefFM);
    if isempty(syncidx)
        if debugFACM
            fprintf('   [FACM DEBUG] frame sync failed: no sync index found, syncSym=%d\n', length(syncChunk));
        end
        snrMean = NaN;
        facmStats = localFACMStats(cfoEstVals, residualCFOVals, dbgFDOK, dbgFDFail, dbgTFOK, dbgTFEmpty, ...
            acquisitionFrame, plFrameSize, fSym);
        return;
    end
    leftOutSym = syncChunk(syncidx(1):end);

    if debugFACM
        fprintf('   [FACM DEBUG] syncidx(1)=%d, syncSym=%d, plFrameSize=%d, warmup=%d, berFrames=%d\n', ...
            syncidx(1), length(syncChunk), rxParams.plFrameSize, simParams.InitalSyncFrames, simParams.NumFramesForBER);
    end

    frameIndex = 1;
    snrAveragingFactor = 6;
    snrWindow = zeros(snrAveragingFactor,1);
    idxTemp = 0;
    while stIdx < length(rxWaveform)
        endIdx = min(stIdx + plFrameSize*sps, length(rxWaveform));
        rxData = rxWaveform(stIdx+1:endIdx);
        stIdx = endIdx;
        if length(rxData) < plFrameSize*sps
            break;
        end

        filteredChunk = rrcfilt(rxData);
        filteredRx = [filteredRx; filteredChunk]; %#ok<AGROW>
        syncChunk = symsyncobj(filteredChunk);
        syncSym = [syncSym; syncChunk]; %#ok<AGROW>
        syncidx = HelperCCSDSFACMFrameSync(syncChunk, rxParams.RefFM);
        if isempty(syncidx)
            dbgFDFail = dbgFDFail + 1;
            extraBits = [];
            frameIndex = frameIndex + 1;
            continue;
        end

        oneFrame = [leftOutSym; syncChunk(1:syncidx(1)-1)];
        leftOutSym = syncChunk(syncidx(1):end);
        if length(oneFrame) < plFrameSize
            oneFrame = [oneFrame; zeros(plFrameSize-length(oneFrame),1)];
        else
            oneFrame = oneFrame(1:plFrameSize);
        end

        [fllOut, ~] = fll(oneFrame);
        cfoEst = HelperCCSDSFACMFMFrequencyEstimate(fllOut(1:256), rxParams.RefFM, fSym);
        cfoEstVals(end+1,1) = cfoEst; %#ok<AGROW>
        fineCFOSync.FrequencyOffset = -cfoEst;
        cfoCorrected = fineCFOSync(fllOut);
        cfoCorrected = facmFrameMarkerEqualize(cfoCorrected, rxParams, opt, acmFmt);
        residualCFOVals(end+1,1) = localFACMResidualCFOFromFrameMarker( ...
            cfoCorrected(1:min(256,end)), rxParams.RefFM, fSym); %#ok<AGROW>

        frameSNR = HelperCCSDSFACMSNREstimate(cfoCorrected(1:256), rxParams.RefFM);
        if ~isfinite(frameSNR) || frameSNR <= 0
            frameSNR = 10^(20/10);
        end
        snrWindow(idxTemp+1) = frameSNR;
        idxTemp = mod(idxTemp + 1, snrAveragingFactor);
        if frameIndex < snrAveragingFactor
            finalFrameSNR = mean(snrWindow(1:max(frameIndex,1)));
        else
            finalFrameSNR = mean(snrWindow);
        end
        if ~isfinite(finalFrameSNR) || finalFrameSNR <= 0
            finalFrameSNR = frameSNR;
        end
        snrVals(end+1,1) = finalFrameSNR; %#ok<AGROW>

        phaseRecovered = false;
        if cfg.HasPilots
            try
                if useFACMPostPilotLS(opt)
                    [payloadWithPilots, frameDescriptor] = facmPhaseRecoveryKeepPilots( ...
                        cfoCorrected, rxParams.PilotSeq, rxParams.RefFM);
                    agcIn = [frameDescriptor; payloadWithPilots];
                else
                    [payload, frameDescriptor] = HelperCCSDSFACMPhaseRecovery(cfoCorrected, rxParams.PilotSeq, rxParams.RefFM);
                    agcIn = [frameDescriptor; payload];
                    payloadWithPilots = [];
                end
                if frameIndex >= snrAveragingFactor
                    [agcOut, G] = HelperDigitalAutomaticGainControl(agcIn, finalFrameSNR, G);
                else
                    agcOut = agcIn;
                end
                if useFACMPostPilotLS(opt)
                    frameDescriptor = agcOut(1:64);
                    payloadWithPilots = agcOut(65:end);
                    [payload, payloadWithPilotsEq] = facmPostPilotLSEqualize(payloadWithPilots, rxParams, opt);
                    agcOut = [frameDescriptor; payload];
                    if isfield(opt,'debugFACM') && logical(opt.debugFACM)
                        [pilotEVM, pilotMER] = facmPilotErrorMetric(payloadWithPilotsEq, rxParams);
                        fprintf('   [FACM POST EQ] mode=pilot-ls, pilotEVM=%.2f%%, pilotMER=%.2fdB\n', ...
                            pilotEVM, pilotMER);
                    end
                else
                    payload = agcOut(65:end);
                end
                fineSynced = [fineSynced; agcOut]; %#ok<AGROW>
                dbgPhaseOK = dbgPhaseOK + 1;
                phaseRecovered = true;
            catch
                payload = cfoCorrected(321:min(end,320+8100*16));
                [payload, G] = HelperDigitalAutomaticGainControl(payload, finalFrameSNR, G);
                fineSynced = [fineSynced; payload]; %#ok<AGROW>
                dbgPhaseFail = dbgPhaseFail + 1;
            end
        else
            phaseFixed = compensateFACMFrameMarkerPhase(cfoCorrected, rxParams.RefFM);
            [agcOut, G] = HelperDigitalAutomaticGainControl(phaseFixed, finalFrameSNR, G);
            payload = agcOut(321:min(end,320+8100*16));
            fineSynced = [fineSynced; agcOut]; %#ok<AGROW>
            dbgPhaseOK = dbgPhaseOK + 1;
            phaseRecovered = true;
        end

        payload = payload(:);
        if length(payload) >= 8100*16
            payload = payload(1:8100*16);
            payloadDescrambled = payload .* conj(scrambler(1:length(payload)));
            payloadAll = [payloadAll; payloadDescrambled]; %#ok<AGROW>
            nVar = max(1/finalFrameSNR, 1e-6);
            fullFrameDecoded = zeros(16*phyParams.K,1);
            for iBlk = 1:16
                idx = (iBlk-1)*8100 + (1:8100);
                softBits = HelperCCSDSFACMDemodulate(payloadDescrambled(idx), acmFmt, nVar);
                decoded = HelperSCCCDecode(softBits(:), acmFmt, numIter);
                fullFrameDecoded((iBlk-1)*phyParams.K+1:iBlk*phyParams.K) = decoded;
            end

            try
                [fdACMFormat, fdHasPilots, decFail] = HelperCCSDSFACMFDRecover(agcOut(1:64));
            catch
                fdACMFormat = acmFmt;
                fdHasPilots = cfg.HasPilots;
                decFail = false;
            end
            fdOK = ~decFail && fdACMFormat == acmFmt && fdHasPilots == cfg.HasPilots;
            if fdOK
                dbgFDOK = dbgFDOK + 1;
            else
                dbgFDFail = dbgFDFail + 1;
            end

            decodedCols = 0;
            if fdOK
                [~, decodedBuffer, extraBits] = HelperCCSDSFACMTFSynchronize( ...
                    [extraBits; fullFrameDecoded], phyParams.ASM, phyParams.NumInputBits);
                if ~isempty(decodedBuffer)
                    decodedCols = size(decodedBuffer,2);
                    if isnan(acquisitionFrame)
                        acquisitionFrame = frameIndex;
                    end
                    prnSeq = satcom.internal.ccsds.tmrandseq(phyParams.NumInputBits);
                    finalBits = xor(decodedBuffer(33:end,:) > 0, prnSeq);
                    if frameIndex > simParams.InitalSyncFrames
                        decodedTFBits = [decodedTFBits, finalBits]; %#ok<AGROW>
                        dbgBERFrames = dbgBERFrames + size(finalBits,2);
                    end
                    dbgTFOK = dbgTFOK + 1;
                else
                    dbgTFEmpty = dbgTFEmpty + 1;
                end
            end
            decodedFrames = decodedFrames + 1;
            if debugFACM && (frameIndex <= 5 || frameIndex == simParams.InitalSyncFrames || mod(frameIndex,20) == 0)
                fprintf('   [FACM DEBUG] frame=%3d cfoEst=%+.2fHz SNR=%.2fdB phaseOK=%d FD=%d/%d/%d TFcols=%d payload=%d decodedTFcols=%d\n', ...
                    frameIndex, cfoEst, 10*log10(finalFrameSNR), phaseRecovered, ...
                    fdACMFormat, fdHasPilots, ~decFail, decodedCols, length(payload), size(decodedTFBits,2));
            end
        else
            dbgPayloadShort = dbgPayloadShort + 1;
            if debugFACM && frameIndex <= 5
                fprintf('   [FACM DEBUG] frame=%3d short payload=%d, expected=%d\n', ...
                    frameIndex, length(payload), 8100*16);
            end
        end
        frameIndex = frameIndex + 1; %#ok<NASGU>
    end

    if debugFACM
        fprintf('   [FACM DEBUG] summary: PL=%d phaseOK=%d phaseFail=%d FDOK=%d FDFail=%d TFOK=%d TFEmpty=%d shortPayload=%d BERcols=%d decodedFrames=%d\n', ...
            max(frameIndex-1,0), dbgPhaseOK, dbgPhaseFail, dbgFDOK, dbgFDFail, dbgTFOK, dbgTFEmpty, dbgPayloadShort, dbgBERFrames, decodedFrames);
    end

    if isempty(payloadAll)
        payloadAll = fineSynced;
    end
    if isempty(snrVals)
        snrMean = NaN;
    else
        snrMean = mean(snrVals);
    end
    facmStats = localFACMStats(cfoEstVals, residualCFOVals, dbgFDOK, dbgFDFail, dbgTFOK, dbgTFEmpty, ...
        acquisitionFrame, plFrameSize, fSym);
end

function tf = useFACMPostPilotLS(opt)
    tf = false;
    mode = "";
    if isfield(opt,'facmEqualizerMode') && ~isempty(opt.facmEqualizerMode)
        mode = lower(string(opt.facmEqualizerMode));
    elseif isfield(opt,'equalizerMode') && ~isempty(opt.equalizerMode)
        mode = lower(string(opt.equalizerMode));
    end
    tf = any(strcmp(mode, ["pilot-ls", "pilot-post-ls"]));
end

function stats = localFACMStats(cfoEstVals, residualCFOVals, fdOK, fdFail, tfOK, tfEmpty, acquisitionFrame, plFrameSize, fSym)
    stats = struct();
    cfoEstVals = cfoEstVals(:);
    cfoEstVals = cfoEstVals(isfinite(cfoEstVals));
    stats.cfoEstimates_Hz = cfoEstVals;
    if isempty(cfoEstVals)
        stats.cfo_est_Hz = NaN;
    else
        nTail = min(10, numel(cfoEstVals));
        stats.cfo_est_Hz = median(cfoEstVals(end-nTail+1:end));
    end

    residualCFOVals = residualCFOVals(:);
    residualCFOVals = residualCFOVals(isfinite(residualCFOVals));
    stats.residualCFOEstimates_Hz = residualCFOVals;
    if isempty(residualCFOVals)
        stats.residualCFO_Hz = NaN;
    else
        nTail = min(10, numel(residualCFOVals));
        stats.residualCFO_Hz = median(residualCFOVals(end-nTail+1:end));
    end

    stats.FDOK = fdOK;
    stats.FDFail = fdFail;
    stats.TFOK = tfOK;
    stats.TFEmpty = tfEmpty;
    stats.AcquisitionFrames = acquisitionFrame;
    if isfinite(acquisitionFrame) && isfinite(plFrameSize) && isfinite(fSym) && fSym > 0
        stats.AcquisitionTime_s = acquisitionFrame * plFrameSize / fSym;
    else
        stats.AcquisitionTime_s = NaN;
    end
end

function residCFO_Hz = localFACMResidualCFOFromFrameMarker(frameMarker, refFM, fSym)
    residCFO_Hz = NaN;
    if isempty(frameMarker) || isempty(refFM) || ~isfinite(fSym) || fSym <= 0
        return;
    end

    y = frameMarker(:);
    ref = refFM(:);
    L = min([numel(y), numel(ref), 256]);
    if L < 16
        return;
    end

    phErr = unwrap(angle(y(1:L) .* conj(ref(1:L))));
    n = (0:L-1).';
    coef = polyfit(n, phErr, 1);
    residCFO_Hz = coef(1) * fSym / (2*pi);
end

function [payloadWithPilots, frameDescriptor] = facmPhaseRecoveryKeepPilots(framesym, pilots, refFM)
    numSymPerBlk = 540;
    numFD = 64;
    numSubSections = 240;
    symPerSubSection = 556;

    codeBlks = reshape(framesym(321:end), symPerSubSection, []);
    pilotBlks = reshape(pilots, 16, []);
    Tm = angle(sum(codeBlks(end-15:end,:).*conj(pilotBlks)));

    payloadWithPilotsTemp = zeros(symPerSubSection, numSubSections);

    Tm0 = angle(sum(framesym(256-15:256).*conj(refFM(end-15:end))));
    phasesInBlk = wrapToPi(Tm0 + (wrapToPi(Tm(1)-Tm0)/(numSymPerBlk+numFD+1))*(1:(numSymPerBlk+numFD)));
    phaseCompensated = framesym(257:256+numFD+numSymPerBlk).*exp(-1j*phasesInBlk.');
    frameDescriptor = phaseCompensated(1:numFD);
    payloadWithPilotsTemp(1:numSymPerBlk,1) = phaseCompensated(numFD+1:end);
    payloadWithPilotsTemp(numSymPerBlk+1:end,1) = codeBlks(numSymPerBlk+1:end,1).*exp(-1j*Tm(1));

    for iSubSection = 2:numSubSections
        % Match the MathWorks helper data phase convention, and keep pilots
        % phase-normalized to their own pilot block for post-equalizer training.
        phasesInBlk = Tm(iSubSection-1) * ones(numSymPerBlk,1);
        payloadWithPilotsTemp(1:numSymPerBlk,iSubSection) = ...
            codeBlks(1:numSymPerBlk,iSubSection).*exp(-1j*phasesInBlk);
        payloadWithPilotsTemp(numSymPerBlk+1:end,iSubSection) = ...
            codeBlks(numSymPerBlk+1:end,iSubSection).*exp(-1j*Tm(iSubSection));
    end

    payloadWithPilots = payloadWithPilotsTemp(:);
end

function [payloadNoPilots, payloadWithPilotsEq] = facmPostPilotLSEqualize(payloadWithPilots, rxParams, opt)
    y = payloadWithPilots(:);
    n = length(y);
    payloadWithPilotsEq = y;

    if ~isfield(rxParams,'PilotIndices') || ~isfield(rxParams,'PilotSeq') || ...
            isempty(rxParams.PilotIndices) || isempty(rxParams.PilotSeq)
        payloadNoPilots = facmRemovePilots(payloadWithPilotsEq, rxParams);
        return;
    end

    nTaps = 11;
    if isfield(opt,'facmEqualizerTaps') && ~isempty(opt.facmEqualizerTaps)
        nTaps = max(3, round(double(opt.facmEqualizerTaps)));
    elseif isfield(opt,'pilotLSTaps') && ~isempty(opt.pilotLSTaps)
        nTaps = max(3, round(double(opt.pilotLSTaps)));
    end
    if mod(nTaps,2) == 0
        nTaps = nTaps + 1;
    end
    dly = floor(nTaps/2);

    reg = 1e-2;
    if isfield(opt,'pilotLSReg') && ~isempty(opt.pilotLSReg)
        reg = max(0, double(opt.pilotLSReg));
    elseif isfield(opt,'facmEqualizerReg') && ~isempty(opt.facmEqualizerReg)
        reg = max(0, double(opt.facmEqualizerReg));
    end

    pilotIdx = double(rxParams.PilotIndices(:));
    pilotRef = rxParams.PilotSeq(:);
    valid = pilotIdx > dly & pilotIdx <= n-dly;
    pilotIdx = pilotIdx(valid);
    pilotRef = pilotRef(valid);
    if numel(pilotIdx) < max(32, 2*nTaps)
        payloadNoPilots = facmRemovePilots(payloadWithPilotsEq, rxParams);
        return;
    end

    maxTrain = inf;
    if isfield(opt,'pilotLSMaxTrain') && ~isempty(opt.pilotLSMaxTrain)
        maxTrain = max(32, round(double(opt.pilotLSMaxTrain)));
    end
    if isfinite(maxTrain) && numel(pilotIdx) > maxTrain
        pick = round(linspace(1, numel(pilotIdx), maxTrain));
        pilotIdx = pilotIdx(pick);
        pilotRef = pilotRef(pick);
    end

    X = zeros(numel(pilotIdx), nTaps);
    for k = 1:numel(pilotIdx)
        ii = pilotIdx(k);
        X(k,:) = y(ii+dly:-1:ii-dly).';
    end

    w = (X' * X + reg * eye(nTaps)) \ (X' * pilotRef);
    yEq = filter(w, 1, y);
    if dly > 0
        yEq = [yEq(dly+1:end); repmat(yEq(end), dly, 1)];
    end

    if ~isfield(opt,'normalizeEqualizerOutput') || logical(opt.normalizeEqualizerOutput)
        inPower = mean(abs(y).^2) + eps;
        outPower = mean(abs(yEq).^2) + eps;
        yEq = yEq / sqrt(outPower) * sqrt(inPower);
    end

    payloadWithPilotsEq = yEq(:);
    payloadNoPilots = facmRemovePilots(payloadWithPilotsEq, rxParams);
end

function payloadNoPilots = facmRemovePilots(payloadWithPilots, rxParams)
    y = payloadWithPilots(:);
    mask = true(length(y),1);
    if isfield(rxParams,'PilotIndices') && ~isempty(rxParams.PilotIndices)
        idx = double(rxParams.PilotIndices(:));
        idx = idx(idx >= 1 & idx <= length(y));
        mask(idx) = false;
    end
    payloadNoPilots = y(mask);
end

function [evmPct, merDB] = facmPilotErrorMetric(payloadWithPilots, rxParams)
    evmPct = NaN;
    merDB = NaN;
    if ~isfield(rxParams,'PilotIndices') || ~isfield(rxParams,'PilotSeq') || ...
            isempty(rxParams.PilotIndices) || isempty(rxParams.PilotSeq)
        return;
    end
    idx = double(rxParams.PilotIndices(:));
    valid = idx >= 1 & idx <= length(payloadWithPilots);
    idx = idx(valid);
    ref = rxParams.PilotSeq(valid);
    if isempty(idx)
        return;
    end
    err = payloadWithPilots(idx) - ref(:);
    evmPct = sqrt(mean(abs(err).^2) / (mean(abs(ref).^2) + eps)) * 100;
    merDB = -20*log10(evmPct/100 + eps);
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

function y = facmFrameMarkerEqualize(x, rxParams, opt, acmFmt)
    y = x(:);
    refFM = rxParams.RefFM;
    useEq = isfield(opt,'enableHChannel') && logical(opt.enableHChannel);
    if isfield(opt,'enableFACMEqualizer') && ~isempty(opt.enableFACMEqualizer)
        useEq = logical(opt.enableFACMEqualizer);
    end
    if ~useEq || length(y) < 256 || isempty(refFM)
        return;
    end

    nTaps = 7;
    if isfield(opt,'facmEqualizerTaps') && ~isempty(opt.facmEqualizerTaps)
        nTaps = max(3, round(double(opt.facmEqualizerTaps)));
    end
    if mod(nTaps, 2) == 0
        nTaps = nTaps + 1;
    end
    mu = 1e-3;
    if isfield(opt,'facmEqualizerReg') && ~isempty(opt.facmEqualizerReg)
        mu = max(0, double(opt.facmEqualizerReg));
    end
    mode = "frame-ls";
    if isfield(opt,'facmEqualizerMode') && ~isempty(opt.facmEqualizerMode)
        mode = lower(string(opt.facmEqualizerMode));
    elseif isfield(opt,'equalizerMode') && ~isempty(opt.equalizerMode)
        eqMode = lower(string(opt.equalizerMode));
        if any(strcmp(eqMode, ["dd16apsk", "cma16apsk", "rde16apsk", ...
                "rde-apsk", "rdeapsk", "pilot-lms", "pilot-dfe", "frame-ls"]))
            mode = eqMode;
        end
    end
    if mode == "pilot-dfe" && ...
            ~(isfield(opt,'enableExperimentalPilotDFE') && logical(opt.enableExperimentalPilotDFE))
        mode = "pilot-lms";
    end

    dly = floor(nTaps/2);
    trainLen = min(256, length(refFM));
    rows = trainLen - nTaps + 1;
    if rows < 32
        return;
    end

    X = zeros(rows, nTaps);
    d = zeros(rows, 1);
    for r = 1:rows
        center = r + dly;
        X(r,:) = y(center + dly : -1 : center - dly).';
        d(r) = refFM(center);
    end
    w = (X' * X + mu * eye(nTaps)) \ (X' * d);

    if any(strcmp(mode, ["dd16apsk", "cma16apsk", "rde16apsk", ...
            "rde-apsk", "rdeapsk", "pilot-lms", "pilot-dfe"]))
        refConst = HelperCCSDSFACMReferenceConstellation(acmFmt);
        refConst = refConst(:) ./ sqrt(mean(abs(refConst(:)).^2) + eps);
        yNorm = y ./ sqrt(mean(abs(y).^2) + eps);
        if any(strcmp(mode, ["pilot-lms", "pilot-dfe"]))
            w = facmPilotLMSWeights(yNorm, w, rxParams, nTaps, opt);
            if mode == "pilot-dfe"
                yEq = facmPilotDFEEqualize(yNorm, w, rxParams, refConst, nTaps, opt);
            else
                yEq = filter(w, 1, yNorm);
            end
        elseif any(strcmp(mode, ["rde16apsk", "rde-apsk", "rdeapsk"]))
            w = facmRDEAPSKEqualizer(yNorm, w, refConst, nTaps, opt);
            yEq = filter(w, 1, yNorm);
        else
            w = facmDecisionDirectedEqualizer(yNorm, w, refConst, nTaps, opt);
            yEq = filter(w, 1, yNorm);
        end
    else
        yEq = filter(w, 1, y);
    end
    if dly > 0 && mode ~= "pilot-dfe"
        yEq = [yEq(dly+1:end); repmat(yEq(end), dly, 1)];
    end
    pwr = mean(abs(yEq).^2);
    if isfinite(pwr) && pwr > 0
        y = yEq ./ sqrt(pwr);
    else
        y = yEq;
    end

    if isfield(opt,'debugFACM') && logical(opt.debugFACM)
        preErr = mean(abs(y(1:trainLen) - refFM(1:trainLen)).^2);
        postErr = mean(abs(yEq(1:trainLen) - refFM(1:trainLen)).^2);
        fprintf('   [FACM EQ] mode=%s, taps=%d, train=%d, preMSE=%.4g, postMSE=%.4g\n', ...
            mode, nTaps, trainLen, preErr, postErr);
    end
end

function w = facmPilotLMSWeights(y, w0, rxParams, nTaps, opt)
    y = y(:);
    w = w0(:);
    dly = floor(nTaps/2);

    [knownIdx, knownSym] = facmKnownTrainingSymbols(rxParams, length(y));
    if numel(knownIdx) < 32
        return;
    end

    mu = 2e-4;
    if isfield(opt,'pilotLMSStep') && ~isempty(opt.pilotLMSStep)
        mu = max(0, double(opt.pilotLMSStep));
    elseif isfield(opt,'lmsStep') && ~isempty(opt.lmsStep)
        mu = max(0, double(opt.lmsStep));
    end
    nPass = 1;
    if isfield(opt,'pilotLMSPasses') && ~isempty(opt.pilotLMSPasses)
        nPass = max(1, round(double(opt.pilotLMSPasses)));
    end
    if mu == 0
        return;
    end

    knownSym = knownSym ./ sqrt(mean(abs(knownSym).^2) + eps);
    for pass = 1:nPass
        for k = 1:numel(knownIdx)
            n = knownIdx(k);
            if n <= dly || n > length(y)-dly
                continue;
            end
            xv = y(n+dly:-1:n-dly);
            z = w.' * xv;
            err = z - knownSym(k);
            normX = real(xv' * xv) + 1e-6;
            w = w - (mu / normX) * conj(err) * conj(xv);
        end
    end
end

function yEq = facmPilotDFEEqualize(y, w, rxParams, refConst, nTaps, opt)
    y = y(:);
    w = w(:);
    dly = floor(nTaps/2);
    nFb = 3;
    if isfield(opt,'dfeFeedbackTaps') && ~isempty(opt.dfeFeedbackTaps)
        nFb = max(0, round(double(opt.dfeFeedbackTaps)));
    end
    muFF = 8e-5;
    if isfield(opt,'dfeFFStep') && ~isempty(opt.dfeFFStep)
        muFF = max(0, double(opt.dfeFFStep));
    end
    muFB = 8e-5;
    if isfield(opt,'dfeFBStep') && ~isempty(opt.dfeFBStep)
        muFB = max(0, double(opt.dfeFBStep));
    end
    errGate = 0.45;
    if isfield(opt,'dfeDecisionErrorGate') && ~isempty(opt.dfeDecisionErrorGate)
        errGate = max(0, double(opt.dfeDecisionErrorGate));
    end

    [knownIdx, knownSym] = facmKnownTrainingSymbols(rxParams, length(y));
    knownSym = knownSym ./ sqrt(mean(abs(knownSym).^2) + eps);
    knownMap = containers.Map('KeyType','double','ValueType','any');
    for k = 1:numel(knownIdx)
        knownMap(knownIdx(k)) = knownSym(k);
    end

    b = zeros(nFb,1);
    fb = zeros(nFb,1);
    yEq = zeros(size(y));
    for n = dly+1:length(y)-dly
        xv = y(n+dly:-1:n-dly);
        zFF = w.' * xv;
        if n <= 320
            yEq(n) = zFF;
            continue;
        end
        z = zFF;
        if nFb > 0
            z = z - b.' * fb;
        end

        isKnown = isKey(knownMap, n);
        if isKnown
            dHat = knownMap(n);
            allowUpdate = true;
        else
            [dist, idx] = min(abs(z - refConst));
            dHat = refConst(idx);
            allowUpdate = isfinite(dist) && dist <= errGate;
        end

        if allowUpdate
            err = z - dHat;
            normX = real(xv' * xv) + 1e-6;
            w = w - (muFF / normX) * conj(err) * conj(xv);
            if nFb > 0
                normFb = real(fb' * fb) + 1e-6;
                b = b + (muFB / normFb) * conj(err) * conj(fb);
            end
        end

        yEq(n) = z;
        if nFb > 0
            fb = [dHat; fb(1:end-1)];
        end
    end

    if dly > 0
        yEq(1:dly) = yEq(dly+1);
        yEq(end-dly+1:end) = yEq(end-dly);
    end
end

function [idx, sym] = facmKnownTrainingSymbols(rxParams, frameLen)
    idxFM = (1:min(256, frameLen)).';
    symFM = rxParams.RefFM(1:numel(idxFM));
    idx = idxFM(:);
    sym = symFM(:);

    if isfield(rxParams,'PilotIndices') && isfield(rxParams,'PilotSeq') && ...
            ~isempty(rxParams.PilotIndices) && ~isempty(rxParams.PilotSeq)
        idxPilot = 320 + double(rxParams.PilotIndices(:));
        valid = idxPilot >= 1 & idxPilot <= frameLen;
        idx = [idx; idxPilot(valid)];
        sym = [sym; rxParams.PilotSeq(valid)];
    end

    [idx, order] = sort(idx);
    sym = sym(order);
end

function w = facmRDEAPSKEqualizer(y, w0, refConst, nTaps, opt)
    y = y(:);
    w = w0(:);
    dly = floor(nTaps/2);

    radii = sort(unique(round(abs(refConst(:))*1e5)/1e5));
    radii = radii(radii > 1e-6);
    if numel(radii) < 2
        return;
    end

    mu = 8e-5;
    if isfield(opt,'rdeStep') && ~isempty(opt.rdeStep)
        mu = max(0, double(opt.rdeStep));
    elseif isfield(opt,'cmaStep') && ~isempty(opt.cmaStep)
        mu = max(0, double(opt.cmaStep));
    end

    nPass = 2;
    if isfield(opt,'rdePasses') && ~isempty(opt.rdePasses)
        nPass = max(1, round(double(opt.rdePasses)));
    end

    startIdx = 257 + dly;
    if isfield(opt,'rdeStart') && ~isempty(opt.rdeStart)
        startIdx = max(dly+1, round(double(opt.rdeStart)));
    elseif isfield(opt,'ddEqualizerStart') && ~isempty(opt.ddEqualizerStart)
        startIdx = max(dly+1, round(double(opt.ddEqualizerStart)));
    end
    stopIdx = length(y) - dly;
    if stopIdx <= startIdx || mu == 0
        return;
    end

    for pass = 1:nPass
        for n = startIdx:stopIdx
            xv = y(n+dly:-1:n-dly);
            z = w.' * xv;
            az = abs(z);
            if az < 1e-8 || ~isfinite(az)
                continue;
            end
            [~, idx] = min(abs(az - radii));
            dHat = radii(idx) * z / az;
            err = z - dHat;
            normX = real(xv' * xv) + 1e-6;
            w = w - (mu / normX) * conj(err) * conj(xv);
        end
    end

    useDDPolish = true;
    if isfield(opt,'rdeUseDDPolish') && ~isempty(opt.rdeUseDDPolish)
        useDDPolish = logical(opt.rdeUseDDPolish);
    end
    if useDDPolish
        optDD = opt;
        if ~isfield(optDD,'ddEqualizerPasses') || isempty(optDD.ddEqualizerPasses)
            optDD.ddEqualizerPasses = 1;
        end
        if ~isfield(optDD,'ddEqualizerStep') || isempty(optDD.ddEqualizerStep)
            optDD.ddEqualizerStep = mu * 0.5;
        end
        w = facmDecisionDirectedEqualizer(y, w, refConst, nTaps, optDD);
    end
end

function w = facmDecisionDirectedEqualizer(y, w0, refConst, nTaps, opt)
    y = y(:);
    w = w0(:);
    dly = floor(nTaps/2);
    mu = 2e-4;
    if isfield(opt,'ddEqualizerStep') && ~isempty(opt.ddEqualizerStep)
        mu = max(0, double(opt.ddEqualizerStep));
    elseif isfield(opt,'cmaStep') && ~isempty(opt.cmaStep)
        mu = max(0, double(opt.cmaStep));
    end
    nPass = 2;
    if isfield(opt,'ddEqualizerPasses') && ~isempty(opt.ddEqualizerPasses)
        nPass = max(1, round(double(opt.ddEqualizerPasses)));
    end
    startIdx = 257 + dly;
    if isfield(opt,'ddEqualizerStart') && ~isempty(opt.ddEqualizerStart)
        startIdx = max(dly+1, round(double(opt.ddEqualizerStart)));
    end
    stopIdx = length(y) - dly;
    if stopIdx <= startIdx
        return;
    end

    for pass = 1:nPass
        for n = startIdx:stopIdx
            xv = y(n+dly:-1:n-dly);
            z = w.' * xv;
            [~, idx] = min(abs(z - refConst));
            dHat = refConst(idx);
            err = z - dHat;
            normX = real(xv' * xv) + 1e-6;
            w = w - (mu / normX) * conj(err) * conj(xv);
        end
    end
end

function [berVal, lockRate] = computeFACMBER(decodedTFBits, txBits, simParams, decodedFrames, opt)
    berVal = 0.5;
    lockRate = min(1, decodedFrames/max(simParams.NumFramesForBER,1));
    if isempty(decodedTFBits)
        lockRate = 0;
        if nargin >= 5 && isfield(opt,'debugFACM') && logical(opt.debugFACM)
            fprintf('   [FACM BER DEBUG] no decoded TF bits available\n');
        end
        return;
    end

    if nargin >= 5 && isfield(opt,'debugFACM') && logical(opt.debugFACM)
        nTx = size(txBits,2);
        nRx = size(decodedTFBits,2);
        numErr = inf(max(nTx-nRx+1,1),1);
        if nTx >= nRx
            for iSliding = 1:nTx-nRx+1
                txCompBits = txBits(:,iSliding+(0:nRx-1));
                numErr(iSliding) = nnz(xor(txCompBits,decodedTFBits));
            end
            [bestErr, bestIdx] = min(numErr);
            fprintf('   [FACM BER DEBUG] txCols=%d rxCols=%d bestStartCol=%d err=%d bits=%d ber=%.6g\n', ...
                nTx, nRx, bestIdx, bestErr, numel(decodedTFBits), bestErr/max(numel(decodedTFBits),1));
        else
            fprintf('   [FACM BER DEBUG] txCols=%d rxCols=%d (rx longer than tx)\n', nTx, nRx);
        end
    end

    berinfo = struct('NumBitsInError',0,'TotalNumBits',0,'BitErrorRate',0);
    berinfo = HelperBitErrorRate(txBits, decodedTFBits, berinfo);
    berVal = berinfo.BitErrorRate;
end

function acmFmt = resolveFACMFormat(opt)
    if isfield(opt,'acmFormat')
        acmFmt = double(opt.acmFormat);
    elseif isfield(opt,'ACMFormat')
        acmFmt = double(opt.ACMFormat);
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
        case {'tpc','product','product-code','product code'}
            code = 'TPC';
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
    elseif isfield(opt,'ACMFormat')
        acmFmt = double(opt.ACMFormat);
    end
    if isfield(opt,'acmFormat') || isfield(opt,'ACMFormat')
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
        if strcmp(code,'TPC')
            r = localTPCEffectiveRate(getfieldwithdefault(opt, 'TPCCodeRate', ...
                getfieldwithdefault(opt, 'tpcCodeRate', 'native')));
            return;
        end
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
function y = uqpskCarrierRecover(x, aRatio, loopBW)

% 借鉴 UQPSKDem.m 的载波相位误差：
%   e_theta = sign(I_est)*Q_est*ARatio - sign(Q_est)*I_est
%
% 输入：
%   x      : 定时同步后的符号流
%   aRatio : UQPSK Q路幅度压缩比
%   loopBW : 环路带宽，建议先 0.001 ~ 0.01 之间试
%
% 输出：
%   y      : 载波相位恢复后的符号流

    x = x(:);
    y = zeros(size(x));

    if isempty(x)
        return;
    end

    if nargin < 3 || isempty(loopBW)
        loopBW = 0.002;
    end

    % 简单 PI 环路参数
    Kp = loopBW;
    Ki = loopBW^2 / 4;

    theta = 0;
    integ = 0;

    for n = 1:numel(x)
        % 去旋转
        z = x(n) * exp(-1j*theta);
        y(n) = z;

        I = real(z);
        Q = imag(z);

        sI = sign(I);
        sQ = sign(Q);

        if sI == 0
            sI = 1;
        end
        if sQ == 0
            sQ = 1;
        end

        % 老师 UQPSK 相位误差公式
        e = sI * Q * aRatio - sQ * I;

        % PI 环路更新
        integ = integ + Ki * e;
        theta = theta + integ + Kp * e;

        % 防止 theta 数值越积越大
        if theta > pi
            theta = theta - 2*pi;
        elseif theta < -pi
            theta = theta + 2*pi;
        end
    end
end


function [y, cfo_est] = uqpskFourthPowerFFTCoarseCFO(x, Fs, maxCFOHz, fftLen)
%UQPSKFOURTHPOWERFFTCOARSECFO
% UQPSK 非数据辅助 4次幂 FFT 粗频偏估计
%
% 思路：
%   接收信号含 CFO：x(n) ≈ s(n)*exp(j*2*pi*f0*n/Fs)
%   4次幂后：x(n)^4 ≈ s(n)^4 * exp(j*2*pi*4*f0*n/Fs)
%   因此频谱峰大致出现在 4*f0，最后除以 4 得到 CFO。
%
% 注意：
%   标准 QPSK 做 4次幂时数据调制消除更彻底；
%   UQPSK 因为 I/Q 不等幅、不等速率，4次幂后仍有数据残留，
%   但通常仍能形成可检测的 CFO 谱峰。

    x = x(:);

    if nargin < 3 || isempty(maxCFOHz)
        maxCFOHz = Fs/16;
    end

    if nargin < 4 || isempty(fftLen)
        fftLen = 2^17;
    end

    if isempty(x)
        y = x;
        cfo_est = 0;
        return;
    end

    L = min(numel(x), fftLen);
    if L < 1024
        y = x;
        cfo_est = 0;
        return;
    end

    xUse = x(1:L);

    % 去直流，避免 DC 峰影响
    xUse = xUse - mean(xUse);

    % 幅度归一，减轻 RRC 包络起伏对 4次幂的影响
    mag = abs(xUse);
    mag(mag < eps) = eps;
    xUnit = xUse ./ mag;

    sig4 = xUnit.^4;

    Nfft = 2^nextpow2(L);
    win = hamming(L);

    X4 = fftshift(fft(sig4 .* win, Nfft));
    fAx = (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);

    P4 = abs(X4).^2;

    % 4次幂后峰在 4*CFO，所以搜索范围是 ±4*maxCFOHz
    searchMask = abs(fAx) <= 4*maxCFOHz;
    if ~any(searchMask)
        y = x;
        cfo_est = 0;
        return;
    end

    P4(~searchMask) = 0;

    [~, ip] = max(P4);
    fPeak = fAx(ip);

    cfo_est = fPeak / 4;

    n = (0:numel(x)-1).';
    y = x .* exp(-1j*2*pi*cfo_est/Fs*n);
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
