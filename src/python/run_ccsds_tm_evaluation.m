function varargout = run_ccsds_tm_evaluation(varargin)
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
%               'channelCoding','none','RolloffFactor',0.35,'hasASM',true, ...
%               'hasPilots',true,'WaveformMode','ordinaryTM');
%   m = run_ccsds_tm_evaluation(p);
% p = struct('modType','QPSK','symbolRate',1e6,'sps',8, ...
%            'snr',20,'cfo',2000,'phaseOffset',15,'delay',0.2, ...
%            'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
%            'RolloffFactor',0.35,'hasASM',true,'RandomizerEnabled',true, ...
%            'NumBytesInTransferFrame',1115, ...
%            'RandomizerFECPosition','afterEncoding','DataPathMode','single', ...
%            'WaveformMode','ordinaryTM', ...
%            'SpacecraftID',1,'VirtualChannelID',0, ...
%            'HasSecondaryHeader',false,'HasOCF',false,'HasFECF',false, ...
%            'showFigures',false);
% p.debugTMFrame = true;
% m = run_ccsds_tm_evaluation(p);
% addpath('E:\web_code\react\fft_project\react-fft\src\python');
%
% matFilePath = 'E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat';
%
% p = struct( ...
%     'modType','QPSK', ...
%     'symbolRate',1e6, ...
%     'sps',8, ...
%     'snr',30, ...
%     'cfo',0, ...
%     'phaseOffset',0, ...
%     'delay',0, ...
%     ...
%     'channelCoding','convolutional', ...
%     'ConvolutionalCodeRate','1/2', ...
%     'NumBytesInTransferFrame',1115, ...
%     ...
%     'RolloffFactor',0.35, ...
%     'hasASM',true, ...
%     'RandomizerEnabled',false, ...
%     ...
%     'berWarmUpFrames',20, ...
%     'berFrames',40, ...
%     ...
%     'enableHChannel',true, ...
%     'HMode','h_matrix_file', ...
%     'channelFilePath',matFilePath, ...
%     'channelInterpolationMethod','linear', ...
%     'interpolateChannelDelays',false, ...
%     ...
%     'normalizeHChannel',false, ...              % 保留真实 H 增益
%     'enableEqualizer',true, ...
%     'equalizerMode','mmse', ...
%     'equalizerReg',[], ...                      % empty => scale-aware automatic MMSE
%     'normalizeEqualizerOutput',true, ...        % 接收端均衡后幅度整理/数字AGC
%     ...
%     'inputLevelDbm',-10, ...
%     'showFigures',true, ...
%     'showPipelineFigure',true, ...
%     'showDamageBudgetFigure',false, ...
%     'showPowerFigure',true);
%
% m = run_ccsds_tm_evaluation(p);
% r = jsondecode(m);



%   2) 用前端的 JSON 直接粘进来调（验一致性）
%   m = run_ccsds_tm_evaluation('{"modType":"QPSK","symbolRate":1e6,"sps":8,"snr":12,"cfo":0,"phaseOffset":0,"channelCoding":"none","RolloffFactor":0.35}');
%

tStart = tic;

[opt, outputMode] = parseEvaluationEntryInputs(varargin{:});
imagePaths = {};

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
        if getLogicalField(opt, 'showPowerFigure', false) || ...
                getLogicalField(opt, 'showChannelPowerFigure', false)
            ccsdsEvalPlotFigures('channelPower', res, ctx, opt);
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
    if isfield(res,'GMSKDetectorUsed'), frontResult.GMSKDetectorUsed = res.GMSKDetectorUsed; end
    if isfield(res,'AcquisitionFrames'), frontResult.AcquisitionFrames = res.AcquisitionFrames; end
    if isfield(res,'AcquisitionTime_s'), frontResult.AcquisitionTime_s = res.AcquisitionTime_s; end
    railMetricFields = localSplitRailMetricFields();
    for iRailMetric = 1:numel(railMetricFields)
        railMetricName = railMetricFields{iRailMetric};
        if isfield(res, railMetricName)
            frontResult.(railMetricName) = res.(railMetricName);
        end
    end
    if isfield(res,'APSKASMEnabled'), frontResult.APSKASMEnabled = res.APSKASMEnabled; end
    if isfield(res,'APSKASMApplied'), frontResult.APSKASMApplied = res.APSKASMApplied; end
    if isfield(res,'APSKASMResidualCFO_Hz'), frontResult.APSKASMResidualCFO_Hz = res.APSKASMResidualCFO_Hz; end
    if isfield(res,'APSKASMPhase_deg'), frontResult.APSKASMPhase_deg = res.APSKASMPhase_deg; end
    if isfield(res,'APSKASMFirstPos'), frontResult.APSKASMFirstPos = res.APSKASMFirstPos; end
    if isfield(res,'APSKASMNumFrames'), frontResult.APSKASMNumFrames = res.APSKASMNumFrames; end
    if isfield(res,'APSKASMReason'), frontResult.APSKASMReason = res.APSKASMReason; end
    if isfield(res,'TMAPSKPilotsEnabled'), frontResult.TMAPSKPilotsEnabled = res.TMAPSKPilotsEnabled; end
    if isfield(res,'TMAPSKPilotsApplied'), frontResult.TMAPSKPilotsApplied = res.TMAPSKPilotsApplied; end
    if isfield(res,'TMAPSKPilotReason'), frontResult.TMAPSKPilotReason = res.TMAPSKPilotReason; end
    if isfield(res,'TMAPSKPilotStart'), frontResult.TMAPSKPilotStart = res.TMAPSKPilotStart; end
    if isfield(res,'TMAPSKPilotCount'), frontResult.TMAPSKPilotCount = res.TMAPSKPilotCount; end
    if isfield(res,'TMAPSKPilotDataSymbols'), frontResult.TMAPSKPilotDataSymbols = res.TMAPSKPilotDataSymbols; end
    if isfield(res,'TMAPSKPilotCFO_Hz'), frontResult.TMAPSKPilotCFO_Hz = res.TMAPSKPilotCFO_Hz; end
    if isfield(res,'TMAPSKPilotMeanAmp'), frontResult.TMAPSKPilotMeanAmp = res.TMAPSKPilotMeanAmp; end
    if isfield(res,'TMAPSKPilotCorrectionMode'), frontResult.TMAPSKPilotCorrectionMode = res.TMAPSKPilotCorrectionMode; end
    if isfield(res,'HasASM'), frontResult.HasASM = res.HasASM; end
    if isfield(res,'ASMLength'), frontResult.ASMLength = res.ASMLength; end
    if isfield(res,'ASMHex'), frontResult.ASMHex = res.ASMHex; end
    if isfield(res,'RandomizerEnabled'), frontResult.RandomizerEnabled = res.RandomizerEnabled; end
    if isfield(res,'RandomizerFECPosition'), frontResult.RandomizerFECPosition = res.RandomizerFECPosition; end
    if isfield(res,'DataPathMode'), frontResult.DataPathMode = res.DataPathMode; end
    if isfield(res,'SplitReceiverImplementation'), frontResult.SplitReceiverImplementation = res.SplitReceiverImplementation; end
    splitReceiverDecisionFields = { ...
        'SplitReceiverIQPhase', 'UQPSKSymSkip', ...
        'UQPSKSymSkipSelectionMethod', ...
        'SplitReceiverStructureSelectionMethod', ...
        'SplitReceiverStructureScore', ...
        'SplitReceiverTMValidFrames', ...
        'SplitReceiverTMMinValidFrames', ...
        'SplitReceiverTMMaxCounterRun', ...
        'SplitReceiverTMOrientationScore'};
    for iDecisionField = 1:numel(splitReceiverDecisionFields)
        decisionField = splitReceiverDecisionFields{iDecisionField};
        if isfield(res, decisionField)
            frontResult.(decisionField) = res.(decisionField);
        end
    end
    if isfield(res,'WaveformMode'), frontResult.WaveformMode = res.WaveformMode; end
    if isfield(res,'UQPSKRRatio'), frontResult.UQPSKRRatio = res.UQPSKRRatio; end
    if isfield(res,'UQPSKARatio'), frontResult.UQPSKARatio = res.UQPSKARatio; end
    if isfield(res,'IFramesPerQFrame'), frontResult.IFramesPerQFrame = res.IFramesPerQFrame; end
    frontResult.Fs           = res.Fs;
    if isfield(res,'cfo_est_Hz'),    frontResult.cfo_est_Hz = res.cfo_est_Hz; end
    if isfield(res,'IFHz'),          frontResult.IFHz = res.IFHz; end
    if isfield(res,'centerFrequencyHz'), frontResult.centerFrequencyHz = res.centerFrequencyHz; end
    if isfield(res,'inputLevelDbm'), frontResult.inputLevelDbm = res.inputLevelDbm; end
    if isfield(res,'carrierFreqHz'), frontResult.carrierFreqHz = res.carrierFreqHz; end
    if isfield(res,'ACMFormat'), frontResult.ACMFormat = res.ACMFormat; end
    if isfield(res,'fmDetectedFrames'), frontResult.fmDetectedFrames = res.fmDetectedFrames; end
    if isfield(res,'fmTotalFrames'),    frontResult.fmTotalFrames = res.fmTotalFrames; end

    % --- 输入回显 ---
    frontResult.snr_in   = res.snr_in;
    if isfield(res,'NoisePlacement'), frontResult.NoisePlacement = res.NoisePlacement; end
    if isfield(res,'NoiseMode'), frontResult.NoiseMode = res.NoiseMode; end
    if isfield(res,'NoisePSD_dBmHz'), frontResult.NoisePSD_dBmHz = res.NoisePSD_dBmHz; end
    if isfield(res,'NoiseBandwidthHz'), frontResult.NoiseBandwidthHz = res.NoiseBandwidthHz; end
    if isfield(res,'NoisePower_dBm'), frontResult.NoisePower_dBm = res.NoisePower_dBm; end
    if isfield(res,'NoiseEquivalentSNR_dB'), frontResult.NoiseEquivalentSNR_dB = res.NoiseEquivalentSNR_dB; end
    if isfield(res,'NoiseReferenceLevel_dBm'), frontResult.NoiseReferenceLevel_dBm = res.NoiseReferenceLevel_dBm; end
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
    if isfield(opt,'TPCInterleaver'), frontResult.TPCInterleaver = opt.TPCInterleaver;
    elseif isfield(opt,'tpcInterleaver'), frontResult.TPCInterleaver = opt.tpcInterleaver; end
    if isfield(res,'CodeRate'), frontResult.CodeRate = res.CodeRate;
    elseif isfield(opt,'CodeRate') && ~strcmp(char(opt.CodeRate),'N/A'), frontResult.CodeRate = opt.CodeRate; end
    if isfield(opt,'channelCoding'),         frontResult.channelCoding = opt.channelCoding; end
    if isfield(res,'HEnabled'), frontResult.HEnabled = res.HEnabled; end
    if isfield(res,'HMode'), frontResult.HMode = res.HMode; end
    if isfield(res,'HNumTaps'), frontResult.HNumTaps = res.HNumTaps; end
    if isfield(res,'HEffectiveTaps'), frontResult.HEffectiveTaps = res.HEffectiveTaps; end
    if isfield(res,'HGain_dB'), frontResult.HGain_dB = res.HGain_dB; end
    if isfield(res,'HChannelMeta')
        frontResult.channelMeta = res.HChannelMeta;
        frontResult.HChannelMeta = res.HChannelMeta;
    end

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

    if isfield(res,'HEnabled')
        frontResult.stats.HEnabled = res.HEnabled;
        frontResult.stats.HMode = res.HMode;
        frontResult.stats.HNumTaps = res.HNumTaps;
        frontResult.stats.HEffectiveTaps = res.HEffectiveTaps;
        frontResult.stats.HGain_dB = res.HGain_dB;
    end
    if isfield(res,'HChannelMeta')
        frontResult.stats.ChannelType = res.HChannelMeta.ChannelType;
        frontResult.stats.ChannelPathCount = res.HChannelMeta.PathCount;
        frontResult.stats.ChannelSampleRateHz = res.HChannelMeta.ChannelSampleRateHz;
        frontResult.stats.WaveformSampleRateHz = res.HChannelMeta.WaveformSampleRateHz;
        frontResult.stats.ChannelMeanGain_dB = res.HChannelMeta.MeanGain_dB;
        if isfield(res.HChannelMeta,'OutOfRangeMode')
            frontResult.stats.ChannelOutOfRangeMode = res.HChannelMeta.OutOfRangeMode;
            frontResult.stats.HSourceDuration_s = res.HChannelMeta.ChannelSourceDuration_s;
            frontResult.stats.HWaveformDuration_s = res.HChannelMeta.WaveformDuration_s;
            frontResult.stats.ExceedsHDuration = res.HChannelMeta.ExceedsChannelDuration;
        end
    end

    frontResult.imagePaths = imagePaths;
    varargout = packEvaluationOutputs(frontResult, imagePaths, outputMode, nargout);

catch ME
    errMsg = ME.message;
    if ~isempty(ME.stack)
        errMsg = sprintf('%s (at %s line %d)', errMsg, ME.stack(1).name, ME.stack(1).line);
    end
    fprintf(2, '[run_ccsds_tm_evaluation ERROR] %s\n', errMsg);
    detectorOnError = 'not-applicable';
    if isfield(opt, 'modType') && contains(upper(string(opt.modType)), 'GMSK')
        requestedMode = lower(string(getfieldwithdefault( ...
            opt, 'GMSKDetectionMode', 'legacy-diff')));
        if requestedMode == "official-viterbi-frame-reset"
            detectorOnError = 'official';
        else
            detectorOnError = char(requestedMode);
        end
    end
    err = struct( ...
        'success',  false, ...
        'errorIdentifier', string(ME.identifier), ...
        'error',    errMsg, ...
        'errorMsg', errMsg, ...
        'GMSKDetectorUsed', detectorOnError, ...
        'BER', -2, 'ber', -2, ...
        'ElapsedTime', toc(tStart));
    varargout = packEvaluationOutputs(err, imagePaths, outputMode, nargout);
end
end

% =========================================================
% 单次仿真：复用主脚本的处理链路 + 提取所有中间信号
% =========================================================
function [opt, outputMode] = parseEvaluationEntryInputs(varargin)
    outputMode = "json";
    defaults = defaultEvaluationParams();

    if nargin < 1 || isempty(varargin{1})
        opt = defaults;
        return;
    end

    firstArg = varargin{1};
    if ischar(firstArg) || isstring(firstArg)
        firstText = strtrim(char(firstArg));
        if nargin >= 2 && ~looksLikeJsonText(firstText)
            opt = parseEvaluationParams(varargin{2}, defaults);
            opt = configureHMatrixEntry(opt, firstText);
            outputMode = "struct";
            return;
        end

        if looksLikeJsonText(firstText)
            opt = parseEvaluationParams(firstArg, defaults);
            return;
        end

        opt = configureHMatrixEntry(defaults, firstText);
        outputMode = "struct";
        return;
    end

    opt = parseEvaluationParams(firstArg, defaults);
end

function opt = parseEvaluationParams(rawParams, defaults)
    if nargin < 1 || isempty(rawParams)
        opt = defaults;
        return;
    end

    if ischar(rawParams) || isstring(rawParams)
        rawText = strtrim(char(rawParams));
        if looksLikeJsonText(rawText)
            opt = jsondecode(rawText);
        else
            error('run_ccsds_tm_evaluation:InvalidParams', ...
                'String params must be JSON unless passed as the first channel-file argument.');
        end
    elseif isstruct(rawParams)
        opt = rawParams;
    else
        error('run_ccsds_tm_evaluation:InvalidParams', ...
            'Params must be a struct or JSON string.');
    end

    rejectLegacyEvaluationFields(opt);
    opt = applyEvaluationDefaults(opt, defaults);
end

function opt = configureHMatrixEntry(opt, matFilePath)
    if isempty(matFilePath)
        error('run_ccsds_tm_evaluation:MissingChannelFile', ...
            'H-matrix channel file path is empty.');
    end

    opt.channelFilePath = char(matFilePath);
    opt.channel_file_path = char(matFilePath);
    opt.matFilePath = char(matFilePath);
    opt.enableHChannel = true;

    if ~hasNonEmptyField(opt, 'HMode')
        opt.HMode = 'h_matrix_file';
    end
    if ~hasNonEmptyField(opt, 'channel_mode')
        opt.channel_mode = 'custom';
    end
    if ~hasNonEmptyField(opt, 'enableEqualizer') && ...
            ~hasNonEmptyField(opt, 'enable_channel_equalization') && ...
            ~hasNonEmptyField(opt, 'channelEqualization')
        opt.enableEqualizer = true;
    end
end

function opt = applyEvaluationDefaults(opt, defaults)
    names = fieldnames(defaults);
    for k = 1:numel(names)
        name = names{k};
        if ~isfield(opt, name) || isempty(opt.(name))
            opt.(name) = defaults.(name);
        end
    end
end

function defaults = defaultEvaluationParams()
    defaults = struct('modType','QPSK','symbolRate',1e6,'sps',8, ...
        'snr',12,'cfo',0,'phaseOffset',0,'delay',0, ...
        'channelCoding','none','RolloffFactor',0.35, ...
        'RandomizerEnabled',false, ...
        'RandomizerFECPosition','afterEncoding', ...
        'DataPathMode','single', ...
        'WaveformMode','ordinaryTM');
end

function rejectLegacyEvaluationFields(opt)
    legacyNames = { ...
        'hasRandomizer', 'HasRandomizer', ...
        'RandomizerPosition', 'RandomizerPathMode', ...
        'useFACM', 'UseFACM', ...
        'waveformSource', 'WaveformSource'};
    canonicalNames = { ...
        'RandomizerEnabled', 'RandomizerEnabled', ...
        'RandomizerFECPosition', 'DataPathMode', ...
        'WaveformMode', 'WaveformMode', ...
        'WaveformMode', 'WaveformMode'};

    for k = 1:numel(legacyNames)
        if isfield(opt, legacyNames{k})
            error('run_ccsds_tm_evaluation:LegacyParameterName', ...
                'Parameter "%s" has been removed. Use "%s".', ...
                legacyNames{k}, canonicalNames{k});
        end
    end
end

function tf = looksLikeJsonText(textValue)
    textValue = strtrim(char(textValue));
    tf = ~isempty(textValue) && any(textValue(1) == ['{' '[']);
end

function tf = hasNonEmptyField(s, name)
    tf = isfield(s, name) && ~isempty(s.(name));
end

function outs = packEvaluationOutputs(resultStruct, imagePaths, outputMode, requestedOutputs)
    if requestedOutputs >= 2 || strcmpi(char(outputMode), 'struct')
        n = max(1, requestedOutputs);
        outs = cell(1, n);
        outs{1} = resultStruct;
        if requestedOutputs >= 2
            outs{2} = imagePaths;
        end
        for k = 3:requestedOutputs
            outs{k} = [];
        end
    else
        outs = {jsonencode(resultStruct)};
    end
end

function [res, ctx] = runOneShot(opt)

    makeNum = @(f) str2double(strrep(string(f), ',', ''));
    if ischar(opt.symbolRate), fSym = makeNum(opt.symbolRate); else, fSym = double(opt.symbolRate); end
    if ischar(opt.sps),        sps  = makeNum(opt.sps);        else, sps  = double(opt.sps);        end
    randomizerEnabled = logical(opt.RandomizerEnabled);
    hasASM        = false;
    if isfield(opt,'hasASM')
        hasASM = opt.hasASM;
    elseif localHasASMOption(opt)
        hasASM = true;
    end
    randomizerFECPosition = char(opt.RandomizerFECPosition);
    dataPathMode = char(opt.DataPathMode);
    if ~any(strcmpi(randomizerFECPosition, {'afterEncoding','beforeEncoding'}))
        error('run_ccsds_tm_evaluation:InvalidRandomizerFECPosition', ...
            ['Unsupported RandomizerFECPosition="%s". Use ' ...
             'afterEncoding or beforeEncoding.'], randomizerFECPosition);
    end
    if ~any(strcmpi(dataPathMode, ...
            {'single','dualIQ','unequalDualIQ'}))
        error('run_ccsds_tm_evaluation:InvalidDataPathMode', ...
            ['Unsupported DataPathMode="%s". Use single, dualIQ, ', ...
             'or unequalDualIQ.'], dataPathMode);
    end
    if ~hasASM && localHasASMOption(opt)
        hasASM = true;
        fprintf('[ASM setup] asmLength/asmHex supplied; enabling HasASM=true.\n');
    end
    splitPathDebug = getLogicalField(opt, 'splitPathDebug', false);
    opt.RandomizerEnabled = randomizerEnabled;
    opt.RandomizerFECPosition = randomizerFECPosition;
    opt.DataPathMode = dataPathMode;
    opt.splitPathDebug = splitPathDebug;

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

    args = {'SamplesPerSymbol', sps, 'RandomizerEnabled', randomizerEnabled, 'HasASM', hasASM};
    args = [args, {'RandomizerFECPosition', char(randomizerFECPosition), ...
                   'DataPathMode', char(dataPathMode)}];
    args = appendASMArgs(args, opt);
    if splitPathDebug
        args = [args, {'SplitPathDebug', true}];
    end
    modStr = string(opt.modType);

    if isFACMEvaluation(opt, modStr)
        [res, ctx] = runFACMOneShot(opt, fSym, sps);
        res.RandomizerEnabled = logical(randomizerEnabled);
        res.RandomizerFECPosition = char(randomizerFECPosition);
        res.DataPathMode = char(dataPathMode);
        res.WaveformMode = char(opt.WaveformMode);
        return;
    end

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

        if any(strcmp(codeKey, ["convolutional", "concatenated"])) && isfield(opt,'ConvolutionalCodeRate')
            rate = char(opt.ConvolutionalCodeRate);
            if ~strcmp(rate,'N/A')
                args = [args, {'ConvolutionalCodeRate', rate}];
            end
        end
        if contains(codeKey,'tpc')
            args = [args, {'TPCCodeRate', localTPCCodeRateValue(opt), ...
                           'TPCBlocksPerTF', tpcBlocksPerTF, ...
                           'TPCInterleaver', localTPCInterleaverValue(opt)}];
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
            case {'BPSK','QPSK','8PSK','OQPSK','16QAM','32QAM','16APSK','32APSK'}
                args = [args, {'FilterSpanInSymbols', 10}];
        end
        if contains(modStr,'APSK')
            hasTMAPSKPilots = true;
            if isfield(opt,'HasTMAPSKPilots') && ~isempty(opt.HasTMAPSKPilots)
                hasTMAPSKPilots = localFlagValue(opt.HasTMAPSKPilots);
            elseif isfield(opt,'hasTMAPSKPilots') && ~isempty(opt.hasTMAPSKPilots)
                hasTMAPSKPilots = localFlagValue(opt.hasTMAPSKPilots);
            end
            opt.HasTMAPSKPilots = hasTMAPSKPilots;
            if hasTMAPSKPilots
                opt.TMAPSKPilotInterval = getfieldnumeric(opt, 'TMAPSKPilotInterval', 512);
                opt.TMAPSKPilotLength = getfieldnumeric(opt, 'TMAPSKPilotLength', 32);
                opt.TMAPSKPilotPreambleLength = getfieldnumeric(opt, 'TMAPSKPilotPreambleLength', 64);
                if contains(codeKey, 'convolutional') && ...
                        ~(isfield(opt,'TMAPSKPilotCorrectionMode') && ~isempty(opt.TMAPSKPilotCorrectionMode))
                    opt.TMAPSKPilotCorrectionMode = 'phaseinterp';
                    opt.TMAPSKPilotPhaseSmoothWindow = getfieldnumeric(opt, 'TMAPSKPilotPhaseSmoothWindow', 3);
                end
            end
            args = [args, {'HasTMAPSKPilots', hasTMAPSKPilots, ...
                           'TMAPSKPilotInterval', getfieldnumeric(opt, 'TMAPSKPilotInterval', 512), ...
                           'TMAPSKPilotLength', getfieldnumeric(opt, 'TMAPSKPilotLength', 32), ...
                           'TMAPSKPilotPreambleLength', getfieldnumeric(opt, 'TMAPSKPilotPreambleLength', 64)}];
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
%% 创建发送端波形

    tmWaveGen = ccsdsTMWaveformGenerator(args{:});
    tmWaveInfo = info(tmWaveGen);
    disp(tmWaveGen)
    disp(tmWaveInfo)
    % TM发送端内部一帧需要多少bit
    fprintf('[TX %s] NumInputBits=%d, ActualCodeRate=%.6f\n', ...
        char(codeStr), tmWaveGen.NumInputBits, tmWaveInfo.ActualCodeRate);
    Fs = fSym * sps;
    isEqualSplitPath = strcmpi(dataPathMode, 'dualIQ');
    isUnequalSplitPath = strcmpi(dataPathMode, 'unequalDualIQ');
    inputBitsPerCall = tmWaveGen.NumInputBits;
    if isEqualSplitPath && mod(inputBitsPerCall, 2) ~= 0
        error('run_ccsds_tm_evaluation:SplitInputLengthNotEven', ...
            'Split mode requires an even NumInputBits, got %d.', inputBitsPerCall);
    end
    if isUnequalSplitPath && mod(inputBitsPerCall, 3) ~= 0
        error('run_ccsds_tm_evaluation:UnequalSplitInputLength', ...
            ['unequalDualIQ requires NumInputBits to contain two I frames ', ...
             'and one Q frame; got %d bits.'], inputBitsPerCall);
    end

    if isEqualSplitPath
        bitsPerFrame = inputBitsPerCall / 2;   % 单 rail 的 TM frame
    elseif isUnequalSplitPath
        bitsPerFrame = inputBitsPerCall / 3;
    else
        bitsPerFrame = inputBitsPerCall;
    end
    if isUnequalSplitPath
        fprintf(['[Actual TF] unequalDualIQ super-input=%d bits ', ...
            '(I=2x%d, Q=1x%d bits), railFrameBytes=%.3f\n'], ...
            tmWaveGen.NumInputBits, bitsPerFrame, bitsPerFrame, ...
            bitsPerFrame/8);
    else
        fprintf('[Actual TF] NumInputBits=%d, NumInputBytes=%.3f\n', ...
                 tmWaveGen.NumInputBits, tmWaveGen.NumInputBits/8);
    end
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
    if isEqualSplitPath
        msgI = zeros(bitsPerFrame * totalFrames, 1, 'int8');
        msgQ = zeros(bitsPerFrame * totalFrames, 1, 'int8');
        validTxFrames = cell(2*totalFrames, 1);
        validTxFrameInfo = cell(2*totalFrames, 1);
        validTxFrameBytes = cell(2*totalFrames, 1);
    elseif isUnequalSplitPath
        msgI = zeros(2 * bitsPerFrame * totalFrames, 1, 'int8');
        msgQ = zeros(bitsPerFrame * totalFrames, 1, 'int8');
        validTxFrames = cell(3*totalFrames, 1);
        validTxFrameInfo = cell(3*totalFrames, 1);
        validTxFrameBytes = cell(3*totalFrames, 1);
    else
        msg = zeros(bitsPerFrame * totalFrames, 1, 'int8');
        validTxFrames = cell(totalFrames, 1);
        validTxFrameInfo = cell(totalFrames, 1);
        validTxFrameBytes = cell(totalFrames, 1);
    end
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

        idx = (i-1)*bitsPerFrame + (1:bitsPerFrame);
        if isEqualSplitPath
            tfOptI = tfOpt;
            tfOptI.MasterChannelFrameCount = mod(2*(i-1), 256);
            tfOptI.VirtualChannelFrameCount = mod(2*(i-1), 256);
            payloadBytesI = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBitsI, frameBytesI, frameInfoI] = make_ccsds_tm_transfer_frame(payloadBytesI, tfOptI);
            currentI = int8(frameBitsI(:));
            if numel(currentI) ~= bitsPerFrame
                error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                    'Generated I-rail TM frame length mismatch: got %d bits, expected %d bits.', ...
                    numel(currentI), bitsPerFrame);
            end

            tfOptQ = tfOpt;
            tfOptQ.MasterChannelFrameCount = mod(2*(i-1)+1, 256);
            tfOptQ.VirtualChannelFrameCount = mod(2*(i-1)+1, 256);
            payloadBytesQ = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBitsQ, frameBytesQ, frameInfoQ] = make_ccsds_tm_transfer_frame(payloadBytesQ, tfOptQ);
            currentQ = int8(frameBitsQ(:));
            if numel(currentQ) ~= bitsPerFrame
                error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                    'Generated Q-rail TM frame length mismatch: got %d bits, expected %d bits.', ...
                    numel(currentQ), bitsPerFrame);
            end

            msgI(idx) = currentI;
            msgQ(idx) = currentQ;
            validTxFrames{2*i-1} = currentI;
            validTxFrames{2*i} = currentQ;
            validTxFrameInfo{2*i-1} = frameInfoI;
            validTxFrameInfo{2*i} = frameInfoQ;
            validTxFrameBytes{2*i-1} = frameBytesI;
            validTxFrameBytes{2*i} = frameBytesQ;
        elseif isUnequalSplitPath
            tfOptI1 = tfOpt;
            tfOptI1.MasterChannelFrameCount = mod(2*(i-1), 256);
            tfOptI1.VirtualChannelFrameCount = mod(2*(i-1), 256);
            payloadBytesI1 = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBitsI1, frameBytesI1, frameInfoI1] = ...
                make_ccsds_tm_transfer_frame(payloadBytesI1, tfOptI1);
            currentI1 = int8(frameBitsI1(:));

            tfOptI2 = tfOpt;
            tfOptI2.MasterChannelFrameCount = mod(2*(i-1)+1, 256);
            tfOptI2.VirtualChannelFrameCount = mod(2*(i-1)+1, 256);
            payloadBytesI2 = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBitsI2, frameBytesI2, frameInfoI2] = ...
                make_ccsds_tm_transfer_frame(payloadBytesI2, tfOptI2);
            currentI2 = int8(frameBitsI2(:));

            tfOptQ = tfOpt;
            tfOptQ.MasterChannelFrameCount = mod(i-1, 256);
            tfOptQ.VirtualChannelFrameCount = mod(i-1, 256);
            payloadBytesQ = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBitsQ, frameBytesQ, frameInfoQ] = ...
                make_ccsds_tm_transfer_frame(payloadBytesQ, tfOptQ);
            currentQ = int8(frameBitsQ(:));

            if any([numel(currentI1), numel(currentI2), ...
                    numel(currentQ)] ~= bitsPerFrame)
                error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                    ['Generated unequalDualIQ rail frame length does not ', ...
                     'match %d bits.'], bitsPerFrame);
            end

            idxI1 = (2*(i-1))*bitsPerFrame + (1:bitsPerFrame);
            idxI2 = (2*(i-1)+1)*bitsPerFrame + (1:bitsPerFrame);
            idxQ = (i-1)*bitsPerFrame + (1:bitsPerFrame);
            msgI(idxI1) = currentI1;
            msgI(idxI2) = currentI2;
            msgQ(idxQ) = currentQ;

            refBase = 3*(i-1);
            validTxFrames{refBase+1} = currentI1;
            validTxFrames{refBase+2} = currentI2;
            validTxFrames{refBase+3} = currentQ;
            validTxFrameInfo{refBase+1} = frameInfoI1;
            validTxFrameInfo{refBase+2} = frameInfoI2;
            validTxFrameInfo{refBase+3} = frameInfoQ;
            validTxFrameBytes{refBase+1} = frameBytesI1;
            validTxFrameBytes{refBase+2} = frameBytesI2;
            validTxFrameBytes{refBase+3} = frameBytesQ;
        else
            payloadBytes = uint8(randi([0 255], 1, numBytesActualTF));
            [frameBits, frameBytes, frameInfo] = make_ccsds_tm_transfer_frame(payloadBytes, tfOpt);
            currentFrame = int8(frameBits(:));
            if numel(currentFrame) ~= bitsPerFrame
                error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                    'Generated TM frame length mismatch: got %d bits, expected %d bits.', ...
                    numel(currentFrame), bitsPerFrame);
            end

            msg(idx) = currentFrame;
            validTxFrames{i} = currentFrame;
            validTxFrameInfo{i} = frameInfo;
            validTxFrameBytes{i} = frameBytes;
        end
    end
    if isEqualSplitPath
        msg = [msgI; msgQ];
        if splitPathDebug
            firstIId = localTMFrameID(validTxFrames{1});
            firstQId = localTMFrameID(validTxFrames{2});
            fprintf(['[SplitPath input] enabled: frames/rail=%d, railFrameBits=%d, ', ...
                'msgI=%d bits, msgQ=%d bits, msg=[I;Q]=%d bits, firstIds I/Q=%d/%d\n'], ...
                totalFrames, bitsPerFrame, numel(msgI), numel(msgQ), numel(msg), ...
                firstIId, firstQId);
            fprintf('[SplitPath input] BER reference order: validTxFrames={I1,Q1,I2,Q2,...}\n');
        end
    elseif isUnequalSplitPath
        msg = [msgI; msgQ];
        if splitPathDebug
            fprintf(['[UQPSK unequal input] groups=%d, frameBits=%d, ', ...
                'I frames=%d, Q frames=%d, msg=[I;Q]=%d bits\n'], ...
                totalFrames, bitsPerFrame, 2*totalFrames, totalFrames, ...
                numel(msg));
            fprintf(['[UQPSK unequal input] BER reference order: ', ...
                '{I1,I2,Q1,I3,I4,Q2,...}\n']);
        end
    end
    if getLogicalField(opt, 'debugTMFrame', false)
        localPrintTMFrameInfo(validTxFrameInfo{1}, validTxFrameBytes{1}, 1);
        if numel(validTxFrameInfo) >= 2
            localPrintTMFrameInfo(validTxFrameInfo{2}, validTxFrameBytes{2}, 2);
        end
    end
    [txWaveform, encodedBits] = tmWaveGen(msg);
    debugCodedBoundary = getLogicalField(opt, 'debugCodedBoundary', false);
    assignin('base', 'debugCodedBoundaryEnabled', debugCodedBoundary);
    if debugCodedBoundary
        assignin('base', 'debugCodedFrameSyncPrintLimit', ...
            max(0, round(getfieldnumeric(opt, 'debugCodedFrameSyncPrintLimit', 80))));
        assignin('base', 'debugCodedFrameSyncPrintCount', 0);
        assignin('base', 'debugTMEncodedBits', int8(encodedBits(:) ~= 0));
        fprintf('[Coded DEBUG] stored tx encodedBits for boundary check: %d bits\n', numel(encodedBits));
    else
        evalin('base', 'if exist(''debugTMEncodedBits'',''var''), clear debugTMEncodedBits; end');
        evalin('base', 'if exist(''debugCodedFrameSyncPrintLimit'',''var''), clear debugCodedFrameSyncPrintLimit; end');
        evalin('base', 'if exist(''debugCodedFrameSyncPrintCount'',''var''), clear debugCodedFrameSyncPrintCount; end');
    end
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

    [txAfterH, hInfo, hState] = applyHChannelDamage(txWithDelay, opt, Fs);
    actualCodeRateForHStats = getfieldnumeric(tmWaveInfo, 'ActualCodeRate', NaN);
    bitsPerSymbolForHStats = getfieldnumeric(tmWaveInfo, 'NumBitsPerSymbol', NaN);
    localPrintHMatrixFrameStats(hState, opt, Fs, sps, bitsPerFrame, ...
        actualCodeRateForHStats, bitsPerSymbolForHStats, totalFrames);

    noisePlacement = getNoisePlacementMode(opt);
    noiseInfo = makeLegacyNoiseInfo(snr_val);
    if noisePlacement == "afterEqualizer"
        rxEqualizedClean = applyKnownChannelEqualizer(txAfterH, opt, snr_val, false, hState);
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise(rxEqualizedClean, opt, Fs, snr_val, rxEqualizedClean);
        rxWaveform = rxNoisyWaveform;
    else
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise(txAfterH, opt, Fs, snr_val, txWithDelay);
        rxWaveform = applyKnownChannelEqualizer(rxNoisyWaveform, opt, noiseInfo.EquivalentSNR_dB, false, hState);
    end
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
        % The official Viterbi branch consumes the oversampled CPM
        % waveform, so residual CFO accumulates throughout a coded frame.
        % Use a longer observation than the original 2^17-point estimate.
        Lfft   = min(length(rxWaveform), 2^19);
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
        binHz = Fs/Nfft;
        ipOffset = localParabolicSpectrumPeakOffset(Psq, ip);
        inOffset = localParabolicSpectrumPeakOffset(Psq, in);
        positivePeakHz = fAx(ip) + ipOffset*binHz;
        negativePeakHz = fAx(in) + inOffset*binHz;
        cfo_est = (positivePeakHz + negativePeakHz) / 4;
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

        % The official GMSK Viterbi detector must see the oversampled CPM
        % waveform.  Keep the existing 1-sps path for plots/metrics, but
        % route the coarse-CFO-corrected waveform to BER only when the
        % explicit experimental mode is requested.
        gmskModeFrontend = "legacy-diff";
        if isfield(opt,'GMSKDetectionMode') && ~isempty(opt.GMSKDetectionMode)
            gmskModeFrontend = lower(string(opt.GMSKDetectionMode));
        end
        if strcmp(gmskModeFrontend, "official-viterbi-frame-reset")
            fineSyncedForBER = rxSynced;
        end

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

            uqpskMaxCFOHz = 0.05 * fSym;   % default search: +/-5% symbol rate
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
            useCoarseFreqSync = true;
            if contains(modStr,'APSK')
                useCoarseFreqSync = false;
                if isfield(opt,'enableAPSKCoarseFrequencyCompensator') && ...
                        ~isempty(opt.enableAPSKCoarseFrequencyCompensator)
                    useCoarseFreqSync = localFlagValue(opt.enableAPSKCoarseFrequencyCompensator);
                end
            end

            if useCoarseFreqSync
                coarseFreqSync = comm.CoarseFrequencyCompensator( ...
                    'Modulation', coarseMod, ...
                    'SampleRate', Fs, ...
                    'FrequencyResolution', 1e3);
                coarseSynced = coarseFreqSync(rxWaveform);
            else
                coarseSynced = rxWaveform;
            end

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
            elseif contains(modStr,'APSK')
                useAPSKQAMCarrierSync = abs(getf(opt,'cfo',0)) > 0 || abs(getf(opt,'phaseOffset',0)) > 0;
                if strcmpi(char(codeStr), 'RS')
                    useAPSKQAMCarrierSync = false;
                end
                if isfield(opt,'enableAPSKQAMCarrierSync') && ~isempty(opt.enableAPSKQAMCarrierSync)
                    useAPSKQAMCarrierSync = localFlagValue(opt.enableAPSKQAMCarrierSync);
                end
                if useAPSKQAMCarrierSync
                    carrierSync = comm.CarrierSynchronizer( ...
                        'Modulation','QAM', ...
                        'SamplesPerSymbol',1, ...
                        'DampingFactor',1/sqrt(2), ...
                        'NormalizedLoopBandwidth',0.001);
                else
                    carrierSync = [];
                end
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

            if isempty(carrierSync)
                fineSynced = TimeSynced;
            else
                fineSynced = carrierSync(TimeSynced);
            end
        end
    end
    if ~exist('fineSyncedForBER','var')
        fineSyncedForBER = fineSynced;
    end

    tmAPSKPilotInfo = localEmptyTMAPSKPilotInfo();
    if contains(modStr,'APSK') && getLogicalField(opt, 'HasTMAPSKPilots', false) && ...
            exist('fineSynced','var') && ~isempty(fineSynced)
        [fineSynced, tmAPSKPilotInfo] = localCorrectAndRemoveTMAPSKPilots( ...
            fineSynced, opt, fSym);
        fineSyncedForBER = fineSynced;
    end

    apskASMInfo = localEmptyAPSKASMInfo();
    if contains(modStr,'APSK') && ~tmAPSKPilotInfo.Applied && ...
            exist('fineSynced','var') && ~isempty(fineSynced)
        [fineSynced, apskASMInfo] = localAPSKASMFineCorrection( ...
            fineSynced, modStr, codeStr, opt, fSym, hasASM);
        fineSyncedForBER = fineSynced;
    elseif contains(modStr,'APSK') && tmAPSKPilotInfo.Applied
        apskASMInfo.Enabled = false;
        apskASMInfo.Reason = 'skipped because TMAPSK pilots were applied';
    end

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)') && ...
            contains(modStr,'APSK') && exist('TimeSynced','var') && ~isempty(TimeSynced)
        ts_pwr = mean(abs(TimeSynced).^2);
        fprintf('[APSK RX post-timing] symbols=%d, mean|s|^2=%.4f\n', length(TimeSynced), ts_pwr);
        assignin('base','debug_apsk_rx_timesync', TimeSynced(1:min(2000,end)));
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
    [berVal, lockRate, bestRot, berStats] = computeBER(fineSyncedForBER, validTxFrames, modStr, opt, randomizerEnabled, hasASM, btVal, numWarmUp);

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
    res.NoisePlacement = char(noisePlacement);
    res.NoiseMode = char(noiseInfo.Mode);
    if isfinite(noiseInfo.PSD_dBmHz)
        res.NoisePSD_dBmHz = noiseInfo.PSD_dBmHz;
        res.NoiseBandwidthHz = noiseInfo.BandwidthHz;
        res.NoisePower_dBm = noiseInfo.NoisePower_dBm;
        res.NoiseEquivalentSNR_dB = noiseInfo.EquivalentSNR_dB;
        res.NoiseReferenceLevel_dBm = noiseInfo.ReferenceLevel_dBm;
    end
    res.cfo_in   = cfo_val;
    res.phase_in = getf(opt,'phaseOffset',0);
    res.delay_in = delay_val;
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.inputLevelDbm = getInputLevelDbm(opt, 0);
    res.HasASM = logical(hasASM);
    res.RandomizerEnabled = logical(randomizerEnabled);
    res.RandomizerFECPosition = char(randomizerFECPosition);
    res.DataPathMode = char(dataPathMode);
    res.WaveformMode = char(opt.WaveformMode);
    if isUnequalSplitPath
        res.UQPSKRRatio = 2;
        res.UQPSKARatio = 2;
        res.IFramesPerQFrame = 2;
    end
    if hasASM
        res.ASMLength = numel(localTMASM(opt, codeStr));
        [asmHexForResult, hasASMHexForResult] = localASMOptionHex(opt);
        if hasASMHexForResult
            res.ASMHex = asmHexForResult;
        end
    else
        res.ASMLength = 0;
    end
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
    res.GMSKDetectorUsed = berStats.GMSKDetectorUsed;
    res.AcquisitionFrames = berStats.AcquisitionFrames;
    res.AcquisitionTime_s = berStats.AcquisitionTime_s;
    if isfield(berStats, 'SplitReceiverImplementation')
        res.SplitReceiverImplementation = berStats.SplitReceiverImplementation;
    end
    splitReceiverDecisionFields = { ...
        'SplitReceiverIQPhase', 'UQPSKSymSkip', ...
        'UQPSKSymSkipSelectionMethod', ...
        'SplitReceiverStructureSelectionMethod', ...
        'SplitReceiverStructureScore', ...
        'SplitReceiverTMValidFrames', ...
        'SplitReceiverTMMinValidFrames', ...
        'SplitReceiverTMMaxCounterRun', ...
        'SplitReceiverTMOrientationScore'};
    for iDecisionField = 1:numel(splitReceiverDecisionFields)
        decisionField = splitReceiverDecisionFields{iDecisionField};
        if isfield(berStats, decisionField)
            res.(decisionField) = berStats.(decisionField);
        end
    end
    railMetricFields = localSplitRailMetricFields();
    for iRailMetric = 1:numel(railMetricFields)
        railMetricName = railMetricFields{iRailMetric};
        res.(railMetricName) = berStats.(railMetricName);
    end
    res.APSKASMEnabled = apskASMInfo.Enabled;
    res.APSKASMApplied = apskASMInfo.Applied;
    res.APSKASMResidualCFO_Hz = apskASMInfo.CFO_Hz;
    res.APSKASMPhase_deg = apskASMInfo.Phase_deg;
    res.APSKASMFirstPos = apskASMInfo.FirstPos;
    res.APSKASMNumFrames = apskASMInfo.NumFrames;
    res.APSKASMReason = apskASMInfo.Reason;
    res.TMAPSKPilotsEnabled = tmAPSKPilotInfo.Enabled;
    res.TMAPSKPilotsApplied = tmAPSKPilotInfo.Applied;
    res.TMAPSKPilotReason = tmAPSKPilotInfo.Reason;
    res.TMAPSKPilotStart = tmAPSKPilotInfo.Start;
    res.TMAPSKPilotCount = tmAPSKPilotInfo.NumPilots;
    res.TMAPSKPilotDataSymbols = tmAPSKPilotInfo.NumDataSymbols;
    res.TMAPSKPilotCFO_Hz = tmAPSKPilotInfo.CFO_Hz;
    res.TMAPSKPilotMeanAmp = tmAPSKPilotInfo.MeanAmp;
    res.TMAPSKPilotCorrectionMode = tmAPSKPilotInfo.CorrectionMode;
    res.Fs          = Fs;
    res.HEnabled    = hInfo.Enabled;
    res.HMode       = char(hInfo.Mode);
    res.HNumTaps    = hInfo.NumTaps;
    res.HEffectiveTaps = hInfo.EffectiveTaps;
    res.HGain_dB    = hInfo.Gain_dB;
    if isfield(hInfo, 'Meta')
        res.HChannelMeta = hInfo.Meta;
    end
    if exist('fmRxInfo','var')
        res.fmRxInfo = fmRxInfo;
        res.fmDetectedFrames = fmRxInfo.detectedFrames;
        res.fmTotalFrames = fmRxInfo.totalFrames;
    end


    %传给前端

    % 给绘图用 — fineSynced 应用 best 旋转后再画,星座视觉对齐参考
    ctx.txWaveform   = txWaveform;
    ctx.channelInput = txWithDelay;
    ctx.channelOutput = txAfterH;
    ctx.rxNoisyWaveform = rxNoisyWaveform;
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

    isFACM = isfield(res,'ACMFormat');

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

function levelDbm = getInputLevelDbm(s, defv)
    names = {'inputLevelDbm','input_level_dbm','outputPowerDbm','output_power_dbm'};
    levelDbm = defv;
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                raw = str2double(strrep(string(raw), ',', ''));
            end
            raw = double(raw);
            raw = raw(1);
            if isfinite(raw)
                levelDbm = raw;
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

function [yOut, hInfo, hState] = applyHChannelDamage(xIn, opt, sampleRateHz)
    % H 信道损伤入口。
    % 当前主链路仍然是单发单收/单路接收, 所以这里先支持 SISO 多径 FIR:
    %   H = [h0 h1 h2 ...]
    % 表示:
    %   y[n] = h0*x[n] + h1*x[n-1] + h2*x[n-2] + ...
    % 后续如果要做 SIMO/MIMO, 可以在这里继续扩展, 主接收链路不用改。
    xIn = xIn(:);
    if nargin < 3 || isempty(sampleRateHz)
        sampleRateHz = estimateWaveformSampleRate(opt);
    end

    hInfo = struct( ...
        'Enabled', false, ...
        'Mode', "", ...
        'NumTaps', 0, ...
        'EffectiveTaps', 0, ...
        'Gain_dB', 0);
    hState = struct('Enabled', false, 'Mode', "", 'hasHMatrix', false);

    if ~isfield(opt,'enableHChannel') || ~logical(opt.enableHChannel)
        yOut = xIn;
        return;
    end

    mode = lower(getOptionString(opt, {'HMode','hMode','channelMode','channel_mode'}, "auto"));
    if mode == "auto" || (mode == "custom" && hasHMatrixFileOption(opt))
        if hasHMatrixFileOption(opt)
            mode = "h_matrix_file";
        else
            mode = "siso_multipath";
        end
    end
    if isHMatrixChannelMode(mode)
        [yOut, hInfo, hState] = applyHMatrixFileChannel(xIn, opt, sampleRateHz, mode);
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

    if mode == "auto" || mode == "custom"
        mode = "siso_multipath";
    end

    switch mode
        case {"siso_multipath","siso","fir","static_fir"}
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
    hState.Enabled = true;
    hState.Mode = mode;
    hState.hasHMatrix = false;
    hState.H = h(:);
end

% 参考星座点
function [yOut, hInfo, hState] = applyHMatrixFileChannel(xIn, opt, sampleRateHz, mode)
    hInfo = struct('Enabled', false, 'Mode', "", 'NumTaps', 0, ...
        'EffectiveTaps', 0, 'Gain_dB', 0);
    hState = struct('Enabled', false, 'Mode', mode, 'hasHMatrix', false);
    yOut = xIn(:);

    channelFilePath = char(getOptionString(opt, ...
        {'channelFilePath','channel_file_path','hMatrixFilePath','h_matrix_file_path','matFilePath'}, ""));
    if isempty(channelFilePath)
        error('run_ccsds_tm_evaluation:MissingHMatrixFile', ...
            'H-matrix channel mode requires channelFilePath or matFilePath.');
    end
    if exist(channelFilePath, 'file') ~= 2
        error('run_ccsds_tm_evaluation:HMatrixFileNotFound', ...
            'H-matrix channel file not found: %s', channelFilePath);
    end

    ch = load(channelFilePath);
    H = getLoadedChannelField(ch, {'H_Martix_tMode','H_Matrix_tMode','HMatrix','H'});
    if isempty(H)
        error('run_ccsds_tm_evaluation:MissingHMatrixVariable', ...
            'Channel file must contain H_Martix_tMode or H_Matrix_tMode.');
    end
    H = double(H);
    if ndims(H) < 3
        H = reshape(H, size(H,1), size(H,2), 1);
    elseif ndims(H) > 3
        H = reshape(H, size(H,1), size(H,2), []);
    end

    xIn = xIn(:);
    pathCount = size(H, 1);
    channelSamplesPerSec = size(H, 2);
    channelSeconds = size(H, 3);

    if ~isfinite(sampleRateHz) || sampleRateHz <= 0
        sampleRateHz = estimateWaveformSampleRate(opt);
    end
    if ~isfinite(sampleRateHz) || sampleRateHz <= 0
        error('run_ccsds_tm_evaluation:InvalidWaveformSampleRate', ...
            'Cannot determine waveform sample rate for H-matrix interpolation.');
    end

    channelSampleRateHz = getOptionDouble(opt, ...
        {'channelSampleRateHz','channel_sample_rate_hz','hMatrixSampleRateHz'}, 100e3);
    if channelSamplesPerSec > 0
        channelSampleRateHz = double(channelSamplesPerSec);
    end
    method = normalizeInterpolationMethod(getOptionString(opt, ...
        {'channelInterpolationMethod','channel_interpolation_method','hMatrixInterpolationMethod'}, "linear"));
    outOfRangeMode = normalizeHMatrixOutOfRangeMode(getOptionString(opt, ...
        {'channelOutOfRangeMode','channel_out_of_range_mode', ...
         'hMatrixOutOfRangeMode','h_matrix_out_of_range_mode', ...
         'channelExtrapolationMode','hMatrixExtrapolationMode'}, "wrap"));

    coeff = interpolateHMatrixCoefficients(H, channelSampleRateHz, numel(xIn), ...
        sampleRateHz, method, outOfRangeMode);

    powerDbRaw = getLoadedChannelField(ch, {'P_nMode','PMode','PathPower_dB','PathPowerDb'});
    if ~isempty(powerDbRaw) && getOptionLogical(opt, {'applyPMode','apply_p_mode','applyChannelPower'}, true)
        powerDbSeries = interpolateHMatrixParameter(powerDbRaw, pathCount, numel(xIn), ...
            sampleRateHz, channelSampleRateHz, channelSeconds, method, outOfRangeMode, 0);
        coeff = coeff .* 10.^(powerDbSeries/20);
    else
        powerDbSeries = zeros(pathCount, numel(xIn));
    end

    delayRaw = getLoadedChannelField(ch, {'tao_nMode','tau_nMode','Delay_nMode','PathDelay_s'});
    interpolateDelays = getOptionLogical(opt, ...
        {'interpolateChannelDelays','interpolate_channel_delays'}, false);
    if isempty(delayRaw)
        delaySecondsSeries = zeros(pathCount, numel(xIn));
    elseif interpolateDelays
        delaySecondsSeries = interpolateHMatrixParameter(delayRaw, pathCount, numel(xIn), ...
            sampleRateHz, channelSampleRateHz, channelSeconds, method, outOfRangeMode, 0);
    else
        delayConst = hMatrixPathMean(delayRaw, pathCount, 0);
        delaySecondsSeries = repmat(delayConst(:), 1, numel(xIn));
    end
    delaySamplesSeries = max(0, round(delaySecondsSeries * sampleRateHz));

    rxWork = complex(zeros(numel(xIn) + max(delaySamplesSeries(:)), 1));
    for pathIdx = 1:pathCount
        weighted = xIn .* coeff(pathIdx,:).';
        delays = delaySamplesSeries(pathIdx,:).';
        if all(delays == delays(1))
            outIndex = double(delays(1)) + (1:numel(xIn)).';
            rxWork(outIndex) = rxWork(outIndex) + weighted;
        else
            outIndex = (1:numel(xIn)).' + delays;
            rxWork = rxWork + accumarray(outIndex, weighted, size(rxWork), @sum, complex(0,0));
        end
    end

    y = rxWork(1:numel(xIn));
    inPower = mean(abs(xIn).^2) + eps;
    outPower = mean(abs(y).^2) + eps;
    gain_dB = 10*log10(outPower / inPower);

    normScale = 1;
    if getOptionLogical(opt, {'normalizeHChannel','normalize_channel_power'}, false)
        normScale = sqrt(inPower / outPower);
        y = y * normScale;
        coeff = coeff * normScale;
    end

    pathPower = mean(abs(coeff).^2, 2);
    [~, dominantPathIndex] = max(pathPower);
    meanCoeff = mean(coeff(:));

    meta = struct();
    meta.ChannelType = 'H_Martix_tMode';
    meta.ChannelFile = channelFilePath;
    meta.PathCount = pathCount;
    meta.ChannelSamplesPerSecond = channelSamplesPerSec;
    meta.ChannelSeconds = channelSeconds;
    meta.ChannelSampleRateHz = channelSampleRateHz;
    meta.WaveformSampleRateHz = sampleRateHz;
    meta.InterpolationMethod = char(method);
    meta.OutOfRangeMode = char(outOfRangeMode);
    meta.ChannelSourceSamples = size(H, 2) * size(H, 3);
    meta.ChannelSourceDuration_s = meta.ChannelSourceSamples / channelSampleRateHz;
    meta.WaveformDuration_s = numel(xIn) / sampleRateHz;
    meta.ExceedsChannelDuration = meta.WaveformDuration_s > meta.ChannelSourceDuration_s;
    meta.InterpolateDelays = interpolateDelays;
    meta.DelayMinSamples = min(delaySamplesSeries(:));
    meta.DelayMaxSamples = max(delaySamplesSeries(:));
    meta.DelayMeanSamples = mean(delaySamplesSeries(:));
    meta.DelayMinSeconds = min(delaySecondsSeries(:));
    meta.DelayMaxSeconds = max(delaySecondsSeries(:));
    meta.MeanGain_dB = gain_dB;
    meta.NormalizationGain_dB = 20*log10(abs(normScale) + eps);
    meta.MeanCoeffMagnitude = mean(abs(coeff(:)));
    meta.MeanPhase_deg = rad2deg(angle(meanCoeff));
    meta.PowerDbMean = mean(powerDbSeries(:));
    meta.EqualizationEnabled = getOptionLogical(opt, ...
        {'enableEqualizer','enable_channel_equalization','channelEqualization','channel_equalization'}, false);

    yOut = y(:);
    hInfo.Enabled = true;
    hInfo.Mode = "h_matrix_file";
    hInfo.NumTaps = pathCount;
    hInfo.EffectiveTaps = nnz(pathPower > 1e-12);
    hInfo.Gain_dB = gain_dB;
    hInfo.Meta = meta;

    hState.Enabled = true;
    hState.Mode = "h_matrix_file";
    hState.hasHMatrix = true;
    hState.pathCoeff = coeff;
    hState.delaySamplesSeries = delaySamplesSeries;
    hState.dominantPathIndex = dominantPathIndex;
    hState.sampleRateHz = sampleRateHz;
    hState.inputPower = inPower;
    hState.outputPower = outPower;
    hState.meta = meta;
end

function yOut = applyKnownChannelEqualizer(yIn, opt, snrForReg_dB, defaultEnable, hState)
    yOut = yIn(:);
    enableEq = logical(defaultEnable);
    if isfield(opt,'enableEqualizer') && ~isempty(opt.enableEqualizer)
        enableEq = logical(opt.enableEqualizer);
    elseif isfield(opt,'enable_channel_equalization') && ~isempty(opt.enable_channel_equalization)
        enableEq = logical(opt.enable_channel_equalization);
    elseif isfield(opt,'channelEqualization') && ~isempty(opt.channelEqualization)
        enableEq = logical(opt.channelEqualization);
    elseif isfield(opt,'channel_equalization') && ~isempty(opt.channel_equalization)
        enableEq = logical(opt.channel_equalization);
    end
    if ~enableEq
        return;
    end

    if nargin >= 5 && isstruct(hState) && isfield(hState,'hasHMatrix') && logical(hState.hasHMatrix)
        mode = lower(getOptionString(opt, {'equalizerMode','channelEqualizerMode'}, "mmse"));
        if any(strcmp(char(mode), {'off','none','disabled'}))
            return;
        end
        yOut = equalizeKnownHMatrixChannel(yOut, hState, opt, snrForReg_dB);
        return;
    end

    yOut = applyKnownHMMSEEqualizer(yOut, opt, snrForReg_dB, enableEq);
end

function yOut = equalizeKnownHMatrixChannel(yIn, hState, opt, snrForReg_dB)
    y = yIn(:);
    yOut = y;
    if ~isfield(hState,'pathCoeff') || isempty(hState.pathCoeff) || ...
            ~isfield(hState,'delaySamplesSeries') || isempty(hState.delaySamplesSeries)
        return;
    end

    coeff = hState.pathCoeff;
    delaySamples = hState.delaySamplesSeries;
    nIn = min([numel(y), size(coeff,2), size(delaySamples,2)]);
    if nIn < 1
        return;
    end

    pathCount = size(coeff,1);
    if isfield(hState,'dominantPathIndex') && hState.dominantPathIndex >= 1 && ...
            hState.dominantPathIndex <= pathCount
        dominantPathIndex = hState.dominantPathIndex;
    else
        [~, dominantPathIndex] = max(mean(abs(coeff(:,1:nIn)).^2, 2));
    end

    inputPowerToEq = mean(abs(y(1:nIn)).^2) + eps;
    txPowerForReg = 1;
    if isfield(hState,'inputPower') && isfinite(hState.inputPower) && hState.inputPower > 0
        txPowerForReg = hState.inputPower;
    end

    mode = lower(getOptionString(opt, {'equalizerMode','channelEqualizerMode'}, "mmse"));
    if strcmp(char(mode), 'zf')
        reg = 1e-8;
    else
        % Scale-aware MMSE:
        % reg = sigma^2 / P_x. With awgn(...,'measured'),
        % sigma^2 = P_rx * 10^(-SNR/10), so raw H gain must scale reg too.
        reg = (inputPowerToEq / txPowerForReg) * 10.^(-double(snrForReg_dB)/10);
    end
    autoReg = reg;
    manualReg = getOptionDouble(opt, {'equalizerReg','channelEqualizerReg'}, NaN);
    if isfinite(manualReg)
        reg = manualReg;
        regSource = 'manual';
    else
        reg = autoReg;
        regSource = 'auto';
    end
    % The MMSE denominator already includes the noise regularizer. Keep the
    % default floor near machine precision so raw-gain deep fades are not
    % accidentally erased by an absolute threshold.
    denomFloor = getOptionDouble(opt, {'equalizerDenomFloor','channelEqualizerDenomFloor'}, eps);
    debugEq = getOptionLogical(opt, 'debugEqualizer', false) || ...
              getOptionLogical(opt, 'debugEqualizerStats', false) || ...
              getOptionLogical(opt, 'debugHMatrixEqualizerStats', false);
    normalizeEqOut = getOptionLogical(opt, {'normalizeEqualizerOutput','normalize_equalizer_output'}, false);

    hVec = coeff(dominantPathIndex,1:nIn).';
    hAbs = abs(hVec);
    denomVec = hAbs.^2 + reg;

    xHat = complex(zeros(nIn,1));
    skippedByDenomFloor = 0;
    for n = 1:nIn
        outIdx = n + delaySamples(dominantPathIndex,n);
        if outIdx < 1 || outIdx > numel(y)
            continue;
        end

        residual = y(outIdx);
        for pathIdx = 1:pathCount
            if pathIdx == dominantPathIndex
                continue;
            end
            otherInIdx = outIdx - delaySamples(pathIdx,n);
            if otherInIdx >= 1 && otherInIdx < n && otherInIdx <= nIn
                residual = residual - coeff(pathIdx,otherInIdx) * xHat(otherInIdx);
            end
        end

        h = coeff(dominantPathIndex,n);
        denom = abs(h)^2 + reg;
        if denom > denomFloor
            xHat(n) = residual * conj(h) / denom;
        else
            skippedByDenomFloor = skippedByDenomFloor + 1;
        end
    end

    yOut(1:nIn) = xHat;
    xHatPower = mean(abs(xHat).^2) + eps;
    xHatMaxAbs = max(abs(xHat));
    normGainDb = 0;
    if normalizeEqOut
        if isfield(hState,'inputPower') && isfinite(hState.inputPower) && hState.inputPower > 0
            inPower = hState.inputPower;
        else
            inPower = mean(abs(y(1:nIn)).^2) + eps;
        end
        outPower = mean(abs(yOut(1:nIn)).^2) + eps;
        scaleEq = sqrt(inPower / outPower);
        yOut(1:nIn) = yOut(1:nIn) * scaleEq;
        normGainDb = 20*log10(max(abs(scaleEq), eps));
    end

    if debugEq
        finalOutPower = mean(abs(yOut(1:nIn)).^2) + eps;
        if isfield(hState,'inputPower') && isfinite(hState.inputPower) && hState.inputPower > 0
            txInputPower = hState.inputPower;
        else
            txInputPower = NaN;
        end
        eqStats = struct();
        eqStats.PathCount = pathCount;
        eqStats.DominantPathIndex = dominantPathIndex;
        eqStats.Mode = char(mode);
        eqStats.Reg = reg;
        eqStats.AutoReg = autoReg;
        eqStats.RegSource = regSource;
        eqStats.RxPowerForReg = inputPowerToEq;
        eqStats.TxPowerForReg = txPowerForReg;
        eqStats.RxPowerForReg_dB = 10*log10(max(inputPowerToEq, eps));
        eqStats.TxPowerForReg_dB = 10*log10(max(txPowerForReg, eps));
        eqStats.DenomFloor = denomFloor;
        eqStats.NormalizeEqualizerOutput = normalizeEqOut;
        eqStats.NormalizeEqualizerGain_dB = normGainDb;
        eqStats.MeanAbsH = mean(hAbs);
        eqStats.RmsAbsH = sqrt(mean(hAbs.^2));
        eqStats.MinAbsH = min(hAbs);
        eqStats.MaxAbsH = max(hAbs);
        eqStats.MeanAbsH_dB = 20*log10(max(eqStats.MeanAbsH, eps));
        eqStats.RmsAbsH_dB = 20*log10(max(eqStats.RmsAbsH, eps));
        eqStats.MinDenom = min(denomVec);
        eqStats.MedianDenom = median(denomVec);
        eqStats.MaxDenom = max(denomVec);
        eqStats.SkippedByDenomFloor = skippedByDenomFloor;
        eqStats.SkippedByDenomFloor_pct = 100 * skippedByDenomFloor / max(nIn, 1);
        eqStats.EqualizerInputPower = inputPowerToEq;
        eqStats.EqualizerInputPower_dB = 10*log10(max(inputPowerToEq, eps));
        eqStats.TxInputPower = txInputPower;
        eqStats.TxInputPower_dB = 10*log10(max(txInputPower, eps));
        eqStats.XHatPower = xHatPower;
        eqStats.XHatPower_dB = 10*log10(max(xHatPower, eps));
        eqStats.XHatMaxAbs = xHatMaxAbs;
        eqStats.XHatMaxAbs_dB = 20*log10(max(xHatMaxAbs, eps));
        eqStats.FinalOutputPower = finalOutPower;
        eqStats.FinalOutputPower_dB = 10*log10(max(finalOutPower, eps));
        eqStats.FiniteXHatRatio = mean(isfinite(real(xHat)) & isfinite(imag(xHat)));

        fprintf(['   [H-Matrix EQ stats] paths=%d, dominant=%d, mode=%s, reg=%.4g, autoReg=%.4g, source=%s, normEQ=%d\n' ...
                 '      reg powers rx/tx = %.2f / %.2f dB\n' ...
                 '      |h| mean/rms/min/max = %.4g / %.4g / %.4g / %.4g  (rms %.2f dB)\n' ...
                 '      denom min/median/max = %.4g / %.4g / %.4g, floor=%.4g, skipped=%d (%.3g%%)\n' ...
                 '      power yIn/xHat/yOutFinal = %.2f / %.2f / %.2f dB, xHat max = %.2f dB, normGain = %.2f dB\n'], ...
            pathCount, dominantPathIndex, char(mode), reg, autoReg, regSource, normalizeEqOut, ...
            eqStats.RxPowerForReg_dB, eqStats.TxPowerForReg_dB, ...
            eqStats.MeanAbsH, eqStats.RmsAbsH, eqStats.MinAbsH, eqStats.MaxAbsH, eqStats.RmsAbsH_dB, ...
            eqStats.MinDenom, eqStats.MedianDenom, eqStats.MaxDenom, eqStats.DenomFloor, ...
            eqStats.SkippedByDenomFloor, eqStats.SkippedByDenomFloor_pct, ...
            eqStats.EqualizerInputPower_dB, eqStats.XHatPower_dB, eqStats.FinalOutputPower_dB, ...
            eqStats.XHatMaxAbs_dB, eqStats.NormalizeEqualizerGain_dB);

        try
            assignin('base','lastHMatrixEqualizerStats',eqStats);
        catch
        end
    end
end

function localPrintHMatrixFrameStats(hState, opt, Fs, sps, bitsPerFrame, actualCodeRate, bitsPerSymbol, totalFrames)
    debugEnabled = getOptionLogical(opt, ...
        {'debugHFrameStats','debugHMatrixFrameStats','debugChannelFrameStats'}, false);
    if ~debugEnabled
        return;
    end
    if nargin < 8 || isempty(totalFrames)
        totalFrames = Inf;
    end
    if ~isstruct(hState) || ~isfield(hState,'hasHMatrix') || ~logical(hState.hasHMatrix) || ...
            ~isfield(hState,'pathCoeff') || isempty(hState.pathCoeff)
        fprintf('   [H-frame stats] no H-matrix state available.\n');
        return;
    end
    if ~isfinite(Fs) || Fs <= 0 || ~isfinite(sps) || sps <= 0 || ...
            ~isfinite(bitsPerFrame) || bitsPerFrame <= 0 || ...
            ~isfinite(actualCodeRate) || actualCodeRate <= 0 || ...
            ~isfinite(bitsPerSymbol) || bitsPerSymbol <= 0
        fprintf('   [H-frame stats] cannot infer frame sample span.\n');
        return;
    end

    pathCount = size(hState.pathCoeff, 1);
    if isfield(hState,'dominantPathIndex') && hState.dominantPathIndex >= 1 && ...
            hState.dominantPathIndex <= pathCount
        dominantPath = hState.dominantPathIndex;
    else
        [~, dominantPath] = max(mean(abs(hState.pathCoeff).^2, 2));
    end

    samplesPerFrame = max(1, round(double(bitsPerFrame) / ...
        double(actualCodeRate) / double(bitsPerSymbol) * double(sps)));
    frameDuration = samplesPerFrame / double(Fs);
    hAbs = abs(hState.pathCoeff(dominantPath, :));
    numFramesAvailable = floor(numel(hAbs) / samplesPerFrame);
    numFramesAvailable = min(numFramesAvailable, floor(double(totalFrames)));
    if numFramesAvailable < 1
        fprintf('   [H-frame stats] no complete frames in H state.\n');
        return;
    end

    startFrame = max(1, round(getOptionDouble(opt, ...
        {'debugHFrameStatsStart','debugHFrameStart','debugChannelFrameStatsStart'}, 1)));
    countFrames = getOptionDouble(opt, ...
        {'debugHFrameStatsCount','debugHFrameCount','debugChannelFrameStatsCount'}, 16);
    if ~isfinite(countFrames)
        endFrame = numFramesAvailable;
    else
        endFrame = min(numFramesAvailable, startFrame + max(0, round(countFrames)) - 1);
    end
    if startFrame > numFramesAvailable
        fprintf('   [H-frame stats] startFrame=%d beyond available frames=%d.\n', ...
            startFrame, numFramesAvailable);
        return;
    end

    fprintf('   [H-frame stats] dominant=%d/%d, frameSamples=%d, frameDuration=%.6g s, show=%d..%d of %d\n', ...
        dominantPath, pathCount, samplesPerFrame, frameDuration, ...
        startFrame, endFrame, numFramesAvailable);

    frameStats = struct('Frame', {}, 'TimeStart_s', {}, 'TimeEnd_s', {}, ...
        'MinAbsH', {}, 'RmsAbsH', {}, 'MedianAbsH', {}, 'MaxAbsH', {}, ...
        'MinAbsH_dB', {}, 'RmsAbsH_dB', {}, 'MedianAbsH_dB', {}, 'MaxAbsH_dB', {});
    for frameIdx = startFrame:endFrame
        idx = (frameIdx-1)*samplesPerFrame + (1:samplesPerFrame);
        idx = idx(idx <= numel(hAbs));
        a = hAbs(idx);
        if isempty(a)
            continue;
        end
        minA = min(a);
        rmsA = sqrt(mean(a.^2));
        medA = median(a);
        maxA = max(a);
        t0 = (idx(1)-1) / double(Fs);
        t1 = idx(end) / double(Fs);
        fprintf(['      frame=%03d t=[%.6f %.6f] s |h| min/rms/med/max = ' ...
                 '%.4g/%.4g/%.4g/%.4g  dB=%.2f/%.2f/%.2f/%.2f\n'], ...
            frameIdx, t0, t1, minA, rmsA, medA, maxA, ...
            20*log10(max(minA, eps)), 20*log10(max(rmsA, eps)), ...
            20*log10(max(medA, eps)), 20*log10(max(maxA, eps)));

        frameStats(end+1).Frame = frameIdx; %#ok<AGROW>
        frameStats(end).TimeStart_s = t0;
        frameStats(end).TimeEnd_s = t1;
        frameStats(end).MinAbsH = minA;
        frameStats(end).RmsAbsH = rmsA;
        frameStats(end).MedianAbsH = medA;
        frameStats(end).MaxAbsH = maxA;
        frameStats(end).MinAbsH_dB = 20*log10(max(minA, eps));
        frameStats(end).RmsAbsH_dB = 20*log10(max(rmsA, eps));
        frameStats(end).MedianAbsH_dB = 20*log10(max(medA, eps));
        frameStats(end).MaxAbsH_dB = 20*log10(max(maxA, eps));
    end

    try
        assignin('base','lastHMatrixFrameStats',frameStats);
    catch
    end
end

function coeff = interpolateHMatrixCoefficients(H, channelSampleRateHz, numOut, waveformSampleRateHz, method, outOfRangeMode)
    pathCount = size(H,1);
    coeffSource = reshape(H, pathCount, []);
    if size(coeffSource,2) == 1
        coeff = repmat(coeffSource, 1, numOut);
        return;
    end

    sourceTimes = (0:size(coeffSource,2)-1) / channelSampleRateHz;
    targetTimes = (0:numOut-1) / waveformSampleRateHz;
    queryTimes = hMatrixQueryTimes(sourceTimes, targetTimes, channelSampleRateHz, outOfRangeMode);
    coeff = complex(zeros(pathCount, numOut));
    for pathIdx = 1:pathCount
        srcSeries = coeffSource(pathIdx,:);
        srcMag = abs(srcSeries);

        if all(srcMag <= eps)
            coeff(pathIdx,:) = complex(zeros(1, numOut));
            continue;
        end

        srcPhase = unwrap(angle(srcSeries));
        tgtMag = interp1(sourceTimes, srcMag, queryTimes, char(method), 'extrap');
        tgtPhase = interp1(sourceTimes, srcPhase, queryTimes, char(method), 'extrap');
        coeff(pathIdx,:) = tgtMag .* exp(1j*tgtPhase);
    end
end

function series = interpolateHMatrixParameter(rawValue, pathCount, numOut, waveformSampleRateHz, channelSampleRateHz, channelSeconds, method, outOfRangeMode, defaultValue)
    param = prepareHMatrixPathParameter(rawValue, pathCount);
    if isempty(param)
        series = defaultValue * ones(pathCount, numOut);
        return;
    end

    if size(param,2) == 1
        series = repmat(param(:,1), 1, numOut);
        return;
    end

    nParam = size(param,2);
    if nParam == channelSeconds && channelSeconds > 1
        sourceTimes = 0:(nParam-1);
        sourcePeriodRateHz = NaN;
    elseif abs(nParam - round(channelSeconds * channelSampleRateHz)) <= 1
        sourceTimes = (0:nParam-1) / channelSampleRateHz;
        sourcePeriodRateHz = channelSampleRateHz;
    else
        sourceTimes = linspace(0, max(channelSeconds, 1), nParam);
        sourcePeriodRateHz = NaN;
    end
    targetTimes = (0:numOut-1) / waveformSampleRateHz;
    queryTimes = hMatrixQueryTimes(sourceTimes, targetTimes, sourcePeriodRateHz, outOfRangeMode);

    series = zeros(pathCount, numOut);
    for pathIdx = 1:pathCount
        series(pathIdx,:) = interp1(sourceTimes, param(pathIdx,:), ...
            queryTimes, char(method), 'extrap');
    end
end

function queryTimes = hMatrixQueryTimes(sourceTimes, targetTimes, sourceSampleRateHz, outOfRangeMode)
    if nargin < 4 || isempty(outOfRangeMode)
        outOfRangeMode = "wrap";
    end
    mode = normalizeHMatrixOutOfRangeMode(outOfRangeMode);
    sourceTimes = double(sourceTimes(:).');
    targetTimes = double(targetTimes(:).');
    if isempty(sourceTimes)
        queryTimes = targetTimes;
        return;
    end

    firstTime = sourceTimes(1);
    lastTime = sourceTimes(end);
    switch char(mode)
        case 'wrap'
            if isfinite(sourceSampleRateHz) && sourceSampleRateHz > 0
                step = 1 / double(sourceSampleRateHz);
            elseif numel(sourceTimes) > 1
                step = median(diff(sourceTimes));
            else
                step = 1;
            end
            period = max(lastTime - firstTime + step, eps);
            queryTimes = mod(targetTimes - firstTime, period) + firstTime;

        case 'hold'
            queryTimes = min(max(targetTimes, firstTime), lastTime);

        case 'error'
            if any(targetTimes < firstTime | targetTimes > lastTime)
                error('run_ccsds_tm_evaluation:HMatrixTimeOutOfRange', ...
                    ['Waveform duration exceeds H-matrix time axis. ', ...
                     'Use channelOutOfRangeMode="wrap", "hold", or "extrap".']);
            end
            queryTimes = targetTimes;

        otherwise
            queryTimes = targetTimes;
    end
end

function param = prepareHMatrixPathParameter(rawValue, pathCount)
    if isempty(rawValue)
        param = [];
        return;
    end

    rawValue = squeeze(double(rawValue));
    if isvector(rawValue)
        values = rawValue(:).';
        if pathCount > 1 && numel(values) == pathCount
            param = values(:);
        else
            param = repmat(values, pathCount, 1);
        end
        return;
    end

    if size(rawValue,1) ~= pathCount && size(rawValue,2) == pathCount
        rawValue = rawValue.';
    end
    if size(rawValue,1) == 1 && pathCount > 1
        rawValue = repmat(rawValue, pathCount, 1);
    elseif size(rawValue,1) < pathCount
        rawValue(end+1:pathCount,:) = repmat(rawValue(end,:), pathCount - size(rawValue,1), 1);
    end
    param = rawValue(1:pathCount,:);
end

function meanValue = hMatrixPathMean(rawValue, pathCount, defaultValue)
    param = prepareHMatrixPathParameter(rawValue, pathCount);
    if isempty(param)
        meanValue = defaultValue * ones(pathCount, 1);
        return;
    end

    meanValue = zeros(pathCount, 1);
    for pathIdx = 1:pathCount
        row = param(pathIdx,:);
        row = row(isfinite(row));
        if isempty(row)
            meanValue(pathIdx) = defaultValue;
        else
            meanValue(pathIdx) = mean(row);
        end
    end
end

function value = getLoadedChannelField(s, names)
    value = [];
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            value = s.(name);
            return;
        end
    end
end

function tf = hasHMatrixFileOption(opt)
    tf = strlength(getOptionString(opt, ...
        {'channelFilePath','channel_file_path','hMatrixFilePath','h_matrix_file_path','matFilePath'}, "")) > 0;
end

function tf = isHMatrixChannelMode(mode)
    tf = any(strcmp(char(lower(string(mode))), ...
        {'h_matrix_file','hmatrix_file','h-matrix-file','h_matrix','hmatrix'}));
end

function method = normalizeInterpolationMethod(method)
    method = lower(string(method));
    if ~any(strcmp(char(method), {'linear','nearest','pchip','spline'}))
        method = "linear";
    end
end

function mode = normalizeHMatrixOutOfRangeMode(mode)
    mode = lower(strtrim(string(mode)));
    switch char(mode)
        case {'wrap','periodic','repeat','repeating','cycle','cyclic','mod'}
            mode = "wrap";
        case {'hold','clamp','edge','nearest-edge','nearest_edge'}
            mode = "hold";
        case {'extrap','extrapolate','linear-extrap','linear_extrap'}
            mode = "extrap";
        case {'error','fail','strict'}
            mode = "error";
        otherwise
            mode = "wrap";
    end
end

function sampleRateHz = estimateWaveformSampleRate(opt)
    sampleRateHz = getOptionDouble(opt, {'Fs','fs','sampleRateHz','SampleRate'}, NaN);
    if isfinite(sampleRateHz) && sampleRateHz > 0
        return;
    end
    symbolRate = getOptionDouble(opt, {'symbolRate','SymbolRate','fSym'}, NaN);
    sps = getOptionDouble(opt, {'sps','SamplesPerSymbol'}, NaN);
    if isfinite(symbolRate) && symbolRate > 0 && isfinite(sps) && sps > 0
        sampleRateHz = symbolRate * sps;
    end
end

function mode = getNoisePlacementMode(opt)
    mode = lower(strtrim(getOptionString(opt, ...
        {'noisePlacement','awgnPlacement','noisePosition','awgnPosition','channelNoiseOrder'}, ...
        "afterChannel")));

    if getOptionLogical(opt, ...
            {'awgnAfterEqualizer','noiseAfterEqualizer','addNoiseAfterEqualizer'}, false)
        mode = "afterequalizer";
    end

    switch char(erase(mode, ["_","-"," "]))
        case {'afterequalizer','postequalizer','posteq','equalizerthennoise','dvb','dvbs2x','ideal'}
            mode = "afterEqualizer";
        case {'afterchannel','postchannel','pre equalizer','preequalizer','channelthennoise','physical','realistic'}
            mode = "afterChannel";
        otherwise
            mode = "afterChannel";
    end
end

function [yOut, noiseInfo] = addReceiverNoise(xIn, opt, sampleRateHz, snr_dB, referenceSignal)
    xIn = xIn(:);
    if nargin < 5 || isempty(referenceSignal)
        referenceSignal = xIn;
    end
    noiseInfo = makeLegacyNoiseInfo(snr_dB);

    psd_dBmHz = getOptionDouble(opt, ...
        {'noisePSDdBmHz','noisePsdDbmHz','noisePSD_dBmHz', ...
         'noisePowerSpectralDensityDbmHz','noiseDensityDbmHz', ...
         'noisePSDdBmPerHz','N0dBmHz','N0_dBmHz'}, NaN);
    if ~isfinite(psd_dBmHz)
        yOut = awgn(xIn, snr_dB, 'measured');
        return;
    end

    noiseBandwidthHz = getOptionDouble(opt, ...
        {'noiseBandwidthHz','noiseBWHz','noiseBandwidth','NoiseBandwidthHz'}, sampleRateHz);
    if ~isfinite(noiseBandwidthHz) || noiseBandwidthHz <= 0
        noiseBandwidthHz = sampleRateHz;
    end

    referencePowerDigital = mean(abs(referenceSignal(:)).^2) + eps;
    signalPowerW = 1e-3 * 10.^(getInputLevelDbm(opt, 0)/10);
    digitalUnitsPerWatt = referencePowerDigital / max(signalPowerW, realmin);

    noisePSD_WHz = 1e-3 * 10.^(psd_dBmHz/10);
    noisePowerW = noisePSD_WHz * noiseBandwidthHz;
    noiseVarianceDigital = noisePowerW * digitalUnitsPerWatt;

    if isreal(xIn)
        n = sqrt(noiseVarianceDigital) .* randn(size(xIn));
    else
        n = sqrt(noiseVarianceDigital/2) .* ...
            (randn(size(xIn)) + 1j*randn(size(xIn)));
    end
    yOut = xIn + n;

    currentSignalPowerDigital = mean(abs(xIn).^2) + eps;
    noiseInfo = struct( ...
        'Mode', "psd", ...
        'SNR_dB', snr_dB, ...
        'PSD_dBmHz', psd_dBmHz, ...
        'BandwidthHz', noiseBandwidthHz, ...
        'NoisePower_dBm', psd_dBmHz + 10*log10(noiseBandwidthHz), ...
        'ReferenceLevel_dBm', getInputLevelDbm(opt, 0), ...
        'EquivalentSNR_dB', 10*log10(currentSignalPowerDigital / max(noiseVarianceDigital, realmin)));
end

function noiseInfo = makeLegacyNoiseInfo(snr_dB)
    noiseInfo = struct( ...
        'Mode', "snr", ...
        'SNR_dB', snr_dB, ...
        'PSD_dBmHz', NaN, ...
        'BandwidthHz', NaN, ...
        'NoisePower_dBm', NaN, ...
        'ReferenceLevel_dBm', NaN, ...
        'EquivalentSNR_dB', snr_dB);
end

function value = getOptionString(s, names, defaultValue)
    value = string(defaultValue);
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if isstring(raw) || ischar(raw)
                value = string(raw);
            elseif isnumeric(raw) || islogical(raw)
                value = string(raw(1));
            end
            return;
        end
    end
end

function value = getOptionDouble(s, names, defaultValue)
    value = defaultValue;
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                raw = str2double(strrep(string(raw), ',', ''));
            end
            raw = double(raw);
            if ~isempty(raw) && isfinite(raw(1))
                value = raw(1);
                return;
            end
        end
    end
end

function value = getOptionLogical(s, names, defaultValue)
    value = logical(defaultValue);
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                text = lower(strtrim(string(raw)));
                value = any(strcmp(text, ["1","true","on","yes","y"]));
            else
                value = logical(raw(1));
            end
            return;
        end
    end
end

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
        refConst = HelperCCSDSFACMReferenceConstellation(14);
    elseif contains(s,'32APSK')
        refConst = HelperCCSDSFACMReferenceConstellation(21);
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

function [berVal, lockRate, bestRot, berStats] = computeBER(fineSynced, validTxFrames, modStr, opt, randomizerEnabled, hasASM, btVal, numWarmUp)
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
        if isfield(opt,'DataPathMode') && ...
                strcmpi(string(opt.DataPathMode), "unequalDualIQ")
            % The grouped UQPSK stream contains two independent ASM
            % periods, so a single-stream ASM preselector is not valid.
            % Score the complete I/Q rail decodes for each rotation.
            phaseResolveMode = "ber";
        end
        if contains(tmMod,'GMSK') && isfield(opt,'GMSKDetectionMode') && ...
                strcmpi(string(opt.GMSKDetectionMode), ...
                "official-viterbi-frame-reset")
            % localDemodForASM is a 1-sps legacy pre-selector.  The official
            % branch receives an oversampled waveform, so let the complete
            % decoder score the four phase hypotheses instead.
            phaseResolveMode = "ber";
        end

        rotationOrder = 1:length(rotations);
        asmResolveInfo = struct('enabled', false, 'selectedIdx', rotationOrder, ...
            'fallbackToBER', false, 'message', "");
        if phaseResolveMode ~= "ber"
            [rotationOrder, asmResolveInfo] = selectRotationsByASM( ...
                fineSynced, rotations, tmMod, tmCode, opt, btVal);
            if asmResolveInfo.enabled
                fprintf('   [ASM phase] %s\n', asmResolveInfo.message);
                if getLogicalField(opt, 'debugCodedBoundary', false) || ...
                        getLogicalField(opt, 'debugASMPhase', false)
                    localPrintASMRotationDebug(rotations, asmResolveInfo);
                end
            end
        end

        bestBer = inf;
        bestLock = -1;
        bestRot = 0;
        bitErrorsBest = 0;
        bitsComparedBest = 0;
        bestStats = localEmptyBERStats();
        bestShift = 0;

        dataPathModeBER = 'single';
        if isfield(opt,'DataPathMode') && ~isempty(opt.DataPathMode)
            dataPathModeBER = char(opt.DataPathMode);
        end
        bitsPerSymBER = localBitsPerSymbolForDebug(tmMod);
        useSplitRSPeriodicASM = localUseSplitRSPeriodicASMAlignment( ...
            dataPathModeBER, tmMod, tmCode, hasASM, opt);
        % Odd-bit 8PSK/32QAM/32APSK needs an I/Q serial-start decision. This is
        % selected from receiver-observable TM structure in the coordinator,
        % never from evaluator BER.  SplitReceiverIQPhase remains an explicit
        % diagnostic override.
        useSplitReceiverStructureSelection = ...
            strcmpi(dataPathModeBER, 'dualIQ') && ...
            any(strcmpi(string(tmMod), {'8PSK','32QAM','32APSK'})) && ...
            getLogicalField(opt, 'UseSplitReceiverCoordinator', true) && ...
            ~(isfield(opt, 'SplitReceiverIQPhase') && ...
              ~isempty(opt.SplitReceiverIQPhase));
        useSplitIQTwoPass = strcmpi(dataPathModeBER, 'dualIQ') && ...
            bitsPerSymBER > 1 && mod(bitsPerSymBER, 2) == 1 && ...
            getLogicalField(opt, 'splitIQPhaseTwoPass', true) && ...
            ~useSplitRSPeriodicASM && ~useSplitReceiverStructureSelection;
        splitIQRoundSucceeded = false;
        splitRoundSuccessBER = getfieldnumeric(opt, 'splitIQPhaseRoundSuccessBER', ...
            getfieldnumeric(opt, 'splitIQPhaseEarlyStopBER', 1e-8));
        splitRoundSuccessLock = getfieldnumeric(opt, 'splitIQPhaseRoundSuccessLock', ...
            getfieldnumeric(opt, 'splitIQPhaseEarlyStopLock', 0.80));
        if useSplitIQTwoPass
            defaultOddIQPhase = round(getfieldnumeric(opt, 'splitOddBpsDefaultIQPhase', 1));
            defaultOddIQPhase = double(defaultOddIQPhase ~= 0);
            opt.splitIQPhaseListOverride = defaultOddIQPhase;
            if getLogicalField(opt, 'splitPathDebug', false)
                fprintf('[SplitPath IQ phase pass] pass=1/2, forced iqPhase=%d\n', defaultOddIQPhase);
            end
        end
        evaluated = false(size(rotations));

        for iiOrder = 1:length(rotationOrder)
            ii = rotationOrder(iiOrder);
            r = rotations(ii);
            evaluated(ii) = true;
            rxRot = fineSynced * r;

            [ber, lock, errs, bitsComp, stats] = tryOneRotationCandidate( ...
                rxRot, validTxFrames, tmMod, tmCode, ...
                opt, randomizerEnabled, hasASM, btVal, numWarmUp);

            fprintf('   [候选角度] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                rad2deg(angle(r)), ber, lock*100, errs, bitsComp);

            % 新规则：
            % 只要锁帧率还可以，就优先选择 BER 最低的角度
            if useSplitReceiverStructureSelection
                isUsableCandidate = localHasCredibleSplitReceiverStructure(stats);
            else
                isUsableCandidate = isfinite(ber) && (bitsComp > 0) && ...
                    (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
            end
            if isUsableCandidate
                % A previously retained fallback may have NaN BER and zero
                % compared bits.  Any usable decode must replace it.
                if useSplitReceiverStructureSelection
                    betterCandidate = bitsComparedBest <= 0 || ...
                        localIsBetterSplitReceiverStructureStats(stats, bestStats);
                else
                    betterCandidate = bitsComparedBest <= 0 || ~isfinite(bestBer) || ...
                        ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock);
                end
                if betterCandidate
                    bestBer = ber;
                    bestLock = lock;
                    bestRot = angle(r);
                    bitErrorsBest = errs;
                    bitsComparedBest = bitsComp;
                    bestStats = stats;
%                     bestShift = shiftBits;
                end
                if useSplitReceiverStructureSelection && ...
                        localHasCredibleSplitReceiverStructure(stats)
                    splitIQRoundSucceeded = true;
                    break;
                end
                % 如果已经找到完美候选, 后面的等价旋转没有必要继续跑。
                % 这对 4D-8PSK-TCM 特别重要, 因为每个候选都会触发一次 4D Viterbi 解调。
                if useSplitIQTwoPass && ber <= splitRoundSuccessBER && ...
                        lock >= splitRoundSuccessLock && bitsComp > 0
                    splitIQRoundSucceeded = true;
                    break;
                end
                if ~useSplitReceiverStructureSelection && ber == 0 && ...
                        (lock >= 0.999 || (strcmp(tmCodeKey,'tpc') && lock >= 0.50)) && bitsComp > 0
                    break;
                end
            else
                % 如果还没有找到可靠候选，则暂时保留 lock 最高的
                if bitsComparedBest <= 0 && ...
                        (~isfinite(bestBer) || lock > bestLock)
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
        needFallback = ~splitIQRoundSucceeded && phaseResolveMode ~= "ber" && ...
            any(~evaluated) && (useSplitReceiverStructureSelection || useSplitIQTwoPass || ...
            (fallbackEnabled && (bestLock < 0.80 || bitsComparedBest <= 0 || bestBer >= fallbackBER)));
        if needFallback
            fprintf('   [ASM phase] selected candidates failed; fallback to remaining rotations.\n');
            for ii = find(~evaluated)
                r = rotations(ii);
                rxRot = fineSynced * r;

                [ber, lock, errs, bitsComp, stats] = tryOneRotationCandidate( ...
                    rxRot, validTxFrames, tmMod, tmCode, ...
                    opt, randomizerEnabled, hasASM, btVal, numWarmUp);

                fprintf('   [候选角度] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                    rad2deg(angle(r)), ber, lock*100, errs, bitsComp);

                if useSplitReceiverStructureSelection
                    isUsableCandidate = localHasCredibleSplitReceiverStructure(stats);
                else
                    isUsableCandidate = isfinite(ber) && (bitsComp > 0) && ...
                        (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
                end
                if isUsableCandidate
                    if useSplitReceiverStructureSelection
                        betterCandidate = bitsComparedBest <= 0 || ...
                            localIsBetterSplitReceiverStructureStats(stats, bestStats);
                    else
                        betterCandidate = bitsComparedBest <= 0 || ~isfinite(bestBer) || ...
                            ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock);
                    end
                    if betterCandidate
                        bestBer = ber;
                        bestLock = lock;
                        bestRot = angle(r);
                        bitErrorsBest = errs;
                        bitsComparedBest = bitsComp;
                        bestStats = stats;
                    end
                    if useSplitReceiverStructureSelection && ...
                            localHasCredibleSplitReceiverStructure(stats)
                        splitIQRoundSucceeded = true;
                        break;
                    end
                    if useSplitIQTwoPass && ber <= splitRoundSuccessBER && ...
                            lock >= splitRoundSuccessLock && bitsComp > 0
                        splitIQRoundSucceeded = true;
                        break;
                    end
                    if ~useSplitReceiverStructureSelection && ber == 0 && ...
                            (lock >= 0.999 || (strcmp(tmCodeKey,'tpc') && lock >= 0.50)) && bitsComp > 0
                        break;
                    end
                else
                    if bitsComparedBest <= 0 && ...
                            (~isfinite(bestBer) || lock > bestLock)
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

        if useSplitIQTwoPass && ~splitIQRoundSucceeded
            opt.splitIQPhaseListOverride = 1 - defaultOddIQPhase;
            if getLogicalField(opt, 'splitPathDebug', false)
                fprintf('[SplitPath IQ phase pass] pass=2/2, forced iqPhase=%d\n', ...
                    opt.splitIQPhaseListOverride);
            end

            evaluated = false(size(rotations));
            for iiOrder = 1:length(rotationOrder)
                ii = rotationOrder(iiOrder);
                r = rotations(ii);
                evaluated(ii) = true;
                rxRot = fineSynced * r;

                [ber, lock, errs, bitsComp, stats] = tryOneRotationCandidate( ...
                    rxRot, validTxFrames, tmMod, tmCode, ...
                    opt, randomizerEnabled, hasASM, btVal, numWarmUp);

                fprintf('   [candidate pass2] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                    rad2deg(angle(r)), ber, lock*100, errs, bitsComp);

                isUsableCandidate = isfinite(ber) && (bitsComp > 0) && ...
                    (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
                if isUsableCandidate
                    if bitsComparedBest <= 0 || ~isfinite(bestBer) || ...
                            ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock)
                        bestBer = ber;
                        bestLock = lock;
                        bestRot = angle(r);
                        bitErrorsBest = errs;
                        bitsComparedBest = bitsComp;
                        bestStats = stats;
                    end
                    if ber <= splitRoundSuccessBER && lock >= splitRoundSuccessLock && bitsComp > 0
                        splitIQRoundSucceeded = true;
                        break;
                    end
                else
                    if bitsComparedBest <= 0 && ...
                            (~isfinite(bestBer) || lock > bestLock)
                        bestBer = ber;
                        bestLock = lock;
                        bestRot = angle(r);
                        bitErrorsBest = errs;
                        bitsComparedBest = bitsComp;
                        bestStats = stats;
                    end
                end
            end

            needFallback = ~splitIQRoundSucceeded && phaseResolveMode ~= "ber" && ...
                any(~evaluated) && (useSplitIQTwoPass || ...
                (fallbackEnabled && (bestLock < 0.80 || bitsComparedBest <= 0 || bestBer >= fallbackBER)));
            if needFallback
                fprintf('   [ASM phase] selected candidates failed in pass2; fallback to remaining rotations.\n');
                for ii = find(~evaluated)
                    r = rotations(ii);
                    rxRot = fineSynced * r;

                    [ber, lock, errs, bitsComp, stats] = tryOneRotationCandidate( ...
                        rxRot, validTxFrames, tmMod, tmCode, ...
                        opt, randomizerEnabled, hasASM, btVal, numWarmUp);

                    fprintf('   [candidate pass2] rot=%+6.1f deg, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d', ...
                        rad2deg(angle(r)), ber, lock*100, errs, bitsComp);

                    isUsableCandidate = isfinite(ber) && (bitsComp > 0) && ...
                        (lock >= 0.80 || (strcmp(tmCodeKey,'tpc') && lock > 0 && ber < 0.25));
                    if isUsableCandidate
                        if bitsComparedBest <= 0 || ~isfinite(bestBer) || ...
                                ber < bestBer || (abs(ber - bestBer) < eps && lock > bestLock)
                            bestBer = ber;
                            bestLock = lock;
                            bestRot = angle(r);
                            bitErrorsBest = errs;
                            bitsComparedBest = bitsComp;
                            bestStats = stats;
                        end
                        if ber <= splitRoundSuccessBER && lock >= splitRoundSuccessLock && bitsComp > 0
                            splitIQRoundSucceeded = true;
                            break;
                        end
                    else
                        if bitsComparedBest <= 0 && ...
                                (~isfinite(bestBer) || lock > bestLock)
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
        end

        berVal = bestBer;
        lockRate = max(bestLock, 0);
        berStats = bestStats;
        if any(strcmpi(dataPathModeBER, ...
                {'dualIQ','unequalDualIQ'})) && ...
                getLogicalField(opt, 'splitPathDebug', false)
            localPrintSplitPredecoderStats('global selected', berStats);
        end

        fprintf('   [Phase ambiguity] best rotation = %+5.1f deg, lockRate=%.1f%%\n', ...
            rad2deg(bestRot), lockRate*100);
    catch ME_BER
        if startsWith(string(ME_BER.identifier), ...
                "gmsk_ccsds_official_demodulate:")
            rethrow(ME_BER);
        end
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

function localPrintASMRotationDebug(rotations, info)
    if ~isfield(info, 'scores') || isempty(info.scores)
        fprintf('   [ASM DEBUG] no rotation score table available\n');
        return;
    end

    nRot = min(numel(rotations), numel(info.scores));
    fprintf('   [ASM DEBUG] rotation score table:\n');
    for ii = 1:nRot
        score = info.scores(ii);
        err = NaN;
        pos = NaN;
        meanErr = NaN;
        nFrames = NaN;
        if isfield(info, 'bestErrs') && numel(info.bestErrs) >= ii
            err = info.bestErrs(ii);
        end
        if isfield(info, 'bestPos') && numel(info.bestPos) >= ii
            pos = info.bestPos(ii);
        end
        if isfield(info, 'meanErrs') && numel(info.meanErrs) >= ii
            meanErr = info.meanErrs(ii);
        end
        if isfield(info, 'periodicFrames') && numel(info.periodicFrames) >= ii
            nFrames = info.periodicFrames(ii);
        end
        fprintf('      rot=%+7.1f deg score=%9.3f err=%6.1f mean=%7.2f frames=%4.0f pos=%8.0f\n', ...
            rad2deg(angle(rotations(ii))), score, err, meanErr, nFrames, pos);
    end
end

function stats = localEmptyBERStats()
    stats = struct( ...
        'FER', NaN, ...
        'FrameErrors', 0, ...
        'CountedFrames', 0, ...
        'MatchedFrames', 0, ...
        'NumRxFrames', 0, ...
        'GMSKDetectorUsed', 'not-applicable', ...
        'AcquisitionFrames', NaN, ...
        'AcquisitionTime_s', NaN);
    railMetricFields = localSplitRailMetricFields();
    for k = 1:numel(railMetricFields)
        stats.(railMetricFields{k}) = NaN;
    end
end

function names = localSplitRailMetricFields()
    names = { ...
        'I_BER','I_LockRate','I_FER','I_BitErrors','I_BitsCompared', ...
        'I_FrameErrors','I_CountedFrames','I_MatchedFrames', ...
        'I_DecodedFrames','I_AcquisitionFrames', ...
        'I_PredecoderBER','I_PredecoderOffset','I_PredecoderPolarity', ...
        'I_PredecoderBitErrors','I_PredecoderBitsCompared', ...
        'Q_BER','Q_LockRate','Q_FER','Q_BitErrors','Q_BitsCompared', ...
        'Q_FrameErrors','Q_CountedFrames','Q_MatchedFrames', ...
        'Q_DecodedFrames','Q_AcquisitionFrames', ...
        'Q_PredecoderBER','Q_PredecoderOffset','Q_PredecoderPolarity', ...
        'Q_PredecoderBitErrors','Q_PredecoderBitsCompared'};
end

function n = localAcquisitionConsecutiveFrames(opt, numWarmUp)
    % acquisition 连续确认门限：用于防止随机 frame ID 假锁。
    % 注意：它不再等于 berWarmUpFrames。默认 3 帧，既能防假锁，
    % 又避免 QPSK 3/4 等边界场景因为前几帧偶发断续而 CountedFrames=0。
    defaultN = 3;
    if nargin >= 1 && isstruct(opt)
        n = getfieldnumeric(opt, 'acquisitionConsecutiveFrames', ...
            getfieldnumeric(opt, 'acqConsecutiveFrames', ...
            getfieldnumeric(opt, 'acquisitionMinConsecutiveFrames', defaultN)));
    else
        n = defaultN;
    end
    if ~isfinite(n) || n < 1
        n = defaultN;
    end
    n = max(1, min(10, round(double(n))));
    if nargin >= 2 && isfinite(double(numWarmUp)) && double(numWarmUp) > 0
        n = min(n, max(1, round(double(numWarmUp))));
    end
end

function thr = localAcquisitionMaxFrameBER(opt)
    % acquisition 单帧质量门限：只有 frame ID 匹配还不够，
    % 本帧 BER 也不能像随机误码。随机假匹配通常约 0.5，默认 0.25 可过滤。
    defaultThr = 0.25;
    if nargin >= 1 && isstruct(opt)
        thr = getfieldnumeric(opt, 'acquisitionMaxFrameBER', ...
            getfieldnumeric(opt, 'acqMaxFrameBER', defaultThr));
    else
        thr = defaultThr;
    end
    if ~isfinite(thr) || thr < 0
        thr = defaultThr;
    end
    thr = min(1, double(thr));
end

function tf = localIsBetterSplitCandidate(candBer, candLock, candBits, bestBer, bestLock, bestBits)
    tol = 1e-12;
    candHasBits = candBits > 0;
    bestHasBits = bestBits > 0;

    if candHasBits && ~bestHasBits
        tf = true;
    elseif ~candHasBits && bestHasBits
        tf = false;
    elseif candHasBits && bestHasBits
        tf = candBer < bestBer - tol || ...
            (abs(candBer - bestBer) <= tol && candLock > bestLock);
    else
        tf = candLock > bestLock || ...
            (abs(candLock - bestLock) <= tol && candBer < bestBer);
    end
end

function [berVal, lockRate, errs, bitsComp, stats, perFrameBER] = ...
        localCountSplitRailBER(decodedI, decodedQ, validTxFrames, bitsPerFrame, numWarmUp, tmMod, tmCode, opt)
    txFramesI = validTxFrames(1:2:end);
    txFramesQ = validTxFrames(2:2:end);

    [statsI, errsI, bitsI, berI] = localCountOneSplitRailBER( ...
        decodedI, txFramesI, bitsPerFrame, numWarmUp, 2, opt);
    [statsQ, errsQ, bitsQ, berQ] = localCountOneSplitRailBER( ...
        decodedQ, txFramesQ, bitsPerFrame, numWarmUp, 2, opt);

    errs = errsI + errsQ;
    bitsComp = bitsI + bitsQ;
    if bitsComp > 0
        berVal = errs / bitsComp;
    else
        berVal = 0.5;
    end

    stats = localEmptyBERStats();
    stats.NumRxFrames = statsI.NumRxFrames + statsQ.NumRxFrames;
    stats.MatchedFrames = statsI.MatchedFrames + statsQ.MatchedFrames;
    stats.CountedFrames = statsI.CountedFrames + statsQ.CountedFrames;
    stats.FrameErrors = statsI.FrameErrors + statsQ.FrameErrors;
    if stats.CountedFrames > 0
        stats.FER = stats.FrameErrors / stats.CountedFrames;
    end
    stats = localAttachOneRailStats(stats, 'I', statsI, errsI, bitsI);
    stats = localAttachOneRailStats(stats, 'Q', statsQ, errsQ, bitsQ);

    acq = [statsI.AcquisitionFrames, statsQ.AcquisitionFrames];
    acq = acq(isfinite(acq));
    if ~isempty(acq)
        stats.AcquisitionFrames = max(acq);
    end
    stats.AcquisitionTime_s = localAcquisitionTimeSeconds( ...
        stats.AcquisitionFrames, bitsPerFrame, tmMod, tmCode, opt);

    if stats.CountedFrames == 0
        lockRate = 0;
    elseif stats.NumRxFrames >= 3
        lockRate = min(1, stats.MatchedFrames / stats.NumRxFrames);
    else
        lockRate = 0;
    end

    n = max(numel(berI), numel(berQ));
    perFrameBER = nan(1, 2*n);
    perFrameBER(1:2:2*numel(berI)-1) = berI;
    perFrameBER(2:2:2*numel(berQ)) = berQ;
end

function evidence = localEmptySplitReceiverStructureEvidence()
    evidence = struct( ...
        'Available',false, ...
        'BothRailsStructured',false, ...
        'TMOrientationScore',0, ...
        'TMMinValidFrames',0, ...
        'TMValidFrames',0, ...
        'TMMinCounterRun',0, ...
        'TMMaxCounterRun',0, ...
        'TMFieldMatches',0, ...
        'SelectionScore',-inf);
end

function stats = localAttachSplitReceiverStructureEvidence(stats, evidence, method)
    if nargin < 3 || isempty(method)
        method = 'tmHeaderStructure';
    end
    if ~isstruct(evidence) || ~isfield(evidence, 'Available')
        evidence = localEmptySplitReceiverStructureEvidence();
    end
    stats.SplitReceiverStructureEvidence = evidence;
    stats.SplitReceiverStructureSelectionMethod = char(string(method));
    stats.SplitReceiverStructureScore = evidence.SelectionScore;
    stats.SplitReceiverTMValidFrames = evidence.TMValidFrames;
    stats.SplitReceiverTMMinValidFrames = evidence.TMMinValidFrames;
    stats.SplitReceiverTMMaxCounterRun = evidence.TMMaxCounterRun;
    stats.SplitReceiverTMOrientationScore = evidence.TMOrientationScore;
end

function tf = localHasCredibleSplitReceiverStructure(stats)
    tf = false;
    if ~isstruct(stats) || ~isfield(stats, 'SplitReceiverStructureEvidence')
        return;
    end
    evidence = stats.SplitReceiverStructureEvidence;
    tf = isstruct(evidence) && isfield(evidence, 'BothRailsStructured') && ...
        logical(evidence.BothRailsStructured);
end

function tf = localIsBetterSplitReceiverStructureStats(candStats, bestStats, preferredPhase)
    if nargin < 3 || isempty(preferredPhase)
        preferredPhase = 1;
    end
    candEvidence = localEmptySplitReceiverStructureEvidence();
    bestEvidence = localEmptySplitReceiverStructureEvidence();
    candPhase = preferredPhase;
    bestPhase = preferredPhase;
    if isstruct(candStats)
        if isfield(candStats, 'SplitReceiverStructureEvidence')
            candEvidence = candStats.SplitReceiverStructureEvidence;
        end
        if isfield(candStats, 'SplitReceiverIQPhase')
            candPhase = candStats.SplitReceiverIQPhase;
        elseif isfield(candStats, 'UQPSKSymSkip')
            candPhase = candStats.UQPSKSymSkip;
        end
    end
    if isstruct(bestStats)
        if isfield(bestStats, 'SplitReceiverStructureEvidence')
            bestEvidence = bestStats.SplitReceiverStructureEvidence;
        end
        if isfield(bestStats, 'SplitReceiverIQPhase')
            bestPhase = bestStats.SplitReceiverIQPhase;
        elseif isfield(bestStats, 'UQPSKSymSkip')
            bestPhase = bestStats.UQPSKSymSkip;
        end
    end
    tf = HelperCCSDSTMSplitReceiver.isBetterTMStructureCandidate( ...
        candEvidence, candPhase, bestEvidence, bestPhase, preferredPhase);
end

function [berVal, lockRate, errs, bitsComp, stats, perFrameBER] = ...
        localCountUnequalUQPSKRailBER(decodedI, decodedQ, validTxFrames, ...
        bitsPerFrame, numWarmUp, tmMod, tmCode, opt)
    if mod(numel(validTxFrames), 3) ~= 0
        error('run_ccsds_tm_evaluation:UnequalReferenceLayout', ...
            ['unequalDualIQ references must use ', ...
             '{I1,I2,Q1,I3,I4,Q2,...}.']);
    end

    referenceGroups = reshape(validTxFrames, 3, []);
    txFramesI = reshape(referenceGroups(1:2,:), [], 1);
    txFramesQ = reshape(referenceGroups(3,:), [], 1);

    % unequalDualIQ explicitly transmits 2x I and 1x Q warm-up frames per
    % logical interval.  They settle timing/carrier/decoder state and must
    % not leak into the requested BERFrames measurement window.
    excludeWarmUp = getLogicalField(opt, 'excludeUQPSKWarmUpFrames', true);
    warmUpI = 0;
    warmUpQ = 0;
    if excludeWarmUp
        warmUpI = 2*numWarmUp;
        warmUpQ = numWarmUp;
    end
    [statsI, errsI, bitsI, berI] = localCountOneSplitRailBER( ...
        decodedI, txFramesI, bitsPerFrame, 2*numWarmUp, 1, opt, warmUpI);
    [statsQ, errsQ, bitsQ, berQ] = localCountOneSplitRailBER( ...
        decodedQ, txFramesQ, bitsPerFrame, numWarmUp, 1, opt, warmUpQ);

    errs = errsI + errsQ;
    bitsComp = bitsI + bitsQ;
    if bitsComp > 0
        berVal = errs / bitsComp;
    else
        berVal = 0.5;
    end

    stats = localEmptyBERStats();
    stats.NumRxFrames = statsI.NumRxFrames + statsQ.NumRxFrames;
    stats.MatchedFrames = statsI.MatchedFrames + statsQ.MatchedFrames;
    stats.CountedFrames = statsI.CountedFrames + statsQ.CountedFrames;
    stats.FrameErrors = statsI.FrameErrors + statsQ.FrameErrors;
    if stats.CountedFrames > 0
        stats.FER = stats.FrameErrors / stats.CountedFrames;
    end
    stats = localAttachOneRailStats(stats, 'I', statsI, errsI, bitsI);
    stats = localAttachOneRailStats(stats, 'Q', statsQ, errsQ, bitsQ);

    acq = [statsI.AcquisitionFrames, statsQ.AcquisitionFrames];
    acq = acq(isfinite(acq));
    if ~isempty(acq)
        stats.AcquisitionFrames = max(acq);
    end
    stats.AcquisitionTime_s = localAcquisitionTimeSeconds( ...
        stats.AcquisitionFrames, bitsPerFrame, tmMod, tmCode, opt);

    if stats.CountedFrames == 0
        lockRate = 0;
    elseif stats.NumRxFrames >= 3
        lockRate = min(1, stats.MatchedFrames / stats.NumRxFrames);
    else
        lockRate = 0;
    end

    nGroups = max(ceil(numel(berI)/2), numel(berQ));
    perFrameBER = nan(1, 3*nGroups);
    for k = 1:nGroups
        iStart = 2*k-1;
        outStart = 3*k-2;
        if iStart <= numel(berI)
            perFrameBER(outStart) = berI(iStart);
        end
        if iStart+1 <= numel(berI)
            perFrameBER(outStart+1) = berI(iStart+1);
        end
        if k <= numel(berQ)
            perFrameBER(outStart+2) = berQ(k);
        end
    end
end

function stats = localAttachOneRailStats(stats, railName, railStats, errs, bitsComp)
    prefix = upper(char(string(railName)));
    if bitsComp > 0
        railBER = errs / bitsComp;
    else
        railBER = NaN;
    end
    if railStats.CountedFrames == 0 || railStats.NumRxFrames < 3
        railLockRate = 0;
    else
        railLockRate = min(1, railStats.MatchedFrames / railStats.NumRxFrames);
    end

    stats.([prefix '_BER']) = railBER;
    stats.([prefix '_LockRate']) = railLockRate;
    stats.([prefix '_FER']) = railStats.FER;
    stats.([prefix '_BitErrors']) = errs;
    stats.([prefix '_BitsCompared']) = bitsComp;
    stats.([prefix '_FrameErrors']) = railStats.FrameErrors;
    stats.([prefix '_CountedFrames']) = railStats.CountedFrames;
    stats.([prefix '_MatchedFrames']) = railStats.MatchedFrames;
    stats.([prefix '_DecodedFrames']) = railStats.NumRxFrames;
    stats.([prefix '_AcquisitionFrames']) = railStats.AcquisitionFrames;
end

function stats = localAttachSplitPredecoderStats(stats, predecoderStats)
    fields = { ...
        'I_PredecoderBER','I_PredecoderOffset','I_PredecoderPolarity', ...
        'I_PredecoderBitErrors','I_PredecoderBitsCompared', ...
        'Q_PredecoderBER','Q_PredecoderOffset','Q_PredecoderPolarity', ...
        'Q_PredecoderBitErrors','Q_PredecoderBitsCompared'};
    for k = 1:numel(fields)
        name = fields{k};
        if isstruct(predecoderStats) && isfield(predecoderStats, name)
            stats.(name) = predecoderStats.(name);
        end
    end
end

function localPrintSplitPredecoderStats(label, stats)
    fprintf(['[SplitPath predecoder %s] ', ...
        'I: hardBER=%.6g offset=%+g polarity=%+g Err=%g/%g | ', ...
        'Q: hardBER=%.6g offset=%+g polarity=%+g Err=%g/%g\n'], ...
        char(string(label)), ...
        stats.I_PredecoderBER, stats.I_PredecoderOffset, ...
        stats.I_PredecoderPolarity, stats.I_PredecoderBitErrors, ...
        stats.I_PredecoderBitsCompared, ...
        stats.Q_PredecoderBER, stats.Q_PredecoderOffset, ...
        stats.Q_PredecoderPolarity, stats.Q_PredecoderBitErrors, ...
        stats.Q_PredecoderBitsCompared);
end

function localPrintSplitRailStats(label, iqPhase, stats)
    fprintf(['[SplitPath rail %s] iqPhase=%d | ', ...
        'I: BER=%.4g Lock=%.1f%% FER=%.4g Err=%g/%g Frames=%g/%g/%g | ', ...
        'Q: BER=%.4g Lock=%.1f%% FER=%.4g Err=%g/%g Frames=%g/%g/%g\n'], ...
        char(string(label)), iqPhase, ...
        stats.I_BER, 100*stats.I_LockRate, stats.I_FER, ...
        stats.I_BitErrors, stats.I_BitsCompared, ...
        stats.I_CountedFrames, stats.I_MatchedFrames, stats.I_DecodedFrames, ...
        stats.Q_BER, 100*stats.Q_LockRate, stats.Q_FER, ...
        stats.Q_BitErrors, stats.Q_BitsCompared, ...
        stats.Q_CountedFrames, stats.Q_MatchedFrames, stats.Q_DecodedFrames);
end

function [stats, errs, bitsComp, perFrameBER] = ...
        localCountOneSplitRailBER(decodedBits, txFrames, bitsPerFrame, numWarmUp, idStep, opt, measurementWarmUpFrames)
    stats = localEmptyBERStats();
    errs = 0;
    bitsComp = 0;
    if nargin < 7 || isempty(measurementWarmUpFrames)
        measurementWarmUpFrames = 0;
    end
    measurementWarmUpFrames = max(0, round(double(measurementWarmUpFrames)));

    txMap = containers.Map('KeyType','double','ValueType','any');
    for k = 1:numel(txFrames)
        fr = txFrames{k};
        txMap(localTMFrameID(fr)) = fr;
    end

    numRx = floor(numel(decodedBits) / bitsPerFrame);
    perFrameBER = nan(1, numRx);
    stats.NumRxFrames = numRx;

    hasLastId = false;
    lastRxId = 0;
    consecIdCount = 0;
    acquisitionConsecutiveFrames = localAcquisitionConsecutiveFrames(opt, numWarmUp);
    acquisitionMaxFrameBER = localAcquisitionMaxFrameBER(opt);
    acquiredForBER = false;
    matchedAfterAcquisition = 0;

    for j = 1:numRx
        idx = (j-1)*bitsPerFrame + (1:bitsPerFrame);
        rxFr = double(decodedBits(idx));
        rxId = localTMFrameID(rxFr);

        if ~isKey(txMap, rxId)
            hasLastId = false;
            consecIdCount = 0;
            continue;
        end

        stats.MatchedFrames = stats.MatchedFrames + 1;
        thisErrs = biterr(txMap(rxId), rxFr);
        perFrameBER(j) = thisErrs / bitsPerFrame;

        % acquisition 阶段只接受“帧号连续 + 本帧 BER 不像随机”的匹配帧。
        % 这样既保留连续帧号防假锁，又不会把 numWarmUp 直接当成连续门限。
        goodFrameForAcq = perFrameBER(j) <= acquisitionMaxFrameBER;
        if goodFrameForAcq
            if ~hasLastId
                consecIdCount = 1;
                hasLastId = true;
            elseif rxId == mod(lastRxId + idStep, 256)
                consecIdCount = consecIdCount + 1;
            else
                consecIdCount = 1;
            end
            lastRxId = rxId;
        else
            hasLastId = false;
            consecIdCount = 0;
        end

        if ~acquiredForBER && consecIdCount >= acquisitionConsecutiveFrames
            acquiredForBER = true;
            stats.AcquisitionFrames = j;
            matchedAfterAcquisition = 0;
        end

        if acquiredForBER
            matchedAfterAcquisition = matchedAfterAcquisition + 1;
        end

        % acquisition 通过后，后续匹配帧直接计入 BER/FER。
        % 防假锁靠上面的连续 ID + per-frame BER 门限完成，不再要求连续 numWarmUp 帧。
        counted = acquiredForBER && j > measurementWarmUpFrames;
        if counted
            stats.CountedFrames = stats.CountedFrames + 1;
            if thisErrs > 0
                stats.FrameErrors = stats.FrameErrors + 1;
            end
            errs = errs + thisErrs;
            bitsComp = bitsComp + bitsPerFrame;
        end
    end

    if stats.CountedFrames > 0
        stats.FER = stats.FrameErrors / stats.CountedFrames;
    end
end

function localPrintPerFrameBER(perFrameBER, opt)
    if nargin < 2 || isempty(opt)
        opt = struct();
    end
    nTotal = numel(perFrameBER);
    nPrint = getfieldnumeric(opt, 'debugPerFrameBERCount', 25);
    if getLogicalField(opt, 'debugAllPerFrameBER', false) || ...
            getLogicalField(opt, 'debugPrintAllFrameBER', false)
        nPrint = nTotal;
    end
    if ~isfinite(nPrint)
        nPrint = nTotal;
    end
    nPrint = max(0, min(nTotal, round(double(nPrint))));
    fmtMode = lower(string(getfieldwithdefault(opt, 'debugPerFrameBERFormat', 'fixed')));
    useSciFormat = any(strcmp(fmtMode, ["sci", "scientific", "e"]));
    if useSciFormat
        valueFormat = '%8.2e ';
        dashFormat = '   -     ';
    else
        valueFormat = '%5.3f ';
        dashFormat = '  -   ';
    end

    fprintf('   [Per-frame BER] ');
    for j = 1:nPrint
        if isnan(perFrameBER(j))
            fprintf(dashFormat);
        else
            fprintf(valueFormat, perFrameBER(j));
        end
        if mod(j,10) == 0 && j < nPrint
            fprintf('\n                   ');
        end
    end
    if nPrint < nTotal
        fprintf('... (%d/%d shown)', nPrint, nTotal);
    end
    fprintf('\n');

    printSummary = getLogicalField(opt, 'debugPerFrameBERSummary', ...
        getLogicalField(opt, 'debugAllPerFrameBER', false));
    if printSummary
        nz = find(isfinite(perFrameBER) & perFrameBER > 0);
        if isempty(nz)
            fprintf('   [Per-frame BER summary] nonzero=0/%d\n', nTotal);
        else
            [maxBER, iMaxLocal] = max(perFrameBER(nz));
            maxIdx = nz(iMaxLocal);
            fprintf('   [Per-frame BER summary] nonzero=%d/%d, first=%d, last=%d, max=%.2e@%d\n', ...
                numel(nz), nTotal, nz(1), nz(end), maxBER, maxIdx);
            nList = getfieldnumeric(opt, 'debugPerFrameBERNonzeroCount', 24);
            if ~isfinite(nList)
                nList = numel(nz);
            end
            nList = min(numel(nz), max(0, round(double(nList))));
            if nList > 0
                fprintf('   [Per-frame BER nonzero] ');
                for k = 1:nList
                    fprintf('%d:%.2e ', nz(k), perFrameBER(nz(k)));
                    if mod(k, 8) == 0 && k < nList
                        fprintf('\n                           ');
                    end
                end
                if nList < numel(nz)
                    fprintf('... (%d/%d shown)', nList, numel(nz));
                end
                fprintf('\n');
            end
        end
    end
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

function value = localTPCInterleaverValue(opt)
    value = getfieldwithdefault(opt, 'TPCInterleaver', ...
        getfieldwithdefault(opt, 'tpcInterleaver', 'auto'));
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

function asmBits = localTMASM(opt, tmCode)
    if nargin < 1 || isempty(opt)
        opt = struct();
    end
    [asmLength, hasLength] = localASMOptionLength(opt);
    [asmHex, hasHex] = localASMOptionHex(opt);
    if hasLength || hasHex
        asmBits = localBuildCustomASMForEval(asmLength, hasLength, asmHex, hasHex);
        return;
    end

    if nargin >= 2 && ~isempty(tmCode)
        codeKey = lower(string(tmCode));
        if codeKey == "ldpc" || codeKey == "turbo"
            rateKey = char(string(getfieldwithdefault(opt, 'CodeRate', '1/2')));
            switch rateKey
                case {'1/2','2/3','4/5'}
                    asmHex = '034776C7272895B0';
                case '1/3'
                    asmHex = '25D5C0CE8990F6C9461BF79C';
                case '1/4'
                    asmHex = '034776C7272895B0FCB88938D8D76A4F';
                case '1/6'
                    asmHex = '25D5C0CE8990F6C9461BF79CDA2A3F31766F0936B9E40863';
                otherwise % Ordinary LDPC rate 7/8.
                    asmHex = '1ACFFC1D';
            end
            asmBits = localHexToBitsForEval(asmHex);
            return;
        end
    end

    asmBits = localDefaultTMASM();
end

function [asmTemplates, periodBits] = localASMTemplatesForPhaseResolve(tmMod, tmCode, opt)
    asmBits = localTMASM(opt, tmCode);
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
        [baseTemplate, puncturePattern, offsetLength, flipSecondBranch] = localConvASMTemplateByRate(rateStr, asmBits);
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

function [asmTemplate, puncturePattern, offsetLength, flipSecondBranch] = localConvASMTemplateByRate(rateStr, asmBits)
    if nargin < 2 || isempty(asmBits)
        asmBits = localTMASM();
    end
    rateStr = string(rateStr);
    puncturePattern = [1;1];
    offsetLength = 12;
    flipSecondBranch = false;
    isDefaultASM = localIsDefaultTMASM(asmBits);

    switch char(rateStr)
        case '1/2'
            puncturePattern = [1;1];
            offsetLength = 12;
            if isDefaultASM
                asmTemplate = int8([1;0;0;0;0;0;0;1;1;1;0;0;1;0;0;1;0;1;1;1;0;0;0;1;1;0;1; ...
                    0;1;0;1;0;0;1;1;1;0;0;1;1;1;1;0;1;0;0;1;1;1;1;1;0]);
            else
                flipSecondBranch = true;
                asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
                    poly2trellis(7, [171 133]), puncturePattern, offsetLength, true);
            end
        case '2/3'
            puncturePattern = [1;1;0;1];
            offsetLength = 10;
            if isDefaultASM
                asmTemplate = int8([1;1;0;1;0;1;0;1;1;1;0;0;0;0;0;1;0; ...
                    1;1;1;1;1;1;0;0;0;0;1;0;1;0;0;0;1;0;1;0;1]);
            else
                asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
                    poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
            end
        case '3/4'
            puncturePattern = [1;1;0;1;1;0];
            offsetLength = 9;
            asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        case '5/6'
            puncturePattern = [1;1;0;1;1;0;0;1;1;0];
            offsetLength = 9;
            asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        case '7/8'
            puncturePattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];
            offsetLength = 7;
            asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
                poly2trellis(7, [171 133]), puncturePattern, offsetLength, false);
        otherwise
            asmTemplate = localBuildConvEncodedASMSync(asmBits, 0, "NRZ-L", ...
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
    if hasASM
        asmLen = numel(localTMASM(opt, tmCode));
    else
        asmLen = 0;
    end
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
        if contains(codeKey, 'turbo')
            codedBits = round((k + 4) / max(rate, eps));
        else
            rateKey = string(getfieldwithdefault(opt, 'CodeRate', '1/2'));
            if rateKey == "7/8" && k == 7136
                % CCSDS ordinary LDPC 7/8 is (8160,7136).  Its exact
                % code rate is 7136/8160, not the nominal fraction 7/8.
                codedBits = 8160;
            else
                codedBits = round(k / max(rate, eps));
            end
        end
        periodBits = codedBits + asmLen;
    elseif contains(codeKey, 'tpc')
        blocksPerTF = getfieldwithdefault(opt, 'TPCBlocksPerTF', 1);
        periodBits = 64*64*double(blocksPerTF) + asmLen;
    elseif contains(codeKey, 'rs')
        rsN = 255;
        rsK = getfieldnumeric(opt, 'RSMessageLength', 223);
        rsI = getfieldnumeric(opt, 'RSInterleavingDepth', 1);
        rsS = getfieldnumeric(opt, 'RSShortenedMessageLength', rsK);
        isShortened = isfield(opt,'IsRSMessageShortened') && ~isempty(opt.IsRSMessageShortened) && ...
            localFlagValue(opt.IsRSMessageShortened);
        if ~isShortened
            rsS = rsK;
        end
        periodBits = 8 * rsI * (rsN - rsK + rsS) + asmLen;
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
        asmTemplates = localTMASM(opt);
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

function [berVal, lockRate, errs, bitsComp, frameStats] = tryOneRotationCandidate(fineSynced, validTxFrames, tmMod, tmCode, opt, randomizerEnabled, hasASM, btVal, numWarmUp)
%TRYONEROTATIONCANDIDATE Isolate failures from an invalid phase hypothesis.
% A wrong GMSK phase can produce a zero-range soft stream.  Some channel
% decoders reject that stream while quantising it; the failure belongs to
% this phase candidate and must not overwrite a previously valid result.
    try
        [berVal, lockRate, errs, bitsComp, frameStats] = tryOneRotation( ...
            fineSynced, validTxFrames, tmMod, tmCode, opt, ...
            randomizerEnabled, hasASM, btVal, numWarmUp);
    catch candidateError
        if startsWith(string(candidateError.identifier), ...
                "gmsk_ccsds_official_demodulate:")
            rethrow(candidateError);
        end
        berVal = inf;
        lockRate = 0;
        errs = 0;
        bitsComp = 0;
        frameStats = localEmptyBERStats();
        fprintf(2, ['\n   [phase candidate skipped] Decoder rejected ', ...
            'this hypothesis: %s\n'], candidateError.message);
    end
end

function [berVal, lockRate, errs, bitsComp, frameStats] = tryOneRotation(fineSynced, validTxFrames, tmMod, tmCode, opt, randomizerEnabled, hasASM, btVal, numWarmUp)
    berVal = 0.5; lockRate = 0;
    gmskDetectorUsed = "not-applicable";

    randomizerFECPosition = opt.RandomizerFECPosition;
    dataPathMode = opt.DataPathMode;

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
        bestLocalUsable = false;
        requireBothUQPSKRails = strcmpi(string(dataPathMode), ...
            "unequalDualIQ");
        useUQPSKTMStructureSelection = requireBothUQPSKRails && ...
            getLogicalField(opt, 'UseSplitReceiverCoordinator', true);

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
                randomizerEnabled, hasASM, btVal, numWarmUp);
            candStats.UQPSKSymSkip = symSkip;

            if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK)
                fprintf('      [UQPSK group] symSkip=%d, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d\n', ...
                    symSkip, candBer, candLock*100, candErrs, candBits);
                if isfield(candStats, 'SplitReceiverStructureEvidence')
                    evidence = candStats.SplitReceiverStructureEvidence;
                    fprintf(['      [UQPSK structure] symSkip=%d score=%.0f ', ...
                        'valid I/Q=%d/%d run I/Q=%d/%d credible=%d\n'], ...
                        symSkip, evidence.SelectionScore, ...
                        evidence.I.ValidFrames, evidence.Q.ValidFrames, ...
                        evidence.I.MaxCounterRun, evidence.Q.MaxCounterRun, ...
                        evidence.BothRailsStructured);
                end
            end

            bothRailsCounted = true;
            if requireBothUQPSKRails
                bothRailsCounted = isfield(candStats, 'I_CountedFrames') && ...
                    isfield(candStats, 'Q_CountedFrames') && ...
                    candStats.I_CountedFrames >= 1 && ...
                    candStats.Q_CountedFrames >= 1;
                if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK) && ...
                        ~bothRailsCounted
                    fprintf(['      [UQPSK unequal reject] symSkip=%d ', ...
                        'requires counted I/Q frames; got I=%g Q=%g\n'], ...
                        symSkip, candStats.I_CountedFrames, ...
                        candStats.Q_CountedFrames);
                end
            end
            if useUQPSKTMStructureSelection
                candidateUsable = localHasCredibleSplitReceiverStructure(candStats);
            else
                candidateUsable = candLock >= 0.80 && candBits > 0 && ...
                    bothRailsCounted;
            end

            if candidateUsable
                % UQPSK grouping is a receiver framing decision.  Use the
                % two rails' decoded TM header/counter evidence, never the
                % evaluator BER, whenever the SplitReceiver is active.
                if useUQPSKTMStructureSelection
                    betterCandidate = ~bestLocalUsable || ...
                        localIsBetterSplitReceiverStructureStats( ...
                        candStats, bestLocalStats, 1);
                else
                    betterCandidate = ~bestLocalUsable || ...
                        localIsBetterSplitCandidate(candBer, candLock, candBits, ...
                        bestLocalBer, bestLocalLock, bestLocalBits);
                end
                if betterCandidate
                    bestLocalBer = candBer;
                    bestLocalLock = candLock;
                    bestLocalErrs = candErrs;
                    bestLocalBits = candBits;
                    bestLocalStats = candStats;
                    bestLocalSkip = symSkip;
                    bestLocalUsable = true;
                end
                if ~useUQPSKTMStructureSelection && candBer == 0 && candLock >= 0.999
                    break;
                end
            elseif ~bestLocalUsable && ...
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
        frameStats.UQPSKSymSkip = bestLocalSkip;
        if useUQPSKTMStructureSelection
            frameStats.UQPSKSymSkipSelectionMethod = 'tmHeaderStructure';
        end
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
                randomizerEnabled, hasASM, btVal, numWarmUp);

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

    % Opt-in GMSK experiment flag.  The default remains the original
    % continuous feedback detector, so existing baseline behavior is not
    % changed unless an explicit frame-reset mode is requested.
    gmskFrameResetAligned = false;
    gmskFrameResetInfo = struct();

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
        debugGMSK = getLogicalField(opt, 'debugGMSK', false) || ...
            getLogicalField(opt, 'debugCodedBoundary', false);
        gmskDetectionMode = "legacy-diff";
        if isfield(opt,'GMSKDetectionMode') && ~isempty(opt.GMSKDetectionMode)
            gmskDetectionMode = lower(string(opt.GMSKDetectionMode));
        end

        useLegacyFrameReset = strcmp(gmskDetectionMode, "legacy-frame-reset");
        useOfficialFrameReset = strcmp(gmskDetectionMode, ...
            "official-viterbi-frame-reset");
        supportedFrameResetCode = strcmpi(string(tmCode), "none") || ...
            contains(lower(string(tmCode)), "convolutional");

        if useOfficialFrameReset
            officialReceiverCfg = struct();
            officialReceiverCfg.ChannelCoding = tmCode;
            officialCodeKey = lower(string(tmCode));
            if contains(officialCodeKey, "convolutional")
                officialReceiverCfg.CodeRate = getfieldwithdefault(opt, ...
                    'ConvolutionalCodeRate', '1/2');
            elseif officialCodeKey == "ldpc" || officialCodeKey == "turbo"
                if ~isfield(opt, 'CodeRate') || isempty(opt.CodeRate)
                    error('run_ccsds_tm_evaluation:MissingOfficialGMSKCodeRate', ...
                        ['Official GMSK with ChannelCoding="%s" requires ', ...
                         'the same CodeRate used by the transmitter.'], ...
                        char(tmCode));
                end
                if ~isfield(opt, 'NumBitsInInformationBlock') || ...
                        isempty(opt.NumBitsInInformationBlock)
                    error(['run_ccsds_tm_evaluation:', ...
                           'MissingOfficialGMSKInformationBlockLength'], ...
                        ['Official GMSK with ChannelCoding="%s" requires ', ...
                         'the same NumBitsInInformationBlock used by the ', ...
                         'transmitter.'], char(tmCode));
                end

                officialReceiverCfg.CodeRate = opt.CodeRate;
                officialReceiverCfg.NumBitsInInformationBlock = ...
                    opt.NumBitsInInformationBlock;
                if officialCodeKey == "ldpc"
                    officialReceiverCfg.IsLDPCOnSMTF = ...
                        getLogicalField(opt, 'IsLDPCOnSMTF', false);
                    if isfield(opt, 'LDPCCodeblockSize') && ...
                            ~isempty(opt.LDPCCodeblockSize)
                        officialReceiverCfg.LDPCCodeblockSize = ...
                            opt.LDPCCodeblockSize;
                    end
                end
            elseif officialCodeKey == "tpc"
                officialReceiverCfg.CodeRate = 'N/A';
                officialReceiverCfg.TPCCodeRate = ...
                    localTPCCodeRateValue(opt);
                officialReceiverCfg.TPCBlocksPerTF = ...
                    getfieldwithdefault(opt, 'TPCBlocksPerTF', 1);
            else
                % The rate is not part of the uncoded GMSK frame layout.
                % Unsupported coding families are rejected by the official
                % receiver entry point; do not invent a convolutional rate.
                officialReceiverCfg.CodeRate = 'N/A';
            end
            officialReceiverCfg.NumBytesInTransferFrame = numBytesTF;
            officialReceiverCfg.ASMBits = localTMASM(opt, tmCode);
            officialReceiverCfg.HasASM = hasASM;
            officialReceiverCfg.PCMFormat = pcmFormatRx;
            officialReceiverCfg.SamplesPerSymbol = ...
                getfieldnumeric(opt, 'sps', 8);
            officialReceiverCfg.BandwidthTimeProduct = btVal;
            officialReceiverCfg.PrintDebug = debugGMSK;

            [demodData, officialReceiverInfo] = ...
                gmsk_ccsds_official_demodulate( ...
                fineSynced, officialReceiverCfg);
            gmskDetectorUsed = "official";
            gmskFrameResetAligned = true;
            if debugGMSK
                fprintf(['   [GMSK official receiver] detector=%s, ', ...
                    'success=%d, input=%d, output=%d, accepted=%d/%d\n'], ...
                    officialReceiverInfo.GMSKDetectorUsed, ...
                    officialReceiverInfo.DetectorSucceeded, ...
                    officialReceiverInfo.Viterbi.InputSamples, ...
                    officialReceiverInfo.Viterbi.OutputSymbols, ...
                    officialReceiverInfo.FrameReset.AcceptedFrames, ...
                    officialReceiverInfo.FrameReset.TotalFrames);
                assignin('base', 'debugGMSKOfficialReceiverInfo', ...
                    officialReceiverInfo);
            end
        elseif useLegacyFrameReset && hasASM && supportedFrameResetCode
            rateForReset = "1/2";
            if isfield(opt,'ConvolutionalCodeRate') && ...
                    ~isempty(opt.ConvolutionalCodeRate)
                rateForReset = string(opt.ConvolutionalCodeRate);
            end
            asmForReset = localTMASM(opt);
            resetTemplateCfg = gmsk_frame_reset_asm_config( ...
                tmCode, rateForReset, numBytesTF, asmForReset, pcmFormatRx);

            if ~isempty(resetTemplateCfg.asmTemplates)
                resetCfg = struct();
                resetCfg.framePeriodBits = resetTemplateCfg.framePeriodBits;
                resetCfg.asmTemplates = resetTemplateCfg.asmTemplates;
                resetCfg.asmOffsetBits = resetTemplateCfg.asmOffsetBits;
                resetCfg.asmMaxErrors = getfieldnumeric(opt, ...
                    'gmskFrameResetASMMaxErrors', ...
                    max(2, ceil(0.20*size(resetCfg.asmTemplates,1))));
                resetCfg.asmMinGap = getfieldnumeric(opt, ...
                    'gmskFrameResetASMMinGap', ...
                    max(3, ceil(0.25*size(resetCfg.asmTemplates,1))));
                resetCfg.maxSearchFrames = getfieldnumeric(opt, ...
                    'gmskFrameResetMaxSearchFrames', 8);
                resetCfg.minSearchFrames = getfieldnumeric(opt, ...
                    'gmskFrameResetMinSearchFrames', 2);
                resetCfg.printDebug = debugGMSK;

                resetInput = fineSynced;

                [frameResetData, gmskFrameResetInfo] = ...
                    gmsk_frame_reset_demodulate(resetInput, resetCfg);
                if gmskFrameResetInfo.GridFound && ~isempty(frameResetData)
                    demodData = frameResetData;
                    gmskFrameResetAligned = true;
                    gmskDetectorUsed = "legacy-frame-reset";
                    if debugGMSK
                        fprintf(['   [GMSK frame reset] grid start=%d, ', ...
                            'altPhase=%d, median ASM errors=%.2f, ', ...
                            'accepted=%d/%d\n'], ...
                            gmskFrameResetInfo.FrameStart, ...
                            gmskFrameResetInfo.AltPhase, ...
                            gmskFrameResetInfo.GridMedianASMErrors, ...
                            gmskFrameResetInfo.AcceptedFrames, ...
                            gmskFrameResetInfo.TotalFrames);
                        assignin('base','debugGMSKFrameResetInfo', ...
                            gmskFrameResetInfo);
                    end
                else
                    if debugGMSK
                        fprintf(['   [GMSK frame reset] acquisition failed: %s; ', ...
                            'mode=%s.\n'], ...
                            gmskFrameResetInfo.FailureReason, ...
                            char(gmskDetectionMode));
                    end
                    if debugGMSK
                        fprintf('   [GMSK frame reset] falling back to legacy detector.\n');
                    end
                    demodobj = HelperCCSDSTMDemodulator( ...
                        'Modulation',tmMod, ...
                        'ChannelCoding',tmCode, ...
                        'BandwidthTimeProduct',btVal);
                    demodData = demodobj(fineSynced);
                    gmskDetectorUsed = "legacy-diff";
                end
            else
                if debugGMSK
                    fprintf(['   [GMSK frame reset] ASM templates are not ', ...
                        'rectangular for this configuration.\n']);
                end
                if debugGMSK
                    fprintf('   [GMSK frame reset] using legacy detector.\n');
                end
                demodobj = HelperCCSDSTMDemodulator( ...
                    'Modulation',tmMod, ...
                    'ChannelCoding',tmCode, ...
                    'BandwidthTimeProduct',btVal);
                demodData = demodobj(fineSynced);
                gmskDetectorUsed = "legacy-diff";
            end
        else
            if useLegacyFrameReset && debugGMSK
                fprintf(['   [GMSK frame reset] requires HasASM=true and ', ...
                    'none/convolutional coding; using legacy.\n']);
            end
            demodobj = HelperCCSDSTMDemodulator( ...
                'Modulation',tmMod, ...
                'ChannelCoding',tmCode, ...
                'BandwidthTimeProduct',btVal);
            demodData = demodobj(fineSynced);
            gmskDetectorUsed = "legacy-diff";
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

    if getLogicalField(opt, 'debugCodedBoundary', false) && ...
            evalin('base','exist(''debugTMEncodedBits'',''var'')')
        txEnc = evalin('base','debugTMEncodedBits');
        localTPCPrintEncodedBoundaryDebug(demodData, txEnc, tmMod);
    end

    if strcmpi(string(tmCode), "TPC") && hasASM && ~isempty(demodData)
        asmBits = localTMASM(opt);
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
%                'RandomizerEnabled',randomizerEnabled,'HasASM',hasASM};
    isLDPCOnSMTF = contains(lower(string(tmCode)),'ldpc') && isfield(opt,'IsLDPCOnSMTF') && logical(opt.IsLDPCOnSMTF);
    decoderMod = tmMod;
    if contains(tmMod,'UQPSK')
        decoderMod = 'QPSK';
    elseif contains(tmMod,'FM')
        decoderMod = 'BPSK';
    end
    decArgs = {'ChannelCoding',tmCode,'Modulation',decoderMod, ...
               'RandomizerEnabled',randomizerEnabled,'HasASM',hasASM};
    decArgs = appendASMArgs(decArgs, opt);
    % HelperCCSDSTMDecoder remains a single-rail component.  The split
    % coordinator owns dualIQ/unequalDualIQ demux and creates one ordinary
    % Decoder per rail.  Keep the legacy branch selectable during migration
    % so its result can be compared with the coordinator using the same seed.
    decoderPathMode = 'single';
    useSplitReceiverCoordinator = getLogicalField( ...
        opt, 'UseSplitReceiverCoordinator', true);
    decArgs = [decArgs, {'RandomizerFECPosition', char(randomizerFECPosition), ...
                         'DataPathMode', decoderPathMode}];
    if isfield(opt,'PCMFormat') && ~isempty(opt.PCMFormat)
        decArgs = [decArgs, {'PCMFormat', string(opt.PCMFormat)}];
    end
    if isfield(opt,'debugPCMFormat') && logical(opt.debugPCMFormat)
        decArgs = [decArgs, {'DebugPCMFormat', true}];
    end
    if isfield(opt,'debugLDPC') && logical(opt.debugLDPC)
        decArgs = [decArgs, {'DebugLDPC', true}];
    end
    if isfield(opt,'debugTurbo') && logical(opt.debugTurbo)
        decArgs = [decArgs, {'DebugTurbo', true}];
    end
    disableDecoderPhaseAmbiguity = false;
    if isfield(opt,'DisablePhaseAmbiguityResolution') && ~isempty(opt.DisablePhaseAmbiguityResolution)
        disableDecoderPhaseAmbiguity = logical(opt.DisablePhaseAmbiguityResolution);
    elseif isfield(opt,'disableDecoderPhaseAmbiguity') && ~isempty(opt.disableDecoderPhaseAmbiguity)
        disableDecoderPhaseAmbiguity = logical(opt.disableDecoderPhaseAmbiguity);
    end
    if contains(tmMod,'UQPSK') || contains(tmMod,'FM') || contains(tmMod,'8PSK') || disableDecoderPhaseAmbiguity
        decArgs = [decArgs, {'DisablePhaseAmbiguityResolution', true}];
    end
    tmCodeKey = lower(string(tmCode));
    usesTransferFrameBytes = any(strcmp(tmCodeKey, ["none", "convolutional", "tpc"])) || isLDPCOnSMTF;
    if contains(tmCodeKey,'tpc')
        decArgs = [decArgs, {'TPCCodeRate', localTPCCodeRateValue(opt), ...
                             'TPCBlocksPerTF', getfieldwithdefault(opt, 'TPCBlocksPerTF', 1), ...
                             'TPCInterleaver', localTPCInterleaverValue(opt)}];
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
    bitsPerFrame = length(validTxFrames{1});
    txMap = containers.Map('KeyType','double','ValueType','any');
    for k=1:length(validTxFrames)
        fr = validTxFrames{k};
        id = localTMFrameID(fr);
        txMap(id)=fr;
    end

    if getLogicalField(opt, 'debugCodedBoundary', false)
        localPrintDemodDataDebug(demodData, tmMod, tmCode, bitsPerFrame);
    end

    if strcmpi(dataPathMode, 'unequalDualIQ') && useSplitReceiverCoordinator
        splitDebug = getLogicalField(opt, 'splitPathDebug', false);
        splitReceiver = HelperCCSDSTMSplitReceiver( ...
            'DataPathMode', dataPathMode, ...
            'Modulation', tmMod, ...
            'ChannelCoding', tmCode, ...
            'BitsPerFrame', bitsPerFrame, ...
            'DecoderArgs', decArgs, ...
            'Options', opt, ...
            'HasASM', hasASM, ...
            'IQPhase', 0, ...
            'Debug', false);
        splitResult = splitReceiver.decode(demodData);
        demodI = splitResult.DemodI;
        demodQ = splitResult.DemodQ;
        decodedI = splitResult.DecodedI;
        decodedQ = splitResult.DecodedQ;
        unequalRSASM = splitResult.RSASMAlignment;

        predecoderStats = localEmptySplitPredecoderStats();
        if splitDebug
            fprintf(['[UQPSK unequal RX demux] grouped=%d soft bits -> ', ...
                'I=%d, Q=%d, droppedTail=%d\n'], ...
                numel(demodData), numel(demodI), numel(demodQ), ...
                splitResult.DroppedTailBits);
            predecoderStats = localMeasureSplitPredecoderRails(demodI, demodQ);
            fprintf(['[UQPSK unequal predecoder] ', ...
                'I: hardBER=%.6g offset=%+g polarity=%+g | ', ...
                'Q: hardBER=%.6g offset=%+g polarity=%+g\n'], ...
                predecoderStats.I_PredecoderBER, ...
                predecoderStats.I_PredecoderOffset, ...
                predecoderStats.I_PredecoderPolarity, ...
                predecoderStats.Q_PredecoderBER, ...
                predecoderStats.Q_PredecoderOffset, ...
                predecoderStats.Q_PredecoderPolarity);
        end
        unequalRSASM = HelperCCSDSTMSplitReceiver.scoreTMStructure( ...
            unequalRSASM, decodedI, decodedQ, bitsPerFrame, opt);
        unequalStructureEvidence = ...
            HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
            decodedI, decodedQ, bitsPerFrame, opt, dataPathMode);
        if splitDebug || getLogicalField(opt, 'debugCodedBoundary', false)
            localPrintSplitRSASMAlignment( ...
                'unequal coordinator', NaN, unequalRSASM);
        end

        [berVal, lockRate, errs, bitsComp, frameStats, perFrameBER] = ...
            localCountUnequalUQPSKRailBER( ...
                decodedI, decodedQ, validTxFrames, bitsPerFrame, ...
                numWarmUp, tmMod, tmCode, opt);
        frameStats = localAttachSplitPredecoderStats(frameStats, predecoderStats);
        frameStats = localAttachSplitReceiverStructureEvidence( ...
            frameStats, unequalStructureEvidence, 'tmHeaderStructure');
        frameStats.SplitReceiverImplementation = 'coordinator';

        if splitDebug
            fprintf(['[UQPSK unequal RX decode] decoded I=%d bits ', ...
                '(%d frames), Q=%d bits (%d frames)\n'], ...
                numel(decodedI), floor(numel(decodedI)/bitsPerFrame), ...
                numel(decodedQ), floor(numel(decodedQ)/bitsPerFrame));
            localPrintSplitRailStats('selected', 0, frameStats);
        end
        if lockRate > 0.5 && bitsComp > 0
            localPrintPerFrameBER(perFrameBER, opt);
        end
        return;
    elseif strcmpi(dataPathMode, 'unequalDualIQ')
        splitDebug = getLogicalField(opt, 'splitPathDebug', false);
        [demodI, demodQ, droppedTail] = ...
            tm_uqpsk_unequal_bit_demux(demodData, 2, 'drop');
        if splitDebug
            fprintf(['[UQPSK unequal RX demux] grouped=%d soft bits -> ', ...
                'I=%d, Q=%d, droppedTail=%d\n'], ...
                numel(demodData), numel(demodI), numel(demodQ), ...
                droppedTail);
        end

        predecoderStats = localEmptySplitPredecoderStats();
        if splitDebug
            predecoderStats = localMeasureSplitPredecoderRails( ...
                demodI, demodQ);
            fprintf(['[UQPSK unequal predecoder] ', ...
                'I: hardBER=%.6g offset=%+g polarity=%+g | ', ...
                'Q: hardBER=%.6g offset=%+g polarity=%+g\n'], ...
                predecoderStats.I_PredecoderBER, ...
                predecoderStats.I_PredecoderOffset, ...
                predecoderStats.I_PredecoderPolarity, ...
                predecoderStats.Q_PredecoderBER, ...
                predecoderStats.Q_PredecoderOffset, ...
                predecoderStats.Q_PredecoderPolarity);
        end

        % UQPSK RS is byte-boundary sensitive.  With an unrandomized
        % payload, a single-frame ASM search can prefer the adjacent bit
        % over the true frame start even though the correct ASM repeats at
        % every RS frame.  Reuse the split-path periodic ASM coordinator
        % to align I and Q independently.  Decoder synchronization is
        % disabled only when both rails have credible periodic ASM; if
        % either rail is ambiguous, the existing Decoder path remains the
        % fallback.
        [demodIForDecoder, demodQForDecoder, decArgsI, decArgsQ, ...
                unequalRSASM] = localPrepareSplitRSPeriodicASMAlignment( ...
            demodI, demodQ, decArgs, dataPathMode, tmMod, tmCode, ...
            hasASM, opt);

        if splitDebug || getLogicalField(opt, 'debugCodedBoundary', false)
            localPrintSplitRSASMAlignment( ...
                'unequal candidate', NaN, unequalRSASM);
        end

        decoderI = HelperCCSDSTMDecoder(decArgsI{:});
        decoderQ = HelperCCSDSTMDecoder(decArgsQ{:});
        decodedI = decoderI(demodIForDecoder);
        decodedQ = decoderQ(demodQForDecoder);

        [berVal, lockRate, errs, bitsComp, frameStats, perFrameBER] = ...
            localCountUnequalUQPSKRailBER( ...
            decodedI, decodedQ, validTxFrames, bitsPerFrame, ...
            numWarmUp, tmMod, tmCode, opt);
        frameStats = localAttachSplitPredecoderStats( ...
            frameStats, predecoderStats);
        frameStats = localAttachSplitReceiverStructureEvidence( ...
            frameStats, HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
            decodedI, decodedQ, bitsPerFrame, opt, dataPathMode), ...
            'tmHeaderStructure');

        if splitDebug
            fprintf(['[UQPSK unequal RX decode] decoded I=%d bits ', ...
                '(%d frames), Q=%d bits (%d frames)\n'], ...
                numel(decodedI), floor(numel(decodedI)/bitsPerFrame), ...
                numel(decodedQ), floor(numel(decodedQ)/bitsPerFrame));
            localPrintSplitRailStats('selected', 0, frameStats);
        end
        if lockRate > 0.5 && bitsComp > 0
            localPrintPerFrameBER(perFrameBER, opt);
        end
        frameStats.SplitReceiverImplementation = 'legacy';
        return;
    elseif strcmpi(dataPathMode, 'dualIQ')
        splitDebug = getLogicalField(opt, 'splitPathDebug', false);
        splitRSASMEnabled = localUseSplitRSPeriodicASMAlignment( ...
            dataPathMode, tmMod, tmCode, hasASM, opt);

        iqPhaseList = 0;
        bitsPerSymForSplit = localBitsPerSymbolForDebug(tmMod);
        % A production caller supplies one explicit phase after its packing
        % contract is known.  The legacy list override remains available only
        % for evaluation/diagnosis of odd-bits-per-symbol modes.
        if isfield(opt, 'SplitReceiverIQPhase') && ~isempty(opt.SplitReceiverIQPhase)
            iqPhaseList = double(opt.SplitReceiverIQPhase(:).');
            iqPhaseList = iqPhaseList(ismember(iqPhaseList, [0 1]));
            if numel(iqPhaseList) ~= 1
                error('run_ccsds_tm_evaluation:InvalidSplitReceiverIQPhase', ...
                    'SplitReceiverIQPhase must be one explicit value: 0 or 1.');
            end
            if splitDebug
                fprintf('[SplitPath IQ phase order] mod=%s, bps=%d, order=%s, reason=explicit receiver contract\n', ...
                    char(tmMod), bitsPerSymForSplit, mat2str(iqPhaseList));
            end
        elseif isfield(opt, 'splitIQPhaseListOverride') && ~isempty(opt.splitIQPhaseListOverride)
            iqPhaseList = double(opt.splitIQPhaseListOverride(:).');
            iqPhaseList = iqPhaseList(ismember(iqPhaseList, [0 1]));
            if isempty(iqPhaseList)
                iqPhaseList = 0;
            end
            if splitDebug
                fprintf('[SplitPath IQ phase order] mod=%s, bps=%d, order=%s, reason=override\n', ...
                    char(tmMod), bitsPerSymForSplit, mat2str(iqPhaseList));
            end
        elseif mod(bitsPerSymForSplit, 2) == 1 && bitsPerSymForSplit > 1
            defaultOddIQPhase = round(getfieldnumeric(opt, 'splitOddBpsDefaultIQPhase', 1));
            if defaultOddIQPhase == 0
                iqPhaseList = [0 1];
            else
                iqPhaseList = [1 0];
            end
            if splitDebug
                fprintf('[SplitPath IQ phase order] mod=%s, bps=%d, order=%s, reason=odd bits/symbol default\n', ...
                    char(tmMod), bitsPerSymForSplit, mat2str(iqPhaseList));
            end
        end
        splitEarlyStopBER = getfieldnumeric(opt, 'splitIQPhaseEarlyStopBER', 1e-8);
        splitEarlyStopLock = getfieldnumeric(opt, 'splitIQPhaseEarlyStopLock', 0.80);
        useTMStructureIQPhase = useSplitReceiverCoordinator && ...
            any(strcmpi(string(tmMod), {'8PSK','32QAM','32APSK'})) && ...
            numel(iqPhaseList) > 1;

        bestSplitBer = inf;
        bestSplitLock = -1;
        bestSplitErrs = 0;
        bestSplitBits = 0;
        bestSplitStats = localEmptyBERStats();
        bestSplitPerFrameBER = [];
        bestSplitPhase = 0;
        bestSplitDecodedI = zeros(0,1,'int8');
        bestSplitDecodedQ = zeros(0,1,'int8');
        bestSplitDecodedBits = zeros(0,1,'int8');
        bestSplitRSASM = localEmptySplitRSASMAlignment();
        bestSplitStructureEvidence = localEmptySplitReceiverStructureEvidence();

        for iqPhase = iqPhaseList
            if iqPhase >= numel(demodData)
                continue;
            end

            if useSplitReceiverCoordinator
                splitReceiver = HelperCCSDSTMSplitReceiver( ...
                    'DataPathMode', dataPathMode, ...
                    'Modulation', tmMod, ...
                    'ChannelCoding', tmCode, ...
                    'BitsPerFrame', bitsPerFrame, ...
                    'DecoderArgs', decArgs, ...
                    'Options', opt, ...
                    'HasASM', hasASM, ...
                    'IQPhase', iqPhase, ...
                    'Debug', false);
                splitResult = splitReceiver.decode(demodData);
                demodI = splitResult.DemodI;
                demodQ = splitResult.DemodQ;
                decodedI = splitResult.DecodedI;
                decodedQ = splitResult.DecodedQ;
                decodedBits = splitResult.DecodedBits;
                splitRSASM = HelperCCSDSTMSplitReceiver.scoreTMStructure( ...
                    splitResult.RSASMAlignment, decodedI, decodedQ, ...
                    bitsPerFrame, opt);
                splitStructureEvidence = ...
                    HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
                    decodedI, decodedQ, bitsPerFrame, opt, dataPathMode);
                predecoderStats = localEmptySplitPredecoderStats();
                if splitDebug
                    fprintf('[SplitPath IQ phase] mod=%s, iqPhase=%d, len=%d\n', ...
                        char(tmMod), iqPhase, numel(demodData)-iqPhase);
                    fprintf('[SplitPath RX deinterleave] demod=%d soft bits -> I=%d, Q=%d\n', ...
                        numel(demodData)-iqPhase, numel(demodI), numel(demodQ));
                    predecoderStats = localMeasureSplitPredecoderRails( ...
                        demodI, demodQ);
                end
            else
                demodData2 = demodData(iqPhase+1:end);
                if mod(numel(demodData2),2) ~= 0
                    demodData2 = demodData2(1:end-1);
                end

                if splitDebug
                    fprintf('[SplitPath IQ phase] mod=%s, iqPhase=%d, len=%d\n', ...
                        char(tmMod), iqPhase, numel(demodData2));
                end

                [demodI, demodQ, predecoderStats] = localBitDeinterleaveIQ( ...
                    demodData2, tmMod, splitDebug, iqPhase);
                if splitDebug
                    fprintf('[SplitPath RX deinterleave] demod=%d soft bits -> I=%d, Q=%d\n', ...
                        numel(demodData2), numel(demodI), numel(demodQ));
                end

                [demodIForDecoder, demodQForDecoder, decArgsI, decArgsQ, splitRSASM] = ...
                    localPrepareSplitRSPeriodicASMAlignment( ...
                    demodI, demodQ, decArgs, dataPathMode, tmMod, tmCode, hasASM, opt);

                [decodedI, decodedQ, decodedBits] = localDecodeSplitRails( ...
                    demodIForDecoder, demodQForDecoder, bitsPerFrame, decArgsI, decArgsQ);
                splitRSASM = localAttachSplitRSTMStructureScore( ...
                    splitRSASM, decodedI, decodedQ, bitsPerFrame, opt);
                splitStructureEvidence = ...
                    HelperCCSDSTMSplitReceiver.scoreDecodedTMStructure( ...
                    decodedI, decodedQ, bitsPerFrame, opt, dataPathMode);
            end
            if splitDebug || getLogicalField(opt, 'debugCodedBoundary', false)
                localPrintSplitRSASMAlignment('candidate', iqPhase, splitRSASM);
            end

            if splitDebug
                fprintf(['[SplitPath RX decode] iqPhase=%d, decodedI=%d bits (%d frames), ', ...
                    'decodedQ=%d bits (%d frames), merged=%d bits\n'], ...
                    iqPhase, numel(decodedI), floor(numel(decodedI)/bitsPerFrame), ...
                    numel(decodedQ), floor(numel(decodedQ)/bitsPerFrame), ...
                    numel(decodedBits));
            end

            [candBer, candLock, candErrs, candBits, candStats, candPerFrameBER] = ...
                localCountSplitRailBER(decodedI, decodedQ, validTxFrames, ...
                bitsPerFrame, numWarmUp, tmMod, tmCode, opt);
            candStats = localAttachSplitPredecoderStats( ...
                candStats, predecoderStats);
            candStats = localAttachSplitReceiverStructureEvidence( ...
                candStats, splitStructureEvidence, 'tmHeaderStructure');
            candStats.SplitReceiverIQPhase = iqPhase;

            if splitDebug
                fprintf('[SplitPath IQ phase score] iqPhase=%d, BER=%.4g, Lock=%.1f%%, Err=%d, Bits=%d\n', ...
                    iqPhase, candBer, candLock*100, candErrs, candBits);
                if useTMStructureIQPhase
                    fprintf(['[SplitReceiver IQ phase structure] iqPhase=%d ', ...
                        'score=%.0f valid I/Q=%d/%d run I/Q=%d/%d ', ...
                        'orientation=%d credible=%d\n'], ...
                        iqPhase, splitStructureEvidence.SelectionScore, ...
                        splitStructureEvidence.I.ValidFrames, ...
                        splitStructureEvidence.Q.ValidFrames, ...
                        splitStructureEvidence.I.MaxCounterRun, ...
                        splitStructureEvidence.Q.MaxCounterRun, ...
                        splitStructureEvidence.TMOrientationScore, ...
                        splitStructureEvidence.BothRailsStructured);
                end
                localPrintSplitRailStats('candidate', iqPhase, candStats);
            end

            if (useTMStructureIQPhase && ...
                    HelperCCSDSTMSplitReceiver.isBetterTMStructureCandidate( ...
                    splitStructureEvidence, iqPhase, bestSplitStructureEvidence, ...
                    bestSplitPhase, getfieldnumeric(opt, ...
                    'splitOddBpsDefaultIQPhase', 1))) || ...
                    (~useTMStructureIQPhase && localIsBetterSplitRSASMCandidate( ...
                    splitRSASM, candBer, candLock, candBits, iqPhase, ...
                    bestSplitRSASM, bestSplitBer, bestSplitLock, bestSplitBits, bestSplitPhase))
                bestSplitBer = candBer;
                bestSplitLock = candLock;
                bestSplitErrs = candErrs;
                bestSplitBits = candBits;
                bestSplitStats = candStats;
                bestSplitPerFrameBER = candPerFrameBER;
                bestSplitPhase = iqPhase;
                bestSplitDecodedI = decodedI;
                bestSplitDecodedQ = decodedQ;
                bestSplitDecodedBits = decodedBits;
                bestSplitRSASM = splitRSASM;
                bestSplitStructureEvidence = splitStructureEvidence;
            end

            if ~useTMStructureIQPhase && ~splitRSASMEnabled && candBits > 0 && ...
                    candBer <= splitEarlyStopBER && candLock >= splitEarlyStopLock
                if splitDebug
                    fprintf('[SplitPath IQ phase early stop] iqPhase=%d, BER=%.4g, Lock=%.1f%%\n', ...
                        iqPhase, candBer, candLock*100);
                end
                break;
            end
        end

        berVal = bestSplitBer;
        if isinf(berVal)
            berVal = 0.5;
        end
        lockRate = max(bestSplitLock, 0);
        errs = bestSplitErrs;
        bitsComp = bestSplitBits;
        frameStats = bestSplitStats;
        if useSplitReceiverCoordinator
            frameStats.SplitReceiverImplementation = 'coordinator';
        else
            frameStats.SplitReceiverImplementation = 'legacy';
        end
        decodedI = bestSplitDecodedI; %#ok<NASGU>
        decodedQ = bestSplitDecodedQ; %#ok<NASGU>
        decodedBits = bestSplitDecodedBits; %#ok<NASGU>

        if splitDebug
            fprintf('[SplitPath IQ phase selected] mod=%s, iqPhase=%d, BER=%.4g, Lock=%.1f%%, Bits=%d\n', ...
                char(tmMod), bestSplitPhase, berVal, lockRate*100, bitsComp);
            localPrintSplitRailStats('selected', bestSplitPhase, frameStats);
            localPrintSplitRSASMAlignment('selected', bestSplitPhase, bestSplitRSASM);
        end

        if lockRate > 0.5 && bitsComp > 0
            localPrintPerFrameBER(bestSplitPerFrameBER, opt);
        end

        if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)') && contains(tmMod,'APSK')
            fprintf('[APSK BER] mod=%s, cfo=%.1f, phase=%.1f, snr=%.1f, BER=%.4e, errs=%d/%d\n', ...
                tmMod, getf(opt,'cfo',NaN), getf(opt,'phaseOffset',NaN), getf(opt,'snr',NaN), ...
                berVal, errs, bitsComp);
        end
        return;
    else
        externalASMAligned = gmskFrameResetAligned;
        modKeyForAlign = upper(string(tmMod));
        codeKeyForAlign = lower(string(tmCode));
        isConvForAlign = contains(codeKeyForAlign, 'convolutional');
        isRSForAlign = strcmpi(string(tmCode), "RS") || contains(codeKeyForAlign, 'rs');
        bitsPerSymForAlign = localBitsPerSymbolForDebug(tmMod);
        rsNeedsExternalASMAlign = contains(modKeyForAlign, '8PSK') || ...
            contains(modKeyForAlign, '16QAM') || contains(modKeyForAlign, '32QAM');
        rsPeriodicASMAlign = isRSForAlign && rsNeedsExternalASMAlign;
        if isfield(opt,'enableRSPeriodicASMAlign') && ~isempty(opt.enableRSPeriodicASMAlign)
            rsPeriodicASMAlign = logical(opt.enableRSPeriodicASMAlign);
        elseif isfield(opt,'EnableRSPeriodicASMAlign') && ~isempty(opt.EnableRSPeriodicASMAlign)
            rsPeriodicASMAlign = logical(opt.EnableRSPeriodicASMAlign);
        end
        rateForAlign = "";
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            rateForAlign = string(opt.ConvolutionalCodeRate);
        end
        needsPeriodicASMAlign = hasASM && ...
            (strcmpi(string(tmCode), "none") || isConvForAlign || rsPeriodicASMAlign);
        if gmskFrameResetAligned
            decArgs = [decArgs, {'DisableFrameSynchronization', true}];
            if getLogicalField(opt, 'debugCodedBoundary', false) || ...
                    getLogicalField(opt, 'debugGMSK', false)
                fprintf(['   [GMSK frame reset] decoder frame synchronization ', ...
                    'disabled after ASM-aided GMSK alignment\n']);
            end
        elseif needsPeriodicASMAlign
            [demodData, asmTrim, asmFound] = localTrimDemodToPeriodicASM(demodData, tmMod, tmCode, opt);
            externalASMAligned = asmTrim > 0 || (rsPeriodicASMAlign && asmFound);
            if getLogicalField(opt, 'debugCodedBoundary', false) && asmFound
                if rsPeriodicASMAlign
                    fprintf('   [ASM bit-align] %s/%s byte-sensitive RS path: bps=%d, trim=%d demod bits before decoder\n', ...
                        char(tmMod), char(tmCode), bitsPerSymForAlign, asmTrim);
                elseif asmTrim > 0
                    fprintf('   [ASM bit-align] %s/%s trimmed %d demod bits before decoder\n', ...
                        char(tmMod), char(tmCode), asmTrim);
                end
            end
            if externalASMAligned
                decArgs = [decArgs, {'DisableFrameSynchronization', true}];
                if getLogicalField(opt, 'debugCodedBoundary', false)
                    fprintf('   [ASM bit-align] decoder frame synchronization disabled after periodic ASM alignment\n');
                end
            end
        end

        codedSearchRate = "";
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            codedSearchRate = string(opt.ConvolutionalCodeRate);
        end
        isGMSKCodedSearch = contains(upper(string(tmMod)), 'GMSK');
        codedPhaseSearch = contains(lower(string(tmCode)), 'convolutional') && ...
            ~isGMSKCodedSearch && ...
            any(strcmp(char(codedSearchRate), {'1/2','2/3','3/4','5/6','7/8'}));
        if isfield(opt,'enableCodedPhaseSearch') && ~isempty(opt.enableCodedPhaseSearch)
            codedPhaseSearch = logical(opt.enableCodedPhaseSearch);
        end
        if codedPhaseSearch
            bestShift = 0;
            bestSyncOffset = 0;
            bestGood = -1;
            bestErrsForShift = inf;
            bestRun = -1;
            bestMatched = -1;
            bestDecodedBits = [];
            codedShiftList = localCodedPhaseShiftList(codedSearchRate);
            codedSyncOffsetList = localCodedSyncOffsetList(codedSearchRate);
            if externalASMAligned
                codedSyncOffsetList = 0;
            end
            for codedShift = codedShiftList
                if codedShift > 0
                    demodCandidate = demodData(codedShift+1:end);
                else
                    demodCandidate = demodData;
                end
                for syncOffset = codedSyncOffsetList
                    decoderArgsNow = decArgs;
                    if syncOffset ~= 0
                        decoderArgsNow = [decoderArgsNow, {'CodedSyncOffset', syncOffset}];
                    end
                    decoderobj = HelperCCSDSTMDecoder(decoderArgsNow{:});
                    decodedCandidate = decoderobj(demodCandidate);
                    [goodNow, errsNow, matchedNow, runNow] = scoreFrameQuality( ...
                        decodedCandidate, bitsPerFrame, txMap, opt);
                    if getLogicalField(opt, 'debugCodedBoundary', false)
                        fprintf('   [Coded phase search] cand shift=%d syncOffset=%+d, demodLen=%d, decodedLen=%d, numRx=%d, good=%d, matched=%d, run=%d, err=%d\n', ...
                            codedShift, syncOffset, numel(demodCandidate), numel(decodedCandidate), ...
                            floor(numel(decodedCandidate) / bitsPerFrame), ...
                            goodNow, matchedNow, runNow, errsNow);
                    end
                    if goodNow > bestGood || ...
                            (goodNow == bestGood && errsNow < bestErrsForShift) || ...
                            (goodNow == bestGood && errsNow == bestErrsForShift && runNow > bestRun) || ...
                            (goodNow == bestGood && errsNow == bestErrsForShift && runNow == bestRun && matchedNow > bestMatched)
                        bestGood = goodNow;
                        bestErrsForShift = errsNow;
                        bestRun = runNow;
                        bestMatched = matchedNow;
                        bestShift = codedShift;
                        bestSyncOffset = syncOffset;
                        bestDecodedBits = decodedCandidate;
                    end
                end
            end
            decodedBits = bestDecodedBits;
            if getLogicalField(opt, 'debugCodedBoundary', false)
                fprintf('   [Coded phase search] selected shift=%d syncOffset=%+d, good=%d, matched=%d, run=%d, err=%d\n', ...
                    bestShift, bestSyncOffset, bestGood, bestMatched, bestRun, bestErrsForShift);
            end
        else
            decoderobj = HelperCCSDSTMDecoder(decArgs{:});
            decodedBits = decoderobj(demodData);
        end
    end

%     decoderobj = HelperCCSDSTMDecoder(decArgs{:});
%     decodedBits = decoderobj(demodData);

    if getLogicalField(opt, 'debugCodedBoundary', false)
        maxFrameDebug = max(1, round(getfieldnumeric(opt, 'debugFrameCheckCount', 20)));
        localPrintDecodedFrameDebug(decodedBits, bitsPerFrame, txMap, ...
            sprintf('%s %s post-decoder', char(tmMod), char(tmCode)), maxFrameDebug);
    end

    if contains(tmMod,'GMSK') && length(decodedBits) >= bitsPerFrame
        debugGMSKPolarity = getLogicalField(opt, 'debugGMSK', false) || ...
            getLogicalField(opt, 'debugCodedBoundary', false);
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

    debugGMSKFrames = contains(tmMod,'GMSK') && ...
        (getLogicalField(opt, 'debugGMSK', false) || ...
         getLogicalField(opt, 'debugCodedBoundary', false));
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
    acquisitionConsecutiveFrames = localAcquisitionConsecutiveFrames(opt, numWarmUp);
    acquisitionMaxFrameBER = localAcquisitionMaxFrameBER(opt);
    acquiredForBER = false;
    matchedAfterAcquisition = 0;

    framesMatched=0;
    perFrameBER = nan(1,numRx);
    countedFrames = 0;
    frameErrors = 0;
    acquisitionFrames = NaN;
    debugFrameCheck = getLogicalField(opt, 'debugCodedBoundary', false) || ...
        getLogicalField(opt, 'debugFrameCheck', false);
    debugFrameLimit = max(0, round(getfieldnumeric(opt, 'debugFrameCheckCount', 20)));

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
            % acquisition 阶段只接受“帧号连续 + 本帧 BER 不像随机”的匹配帧。
            % 这样可以防止乱比特偶然撞上某个 frame ID 造成假同步。
            goodFrameForAcq = perFrameBER(j) <= acquisitionMaxFrameBER;
            if goodFrameForAcq
                if ~hasLastId
                    % 第一个可靠匹配帧，没有上一帧。
                    hasLastId = true;
                    consecIdCount = 1;
                else
                    expectedId = mod(lastRxId + 1, 256);
                    if rxId == expectedId
                        consecIdCount  = consecIdCount + 1;
                    else
                        consecIdCount = 1;
                    end
                end
                lastRxId = rxId;
            else
                hasLastId = false;
                consecIdCount = 0;
            end
            if ~acquiredForBER && consecIdCount >= acquisitionConsecutiveFrames
                acquiredForBER = true;
                acquisitionFrames = j;
                matchedAfterAcquisition = 0;
            end

            if acquiredForBER
                matchedAfterAcquisition = matchedAfterAcquisition + 1;
            end

            % acquisition 已通过 5 连续帧检测（防假锁），之后所有匹配帧都计入 BER。
            % 不再要求 matchedAfterAcquisition > numWarmUp —— 因为 numWarmUp 语义现在
            % 是 "总匹配帧至少 N 才算有意义的样本量"，用 acquiredForBER 已经覆盖。
            counted = acquiredForBER;

%             fprintf('\n   [FrameCheck] j=%d, rxId=%d, perBER=%.3f, counted=%d', ...
%                 j, rxId, perFrameBER(j), counted);

            if counted
                countedFrames = countedFrames + 1;
                if thisErrs > 0
                    frameErrors = frameErrors + 1;
                end
                errs = errs + thisErrs;
                bitsComp = bitsComp + bitsPerFrame;
            end
            if debugFrameCheck && j <= debugFrameLimit
                fprintf('   [FrameCheck] j=%03d rxId=%3d match=1 err=%5d ber=%.4f good=%d consec=%d acq=%d counted=%d\n', ...
                    j, rxId, thisErrs, perFrameBER(j), goodFrameForAcq, ...
                    consecIdCount, acquiredForBER, counted);
            end
        else
            if debugFrameCheck && j <= debugFrameLimit
                fprintf('   [FrameCheck] j=%03d rxId=%3d match=0 consec=%d acq=%d counted=0\n', ...
                    j, rxId, consecIdCount, acquiredForBER);
            end
        end
    end
    if bitsComp>0
        berVal = errs/bitsComp;
    elseif framesMatched > 0
        % 有匹配帧但从未通过 acquisition（说明只是零星假匹配），报为随机等价 BER
        berVal = 0.5;
    else
        % 一帧都没匹配上（帧同步彻底失败）
        berVal = NaN;
    end
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
    frameStats.GMSKDetectorUsed = char(gmskDetectorUsed);
    % numRx 太少说明解码器同步失败,只输出了 1 帧 zeros (header=0 偶然命中 warmup 帧 0),
    % 这种"虚假 100% lockRate"不能参与竞选,直接置零
    if countedFrames == 0
        lockRate = 0;
    elseif numRx < 3
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
        localPrintPerFrameBER(perFrameBER, opt);
    end
    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)') && contains(tmMod,'APSK')
        fprintf('[APSK BER] mod=%s, cfo=%.1f, phase=%.1f, snr=%.1f, BER=%.4e, errs=%d/%d\n', ...
            tmMod, getf(opt,'cfo',NaN), getf(opt,'phaseOffset',NaN), getf(opt,'snr',NaN), ...
            berVal, errs, bitsComp);
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

function shifts = localCodedPhaseShiftList(rateStr)
    switch char(string(rateStr))
        case '1/2'
            shifts = 0;
        case '2/3'
            shifts = 0:3;
        case '5/6'
            shifts = 0:5;
        case '7/8'
            shifts = 0:7;
        otherwise
            shifts = 0:3;
    end
end

function offsets = localCodedSyncOffsetList(rateStr)
    switch char(string(rateStr))
        case '1/2'
            offsets = 0:3;
        case '2/3'
            offsets = -12:4;
        case '3/4'
            offsets = -3:3;
        case '7/8'
            offsets = -4:4;
        otherwise
            offsets = 0;
    end
end

function [demodAligned, trimBits, alignedFound, alignmentInfo] = localTrimDemodToPeriodicASM(demodData, tmMod, tmCode, opt)
    demodAligned = demodData;
    trimBits = 0;
    alignedFound = false;
    alignmentInfo = struct( ...
        'BestError',NaN, ...
        'BestPosition',NaN, ...
        'MeanError',NaN, ...
        'PeriodicFrames',0, ...
        'Score',-inf, ...
        'PeriodBits',NaN, ...
        'TrimBits',0);
    if isempty(demodData)
        return;
    end

    [asmTemplates, periodBits] = localASMTemplatesForPhaseResolve(tmMod, tmCode, opt);
    alignmentInfo.PeriodBits = periodBits;
    if ~isfinite(periodBits) || periodBits <= 0
        return;
    end

    hardBits = int8(demodData(:) > 0);
    [bestErr, bestPos, meanErr, nFrames, score] = localBestASMPeriodicScore( ...
        hardBits, asmTemplates, periodBits, opt);
    alignmentInfo.BestError = bestErr;
    alignmentInfo.BestPosition = bestPos;
    alignmentInfo.MeanError = meanErr;
    alignmentInfo.PeriodicFrames = nFrames;
    alignmentInfo.Score = score;
    if bestPos <= 0 || nFrames < 2
        return;
    end

    asmLen = size(asmTemplates, 1);
    maxErr = max(2, ceil(0.20 * double(asmLen)));
    if bestErr > maxErr || meanErr > maxErr
        return;
    end
    alignedFound = true;

    asmOffsetBits = 0;
    if contains(lower(string(tmCode)), 'convolutional')
        rateStr = "1/2";
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            rateStr = string(opt.ConvolutionalCodeRate);
        end
        [~, ~, asmOffsetBits] = localConvASMTemplateByRate(rateStr, localTMASM(opt));
    end

    trimBits = mod(double(bestPos) - 1 - double(asmOffsetBits), double(periodBits));
    if trimBits > 0 && trimBits < numel(demodData)
        demodAligned = demodData(trimBits+1:end);
    else
        trimBits = 0;
    end
    alignmentInfo.TrimBits = trimBits;
end

function enabled = localUseSplitRSPeriodicASMAlignment(dataPathMode, tmMod, tmCode, hasASM, opt)
% Restrict this coordinator to the affected split-path RS cases.  The
% ordinary dual-I/Q high-order paths need independent byte alignment, and
% unequal UQPSK needs the same protection against a one-bit false ASM peak
% on either rail.  All single-stream and non-RS paths retain their existing
% logic.
    isOrdinaryDualRS = strcmpi(string(dataPathMode), "dualIQ") && ...
        any(strcmpi(string(tmMod), ...
            ["8PSK","16QAM","32QAM","16APSK","32APSK"]));
    isUnequalUQPSKRS = strcmpi(string(dataPathMode), "unequalDualIQ") && ...
        strcmpi(string(tmMod), "UQPSK");

    enabled = logical(hasASM) && strcmpi(string(tmCode), "RS") && ...
        (isOrdinaryDualRS || isUnequalUQPSKRS);

    if isfield(opt,'enableSplitRSPeriodicASMAlign') && ...
            ~isempty(opt.enableSplitRSPeriodicASMAlign)
        enabled = enabled && logical(opt.enableSplitRSPeriodicASMAlign);
    elseif isfield(opt,'EnableSplitRSPeriodicASMAlign') && ...
            ~isempty(opt.EnableSplitRSPeriodicASMAlign)
        enabled = enabled && logical(opt.EnableSplitRSPeriodicASMAlign);
    end
end

function alignment = localEmptySplitRSASMAlignment()
    rail = struct( ...
        'Found',false, ...
        'BestError',NaN, ...
        'BestPosition',NaN, ...
        'MeanError',NaN, ...
        'PeriodicFrames',0, ...
        'Score',-inf, ...
        'PeriodBits',NaN, ...
        'TrimBits',0);
    alignment = struct( ...
        'Enabled',false, ...
        'BothFound',false, ...
        'DecoderSyncDisabled',false, ...
        'Score',-inf, ...
        'MaxMeanError',inf, ...
        'TMStructureScore',-inf, ...
        'TMValidFrames',0, ...
        'TMMaxCounterRun',0, ...
        'TMOrientationScore',-inf, ...
        'TMSwappedOrientationScore',-inf, ...
        'TMFirstIFrameID',NaN, ...
        'TMFirstQFrameID',NaN, ...
        'I',rail, ...
        'Q',rail);
end

function [demodIForDecoder, demodQForDecoder, decArgsI, decArgsQ, alignment] = ...
        localPrepareSplitRSPeriodicASMAlignment( ...
        demodI, demodQ, decArgs, dataPathMode, tmMod, tmCode, hasASM, opt)
% Align raw RS ASM independently on I and Q.  The existing Decoder's
% frame synchronizer remains the fallback whenever either rail is not
% confidently aligned.
    demodIForDecoder = demodI;
    demodQForDecoder = demodQ;
    decArgsI = decArgs;
    decArgsQ = decArgs;
    alignment = localEmptySplitRSASMAlignment();
    alignment.Enabled = localUseSplitRSPeriodicASMAlignment( ...
        dataPathMode, tmMod, tmCode, hasASM, opt);
    if ~alignment.Enabled
        return;
    end

    [alignedI, ~, foundI, infoI] = localTrimDemodToPeriodicASM( ...
        demodI, tmMod, tmCode, opt);
    [alignedQ, ~, foundQ, infoQ] = localTrimDemodToPeriodicASM( ...
        demodQ, tmMod, tmCode, opt);

    alignment.I = localSplitRSASMInfoFromPeriodicInfo(infoI, foundI);
    alignment.Q = localSplitRSASMInfoFromPeriodicInfo(infoQ, foundQ);
    alignment.BothFound = foundI && foundQ;
    if alignment.BothFound
        alignment.Score = infoI.Score + infoQ.Score;
        alignment.MaxMeanError = max(infoI.MeanError, infoQ.MeanError);
        demodIForDecoder = alignedI;
        demodQForDecoder = alignedQ;
        decArgsI = localSetDecoderNameValue( ...
            decArgsI, 'DisableFrameSynchronization', true);
        decArgsQ = localSetDecoderNameValue( ...
            decArgsQ, 'DisableFrameSynchronization', true);
        alignment.DecoderSyncDisabled = true;
    end

end

function rail = localSplitRSASMInfoFromPeriodicInfo(info, found)
    rail = struct( ...
        'Found',logical(found), ...
        'BestError',info.BestError, ...
        'BestPosition',info.BestPosition, ...
        'MeanError',info.MeanError, ...
        'PeriodicFrames',info.PeriodicFrames, ...
        'Score',info.Score, ...
        'PeriodBits',info.PeriodBits, ...
        'TrimBits',info.TrimBits);
end

function alignment = localAttachSplitRSTMStructureScore( ...
        alignment, decodedI, decodedQ, bitsPerFrame, opt)
% I and Q carry the same ASM, so an odd-bit parity error can still produce
% perfect ASM correlations on both rails.  Break that unavoidable tie with
% the configured TM primary-header contract and counter continuity.  This
% uses no transmitted payload or BER reference.
    if ~isstruct(alignment) || ~isfield(alignment,'Enabled') || ...
            ~alignment.Enabled || ~alignment.BothFound
        return;
    end

    scoreI = localScoreDecodedTMStructure(decodedI, bitsPerFrame, opt);
    scoreQ = localScoreDecodedTMStructure(decodedQ, bitsPerFrame, opt);
    alignment.TMStructureScore = scoreI.Score + scoreQ.Score;
    alignment.TMValidFrames = scoreI.ValidFrames + scoreQ.ValidFrames;
    alignment.TMMaxCounterRun = scoreI.MaxCounterRun + scoreQ.MaxCounterRun;
    counterConvention = lower(string(getfieldwithdefault( ...
        opt, 'splitRSTMFrameCounterConvention', 'interleavedEvenOdd')));
    if counterConvention == "interleavedevenodd" && ...
            ~isempty(scoreI.VCFC) && ~isempty(scoreQ.VCFC)
        alignment.TMFirstIFrameID = scoreI.VCFC(1);
        alignment.TMFirstQFrameID = scoreQ.VCFC(1);
        alignment.TMOrientationScore = ...
            nnz(mod(scoreI.VCFC,2) == 0) + nnz(mod(scoreQ.VCFC,2) == 1);
        alignment.TMSwappedOrientationScore = ...
            nnz(mod(scoreI.VCFC,2) == 1) + nnz(mod(scoreQ.VCFC,2) == 0);
    end
end

function result = localScoreDecodedTMStructure(decodedBits, bitsPerFrame, opt)
    result = struct( ...
        'Score',-inf, ...
        'ValidFrames',0, ...
        'MaxCounterRun',0, ...
        'FieldMatches',0, ...
        'FramesChecked',0, ...
        'VCFC',zeros(0,1));
    numFrames = floor(numel(decodedBits) / bitsPerFrame);
    if bitsPerFrame < 37 || numFrames < 1
        return;
    end

    maxFrames = min(numFrames, max(1, round(getfieldnumeric( ...
        opt, 'splitRSTMHeaderScoreFrames', 32))));
    expectedVersion = round(getfieldnumeric(opt, ...
        'TransferFrameVersionNumber', 0));
    expectedSCID = round(getfieldnumeric(opt, 'SpacecraftID', 1));
    expectedVCID = round(getfieldnumeric(opt, 'VirtualChannelID', 0));
    expectedOCF = double(getLogicalField(opt, 'HasOCF', false));
    expectedSHF = double(getLogicalField(opt, 'HasSecondaryHeader', false));
    expectedSync = round(getfieldnumeric(opt, 'SynchronizationFlag', 0));
    expectedPacketOrder = round(getfieldnumeric(opt, 'PacketOrderFlag', 0));
    expectedSLID = getfieldnumeric(opt, 'SegmentLengthID', NaN);
    if ~isfinite(expectedSLID)
        expectedSLID = 3 * double(expectedSync == 0);
    end
    expectedSLID = round(expectedSLID);

    vcfc = zeros(maxFrames,1);
    mcfc = zeros(maxFrames,1);
    fieldMatches = 0;
    validFrames = 0;
    for iFrame = 1:maxFrames
        idx = (iFrame-1)*bitsPerFrame + (1:37);
        header = uint8(decodedBits(idx) ~= 0);
        version = localBitsToUnsignedMSB(header(1:2));
        scid = localBitsToUnsignedMSB(header(3:12));
        vcid = localBitsToUnsignedMSB(header(13:15));
        ocf = double(header(16));
        mcfc(iFrame) = localBitsToUnsignedMSB(header(17:24));
        vcfc(iFrame) = localBitsToUnsignedMSB(header(25:32));
        shf = double(header(33));
        syncFlag = double(header(34));
        packetOrder = double(header(35));
        slid = localBitsToUnsignedMSB(header(36:37));

        matches = [ ...
            version == expectedVersion, ...
            scid == expectedSCID, ...
            vcid == expectedVCID, ...
            ocf == expectedOCF, ...
            shf == expectedSHF, ...
            syncFlag == expectedSync, ...
            packetOrder == expectedPacketOrder, ...
            slid == expectedSLID];
        fieldMatches = fieldMatches + nnz(matches);
        validFrames = validFrames + all(matches);
    end

    maxCounterRun = max([ ...
        localModuloCounterRun(vcfc, 1), ...
        localModuloCounterRun(vcfc, 2), ...
        localModuloCounterRun(mcfc, 1), ...
        localModuloCounterRun(mcfc, 2)]);
    result.ValidFrames = validFrames;
    result.MaxCounterRun = maxCounterRun;
    result.FieldMatches = fieldMatches;
    result.FramesChecked = maxFrames;
    result.VCFC = vcfc;
    result.Score = 1000*validFrames + 10*maxCounterRun + ...
        fieldMatches / maxFrames;
end

function value = localBitsToUnsignedMSB(bits)
    bits = double(bits(:).' ~= 0);
    value = sum(bits .* 2.^(numel(bits)-1:-1:0));
end

function maxRun = localModuloCounterRun(values, step)
    values = double(values(:));
    if isempty(values)
        maxRun = 0;
        return;
    end
    maxRun = 1;
    runLength = 1;
    for k = 2:numel(values)
        if values(k) == mod(values(k-1) + step, 256)
            runLength = runLength + 1;
        else
            runLength = 1;
        end
        maxRun = max(maxRun, runLength);
    end
end

function args = localSetDecoderNameValue(args, name, value)
    for k = 1:2:numel(args)-1
        if strcmpi(string(args{k}), string(name))
            args{k+1} = value;
            return;
        end
    end
    args = [args, {name, value}];
end

function localPrintSplitRSASMAlignment(label, iqPhase, alignment)
    if ~isstruct(alignment) || ~isfield(alignment,'Enabled') || ~alignment.Enabled
        return;
    end
    if isnan(iqPhase)
        phaseText = 'n/a';
    else
        phaseText = sprintf('%d', iqPhase);
    end
    stateText = 'fallback';
    if alignment.BothFound
        stateText = 'aligned';
    end
    fprintf(['[SplitPath RS ASM %s] iqPhase=%s state=%s asmScore=%.3f ', ...
        'tmScore=%.3f validTM=%g counterRun=%g ', ...
        'orientation=%g swapped=%g firstVCFC=%g/%g ', ...
        '| I: found=%d trim=%d pos=%g err=%g mean=%.2f frames=%g ', ...
        '| Q: found=%d trim=%d pos=%g err=%g mean=%.2f frames=%g\n'], ...
        char(string(label)), phaseText, stateText, alignment.Score, ...
        alignment.TMStructureScore, alignment.TMValidFrames, ...
        alignment.TMMaxCounterRun, alignment.TMOrientationScore, ...
        alignment.TMSwappedOrientationScore, alignment.TMFirstIFrameID, ...
        alignment.TMFirstQFrameID, ...
        alignment.I.Found, alignment.I.TrimBits, alignment.I.BestPosition, ...
        alignment.I.BestError, alignment.I.MeanError, alignment.I.PeriodicFrames, ...
        alignment.Q.Found, alignment.Q.TrimBits, alignment.Q.BestPosition, ...
        alignment.Q.BestError, alignment.Q.MeanError, alignment.Q.PeriodicFrames);
end

function better = localIsBetterSplitRSASMCandidate( ...
        candAlignment, candBer, candLock, candBits, candPhase, ...
        bestAlignment, bestBer, bestLock, bestBits, bestPhase)
% For the targeted RS path, choose odd-bit parity using independent I/Q
% periodic ASM evidence rather than payload BER.  If no parity hypothesis
% has credible ASM on both rails, preserve the former BER/lock fallback.
    if isstruct(candAlignment) && isfield(candAlignment,'Enabled') && ...
            candAlignment.Enabled
        candFound = candAlignment.BothFound;
        bestFound = isstruct(bestAlignment) && isfield(bestAlignment,'BothFound') && ...
            bestAlignment.BothFound;
        if candFound && ~bestFound
            better = true;
            return;
        elseif ~candFound && bestFound
            better = false;
            return;
        elseif candFound && bestFound
            tol = 1e-12;
            if isfinite(candAlignment.TMOrientationScore) && ...
                    isfinite(bestAlignment.TMOrientationScore) && ...
                    candAlignment.TMOrientationScore > ...
                    bestAlignment.TMOrientationScore
                better = true;
                return;
            elseif isfinite(candAlignment.TMOrientationScore) && ...
                    isfinite(bestAlignment.TMOrientationScore) && ...
                    candAlignment.TMOrientationScore < ...
                    bestAlignment.TMOrientationScore
                better = false;
                return;
            elseif candAlignment.TMStructureScore > ...
                    bestAlignment.TMStructureScore + tol
                better = true;
                return;
            elseif candAlignment.TMStructureScore < ...
                    bestAlignment.TMStructureScore - tol
                better = false;
                return;
            elseif candAlignment.TMValidFrames > bestAlignment.TMValidFrames
                better = true;
                return;
            elseif candAlignment.TMValidFrames < bestAlignment.TMValidFrames
                better = false;
                return;
            elseif candAlignment.Score > bestAlignment.Score + tol
                better = true;
                return;
            elseif candAlignment.Score < bestAlignment.Score - tol
                better = false;
                return;
            elseif candAlignment.MaxMeanError < bestAlignment.MaxMeanError - tol
                better = true;
                return;
            elseif candAlignment.MaxMeanError > bestAlignment.MaxMeanError + tol
                better = false;
                return;
            end
            better = candPhase < bestPhase;
            return;
        end
    end

    better = localIsBetterSplitCandidate( ...
        candBer, candLock, candBits, bestBer, bestLock, bestBits);
end

function [goodFrames, totalErrs, matched, maxRun] = scoreFrameQuality(bits, bitsPerFrame, txMap, opt)
    goodFrames = 0;
    totalErrs = 0;
    matched = 0;
    maxRun = 0;
    runLen = 0;
    lastId = [];
    maxFrameBER = localAcquisitionMaxFrameBER(opt);
    numRx = floor(length(bits) / bitsPerFrame);

    for j = 1:numRx
        rxFr = double(bits((j-1)*bitsPerFrame+1:j*bitsPerFrame));
        rxId = localTMFrameID(rxFr);
        if ~isKey(txMap, rxId)
            runLen = 0;
            lastId = [];
            continue;
        end

        matched = matched + 1;
        thisErrs = biterr(txMap(rxId), rxFr);
        if thisErrs / bitsPerFrame > maxFrameBER
            runLen = 0;
            lastId = [];
            continue;
        end

        goodFrames = goodFrames + 1;
        totalErrs = totalErrs + thisErrs;
        if isempty(lastId) || rxId == mod(lastId + 1, 256)
            runLen = runLen + 1;
        else
            runLen = 1;
        end
        maxRun = max(maxRun, runLen);
        lastId = rxId;
    end
end

function localPrintDemodDataDebug(demodData, tmMod, tmCode, bitsPerFrame)
    if isempty(demodData)
        fprintf('   [Coded DEBUG] demodData is empty (%s/%s)\n', ...
            char(tmMod), char(tmCode));
        return;
    end

    x = double(demodData(:));
    hard = x > 0;
    finiteMask = isfinite(x);
    if any(finiteMask)
        xFinite = x(finiteMask);
        fprintf('   [Coded DEBUG] demod soft (%s/%s): len=%d, bitsPerFrame=%d, mean=%+.4g, std=%.4g, min=%+.4g, max=%+.4g, hard1=%.1f%%\n', ...
            char(tmMod), char(tmCode), numel(x), bitsPerFrame, ...
            mean(xFinite), std(xFinite), min(xFinite), max(xFinite), 100*mean(hard));
    else
        fprintf('   [Coded DEBUG] demod soft (%s/%s): len=%d, bitsPerFrame=%d, all non-finite\n', ...
            char(tmMod), char(tmCode), numel(x), bitsPerFrame);
    end
end

function localPrintDecodedFrameDebug(decodedBits, bitsPerFrame, txMap, label, maxFrames)
    if nargin < 5 || isempty(maxFrames)
        maxFrames = 20;
    end
    numRx = floor(numel(decodedBits) / bitsPerFrame);
    nShow = min(maxFrames, numRx);
    fprintf('   [FrameID DEBUG] %s: decodedBits=%d, bitsPerFrame=%d, numRx=%d, show=%d\n', ...
        char(label), numel(decodedBits), bitsPerFrame, numRx, nShow);

    for j = 1:nShow
        idx = (j-1)*bitsPerFrame + (1:bitsPerFrame);
        rxFr = double(decodedBits(idx));
        rxId = localTMFrameID(rxFr);
        if isKey(txMap, rxId)
            thisErrs = biterr(txMap(rxId), rxFr);
            fprintf('      j=%03d rxId=%3d match=1 err=%5d ber=%.4f\n', ...
                j, rxId, thisErrs, thisErrs / bitsPerFrame);
        else
            fprintf('      j=%03d rxId=%3d match=0\n', j, rxId);
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
        assignin('base', 'debugTPC_demodBestOffset', best.offset);
        assignin('base', 'debugTPC_demodBestPolarity', best.polarity);
        fprintf('   [Coded DEBUG] demod-vs-encoded (%s): bestOffset=%d bits, polarity=%+d, hardBER=%.6g (%d/%d)\n', ...
            char(tmMod), best.offset, best.polarity, best.err / best.len, best.err, best.len);
        localTPCPrintBitPlaneDebug(demodData, txBits, tmMod, best);
    end
end

function localTPCPrintBitPlaneDebug(demodData, txBits, tmMod, best)
    bitsPerSym = localBitsPerSymbolForDebug(tmMod);
    if bitsPerSym <= 1 || best.len <= 0
        return;
    end

    rxSoft = double(demodData(:));
    rxSoft = rxSoft(best.offset+1:best.offset+best.len);
    if best.polarity < 0
        rxSoft = -rxSoft;
    end
    rxHard = int8(rxSoft > 0);
    txAlign = int8(txBits(1:best.len));

    fprintf('   [TPC DEBUG] bit-plane hardBER/soft | ');
    for iPlane = 1:bitsPerSym
        idx = iPlane:bitsPerSym:best.len;
        if isempty(idx)
            continue;
        end
        nErr = nnz(rxHard(idx) ~= txAlign(idx));
        planeBER = nErr / numel(idx);
        meanAbsSoft = mean(abs(rxSoft(idx)));
        hardOnePct = 100 * mean(rxHard(idx) ~= 0);
        fprintf('b%d:BER=%.4g,|s|=%.3g,1=%.1f%%; ', ...
            iPlane, planeBER, meanAbsSoft, hardOnePct);
    end
    fprintf('\n');
end

function bitsPerSym = localBitsPerSymbolForDebug(tmMod)
    modKey = upper(strtrim(char(tmMod)));
    if contains(modKey, '32QAM') || contains(modKey, '32APSK')
        bitsPerSym = 5;
    elseif contains(modKey, '16QAM') || contains(modKey, '16APSK')
        bitsPerSym = 4;
    elseif contains(modKey, '8PSK')
        bitsPerSym = 3;
    elseif contains(modKey, 'QPSK') || contains(modKey, 'OQPSK') || contains(modKey, 'UQPSK')
        bitsPerSym = 2;
    else
        bitsPerSym = 1;
    end
end

function info = localEmptyTMAPSKPilotInfo()
    info = struct( ...
        'Enabled', false, ...
        'Applied', false, ...
        'Reason', '', ...
        'Start', 0, ...
        'NumPilots', 0, ...
        'NumDataSymbols', 0, ...
        'CFO_Hz', NaN, ...
        'MeanAmp', NaN, ...
        'CorrectionMode', '', ...
        'CorrRatio', NaN);
end

function [dataSym, info] = localCorrectAndRemoveTMAPSKPilots(rxSym, opt, symbolRate)
    dataSym = rxSym;
    info = localEmptyTMAPSKPilotInfo();
    info.Enabled = true;

    if isfield(opt,'HasTMAPSKPilots') && ~isempty(opt.HasTMAPSKPilots) && ...
            ~localFlagValue(opt.HasTMAPSKPilots)
        info.Reason = 'disabled by HasTMAPSKPilots';
        return;
    end

    rx = rxSym(:);
    if isempty(rx)
        info.Reason = 'empty input';
        dataSym = rx;
        return;
    end

    pilotInterval = max(1, round(getfieldnumeric(opt, 'TMAPSKPilotInterval', 512)));
    pilotLen = max(1, round(getfieldnumeric(opt, 'TMAPSKPilotLength', 32)));
    preambleLen = max(1, round(getfieldnumeric(opt, 'TMAPSKPilotPreambleLength', 64)));
    if numel(rx) < preambleLen + 8
        info.Reason = 'too few symbols for pilot preamble';
        return;
    end

    preamble = localTMAPSKPilotSequence(preambleLen, 1);
    pilot = localTMAPSKPilotSequence(pilotLen, 2);
    rxNorm = rx ./ sqrt(mean(abs(rx).^2) + eps);

    defaultSearch = max(4096, preambleLen + pilotInterval + pilotLen + 32);
    searchSpan = max(preambleLen, round(getfieldnumeric(opt, 'TMAPSKPilotSearchSpan', defaultSearch)));
    maxStart = min(numel(rxNorm) - preambleLen + 1, searchSpan);
    if maxStart < 1
        info.Reason = 'no room for pilot preamble search';
        return;
    end

    scores = zeros(maxStart, 1);
    for pos = 1:maxStart
        seg = rxNorm(pos:pos+preambleLen-1);
        scores(pos) = abs(sum(seg .* conj(preamble)));
    end
    [bestScore, startPos] = max(scores);
    sortedScores = sort(scores, 'descend');
    if numel(sortedScores) >= 2 && sortedScores(2) > 0
        info.CorrRatio = sortedScores(1) / sortedScores(2);
    else
        info.CorrRatio = Inf;
    end

    minScore = getfieldnumeric(opt, 'TMAPSKPilotMinPreambleScore', 0.35 * preambleLen);
    if bestScore < minScore
        info.Reason = sprintf('pilot preamble correlation too weak: %.3f', bestScore);
        return;
    end

    pilotPos = (startPos:startPos+preambleLen-1).';
    pilotRef = preamble(:);
    pilotMask = false(numel(rx), 1);
    dataMask = false(numel(rx), 1);
    pilotMask(pilotPos) = true;

    pos = startPos + preambleLen;
    while pos <= numel(rx)
        dataEnd = min(pos + pilotInterval - 1, numel(rx));
        if dataEnd >= pos
            dataMask(pos:dataEnd) = true;
        end
        pos = dataEnd + 1;
        if pos + pilotLen - 1 <= numel(rx)
            pidx = (pos:pos+pilotLen-1).';
            pilotPos = [pilotPos; pidx]; %#ok<AGROW>
            pilotRef = [pilotRef; pilot(:)]; %#ok<AGROW>
            pilotMask(pidx) = true;
            pos = pos + pilotLen;
        else
            break;
        end
    end
    dataMask(pilotMask) = false;

    if numel(pilotPos) < max(8, preambleLen)
        info.Reason = 'too few pilots';
        return;
    end

    hPilotRaw = rx(pilotPos) ./ pilotRef;
    adjValid = diff(pilotPos) == 1;
    if any(adjValid)
        adjProducts = hPilotRaw(2:end) .* conj(hPilotRaw(1:end-1));
        slopeRadPerSym = angle(sum(adjProducts(adjValid)));
    else
        slopeRadPerSym = 0;
    end
    allIdx0 = (0:numel(rx)-1).';
    rxCoarse = rx .* exp(-1j * slopeRadPerSym * allIdx0);

    hPilotCoarse = rxCoarse(pilotPos) ./ pilotRef;
    blockBreaks = [1; find(diff(pilotPos) > 1) + 1; numel(pilotPos) + 1];
    numBlocks = numel(blockBreaks) - 1;
    blockCenters = zeros(numBlocks, 1);
    blockH = complex(zeros(numBlocks, 1));
    for iBlock = 1:numBlocks
        idx = blockBreaks(iBlock):(blockBreaks(iBlock+1)-1);
        blockCenters(iBlock) = mean(double(pilotPos(idx)));
        blockH(iBlock) = mean(hPilotCoarse(idx));
    end
    residualSlope = 0;
    if numBlocks >= 2
        blockPhase = unwrap(angle(blockH));
        residualCoef = polyfit(blockCenters, blockPhase, 1);
        residualSlope = residualCoef(1);
    end
    totalSlopeRadPerSym = slopeRadPerSym + residualSlope;
    rxCFO = rx .* exp(-1j * totalSlopeRadPerSym * allIdx0);

    rxPilot = rxCFO(pilotPos);
    hPilot = rxPilot ./ pilotRef;
    amp = abs(hPilot);
    allIdx = (1:numel(rx)).';

    correctionMode = "global";
    if isfield(opt,'TMAPSKPilotCorrectionMode') && ~isempty(opt.TMAPSKPilotCorrectionMode)
        correctionMode = lower(string(opt.TMAPSKPilotCorrectionMode));
    end
    info.CorrectionMode = char(correctionMode);
    if correctionMode == "interp"
        ph = unwrap(angle(hPilot));
        phInterp = interp1(double(pilotPos), ph, double(allIdx), 'linear', 'extrap');
        ampInterp = interp1(double(pilotPos), amp, double(allIdx), 'linear', 'extrap');
        ampInterp = max(ampInterp, sqrt(eps));
        hInterp = ampInterp .* exp(1j * phInterp);
    elseif correctionMode == "phaseinterp" || correctionMode == "phase"
        blockCentersPost = zeros(numBlocks, 1);
        blockHPost = complex(zeros(numBlocks, 1));
        for iBlock = 1:numBlocks
            idx = blockBreaks(iBlock):(blockBreaks(iBlock+1)-1);
            blockCentersPost(iBlock) = mean(double(pilotPos(idx)));
            blockHPost(iBlock) = mean(hPilot(idx));
        end

        validBlocks = abs(blockHPost) > sqrt(eps);
        if nnz(validBlocks) >= 2
            phBlock = unwrap(angle(blockHPost(validBlocks)));
            smoothWindow = max(1, round(getfieldnumeric(opt, 'TMAPSKPilotPhaseSmoothWindow', 3)));
            if smoothWindow > 1 && numel(phBlock) >= smoothWindow
                phBlock = movmean(phBlock, smoothWindow);
            end
            phInterp = interp1(double(blockCentersPost(validBlocks)), phBlock, ...
                double(allIdx), 'linear', 'extrap');
            amp0 = median(amp(isfinite(amp) & amp > 0));
            if isempty(amp0) || ~isfinite(amp0) || amp0 < sqrt(eps)
                amp0 = 1;
            end
            hInterp = amp0 .* exp(1j * phInterp);
        else
            h0 = mean(hPilot);
            if abs(h0) < sqrt(eps)
                h0 = 1;
            end
            hInterp = repmat(h0, numel(rx), 1);
        end
    else
        h0 = mean(hPilot);
        if abs(h0) < sqrt(eps)
            h0 = 1;
        end
        hInterp = repmat(h0, numel(rx), 1);
    end
    rxCorr = rxCFO ./ hInterp;

    dataSym = rxCorr(dataMask);
    if isempty(dataSym)
        info.Reason = 'pilot removal produced no data symbols';
        dataSym = rxSym;
        return;
    end

    info.Applied = true;
    info.Reason = 'applied';
    info.Start = startPos;
    info.NumPilots = numel(pilotPos);
    info.NumDataSymbols = numel(dataSym);
    info.CFO_Hz = totalSlopeRadPerSym * double(symbolRate) / (2*pi);
    info.MeanAmp = mean(amp);

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
        fprintf('[APSK TM pilots] applied=%d, start=%d, pilots=%d, data=%d, corrRatio=%.3f, cfoEst=%.2f Hz, meanAmp=%.4f\n', ...
            info.Applied, info.Start, info.NumPilots, info.NumDataSymbols, ...
            info.CorrRatio, info.CFO_Hz, info.MeanAmp);
        assignin('base','debug_tmapsk_pilot_pos', pilotPos(:));
        assignin('base','debug_tmapsk_pilot_h', hPilot(:));
        assignin('base','debug_tmapsk_data_symbols', dataSym(1:min(2000,end)));
    end
end

function p = localTMAPSKPilotSequence(N, seed)
    N = max(0, round(double(N)));
    if N == 0
        p = complex(zeros(0,1));
        return;
    end
    n = (1:N).';
    q = mod(floor(abs(sin((n + double(seed)*97) * 12.9898) * 43758.5453)), 4);
    p = exp(1j * (pi/4 + pi/2*q));
    p = p ./ sqrt(mean(abs(p).^2) + eps);
end

function info = localEmptyAPSKASMInfo()
    info = struct( ...
        'Enabled', false, ...
        'Applied', false, ...
        'CFO_Hz', NaN, ...
        'Phase_deg', NaN, ...
        'FirstPos', 0, ...
        'NumFrames', 0, ...
        'SymsPerFrame', 0, ...
        'CorrRatio', NaN, ...
        'Reason', '');
end

function [correctedSyms, info] = localAPSKASMFineCorrection(rxSyms, modStr, tmCode, opt, symbolRate, hasASM)
    correctedSyms = rxSyms;
    info = localEmptyAPSKASMInfo();
    info.Enabled = true;

    if isfield(opt,'enableAPSKASMFineCorrection') && ~isempty(opt.enableAPSKASMFineCorrection) && ...
            ~localFlagValue(opt.enableAPSKASMFineCorrection)
        info.Reason = 'disabled by enableAPSKASMFineCorrection';
        return;
    end
    if isfield(opt,'enableAPSKASMCarrierFine') && ~isempty(opt.enableAPSKASMCarrierFine) && ...
            ~localFlagValue(opt.enableAPSKASMCarrierFine)
        info.Reason = 'disabled by enableAPSKASMCarrierFine';
        return;
    end
    if ~hasASM
        info.Reason = 'HasASM is false';
        return;
    end
    carrierOffsetRequested = abs(getfieldnumeric(opt, 'cfo', 0)) > 0 || ...
        abs(getfieldnumeric(opt, 'phaseOffset', 0)) > 0;
    if ~carrierOffsetRequested
        info.Reason = 'no carrier offset requested';
        return;
    end
    codeKey = lower(string(tmCode));
    if ~any(strcmp(codeKey, ["none", "rs"]))
        info.Reason = 'only ChannelCoding=none/RS is enabled in this phase';
        return;
    end

    rx = rxSyms(:);
    if numel(rx) < 64
        info.Reason = 'too few symbols';
        return;
    end

    bps = localBitsPerSymbolForDebug(modStr);
    asmBits = localTMASM(opt);
    if mod(numel(asmBits), bps) ~= 0
        info.Reason = 'ASM is not symbol-aligned for this APSK order';
        return;
    end

    periodBits = localASMPeriodBits(modStr, tmCode, opt);
    if mod(periodBits, bps) ~= 0
        info.Reason = 'frame length is not symbol-aligned';
        return;
    end
    symsPerFrame = periodBits / bps;
    info.SymsPerFrame = symsPerFrame;

    asmRef = localAPSKASMReferenceSymbols(asmBits, modStr);
    asmRef = asmRef(:) ./ sqrt(mean(abs(asmRef).^2) + eps);
    numAsmSym = numel(asmRef);
    maxStart = numel(rx) - numAsmSym + 1;
    if maxStart < symsPerFrame
        info.Reason = 'not enough symbols for periodic ASM search';
        return;
    end

    rxNorm = rx ./ sqrt(mean(abs(rx).^2) + eps);
    maxFramesForSearch = max(3, round(getfieldnumeric(opt, 'apskASMMaxSearchFrames', 64)));
    offsetScores = zeros(symsPerFrame, 1);
    offsetFrames = zeros(symsPerFrame, 1);
    for offset = 1:symsPerFrame
        pos = offset:symsPerFrame:maxStart;
        if numel(pos) > maxFramesForSearch
            pos = pos(1:maxFramesForSearch);
        end
        mags = zeros(numel(pos), 1);
        for k = 1:numel(pos)
            seg = rxNorm(pos(k):pos(k)+numAsmSym-1);
            mags(k) = abs(sum(seg .* conj(asmRef)));
        end
        if ~isempty(mags)
            offsetScores(offset) = median(mags) + 0.25*mean(mags);
            offsetFrames(offset) = numel(mags);
        end
    end

    [bestScore, bestOffset] = max(offsetScores);
    if bestScore <= 0 || offsetFrames(bestOffset) < 3
        info.Reason = 'periodic ASM correlation failed';
        return;
    end
    sortedScores = sort(offsetScores, 'descend');
    if numel(sortedScores) >= 2 && sortedScores(2) > 0
        info.CorrRatio = sortedScores(1) / sortedScores(2);
    else
        info.CorrRatio = Inf;
    end

    minCorrRatio = getfieldnumeric(opt, 'apskASMCorrRatioMin', 1.03);
    if info.CorrRatio < minCorrRatio
        info.Reason = sprintf('ASM correlation ambiguous: ratio=%.3f', info.CorrRatio);
        if ~(isfield(opt,'allowAmbiguousAPSKASM') && localFlagValue(opt.allowAmbiguousAPSKASM))
            return;
        end
    end

    pos = bestOffset:symsPerFrame:maxStart;
    maxFramesForFit = max(3, round(getfieldnumeric(opt, 'apskASMMaxFitFrames', 96)));
    if numel(pos) > maxFramesForFit
        pos = pos(1:maxFramesForFit);
    end

    noAmbigCFO = double(symbolRate) / (2 * symsPerFrame);
    requestedCFOHz = getfieldnumeric(opt, 'cfo', 0);
    cfoPriorHz = requestedCFOHz;
    if isfield(opt,'apskASMCoarseCenterHz') && ~isempty(opt.apskASMCoarseCenterHz)
        cfoPriorHz = getfieldnumeric(opt, 'apskASMCoarseCenterHz', cfoPriorHz);
    elseif isfield(opt,'apskASMCoarsePriorHz') && ~isempty(opt.apskASMCoarsePriorHz)
        cfoPriorHz = getfieldnumeric(opt, 'apskASMCoarsePriorHz', cfoPriorHz);
    end
    useCoarseCFOScan = strcmp(codeKey, "rs") && abs(cfoPriorHz) > noAmbigCFO;
    if isfield(opt,'enableAPSKASMCoarseCFOScan') && ~isempty(opt.enableAPSKASMCoarseCFOScan)
        useCoarseCFOScan = localFlagValue(opt.enableAPSKASMCoarseCFOScan);
    end
    cfoCoarseHz = 0;
    rxFit = rxNorm;
    if useCoarseCFOScan
        cfoMaxHz = getfieldnumeric(opt, 'apskASMCoarseCFOMaxHz', 3000);
        cfoStepHz = getfieldnumeric(opt, 'apskASMCoarseCFOStepHz', noAmbigCFO/2);
        numCoarseFrames = max(1, round(getfieldnumeric(opt, 'apskASMCoarseFrames', 6)));
        [cfoCoarseHz, coarseCFOGrid, coarseCFOScores] = localAPSKASMCoarseCFOScan( ...
            rxNorm, asmRef, bestOffset, symsPerFrame, symbolRate, ...
            cfoMaxHz, cfoStepHz, numCoarseFrames, cfoPriorHz);
        nCoarse = (0:numel(rxNorm)-1).';
        rxFit = rxNorm .* exp(-1j * (2*pi*cfoCoarseHz/double(symbolRate)) * nCoarse);

        if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
            fprintf('[APSK ASM coarse] cfoCoarse=%.1f Hz, prior=%.1f Hz, search=[%.1f, %.1f] Hz, step=%.1f Hz\n', ...
                cfoCoarseHz, cfoPriorHz, -abs(cfoMaxHz), abs(cfoMaxHz), cfoStepHz);
            assignin('base','debug_apsk_asm_coarse_cfo_grid', coarseCFOGrid(:));
            assignin('base','debug_apsk_asm_coarse_cfo_scores', coarseCFOScores(:));
        end
    end

    z = zeros(numel(pos), 1);
    zBlocks = zeros(numAsmSym, numel(pos));
    for k = 1:numel(pos)
        seg = rxFit(pos(k):pos(k)+numAsmSym-1);
        zBlocks(:, k) = seg .* conj(asmRef);
        z(k) = sum(zBlocks(:, k));
    end
    mags = abs(z);
    phases = angle(z);
    phaseUnwAll = unwrap(phases);

    minFrames = max(3, round(getfieldnumeric(opt, 'apskASMMinFitFrames', 5)));
    good = isfinite(phases) & mags > 0;
    if nnz(good) < minFrames
        info.Reason = 'too few ASM phase samples';
        return;
    end

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
        phaseDiffRaw = diff(phases);
        phaseDiffWrapped = mod(phaseDiffRaw + pi, 2*pi) - pi;
        theoreticalFrameDiffDeg = 360 * requestedCFOHz * symsPerFrame / double(symbolRate);
        peakToMean = max(mags) / (mean(mags) + eps);
        fprintf('[APSK ASM fine] symsPerFrame=%d, no-ambig CFO limit = +/-%.1f Hz\n', ...
            symsPerFrame, noAmbigCFO);
        fprintf('[APSK ASM fine] frame-to-frame diff raw  (deg) = %s\n', ...
            mat2str(round(rad2deg(phaseDiffRaw(1:min(6,end))), 1).'));
        fprintf('[APSK ASM fine] frame-to-frame diff wrap (deg) = %s\n', ...
            mat2str(round(rad2deg(phaseDiffWrapped(1:min(6,end))), 1).'));
        fprintf('[APSK ASM fine] median wrapped diff = %.2f deg (theoretical %.2f deg for requested CFO=%.0f Hz)\n', ...
            rad2deg(median(phaseDiffWrapped)), theoreticalFrameDiffDeg, requestedCFOHz);
        fprintf('[APSK ASM fine] phase raw  (deg) first 6 = %s\n', ...
            mat2str(round(rad2deg(phases(1:min(6,end))), 1).'));
        fprintf('[APSK ASM fine] phase unw  (deg) first 6 = %s\n', ...
            mat2str(round(rad2deg(phaseUnwAll(1:min(6,end))), 1).'));
        fprintf('[APSK ASM fine] corr peakToMean = %.2f (>>1 is good; near 1 means noise-dominated)\n', ...
            peakToMean);
    end

    useIntraASMSlope = false;
    if isfield(opt,'apskASMUseIntraBlockSlope') && ~isempty(opt.apskASMUseIntraBlockSlope)
        useIntraASMSlope = localFlagValue(opt.apskASMUseIntraBlockSlope);
    end

    if useIntraASMSlope && numAsmSym >= 2
        zGood = zBlocks(:, good);
        posGood = double(pos(good));
        adjacentProducts = zGood(2:end, :) .* conj(zGood(1:end-1, :));
        slopeRadPerSym = angle(sum(adjacentProducts(:)));

        xAll = (posGood(:).' - 1) + (0:numAsmSym-1).';
        phaseSamples = zGood .* exp(-1j * slopeRadPerSym * xAll);
        phaseAtZero = angle(sum(phaseSamples(:)));
    else
        x = double(pos(good).') - 1;      % 0-based symbol index
        y = unwrap(phases(good));
        w = mags(good);
        w = w(:) / (max(w) + eps);
        A = [x(:), ones(numel(x), 1)];
        coeff = (A' * (A .* w)) \ (A' * (y(:) .* w));
        slopeRadPerSym = coeff(1);
        phaseAtZero = coeff(2);
    end
    coarseSlopeRadPerSym = 2*pi*cfoCoarseHz/double(symbolRate);
    totalSlopeRadPerSym = coarseSlopeRadPerSym + slopeRadPerSym;
    cfoHz = cfoCoarseHz + slopeRadPerSym * double(symbolRate) / (2*pi);

    n = (0:numel(rx)-1).';
    corrected = rx .* exp(-1j*(totalSlopeRadPerSym*n + phaseAtZero));

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
        postFrames = min(numel(pos), 10);
        postPhases = zeros(postFrames, 1);
        for k = 1:postFrames
            postStart = pos(k);
            postPhases(k) = angle(sum(corrected(postStart:postStart+numAsmSym-1) .* conj(asmRef)));
        end
        fprintf('[APSK ASM fine POST] phases (deg) = %s\n', ...
            mat2str(round(rad2deg(postPhases), 1).'));
        fprintf('[APSK ASM fine POST] std = %.2f deg (near 0 is good; >10 deg means correction failed)\n', ...
            rad2deg(std(postPhases)));
        assignin('base','debug_apsk_asm_post_phases', postPhases(:));
    end

    correctedSyms = reshape(corrected, size(rxSyms));
    info.Applied = true;
    info.CFO_Hz = cfoHz;
    info.Phase_deg = rad2deg(wrapToPi(phaseAtZero));
    info.FirstPos = bestOffset;
    info.NumFrames = nnz(good);
    info.Reason = 'applied';

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
        fprintf('[APSK ASM fine] applied=%d, offset=%d, frames=%d, syms/frame=%d, corrRatio=%.3f\n', ...
            info.Applied, info.FirstPos, info.NumFrames, symsPerFrame, info.CorrRatio);
        fprintf('[APSK ASM fine] residualCFO=%.3f Hz, phase0=%.2f deg, slope=%.5g rad/sym\n', ...
            info.CFO_Hz, info.Phase_deg, totalSlopeRadPerSym);
        fprintf('[APSK ASM fine] phase first 6 deg = %s\n', ...
            mat2str(round(rad2deg(phases(1:min(6,end))), 1).'));
        assignin('base','debug_apsk_asm_positions', pos(:));
        assignin('base','debug_apsk_asm_phases', phases(:));
        assignin('base','debug_apsk_asm_phase_unwrapped', unwrap(phases(:)));
        assignin('base','debug_apsk_asm_corr_mag', mags(:));
        assignin('base','debug_apsk_asm_corrected', correctedSyms(1:min(2000,end)));
    end
end

function [bestCFO, cfos, scores] = localAPSKASMCoarseCFOScan(rxSyms, asmRefSyms, firstPos, symsPerFrame, symbolRate, cfoMax, cfoStep, numFramesUse, preferredCFO)
    rxSyms = rxSyms(:);
    asmRefSyms = asmRefSyms(:);
    bestCFO = 0;
    if nargin < 9 || isempty(preferredCFO) || ~isfinite(double(preferredCFO))
        preferredCFO = 0;
    end
    preferredCFO = double(preferredCFO);
    cfoMax = abs(double(cfoMax));
    cfoStep = abs(double(cfoStep));
    if ~isfinite(cfoMax) || cfoMax <= 0 || ~isfinite(cfoStep) || cfoStep <= 0
        cfos = 0;
        scores = 0;
        return;
    end

    cfos = -cfoMax:cfoStep:cfoMax;
    if isempty(cfos) || cfos(end) < cfoMax
        cfos = [cfos, cfoMax];
    end
    scores = zeros(size(cfos));

    numAsmSym = numel(asmRefSyms);
    maxFrames = floor((numel(rxSyms) - firstPos - numAsmSym + 1) / symsPerFrame) + 1;
    numFramesUse = min(max(1, round(numFramesUse)), maxFrames);
    if numFramesUse <= 0
        return;
    end

    for iC = 1:numel(cfos)
        rateRad = 2*pi*cfos(iC)/double(symbolRate);
        total = 0;
        for k = 1:numFramesUse
            pos = firstPos + (k-1)*symsPerFrame;
            if pos + numAsmSym - 1 > numel(rxSyms)
                break;
            end
            seg = rxSyms(pos:pos+numAsmSym-1);
            idxN = (pos-1:pos+numAsmSym-2).';
            deChirp = exp(-1j * rateRad * idxN);
            total = total + sum(seg .* deChirp .* conj(asmRefSyms));
        end
        scores(iC) = abs(total);
    end

    maxScore = max(scores);
    nearPeak = find(scores >= 0.98 * maxScore);
    if isempty(nearPeak)
        [~, iBest] = max(scores);
    else
        [~, iNear] = min(abs(cfos(nearPeak) - preferredCFO));
        iBest = nearPeak(iNear);
    end
    bestCFO = cfos(iBest);
end

function sym = localAPSKASMReferenceSymbols(bits, modStr)
    modKey = upper(string(modStr));
    if contains(modKey, '32APSK')
        bps = 5;
        radiiRatio = [2.72; 4.87];
        radius1 = sqrt(8/(1 + 3*(radiiRatio(1)^2) + 4*(radiiRatio(2)^2)));
        radii = [radius1; radiiRatio(1)*radius1; radiiRatio(2)*radius1];
    else
        bps = 4;
        radiiRatio = 3.15;
        radius1 = sqrt(4/(1 + 3*(radiiRatio^2)));
        radii = [radius1; radiiRatio*radius1];
    end
    sym = satcom.internal.ccsds.facmModulate(int8(bits(:)), bps, radii);
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
    if isfield(res,'NoisePlacement')
        fprintf(' Noise order  : %s\n', res.NoisePlacement);
    end
    if isfield(res,'NoiseMode') && strcmpi(char(res.NoiseMode), 'psd')
        fprintf(' Noise PSD    : %.2f dBm/Hz over %.3g Hz -> %.2f dBm, EqSNR=%.2f dB\n', ...
            res.NoisePSD_dBmHz, res.NoiseBandwidthHz, ...
            res.NoisePower_dBm, res.NoiseEquivalentSNR_dB);
    end
    if isfield(res,'GMSKDetectorUsed') && ...
            ~strcmpi(char(res.GMSKDetectorUsed), 'not-applicable')
        fprintf(' GMSK detector: %s\n', char(res.GMSKDetectorUsed));
    end
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
    if isfield(res,'I_LockRate') && isfinite(res.I_LockRate)
        fprintf([' I rail       : BER=%.6g, Lock=%.2f%%, FER=%.6g, ', ...
            'Err=%g/%g bits, Frames=%g/%g/%g\n'], ...
            res.I_BER, 100*res.I_LockRate, res.I_FER, ...
            res.I_BitErrors, res.I_BitsCompared, ...
            res.I_CountedFrames, res.I_MatchedFrames, res.I_DecodedFrames);
    end
    if isfield(res,'Q_LockRate') && isfinite(res.Q_LockRate)
        fprintf([' Q rail       : BER=%.6g, Lock=%.2f%%, FER=%.6g, ', ...
            'Err=%g/%g bits, Frames=%g/%g/%g\n'], ...
            res.Q_BER, 100*res.Q_LockRate, res.Q_FER, ...
            res.Q_BitErrors, res.Q_BitsCompared, ...
            res.Q_CountedFrames, res.Q_MatchedFrames, res.Q_DecodedFrames);
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
        if isfield(res,'HChannelMeta') && isfield(res.HChannelMeta,'OutOfRangeMode')
            exceedsText = 'no';
            if isfield(res.HChannelMeta,'ExceedsChannelDuration') && ...
                    logical(res.HChannelMeta.ExceedsChannelDuration)
                exceedsText = 'yes';
            end
            fprintf(' H time       : waveform=%.6g s, source=%.6g s, outOfRange=%s, exceeds=%s\n', ...
                getfieldnumeric(res.HChannelMeta, 'WaveformDuration_s', NaN), ...
                getfieldnumeric(res.HChannelMeta, 'ChannelSourceDuration_s', NaN), ...
                char(res.HChannelMeta.OutOfRangeMode), exceedsText);
        end
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

function tf = isFACMEvaluation(opt, modStr)
    isAPSK = contains(upper(string(modStr)), 'APSK');
    mode = lower(strtrim(string(opt.WaveformMode)));
    switch mode
        case "ordinarytm"
            tf = false;
        case "facm"
            tf = true;
        otherwise
            error('run_ccsds_tm_evaluation:InvalidWaveformMode', ...
                'Unsupported WaveformMode="%s". Use ordinaryTM or FACM.', ...
                char(string(opt.WaveformMode)));
    end

    if tf && ~isAPSK
        error('run_ccsds_tm_evaluation:FACMRequiresAPSK', ...
            'WaveformMode="FACM" is only valid for APSK modulation.');
    end
end

function tf = localFlagValue(raw)
    if islogical(raw) || isnumeric(raw)
        tf = logical(raw);
    else
        key = lower(strtrim(string(raw)));
        tf = any(strcmp(key, ["1","true","yes","on"]));
    end
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

    channelInput = rxWaveform;
    [channelOutput, hInfo, hState] = applyHChannelDamage(channelInput, opt, Fs);
    rxSNRForAWGN = snr_val - 10*log10(sps);
    noisePlacement = getNoisePlacementMode(opt);
    % APSK/FACM has its own frame-marker/pilot aided equalizer below.
    % Do not run the generic known-H FFT equalizer on the whole FACM waveform:
    % it can allocate a huge FFT buffer and it also disturbs FACM phase recovery.
    enableKnownHPreEq = isfield(opt,'enableKnownHPreEqualizer') && logical(opt.enableKnownHPreEqualizer);
    if noisePlacement == "afterEqualizer" && enableKnownHPreEq
        rxEqualizedClean = applyKnownChannelEqualizer(channelOutput, opt, rxSNRForAWGN, false, hState);
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise(rxEqualizedClean, opt, Fs, rxSNRForAWGN, rxEqualizedClean);
        rxWaveform = rxNoisyWaveform;
    else
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise(channelOutput, opt, Fs, rxSNRForAWGN, channelInput);
        rxWaveform = rxNoisyWaveform;
        if enableKnownHPreEq
            rxWaveform = applyKnownChannelEqualizer(rxWaveform, opt, noiseInfo.EquivalentSNR_dB, false, hState);
        end
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
    res.NoisePlacement = char(noisePlacement);
    res.NoiseMode = char(noiseInfo.Mode);
    if isfinite(noiseInfo.PSD_dBmHz)
        res.NoisePSD_dBmHz = noiseInfo.PSD_dBmHz;
        res.NoiseBandwidthHz = noiseInfo.BandwidthHz;
        res.NoisePower_dBm = noiseInfo.NoisePower_dBm;
        res.NoiseEquivalentSNR_dB = noiseInfo.EquivalentSNR_dB;
        res.NoiseReferenceLevel_dBm = noiseInfo.ReferenceLevel_dBm;
    end
    res.cfo_in = cfo_val;
    res.phase_in = phase_deg;
    res.delay_in = delay_val;
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.inputLevelDbm = getInputLevelDbm(opt, 0);
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
    if isfield(hInfo, 'Meta')
        res.HChannelMeta = hInfo.Meta;
    end

    ctx.txWaveform = txWaveform;
    ctx.channelInput = channelInput;
    ctx.channelOutput = channelOutput;
    ctx.rxNoisyWaveform = rxNoisyWaveform;
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
                if isFACMPostPilotLSEnabled(opt)
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
                if isFACMPostPilotLSEnabled(opt)
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

function tf = isFACMPostPilotLSEnabled(opt)
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

function args = appendASMArgs(args, opt)
    [asmLength, hasLength] = localASMOptionLength(opt);
    [asmHex, hasHex] = localASMOptionHex(opt);
    if hasLength
        args = [args, {'ASMLength', asmLength}];
    end
    if hasHex
        args = [args, {'ASMHex', asmHex}];
    end
end

function tf = localHasASMOption(opt)
    [~, hasLength] = localASMOptionLength(opt);
    [~, hasHex] = localASMOptionHex(opt);
    tf = hasLength || hasHex;
end

function [asmLength, found] = localASMOptionLength(opt)
    asmLength = [];
    found = false;
    names = {'ASMLength','asmLength','frameASMLength','FrameASMLength', ...
        'frame_asm_len','frameASMLen','syncWordLength','SyncWordLength'};
    for iName = 1:numel(names)
        name = names{iName};
        if ~isfield(opt, name) || isempty(opt.(name))
            continue;
        end
        raw = opt.(name);
        if ischar(raw) || isstring(raw)
            txt = strtrim(string(raw));
            if strlength(txt) == 0
                continue;
            end
            raw = str2double(txt);
        end
        asmLength = double(raw);
        if ~isscalar(asmLength) || ~isfinite(asmLength) || asmLength < 8 || ...
                asmLength > 64 || mod(asmLength,8) ~= 0
            error('run_ccsds_tm_evaluation:InvalidASMLength', ...
                'ASMLength must be one of 8,16,24,32,40,48,56,64 bits.');
        end
        found = true;
        return;
    end
end

function [asmHex, found] = localASMOptionHex(opt)
    asmHex = '';
    found = false;
    names = {'ASMHex','asmHex','frameASMHex','FrameASMHex', ...
        'frame_asm_hex','syncWordHex','SyncWordHex'};
    for iName = 1:numel(names)
        name = names{iName};
        if ~isfield(opt, name) || isempty(opt.(name))
            continue;
        end
        asmHex = localNormalizeASMHexForEval(opt.(name));
        if isempty(asmHex)
            continue;
        end
        found = true;
        return;
    end
end

function bits = localBuildCustomASMForEval(asmLength, hasLength, asmHex, hasHex)
    if ~hasLength
        if hasHex
            asmLength = 4*numel(asmHex);
        else
            asmLength = 32;
        end
    end
    if isempty(asmLength) || ~isscalar(asmLength) || ~isfinite(asmLength) || ...
            asmLength < 8 || asmLength > 64 || mod(asmLength,8) ~= 0
        error('run_ccsds_tm_evaluation:InvalidASMLength', ...
            'ASMLength must be one of 8,16,24,32,40,48,56,64 bits.');
    end

    if hasHex
        if 4*numel(asmHex) ~= asmLength
            error('run_ccsds_tm_evaluation:ASMHexLengthMismatch', ...
                'ASMHex must contain exactly ASMLength/4 hexadecimal digits.');
        end
        bits = localHexToBitsForEval(asmHex);
    else
        if asmLength ~= 32
            error('run_ccsds_tm_evaluation:ASMHexRequired', ...
                'Custom ASM lengths other than 32 bits require an explicit ASMHex value.');
        end
        bits = localDefaultTMASM();
    end
end

function bits = localDefaultTMASM()
    bits = int8([0;0;0;1;1;0;1;0;1;1;0;0;1;1;1;1;1;1;1;1;1;1;0;0;0;0;0;1;1;1;0;1]);
end

function tf = localIsDefaultTMASM(bits)
    defaultBits = localDefaultTMASM();
    tf = numel(bits) == numel(defaultBits) && all(int8(bits(:) ~= 0) == defaultBits);
end

function asmHex = localNormalizeASMHexForEval(value)
    if isempty(value)
        asmHex = '';
        return;
    end
    if isstring(value)
        value = char(value);
    elseif ~ischar(value)
        error('run_ccsds_tm_evaluation:InvalidASMHex', ...
            'ASMHex must be a hexadecimal character vector or string scalar.');
    end
    asmHex = upper(strtrim(value));
    if startsWith(asmHex, '0X')
        asmHex = asmHex(3:end);
    end
    asmHex(asmHex == ' ') = [];
    asmHex(asmHex == '_') = [];
    if isempty(asmHex)
        return;
    end
    valid = (asmHex >= '0' & asmHex <= '9') | (asmHex >= 'A' & asmHex <= 'F');
    if ~all(valid)
        error('run_ccsds_tm_evaluation:InvalidASMHex', ...
            'ASMHex must contain hexadecimal digits only.');
    end
    if numel(asmHex) > 16
        error('run_ccsds_tm_evaluation:InvalidASMHex', ...
            'ASMHex supports at most 16 hexadecimal digits (64 bits).');
    end
end

function bits = localHexToBitsForEval(hexText)
    bits = zeros(4*numel(hexText), 1, 'int8');
    for k = 1:numel(hexText)
        val = uint8(hex2dec(hexText(k)));
        idx = (k-1)*4 + (1:4);
        bits(idx) = int8(bitget(val, 4:-1:1).');
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
function [iStream, qStream, predecoderStats] = ...
        localBitDeinterleaveIQ(x, modulation, debugEnabled, iqPhase)
    if nargin < 2 || isempty(modulation)
        modulation = '';
    end
    if nargin < 3
        debugEnabled = false;
    end
    if nargin < 4 || isempty(iqPhase)
        iqPhase = NaN;
    end
    predecoderStats = localEmptySplitPredecoderStats();

    x = x(:);
    [bitsPerSymbol, fpgaBlockBits] = localSplitFPGAPackingShape(modulation);
    if debugEnabled
        rxPackedHard = int8(real(x) > 0);
        fprintf('[SplitPath RX unpack input] mod=%s, fpgaBlockBits=%d, bitsPerSymbol=%d, blockReverse=off, packedHardFirst64=%s\n', ...
            char(modulation), fpgaBlockBits, bitsPerSymbol, localSoftBitVectorString(x, 64));
        assignin('base', 'debug_split_rx_packed_soft', x);
        assignin('base', 'debug_split_rx_packed_hardbits', rxPackedHard);
        localPrintSplitDebugMatch('TX packed output vs RX unpack input', ...
            'debug_split_tx_packed_bits', rxPackedHard);
    end

    % Phase-1 split debug: do not reverse 96/160-bit mapper blocks here.
    % Try the possible I/Q bit parity phase in tryOneRotation before
    % deinterleaving the serial stream into rails.
    % if fpgaBlockBits > 0
    %     x = localReverseSymbolGroupsInBlocks(x, bitsPerSymbol, fpgaBlockBits);
    % end

    if debugEnabled
        rxUnpackedHard = int8(real(x) > 0);
        fprintf('[SplitPath RX unpack output] mod=%s, iqInterleavedHardFirst64=%s\n', ...
            char(modulation), localSoftBitVectorString(x, 64));
        assignin('base', 'debug_split_rx_unpack_output_soft', x);
        assignin('base', 'debug_split_rx_unpack_output_hardbits', rxUnpackedHard);
        localPrintSplitDebugMatch('TX pack input vs RX unpack output', ...
            'debug_split_tx_pack_input_bits', rxUnpackedHard);
    end

    [iStream, qStream, droppedTail] = ...
        tm_data_path_bit_deinterleave(x, 'drop');
    if debugEnabled && droppedTail
        fprintf('[SplitPath RX deinterleave] dropping 1 tail soft bit to keep I/Q pairs aligned.\n');
    end
    if debugEnabled
        predecoderStats = localMeasureSplitPredecoderRails( ...
            iStream, qStream);
        fprintf(['[SplitPath predecoder candidate] iqPhase=%g | ', ...
            'I: hardBER=%.6g offset=%+g polarity=%+g Err=%g/%g | ', ...
            'Q: hardBER=%.6g offset=%+g polarity=%+g Err=%g/%g\n'], ...
            iqPhase, ...
            predecoderStats.I_PredecoderBER, ...
            predecoderStats.I_PredecoderOffset, ...
            predecoderStats.I_PredecoderPolarity, ...
            predecoderStats.I_PredecoderBitErrors, ...
            predecoderStats.I_PredecoderBitsCompared, ...
            predecoderStats.Q_PredecoderBER, ...
            predecoderStats.Q_PredecoderOffset, ...
            predecoderStats.Q_PredecoderPolarity, ...
            predecoderStats.Q_PredecoderBitErrors, ...
            predecoderStats.Q_PredecoderBitsCompared);
        localPrintSplitPredecoderCrossRail(iStream, qStream, iqPhase);
    end
end

function stats = localEmptySplitPredecoderStats()
    stats = struct( ...
        'I_PredecoderBER',NaN, ...
        'I_PredecoderOffset',NaN, ...
        'I_PredecoderPolarity',NaN, ...
        'I_PredecoderBitErrors',NaN, ...
        'I_PredecoderBitsCompared',NaN, ...
        'Q_PredecoderBER',NaN, ...
        'Q_PredecoderOffset',NaN, ...
        'Q_PredecoderPolarity',NaN, ...
        'Q_PredecoderBitErrors',NaN, ...
        'Q_PredecoderBitsCompared',NaN);
end

function stats = localMeasureSplitPredecoderRails(rxI, rxQ)
    stats = localEmptySplitPredecoderStats();
    stats = localMeasureOneSplitPredecoderRail( ...
        stats, 'I', 'debug_split_tx_encoded_i_bits', rxI);
    stats = localMeasureOneSplitPredecoderRail( ...
        stats, 'Q', 'debug_split_tx_encoded_q_bits', rxQ);
end

function localPrintSplitPredecoderCrossRail(rxI, rxQ, iqPhase)
% Debug-only oracle: show whether a parity hypothesis preserves I/Q labels
% or merely swaps two otherwise valid rails.  This is never used for
% candidate selection.
    if ~evalin('base', ...
            'exist(''debug_split_tx_encoded_i_bits'',''var'') && exist(''debug_split_tx_encoded_q_bits'',''var'')')
        return;
    end
    txI = int8(evalin('base', 'debug_split_tx_encoded_i_bits') ~= 0);
    txQ = int8(evalin('base', 'debug_split_tx_encoded_q_bits') ~= 0);
    rxIHard = int8(real(rxI(:)) > 0);
    rxQHard = int8(real(rxQ(:)) > 0);
    [berIQ, offsetIQ, polarityIQ] = ...
        localBestSignedHardBitAlignment(txQ(:), rxIHard, 256, 2048);
    [berQI, offsetQI, polarityQI] = ...
        localBestSignedHardBitAlignment(txI(:), rxQHard, 256, 2048);
    fprintf(['[SplitPath predecoder cross-rail] iqPhase=%g | ', ...
        'RX-I vs TX-Q: BER=%.6g offset=%+g polarity=%+g | ', ...
        'RX-Q vs TX-I: BER=%.6g offset=%+g polarity=%+g\n'], ...
        iqPhase, berIQ, offsetIQ, polarityIQ, ...
        berQI, offsetQI, polarityQI);
end

function stats = localMeasureOneSplitPredecoderRail( ...
        stats, railName, txVarName, rxSoft)
    if ~evalin('base', sprintf('exist(''%s'',''var'')', txVarName))
        return;
    end

    txBits = evalin('base', txVarName);
    txBits = int8(txBits(:) ~= 0);
    rxHard = int8(real(rxSoft(:)) > 0);
    [ber, offset, polarity, errors, bitsCompared] = ...
        localBestSignedHardBitAlignment(txBits, rxHard, 256, 2048);

    prefix = upper(char(string(railName)));
    stats.([prefix '_PredecoderBER']) = ber;
    stats.([prefix '_PredecoderOffset']) = offset;
    stats.([prefix '_PredecoderPolarity']) = polarity;
    stats.([prefix '_PredecoderBitErrors']) = errors;
    stats.([prefix '_PredecoderBitsCompared']) = bitsCompared;
end

function [ber, bestOffset, bestPolarity, errors, bitsCompared] = ...
        localBestSignedHardBitAlignment(txBits, rxBits, maxOffset, probeLength)
    txBits = int8(txBits(:) ~= 0);
    rxBits = int8(rxBits(:) ~= 0);
    ber = NaN;
    bestOffset = NaN;
    bestPolarity = NaN;
    errors = NaN;
    bitsCompared = 0;
    if isempty(txBits) || isempty(rxBits)
        return;
    end

    maxOffset = min([round(double(maxOffset)), ...
        numel(txBits)-1, numel(rxBits)-1]);
    if maxOffset < 0
        return;
    end
    probeLength = max(1, round(double(probeLength)));

    bestProbeBER = inf;
    bestAbsOffset = inf;
    for offset = -maxOffset:maxOffset
        [txStart, rxStart, overlap] = ...
            localSignedAlignmentWindow(numel(txBits), numel(rxBits), offset);
        nProbe = min(probeLength, overlap);
        if nProbe < 1
            continue;
        end

        txProbe = txBits(txStart:txStart+nProbe-1);
        rxProbe = rxBits(rxStart:rxStart+nProbe-1);
        directErrors = nnz(txProbe ~= rxProbe);
        inverseErrors = nProbe - directErrors;
        if inverseErrors < directErrors
            probeErrors = inverseErrors;
            polarity = -1;
        else
            probeErrors = directErrors;
            polarity = 1;
        end
        probeBER = probeErrors / nProbe;

        if probeBER < bestProbeBER || ...
                (abs(probeBER-bestProbeBER) <= eps && ...
                 abs(offset) < bestAbsOffset)
            bestProbeBER = probeBER;
            bestOffset = offset;
            bestPolarity = polarity;
            bestAbsOffset = abs(offset);
        end
    end

    if ~isfinite(bestOffset)
        return;
    end
    [txStart, rxStart, bitsCompared] = ...
        localSignedAlignmentWindow(numel(txBits), numel(rxBits), bestOffset);
    txAligned = txBits(txStart:txStart+bitsCompared-1);
    rxAligned = rxBits(rxStart:rxStart+bitsCompared-1);
    if bestPolarity < 0
        rxAligned = int8(~logical(rxAligned));
    end
    errors = nnz(txAligned ~= rxAligned);
    ber = errors / bitsCompared;
end

function [txStart, rxStart, overlap] = ...
        localSignedAlignmentWindow(txLength, rxLength, offset)
    if offset >= 0
        txStart = 1;
        rxStart = 1 + offset;
    else
        txStart = 1 - offset;
        rxStart = 1;
    end
    overlap = min(txLength-txStart+1, rxLength-rxStart+1);
end

function localPrintSplitDebugMatch(label, txVarName, rxHard)
    if ~evalin('base', sprintf('exist(''%s'',''var'')', txVarName))
        return;
    end

    txBits = evalin('base', txVarName);
    txBits = int8(txBits(:) ~= 0);
    rxHard = int8(rxHard(:) ~= 0);

    probeLen = min([256, numel(txBits), numel(rxHard)]);
    if probeLen <= 0
        return;
    end

    maxOffset = min(4096, numel(rxHard) - probeLen);
    if maxOffset < 0
        return;
    end

    txProbe = txBits(1:probeLen);
    bestErr = probeLen + 1;
    bestOffset = 0;
    for offset = 0:maxOffset
        rxProbe = rxHard(offset + (1:probeLen));
        errNow = nnz(rxProbe ~= txProbe);
        if errNow < bestErr
            bestErr = errNow;
            bestOffset = offset;
            if bestErr == 0
                break;
            end
        end
    end

    fprintf('[SplitPath DEBUG match] %s: bestOffset=%d bit, err=%d/%d\n', ...
        label, bestOffset, bestErr, probeLen);
end

function [bitsPerSymbol, fpgaBlockBits] = localSplitFPGAPackingShape(modulation)
    switch char(modulation)
        case '8PSK'
            bitsPerSymbol = 3;
            fpgaBlockBits = 96;   % 3 x 32-bit interleaved words -> 4 x 24-bit mapper words
        case '32QAM'
            bitsPerSymbol = 5;
            fpgaBlockBits = 160;  % 5 x 32-bit interleaved words -> 4 x 40-bit mapper words
        otherwise
            bitsPerSymbol = 0;
            fpgaBlockBits = 0;
    end
end

function out = localReverseSymbolGroupsInBlocks(x, bitsPerSymbol, blockBits)
    out = x(:);
    if bitsPerSymbol <= 0 || blockBits <= 0 || mod(blockBits, bitsPerSymbol) ~= 0
        return;
    end

    numFullBlocks = floor(numel(out) / blockBits);
    if numFullBlocks <= 0
        return;
    end

    symbolsPerBlock = blockBits / bitsPerSymbol;
    for iBlock = 1:numFullBlocks
        idx = (iBlock-1)*blockBits + (1:blockBits);
        symbolGroups = reshape(out(idx), bitsPerSymbol, symbolsPerBlock);
        out(idx) = reshape(symbolGroups(:, end:-1:1), [], 1);
    end
end

function txt = localSoftBitVectorString(values, maxLen)
    if nargin < 2
        maxLen = 64;
    end
    values = values(:);
    values = values(1:min(maxLen, numel(values)));
    if isempty(values)
        txt = '';
        return;
    end
    hardBits = int8(real(values) > 0);
    txt = char('0' + double(hardBits(:).'));
end

function [decodedI, decodedQ, decodedBits] = localDecodeSplitRails( ...
        demodI, demodQ, bitsPerFrame, decArgsI, decArgsQ)
    if nargin < 5 || isempty(decArgsQ)
        decArgsQ = decArgsI;
    end
    decoderI = HelperCCSDSTMDecoder(decArgsI{:});
    decoderQ = HelperCCSDSTMDecoder(decArgsQ{:});
    decodedI = decoderI(demodI);
    decodedQ = decoderQ(demodQ);
    decodedBits = tm_data_path_frame_interleave( ...
        int8(decodedI), int8(decodedQ), bitsPerFrame, 'truncate');
end

function offset = localParabolicSpectrumPeakOffset(powerSpectrum, peakIndex)
%LOCALPARABOLICSPECTRUMPEAKOFFSET Estimate a spectral peak between bins.
% Fit a parabola to the log-power values immediately around the integer
% maximum.  The result is bounded to the current FFT bin.
    offset = 0;
    if peakIndex <= 1 || peakIndex >= numel(powerSpectrum)
        return;
    end

    y = log(max(double(powerSpectrum(peakIndex + (-1:1))), realmin('double')));
    denominator = y(1) - 2*y(2) + y(3);
    if ~all(isfinite(y)) || ~isfinite(denominator) || denominator >= 0 || ...
            abs(denominator) <= eps(max(abs(y)))
        return;
    end

    offset = 0.5 * (y(1) - y(3)) / denominator;
    offset = max(-0.5, min(0.5, offset));
end
