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

%  p = struct( ...
%     'modType','GMSK', ...
%     'DataPathMode','single', ...
%     'symbolRate',10e6, ...
%     'sps',8, ...
%     'snr',50, ...
%     'cfo',0, ...
%     'phaseOffset',0, ...
%     'delay',0, ...
%     'channelCoding','TPC', ...
%     'TPCCodeRate','2/3', ...
%     'channelFilePath','E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat', ...
%     'TPCBlocksPerTF',1, ...
%     'TPCInterleaver','auto', ...
%     'hasASM',true, ...
%     'RandomizerEnabled',false, ...
%     'RandomizerFECPosition','afterEncoding', ...
%     'GMSKDetectionMode','official-viterbi-frame-reset', ...
%     'enableHChannel',true, ...
%     'berWarmUpFrames',8, ...
%     'berFrames',16, ...
%     'showFigures',true);
%
% [M,~] = run_ccsds_tm_evaluation(p);
%
%   2) 用前端的 JSON 直接粘进来调（验一致性）
%   m = run_ccsds_tm_evaluation('{"modType":"QPSK","symbolRate":1e6,"sps":8,"snr":12,"cfo":0,"phaseOffset":0,"channelCoding":"none","RolloffFactor":0.35}');
%

tStart = tic;

[opt, outputMode] = parseEvaluationEntryInputs(varargin{:});
imagePaths = '';

try   % ===== 顶层 try/catch: 任何崩溃都返回 success=false 给前端 =====
    % ======== Single point simulation ========
%     res：内部完整指标
%     ctx：内部大数据
%     frontResult：对外稳定接口
    [res, ctx] = runOneShot(opt);
    res = attachResidualMetrics(res, ctx);

    showFigures = false; % 图像开关
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

    % ======== Frontend plot source data ========
    % Remote mode renders these data to three PNG files.  The arrays are
    % only copied into the public result when includeRawData=true.
    includeRawData = getLogicalField(opt, 'includeRawData', false);
    fe = buildFrontendArrays(ctx, res, includeRawData);
    if getLogicalField(opt, 'remoteMode', false)
        imagePaths = createRemoteResultFigures(ctx, fe, res, opt);
    end

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
    if isfield(res,'TMDataSource'), frontResult.TMDataSource = res.TMDataSource; end
    if isfield(res,'TMDataSourceI'), frontResult.TMDataSourceI = res.TMDataSourceI; end
    if isfield(res,'TMDataSourceQ'), frontResult.TMDataSourceQ = res.TMDataSourceQ; end
    frontResult.BER          = res.BER;
    frontResult.ber          = res.BER;     % 兼容老 main 字段(小写)
    frontResult.EVM_post_pct = res.EVM_post_pct;
    frontResult.EVM_pre_pct  = res.EVM_pre_pct;
    frontResult.MER_dB       = res.MER_dB;
    frontResult.SNR_est_dB   = res.SNR_est_dB;
    residualGeometryFields = { ...
        'EVMRadial_pct','EVMTangential_pct', ...
        'ResidualPhaseRMS_deg','ResidualRadiusRMS_dB'};
    for iResidualGeometry = 1:numel(residualGeometryFields)
        geometryField = residualGeometryFields{iResidualGeometry};
        if isfield(res,geometryField)
            frontResult.(geometryField) = res.(geometryField);
        end
    end
    if isfield(res,'QualityMetricType')
        frontResult.QualityMetricType = res.QualityMetricType;
    end
    frontResult.PAPR_dB      = res.PAPR_dB;
    frontResult.LockRate     = res.LockRate;
    if isfield(res,'FER'), frontResult.FER = res.FER; end
    if isfield(res,'FrameErrorRate'), frontResult.FrameErrorRate = res.FrameErrorRate; end
    if isfield(res,'FrameErrors'), frontResult.FrameErrors = res.FrameErrors; end
    if isfield(res,'CountedFrames'), frontResult.CountedFrames = res.CountedFrames; end
    if isfield(res,'MatchedFrames'), frontResult.MatchedFrames = res.MatchedFrames; end
    if isfield(res,'DecodedFrames'), frontResult.DecodedFrames = res.DecodedFrames; end
    if isfield(res,'GMSKDetectorUsed'), frontResult.GMSKDetectorUsed = res.GMSKDetectorUsed; end
    gmskPLLFields = { ...
        'GMSKSecondOrderPLLApplied','GMSKSecondOrderPLLReason', ...
        'GMSKSecondOrderPLLLocked','GMSKSecondOrderPLLFinalMode', ...
        'GMSKSecondOrderPLLFinalFrequency_Hz', ...
        'GMSKSecondOrderPLLFrequencyMin_Hz', ...
        'GMSKSecondOrderPLLFrequencyMax_Hz', ...
        'GMSKSecondOrderPLLUpdateAcceptanceRate', ...
        'GMSKSecondOrderPLLFadeHoldSamples', ...
        'GMSKSecondOrderPLLExternalHoldApplied', ...
        'GMSKSecondOrderPLLExternalHoldSamples', ...
        'GMSKSecondOrderPLLMeanAbsPhaseError'};
    for iGMSKPLL = 1:numel(gmskPLLFields)
        gmskPLLField = gmskPLLFields{iGMSKPLL};
        if isfield(res,gmskPLLField)
            frontResult.(gmskPLLField) = res.(gmskPLLField);
        end
    end
    gmskTrackerFields = { ...
        'GMSKResidualTrackerApplied','GMSKResidualWindowCount', ...
        'GMSKResidualAcceptedWindows','GMSKResidualHoldWindows', ...
        'GMSKResidualExternalHoldApplied', ...
        'GMSKResidualExternalHoldSamples', ...
        'GMSKResidualExternalHoldRejectedWindows', ...
        'GMSKResidualWindowSymbols','GMSKResidualHopSymbols', ...
        'GMSKResidualMin_Hz','GMSKResidualMedian_Hz', ...
        'GMSKResidualMax_Hz','GMSKResidualRMS_Hz', ...
        'GMSKResidualFinal_Hz','GMSKResidualMedianConfidence_dB'};
    for iGMSKTracker = 1:numel(gmskTrackerFields)
        trackerField = gmskTrackerFields{iGMSKTracker};
        if isfield(res,trackerField)
            frontResult.(trackerField) = res.(trackerField);
        end
    end
    if isfield(res,'GMSKResidualRawAcceptedRate')
        frontResult.GMSKResidualRawAcceptedRate = res.GMSKResidualRawAcceptedRate;
    end
    candidateTrackerFields = { ...
        'GMSKResidualCandidateFiniteRate','GMSKResidualCandidateMin_Hz', ...
        'GMSKResidualCandidateMedian_Hz','GMSKResidualCandidateMax_Hz', ...
        'GMSKResidualCandidateRMS_Hz','GMSKResidualNonfiniteWindows', ...
        'GMSKResidualConfidenceRejectedWindows', ...
        'GMSKResidualRangeRejectedWindows'};
    for iCandidateTracker = 1:numel(candidateTrackerFields)
        trackerField = candidateTrackerFields{iCandidateTracker};
        if isfield(res,trackerField)
            frontResult.(trackerField) = res.(trackerField);
        end
    end
    if isfield(res,'GMSKResidualRawMin_Hz')
        frontResult.GMSKResidualRawMin_Hz = res.GMSKResidualRawMin_Hz;
        frontResult.GMSKResidualRawMedian_Hz = res.GMSKResidualRawMedian_Hz;
        frontResult.GMSKResidualRawMax_Hz = res.GMSKResidualRawMax_Hz;
        frontResult.GMSKResidualRawRMS_Hz = res.GMSKResidualRawRMS_Hz;
    end
    if isfield(res,'GMSKResidualJumpMax_Hz')
        frontResult.GMSKResidualJumpMax_Hz = res.GMSKResidualJumpMax_Hz;
        frontResult.GMSKResidualJumpRMS_Hz = res.GMSKResidualJumpRMS_Hz;
        frontResult.GMSKResidualPhaseCorrectionEnd_deg = ...
            res.GMSKResidualPhaseCorrectionEnd_deg;
    end
    if isfield(res,'GMSKResidualWindowDebug')
        frontResult.GMSKResidualWindowDebug = res.GMSKResidualWindowDebug;
    end
    if isfield(res,'AcquisitionFrames'), frontResult.AcquisitionFrames = res.AcquisitionFrames; end
    if isfield(res,'AcquisitionTime_s'), frontResult.AcquisitionTime_s = res.AcquisitionTime_s; end
    qamBPSFadeBERFields = localQAMBPSFadeBERResultFields();
    for iQAMBPSFadeBER = 1:numel(qamBPSFadeBERFields)
        fadeBERField = qamBPSFadeBERFields{iQAMBPSFadeBER};
        if isfield(res,fadeBERField)
            frontResult.(fadeBERField) = res.(fadeBERField);
        end
    end
    asmFramePhaseFields = { ...
        'ASMFramePhaseCorrectionEnabled', ...
        'ASMFramePhaseCorrectionApplied', ...
        'ASMFramePhaseCorrectionReason', ...
        'ASMFramePhaseCorrectionFrames', ...
        'ASMFramePhaseCorrectionReliableFrames', ...
        'ASMFramePhaseCorrectionHoldoverFrames', ...
        'ASMFramePhaseCorrectionUncorrectedPrefixFrames', ...
        'ASMFramePhaseCycleSlipsBefore', ...
        'ASMFramePhaseCycleSlipsAfter'};
    for iASMFramePhase = 1:numel(asmFramePhaseFields)
        phaseField = asmFramePhaseFields{iASMFramePhase};
        if isfield(res,phaseField)
            frontResult.(phaseField) = res.(phaseField);
        end
    end
    railMetricFields = localSplitRailMetricFields();
    for iRailMetric = 1:numel(railMetricFields)
        railMetricName = railMetricFields{iRailMetric};
        if isfield(res, railMetricName)
            frontResult.(railMetricName) = res.(railMetricName);
        end
    end
    predecoderMetricFields = localPredecoderResultFields();
    for iPredecoderMetric = 1:numel(predecoderMetricFields)
        predecoderMetricName = predecoderMetricFields{iPredecoderMetric};
        if isfield(res, predecoderMetricName)
            frontResult.(predecoderMetricName) = res.(predecoderMetricName);
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
    pilotRobustnessFields = { ...
        'TMAPSKPilotFadeFraction','TMAPSKPilotDataFadeSymbols', ...
        'TMAPSKPilotDataFadeFraction','TMAPSKPilotMaxAppliedGain_dB', ...
        'TMAPSKPilotRegularization','TMAPSKPilotNoiseVariance'};
    for iPilotRobustness = 1:numel(pilotRobustnessFields)
        pilotField = pilotRobustnessFields{iPilotRobustness};
        if isfield(res,pilotField)
            frontResult.(pilotField) = res.(pilotField);
        end
    end
    pilotlessAPSKFields = { ...
        'APSKReceiverMode','PilotlessAPSKApplied','PilotlessAPSKReason', ...
        'PilotlessAPSKFourthPowerCFO_Hz', ...
        'PilotlessAPSKFourthPowerConfidence_dB', ...
        'PilotlessAPSKCoarsePowerOrder', ...
        'PilotlessAPSKNDAResidualCFO_Hz', ...
        'PilotlessAPSKNDAResidualCFOApplied', ...
        'PilotlessAPSKMthPowerPhaseTrackerApplied', ...
        'PilotlessAPSKMthPowerPhaseFinalCorrection_deg', ...
        'PilotlessAPSKMthPowerPhaseMedianConfidence', ...
        'PilotlessAPSKBlindPhaseSearchApplied', ...
        'PilotlessAPSKBlindPhaseSearchReliableRate', ...
        'PilotlessAPSKBlindPhaseSearchMedianMetric', ...
        'PilotlessAPSKBlindPhaseSearchFinalCorrection_deg', ...
        'PilotlessAPSKSharedReliabilityApplied', ...
        'PilotlessAPSKSharedReliabilityHoldSymbols', ...
        'PilotlessAPSKSharedReliabilityHoldFraction', ...
        'PilotlessAPSKPreDDGainApplied', ...
        'PilotlessAPSKPreDDGainAcceptanceRate', ...
        'PilotlessAPSKPreDDGainHoldFraction', ...
        'PilotlessAPSKPreDDGainFadeFraction', ...
        'PilotlessAPSKPreDDGainFinalMagnitude_dB', ...
        'PilotlessAPSKRingNormalizerApplied', ...
        'PilotlessAPSKRingEstimatorMode', ...
        'PilotlessAPSKRingAcceptanceRate', ...
        'PilotlessAPSKRingHoldFraction', ...
        'PilotlessAPSKRingFadeFraction', ...
        'PilotlessAPSKRingFinalAmplitude_dB', ...
        'PilotlessAPSKCarrierAcceptanceRate', ...
        'PilotlessAPSKCarrierHoldFraction', ...
        'PilotlessAPSKCarrierFadeFraction', ...
        'PilotlessAPSKCarrierPhaseErrorRMS_deg', ...
        'PilotlessAPSKResidualFrequency_Hz', ...
        'PilotlessAPSKComplexGainEnabled', ...
        'PilotlessAPSKGainAcceptanceRate', ...
        'PilotlessAPSKGainHoldFraction', ...
        'PilotlessAPSKGainFadeFraction', ...
        'PilotlessAPSKFinalGainMagnitude_dB', ...
        'PilotlessAPSKFinalGainPhase_deg', ...
        'PilotlessAPSKGainRegularization', ...
        'PilotlessAPSKGainMaxInverseGainDB', ...
        'PilotlessAPSKGainInverseMaxObserved_dB'};
    for iPilotlessAPSK = 1:numel(pilotlessAPSKFields)
        pilotlessField = pilotlessAPSKFields{iPilotlessAPSK};
        if isfield(res,pilotlessField)
            frontResult.(pilotlessField) = res.(pilotlessField);
        end
    end
    qamFrontEndFields = { ...
        'QAMBlindPhaseSearchApplied', ...
        'QAMBlindPhaseSearchReliableRate', ...
        'QAMBlindPhaseSearchMedianMetric', ...
        'QAMBlindPhaseSearchFinalCorrection_deg', ...
        'QAMBlindPhaseSearchFadeHoldBlocks', ...
        'QAMBlindPhaseSearchFadeEvents', ...
        'QAMBlindPhaseSearchFadeRecoveries', ...
        'QAMBlindPhaseSearchReacquisitions', ...
        'QAMBlindPhaseSearchInitialFrequencyRadPerSymbol', ...
        'QAMPowerGainApplied', ...
        'QAMPowerGainAcceptanceRate', ...
        'QAMPowerGainRegularization', ...
        'QAMPowerGainMaxInverseGainDB', ...
        'QAMPowerGainInverseMaxObserved_dB'};
    for iQAMFrontEnd = 1:numel(qamFrontEndFields)
        qamField = qamFrontEndFields{iQAMFrontEnd};
        if isfield(res,qamField)
            frontResult.(qamField) = res.(qamField);
        end
    end
    if isfield(res,'HasASM'), frontResult.HasASM = res.HasASM; end
    if isfield(res,'ASMLength'), frontResult.ASMLength = res.ASMLength; end
    if isfield(res,'ASMHex'), frontResult.ASMHex = res.ASMHex; end
    if isfield(res,'RandomizerEnabled'), frontResult.RandomizerEnabled = res.RandomizerEnabled; end
    if isfield(res,'RandomizerFECPosition'), frontResult.RandomizerFECPosition = res.RandomizerFECPosition; end
    if isfield(res,'DataPathMode'), frontResult.DataPathMode = res.DataPathMode; end
    if isfield(res,'ConvolutionalG1G2Mode')
        frontResult.ConvolutionalG1G2Mode = res.ConvolutionalG1G2Mode;
    end
    if isfield(res,'CarrierCaptureRangeConfigured_Hz')
        frontResult.CarrierCaptureRangeConfigured_Hz = ...
            res.CarrierCaptureRangeConfigured_Hz;
    end
    crcResultFields = {'HasFECF','CRCType','CRCCheckedFrames', ...
        'CRCErrorFrames','CRCErrorRate','DemodNoiseVariance'};
    for iCRCResult = 1:numel(crcResultFields)
        crcField = crcResultFields{iCRCResult};
        if isfield(res,crcField)
            frontResult.(crcField) = res.(crcField);
        end
    end
    adaptiveResultFields = { ...
        'UQPSKPostCarrierEQEnabled', ...
        'AdaptiveEqualizerEnabled','AdaptiveEqualizerMode', ...
        'AdaptiveEqualizerReason','AdaptiveEqualizerTaps', ...
        'AdaptiveEqualizerCMASymbols','AdaptiveEqualizerDDPasses', ...
        'AdaptiveEqualizerCMAStep','AdaptiveEqualizerDDStep', ...
        'AdaptiveEqualizerCMAR2','AdaptiveEqualizerDecisionGate', ...
        'AdaptiveEqualizerBlindCostMode', ...
        'AdaptiveEqualizerPhaseRotation_deg', ...
        'AdaptiveEqualizerPhaseStructureScore', ...
        'AdaptiveEqualizerCMASwitchMSE', ...
        'AdaptiveEqualizerCMAConfidenceRate', ...
        'AdaptiveEqualizerCMAQualified', ...
        'AdaptiveEqualizerCMAMSE','AdaptiveEqualizerDDMSE', ...
        'AdaptiveEqualizerAcceptanceRate', ...
        'AdaptiveEqualizerRejectedDecisions', ...
        'AdaptiveEqualizerFinalTapNorm', ...
        'AdaptiveEqualizerInputStructureMSE', ...
        'AdaptiveEqualizerOutputStructureMSE', ...
        'AdaptiveEqualizerQualityImprovement', ...
        'AdaptiveEqualizerStructure', ...
        'AdaptiveEqualizerScalarMode', ...
        'AdaptiveEqualizerSideTapEnergyRatio', ...
        'AdaptiveEqualizerDDWindowSymbols', ...
        'AdaptiveEqualizerDDMinWindowAcceptance', ...
        'AdaptiveEqualizerDDWindowCount', ...
        'AdaptiveEqualizerDDGoodWindows', ...
        'AdaptiveEqualizerDDHoldWindows', ...
        'AdaptiveEqualizerDDFadeHoldWindows', ...
        'AdaptiveEqualizerDDFadeEnterEvents', ...
        'AdaptiveEqualizerDDFadeRecoverEvents', ...
        'AdaptiveEqualizerFadeRecoverDB', ...
        'AdaptiveEqualizerFadeDetectorSymbols', ...
        'AdaptiveEqualizerExternalFadeMaskProvided', ...
        'AdaptiveEqualizerExternalFadeMaskLengthMatched', ...
        'AdaptiveEqualizerExternalFadeMaskInputLength', ...
        'AdaptiveEqualizerExternalFadeInputSymbols', ...
        'AdaptiveEqualizerExternalFadeExpandedSymbols', ...
        'AdaptiveEqualizerDDExternalFadeHoldWindows', ...
        'AdaptiveEqualizerDDExternalFadeHoldSymbols', ...
        'AdaptiveEqualizerFadeHoldDB', ...
        'AdaptiveEqualizerDDHoldReason', ...
        'AdaptiveEqualizerOutputAccepted', ...
        'AdaptiveEqualizerRollbackReason', ...
        'AdaptiveEqualizerConverged', ...
        'ASMTrainingEqualizerASMCount','ASMTrainingEqualizerUpdates', ...
        'ASMTrainingEqualizerMedianScoreBefore', ...
        'ASMTrainingEqualizerMedianScoreAfter'};
    for iAdaptiveResult = 1:numel(adaptiveResultFields)
        adaptiveField = adaptiveResultFields{iAdaptiveResult};
        if isfield(res, adaptiveField)
            frontResult.(adaptiveField) = res.(adaptiveField);
        end
    end
    fastTrackerFields = { ...
        'FastEnvelopeApplied','FastEnvelopeEstimatorMode', ...
        'FastEnvelopeTauSymbols','FastEnvelopeBlockSymbols', ...
        'FastEnvelopeHopSymbols','FastEnvelopeMedianBlocks', ...
        'FastEnvelopeTrimFraction', ...
        'FastEnvelopeGainSlewDBPerSymbol', ...
        'FastEnvelopeFinalGain_dB', ...
        'FastEnvelopeGainMin_dB','FastEnvelopeGainMax_dB', ...
        'FastEnvelopeExternalHoldApplied', ...
        'FastEnvelopeExternalHoldSamples', ...
        'FastEnvelopeExternalHoldFraction', ...
        'BlindReliabilityApplied','BlindReliabilityReason', ...
        'BlindReliabilityFinalState','BlindReliabilityWindowSymbols', ...
        'BlindReliabilityHoldFraction','BlindReliabilityHoldEvents', ...
        'BlindReliabilityRecoverEvents', ...
        'BlindReliabilityMinRelativePower_dB', ...
        'BlindReliabilityMaxInverseGain_dB', ...
        'FastComplexGainApplied','FastComplexGainFinalMagnitude_dB', ...
        'FastComplexGainFinalPhase_deg','FastComplexGainAcceptanceRate', ...
        'FastComplexGainDDMSE','FastComplexGainMin_dB', ...
        'FastComplexGainMax_dB','FastComplexExternalHoldApplied', ...
        'FastComplexExternalHoldSamples', ...
        'FastComplexExternalHoldFraction', ...
        'HighRatePhaseTrackingApplied','HighRatePhaseWindowSymbols', ...
        'HighRatePhaseMeanConfidence','HighRatePhaseHoldSamples', ...
        'HighRatePhaseFinalRelativePhase_deg', ...
        'UQPSKCarrierPLLApplied','UQPSKCarrierPLLDualBandwidth', ...
        'UQPSKCarrierPLLLocked','UQPSKCarrierPLLFinalMode', ...
        'UQPSKCarrierPLLAcquireBW','UQPSKCarrierPLLTrackBW', ...
        'UQPSKCarrierPLLFinalFrequency_Hz', ...
        'UQPSKCarrierPLLLockTransitions', ...
        'UQPSKCarrierPLLReacquisitions', ...
        'UQPSKCarrierPLLFadeHoldSymbols', ...
        'UQPSKCarrierPLLExternalHoldApplied', ...
        'UQPSKCarrierPLLExternalHoldSymbols', ...
        'UQPSKCarrierPLLExternalHoldFraction', ...
        'UQPSKCarrierPLLUpdateAcceptanceRate', ...
        'UQPSKCarrierPLLMeanAbsPhaseError'};
    for iFastTracker = 1:numel(fastTrackerFields)
        fastField = fastTrackerFields{iFastTracker};
        if isfield(res,fastField)
            frontResult.(fastField) = res.(fastField);
        end
    end
    if isfield(res,'SyncDiagnostics')
        frontResult.SyncDiagnostics = res.SyncDiagnostics;
    end
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
    if isfield(res,'ActualWaveformDuration_s')
        frontResult.ActualWaveformDuration_s = ...
            res.ActualWaveformDuration_s;
    end
    if isfield(res,'cfo_est_Hz'),    frontResult.cfo_est_Hz = res.cfo_est_Hz; end
    if isfield(res,'IFHz'),          frontResult.IFHz = res.IFHz; end
    if isfield(res,'centerFrequencyHz'), frontResult.centerFrequencyHz = res.centerFrequencyHz; end
    if isfield(res,'inputLevelDbm'), frontResult.inputLevelDbm = res.inputLevelDbm; end
    if isfield(res,'outputLevelDbm'), frontResult.outputLevelDbm = res.outputLevelDbm; end
    converterResultFields = { ...
        'ConverterChainEnabled','BasebandIFLevel_dBm', ...
        'UpconverterFixedGain_dB','UpconverterAttenuation_dB', ...
        'UpconverterNetGain_dB','UpconverterOutputLevel_dBm', ...
        'UpconverterCompressionRisk','UpconverterCompression_dB', ...
        'UpconverterInputWithinTypicalRange','HAppliedGain_dB', ...
        'DownconverterInputLevel_dBm','DownconverterFixedGain_dB', ...
        'DownconverterAttenuation_dB','DownconverterAutoAttenuation', ...
        'DownconverterNetGain_dB', ...
        'DownconverterOutputLevel_dBm','DownconverterCompressionRisk', ...
        'DownconverterCompression_dB','DownconverterInputWithinTypicalRange', ...
        'ADCEquivalentEnabled','ADCBits','ADCFullScalePower_dBm', ...
        'ADCRMSBackoff_dB','ADCClipFraction','ADCQuantizationSNR_dB'};
    for iConverterResult = 1:numel(converterResultFields)
        converterField = converterResultFields{iConverterResult};
        if isfield(res, converterField)
            frontResult.(converterField) = res.(converterField);
        end
    end
    if isfield(res,'carrierFreqHz'), frontResult.carrierFreqHz = res.carrierFreqHz; end
    if isfield(res,'ACMFormat'), frontResult.ACMFormat = res.ACMFormat; end
    if isfield(res,'fmDetectedFrames'), frontResult.fmDetectedFrames = res.fmDetectedFrames; end
    if isfield(res,'fmTotalFrames'),    frontResult.fmTotalFrames = res.fmTotalFrames; end
    if isfield(res,'fmReceiverMode'), frontResult.fmReceiverMode = res.fmReceiverMode; end
    if isfield(res,'fmBestNormalizedCorrelation')
        frontResult.fmBestNormalizedCorrelation = ...
            res.fmBestNormalizedCorrelation;
    end
    if isfield(res,'fmSelectedSamplePhase')
        frontResult.fmSelectedSamplePhase = res.fmSelectedSamplePhase;
    end

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

    % --- 可选完整绘图数组 ---
    % 远控接口默认关闭，避免频谱、星座和管线数组进入大 JSON。以后如需
    % 恢复交互式绘图，只需在调用参数中设置 includeRawData=true。
    if includeRawData
        frontResult.spectrum             = fe.spectrum;
        frontResult.channelPower        = fe.channelPower;
        frontResult.constellation_tx     = fe.constTx;
        frontResult.constellation_raw    = fe.constRaw;
        frontResult.constellation_synced = fe.constSync;
        frontResult.pipeline             = fe.pipeline;
    end

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
        'AdaptiveEqualizerEnabled', getLogicalField(res, 'AdaptiveEqualizerEnabled', false), ...
        'AdaptiveEqualizerMode', getfieldwithdefault(res, 'AdaptiveEqualizerMode', 'off'), ...
        'AdaptiveEqualizerCMAMSE', getfieldnumeric(res, 'AdaptiveEqualizerCMAMSE', NaN), ...
        'AdaptiveEqualizerDDMSE', getfieldnumeric(res, 'AdaptiveEqualizerDDMSE', NaN), ...
        'AdaptiveEqualizerAcceptanceRate', getfieldnumeric(res, 'AdaptiveEqualizerAcceptanceRate', NaN), ...
        'AdaptiveEqualizerRejectedDecisions', getfieldnumeric(res, 'AdaptiveEqualizerRejectedDecisions', 0), ...
        'AdaptiveEqualizerFinalTapNorm', getfieldnumeric(res, 'AdaptiveEqualizerFinalTapNorm', NaN), ...
        'AdaptiveEqualizerConverged', getLogicalField(res, 'AdaptiveEqualizerConverged', false), ...
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
     if isfield(res,'AGCEnabled'), frontResult.stats.AGCEnabled = res.AGCEnabled; end
     if isfield(res,'AGCTimeConstantMs'), frontResult.stats.AGCTimeConstantMs = res.AGCTimeConstantMs; end
     if isfield(res,'AGCSufficientObservation'), frontResult.stats.AGCSufficientObservation = res.AGCSufficientObservation; end
     if isfield(res,'AGCEnabled'), frontResult.AGCEnabled = res.AGCEnabled; end
     if isfield(res,'AGCTimeConstantMs'), frontResult.AGCTimeConstantMs = res.AGCTimeConstantMs; end
     agcStatsFields = {'AGCProcessingRateHz','AGCInitialGain_dB', ...
         'AGCFinalGain_dB','AGCMinGain_dB','AGCMaxGain_dB', ...
         'AGCInputPower_dB','AGCOutputPower_dB', ...
         'AGCPowerEstimateFinal_dB','WaveformDurationOverTau'};
      for iAGCStats = 1:numel(agcStatsFields)
          agcField = agcStatsFields{iAGCStats};
          if isfield(res, agcField)
              frontResult.(agcField) = res.(agcField);
              frontResult.stats.(agcField) = res.(agcField);
          end
      end
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
            opt, 'GMSKDetectionMode', 'official-viterbi-frame-reset')));
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



% 负责把具体参数转换并整理成统一的 opt 结构体
% 告诉最后的结果打包函数：
% "struct"：按 MATLAB struct 返回
% "json"  ：按 JSON 字符串返回
function [opt, outputMode] = parseEvaluationEntryInputs(varargin)
    outputMode = "json";
    defaults = struct('modType','QPSK','symbolRate',10e6,'sps',8, ...
        'snr',12,'cfo',0,'phaseOffset',0,'delay',0, ...
        'noiseMode','psd','noisePSDdBmHz',-115.3, ...
        'noiseBandwidthHz',[], ...
        'inputLevelDbm',-10, ...
        'enableConverterChain',false, ...
        'upconverterFixedGainDB',31, ...
        'upconverterAttenuationDB',21, ...
        'downconverterFixedGainDB',31, ...
        'downconverterAttenuationDB',21, ...
        'downconverterAutoAttenuation',true, ...
        'downconverterTargetOutputDBm',0, ...
        'converterAttenuationStepDB',0.5, ...
        'converterMaxAttenuationDB',30, ...
        'converterOutputP1dBDBm',11, ...
        'converterInputMinimumDBm',-60, ...
        'converterInputMaximumDBm',-10, ...
        'enableConverterCompression',false, ...
        'enableADCEquivalent',false, ...
        'adcBits',12, ...
        'adcFullScalePowerDBm',0, ...
        'channelCoding','none','RolloffFactor',0.35, ...
        'RandomizerEnabled',false, ...
        'RandomizerFECPosition','afterEncoding', ...
        'DataPathMode','single', ...
        'TMDataSource','random', ...
        'TMDataSourceI','', ...
        'TMDataSourceQ','', ...
        'TMDataSourcePNInitialState',[], ...
        'TMDataSourcePNPolynomialExponents',[], ...
        'TMDataSourcePNInvert',false, ...
        'TMDataSourceFixedPattern',uint8(hex2dec('55')), ...
        'TMDataSourceIncrementStart',0, ...
        'debugTMDataSource',false, ...
        'ConvolutionalG1G2Mode','auto-ccsds', ...
        'carrierCaptureRangeHz',[], ...
        'WaveformMode','ordinaryTM', ...
        'hasASM',true,...
        'AGCEnabled',false, ...
        'AGCTimeConstantMs',10, ...
        'AGCTargetSignalPower',[], ...
        'AGCUseTransmitReference',false, ...
        'AGCMinGainDB',-40, ...
        'AGCMaxGainDB',40, ...
        'AGCPowerFloor',1e-12, ...
        'remoteMode',false, ...
        'includeRawData',false, ...
        'outputDir','', ...
        'enableAPSKCoarseFrequencyCompensator',true);

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
    outputMode = "struct";
end
% 把用户传入的 JSON 或 struct，统一变成字段完整的 MATLAB struct。
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



function [enabled, timeConstantMs] = localResolveAGCOptions(opt)
%LOCALRESOLVEAGCOPTIONS Resolve the two public ordinary-TM AGC controls.
% Keep the accepted time constants explicit so a sweep cannot silently use
% an arbitrary value or a legacy fixed-loop coefficient.
    enabled = getLogicalField(opt, 'AGCEnabled', false);
    timeConstantMs = 10;
    if isfield(opt, 'AGCTimeConstantMs') && ...
            ~isempty(opt.AGCTimeConstantMs)
        raw = opt.AGCTimeConstantMs;
        if isnumeric(raw) || islogical(raw)
            timeConstantMs = double(raw);
        else
            timeConstantMs = str2double(string(raw));
        end
    end
    if ~isscalar(timeConstantMs) || ~isfinite(timeConstantMs) || ...
            ~ismember(timeConstantMs, [1 10 100 1000])
        error('run_ccsds_tm_evaluation:InvalidAGCTimeConstantMs', ...
            'AGCTimeConstantMs must be one of [1 10 100 1000].');
    end
    timeConstantMs = double(timeConstantMs);
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

    if isfield(opt, 'GMSKDetectionMode') && ...
            ~isempty(opt.GMSKDetectionMode) && ...
            ~strcmpi(string(opt.GMSKDetectionMode), ...
            "official-viterbi-frame-reset")
        error('run_ccsds_tm_evaluation:GMSKProductionDetectorRemoved', ...
            ['GMSKDetectionMode="%s" is no longer a production receiver ', ...
             'mode. Use "official-viterbi-frame-reset"; instantiate a ', ...
             'legacy helper directly only in an isolated debug script.'], ...
            char(string(opt.GMSKDetectionMode)));
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
    n = max(1, requestedOutputs);
    outs = cell(1, n);
    if strcmpi(char(outputMode), 'struct')
        outs{1} = resultStruct;
    else
        % JSON callers keep a JSON first output even when requesting the
        % reference-compatible second output containing image paths.
        outs{1} = jsonencode(resultStruct);
    end
    if requestedOutputs >= 2
        outs{2} = imagePaths;
    end
    for k = 3:requestedOutputs
        outs{k} = [];
    end
end

function imagePaths = createRemoteResultFigures(ctx, fe, res, opt)
%CREATEREMOTERESULTFIGURES Create the three PNG artifacts used by the
% reference Vue/Python interface: time domain, spectrum and constellation.
    outputDir = char(string(getfieldwithdefault(opt, 'outputDir', '')));
    if isempty(strtrim(outputDir))
        outputDir = tempname;
    end
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    timePath = fullfile(outputDir, 'TimeDomain.png');
    spectrumPath = fullfile(outputDir, 'Spectrum.png');
    constellationPath = fullfile(outputDir, 'Constellation.png');

    if isfield(ctx, 'rxWaveform') && ~isempty(ctx.rxWaveform)
        timeSignal = ctx.rxWaveform(:);
    else
        timeSignal = ctx.channelOutput(:);
    end
    sampleCount = min(5000, numel(timeSignal));

    fig = localRemoteFigure('CCSDS TM Time-Domain Power', ...
        [100 100 1200 620]);
    if sampleCount > 0
        timeMs = (0:sampleCount-1).' / double(ctx.Fs) * 1000;
        timePowerDbm = localCalibratedComplexPowerDbm( ...
            timeSignal(1:sampleCount), timeSignal, ...
            getfieldnumeric(res, 'inputLevelDbm', -10));
        plot(timeMs, timePowerDbm, 'Color', 'b', 'LineWidth', 0.8);
        powerMaximum = max(timePowerDbm);
        powerMinimum = min(timePowerDbm);
        powerRange = max(powerMaximum - powerMinimum, 10);
        ylim([powerMinimum - 0.05*powerRange, ...
            powerMaximum + 0.1*powerRange]);
        xlim([timeMs(1), timeMs(end)]);
        powerLegend = legend('信道输出瞬时功率', ...
            'Location', 'northoutside', 'NumColumns', 1, ...
            'TextColor', 'w');
        set(powerLegend, 'Color', 'none', 'EdgeColor', 'none');
    else
        text(0.5, 0.5, '没有有效的时域功率样本', ...
            'Color', 'w', 'HorizontalAlignment', 'center');
    end
    localStyleRemoteAxes('时间 (ms)', '瞬时功率 (dBm)', ...
        sprintf('CCSDS TM 信道输出 - 时域功率 | %s', ...
        char(string(res.modType))));
    saveas(fig, timePath);
    close(fig);

    fig = localRemoteFigure('CCSDS TM Spectrum', [100 100 1200 620]);
    if isfield(ctx, 'channelInput') && ~isempty(ctx.channelInput)
        spectrumInput = ctx.channelInput(:);
    else
        spectrumInput = ctx.txWaveform(:);
    end
    if isfield(ctx, 'rxWaveform') && ~isempty(ctx.rxWaveform)
        spectrumOutput = ctx.rxWaveform(:);
    else
        spectrumOutput = ctx.channelOutput(:);
    end
    spectrumSampleCount = min([numel(spectrumInput), ...
        numel(spectrumOutput), 65536]);
    if spectrumSampleCount > 1
        fftCount = min(65536, 2^nextpow2(spectrumSampleCount));
        spectrumInput = spectrumInput(1:spectrumSampleCount);
        spectrumOutput = spectrumOutput(1:spectrumSampleCount);
        spectrumWindow = localRaisedCosineWindow(spectrumSampleCount);
        inputFft = fftshift(fft(spectrumInput .* spectrumWindow, fftCount));
        outputFft = fftshift(fft(spectrumOutput .* spectrumWindow, fftCount));
        inputLevelDbm = getfieldnumeric(res, 'inputLevelDbm', -10);
        inputPsdDbmHz = localCalibratedSpectrumPsdDbmHz( ...
            inputFft, spectrumWindow, ctx.Fs, spectrumInput, inputLevelDbm);
        outputPsdDbmHz = localCalibratedSpectrumPsdDbmHz( ...
            outputFft, spectrumWindow, ctx.Fs, spectrumInput, inputLevelDbm);
        centerFrequencyMHz = getCenterFrequencyHz(res, 0) / 1e6;
        basebandFrequencyMHz = (-fftCount/2:fftCount/2-1).' / ...
            fftCount * double(ctx.Fs) / 1e6;
        frequencyMHz = centerFrequencyMHz + basebandFrequencyMHz;

        plot(frequencyMHz, inputPsdDbmHz, ...
            'Color', 'c', 'LineWidth', 1.2);
        hold on;
        plot(frequencyMHz, outputPsdDbmHz, ...
            'Color', 'g', 'LineWidth', 0.8);

        yMaximum = max([inputPsdDbmHz; outputPsdDbmHz]);
        yMinimum = min([inputPsdDbmHz; outputPsdDbmHz]);
        yRange = max(yMaximum - yMinimum, 10);
        ylim([yMinimum - 0.05*yRange, yMaximum + 0.1*yRange]);
        xlim([frequencyMHz(1), frequencyMHz(end)]);
        spectrumLegend = legend('信道输入 PSD', '信道输出 PSD', ...
            'Location', 'northoutside', 'NumColumns', 2, ...
            'TextColor', 'w');
        set(spectrumLegend, 'Color', 'none', 'EdgeColor', 'none');
    else
        text(0.5, 0.5, 'No spectrum samples', ...
            'Color', 'w', 'HorizontalAlignment', 'center');
    end
    localStyleRemoteAxes('频率 (MHz)', '功率谱密度 (dBm/Hz)', ...
        sprintf('CCSDS TM 频谱对比（输入 vs 输出）| %s', ...
        char(string(res.modType))));
    saveas(fig, spectrumPath);
    close(fig);

    fig = localRemoteFigure('CCSDS TM Constellation', [100 100 820 760]);
    if isfield(ctx, 'fineSynced') && ~isempty(ctx.fineSynced)
        plotSymbols = ctx.fineSynced(:);
        maxPoints = min(80000, numel(plotSymbols));
        sampleIndices = round(linspace(1, numel(plotSymbols), maxPoints));
        plotSymbols = plotSymbols(sampleIndices);

        referenceSymbols = [];
        if isfield(ctx, 'refConst') && ~isempty(ctx.refConst) && ...
                ~any(contains(upper(string(res.modType)), ...
                ["GMSK","MSK","FM"]))
            referenceSymbols = ctx.refConst(:);
            referenceRms = sqrt(mean(abs(referenceSymbols).^2));
            plotRms = sqrt(mean(abs(plotSymbols).^2));
            if referenceRms > 0 && isfinite(plotRms) && plotRms > 0
                referenceSymbols = referenceSymbols / referenceRms * plotRms;
            end
        end

        plot(real(plotSymbols), imag(plotSymbols), '.', ...
            'MarkerSize', 1, 'Color', [1.0 0.85 0.1]);
        hold on;
        if ~isempty(referenceSymbols)
            plot(real(referenceSymbols), imag(referenceSymbols), 'o', ...
                'MarkerSize', 5, 'LineWidth', 1.1, ...
                'MarkerEdgeColor', [0 0.95 1], ...
                'MarkerFaceColor', 'none');
        end

        axisSymbols = plotSymbols;
        if ~isempty(referenceSymbols)
            axisSymbols = [axisSymbols(:); referenceSymbols(:)];
        end
        axisLimit = max(abs([real(axisSymbols(:)); ...
            imag(axisSymbols(:))])) * 1.2 + 1e-6;
        axis([-axisLimit axisLimit -axisLimit axisLimit]);
        axis square;
        line([-axisLimit axisLimit], [0 0], 'Color', [0.5 0.5 0.5], ...
            'LineStyle', '--', 'LineWidth', 0.5);
        line([0 0], [-axisLimit axisLimit], 'Color', [0.5 0.5 0.5], ...
            'LineStyle', '--', 'LineWidth', 0.5);
    else
        text(0.5, 0.5, '没有有效的同步符号', ...
            'Color', 'w', 'HorizontalAlignment', 'center');
    end
    channelLabel = '高斯白噪声 (AWGN)';
    if getLogicalField(res, 'HEnabled', false)
        channelLabel = char(string(getfieldwithdefault(res, ...
            'HMode', 'H-Matrix')));
    end
    localStyleRemoteAxes('同相幅度 (I)', '正交幅度 (Q)', ...
        sprintf('星座图 | %s | %s | 误码率: %.2e', ...
        char(string(res.modType)), channelLabel, double(res.BER)));
    saveas(fig, constellationPath);
    close(fig);

    imagePaths = char(strjoin(string( ...
        {timePath, spectrumPath, constellationPath}), ';'));
end

function fig = localRemoteFigure(figureName, position)
    fig = figure('Name', figureName, 'NumberTitle', 'off', ...
        'Visible', 'off', 'Color', 'k', 'Position', position);
    set(fig, 'InvertHardcopy', 'off');
end

function localStyleRemoteAxes(xLabelText, yLabelText, titleText)
    ax = gca;
    set(ax, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', ...
        'GridColor', [0.45 0.45 0.45], 'GridAlpha', 0.35);
    grid(ax, 'on');
    xlabel(xLabelText, 'Color', 'w');
    ylabel(yLabelText, 'Color', 'w');
    title(titleText, 'Color', 'w');
end

function psdDbmHz = localCalibratedSpectrumPsdDbmHz( ...
        spectrum, window, sampleRateHz, referenceSignal, totalPowerDbm)
    windowPower = max(sum(abs(window(:)).^2), eps);
    relativePsdHz = abs(spectrum(:)).^2 / ...
        (double(sampleRateHz) * windowPower);
    referencePower = mean(abs(referenceSignal(:)).^2);
    if ~isfinite(referencePower) || referencePower <= 0
        referencePower = 1;
    end
    normalizedPsdHz = relativePsdHz / referencePower;
    psdDbmHz = double(totalPowerDbm) + ...
        10*log10(max(normalizedPsdHz, realmin));
end

function powerDbm = localCalibratedComplexPowerDbm( ...
        samples, referenceSignal, totalPowerDbm)
    referencePower = mean(abs(referenceSignal(:)).^2);
    if ~isfinite(referencePower) || referencePower <= 0
        referencePower = 1;
    end
    relativePower = abs(samples(:)).^2 / referencePower;
    powerDbm = double(totalPowerDbm) + ...
        10*log10(max(relativePower, realmin));
end

function window = localRaisedCosineWindow(sampleCount)
    if sampleCount <= 1
        window = ones(sampleCount, 1);
    else
        sampleIndex = (0:sampleCount-1).';
        window = 0.5 - 0.5*cos(2*pi*sampleIndex/(sampleCount-1));
    end
end

% =========================================================
% 单次仿真：复用主脚本的处理链路 + 提取所有中间信号
% =========================================================
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
    % MSK只能合路
    if strcmpi(modStr, "MSK") && ...
            ~strcmpi(string(dataPathMode), "single")
        error('run_ccsds_tm_evaluation:MSKDataPathMode', ...
            ['MSK v1 only supports DataPathMode="single". ', ...
            'MSK waveform I/Q components are not independent TM rails.']);
    end

    if isFACMEvaluation(opt, modStr)
        if ~strcmpi(string(getfieldwithdefault(opt, ...
                'TMDataSource', 'random')), 'random')
            error('run_ccsds_tm_evaluation:FACMInternalDataSource', ...
                ['TMDataSource is currently implemented for ordinaryTM. ', ...
                 'Use TMDataSource="random" for FACM.']);
        end
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
        if any(strcmp(codeKey, ["convolutional", "concatenated"]))
            [~, canonicalConvMode] = ccsdsTMConvolutionalOutputTrellis( ...
                poly2trellis(7, [171 133]), opt.ConvolutionalG1G2Mode, ...
                char(getfieldwithdefault(opt,'ConvolutionalCodeRate','1/2')));
            opt.ConvolutionalG1G2Mode = canonicalConvMode;
            args = [args, {'ConvolutionalG1G2Mode', canonicalConvMode}];
            if getLogicalField(opt, 'debugConvolutionalG1G2', false)
                fprintf('[TM convolutional config] TX mode=%s rate=%s path=%s\n', ...
                    canonicalConvMode, char(getfieldwithdefault(opt, ...
                    'ConvolutionalCodeRate', '1/2')), dataPathMode);
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

        if strcmpi(modStr,'GMSK')
            args = [args, {'BandwidthTimeProduct', btVal}];
        elseif strcmpi(modStr,'MSK')

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
                if any(strcmp(codeKey, ["convolutional", "concatenated"])) && ...
                        ~(isfield(opt,'TMAPSKPilotCorrectionMode') && ~isempty(opt.TMAPSKPilotCorrectionMode))
                    opt.TMAPSKPilotCorrectionMode = 'mmseinterp';
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
    % 动态AGC
    [agcEnabled, agcTimeConstantMs] = ...
        localResolveAGCOptions(opt);

    % 动态 AGC 开启时，不允许均衡器提前执行整段静态功率恢复。
    % 必须在 applyKnownChannelEqualizer 调用前改 opt。
    if agcEnabled
        opt.normalizeEqualizerOutput = false;
    end

    % 合路/IQ分路 功能
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

    % Device-equivalent internal test data are inserted only into the TM
    % Transfer Frame Data Field.  ASM, primary header, optional OCF/FECF,
    % randomization, coding, and modulation remain on the existing path.
    tmSourceSingle = localTMDataSourceType(opt, '');
    tmSourceI = localTMDataSourceType(opt, 'I');
    tmSourceQ = localTMDataSourceType(opt, 'Q');
    tmSourceOptSingle = localTMDataSourceOptions(opt, '');
    tmSourceOptI = localTMDataSourceOptions(opt, 'I');
    tmSourceOptQ = localTMDataSourceOptions(opt, 'Q');
    tmSourceStateSingle = [];
    tmSourceStateI = [];
    tmSourceStateQ = [];
    tmSourceInfoSingle = struct('CanonicalType','');
    tmSourceInfoI = struct('CanonicalType','');
    tmSourceInfoQ = struct('CanonicalType','');
    if isEqualSplitPath || isUnequalSplitPath
        [~, tmSourceStateI, tmSourceInfoI] = ccsdsTMInternalDataSource( ...
            0, tmSourceI, tmSourceStateI, tmSourceOptI);
        [~, tmSourceStateQ, tmSourceInfoQ] = ccsdsTMInternalDataSource( ...
            0, tmSourceQ, tmSourceStateQ, tmSourceOptQ);
    else
        [~, tmSourceStateSingle, tmSourceInfoSingle] = ...
            ccsdsTMInternalDataSource(0, tmSourceSingle, ...
            tmSourceStateSingle, tmSourceOptSingle);
    end

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
        tfOpt.HasFECF = getLogicalField(opt, 'HasFECF', ...
            getLogicalField(opt, 'CRCEnabled', false));
        tfOpt.CRCType = char(getfieldwithdefault(opt, 'CRCType', 'CCITT'));
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
            sourceBytesI = localTMSourceRequestBytes(tfOptI, ...
                numBytesActualTF, tmSourceInfoI.CanonicalType);
            sourceOptI = tmSourceOptI;
            sourceOptI.Debug = getLogicalField(opt, ...
                'debugTMDataSource', false) && i == 1;
            [payloadBytesI, tmSourceStateI, tmSourceInfoI] = ...
                ccsdsTMInternalDataSource(sourceBytesI, tmSourceI, ...
                tmSourceStateI, sourceOptI);
            [frameBitsI, frameBytesI, frameInfoI] = make_ccsds_tm_transfer_frame(payloadBytesI, tfOptI);
            frameInfoI = localAttachTMDataSourceInfo(frameInfoI, ...
                tmSourceInfoI, 'I');
            currentI = int8(frameBitsI(:));
            if numel(currentI) ~= bitsPerFrame
                error('run_ccsds_tm_evaluation:TMFrameLengthMismatch', ...
                    'Generated I-rail TM frame length mismatch: got %d bits, expected %d bits.', ...
                    numel(currentI), bitsPerFrame);
            end

            tfOptQ = tfOpt;
            tfOptQ.MasterChannelFrameCount = mod(2*(i-1)+1, 256);
            tfOptQ.VirtualChannelFrameCount = mod(2*(i-1)+1, 256);
            sourceBytesQ = localTMSourceRequestBytes(tfOptQ, ...
                numBytesActualTF, tmSourceInfoQ.CanonicalType);
            sourceOptQ = tmSourceOptQ;
            sourceOptQ.Debug = getLogicalField(opt, ...
                'debugTMDataSource', false) && i == 1;
            [payloadBytesQ, tmSourceStateQ, tmSourceInfoQ] = ...
                ccsdsTMInternalDataSource(sourceBytesQ, tmSourceQ, ...
                tmSourceStateQ, sourceOptQ);
            [frameBitsQ, frameBytesQ, frameInfoQ] = make_ccsds_tm_transfer_frame(payloadBytesQ, tfOptQ);
            frameInfoQ = localAttachTMDataSourceInfo(frameInfoQ, ...
                tmSourceInfoQ, 'Q');
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
            sourceBytesI1 = localTMSourceRequestBytes(tfOptI1, ...
                numBytesActualTF, tmSourceInfoI.CanonicalType);
            sourceOptI = tmSourceOptI;
            sourceOptI.Debug = getLogicalField(opt, ...
                'debugTMDataSource', false) && i == 1;
            [payloadBytesI1, tmSourceStateI, tmSourceInfoI] = ...
                ccsdsTMInternalDataSource(sourceBytesI1, tmSourceI, ...
                tmSourceStateI, sourceOptI);
            [frameBitsI1, frameBytesI1, frameInfoI1] = ...
                make_ccsds_tm_transfer_frame(payloadBytesI1, tfOptI1);
            frameInfoI1 = localAttachTMDataSourceInfo(frameInfoI1, ...
                tmSourceInfoI, 'I');
            currentI1 = int8(frameBitsI1(:));

            tfOptI2 = tfOpt;
            tfOptI2.MasterChannelFrameCount = mod(2*(i-1)+1, 256);
            tfOptI2.VirtualChannelFrameCount = mod(2*(i-1)+1, 256);
            sourceBytesI2 = localTMSourceRequestBytes(tfOptI2, ...
                numBytesActualTF, tmSourceInfoI.CanonicalType);
            sourceOptI = tmSourceOptI;
            sourceOptI.Debug = false;
            [payloadBytesI2, tmSourceStateI, tmSourceInfoI] = ...
                ccsdsTMInternalDataSource(sourceBytesI2, tmSourceI, ...
                tmSourceStateI, sourceOptI);
            [frameBitsI2, frameBytesI2, frameInfoI2] = ...
                make_ccsds_tm_transfer_frame(payloadBytesI2, tfOptI2);
            frameInfoI2 = localAttachTMDataSourceInfo(frameInfoI2, ...
                tmSourceInfoI, 'I');
            currentI2 = int8(frameBitsI2(:));

            tfOptQ = tfOpt;
            tfOptQ.MasterChannelFrameCount = mod(i-1, 256);
            tfOptQ.VirtualChannelFrameCount = mod(i-1, 256);
            sourceBytesQ = localTMSourceRequestBytes(tfOptQ, ...
                numBytesActualTF, tmSourceInfoQ.CanonicalType);
            sourceOptQ = tmSourceOptQ;
            sourceOptQ.Debug = getLogicalField(opt, ...
                'debugTMDataSource', false) && i == 1;
            [payloadBytesQ, tmSourceStateQ, tmSourceInfoQ] = ...
                ccsdsTMInternalDataSource(sourceBytesQ, tmSourceQ, ...
                tmSourceStateQ, sourceOptQ);
            [frameBitsQ, frameBytesQ, frameInfoQ] = ...
                make_ccsds_tm_transfer_frame(payloadBytesQ, tfOptQ);
            frameInfoQ = localAttachTMDataSourceInfo(frameInfoQ, ...
                tmSourceInfoQ, 'Q');
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
            sourceBytes = localTMSourceRequestBytes(tfOpt, ...
                numBytesActualTF, tmSourceInfoSingle.CanonicalType);
            sourceOptSingle = tmSourceOptSingle;
            sourceOptSingle.Debug = getLogicalField(opt, ...
                'debugTMDataSource', false) && i == 1;
            [payloadBytes, tmSourceStateSingle, tmSourceInfoSingle] = ...
                ccsdsTMInternalDataSource(sourceBytes, tmSourceSingle, ...
                tmSourceStateSingle, sourceOptSingle);
            [frameBits, frameBytes, frameInfo] = make_ccsds_tm_transfer_frame(payloadBytes, tfOpt);
            frameInfo = localAttachTMDataSourceInfo(frameInfo, ...
                tmSourceInfoSingle, 'single');
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
    actualWaveformDuration_s = numel(txWaveform) / Fs;
    fprintf(['[Test length] waveform=%.3f ms | warmup=%d | ', ...
        'BER=%d | total=%d frames\n'], ...
        1e3*actualWaveformDuration_s, numWarmUp, numRealFrames, totalFrames);
    debugCodedBoundary = getLogicalField(opt, 'debugCodedBoundary', false);
    collectPredecoderStats = debugCodedBoundary || ...
        getLogicalField(opt, 'collectPredecoderStats', false);
    assignin('base', 'debugCodedBoundaryEnabled', debugCodedBoundary);
    if collectPredecoderStats
        assignin('base', 'debugCodedFrameSyncPrintLimit', ...
            max(0, round(getfieldnumeric(opt, 'debugCodedFrameSyncPrintLimit', 80))));
        assignin('base', 'debugCodedFrameSyncPrintCount', 0);
        assignin('base', 'debugTMEncodedBits', int8(encodedBits(:) ~= 0));
        if debugCodedBoundary
            fprintf('[Coded DEBUG] stored tx encodedBits for boundary check: %d bits\n', numel(encodedBits));
        end
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
        % comm.PhaseFrequencyOffset.PhaseOffset is specified in DEGREES.
        % Keep phase_val in radians for the evaluator's internal metrics,
        % but pass the original user-facing degree value to the object.
        pfo = comm.PhaseFrequencyOffset('FrequencyOffset',cfo_val, ...
            'PhaseOffset',rad2deg(phase_val),'SampleRate',Fs);
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

    converterChainEnabled = getLogicalField(opt, 'enableConverterChain', false);
    converterAttenuationStepDB = getfieldnumeric( ...
        opt, 'converterAttenuationStepDB', 0.5);
    converterMaxAttenuationDB = getfieldnumeric( ...
        opt, 'converterMaxAttenuationDB', 30);
    converterOutputP1dBDBm = getfieldnumeric( ...
        opt, 'converterOutputP1dBDBm', 11);
    converterCompressionEnabled = getLogicalField( ...
        opt, 'enableConverterCompression', false);
    basebandIFLevelDBm = getInputLevelDbm(opt, -10);

    upconverterCfg = struct( ...
        'Enabled', converterChainEnabled, ...
        'StageName', 'upconverter', ...
        'InputSignalLevelDBm', basebandIFLevelDBm, ...
        'InputTotalLevelDBm', basebandIFLevelDBm, ...
        'FixedGainDB', getfieldnumeric(opt, 'upconverterFixedGainDB', 31), ...
        'AttenuationDB', getfieldnumeric(opt, 'upconverterAttenuationDB', 21), ...
        'AttenuationStepDB', converterAttenuationStepDB, ...
        'MaxAttenuationDB', converterMaxAttenuationDB, ...
        'OutputP1dBDBm', converterOutputP1dBDBm, ...
        'InputMinimumDBm', getfieldnumeric(opt, 'converterInputMinimumDBm', -60), ...
        'InputMaximumDBm', getfieldnumeric(opt, 'converterInputMaximumDBm', -10), ...
        'EnableCompression', converterCompressionEnabled);
    [txAfterUpconverter, upconverterInfo] = ...
        HelperTMConverterGain(txWithDelay, upconverterCfg);

    [txAfterH, hInfo, hState] = applyHChannelDamage( ...
        txAfterUpconverter, opt, Fs);
    hAppliedGainDB = 10*log10( ...
        (mean(abs(txAfterH).^2) + eps) / ...
        (mean(abs(txAfterUpconverter).^2) + eps));
    actualCodeRateForHStats = getfieldnumeric(tmWaveInfo, 'ActualCodeRate', NaN);
    bitsPerSymbolForHStats = getfieldnumeric(tmWaveInfo, 'NumBitsPerSymbol', NaN);
    localPrintHMatrixFrameStats(hState, opt, Fs, sps, bitsPerFrame, ...
        actualCodeRateForHStats, bitsPerSymbolForHStats, totalFrames);

    noisePlacement = getNoisePlacementMode(opt);
    noiseInfo = makeLegacyNoiseInfo(snr_val);
    if converterChainEnabled && noisePlacement == "afterEqualizer"
        error('run_ccsds_tm_evaluation:ConverterChainNoiseOrder', ...
            ['enableConverterChain requires noisePlacement=''afterChannel'' ', ...
             'so that H -> receiver noise -> downconverter -> ADC is physical.']);
    end
    noiseOpt = opt;
    noiseOpt.signalReferenceLevelDbm = ...
        upconverterInfo.OutputSignalLevelDBm;
    downconverterInfo = localDisabledConverterInfo( ...
        'downconverter', upconverterInfo.OutputSignalLevelDBm);
    adcInfo = localDisabledADCInfo();
    rxAfterDownconverter = [];
    rxAfterADC = [];
    if noisePlacement == "afterEqualizer"
        rxEqualizedClean = applyKnownChannelEqualizer(txAfterH, opt, snr_val, false, hState);
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise( ...
            rxEqualizedClean, noiseOpt, Fs, snr_val, txAfterUpconverter);
        rxWaveform = rxNoisyWaveform;
    else
        [rxNoisyWaveform, noiseInfo] = addReceiverNoise( ...
            txAfterH, noiseOpt, Fs, snr_val, txAfterUpconverter);

        signalAtDownconverterDBm = ...
            upconverterInfo.OutputSignalLevelDBm + hAppliedGainDB;
        receiverNoisePowerDBm = localReceiverNoisePowerDBm( ...
            noiseInfo, signalAtDownconverterDBm);
        totalAtDownconverterDBm = localSumPowerDBm( ...
            signalAtDownconverterDBm, receiverNoisePowerDBm);
        downconverterCfg = struct( ...
            'Enabled', converterChainEnabled, ...
            'StageName', 'downconverter', ...
            'InputSignalLevelDBm', signalAtDownconverterDBm, ...
            'InputTotalLevelDBm', totalAtDownconverterDBm, ...
            'FixedGainDB', getfieldnumeric(opt, 'downconverterFixedGainDB', 31), ...
            'AttenuationDB', getfieldnumeric(opt, 'downconverterAttenuationDB', 21), ...
            'AutoAttenuation', getLogicalField(opt, ...
                'downconverterAutoAttenuation', true), ...
            'TargetOutputTotalLevelDBm', getfieldnumeric(opt, ...
                'downconverterTargetOutputDBm', 0), ...
            'AttenuationStepDB', converterAttenuationStepDB, ...
            'MaxAttenuationDB', converterMaxAttenuationDB, ...
            'OutputP1dBDBm', converterOutputP1dBDBm, ...
            'InputMinimumDBm', getfieldnumeric(opt, 'converterInputMinimumDBm', -60), ...
            'InputMaximumDBm', getfieldnumeric(opt, 'converterInputMaximumDBm', -10), ...
            'EnableCompression', converterCompressionEnabled);
        [rxAfterDownconverter, downconverterInfo] = ...
            HelperTMConverterGain(rxNoisyWaveform, downconverterCfg);

        adcCfg = struct( ...
            'Enabled', converterChainEnabled && ...
                getLogicalField(opt, 'enableADCEquivalent', false), ...
            'Bits', getfieldnumeric(opt, 'adcBits', 12), ...
            'FullScalePowerDBm', getfieldnumeric(opt, 'adcFullScalePowerDBm', 0), ...
            'InputTotalLevelDBm', downconverterInfo.OutputTotalLevelDBm);
        [rxAfterADC, adcInfo] = HelperTMADCEquivalent( ...
            rxAfterDownconverter, adcCfg);
        rxWaveform = applyKnownChannelEqualizer( ...
            rxAfterADC, opt, noiseInfo.EquivalentSNR_dB, false, hState);
    end

    if getLogicalField(opt, 'debugConverterChain', false)
        localPrintConverterChain(basebandIFLevelDBm, upconverterInfo, ...
            hAppliedGainDB, noiseInfo, downconverterInfo, adcInfo);
    end

    % 动态AGC
    % =========================================================
    % Ordinary TM dynamic AGC
    %
    % Optional hardware path:
    % upconverter -> H -> receiver noise -> downconverter -> ADC
    % Then the existing receiver continues with equalizer -> digital AGC ->
    % synchronization.  With the converter path disabled, historical sample
    % ordering and scaling are preserved.
    % =========================================================

%     % ===== 临时 AGC 突发衰落测试：测试完整段删除 =====
%     fadeStartMs = 100;
%     fadeDurationMs = 200;
%     fadeDepth_dB = 20;
%
%     fadeStartSample = floor(fadeStartMs*1e-3*Fs) + 1;
%     fadeEndSample = min(numel(rxWaveform), floor((fadeStartMs + fadeDurationMs)*1e-3*Fs));
%
%     if fadeStartSample <= numel(rxWaveform)
%         rxWaveform(fadeStartSample:fadeEndSample) = rxWaveform(fadeStartSample:fadeEndSample) * 10^(fadeDepth_dB/20);
%         fprintf('[AGC TEST] %.1f~%.1f ms 加入 %.1f dB 衰落\n', fadeStartMs, fadeStartMs + fadeDurationMs, fadeDepth_dB);
%     else
%         warning('AGC测试衰落起点超出波形长度，当前波形时长只有 %.3f ms。', 1000*numel(rxWaveform)/Fs);
%     end
%     % ===== 临时 AGC 突发衰落测试结束 =====

    rxWaveformBeforeAGC = rxWaveform;


    agcTargetSignalPower = getfieldnumeric( ...
        opt,'AGCTargetSignalPower',NaN);
    agcUseTransmitReference = getLogicalField( ...
        opt,'AGCUseTransmitReference',false);
    if converterChainEnabled
        if ~agcEnabled
            error('run_ccsds_tm_evaluation:ConverterChainRequiresAGC', ...
                ['enableConverterChain models the analog front end and ', ...
                 'requires AGCEnabled=true to restore the FPGA demodulator ', ...
                 'input scale after the ADC reference plane.']);
        end
    end
    if ~isfinite(agcTargetSignalPower) && ...
            (converterChainEnabled || agcUseTransmitReference)
        % Explicit simulation/calibration reference: restore the receive
        % waveform to the modulation-specific transmit RMS without using
        % the instantaneous or true H coefficient.  The default remains
        % burst-bootstrap AGC so production behavior is unchanged.
        agcTargetSignalPower = mean(abs(txWithDelay).^2) + eps;
    end
    agcCfg = struct( ...
        'Enabled',agcEnabled, ...
        'SampleRateHz',Fs, ...
        'TimeConstantMs',agcTimeConstantMs, ...
        'TargetSignalPower',agcTargetSignalPower, ...
        'MinGainDB',getfieldnumeric(opt,'AGCMinGainDB',-40), ...
        'MaxGainDB',getfieldnumeric(opt,'AGCMaxGainDB',40), ...
        'PowerFloor',getfieldnumeric(opt,'AGCPowerFloor',1e-12), ...
        'InitialPowerEstimate',NaN, ...
        'TraceMaxPoints',2000, ...
        'ChunkSizeSamples',1e6);

    agcState = struct();

    [rxWaveform, agcState, agcInfo] = ...
        HelperTMAGC( ...
        rxWaveformBeforeAGC, ...
        agcState, ...
        agcCfg);

    rxWaveformAfterAGC = rxWaveform;

%临时AGC
%     assignin('base', 'agcTestBefore', rxWaveformBeforeAGC);
%     assignin('base', 'agcTestAfter', rxWaveformAfterAGC);
%     assignin('base', 'agcTestInfo', agcInfo);
%     assignin('base', 'agcTestFs', Fs);

    if getLogicalField(opt,'debugAGC',false)
        fprintf('\n[TM AGC]\n');
        fprintf('  enabled             : %d\n', ...
            agcInfo.Enabled);

        fprintf('  tau                 : %.3f ms\n', ...
            agcInfo.TimeConstantMs);

        fprintf('  processing rate     : %.6g Hz\n', ...
            agcInfo.ProcessingRateHz);

        fprintf('  waveform/tau        : %.6f\n', ...
            agcInfo.WaveformDurationOverTau);

        fprintf('  initial/final gain  : %+.3f / %+.3f dB\n', ...
            agcInfo.InitialGain_dB, ...
            agcInfo.FinalGain_dB);

        fprintf('  observed gain range : %+.3f .. %+.3f dB\n', ...
            agcInfo.MinGain_dB, ...
            agcInfo.MaxGain_dB);

        fprintf('  input/output power  : %+.3f / %+.3f dB\n', ...
            10*log10(max(agcInfo.InputPower,eps)), ...
            10*log10(max(agcInfo.OutputPower,eps)));

        fprintf('  >=5 tau observed    : %d\n', ...
            agcInfo.SufficientObservation);
    end


%% ===== 接收链路 =====
    adaptiveEqMode = lower(getOptionString( ...
        opt, {'equalizerMode','channelEqualizerMode'}, "off"));
    apskReceiverMode = lower(strtrim(getOptionString( ...
        opt, {'APSKReceiverMode','apskReceiverMode'}, "pilotless")));
    usePilotlessAPSKFrontEnd = contains(upper(string(modStr)),'APSK') && ...
        any(apskReceiverMode == ["pilotless","pilotless-apsk", ...
        "pilotless-x4-nda-dd","pilotless-xm-nda-dd"]);
    if usePilotlessAPSKFrontEnd && ...
            getLogicalField(opt,'HasTMAPSKPilots',false)
        error('run_ccsds_tm_evaluation:PilotlessAPSKHasPilots', ...
            ['APSKReceiverMode="pilotless" requires HasTMAPSKPilots=false. ', ...
             'The experimental front end must not depend on custom pilots.']);
    end
    pilotlessAPSKInfo = struct( ...
        'Applied',false,'Mode','legacy','Reason','not requested', ...
        'FourthPowerCFO_Hz',NaN,'FourthPowerConfidence_dB',NaN, ...
        'CoarsePowerOrder',NaN,'NDAResidualCFO_Hz',NaN, ...
        'NDAResidualCFOApplied',false, ...
        'MthPowerPhaseTrackerApplied',false, ...
        'MthPowerPhaseFinalCorrection_deg',NaN, ...
        'MthPowerPhaseMedianConfidence',NaN, ...
        'BlindPhaseSearchApplied',false, ...
        'BlindPhaseSearchReliableFraction',NaN, ...
        'BlindPhaseSearchMedianMetric',NaN, ...
        'BlindPhaseSearchFinalCorrection_deg',NaN, ...
        'PreDDGainTrackerApplied',false, ...
        'PreDDGainAcceptanceRate',NaN,'PreDDGainHoldFraction',NaN, ...
        'PreDDGainFadeFraction',NaN,'PreDDGainFinalMagnitude_dB',NaN, ...
        'RingNormalizerApplied',false,'RingEstimatorMode','off', ...
        'RingAcceptanceRate',NaN,'RingHoldFraction',NaN, ...
        'RingFadeFraction',NaN,'RingFinalAmplitude_dB',NaN, ...
        'CarrierAcceptanceRate',NaN,'CarrierHoldFraction',NaN, ...
        'CarrierFadeFraction',NaN,'CarrierPhaseErrorRMS_deg',NaN, ...
        'FinalResidualFrequency_Hz',NaN, ...
        'ComplexGainEnabled',false,'GainAcceptanceRate',NaN, ...
        'GainHoldFraction',NaN,'GainFadeFraction',NaN, ...
        'FinalGainMagnitude_dB',NaN,'FinalGainPhase_deg',NaN, ...
        'GainRegularization',NaN,'GainMaxInverseGainDB',NaN, ...
        'GainInverseMaxObserved_dB',NaN, ...
        'SharedReliabilityMaskProvided',false, ...
        'SharedReliabilityHoldSymbols',0, ...
        'SharedReliabilityHoldFraction',0);
    syncDebugRequested = getLogicalField(opt, 'debugSynchronizationChain', ...
        getLogicalField(opt, 'debugSyncChain', false));
    syncDebugStages = struct( ...
        'CoarseEstimate_Hz',NaN, ...
        'FilterSamplesPerSymbol',NaN, ...
        'Filtered',complex(zeros(0,1)), ...
        'Timing',complex(zeros(0,1)), ...
        'Carrier',complex(zeros(0,1)), ...
        'PilotInput',complex(zeros(0,1)), ...
        'Pilot',complex(zeros(0,1)), ...
        'PreEQTracker',complex(zeros(0,1)), ...
        'Equalizer',complex(zeros(0,1)), ...
        'PostEQTracker',complex(zeros(0,1)));
    fastEnvelopeInfo = struct('Applied',false,'FinalMagnitude_dB',0, ...
        'GainMin_dB',NaN,'GainMax_dB',NaN,'TauSymbols',NaN, ...
        'EstimatorMode','','BlockSymbols',NaN,'HopSymbols',NaN, ...
        'MedianBlocks',NaN,'TrimFraction',NaN, ...
        'GainSlewDBPerSymbol',NaN, ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSamples',0, ...
        'ExternalHoldFraction',0);
    blindReliabilityInfo = struct('Applied',false,'Reason','disabled', ...
        'FinalState','TRACK','SamplesPerSymbol',NaN, ...
        'WindowSymbols',NaN,'WindowSamples',NaN,'NumWindows',0, ...
        'AcquireWindows',0,'ReferenceTauSymbols',NaN, ...
        'ReferencePowerInitial',NaN,'ReferencePowerFinal',NaN, ...
        'FadeEnterDB',NaN,'FadeExitDB',NaN, ...
        'FadeEnterWindows',NaN,'RecoverWindows',NaN, ...
        'HoldWindows',0,'HoldSamples',0,'HoldFraction',0, ...
        'HoldEvents',0,'RecoverEvents',0, ...
        'MinRelativePowerDB',NaN,'MedianRelativePowerDB',NaN, ...
        'MaxRelativePowerDB',NaN,'MaxInverseGainDB',NaN);
    blindReliabilityHoldMaskFiltered = false(0,1);
    blindReliabilityHoldMaskSymbols = false(0,1);
    fastComplexGainInfo = struct('Applied',false,'FinalMagnitude_dB',0, ...
        'FinalPhase_deg',0,'AcceptanceRate',NaN,'DDMSE',NaN, ...
        'GainMin_dB',NaN,'GainMax_dB',NaN, ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSamples',0, ...
        'ExternalHoldFraction',0);
    highRatePhaseInfo = struct('Applied',false, ...
        'WindowSymbols',NaN,'WindowSamples',NaN, ...
        'MeanConfidence',NaN,'HoldSamples',0, ...
        'FinalRelativePhase_deg',0);
    gmskResidualTrackerInfo = localEmptyGMSKResidualTrackerInfo();
    gmskSecondOrderPLLInfo = localEmptyGMSKSecondOrderPLLInfo();
    uqpskCarrierPLLInfo = localEmptyUQPSKCarrierPLLInfo();
    uqpskPostCarrierEQEnabled = true;
    useFastEnvelopePath = false;
    useFastComplexPath = false;
    useFastPhasePath = false;
    qamBlindPhaseSearchRequested = contains(upper(string(modStr)),'QAM') && ...
        getLogicalField(opt,'enableQAMBlindPhaseSearch', ...
        getLogicalField(opt,'enableHChannel',false));
    isTPCQAM = contains(upper(string(modStr)),'QAM') && ...
        strcmpi(string(codeStr),'TPC');
    % A TPC transfer frame contains long, highly structured row/column
    % product-code sequences.  The generic decision-directed QAM BPS cost
    % can mistake that data structure for a carrier trajectory and rotate an
    % otherwise correct stream (including NoH) away from its ASM.  The normal
    % QAM carrier loop plus the common adaptive equalizer is reliable for this
    % path, so keep BPS out of TPC unless an explicit diagnostic override is
    % requested.
    qamBlindPhaseSearchEnabled = qamBlindPhaseSearchRequested && ...
        (~isTPCQAM || getLogicalField(opt, ...
        'enableQAMBlindPhaseSearchForTPC',false));
    isSplitQAM = contains(upper(string(modStr)),'QAM') && ...
        any(strcmpi(string(getfieldwithdefault(opt,'DataPathMode','single')), ...
        ["dualIQ","unequalDualIQ"]));
    qamBlindPhaseSearchEnabled = qamBlindPhaseSearchEnabled && ...
        (~isSplitQAM || getLogicalField(opt, ...
        'enableQAMBlindPhaseSearchForSplit',false));
    if qamBlindPhaseSearchRequested && isTPCQAM && ...
            ~qamBlindPhaseSearchEnabled && ...
            (getLogicalField(opt,'debugAdaptiveEqualizer',false) || ...
             getLogicalField(opt,'debugSynchronizationChain',false) || ...
             getLogicalField(opt,'debugCodedBoundary',false))
        fprintf(['   [TM QAM BPS routing] disabled for TPC; using the ', ...
            'normal QAM carrier loop and adaptive equalizer.\n']);
    end
    if qamBlindPhaseSearchRequested && isSplitQAM && ...
            ~qamBlindPhaseSearchEnabled && ...
            (getLogicalField(opt,'debugAdaptiveEqualizer',false) || ...
             getLogicalField(opt,'debugSynchronizationChain',false) || ...
             getLogicalField(opt,'debugCodedBoundary',false))
        fprintf(['   [TM QAM BPS routing] disabled for split I/Q; ', ...
            'using the normal QAM carrier loop.  Set ', ...
            'enableQAMBlindPhaseSearchForSplit=true only for diagnosis.\n']);
    end
    % computeBER receives OPT rather than this local routing state. Record
    % the actual decision so sparse ASM phase anchoring is enabled only when
    % BPS really processed this stream.
    opt.QAMBlindPhaseSearchActive = qamBlindPhaseSearchEnabled;
    qamPostBPSAdaptiveEqualizerEnabled = getLogicalField(opt, ...
        'enableQAMPostBPSAdaptiveEqualizer',false);
    pilotlessAPSKPostFrontEndAdaptiveEqualizerEnabled = getLogicalField( ...
        opt,'enablePilotlessAPSKPostFrontEndAdaptiveEqualizer',false);
    qamBlindPhaseInfo = struct('Applied',false, ...
        'ReliableFraction',NaN,'MedianBestMetric',NaN, ...
        'FinalCorrection_deg',NaN,'FadeHoldBlocks',0, ...
        'FadeEvents',0,'FadeRecoveries',0,'Reacquisitions',0, ...
        'InitialFrequencyRadPerSymbol',NaN);
    qamBlindPhaseState = struct( ...
        'FadeHold',false(0,1),'Centers',zeros(0,1));
    qamPowerGainInfo = struct('Applied',false, ...
        'AcceptanceRate',NaN,'FinalGainMagnitude_dB',NaN, ...
        'InverseGainMaxObserved_dB',NaN,'Regularization',NaN, ...
        'MaxInverseGainDB',NaN);
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
    elseif strcmpi(modStr,'MSK')
        % =========================================================
        % 标准 MSK：
        % 独立粗 CFO -> 原始 CPM 定时同步 -> 差分 soft metric
        %
        % 固定载波相位会在相邻符号相位差中抵消，
        % 第一版不使用 QPSK CarrierSynchronizer。
        % =========================================================

        enableCPMCoarse = getLogicalField( ...
            opt, 'enableCPMCoarseFrequencyCompensator', false);

        [coarseSynced, cfo_est] = ...
            localMSKGMSKX2CoarseCFO( ...
            rxWaveform, Fs, fSym, enableCPMCoarse);

        % Preserve the oversampled CPM waveform for the soft detector.  A
        % one-sample/symbol differential metric throws away seven of eight
        % independent phase-increment observations and is vulnerable to a
        % short amplitude notch inside one symbol.
        fineSyncedForBER = coarseSynced;
        opt.mskSoftSamplesPerSymbol = sps;

        % 当前仿真没有采样时钟漂移，只有固定分数时延。
        % 使用 MSK 专用固定输出率定时，避免 SymbolSynchronizer
        % 在长序列中随机插入或删除一个符号。
        [TimeSynced, mskTimingPhase, mskTimingScore, mskPhaseScores] = ...
            localMSKFixedRateTiming(coarseSynced, sps);

        if getLogicalField(opt,'debugMSK',false)
            fprintf(['   [MSK timing] mode=fixed-rate, phase=%d/%d, ', ...
                'score=%.6f, symbols=%d\n'], ...
                mskTimingPhase, sps, mskTimingScore, numel(TimeSynced));

            fprintf('   [MSK timing] phase scores: %s\n', ...
                mat2str(mskPhaseScores.', 5));
        end

%         TimeSynced = timingObj(coarseSynced);

        % MSK 使用相邻符号差分，不依赖固定载波相位
        fineSynced = TimeSynced;
        if getLogicalField(opt,'debugMSK',false)
            fprintf(['   [MSK coarse CFO] enabled=%d, ', ...
                'estimated=%+.3f Hz, input=%+.3f Hz\n'], ...
                enableCPMCoarse, cfo_est, cfo_val);
        end
    elseif contains(modStr,'GMSK')
        % A real H trace can carry Doppler even when the separately injected
        % test CFO is zero.  Therefore the production GMSK receiver keeps
        % the x^2 estimate enabled by default; the option is only an A/B
        % diagnostic override.
        enableGMSKCoarse = getLogicalField(opt, ...
            'enableGMSKCoarseFrequencyCompensator', true);
        [rxSynced, cfo_est] = localMSKGMSKX2CoarseCFO( ...
            rxWaveform, Fs, fSym, enableGMSKCoarse);
        gmskTrackerOpt = opt;
        % In an exactly noiseless H experiment even a very small CPM sample
        % still carries deterministic phase.  HOLD discards that phase and
        % forces the loop to coast across the fastest channel excursion.
        % Keep noisy operation conservative; this continuous mode is H-only,
        % noise-off only, and remains explicitly overridable.
        gmskNoiselessContinuousTracking = getLogicalField(opt, ...
            'enableGMSKNoiselessContinuousTracking',true) && ...
            getLogicalField(opt,'enableHChannel',false) && ...
            strcmpi(string(noiseInfo.Mode),'off');
        gmskBlindReliabilityEnabled = getLogicalField(opt, ...
            'enableBlindReliabilityManager',false) && ...
            getLogicalField(opt,'enableHChannel',false) && ...
            ~gmskNoiselessContinuousTracking;
        if gmskBlindReliabilityEnabled
            gmskReliabilityCfg = struct( ...
                'SamplesPerSymbol',sps, ...
                'WindowSymbols',getfieldnumeric(opt, ...
                    'blindReliabilityWindowSymbols',32), ...
                'AcquireSymbols',getfieldnumeric(opt, ...
                    'blindReliabilityAcquireSymbols',256), ...
                'ReferenceTauSymbols',getfieldnumeric(opt, ...
                    'blindReliabilityReferenceTauSymbols',4096), ...
                'FadeEnterDB',getfieldnumeric(opt, ...
                    'blindReliabilityFadeEnterDB',-12), ...
                'FadeExitDB',getfieldnumeric(opt, ...
                    'blindReliabilityFadeExitDB',-8), ...
                'FadeEnterWindows',getfieldnumeric(opt, ...
                    'blindReliabilityFadeEnterWindows',2), ...
                'RecoverWindows',getfieldnumeric(opt, ...
                    'blindReliabilityRecoverWindows',4), ...
                'MaxInverseGainDB',getfieldnumeric(opt, ...
                    'blindReliabilityMaxInverseGainDB',18), ...
                'Debug',getLogicalField(opt, ...
                    'debugBlindReliabilityManager',false));
            [gmskReliabilityCtrl,blindReliabilityInfo] = ...
                HelperTMBlindReliabilityManager(rxSynced,gmskReliabilityCfg);
            blindReliabilityHoldMaskFiltered = ...
                logical(gmskReliabilityCtrl.HoldMask(:));
            gmskTrackerOpt.ExternalHoldMask = ...
                blindReliabilityHoldMaskFiltered;
        end
        % Two explicitly selectable residual-Doppler implementations are
        % kept separate for strict A/B testing.  The new GMSK differential
        % phase detector feeds a second-order phase/frequency loop; when it
        % is selected the old windowed feed-forward correction is not run.
        enableGMSKSecondOrderPLL = getLogicalField( ...
            opt,'enableGMSKSecondOrderPLL',gmskNoiselessContinuousTracking);
        if gmskNoiselessContinuousTracking
            if ~isfield(gmskTrackerOpt,'gmskPLLAcquireLoopBandwidth') || ...
                    isempty(gmskTrackerOpt.gmskPLLAcquireLoopBandwidth)
                gmskTrackerOpt.gmskPLLAcquireLoopBandwidth = 0.03;
            end
            if ~isfield(gmskTrackerOpt,'gmskPLLTrackLoopBandwidth') || ...
                    isempty(gmskTrackerOpt.gmskPLLTrackLoopBandwidth)
                gmskTrackerOpt.gmskPLLTrackLoopBandwidth = 0.01;
            end
            if ~isfield(gmskTrackerOpt,'gmskPLLDetectorTauSymbols') || ...
                    isempty(gmskTrackerOpt.gmskPLLDetectorTauSymbols)
                gmskTrackerOpt.gmskPLLDetectorTauSymbols = 8;
            end
            if ~isfield(gmskTrackerOpt,'gmskPLLFadeThresholdDB') || ...
                    isempty(gmskTrackerOpt.gmskPLLFadeThresholdDB)
                gmskTrackerOpt.gmskPLLFadeThresholdDB = -100;
            end
        end
        if enableGMSKSecondOrderPLL
            [rxSynced, gmskSecondOrderPLLInfo] = ...
                HelperGMSKSecondOrderPLL(rxSynced,Fs,fSym,gmskTrackerOpt);
        else
            [rxSynced, gmskResidualTrackerInfo] = ...
                localGMSKResidualDopplerTracker( ...
                rxSynced, Fs, fSym, gmskTrackerOpt);
        end
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
        % waveform. Keep the existing 1-sps path only for plots/metrics;
        % production BER always uses the continuously tracked 8-sps path.
        gmskModeFrontend = "official-viterbi-frame-reset";
        if isfield(opt,'GMSKDetectionMode') && ~isempty(opt.GMSKDetectionMode)
            gmskModeFrontend = lower(string(opt.GMSKDetectionMode));
        end
        if strcmp(gmskModeFrontend, "official-viterbi-frame-reset")
            fineSyncedForBER = rxSynced;
        end

        fprintf(['   [GMSK coarse CFO] enabled=%d, estimated=%+.1f Hz ', ...
                 '(input=%+.1f Hz)\n'], ...
                enableGMSKCoarse, cfo_est, getf(opt,'cfo',0));
        if getLogicalField(opt,'debugGMSK',false) || ...
                getLogicalField(opt,'debugCodedBoundary',false)
            if enableGMSKSecondOrderPLL
                fprintf(['   [GMSK second-order PLL] applied=%d mode=%s ', ...
                    'locked=%d freq=%+.1f Hz range=[%+.1f,%+.1f] Hz ', ...
                    'updates=%.1f%% fadeHold=%d mean|e|=%.4g rad\n'], ...
                    gmskSecondOrderPLLInfo.Applied, ...
                    gmskSecondOrderPLLInfo.FinalMode, ...
                    gmskSecondOrderPLLInfo.Locked, ...
                    gmskSecondOrderPLLInfo.FinalFrequency_Hz, ...
                    gmskSecondOrderPLLInfo.FrequencyMin_Hz, ...
                    gmskSecondOrderPLLInfo.FrequencyMax_Hz, ...
                    100*gmskSecondOrderPLLInfo.UpdateAcceptanceRate, ...
                    gmskSecondOrderPLLInfo.FadeHoldSamples, ...
                    gmskSecondOrderPLLInfo.MeanAbsPhaseError);
            else
                fprintf(['   [GMSK residual tracker] applied=%d windows=%d ', ...
                    'accepted=%d hold=%d residual=%+.1f/%+.1f/%+.1f Hz ', ...
                    'rms=%.1f Hz confidence=%.1f dB\n'], ...
                    gmskResidualTrackerInfo.Applied, ...
                    gmskResidualTrackerInfo.WindowCount, ...
                    gmskResidualTrackerInfo.AcceptedWindows, ...
                    gmskResidualTrackerInfo.HoldWindows, ...
                    gmskResidualTrackerInfo.ResidualMin_Hz, ...
                    gmskResidualTrackerInfo.ResidualMedian_Hz, ...
                    gmskResidualTrackerInfo.ResidualMax_Hz, ...
                    gmskResidualTrackerInfo.ResidualRMS_Hz, ...
                    gmskResidualTrackerInfo.MedianConfidence_dB);
            end
        end
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

            % The UQPSK fourth-power spectrum contains residual data terms
            % because the I/Q rails are unequal.  Treating its largest peak
            % as CFO by default can create a false offset (especially when
            % the configured CFO is zero).  Keep this estimator opt-in;
            % the dedicated carrier loop and high-rate phase tracker remain
            % the normal acquisition path.
            enableUQPSKFFTCoarseCFO = getLogicalField(opt, ...
                'enableUQPSKFFTCoarseCFO', true);
            if isfield(opt,'enableUQPSKFFTCoarseCFO') && ~isempty(opt.enableUQPSKFFTCoarseCFO)
                enableUQPSKFFTCoarseCFO = logical(opt.enableUQPSKFFTCoarseCFO);
            end

            uqpskMaxCFOHz = 0.05 * fSym;   % default search: +/-5% symbol rate
            if isfield(opt,'carrierCaptureRangeHz') && ...
                    ~isempty(opt.carrierCaptureRangeHz)
                uqpskMaxCFOHz = double(opt.carrierCaptureRangeHz);
            end
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

            % UQPSK needs gain/phase tracking before the 8-to-2 sps
            % decimator.  Once a fast H-channel variation is averaged by
            % that decimator it cannot be recovered by the symbol-rate
            % carrier loop below.  Keep this path H-only so the established
            % NoH receiver remains an unchanged regression baseline.
            useUQPSKHighRateTracking = getLogicalField(opt, ...
                'enableUQPSKHighRateTracking', true) && ...
                getLogicalField(opt,'enableHChannel',false);
            % A rectangular UQPSK symbol does not have the QPSK property
            % s^4=constant: the fourth-power observation still contains
            % data modulation.  Keep the decision-free envelope tracker as
            % the production H-path default, but make the inherited QPSK
            % fourth-power phase tracker an explicit diagnostic option.
            useUQPSKFourthPowerPhaseTracking = ...
                useUQPSKHighRateTracking && getLogicalField(opt, ...
                'enableUQPSKFourthPowerHighRatePhaseTracker', false);
            useUQPSKSecondPowerPhaseTracking = ...
                useUQPSKHighRateTracking && ...
                ~useUQPSKFourthPowerPhaseTracking && ...
                getLogicalField(opt, ...
                'enableUQPSKSecondPowerHighRatePhaseTracker', false);
            uqpskHighRatePhaseMode = 'off';
            uqpskHighRateHoldMask = false(numel(coarseSynced),1);
            useUQPSKSharedReliabilityHold = getLogicalField(opt, ...
                'enableUQPSKSharedReliabilityHold',false) && ...
                getLogicalField(opt,'enableBlindReliabilityManager',false) && ...
                getLogicalField(opt,'enableHChannel',false);
            if useUQPSKSharedReliabilityHold
                uqpskReliabilityCfg = struct( ...
                    'SamplesPerSymbol',sps, ...
                    'WindowSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityWindowSymbols',32), ...
                    'AcquireSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityAcquireSymbols',256), ...
                    'ReferenceTauSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityReferenceTauSymbols',4096), ...
                    'FadeEnterDB',getfieldnumeric(opt, ...
                        'blindReliabilityFadeEnterDB',-12), ...
                    'FadeExitDB',getfieldnumeric(opt, ...
                        'blindReliabilityFadeExitDB',-8), ...
                    'FadeEnterWindows',getfieldnumeric(opt, ...
                        'blindReliabilityFadeEnterWindows',2), ...
                    'RecoverWindows',getfieldnumeric(opt, ...
                        'blindReliabilityRecoverWindows',4), ...
                    'MaxInverseGainDB',getfieldnumeric(opt, ...
                        'blindReliabilityMaxInverseGainDB',18), ...
                    'Debug',getLogicalField(opt, ...
                        'debugBlindReliabilityManager',false));
                [uqpskReliabilityCtrl,blindReliabilityInfo] = ...
                    HelperTMBlindReliabilityManager( ...
                    coarseSynced,uqpskReliabilityCfg);
                uqpskHighRateHoldMask = logical( ...
                    uqpskReliabilityCtrl.HoldMask(:));
            end
            if useUQPSKHighRateTracking
                uqpskEnvelopeTau = getfieldnumeric(opt, ...
                    'uqpskEnvelopeTauSymbols', 16);
                uqpskEnvelopeMinGainDB = getfieldnumeric(opt, ...
                    'uqpskEnvelopeMinGainDB', -40);
                uqpskEnvelopeMaxGainDB = getfieldnumeric(opt, ...
                    'uqpskEnvelopeMaxGainDB', 100);
                if ~isscalar(uqpskEnvelopeMinGainDB) || ...
                        ~isfinite(uqpskEnvelopeMinGainDB)
                    uqpskEnvelopeMinGainDB = -40;
                end
                if ~isscalar(uqpskEnvelopeMaxGainDB) || ...
                        ~isfinite(uqpskEnvelopeMaxGainDB)
                    uqpskEnvelopeMaxGainDB = 100;
                end
                uqpskEnvelopeMaxGainDB = max(uqpskEnvelopeMaxGainDB, ...
                    uqpskEnvelopeMinGainDB);
                uqpskEnvelopeCfg = struct( ...
                    'FastEnvelopeSampleRateHz',Fs, ...
                    'FastEnvelopeSamplesPerSymbol',sps, ...
                    'FastEnvelopeTauSymbols',uqpskEnvelopeTau, ...
                    'FastEnvelopeTargetPower',1, ...
                    'FastEnvelopeMinGainDB',uqpskEnvelopeMinGainDB, ...
                    'FastEnvelopeMaxGainDB',uqpskEnvelopeMaxGainDB);
                if blindReliabilityInfo.Applied && ...
                        numel(uqpskHighRateHoldMask) == numel(coarseSynced)
                    uqpskEnvelopeCfg.ExternalHoldMask = ...
                        uqpskHighRateHoldMask;
                    uqpskEnvelopeCfg.FastEnvelopeMaxGainDB = min( ...
                        uqpskEnvelopeCfg.FastEnvelopeMaxGainDB, ...
                        blindReliabilityInfo.MaxInverseGainDB);
                end
                [coarseSynced, fastEnvelopeInfo] = ...
                    HelperTMFastComplexGainTracker(coarseSynced,[], ...
                    uqpskEnvelopeCfg,'envelope');
                if useUQPSKFourthPowerPhaseTracking
                    uqpskPhaseWindowSymbols = getfieldnumeric(opt, ...
                        'uqpskHighRatePhaseWindowSymbols', 16);
                    [coarseSynced, highRatePhaseInfo] = ...
                        localFourthPowerHighRatePhaseTrack(coarseSynced, ...
                        sps, uqpskPhaseWindowSymbols);
                    uqpskHighRatePhaseMode = 'fourth-power';
                elseif useUQPSKSecondPowerPhaseTracking
                    uqpskPhaseWindowSymbols = getfieldnumeric(opt, ...
                        'uqpskHighRatePhaseWindowSymbols', 16);
                    [coarseSynced, highRatePhaseInfo] = ...
                        localSecondPowerHighRatePhaseTrack(coarseSynced, ...
                        sps, uqpskPhaseWindowSymbols);
                    uqpskHighRatePhaseMode = 'second-power';
                end
            end
            if isfield(opt,'debugUQPSK') && logical(opt.debugUQPSK)
                fprintf(['   [UQPSK front end] fftCFO=%d envelope=%d ', ...
                    'phaseMode=%s ', ...
                    'env(tau=%.0f,gain=[%.1f, %.1f] dB,applied=%d) ', ...
                    'phase(window=%.0f,conf=%.3f,hold=%d)\n'], ...
                    enableUQPSKFFTCoarseCFO, useUQPSKHighRateTracking, ...
                    uqpskHighRatePhaseMode, ...
                    getfieldnumeric(opt,'uqpskEnvelopeTauSymbols',16), ...
                    getfieldnumeric(opt,'uqpskEnvelopeMinGainDB',-40), ...
                    getfieldnumeric(opt,'uqpskEnvelopeMaxGainDB',100), ...
                    logical(fastEnvelopeInfo.Applied), ...
                    highRatePhaseInfo.WindowSymbols, ...
                    highRatePhaseInfo.MeanConfidence, ...
                    highRatePhaseInfo.HoldSamples);
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
            syncDebugStages.FilterSamplesPerSymbol = sps_after;
            if syncDebugRequested
                syncDebugStages.Filtered = filtered;
            end

            uqpskTimingLoopBW = getfieldnumeric(opt, ...
                'uqpskTimingLoopBandwidth',0.01);
            if ~isscalar(uqpskTimingLoopBW) || ...
                    ~isfinite(uqpskTimingLoopBW) || ...
                    uqpskTimingLoopBW <= 0 || uqpskTimingLoopBW > 0.2
                error('run_ccsds_tm_evaluation:InvalidUQPSKTimingBandwidth', ...
                    'uqpskTimingLoopBandwidth must be a scalar in (0, 0.2].');
            end
            timingObj = comm.SymbolSynchronizer( ...
                'TimingErrorDetector','Gardner (non-data-aided)', ...
                'SamplesPerSymbol', sps_after, ...
                'DetectorGain', 2.7, ...
                'Modulation','PAM/PSK/QAM', ...
                'DampingFactor', 1/sqrt(2), ...
                'NormalizedLoopBandwidth', uqpskTimingLoopBW);

            TimeSynced = timingObj(filtered);
            if blindReliabilityInfo.Applied && ~isempty(TimeSynced) && ...
                    ~isempty(uqpskHighRateHoldMask)
                uqpskHoldIndex = round(linspace(1, ...
                    numel(uqpskHighRateHoldMask),numel(TimeSynced)));
                uqpskHoldIndex = min(max(uqpskHoldIndex,1), ...
                    numel(uqpskHighRateHoldMask));
                uqpskSymbolHold = uqpskHighRateHoldMask(uqpskHoldIndex);
                % Protect the resampling edge on each side of a HOLD event.
                uqpskSymbolHold = conv(double(uqpskSymbolHold(:)), ...
                    ones(3,1),'same') > 0;
                blindReliabilityHoldMaskSymbols = uqpskSymbolHold;
            end
            if syncDebugRequested
                syncDebugStages.Timing = TimeSynced;
            end
            % SymbolSynchronizer consumes the 2-sps stream and emits one
            % timing-corrected sample per symbol.  The common blind helper
            % is intentionally symbol-rate, so it receives this 1-sps
            % output after the UQPSK carrier loop below.
            if ~isempty(TimeSynced)
                timingPower = mean(abs(TimeSynced).^2);
                if isfinite(timingPower) && timingPower > eps
                    % The UQPSK phase detector is amplitude dependent.  A
                    % H path can leave the 2-sps timing output tens of dB
                    % below nominal even after the high-rate tracker; make
                    % the carrier-loop error scale invariant.
                    TimeSynced = TimeSynced / sqrt(timingPower);
                end
            end

            uqpskCarrierLoopBW = 0.002;
            if isfield(opt,'uqpskCarrierLoopBW') && ~isempty(opt.uqpskCarrierLoopBW)
                uqpskCarrierLoopBW = double(opt.uqpskCarrierLoopBW);
            end

            uqpskCarrierOpt = opt;
            if blindReliabilityInfo.Applied && ...
                    numel(blindReliabilityHoldMaskSymbols) == numel(TimeSynced)
                uqpskCarrierOpt.ExternalHoldMask = ...
                    blindReliabilityHoldMaskSymbols;
            end
            [fineSynced, uqpskCarrierPLLInfo] = uqpskCarrierRecover( ...
                TimeSynced, 2, uqpskCarrierLoopBW,uqpskCarrierOpt,fSym);
            if getLogicalField(opt,'debugUQPSK',false)
                fprintf(['   [UQPSK carrier PLL] dual=%d mode=%s locked=%d ', ...
                    'BW(acq/track)=%.4g/%.4g finalFreq=%+.2f Hz ', ...
                    'locks=%d reacq=%d fadeHold=%d extHold=%d/%d ', ...
                    'accept=%.1f%% ', ...
                    'mean|e|=%.4g\n'], ...
                    uqpskCarrierPLLInfo.DualBandwidth, ...
                    uqpskCarrierPLLInfo.FinalMode, ...
                    uqpskCarrierPLLInfo.Locked, ...
                    uqpskCarrierPLLInfo.AcquireLoopBW, ...
                    uqpskCarrierPLLInfo.TrackLoopBW, ...
                    uqpskCarrierPLLInfo.FinalFrequency_Hz, ...
                    uqpskCarrierPLLInfo.LockTransitions, ...
                    uqpskCarrierPLLInfo.Reacquisitions, ...
                    uqpskCarrierPLLInfo.FadeHoldSymbols, ...
                    uqpskCarrierPLLInfo.ExternalHoldSymbols, ...
                    uqpskCarrierPLLInfo.ExternalHoldMaskProvided, ...
                    100*uqpskCarrierPLLInfo.UpdateAcceptanceRate, ...
                    uqpskCarrierPLLInfo.MeanAbsPhaseError);
            end
            if syncDebugRequested
                syncDebugStages.Carrier = fineSynced;
            end

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
            useOQPSKHighRateTracking = getLogicalField(opt, ...
                'enableOQPSKHighRateTracking', true) && ...
                getLogicalField(opt,'enableHChannel',false);
            if useOQPSKHighRateTracking
                oqpskEnvelopeTau = getfieldnumeric(opt, ...
                    'oqpskEnvelopeTauSymbols', 16);
                [coarseSynced, fastEnvelopeInfo] = ...
                    HelperTMFastComplexGainTracker(coarseSynced,[],struct( ...
                    'FastEnvelopeSampleRateHz',Fs, ...
                    'FastEnvelopeSamplesPerSymbol',sps, ...
                    'FastEnvelopeTauSymbols',oqpskEnvelopeTau, ...
                    'FastEnvelopeTargetPower',1, ...
                    'FastEnvelopeMinGainDB',-30, ...
                    'FastEnvelopeMaxGainDB',30),'envelope');
                oqpskPhaseWindowSymbols = getfieldnumeric(opt, ...
                    'oqpskHighRatePhaseWindowSymbols', 16);
                [coarseSynced, highRatePhaseInfo] = ...
                    localFourthPowerHighRatePhaseTrack(coarseSynced, ...
                    sps, oqpskPhaseWindowSymbols);
            end
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
            % Common ordinary-TM path for BPSK / QPSK / 8PSK / APSK.
            % FACM was returned above and retains its independent FLL/pilot
            % acquisition chain. When enabled, APSK reuses the QAM coarse
            % estimator; the option remains explicit for A/B debugging.
            useCoarseFreqSync = true;
            if contains(modStr,'APSK')
                if usePilotlessAPSKFrontEnd
                    % The pilotless adapter owns x^4 coarse acquisition.
                    % Do not pre-rotate it with the generic QAM estimator.
                    useCoarseFreqSync = false;
                end
                if isfield(opt,'enableAPSKCoarseFrequencyCompensator') && ...
                        ~isempty(opt.enableAPSKCoarseFrequencyCompensator) && ...
                        ~usePilotlessAPSKFrontEnd
                    useCoarseFreqSync = localFlagValue(opt.enableAPSKCoarseFrequencyCompensator);
                end
            end

            if useCoarseFreqSync
                coarseFreqSync = comm.CoarseFrequencyCompensator( ...
                    'Modulation', coarseMod, ...
                    'SampleRate', Fs, ...
                    'FrequencyResolution', 1e3);
                [coarseSynced, cfo_est] = coarseFreqSync(rxWaveform);
                syncDebugStages.CoarseEstimate_Hz = cfo_est;
                if getLogicalField(opt, 'debugCarrierRecovery', false)
                    fprintf(['   [TM coarse CFO] modulation=%s, ', ...
                        'estimated=%+.3f Hz, configured=%+.3f Hz\n'], ...
                        coarseMod, cfo_est, cfo_val);
                end
            else
                coarseSynced = rxWaveform;
                cfo_est = 0;
            end

            rxFilterDecimationFactor = sps/2;
            rxfilter = comm.RaisedCosineReceiveFilter( ...
                'RolloffFactor', rolloff, ...
                'InputSamplesPerSymbol', sps, ...
                'DecimationFactor', rxFilterDecimationFactor);

            filtered = rxfilter(coarseSynced);
            sps_after = sps / rxFilterDecimationFactor;
            syncDebugStages.FilterSamplesPerSymbol = sps_after;
            if syncDebugRequested
            syncDebugStages.Filtered = filtered;
            end

            % One blind, pre-normalization reliability observation is shared
            % by the downstream adaptive stages.  It uses only received
            % relative power: no H, pilots, ASM, transmitted bits, or FEC
            % outcome.  The feature is opt-in until the normalized-H A/B
            % regression is complete, so existing production behaviour is
            % unchanged when the option is absent.
            blindReliabilityEnabled = getLogicalField(opt, ...
                'enableBlindReliabilityManager',false) && ...
                getLogicalField(opt,'enableHChannel',false) && ...
                localIsAdaptiveEqualizerMode(adaptiveEqMode) && ...
                localSupportsTMBlindAdaptiveModulation(modStr);
            if blindReliabilityEnabled
                reliabilityCfg = struct( ...
                    'SamplesPerSymbol',sps_after, ...
                    'WindowSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityWindowSymbols',32), ...
                    'AcquireSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityAcquireSymbols',256), ...
                    'ReferenceTauSymbols',getfieldnumeric(opt, ...
                        'blindReliabilityReferenceTauSymbols',4096), ...
                    'FadeEnterDB',getfieldnumeric(opt, ...
                        'blindReliabilityFadeEnterDB',-12), ...
                    'FadeExitDB',getfieldnumeric(opt, ...
                        'blindReliabilityFadeExitDB',-8), ...
                    'FadeEnterWindows',getfieldnumeric(opt, ...
                        'blindReliabilityFadeEnterWindows',2), ...
                    'RecoverWindows',getfieldnumeric(opt, ...
                        'blindReliabilityRecoverWindows',4), ...
                    'MaxInverseGainDB',getfieldnumeric(opt, ...
                        'blindReliabilityMaxInverseGainDB',18), ...
                    'Debug',getLogicalField(opt, ...
                        'debugBlindReliabilityManager',false));
                [blindReliabilityCtrl,blindReliabilityInfo] = ...
                    HelperTMBlindReliabilityManager(filtered,reliabilityCfg);
                blindReliabilityHoldMaskFiltered = ...
                    logical(blindReliabilityCtrl.HoldMask(:));
            end

            % Fixed internal front-end power tracking for H-channel blind
            % mode.  The slow envelope estimate is decision free and is
            % also used for QAM/APSK so Gardner does not see a wildly
            % time-varying amplitude.  The faster complex phase/gain loop
            % below remains limited to constant-envelope PSK; a scalar
            % nearest-point loop can lock a multi-ring signal to the wrong
            % radius during acquisition.
            useFastEnvelopePath = getLogicalField(opt,'enableHChannel',false) && ...
                localIsAdaptiveEqualizerMode(adaptiveEqMode) && ...
                localSupportsTMBlindAdaptiveModulation(modStr) && ...
                getLogicalField(opt,'enableAdaptiveFastEnvelopeTracker',true) && ...
                ~usePilotlessAPSKFrontEnd && ...
                ~qamBlindPhaseSearchEnabled;
            useConstantEnvelopePath = useFastEnvelopePath && ...
                any(strcmpi(string(modStr),["BPSK","QPSK","8PSK"]));
            useFastComplexPath = useConstantEnvelopePath;
            useFastPhasePath = useFastEnvelopePath && ...
                ~useConstantEnvelopePath && ...
                getLogicalField(opt,'enableAdaptiveFastPhaseTracker',true) && ...
                ~qamBlindPhaseSearchEnabled;
            if useFastEnvelopePath
                defaultEnvelopeTauSymbols = 64;
                % Keep production/release behaviour unchanged.  The new
                % robust-block estimator is an explicit diagnostic mode
                % until it passes the full time-varying H matrix.
                defaultEnvelopeEstimatorMode = "iir";
                if useConstantEnvelopePath
                    defaultEnvelopeTauSymbols = 16;
                    defaultEnvelopeEstimatorMode = "iir";
                end
                envelopeEstimatorMode = lower(strtrim(string( ...
                    getfieldwithdefault(opt, ...
                    'adaptiveFastEnvelopeEstimatorMode','auto'))));
                if envelopeEstimatorMode == "auto"
                    envelopeEstimatorMode = defaultEnvelopeEstimatorMode;
                end
                if ~any(envelopeEstimatorMode == ["iir","robust-block"])
                    error('run_ccsds_tm_evaluation:InvalidFastEnvelopeEstimator', ...
                        ['adaptiveFastEnvelopeEstimatorMode must be ', ...
                         '''auto'', ''iir'', or ''robust-block''.']);
                end
                envelopeTauSymbols = getfieldnumeric(opt, ...
                    'adaptiveFastEnvelopeTauSymbols', ...
                    defaultEnvelopeTauSymbols);
                if ~isscalar(envelopeTauSymbols) || ...
                        ~isfinite(envelopeTauSymbols) || ...
                        envelopeTauSymbols <= 0
                    error('run_ccsds_tm_evaluation:InvalidFastEnvelopeTau', ...
                        ['adaptiveFastEnvelopeTauSymbols must be a ', ...
                         'finite positive scalar.']);
                end
                envelopeMinGainDB = getfieldnumeric(opt, ...
                    'adaptiveFastEnvelopeMinGainDB', -40);
                envelopeMaxGainDB = getfieldnumeric(opt, ...
                    'adaptiveFastEnvelopeMaxGainDB', 100);
                if ~isscalar(envelopeMinGainDB) || ...
                        ~isfinite(envelopeMinGainDB) || ...
                        ~isscalar(envelopeMaxGainDB) || ...
                        ~isfinite(envelopeMaxGainDB) || ...
                        envelopeMaxGainDB < envelopeMinGainDB
                    error('run_ccsds_tm_evaluation:InvalidFastEnvelopeGainLimits', ...
                        ['adaptiveFastEnvelopeMinGainDB and ', ...
                         'adaptiveFastEnvelopeMaxGainDB must be finite ', ...
                         'scalars with max >= min.']);
                end
                envelopeCfg = struct( ...
                    'FastEnvelopeSampleRateHz',Fs/rxFilterDecimationFactor, ...
                    'FastEnvelopeSamplesPerSymbol',sps_after, ...
                    'FastEnvelopeEstimatorMode',char(envelopeEstimatorMode), ...
                    'FastEnvelopeTauSymbols',envelopeTauSymbols, ...
                    'FastEnvelopeTargetPower',1, ...
                    'FastEnvelopeMinGainDB',envelopeMinGainDB, ...
                    'FastEnvelopeMaxGainDB',envelopeMaxGainDB);
                if blindReliabilityInfo.Applied
                    envelopeCfg.ExternalHoldMask = ...
                        blindReliabilityHoldMaskFiltered;
                    envelopeCfg.FastEnvelopeMaxGainDB = min( ...
                        envelopeCfg.FastEnvelopeMaxGainDB, ...
                        blindReliabilityInfo.MaxInverseGainDB);
                end
                if envelopeEstimatorMode == "iir"
                    % Preserve the original constant-envelope PSK response.
                else
                    % Keep the original unit-power operating point used to
                    % calibrate Gardner/carrier loop gains.  Only the received
                    % power estimator changes: it now averages constellation
                    % activity instead of reacting to individual ring samples.
                    envelopeCfg.FastEnvelopeBlockSymbols = getfieldnumeric( ...
                        opt,'adaptiveFastEnvelopeBlockSymbols',256);
                    envelopeCfg.FastEnvelopeHopSymbols = getfieldnumeric( ...
                        opt,'adaptiveFastEnvelopeHopSymbols',64);
                    envelopeCfg.FastEnvelopeMedianBlocks = getfieldnumeric( ...
                        opt,'adaptiveFastEnvelopeMedianBlocks',3);
                    envelopeCfg.FastEnvelopeTrimFraction = getfieldnumeric( ...
                        opt,'adaptiveFastEnvelopeTrimFraction',0.05);
                    envelopeCfg.FastEnvelopeGainSlewDBPerSymbol = ...
                        getfieldnumeric(opt, ...
                        'adaptiveFastEnvelopeGainSlewDBPerSymbol',0.05);
                end
                [filtered, fastEnvelopeInfo] = ...
                    HelperTMFastComplexGainTracker(filtered,[], ...
                    envelopeCfg,'envelope');
                if syncDebugRequested
                    syncDebugStages.Filtered = filtered;
                end
                if getLogicalField(opt,'debugAdaptiveEqualizer',false)
                    fprintf(['   [TM fast envelope] applied=%d mode=%s ', ...
                        'tau=%.1f block=%.1f hop=%.1f sym ', ...
                        'gain=%+.2f dB range=[%+.2f,%+.2f] dB\n'], ...
                        fastEnvelopeInfo.Applied, ...
                        fastEnvelopeInfo.EstimatorMode, ...
                        fastEnvelopeInfo.TauSymbols, ...
                        fastEnvelopeInfo.BlockSymbols, ...
                        fastEnvelopeInfo.HopSymbols, ...
                        fastEnvelopeInfo.FinalMagnitude_dB, ...
                        fastEnvelopeInfo.GainMin_dB, ...
                        fastEnvelopeInfo.GainMax_dB);
                end
            end

            SyncMod = 'PAM/PSK/QAM';
            Kp = 1/(pi*(1-((rolloff^2)/4))) * cos(pi*rolloff/2);

            defaultTimingLoopBandwidth = 0.01;
            if contains(modStr,'APSK')
                % At the unit-power operating point used by the H-channel
                % envelope tracker, 0.01 turns APSK ring-power variation
                % into Gardner timing jitter.  A narrower loop preserves
                % acquisition while avoiding the deterministic EVM floor.
                defaultTimingLoopBandwidth = 0.005;
            end
            timingLoopBandwidth = getfieldnumeric( ...
                opt, 'timingLoopBandwidth', defaultTimingLoopBandwidth);
            protectHPSKTiming = getLogicalField(opt, ...
                'enableHChannelPSKTimingProtection',true) && ...
                getLogicalField(opt,'enableHChannel',false) && ...
                any(strcmpi(string(modStr),["BPSK","QPSK","8PSK"]));
            if protectHPSKTiming
                % The scalar H path changes amplitude and phase but not the
                % physical symbol clock.  A wide Gardner loop can therefore
                % convert a deep-fade transient into a permanent symbol
                % boundary error, most visibly for the longer BPSK record.
                % Cap only the H-channel PSK path; static/no-H operation and
                % OQPSK/UQPSK dedicated timing chains remain untouched.
                hPSKTimingMax = getfieldnumeric(opt, ...
                    'hChannelPSKTimingLoopBandwidthMax',0.005);
                if ~isscalar(hPSKTimingMax) || ...
                        ~isfinite(hPSKTimingMax) || ...
                        hPSKTimingMax <= 0 || hPSKTimingMax > 0.2
                    error('run_ccsds_tm_evaluation:InvalidHPSKTimingBandwidth', ...
                        ['hChannelPSKTimingLoopBandwidthMax must be a ', ...
                         'scalar in (0, 0.2].']);
                end
                timingLoopBandwidth = min(timingLoopBandwidth,hPSKTimingMax);
            end
            if ~isscalar(timingLoopBandwidth) || ...
                    ~isfinite(timingLoopBandwidth) || ...
                    timingLoopBandwidth <= 0 || timingLoopBandwidth > 0.2
                error('run_ccsds_tm_evaluation:InvalidTimingLoopBandwidth', ...
                    'timingLoopBandwidth must be a scalar in (0, 0.2].');
            end
            timingCfg = struct( ...
                'SamplesPerSymbol',sps_after, ...
                'DetectorGain',Kp, ...
                'Modulation',SyncMod, ...
                'NormalizedLoopBandwidth',timingLoopBandwidth, ...
                'ChunkSizeSamples',50000);
            [TimeSynced, timingChunkInfo] = ...
                HelperTMSymbolSynchronizerChunked(filtered,timingCfg);
            if blindReliabilityInfo.Applied && ~isempty(TimeSynced)
                % Gardner changes the sample count, so carry the common
                % pre-envelope state to the 1-sps stream by time position.
                % A one-input-sample dilation protects the transition edges
                % without introducing a separate mask-resampler helper.
                nReliabilityInput = numel(blindReliabilityHoldMaskFiltered);
                nReliabilityOutput = numel(TimeSynced);
                expandedHold = conv( ...
                    double(blindReliabilityHoldMaskFiltered), ...
                    ones(3,1),'same') > 0;
                reliabilityIndex = round( ...
                    ((1:nReliabilityOutput).'-0.5) * ...
                    nReliabilityInput/nReliabilityOutput + 0.5);
                reliabilityIndex = min(nReliabilityInput, ...
                    max(1,reliabilityIndex));
                blindReliabilityHoldMaskSymbols = ...
                    expandedHold(reliabilityIndex);
            else
                blindReliabilityHoldMaskSymbols = ...
                    false(numel(TimeSynced),1);
            end
            if syncDebugRequested
                syncDebugStages.Timing = TimeSynced;
                if getLogicalField(opt,'debugSynchronizationChain',false)
                    fprintf(['   [TM timing] chunks=%d input=%d output=%d ', ...
                        'rateError=%+.1f ppm\n'], ...
                        timingChunkInfo.NumChunks, ...
                        timingChunkInfo.InputSamples, ...
                        timingChunkInfo.OutputSamples, ...
                        timingChunkInfo.RateError_ppm);
                end
            end

            if contains(modStr,'APSK')
                fineLoopBW = 0.001;
            elseif contains(modStr,'8PSK') || contains(modStr,'QAM')
                fineLoopBW = 0.005;
            else
                fineLoopBW = 0.01;
            end
            fineLoopBW = getfieldnumeric( ...
                opt, 'carrierLoopBandwidth', fineLoopBW);
            if ~isscalar(fineLoopBW) || ~isfinite(fineLoopBW) || ...
                    fineLoopBW <= 0 || fineLoopBW > 0.2
                error('run_ccsds_tm_evaluation:InvalidCarrierLoopBandwidth', ...
                    'carrierLoopBandwidth must be a scalar in (0, 0.2].');
            end
            if getLogicalField(opt, 'debugCarrierRecovery', false)
                fprintf('   [TM carrier] normalized loop bandwidth=%.6g\n', ...
                    fineLoopBW);
            end

            if contains(modStr,'4D-8PSK-TCM')
                carrierSync = comm.CarrierSynchronizer( ...
                    'Modulation','8PSK', ...
                    'SamplesPerSymbol',1, ...
                    'DampingFactor',1/sqrt(2), ...
                    'NormalizedLoopBandwidth',fineLoopBW);
            elseif contains(modStr,'APSK')
                if usePilotlessAPSKFrontEnd
                    % External pilotless adapter runs immediately after
                    % Gardner and returns the symbol stream to the main
                    % demapper/FEC boundary.
                    carrierSync = [];
                else
                    useAPSKQAMCarrierSync = abs(getf(opt,'cfo',0)) > 0 || ...
                        abs(getf(opt,'phaseOffset',0)) > 0 || ...
                        (getLogicalField(opt,'enableHChannel',false) && ...
                         localIsAdaptiveEqualizerMode(adaptiveEqMode));
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
                            'NormalizedLoopBandwidth',fineLoopBW);
                    else
                        carrierSync = [];
                    end
                end
            elseif contains(modStr,'QAM')
                if qamBlindPhaseSearchEnabled
                    % The feed-forward BPS stage below owns fine carrier
                    % phase.  Do not cascade a decision-directed QAM PLL
                    % before it, because quadrant slips are invisible to a
                    % pi/2-symmetric blind estimator after the fact.
                    carrierSync = [];
                else
                    carrierSync = comm.CarrierSynchronizer( ...
                        'Modulation','QAM', ...
                        'SamplesPerSymbol',1, ...
                        'DampingFactor',1/sqrt(2), ...
                        'NormalizedLoopBandwidth',fineLoopBW);
                end
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
            if usePilotlessAPSKFrontEnd
                pilotlessOpt = opt;
                if blindReliabilityInfo.Applied
                    pilotlessOpt.BlindReliabilityExternalHoldMask = ...
                        blindReliabilityHoldMaskSymbols;
                    pilotlessOpt.blindReliabilityMaxInverseGainDB = ...
                        blindReliabilityInfo.MaxInverseGainDB;
                end
                [fineSynced,pilotlessAPSKInfo] = ...
                    HelperTMAPSKPilotlessFrontEnd( ...
                    fineSynced,char(modStr),pilotlessOpt);
            end
            % After several consistent post-fade observations the
                    % new phase is established evidence, not a noisy loop
                    % error.  Re-anchor in one step; slow 25%% slewing made
                    % one physical fade contaminate many later blocks.
            if qamBlindPhaseSearchEnabled
                qamBPSOpt = struct( ...
                    'NumTestPhases',61, ...
                    'WindowSymbols',33, ...
                    'HopSymbols',4, ...
                    'MetricPowerWindowSymbols',33, ...
                    'MinConfidence',0.02, ...
                    'FadeThresholdDB',-22, ...
                    'EnableFadeHold',true, ...
                    'FadeEnterDB',-10, ...
                    'FadeExitDB',-7, ...
                    'FadeEnterBlocks',2, ...
                    'FadeRecoverBlocks',4, ...
                    'FadeArmReliableBlocks',4, ...
                    'TrajectoryAlpha',0.85, ...
                    'FrequencyAlpha',0.20, ...
                    'MaxInnovationRad',deg2rad(35), ...
                    'ReacquireReliableBlocks',4, ...
                    'EnableInitialFrequencyEstimate',true, ...
                    'InitialFrequencyBlocks',64, ...
                    'PreserveFrequencyOnReacquire',true, ...
                    'ReacquirePhaseAlpha',1.0, ...
                    'ReacquireConsistencyRad',deg2rad(12), ...
                    'PreserveInitialPhase',false, ...
                    'MaxFrequencyRadPerSymbol',0.05, ...
                    ... % Low power alone does not prove phase is unobservable.
                    'ReliableMetricOverridesFadeHold',true, ...
                    ... % 0.05*dmin^2 equals 0.02 for normalized 16QAM,
                    ... % but scales correctly for 32QAM/APSK.
                    'FadeOverrideMaxMetricFraction',0.05, ...
                    'FadeOverrideMinConfidence',0.20, ...
                    'FadeOverrideRecoverBlocks',16);
                if isfield(opt,'QAMBlindPhaseSearch') && ...
                        isstruct(opt.QAMBlindPhaseSearch)
                    qamNames = fieldnames(opt.QAMBlindPhaseSearch);
                    for qamFieldIndex = 1:numel(qamNames)
                        qamBPSOpt.(qamNames{qamFieldIndex}) = ...
                            opt.QAMBlindPhaseSearch.(qamNames{qamFieldIndex});
                    end
                end
                if blindReliabilityInfo.Applied
                    qamBPSOpt.ExternalHoldMask = ...
                        blindReliabilityHoldMaskSymbols;
                end
                qamBPSOpt.Debug = getLogicalField(opt, ...
                    'debugAdaptiveEqualizer',false);
                [fineSynced,qamBlindPhaseState,qamBlindPhaseInfo] = ...
                    HelperTMFeedforwardBlindPhaseSearch( ...
                    fineSynced,getReferenceConstellation(modStr),qamBPSOpt);
            end
            % Scalar QAM magnitude tracking is independent of BPS.  In
            % particular, TPC intentionally disables BPS because its highly
            % structured product-code stream can bias the phase metric.  The
            % old nesting also disabled the unrelated magnitude tracker and
            % left the large radial EVM seen in normalized-H TPC sweeps.
            if contains(upper(string(modStr)),'QAM') && ...
                    getLogicalField(opt,'enableQAMPowerGainTracker',true)
                % QAM has intrinsic multi-level amplitude.  A short raw-power
                % window mistakes a structured TPC symbol sequence for channel
                % fading (even in NoH).  Use gated nearest-symbol amplitude
                % observations; the independent envelope tracker remains
                % responsible for decision-free fade acquisition.
                qamGainOpt = struct( ...
                    'MagnitudeEstimationMode','decision', ...
                    'UpdatePowerReference',false, ...
                    'FadePowerTauSymbols',16, ...
                    'FadeReferenceTauSymbols',4096, ...
                    'EnableFadeHold',true, ...
                    'FadeEnterDB',-10, ...
                    'FadeExitDB',-6, ...
                    'HoldEnterBadSymbols',8, ...
                    'RecoverGoodSymbols',4, ...
                    'Regularization',0, ...
                    'MaxInverseGainDB',40, ...
                    'PowerReference',1, ...
                    'NormalizeInputPower',true, ...
                    'TrackMagnitude',true, ...
                    'TrackPhase',false);
                % A single magnitude estimator is not optimal for both QAM
                % constellations under a scalar, rapidly varying H.  The
                % denser 32QAM ring set can make a per-symbol ring-directed
                % estimate jump into the wrong scale basin; a 32-symbol
                % power average is stable on the validated std7 profile.
                % 16QAM has wider ring separation and benefits from the
                % faster ring-directed estimate.  Keep NoH and TPC on the
                % established decision-directed baseline.
                if getLogicalField(opt,'enableHChannel',false) && ~isTPCQAM
                    if strcmpi(strtrim(string(modStr)),'16QAM')
                        qamGainOpt.MagnitudeEstimationMode = 'ring-directed';
                        qamGainOpt.FadePowerTauSymbols = 16;
                        qamGainOpt.TrackPowerMagnitudeDuringFade = true;
                    elseif strcmpi(strtrim(string(modStr)),'32QAM')
                        qamGainOpt.MagnitudeEstimationMode = 'power';
                        qamGainOpt.FadePowerTauSymbols = 32;
                        qamGainOpt.TrackPowerMagnitudeDuringFade = true;
                    end
                end
                if isfield(opt,'QAMPowerGainTracker') && ...
                        isstruct(opt.QAMPowerGainTracker)
                    qamNames = fieldnames(opt.QAMPowerGainTracker);
                    for qamFieldIndex = 1:numel(qamNames)
                        qamGainOpt.(qamNames{qamFieldIndex}) = ...
                            opt.QAMPowerGainTracker.(qamNames{qamFieldIndex});
                    end
                end
                if blindReliabilityInfo.Applied
                    qamGainOpt.ExternalHoldMask = ...
                        blindReliabilityHoldMaskSymbols;
                    qamGainOpt.MaxInverseGainDB = min( ...
                        qamGainOpt.MaxInverseGainDB, ...
                        blindReliabilityInfo.MaxInverseGainDB);
                end
                qamGainOpt.Debug = getLogicalField(opt, ...
                    'debugAdaptiveEqualizer',false);
                [fineSynced,~,qamPowerGainInfo] = ...
                    HelperTMComplexGainTracker( ...
                    fineSynced,getReferenceConstellation(modStr),qamGainOpt);
            end
            if contains(upper(string(modStr)),'QAM') && ...
                    getLogicalField(opt,'debugAdaptiveEqualizer',false)
                fprintf(['   [TM QAM front-end] BPS=%d reliable=%.2f%% ', ...
                    'metric=%.5g finalPhase=%+.2f deg ', ...
                    'powerGain=%d inverseMax=%+.2f dB\n'], ...
                    qamBlindPhaseInfo.Applied, ...
                    100*qamBlindPhaseInfo.ReliableFraction, ...
                    qamBlindPhaseInfo.MedianBestMetric, ...
                    qamBlindPhaseInfo.FinalCorrection_deg, ...
                    qamPowerGainInfo.Applied, ...
                    qamPowerGainInfo.InverseGainMaxObserved_dB);
            end
            if syncDebugRequested
                syncDebugStages.Carrier = fineSynced;
            end
        end
    end
    if ~exist('fineSyncedForBER','var')
        fineSyncedForBER = fineSynced;
    end

    % Ordinary-TM APSK pilots are receiver-observable training symbols.
    % Correct the time-varying complex gain and remove them before the
    % decision-directed equalizer. Running DD-NLMS first would treat the
    % QPSK pilot sequence as APSK payload and contaminate its updates.
    tmAPSKPilotInfo = localEmptyTMAPSKPilotInfo();
    if contains(modStr,'APSK') && getLogicalField(opt, 'HasTMAPSKPilots', false) && ...
            exist('fineSynced','var') && ~isempty(fineSynced)
        [fineSynced, tmAPSKPilotInfo, pilotInputData] = ...
            localCorrectAndRemoveTMAPSKPilots(fineSynced, opt, fSym);
        fineSyncedForBER = fineSynced;
        if syncDebugRequested
            syncDebugStages.PilotInput = pilotInputData;
            syncDebugStages.Pilot = fineSynced;
            fprintf(['   [TM APSK pilot diagnostics] applied=%d start=%d ', ...
                'pilots=%d corrRatio=%.3f cfo=%+.3f Hz meanAmp=%.4g ', ...
                'fade=%.2f%% maxGain=%+.2f dB noiseVar=%.4g mode=%s\n'], ...
                tmAPSKPilotInfo.Applied,tmAPSKPilotInfo.Start, ...
                tmAPSKPilotInfo.NumPilots,tmAPSKPilotInfo.CorrRatio, ...
                tmAPSKPilotInfo.CFO_Hz,tmAPSKPilotInfo.MeanAmp, ...
                100*tmAPSKPilotInfo.FadeFraction, ...
                tmAPSKPilotInfo.MaxAppliedGain_dB, ...
                tmAPSKPilotInfo.PilotNoiseVariance, ...
                tmAPSKPilotInfo.CorrectionMode);
        end
    end

    if useFastComplexPath && exist('fineSynced','var') && ~isempty(fineSynced)
        fastComplexOpt = struct( ...
            'FastComplexGainStep',0.05, ...
            'FastComplexGainDecisionGate',0.60, ...
            'FastComplexGainMaxMagnitudeDB',24);
        if blindReliabilityInfo.Applied && ...
                numel(blindReliabilityHoldMaskSymbols) == numel(fineSynced)
            fastComplexOpt.ExternalHoldMask = ...
                blindReliabilityHoldMaskSymbols;
        end
        [fineSynced, fastComplexGainInfo] = ...
            HelperTMFastComplexGainTracker(fineSynced, ...
            getReferenceConstellation(modStr),fastComplexOpt,'complex');
        if syncDebugRequested
            syncDebugStages.PreEQTracker = fineSynced;
        end
        if getLogicalField(opt,'debugAdaptiveEqualizer',false)
            fprintf(['   [TM fast complex gain] applied=%d gain=%+.2f dB ', ...
                'phase=%+.2f deg accept=%.1f%% DD-MSE=%.4g\n'], ...
                fastComplexGainInfo.Applied, ...
                fastComplexGainInfo.FinalMagnitude_dB, ...
                fastComplexGainInfo.FinalPhase_deg, ...
                100*fastComplexGainInfo.AcceptanceRate, ...
                fastComplexGainInfo.DDMSE);
        end
    elseif useFastPhasePath && exist('fineSynced','var') && ~isempty(fineSynced)
        fastPhaseOpt = struct( ...
            'FastPhaseStep',0.08, ...
            'FastPhaseFrequencyStep',0.002, ...
            'FastPhaseDecisionGate',0.35);
        if blindReliabilityInfo.Applied && ...
                numel(blindReliabilityHoldMaskSymbols) == numel(fineSynced)
            fastPhaseOpt.ExternalHoldMask = ...
                blindReliabilityHoldMaskSymbols;
        end
        [fineSynced, fastComplexGainInfo] = ...
            HelperTMFastComplexGainTracker(fineSynced, ...
            getReferenceConstellation(modStr),fastPhaseOpt,'phase');
        if syncDebugRequested
            syncDebugStages.PreEQTracker = fineSynced;
        end
        if getLogicalField(opt,'debugAdaptiveEqualizer',false)
            fprintf(['   [TM fast phase] phase=%+.2f deg ', ...
                'accept=%.1f%% DD-MSE=%.4g\n'], ...
                fastComplexGainInfo.FinalPhase_deg, ...
                100*fastComplexGainInfo.AcceptanceRate, ...
                fastComplexGainInfo.DDMSE);
        end
    end

    % ===== CMA 盲启动 + 复数 DD-NLMS 跟踪 =====
    % One ordinary-TM blind-equalizer stage follows timing/carrier recovery
    % (and APSK pilot removal). UQPSK joins this common stage only after its
    % dedicated 2-sps RRC/Gardner/carrier path has produced a 1-sps stream;
    % OQPSK and CPM paths retain their rail/continuous-phase semantics.
    adaptiveEqInfo = localEmptyTMAdaptiveEqualizerInfo();
    uqpskPostCarrierEQEnabled = getLogicalField(opt, ...
        'enableUQPSKPostCarrierAdaptiveEqualizer', true);
    if localIsAdaptiveEqualizerMode(adaptiveEqMode)
        adaptiveEqInfo.Mode = char(adaptiveEqMode);
        if localIsASMTrainingEqualizerMode(adaptiveEqMode)
            [asmModeSupported,asmModeReason] = ...
                localSupportsASMTrainingEqualizer(modStr,codeStr,opt,hasASM);
            if asmModeSupported && exist('fineSynced','var') && ...
                    ~isempty(fineSynced)
                asmBitsForTraining = localTMASM(opt,codeStr);
                asmPeriodBits = localASMPeriodBits(modStr,codeStr,opt);
                [fineSynced,~,adaptiveEqInfo] = ...
                    HelperTMASMTrainingEqualizer(fineSynced, ...
                    asmBitsForTraining,modStr,asmPeriodBits,opt);
                adaptiveEqInfo.Mode = char(adaptiveEqMode);
                fineSyncedForBER = fineSynced;
                if syncDebugRequested
                    syncDebugStages.Equalizer = fineSynced;
                end
                if getLogicalField(opt,'debugAdaptiveEqualizer',false)
                    fprintf(['   [TM ASM-training EQ] modulation=%s ', ...
                        'ASM=%d score=%.4f->%.4f taps=%d ', ...
                        'train=%d DDaccept=%.1f%% outputAccepted=%d ', ...
                        'reason=%s\n'], ...
                        char(modStr),getfieldnumeric(adaptiveEqInfo, ...
                        'ASMCount',0),getfieldnumeric(adaptiveEqInfo, ...
                        'ASMMedianScoreBefore',NaN), ...
                        getfieldnumeric(adaptiveEqInfo, ...
                        'ASMMedianScoreAfter',NaN),adaptiveEqInfo.NumTaps, ...
                        getfieldnumeric(adaptiveEqInfo, ...
                        'ASMTrainingUpdates',0), ...
                        100*adaptiveEqInfo.AcceptanceRate, ...
                        adaptiveEqInfo.OutputAccepted,adaptiveEqInfo.Reason);
                end
            else
                adaptiveEqInfo.Reason = asmModeReason;
            end
        elseif localSupportsTMBlindAdaptiveModulation(modStr) && ...
                (~contains(upper(string(modStr)),'UQPSK') || ...
                 uqpskPostCarrierEQEnabled) && ...
                (~qamBlindPhaseSearchEnabled || ...
                 qamPostBPSAdaptiveEqualizerEnabled) && ...
                (~usePilotlessAPSKFrontEnd || ...
                 pilotlessAPSKPostFrontEndAdaptiveEqualizerEnabled) && ...
                exist('fineSynced','var') && ~isempty(fineSynced)
            adaptiveRefConst = getReferenceConstellation(modStr);

            ddOpt = opt;
            sharedReliabilityMaskPassed = false;
            if blindReliabilityInfo.Applied && ...
                    numel(blindReliabilityHoldMaskSymbols) == ...
                    numel(fineSynced)
                ddOpt.adaptiveEqualizerExternalFadeMask = ...
                    logical(blindReliabilityHoldMaskSymbols(:));
                sharedReliabilityMaskPassed = true;
            end
            pilotFadeBridgeEnabled = contains(upper(string(modStr)),'APSK') && ...
                getLogicalField(opt, ...
                'enableAPSKPilotFadeEqualizerHold', true);
            pilotFadeMaskPassed = false;
            if pilotFadeBridgeEnabled && tmAPSKPilotInfo.Applied && ...
                    isfield(tmAPSKPilotInfo,'DataFadeMask') && ...
                    numel(tmAPSKPilotInfo.DataFadeMask) == numel(fineSynced)
                pilotFadeMask = logical(tmAPSKPilotInfo.DataFadeMask(:));
                if isfield(ddOpt,'adaptiveEqualizerExternalFadeMask') && ...
                        ~isempty(ddOpt.adaptiveEqualizerExternalFadeMask)
                    ddOpt.adaptiveEqualizerExternalFadeMask = ...
                        logical(ddOpt.adaptiveEqualizerExternalFadeMask(:)) | ...
                        pilotFadeMask;
                else
                    ddOpt.adaptiveEqualizerExternalFadeMask = pilotFadeMask;
                end
                pilotFadeMaskPassed = true;
            end
            if getLogicalField(opt,'debugAdaptiveEqualizer',false) && ...
                    blindReliabilityInfo.Applied
                fprintf(['   [TM shared reliability -> EQ] passed=%d ', ...
                    'maskLength=%d eqLength=%d holdSymbols=%d (%.2f%%)\n'], ...
                    sharedReliabilityMaskPassed, ...
                    numel(blindReliabilityHoldMaskSymbols), ...
                    numel(fineSynced), ...
                    nnz(blindReliabilityHoldMaskSymbols), ...
                    100*mean(double(blindReliabilityHoldMaskSymbols)));
            end
            if getLogicalField(opt,'debugAdaptiveEqualizer',false) && ...
                    contains(upper(string(modStr)),'APSK')
                fprintf(['   [TM APSK fade bridge] enabled=%d pilotApplied=%d ', ...
                    'maskPassed=%d maskLength=%d eqLength=%d ', ...
                    'fadeSymbols=%d (%.2f%%) envGainLimit=[%+.1f,%+.1f] dB\n'], ...
                    pilotFadeBridgeEnabled,tmAPSKPilotInfo.Applied, ...
                    pilotFadeMaskPassed, ...
                    numel(tmAPSKPilotInfo.DataFadeMask),numel(fineSynced), ...
                    nnz(tmAPSKPilotInfo.DataFadeMask), ...
                    100*mean(double(tmAPSKPilotInfo.DataFadeMask(:))), ...
                    getfieldnumeric(opt,'adaptiveFastEnvelopeMinGainDB',-40), ...
                    getfieldnumeric(opt,'adaptiveFastEnvelopeMaxGainDB',100));
            end
            if strcmpi(char(adaptiveEqMode),'dd-nlms')
                ddOpt.adaptiveEqualizerStage = 'dd';
            else
                ddOpt.adaptiveEqualizerStage = 'full';
            end
            [fineSynced, ~, adaptiveEqInfo] = ...
                HelperTMBlindCMAEqualizer(fineSynced, adaptiveRefConst, ddOpt);
            if syncDebugRequested
                syncDebugStages.Equalizer = fineSynced;
            end
            % Preserve the user-selected public mode in the result.  The
            % helper implements the common DD engine and reports its
            % internal implementation name by default.
            adaptiveEqInfo.Mode = char(adaptiveEqMode);
            if contains(upper(string(modStr)), 'UQPSK')
                helperReason = char(adaptiveEqInfo.Reason);
                adaptiveEqInfo.Reason = sprintf( ...
                    ['UQPSK 2-sps timing/carrier -> 1-sps rectangular ', ...
                     'MMA + %s; %s'], ...
                    char(adaptiveEqMode), helperReason);
            elseif strcmpi(char(adaptiveEqMode), 'dd-nlms')
                adaptiveEqInfo.Reason = ...
                    'complex DD-NLMS after carrier synchronization';
            end
            % The BER path must use exactly the same equalized symbol stream;
            % otherwise the reported BER would not describe the plotted path.
            fineSyncedForBER = fineSynced;
            if getLogicalField(opt, 'debugAdaptiveEqualizer', false)
                fprintf(['   [TM adaptive EQ] mode=%s taps=%d CMA=%d ', ...
                    ['DD decisions=%d passes=%d/%d ', ...
                     'qualified=%d outputAccepted=%d structure=%s ', ...
                     'sideRatio=%.4f hold=%d/%d fadeHold=%d ', ...
                     'enter/recover=%d/%d externalHold=%d ', ...
                     'externalMask=%d/%d ', ...
                     'accept=%.1f%% CMA-MSE=%.4g DD-MSE=%.4g\n']], ...
                    adaptiveEqInfo.Mode, adaptiveEqInfo.NumTaps, ...
                    adaptiveEqInfo.CMASymbols, adaptiveEqInfo.DecisionCount, ...
                    adaptiveEqInfo.DDPasses, ...
                    adaptiveEqInfo.DDPassesRequested, ...
                    adaptiveEqInfo.CMAQualified, ...
                    adaptiveEqInfo.OutputAccepted, ...
                    getfieldwithdefault(adaptiveEqInfo, ...
                        'EqualizerStructure','unknown'), ...
                    getfieldnumeric(adaptiveEqInfo, ...
                        'SideTapEnergyRatio',NaN), ...
                    getfieldnumeric(adaptiveEqInfo,'DDHoldWindows',0), ...
                    getfieldnumeric(adaptiveEqInfo,'DDWindowCount',0), ...
                    getfieldnumeric(adaptiveEqInfo,'DDFadeHoldWindows',0), ...
                    getfieldnumeric(adaptiveEqInfo,'DDFadeEnterEvents',0), ...
                    getfieldnumeric(adaptiveEqInfo,'DDFadeRecoverEvents',0), ...
                    getfieldnumeric(adaptiveEqInfo, ...
                        'DDExternalFadeHoldWindows',0), ...
                    getfieldnumeric(adaptiveEqInfo, ...
                        'ExternalFadeInputSymbols',0), ...
                    getfieldnumeric(adaptiveEqInfo, ...
                        'ExternalFadeExpandedSymbols',0), ...
                    100*adaptiveEqInfo.AcceptanceRate, ...
                    adaptiveEqInfo.CMAMSE, adaptiveEqInfo.DDMSE);
                fprintf(['   [TM adaptive EQ gate] blind=%s ', ...
                    'score=%.4g/%.4g confidence=%.1f%%/%.1f%% reason=%s\n'], ...
                    adaptiveEqInfo.BlindCostMode, ...
                    adaptiveEqInfo.PhaseStructureScore, ...
                    getfieldnumeric(adaptiveEqInfo,'CMASwitchMSE',NaN), ...
                    100*getfieldnumeric(adaptiveEqInfo, ...
                        'CMAConfidenceRate',NaN), ...
                    100*getfieldnumeric(opt, ...
                        'adaptiveEqualizerMinCMAConfidence',0.50), ...
                    adaptiveEqInfo.Reason);
            end
        else
            if contains(upper(string(modStr)),'UQPSK') && ...
                    ~uqpskPostCarrierEQEnabled
                adaptiveEqInfo.Reason = ...
                    'UQPSK post-carrier adaptive equalizer disabled by option';
            else
                adaptiveEqInfo.Reason = sprintf( ...
                    'unsupported modulation or empty synchronized symbols: %s', ...
                    char(modStr));
            end
        end
    end

    % The CMA/DD taps can introduce a discrete PSK phase ambiguity while
    % adapting to a time-varying H path.  Run the same fixed m-th-power gain
    % tracker once on the final equalized PSK stream so a cycle slip is
    % corrected before ASM/frame statistics.  This is not a BER-based
    % selection and is not exposed as a separate user option.
    if useFastComplexPath && exist('fineSynced','var') && ~isempty(fineSynced)
        postFastComplexOpt = struct( ...
            'FastComplexGainPhaseStep',0.12, ...
            'FastComplexGainPowerStep',0.04, ...
            'FastComplexGainMaxMagnitudeDB',12);
        if blindReliabilityInfo.Applied && ...
                numel(blindReliabilityHoldMaskSymbols) == numel(fineSynced)
            postFastComplexOpt.ExternalHoldMask = ...
                blindReliabilityHoldMaskSymbols;
        end
        [fineSynced, fastComplexGainInfoPost] = ...
            HelperTMFastComplexGainTracker(fineSynced, ...
            getReferenceConstellation(modStr),postFastComplexOpt,'complex');
        fastComplexGainInfo = fastComplexGainInfoPost;
        fineSyncedForBER = fineSynced;
        if syncDebugRequested
            syncDebugStages.PostEQTracker = fineSynced;
        end
        if getLogicalField(opt,'debugAdaptiveEqualizer',false)
            fprintf(['   [TM fast complex gain post-DD] gain=%+.2f dB ', ...
                'phase=%+.2f deg accept=%.1f%% DD-MSE=%.4g\n'], ...
                fastComplexGainInfo.FinalMagnitude_dB, ...
                fastComplexGainInfo.FinalPhase_deg, ...
                100*fastComplexGainInfo.AcceptanceRate, ...
                fastComplexGainInfo.DDMSE);
        end
    elseif useFastPhasePath && exist('fineSynced','var') && ~isempty(fineSynced)
        postFastPhaseOpt = struct( ...
            'FastPhaseStep',0.12, ...
            'FastPhaseFrequencyStep',0.004, ...
            'FastPhaseDecisionGate',0.35);
        if blindReliabilityInfo.Applied && ...
                numel(blindReliabilityHoldMaskSymbols) == numel(fineSynced)
            postFastPhaseOpt.ExternalHoldMask = ...
                blindReliabilityHoldMaskSymbols;
        end
        [fineSynced, fastComplexGainInfoPost] = ...
            HelperTMFastComplexGainTracker(fineSynced, ...
            getReferenceConstellation(modStr),postFastPhaseOpt,'phase');
        fastComplexGainInfo = fastComplexGainInfoPost;
        fineSyncedForBER = fineSynced;
        if syncDebugRequested
            syncDebugStages.PostEQTracker = fineSynced;
        end
        if getLogicalField(opt,'debugAdaptiveEqualizer',false)
            fprintf(['   [TM fast phase post-DD] phase=%+.2f deg ', ...
                'accept=%.1f%% DD-MSE=%.4g\n'], ...
                fastComplexGainInfo.FinalPhase_deg, ...
                100*fastComplexGainInfo.AcceptanceRate, ...
                fastComplexGainInfo.DDMSE);
        end
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
    % Legacy post-sync RMS normalization.
    % This is after timing/carrier synchronization, so it does not erase the
    % dynamic AGC behavior.  It keeps EVM/MER/BER metrics on the historical
    % unit-power scale for an apples-to-apples AGC-off comparison.
    applyLegacyPostSyncNormalization = true;

    if applyLegacyPostSyncNormalization
        if ~isempty(fineSynced)
            pwr = mean(abs(fineSynced).^2);
            if pwr > 0, fineSynced = fineSynced / sqrt(pwr); end
        end
        if ~isempty(fineSyncedForBER)
            pwrBER = mean(abs(fineSyncedForBER).^2);
            if pwrBER > 0, fineSyncedForBER = fineSyncedForBER / sqrt(pwrBER); end
        end
    end
    % ===== 计算所有指标 =====
    isCPMMod = any(strcmpi( ...
    string(modStr), ["GMSK","MSK"]));
    isOQPSKMod = strcmpi(string(modStr), "OQPSK");
    isFMMod = contains(upper(string(modStr)),'FM');
    if isCPMMod || isPCMPhaseMod || isFMMod
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
    if isFMMod || isOQPSKMod
        evm_pre = NaN;
    elseif isCPMMod
        evm_pre = NaN;
    else
        [evm_pre,  ~] = computeEVM(rawSym, refConst);
    end
    % EVM/MER/SNR_est 先用未旋转的算一份占位,稍后用 best 旋转后的覆盖

    % 同步后的evm
    if isFMMod
        evm_post = NaN;
        mer_post = NaN;
    elseif isCPMMod
        evm_post = NaN;
        mer_post = NaN;
    elseif isOQPSKMod
        [evm_post, mer_post] = localOQPSKRailQualityMetrics( ...
            fineSyncedForBER, sps, rolloff, ...
            getfieldnumeric(opt,'FilterSpanInSymbols',10));
    else
        [evm_post, mer_post] = computeEVM(fineSynced, refConst);
    end

    % 基于星座误差估计的等效 SNR，不等于输入 SNR
    if isFMMod
        snr_est = NaN;
    elseif isCPMMod
        snr_est = NaN;
    elseif isOQPSKMod
        snr_est = mer_post;
    else
        snr_est = computeSNRest(fineSynced, refConst);
    end

    % 峰均功率比
    papr_dB = 10*log10(max(abs(txWaveform).^2)/mean(abs(txWaveform).^2));

    % BER + Frame Lock（沿用主脚本逻辑的简化版）
    demodNoiseVariance = NaN;
    if isOQPSKMod
        demodNoiseVariance = max(1e-4, min(1, ...
            (max(evm_post,0)/100)^2));
        opt.DemodNoiseVariance = demodNoiseVariance;
    elseif contains(modStr,'QAM') || contains(modStr,'APSK')
        if isfield(opt,'DemodNoiseVariance') && ...
                ~isempty(opt.DemodNoiseVariance) && ...
                isfinite(double(opt.DemodNoiseVariance))
            demodNoiseVariance = max(eps, double(opt.DemodNoiseVariance));
        else
            demodNoiseVariance = localEstimateDemodNoiseVariance( ...
                fineSyncedForBER, refConst);
            if contains(modStr,'APSK') && ...
                    isfinite(tmAPSKPilotInfo.PilotNoiseVariance)
                % Pilot residuals are independent of payload decisions and
                % protect the LDPC/Turbo demapper from overconfident LLRs in
                % a faded interval.
                demodNoiseVariance = max(demodNoiseVariance, ...
                    tmAPSKPilotInfo.PilotNoiseVariance);
            end
        end
        demodNoiseVariance = min(1, max(1e-4, demodNoiseVariance));
        opt.DemodNoiseVariance = demodNoiseVariance;
    end
    if qamBlindPhaseInfo.Applied && ...
            isfield(qamBlindPhaseState,'FadeHold') && ...
            isfield(qamBlindPhaseState,'Centers')
        % Diagnostic only: preserve the BPS detector's actual HOLD state.
        % The mask is never fed back into synchronization or equalization.
        opt.QAMBPSHoldMaskSymbols = localExpandQAMBPSHoldMask( ...
            qamBlindPhaseState.FadeHold, ...
            qamBlindPhaseState.Centers, numel(fineSyncedForBER));
    end
    [berVal, lockRate, bestRot, berStats] = computeBER(fineSyncedForBER, validTxFrames, modStr, opt, randomizerEnabled, hasASM, btVal, numWarmUp);
    if getLogicalField(opt,'debugQAMBPSFadeBER',false)
        localPrintQAMBPSFadeBER(berStats);
    end

    syncDiagnostics = localEmptyTMSyncDiagnostics();
    if syncDebugRequested && ~isCPMMod && ~isOQPSKMod && ...
            ~isPCMPhaseMod && ~isFMMod
        syncDiagnostics = localBuildTMSyncDiagnostics( ...
            syncDebugStages, refConst, fSym, cfo_val, ...
            adaptiveEqInfo, berStats, opt);
        localPrintTMSyncDiagnostics(syncDiagnostics);
    end

    % 用 BER 评估挑出来的 best 旋转把 fineSynced 转回参考相位,星座图视觉对齐
    if isFMMod
        fineSyncedAligned = fineSynced;
        evm_post = NaN;
        mer_post = NaN;
        snr_est = NaN;
    elseif isCPMMod
        fineSyncedAligned = fineSynced;
        evm_post = NaN;
        mer_post = NaN;
        snr_est = NaN;
    elseif isOQPSKMod
        fineSyncedAligned = fineSynced * exp(1j*bestRot);
        oqpskAlignedForMetric = fineSyncedForBER * exp(1j*bestRot);
        [evm_post, mer_post] = localOQPSKRailQualityMetrics( ...
            oqpskAlignedForMetric, sps, rolloff, ...
            getfieldnumeric(opt,'FilterSpanInSymbols',10));
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

    evmRadialPct = NaN;
    evmTangentialPct = NaN;
    residualPhaseRMSDeg = NaN;
    residualRadiusRMSDB = NaN;
    if ~isFMMod && ~isCPMMod && ~isOQPSKMod && ~isempty(refConst)
        [evmRadialPct,evmTangentialPct,residualPhaseRMSDeg, ...
            residualRadiusRMSDB] = ...
            localConstellationResidualComponents( ...
            fineSyncedAligned,refConst);
    end

    % ===== 打包返回 =====
    res = struct();
    res.modType  = char(modStr);
    res.ActualWaveformDuration_s = actualWaveformDuration_s;
    res.snr_in   = snr_val;
    res.NoisePlacement = char(noisePlacement);
    res.NoiseMode = char(noiseInfo.Mode);
    if isfinite(noiseInfo.PSD_dBmHz)
        res.NoisePSD_dBmHz = noiseInfo.PSD_dBmHz;
        res.NoiseBandwidthHz = noiseInfo.BandwidthHz;
        res.NoisePower_dBm = noiseInfo.NoisePower_dBm;
        res.NoiseReferenceLevel_dBm = noiseInfo.ReferenceLevel_dBm;
    end
    res.NoiseEquivalentSNR_dB = noiseInfo.EquivalentSNR_dB;
    res.cfo_in   = cfo_val;
    res.phase_in = getf(opt,'phaseOffset',0);
    res.delay_in = delay_val;
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.inputLevelDbm = getInputLevelDbm(opt, -10);
    res.outputLevelDbm = res.inputLevelDbm;
    res.ConverterChainEnabled = logical(converterChainEnabled);
    res.BasebandIFLevel_dBm = basebandIFLevelDBm;
    res.UpconverterFixedGain_dB = upconverterInfo.FixedGainDB;
    res.UpconverterAttenuation_dB = upconverterInfo.AppliedAttenuationDB;
    res.UpconverterNetGain_dB = upconverterInfo.NetGainDB;
    res.UpconverterOutputLevel_dBm = upconverterInfo.OutputSignalLevelDBm;
    res.UpconverterCompressionRisk = logical(upconverterInfo.CompressionRisk);
    res.UpconverterCompression_dB = upconverterInfo.EstimatedCompressionDB;
    res.UpconverterInputWithinTypicalRange = ...
        logical(upconverterInfo.InputWithinTypicalRange);
    res.HAppliedGain_dB = hAppliedGainDB;
    res.DownconverterInputLevel_dBm = downconverterInfo.InputSignalLevelDBm;
    res.DownconverterFixedGain_dB = downconverterInfo.FixedGainDB;
    res.DownconverterAttenuation_dB = downconverterInfo.AppliedAttenuationDB;
    res.DownconverterAutoAttenuation = ...
        logical(downconverterInfo.AutoAttenuation);
    res.DownconverterNetGain_dB = downconverterInfo.NetGainDB;
    res.DownconverterOutputLevel_dBm = downconverterInfo.OutputSignalLevelDBm;
    res.DownconverterCompressionRisk = logical(downconverterInfo.CompressionRisk);
    res.DownconverterCompression_dB = downconverterInfo.EstimatedCompressionDB;
    res.DownconverterInputWithinTypicalRange = ...
        logical(downconverterInfo.InputWithinTypicalRange);
    res.ADCEquivalentEnabled = logical(adcInfo.Enabled);
    res.ADCBits = adcInfo.Bits;
    res.ADCFullScalePower_dBm = adcInfo.FullScalePowerDBm;
    res.ADCRMSBackoff_dB = adcInfo.RMSBackoffDB;
    res.ADCClipFraction = adcInfo.ClipFraction;
    res.ADCQuantizationSNR_dB = adcInfo.QuantizationSNRDB;
    res.HasASM = logical(hasASM);
    res.HasFECF = getLogicalField(opt, 'HasFECF', ...
        getLogicalField(opt, 'CRCEnabled', false));
    res.CRCType = char(getfieldwithdefault(opt, 'CRCType', 'CCITT'));
    res.RandomizerEnabled = logical(randomizerEnabled);
    res.RandomizerFECPosition = char(randomizerFECPosition);
    res.DataPathMode = char(dataPathMode);
    if isEqualSplitPath || isUnequalSplitPath
        res.TMDataSource = 'split';
        res.TMDataSourceI = char(tmSourceInfoI.CanonicalType);
        res.TMDataSourceQ = char(tmSourceInfoQ.CanonicalType);
        res.TMDataSourcePolynomialI = localTMSourcePolynomial(tmSourceInfoI);
        res.TMDataSourcePolynomialQ = localTMSourcePolynomial(tmSourceInfoQ);
    else
        res.TMDataSource = char(tmSourceInfoSingle.CanonicalType);
        res.TMDataSourceI = '';
        res.TMDataSourceQ = '';
        res.TMDataSourcePolynomial = localTMSourcePolynomial(tmSourceInfoSingle);
    end
    res.ConvolutionalG1G2Mode = char(getfieldwithdefault(opt, ...
        'ConvolutionalG1G2Mode', 'not-applicable'));
    res.CarrierCaptureRangeConfigured_Hz = getfieldnumeric(opt, ...
        'carrierCaptureRangeHz', NaN);
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
    res.AGCEnabled = logical(agcInfo.Enabled);
    res.AGCTimeConstantMs = agcInfo.TimeConstantMs;
    res.AGCProcessingRateHz = agcInfo.ProcessingRateHz;
    res.AGCInitialGain_dB = agcInfo.InitialGain_dB;
    res.AGCFinalGain_dB = agcInfo.FinalGain_dB;
    res.AGCMinGain_dB = agcInfo.MinGain_dB;
    res.AGCMaxGain_dB = agcInfo.MaxGain_dB;
    res.AGCInputPower_dB = 10*log10(max(agcInfo.InputPower, eps));
    res.AGCOutputPower_dB = 10*log10(max(agcInfo.OutputPower, eps));
    res.AGCPowerEstimateFinal_dB = ...
        10*log10(max(agcInfo.FinalPowerEstimate, eps));
    res.WaveformDurationOverTau = agcInfo.WaveformDurationOverTau;
    res.AGCSufficientObservation = logical(agcInfo.SufficientObservation);
    res.FastEnvelopeApplied = logical(fastEnvelopeInfo.Applied);
    res.FastEnvelopeEstimatorMode = fastEnvelopeInfo.EstimatorMode;
    res.FastEnvelopeTauSymbols = fastEnvelopeInfo.TauSymbols;
    res.FastEnvelopeBlockSymbols = fastEnvelopeInfo.BlockSymbols;
    res.FastEnvelopeHopSymbols = fastEnvelopeInfo.HopSymbols;
    res.FastEnvelopeMedianBlocks = fastEnvelopeInfo.MedianBlocks;
    res.FastEnvelopeTrimFraction = fastEnvelopeInfo.TrimFraction;
    res.FastEnvelopeGainSlewDBPerSymbol = ...
        fastEnvelopeInfo.GainSlewDBPerSymbol;
    res.FastEnvelopeFinalGain_dB = fastEnvelopeInfo.FinalMagnitude_dB;
    res.FastEnvelopeGainMin_dB = fastEnvelopeInfo.GainMin_dB;
    res.FastEnvelopeGainMax_dB = fastEnvelopeInfo.GainMax_dB;
    res.FastEnvelopeExternalHoldApplied = ...
        logical(fastEnvelopeInfo.ExternalHoldMaskProvided);
    res.FastEnvelopeExternalHoldSamples = ...
        fastEnvelopeInfo.ExternalHoldSamples;
    res.FastEnvelopeExternalHoldFraction = ...
        fastEnvelopeInfo.ExternalHoldFraction;
    res.BlindReliabilityApplied = logical(blindReliabilityInfo.Applied);
    res.BlindReliabilityReason = char(blindReliabilityInfo.Reason);
    res.BlindReliabilityFinalState = char(blindReliabilityInfo.FinalState);
    res.BlindReliabilityWindowSymbols = ...
        blindReliabilityInfo.WindowSymbols;
    res.BlindReliabilityHoldFraction = ...
        blindReliabilityInfo.HoldFraction;
    res.BlindReliabilityHoldEvents = blindReliabilityInfo.HoldEvents;
    res.BlindReliabilityRecoverEvents = ...
        blindReliabilityInfo.RecoverEvents;
    res.BlindReliabilityMinRelativePower_dB = ...
        blindReliabilityInfo.MinRelativePowerDB;
    res.BlindReliabilityMaxInverseGain_dB = ...
        blindReliabilityInfo.MaxInverseGainDB;
    res.FastComplexGainApplied = logical(fastComplexGainInfo.Applied);
    res.FastComplexGainFinalMagnitude_dB = fastComplexGainInfo.FinalMagnitude_dB;
    res.FastComplexGainFinalPhase_deg = fastComplexGainInfo.FinalPhase_deg;
    res.FastComplexGainAcceptanceRate = fastComplexGainInfo.AcceptanceRate;
    res.FastComplexGainDDMSE = fastComplexGainInfo.DDMSE;
    res.FastComplexGainMin_dB = fastComplexGainInfo.GainMin_dB;
    res.FastComplexGainMax_dB = fastComplexGainInfo.GainMax_dB;
    res.FastComplexExternalHoldApplied = ...
        logical(fastComplexGainInfo.ExternalHoldMaskProvided);
    res.FastComplexExternalHoldSamples = ...
        fastComplexGainInfo.ExternalHoldSamples;
    res.FastComplexExternalHoldFraction = ...
        fastComplexGainInfo.ExternalHoldFraction;
    res.HighRatePhaseTrackingApplied = logical(highRatePhaseInfo.Applied);
    res.HighRatePhaseWindowSymbols = highRatePhaseInfo.WindowSymbols;
    res.HighRatePhaseMeanConfidence = highRatePhaseInfo.MeanConfidence;
    res.HighRatePhaseHoldSamples = highRatePhaseInfo.HoldSamples;
    res.HighRatePhaseFinalRelativePhase_deg = ...
        highRatePhaseInfo.FinalRelativePhase_deg;
    res.UQPSKCarrierPLLApplied = logical(uqpskCarrierPLLInfo.Applied);
    res.UQPSKCarrierPLLDualBandwidth = ...
        logical(uqpskCarrierPLLInfo.DualBandwidth);
    res.UQPSKCarrierPLLLocked = logical(uqpskCarrierPLLInfo.Locked);
    res.UQPSKCarrierPLLFinalMode = char(uqpskCarrierPLLInfo.FinalMode);
    res.UQPSKCarrierPLLAcquireBW = uqpskCarrierPLLInfo.AcquireLoopBW;
    res.UQPSKCarrierPLLTrackBW = uqpskCarrierPLLInfo.TrackLoopBW;
    res.UQPSKCarrierPLLFinalFrequency_Hz = ...
        uqpskCarrierPLLInfo.FinalFrequency_Hz;
    res.UQPSKCarrierPLLLockTransitions = uqpskCarrierPLLInfo.LockTransitions;
    res.UQPSKCarrierPLLReacquisitions = uqpskCarrierPLLInfo.Reacquisitions;
    res.UQPSKCarrierPLLFadeHoldSymbols = uqpskCarrierPLLInfo.FadeHoldSymbols;
    res.UQPSKCarrierPLLExternalHoldApplied = ...
        logical(uqpskCarrierPLLInfo.ExternalHoldMaskProvided);
    res.UQPSKCarrierPLLExternalHoldSymbols = ...
        uqpskCarrierPLLInfo.ExternalHoldSymbols;
    res.UQPSKCarrierPLLExternalHoldFraction = ...
        uqpskCarrierPLLInfo.ExternalHoldFraction;
    res.UQPSKCarrierPLLUpdateAcceptanceRate = ...
        uqpskCarrierPLLInfo.UpdateAcceptanceRate;
    res.UQPSKCarrierPLLMeanAbsPhaseError = ...
        uqpskCarrierPLLInfo.MeanAbsPhaseError;
    res.UQPSKPostCarrierEQEnabled = logical(uqpskPostCarrierEQEnabled);
    res.AdaptiveEqualizerEnabled = logical(adaptiveEqInfo.Enabled);
    res.AdaptiveEqualizerMode = char(adaptiveEqInfo.Mode);
    res.AdaptiveEqualizerReason = char(adaptiveEqInfo.Reason);
    res.AdaptiveEqualizerTaps = adaptiveEqInfo.NumTaps;
    res.AdaptiveEqualizerCMASymbols = adaptiveEqInfo.CMASymbols;
    res.AdaptiveEqualizerDDPasses = adaptiveEqInfo.DDPasses;
    res.AdaptiveEqualizerCMAStep = adaptiveEqInfo.CMAStep;
    res.AdaptiveEqualizerDDStep = adaptiveEqInfo.DDStep;
    res.AdaptiveEqualizerCMAR2 = adaptiveEqInfo.CMAR2;
    res.AdaptiveEqualizerDecisionGate = adaptiveEqInfo.DecisionGate;
    blindCostMode = 'off';
    if isfield(adaptiveEqInfo, 'BlindCostMode') && ...
            ~isempty(adaptiveEqInfo.BlindCostMode)
        blindCostMode = char(adaptiveEqInfo.BlindCostMode);
    end
    res.AdaptiveEqualizerBlindCostMode = blindCostMode;
    res.AdaptiveEqualizerPhaseRotation_deg = adaptiveEqInfo.PhaseRotation_deg;
    res.AdaptiveEqualizerPhaseStructureScore = adaptiveEqInfo.PhaseStructureScore;
    res.AdaptiveEqualizerCMASwitchMSE = getfieldnumeric( ...
        adaptiveEqInfo, 'CMASwitchMSE', NaN);
    res.AdaptiveEqualizerCMAConfidenceRate = getfieldnumeric( ...
        adaptiveEqInfo, 'CMAConfidenceRate', NaN);
    res.AdaptiveEqualizerCMAQualified = getLogicalField( ...
        adaptiveEqInfo, 'CMAQualified', false);
    res.AdaptiveEqualizerCMAMSE = adaptiveEqInfo.CMAMSE;
    res.AdaptiveEqualizerDDMSE = adaptiveEqInfo.DDMSE;
    res.AdaptiveEqualizerAcceptanceRate = adaptiveEqInfo.AcceptanceRate;
    res.AdaptiveEqualizerRejectedDecisions = getfieldnumeric( ...
        adaptiveEqInfo, 'RejectedDecisions', 0);
    res.AdaptiveEqualizerFinalTapNorm = getfieldnumeric( ...
        adaptiveEqInfo, 'FinalTapNorm', NaN);
    res.AdaptiveEqualizerInputStructureMSE = getfieldnumeric( ...
        adaptiveEqInfo, 'InputStructureMSE', NaN);
    res.AdaptiveEqualizerOutputStructureMSE = getfieldnumeric( ...
        adaptiveEqInfo, 'OutputStructureMSE', NaN);
    res.AdaptiveEqualizerQualityImprovement = getfieldnumeric( ...
        adaptiveEqInfo, 'QualityImprovement', NaN);
    res.AdaptiveEqualizerOutputAccepted = getLogicalField( ...
        adaptiveEqInfo, 'OutputAccepted', false);
    res.AdaptiveEqualizerStructure = char(getfieldwithdefault( ...
        adaptiveEqInfo, 'EqualizerStructure', 'off'));
    res.AdaptiveEqualizerScalarMode = strcmpi( ...
        res.AdaptiveEqualizerStructure, 'scalar');
    res.AdaptiveEqualizerSideTapEnergyRatio = getfieldnumeric( ...
        adaptiveEqInfo, 'SideTapEnergyRatio', NaN);
    res.AdaptiveEqualizerDDWindowSymbols = getfieldnumeric( ...
        adaptiveEqInfo, 'DDWindowSymbols', 0);
    res.AdaptiveEqualizerDDMinWindowAcceptance = getfieldnumeric( ...
        adaptiveEqInfo, 'DDMinWindowAcceptance', NaN);
    res.AdaptiveEqualizerDDWindowCount = getfieldnumeric( ...
        adaptiveEqInfo, 'DDWindowCount', 0);
    res.AdaptiveEqualizerDDGoodWindows = getfieldnumeric( ...
        adaptiveEqInfo, 'DDGoodWindows', 0);
    res.AdaptiveEqualizerDDHoldWindows = getfieldnumeric( ...
        adaptiveEqInfo, 'DDHoldWindows', 0);
    res.AdaptiveEqualizerDDFadeHoldWindows = getfieldnumeric( ...
        adaptiveEqInfo, 'DDFadeHoldWindows', 0);
    res.AdaptiveEqualizerDDFadeEnterEvents = getfieldnumeric( ...
        adaptiveEqInfo, 'DDFadeEnterEvents', 0);
    res.AdaptiveEqualizerDDFadeRecoverEvents = getfieldnumeric( ...
        adaptiveEqInfo, 'DDFadeRecoverEvents', 0);
    res.AdaptiveEqualizerFadeRecoverDB = getfieldnumeric( ...
        adaptiveEqInfo, 'FadeRecoverDB', NaN);
    res.AdaptiveEqualizerFadeDetectorSymbols = getfieldnumeric( ...
        adaptiveEqInfo, 'FadeDetectorSymbols', 0);
    res.AdaptiveEqualizerExternalFadeMaskProvided = getLogicalField( ...
        adaptiveEqInfo, 'ExternalFadeMaskProvided', false);
    res.AdaptiveEqualizerExternalFadeMaskLengthMatched = getLogicalField( ...
        adaptiveEqInfo, 'ExternalFadeMaskLengthMatched', false);
    res.AdaptiveEqualizerExternalFadeMaskInputLength = getfieldnumeric( ...
        adaptiveEqInfo, 'ExternalFadeMaskInputLength', 0);
    res.AdaptiveEqualizerExternalFadeInputSymbols = getfieldnumeric( ...
        adaptiveEqInfo, 'ExternalFadeInputSymbols', 0);
    res.AdaptiveEqualizerExternalFadeExpandedSymbols = getfieldnumeric( ...
        adaptiveEqInfo, 'ExternalFadeExpandedSymbols', 0);
    res.AdaptiveEqualizerDDExternalFadeHoldWindows = getfieldnumeric( ...
        adaptiveEqInfo, 'DDExternalFadeHoldWindows', 0);
    res.AdaptiveEqualizerDDExternalFadeHoldSymbols = getfieldnumeric( ...
        adaptiveEqInfo, 'DDExternalFadeHoldSymbols', 0);
    res.AdaptiveEqualizerFadeHoldDB = getfieldnumeric( ...
        adaptiveEqInfo, 'FadeHoldDB', NaN);
    res.AdaptiveEqualizerDDHoldReason = char(getfieldwithdefault( ...
        adaptiveEqInfo, 'DDHoldReason', ''));
    res.AdaptiveEqualizerRollbackReason = getfieldwithdefault( ...
        adaptiveEqInfo, 'RollbackReason', '');
    if syncDiagnostics.Enabled
        res.SyncDiagnostics = syncDiagnostics;
    end
    res.AdaptiveEqualizerConverged = logical(adaptiveEqInfo.Converged);
    res.ASMTrainingEqualizerASMCount = getfieldnumeric( ...
        adaptiveEqInfo,'ASMCount',0);
    res.ASMTrainingEqualizerUpdates = getfieldnumeric( ...
        adaptiveEqInfo,'ASMTrainingUpdates',0);
    res.ASMTrainingEqualizerMedianScoreBefore = getfieldnumeric( ...
        adaptiveEqInfo,'ASMMedianScoreBefore',NaN);
    res.ASMTrainingEqualizerMedianScoreAfter = getfieldnumeric( ...
        adaptiveEqInfo,'ASMMedianScoreAfter',NaN);
    res.BER         = berVal;
    res.EVM_pre_pct = evm_pre;
    res.EVM_post_pct= evm_post;
    res.EVMRadial_pct = evmRadialPct;
    res.EVMTangential_pct = evmTangentialPct;
    res.ResidualPhaseRMS_deg = residualPhaseRMSDeg;
    res.ResidualRadiusRMS_dB = residualRadiusRMSDB;
    res.MER_dB      = mer_post;
    res.SNR_est_dB  = snr_est;
    if isCPMMod
        res.QualityMetricType = 'not-defined-for-cpm-waveform';
    elseif isOQPSKMod
        res.QualityMetricType = 'oqpsk-staggered-iq-rail';
    else
        res.QualityMetricType = 'constellation-nearest-point';
    end
    res.DemodNoiseVariance = demodNoiseVariance;
    res.PAPR_dB     = papr_dB;
    res.LockRate    = lockRate;
    res.FER         = berStats.FER;
    res.FrameErrorRate = berStats.FER;
    res.FrameErrors = berStats.FrameErrors;
    res.CountedFrames = berStats.CountedFrames;
    res.MatchedFrames = berStats.MatchedFrames;
    res.DecodedFrames = berStats.NumRxFrames;
    res.GMSKDetectorUsed = berStats.GMSKDetectorUsed;
    qamBPSFadeBERFields = localQAMBPSFadeBERResultFields();
    for iQAMBPSFadeBER = 1:numel(qamBPSFadeBERFields)
        fadeBERField = qamBPSFadeBERFields{iQAMBPSFadeBER};
        res.(fadeBERField) = berStats.(fadeBERField);
    end
    res.GMSKSecondOrderPLLApplied = ...
        logical(gmskSecondOrderPLLInfo.Applied);
    res.GMSKSecondOrderPLLReason = gmskSecondOrderPLLInfo.Reason;
    res.GMSKSecondOrderPLLLocked = ...
        logical(gmskSecondOrderPLLInfo.Locked);
    res.GMSKSecondOrderPLLFinalMode = ...
        char(gmskSecondOrderPLLInfo.FinalMode);
    res.GMSKSecondOrderPLLFinalFrequency_Hz = ...
        gmskSecondOrderPLLInfo.FinalFrequency_Hz;
    res.GMSKSecondOrderPLLFrequencyMin_Hz = ...
        gmskSecondOrderPLLInfo.FrequencyMin_Hz;
    res.GMSKSecondOrderPLLFrequencyMax_Hz = ...
        gmskSecondOrderPLLInfo.FrequencyMax_Hz;
    res.GMSKSecondOrderPLLUpdateAcceptanceRate = ...
        gmskSecondOrderPLLInfo.UpdateAcceptanceRate;
    res.GMSKSecondOrderPLLFadeHoldSamples = ...
        gmskSecondOrderPLLInfo.FadeHoldSamples;
    res.GMSKSecondOrderPLLExternalHoldApplied = ...
        logical(gmskSecondOrderPLLInfo.ExternalHoldMaskProvided);
    res.GMSKSecondOrderPLLExternalHoldSamples = ...
        gmskSecondOrderPLLInfo.ExternalHoldSamples;
    res.GMSKSecondOrderPLLMeanAbsPhaseError = ...
        gmskSecondOrderPLLInfo.MeanAbsPhaseError;
    res.GMSKResidualTrackerApplied = ...
        logical(gmskResidualTrackerInfo.Applied);
    res.GMSKResidualWindowCount = gmskResidualTrackerInfo.WindowCount;
    res.GMSKResidualAcceptedWindows = ...
        gmskResidualTrackerInfo.AcceptedWindows;
    res.GMSKResidualHoldWindows = gmskResidualTrackerInfo.HoldWindows;
    res.GMSKResidualExternalHoldApplied = ...
        logical(gmskResidualTrackerInfo.ExternalHoldMaskProvided);
    res.GMSKResidualExternalHoldSamples = ...
        gmskResidualTrackerInfo.ExternalHoldSamples;
    res.GMSKResidualExternalHoldRejectedWindows = ...
        gmskResidualTrackerInfo.ExternalHoldRejectedWindows;
    res.GMSKResidualWindowSymbols = gmskResidualTrackerInfo.WindowSymbols;
    res.GMSKResidualHopSymbols = gmskResidualTrackerInfo.HopSymbols;
    res.GMSKResidualMin_Hz = gmskResidualTrackerInfo.ResidualMin_Hz;
    res.GMSKResidualMedian_Hz = gmskResidualTrackerInfo.ResidualMedian_Hz;
    res.GMSKResidualMax_Hz = gmskResidualTrackerInfo.ResidualMax_Hz;
    res.GMSKResidualRMS_Hz = gmskResidualTrackerInfo.ResidualRMS_Hz;
    res.GMSKResidualFinal_Hz = gmskResidualTrackerInfo.FinalResidual_Hz;
    res.GMSKResidualMedianConfidence_dB = ...
        gmskResidualTrackerInfo.MedianConfidence_dB;
    res.GMSKResidualRawAcceptedRate = ...
        gmskResidualTrackerInfo.RawAcceptedRate;
    res.GMSKResidualCandidateFiniteRate = ...
        gmskResidualTrackerInfo.CandidateFiniteRate;
    res.GMSKResidualCandidateMin_Hz = ...
        gmskResidualTrackerInfo.CandidateMin_Hz;
    res.GMSKResidualCandidateMedian_Hz = ...
        gmskResidualTrackerInfo.CandidateMedian_Hz;
    res.GMSKResidualCandidateMax_Hz = ...
        gmskResidualTrackerInfo.CandidateMax_Hz;
    res.GMSKResidualCandidateRMS_Hz = ...
        gmskResidualTrackerInfo.CandidateRMS_Hz;
    res.GMSKResidualNonfiniteWindows = ...
        gmskResidualTrackerInfo.NonfiniteWindows;
    res.GMSKResidualConfidenceRejectedWindows = ...
        gmskResidualTrackerInfo.ConfidenceRejectedWindows;
    res.GMSKResidualRangeRejectedWindows = ...
        gmskResidualTrackerInfo.RangeRejectedWindows;
    res.GMSKResidualRawMin_Hz = gmskResidualTrackerInfo.RawMin_Hz;
    res.GMSKResidualRawMedian_Hz = gmskResidualTrackerInfo.RawMedian_Hz;
    res.GMSKResidualRawMax_Hz = gmskResidualTrackerInfo.RawMax_Hz;
    res.GMSKResidualRawRMS_Hz = gmskResidualTrackerInfo.RawRMS_Hz;
    res.GMSKResidualJumpMax_Hz = gmskResidualTrackerInfo.JumpMax_Hz;
    res.GMSKResidualJumpRMS_Hz = gmskResidualTrackerInfo.JumpRMS_Hz;
    res.GMSKResidualPhaseCorrectionEnd_deg = ...
        gmskResidualTrackerInfo.PhaseCorrectionEnd_deg;
    if getLogicalField(opt,'debugGMSKResidualTracker',false)
        res.GMSKResidualWindowDebug = gmskResidualTrackerInfo.WindowDebug;
    end
    res.AcquisitionFrames = berStats.AcquisitionFrames;
    res.AcquisitionTime_s = berStats.AcquisitionTime_s;
    res.CRCCheckedFrames = getfieldnumeric(berStats, 'CRCCheckedFrames', 0);
    res.CRCErrorFrames = getfieldnumeric(berStats, 'CRCErrorFrames', 0);
    res.CRCErrorRate = getfieldnumeric(berStats, 'CRCErrorRate', NaN);
    predecoderMetricFields = localPredecoderResultFields();
    for iPredecoderMetric = 1:numel(predecoderMetricFields)
        predecoderMetricName = predecoderMetricFields{iPredecoderMetric};
        res.(predecoderMetricName) = getfieldnumeric( ...
            berStats, predecoderMetricName, NaN);
    end
    if isfield(berStats,'ASMFramePhaseCorrection')
        phaseCorrection = berStats.ASMFramePhaseCorrection;
        res.ASMFramePhaseCorrectionEnabled = ...
            getLogicalField(phaseCorrection,'Enabled',false);
        res.ASMFramePhaseCorrectionApplied = ...
            getLogicalField(phaseCorrection,'Applied',false);
        res.ASMFramePhaseCorrectionReason = ...
            char(getfieldwithdefault(phaseCorrection,'Reason',''));
        res.ASMFramePhaseCorrectionFrames = getfieldnumeric( ...
            phaseCorrection,'CorrectedFrames',0);
        res.ASMFramePhaseCorrectionReliableFrames = getfieldnumeric( ...
            phaseCorrection,'ReliableFrames',0);
        res.ASMFramePhaseCorrectionHoldoverFrames = getfieldnumeric( ...
            phaseCorrection,'HoldoverFrames',0);
        res.ASMFramePhaseCorrectionUncorrectedPrefixFrames = getfieldnumeric( ...
            phaseCorrection,'UncorrectedPrefixFrames',0);
        res.ASMFramePhaseCycleSlipsBefore = getfieldnumeric( ...
            phaseCorrection,'CycleSlipCountBefore',0);
        if isfield(phaseCorrection,'AfterTimeline') && ...
                getLogicalField(phaseCorrection.AfterTimeline,'Available',false)
            res.ASMFramePhaseCycleSlipsAfter = getfieldnumeric( ...
                phaseCorrection.AfterTimeline,'CycleSlipCount',NaN);
        else
            res.ASMFramePhaseCycleSlipsAfter = NaN;
        end
    end
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
    res.TMAPSKPilotFadeFraction = tmAPSKPilotInfo.FadeFraction;
    res.TMAPSKPilotDataFadeSymbols = nnz(tmAPSKPilotInfo.DataFadeMask);
    res.TMAPSKPilotDataFadeFraction = ...
        mean(double(tmAPSKPilotInfo.DataFadeMask(:)));
    res.TMAPSKPilotMaxAppliedGain_dB = tmAPSKPilotInfo.MaxAppliedGain_dB;
    res.TMAPSKPilotRegularization = tmAPSKPilotInfo.Regularization;
    res.TMAPSKPilotNoiseVariance = tmAPSKPilotInfo.PilotNoiseVariance;
    res.APSKReceiverMode = char(apskReceiverMode);
    res.PilotlessAPSKApplied = pilotlessAPSKInfo.Applied;
    res.PilotlessAPSKReason = pilotlessAPSKInfo.Reason;
    res.PilotlessAPSKFourthPowerCFO_Hz = ...
        pilotlessAPSKInfo.FourthPowerCFO_Hz;
    res.PilotlessAPSKFourthPowerConfidence_dB = ...
        pilotlessAPSKInfo.FourthPowerConfidence_dB;
    res.PilotlessAPSKCoarsePowerOrder = ...
        pilotlessAPSKInfo.CoarsePowerOrder;
    res.PilotlessAPSKNDAResidualCFO_Hz = ...
        pilotlessAPSKInfo.NDAResidualCFO_Hz;
    res.PilotlessAPSKNDAResidualCFOApplied = ...
        pilotlessAPSKInfo.NDAResidualCFOApplied;
    res.PilotlessAPSKMthPowerPhaseTrackerApplied = ...
        pilotlessAPSKInfo.MthPowerPhaseTrackerApplied;
    res.PilotlessAPSKMthPowerPhaseFinalCorrection_deg = ...
        pilotlessAPSKInfo.MthPowerPhaseFinalCorrection_deg;
    res.PilotlessAPSKMthPowerPhaseMedianConfidence = ...
        pilotlessAPSKInfo.MthPowerPhaseMedianConfidence;
    res.PilotlessAPSKBlindPhaseSearchApplied = ...
        pilotlessAPSKInfo.BlindPhaseSearchApplied;
    res.PilotlessAPSKBlindPhaseSearchReliableRate = ...
        pilotlessAPSKInfo.BlindPhaseSearchReliableFraction;
    res.PilotlessAPSKBlindPhaseSearchMedianMetric = ...
        pilotlessAPSKInfo.BlindPhaseSearchMedianMetric;
    res.PilotlessAPSKBlindPhaseSearchFinalCorrection_deg = ...
        pilotlessAPSKInfo.BlindPhaseSearchFinalCorrection_deg;
    res.PilotlessAPSKSharedReliabilityApplied = ...
        logical(pilotlessAPSKInfo.SharedReliabilityMaskProvided);
    res.PilotlessAPSKSharedReliabilityHoldSymbols = ...
        pilotlessAPSKInfo.SharedReliabilityHoldSymbols;
    res.PilotlessAPSKSharedReliabilityHoldFraction = ...
        pilotlessAPSKInfo.SharedReliabilityHoldFraction;
    res.PilotlessAPSKPreDDGainApplied = ...
        pilotlessAPSKInfo.PreDDGainTrackerApplied;
    res.PilotlessAPSKPreDDGainAcceptanceRate = ...
        pilotlessAPSKInfo.PreDDGainAcceptanceRate;
    res.PilotlessAPSKPreDDGainHoldFraction = ...
        pilotlessAPSKInfo.PreDDGainHoldFraction;
    res.PilotlessAPSKPreDDGainFadeFraction = ...
        pilotlessAPSKInfo.PreDDGainFadeFraction;
    res.PilotlessAPSKPreDDGainFinalMagnitude_dB = ...
        pilotlessAPSKInfo.PreDDGainFinalMagnitude_dB;
    res.PilotlessAPSKRingNormalizerApplied = ...
        pilotlessAPSKInfo.RingNormalizerApplied;
    res.PilotlessAPSKRingEstimatorMode = ...
        pilotlessAPSKInfo.RingEstimatorMode;
    res.PilotlessAPSKRingAcceptanceRate = ...
        pilotlessAPSKInfo.RingAcceptanceRate;
    res.PilotlessAPSKRingHoldFraction = ...
        pilotlessAPSKInfo.RingHoldFraction;
    res.PilotlessAPSKRingFadeFraction = ...
        pilotlessAPSKInfo.RingFadeFraction;
    res.PilotlessAPSKRingFinalAmplitude_dB = ...
        pilotlessAPSKInfo.RingFinalAmplitude_dB;
    res.PilotlessAPSKCarrierAcceptanceRate = ...
        pilotlessAPSKInfo.CarrierAcceptanceRate;
    res.PilotlessAPSKCarrierHoldFraction = ...
        pilotlessAPSKInfo.CarrierHoldFraction;
    res.PilotlessAPSKCarrierFadeFraction = ...
        pilotlessAPSKInfo.CarrierFadeFraction;
    res.PilotlessAPSKCarrierPhaseErrorRMS_deg = ...
        pilotlessAPSKInfo.CarrierPhaseErrorRMS_deg;
    res.PilotlessAPSKResidualFrequency_Hz = ...
        pilotlessAPSKInfo.FinalResidualFrequency_Hz;
    res.PilotlessAPSKComplexGainEnabled = ...
        pilotlessAPSKInfo.ComplexGainEnabled;
    res.PilotlessAPSKGainAcceptanceRate = ...
        pilotlessAPSKInfo.GainAcceptanceRate;
    res.PilotlessAPSKGainHoldFraction = ...
        pilotlessAPSKInfo.GainHoldFraction;
    res.PilotlessAPSKGainFadeFraction = ...
        pilotlessAPSKInfo.GainFadeFraction;
    res.PilotlessAPSKFinalGainMagnitude_dB = ...
        pilotlessAPSKInfo.FinalGainMagnitude_dB;
    res.PilotlessAPSKFinalGainPhase_deg = ...
        pilotlessAPSKInfo.FinalGainPhase_deg;
    res.PilotlessAPSKGainRegularization = ...
        pilotlessAPSKInfo.GainRegularization;
    res.PilotlessAPSKGainMaxInverseGainDB = ...
        pilotlessAPSKInfo.GainMaxInverseGainDB;
    res.PilotlessAPSKGainInverseMaxObserved_dB = ...
        pilotlessAPSKInfo.GainInverseMaxObserved_dB;
    res.QAMBlindPhaseSearchApplied = qamBlindPhaseInfo.Applied;
    res.QAMBlindPhaseSearchReliableRate = ...
        qamBlindPhaseInfo.ReliableFraction;
    res.QAMBlindPhaseSearchMedianMetric = ...
        qamBlindPhaseInfo.MedianBestMetric;
    res.QAMBlindPhaseSearchFinalCorrection_deg = ...
        qamBlindPhaseInfo.FinalCorrection_deg;
    res.QAMBlindPhaseSearchFadeHoldBlocks = ...
        qamBlindPhaseInfo.FadeHoldBlocks;
    res.QAMBlindPhaseSearchFadeEvents = qamBlindPhaseInfo.FadeEvents;
    res.QAMBlindPhaseSearchFadeRecoveries = ...
        qamBlindPhaseInfo.FadeRecoveries;
    res.QAMBlindPhaseSearchReacquisitions = ...
        qamBlindPhaseInfo.Reacquisitions;
    res.QAMBlindPhaseSearchInitialFrequencyRadPerSymbol = ...
        qamBlindPhaseInfo.InitialFrequencyRadPerSymbol;
    res.QAMPowerGainApplied = qamPowerGainInfo.Applied;
    res.QAMPowerGainAcceptanceRate = qamPowerGainInfo.AcceptanceRate;
    res.QAMPowerGainRegularization = qamPowerGainInfo.Regularization;
    res.QAMPowerGainMaxInverseGainDB = qamPowerGainInfo.MaxInverseGainDB;
    res.QAMPowerGainInverseMaxObserved_dB = ...
        qamPowerGainInfo.InverseGainMaxObserved_dB;
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
        res.fmReceiverMode = getfieldwithdefault( ...
            fmRxInfo,'receiverMode','teacher-loop');
        res.fmBestNormalizedCorrelation = getfieldnumeric( ...
            fmRxInfo,'bestNormalizedCorrelation',NaN);
        res.fmSelectedSamplePhase = getfieldnumeric( ...
            fmRxInfo,'selectedSamplePhase',NaN);
    end


    %传给前端

    % 给绘图用 — fineSynced 应用 best 旋转后再画,星座视觉对齐参考
    ctx.txWaveform   = txWaveform;
    ctx.txAfterUpconverter = txAfterUpconverter;
    ctx.channelInput = txAfterUpconverter;
    ctx.channelOutput = txAfterH;
    ctx.rxNoisyWaveform = rxNoisyWaveform;
    ctx.rxAfterDownconverter = rxAfterDownconverter;
    ctx.rxAfterADC = rxAfterADC;
    ctx.rxWaveform   = rxWaveform;
    ctx.rxWaveformBeforeAGC = rxWaveformBeforeAGC;
    ctx.rxWaveformAfterAGC = rxWaveformAfterAGC;
    ctx.AGCGainTraceTime_s = agcInfo.TraceTime_s;
    ctx.AGCGainTrace_dB = agcInfo.TraceGain_dB;
    ctx.AGCPowerEstimateTrace_dB = agcInfo.TracePowerEstimate_dB;
    ctx.adaptiveEqualizerInfo = adaptiveEqInfo;
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

function sourceType = localTMDataSourceType(opt, rail)
%LOCALTMDATASOURCETYPE Resolve the common or per-I/Q source selection.
    sourceType = char(string(getfieldwithdefault(opt, ...
        'TMDataSource', 'random')));
    rail = upper(char(string(rail)));
    if ~isempty(rail)
        railField = ['TMDataSource', rail];
        if isfield(opt, railField) && ~isempty(opt.(railField))
            sourceType = char(string(opt.(railField)));
        end
    end
end

function sourceOpt = localTMDataSourceOptions(opt, rail)
%LOCALTMDATASOURCEOPTIONS Translate public options to the reusable source.
    sourceOpt = struct();
    mappings = { ...
        'TMDataSourcePNInitialState', 'PNInitialState'; ...
        'TMDataSourcePNPolynomialExponents', 'PNPolynomialExponents'; ...
        'TMDataSourcePNInvert', 'PNInvertOutput'; ...
        'TMDataSourceFixedPattern', 'FixedPattern'; ...
        'TMDataSourceIncrementStart', 'IncrementStart'};
    rail = upper(char(string(rail)));
    for k = 1:size(mappings,1)
        publicName = mappings{k,1};
        helperName = mappings{k,2};
        if isfield(opt, publicName) && ~isempty(opt.(publicName))
            sourceOpt.(helperName) = opt.(publicName);
        end
        if ~isempty(rail)
            railName = [publicName, rail];
            if isfield(opt, railName) && ~isempty(opt.(railName))
                sourceOpt.(helperName) = opt.(railName);
            end
        end
    end
    sourceOpt.Debug = false;
end

function numBytes = localTMSourceRequestBytes(tfOpt, fullFrameBytes, sourceType)
% Preserve the historical random-data RNG consumption exactly.  Patterned
% sources advance only through the bytes that are actually placed in the TM
% data field, matching a continuous equipment test-pattern generator.
    if strcmpi(string(sourceType), 'random')
        numBytes = double(fullFrameBytes);
        return;
    end
    secondaryLength = 0;
    if isfield(tfOpt, 'HasSecondaryHeader') && logical(tfOpt.HasSecondaryHeader) && ...
            isfield(tfOpt, 'SecondaryHeader')
        secondaryLength = numel(tfOpt.SecondaryHeader);
    end
    ocfLength = 4 * double(isfield(tfOpt, 'HasOCF') && logical(tfOpt.HasOCF));
    fecfLength = 2 * double(isfield(tfOpt, 'HasFECF') && logical(tfOpt.HasFECF));
    numBytes = double(tfOpt.FrameLengthBytes) - 6 - secondaryLength - ...
        ocfLength - fecfLength;
    if numBytes < 1
        error('run_ccsds_tm_evaluation:TMDataSourceFieldTooShort', ...
            'TM frame has no data-field bytes available for TMDataSource.');
    end
end

function fields = localAttachTMDataSourceInfo(fields, sourceInfo, rail)
    fields.TMDataSource = char(sourceInfo.CanonicalType);
    fields.TMDataSourceRail = char(string(rail));
    fields.TMDataSourcePolynomial = localTMSourcePolynomial(sourceInfo);
    if isfield(sourceInfo, 'FixedPatternHex')
        fields.TMDataSourceFixedPatternHex = sourceInfo.FixedPatternHex;
    end
end

function polynomial = localTMSourcePolynomial(sourceInfo)
    polynomial = '';
    if isstruct(sourceInfo) && isfield(sourceInfo, 'Polynomial') && ...
            ~isempty(sourceInfo.Polynomial)
        polynomial = char(sourceInfo.Polynomial);
    end
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
    % This is the absolute signal level assigned to referenceSignal before
    % receiver noise is added.  Keep the historical inputLevelDbm aliases,
    % but also accept names that make the TX/link-budget meaning explicit.
    names = {'transmitOutputLevelDbm','txOutputLevelDbm', ...
        'outputLevelDbm','signalReferenceLevelDbm', ...
        'inputLevelDbm','input_level_dbm', ...
        'outputPowerDbm','output_power_dbm'};
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
    fmParams.fmReceiverMode = char(string(getfieldwithdefault( ...
        opt,'fmReceiverMode','matched-training')));
    fmParams.fmTrainingMinNormalizedCorrelation = double(getf( ...
        opt,'fmTrainingMinNormalizedCorrelation',0.65));
    fmParams.fmTrainingSearchSymbols = double(getf( ...
        opt,'fmTrainingSearchSymbols',8));
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
    % Diagnostic-only channel decomposition.  This is deliberately not a
    % frontend control and must never be used as a production equalizer.
    % It isolates whether acquisition is being broken by the magnitude or
    % phase part of the same time-varying H realization.
    debugResponseMode = lower(strtrim(char(getOptionString(opt, ...
        {'debugHMatrixResponseMode'}, "normal"))));
    switch debugResponseMode
        case {'normal',''}
            debugResponseMode = 'normal';
        case 'magnitude-only'
            coeff = abs(coeff);
        case 'phase-only'
            coeff = coeff ./ max(abs(coeff), eps);
        case 'frozen'
            coeff = repmat(coeff(:,1), 1, size(coeff,2));
        otherwise
            error('run_ccsds_tm_evaluation:InvalidDebugHMatrixResponseMode', ...
                ['debugHMatrixResponseMode must be "normal", ', ...
                 '"magnitude-only", "phase-only", or "frozen".']);
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
    dominantCoeff = coeff(dominantPathIndex,:);
    dominantMagnitude = abs(dominantCoeff);
    finiteMagnitude = dominantMagnitude(isfinite(dominantMagnitude));
    if isempty(finiteMagnitude)
        magnitudeMin = NaN;
        magnitudeMedian = NaN;
        magnitudeMax = NaN;
        magnitudeDynamicRange_dB = NaN;
        deepFadeFraction20dB = NaN;
    else
        magnitudeMin = min(finiteMagnitude);
        magnitudeMedian = median(finiteMagnitude);
        magnitudeMax = max(finiteMagnitude);
        positiveMagnitude = finiteMagnitude(finiteMagnitude > 0);
        if isempty(positiveMagnitude)
            magnitudeDynamicRange_dB = Inf;
        else
            magnitudeDynamicRange_dB = 20*log10( ...
                magnitudeMax/max(min(positiveMagnitude),eps));
        end
        deepFadeFraction20dB = mean( ...
            finiteMagnitude <= 0.1*max(magnitudeMedian,eps));
    end
    if numel(dominantCoeff) >= 2 && isfinite(magnitudeMedian)
        phaseUsable = dominantMagnitude(1:end-1) > 0.1*max(magnitudeMedian,eps) & ...
            dominantMagnitude(2:end) > 0.1*max(magnitudeMedian,eps);
        phaseStep = angle(dominantCoeff(2:end).*conj(dominantCoeff(1:end-1)));
        phaseStep = phaseStep(phaseUsable & isfinite(phaseStep));
    else
        phaseStep = [];
    end
    if isempty(phaseStep)
        phaseStepRMS_deg = NaN;
        phaseStepMax_deg = NaN;
    else
        phaseStepRMS_deg = rad2deg(sqrt(mean(phaseStep.^2)));
        phaseStepMax_deg = rad2deg(max(abs(phaseStep)));
    end

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
    meta.DominantMagnitudeMin = magnitudeMin;
    meta.DominantMagnitudeMedian = magnitudeMedian;
    meta.DominantMagnitudeMax = magnitudeMax;
    meta.DominantMagnitudeDynamicRange_dB = magnitudeDynamicRange_dB;
    meta.DominantDeepFadeFractionBelowMinus20dB = deepFadeFraction20dB;
    meta.DominantPhaseStepRMS_deg = phaseStepRMS_deg;
    meta.DominantPhaseStepMax_deg = phaseStepMax_deg;
    meta.PowerDbMean = mean(powerDbSeries(:));
    meta.DebugResponseMode = debugResponseMode;
    dopplerRaw = getLoadedChannelField(ch, ...
        {'doppler','Doppler','dopplerHz','DopplerHz'});
    dopplerValues = double(dopplerRaw(:));
    dopplerValues = dopplerValues(isfinite(dopplerValues));
    if isempty(dopplerValues)
        meta.DopplerCenterMean_Hz = NaN;
        meta.DopplerMin_Hz = NaN;
        meta.DopplerMax_Hz = NaN;
    else
        meta.DopplerCenterMean_Hz = mean(dopplerValues);
        meta.DopplerMin_Hz = min(dopplerValues);
        meta.DopplerMax_Hz = max(dopplerValues);
    end
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

    mode = lower(getOptionString( ...
        opt, {'equalizerMode','channelEqualizerMode'}, "mmse"));
    if localIsAdaptiveEqualizerMode(mode)
        % The blind path must never receive oracle H compensation.  Its CMA
        % FSE runs after the receive filter and its optional DD stage runs
        % after timing/carrier recovery, for both static-H and H-matrix tests.
        return;
    end

    if nargin >= 5 && isstruct(hState) && isfield(hState,'hasHMatrix') && logical(hState.hasHMatrix)
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
    hComplex = hState.pathCoeff(dominantPath, :);
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
        'MinAbsH_dB', {}, 'RmsAbsH_dB', {}, 'MedianAbsH_dB', {}, 'MaxAbsH_dB', {}, ...
        'HDopplerMedian_Hz', {}, 'HDopplerRMS_Hz', {}, ...
        'HDopplerMaxAbs_Hz', {});
    for frameIdx = startFrame:endFrame
        idx = (frameIdx-1)*samplesPerFrame + (1:samplesPerFrame);
        idx = idx(idx <= numel(hAbs));
        a = hAbs(idx);
        hFrame = hComplex(idx);
        if isempty(a)
            continue;
        end
        minA = min(a);
        rmsA = sqrt(mean(a.^2));
        medA = median(a);
        maxA = max(a);
        t0 = (idx(1)-1) / double(Fs);
        t1 = idx(end) / double(Fs);
        if numel(hFrame) >= 2
            phaseStep = angle(hFrame(2:end).*conj(hFrame(1:end-1)));
            phaseValid = a(1:end-1) > 0.1*max(medA,eps) & ...
                a(2:end) > 0.1*max(medA,eps) & isfinite(phaseStep);
            phaseStep = phaseStep(phaseValid);
        else
            phaseStep = [];
        end
        if isempty(phaseStep)
            hDopplerMedian = NaN;
            hDopplerRMS = NaN;
            hDopplerMax = NaN;
        else
            hDoppler = phaseStep*double(Fs)/(2*pi);
            hDopplerMedian = median(hDoppler);
            hDopplerRMS = sqrt(mean(hDoppler.^2));
            hDopplerMax = max(abs(hDoppler));
        end
        fprintf(['      frame=%03d t=[%.6f %.6f] s |h| min/rms/med/max = ' ...
                 '%.4g/%.4g/%.4g/%.4g  dB=%.2f/%.2f/%.2f/%.2f ' ...
                 'Hdoppler[med/rms/max]=%+.1f/%.1f/%.1f Hz\n'], ...
            frameIdx, t0, t1, minA, rmsA, medA, maxA, ...
            20*log10(max(minA, eps)), 20*log10(max(rmsA, eps)), ...
            20*log10(max(medA, eps)), 20*log10(max(maxA, eps)), ...
            hDopplerMedian,hDopplerRMS,hDopplerMax);

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
        frameStats(end).HDopplerMedian_Hz = hDopplerMedian;
        frameStats(end).HDopplerRMS_Hz = hDopplerRMS;
        frameStats(end).HDopplerMaxAbs_Hz = hDopplerMax;
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

    noiseMode = lower(strtrim(getOptionString(opt, ...
        {'noiseMode','receiverNoiseMode','awgnMode'}, "psd")));
    noiseModeKey = string(erase(noiseMode, ["_","-"," "]));
    disableNoise = any(noiseModeKey == ...
        ["off","none","disabled","noiseless","ideal"]);
    useMeasuredSNR = any(noiseModeKey == ...
        ["snr","measured","legacy","legacymeasured","awgn"]);

    % A true noise-free path is useful for separating deterministic
    % synchronization/equalization errors from link-margin limitations.
    % Do not emulate this with an extremely large SNR: that still consumes
    % RNG state and is not an exact identity channel.
    if disableNoise
        yOut = xIn;
        noiseInfo = struct( ...
            'Mode', "off", ...
            'SNR_dB', Inf, ...
            'PSD_dBmHz', NaN, ...
            'BandwidthHz', NaN, ...
            'NoisePower_dBm', -Inf, ...
            'ReferenceLevel_dBm', getInputLevelDbm(opt, -10), ...
            'EquivalentSNR_dB', Inf);
        return;
    end

    psd_dBmHz = getOptionDouble(opt, ...
        {'noisePSDdBmHz','noisePsdDbmHz','noisePSD_dBmHz', ...
         'noisePowerSpectralDensityDbmHz','noiseDensityDbmHz', ...
         'noisePSDdBmPerHz','N0dBmHz','N0_dBmHz'}, -115.3);
    if useMeasuredSNR
        yOut = awgn(xIn, snr_dB, 'measured');
        return;
    end
    if ~isfinite(psd_dBmHz)
        psd_dBmHz = -115.3;
    end

    noiseBandwidthHz = getOptionDouble(opt, ...
        {'noiseBandwidthHz','noiseBWHz','noiseBandwidth','NoiseBandwidthHz'}, NaN);
    if ~isfinite(noiseBandwidthHz) || noiseBandwidthHz <= 0
        % For complex baseband, integrate the two-sided PSD over the
        % occupied RRC bandwidth.  Users can override this with the actual
        % receiver equivalent-noise bandwidth.
        symbolRateHz = getOptionDouble(opt, ...
            {'symbolRate','SymbolRate','symbol_rate'}, NaN);
        rolloff = getOptionDouble(opt, ...
            {'RolloffFactor','rolloffFactor','rolloff'}, 0.35);
        if isfinite(symbolRateHz) && symbolRateHz > 0 && ...
                isfinite(rolloff) && rolloff >= 0
            noiseBandwidthHz = min(sampleRateHz, (1 + rolloff)*symbolRateHz);
        else
            noiseBandwidthHz = sampleRateHz;
        end
    end

    referencePowerDigital = mean(abs(referenceSignal(:)).^2) + eps;
    referenceLevel_dBm = getInputLevelDbm(opt, -10);
    signalPowerW = 1e-3 * 10.^(referenceLevel_dBm/10);
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
        'ReferenceLevel_dBm', referenceLevel_dBm, ...
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
    if localIsAdaptiveEqualizerMode(mode)
        return;
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

function tf = localIsAdaptiveEqualizerMode(mode)
    mode = lower(string(mode));
    tf = any(strcmp(mode, [ ...
        "blind-cma-lms", "cma-dd-nlms", "cma-lms", ...
        "adaptive-cma-lms", "blind", "dd-nlms", ...
        "asm-training-nlms"]));
end

function levelDBm = localReceiverNoisePowerDBm(noiseInfo, fallbackSignalLevelDBm)
    levelDBm = -Inf;
    if isstruct(noiseInfo) && isfield(noiseInfo, 'NoisePower_dBm') && ...
            isfinite(noiseInfo.NoisePower_dBm)
        levelDBm = double(noiseInfo.NoisePower_dBm);
        return;
    end
    if isstruct(noiseInfo) && isfield(noiseInfo, 'EquivalentSNR_dB') && ...
            isfinite(noiseInfo.EquivalentSNR_dB)
        levelDBm = fallbackSignalLevelDBm - double(noiseInfo.EquivalentSNR_dB);
    end
end

function totalDBm = localSumPowerDBm(varargin)
    totalW = 0;
    for k = 1:nargin
        value = double(varargin{k});
        if isfinite(value)
            totalW = totalW + 1e-3 * 10.^(value/10);
        end
    end
    if totalW <= 0
        totalDBm = -Inf;
    else
        totalDBm = 10*log10(totalW/1e-3);
    end
end

function info = localDisabledConverterInfo(stageName, levelDBm)
    info = struct( ...
        'Enabled', false, ...
        'StageName', char(stageName), ...
        'InputSignalLevelDBm', levelDBm, ...
        'InputTotalLevelDBm', levelDBm, ...
        'FixedGainDB', 0, ...
        'RequestedAttenuationDB', 0, ...
        'AppliedAttenuationDB', 0, ...
        'ConfiguredNetGainDB', 0, ...
        'NetGainDB', 0, ...
        'OutputSignalLevelDBm', levelDBm, ...
        'OutputTotalLevelDBm', levelDBm, ...
        'CompressionRisk', false, ...
        'EstimatedCompressionDB', 0, ...
        'IdealPeakOutputLevelDBm', levelDBm, ...
        'AutoAttenuation', false, ...
        'InputWithinTypicalRange', false);
end

function info = localDisabledADCInfo()
    info = struct( ...
        'Enabled', false, ...
        'Bits', NaN, ...
        'FullScalePowerDBm', NaN, ...
        'InputTotalLevelDBm', NaN, ...
        'RMSBackoffDB', NaN, ...
        'ClipFraction', 0, ...
        'QuantizationSNRDB', Inf);
end

function localPrintConverterChain(basebandIFLevelDBm, upInfo, hGainDB, ...
        noiseInfo, downInfo, adcInfo)
    fprintf('\n[TM converter chain]\n');
    fprintf('  baseband/IF reference : %+.2f dBm\n', basebandIFLevelDBm);
    fprintf(['  upconverter           : fixed=%+.2f dB, atten=%.2f dB, ', ...
        'net=%+.2f dB, output=%+.2f dBm\n'], ...
        upInfo.FixedGainDB, upInfo.AppliedAttenuationDB, ...
        upInfo.NetGainDB, upInfo.OutputSignalLevelDBm);
    fprintf('  H applied mean gain   : %+.2f dB\n', hGainDB);
    if isfield(noiseInfo, 'NoisePower_dBm') && isfinite(noiseInfo.NoisePower_dBm)
        fprintf('  receiver noise power  : %+.2f dBm\n', noiseInfo.NoisePower_dBm);
    end
    fprintf(['  downconverter         : input=%+.2f dBm, fixed=%+.2f dB, ', ...
        'atten=%.2f dB, net=%+.2f dB, output=%+.2f dBm\n'], ...
        downInfo.InputSignalLevelDBm, downInfo.FixedGainDB, ...
        downInfo.AppliedAttenuationDB, downInfo.NetGainDB, ...
        downInfo.OutputSignalLevelDBm);
    if downInfo.AutoAttenuation
        fprintf('  downconverter control : automatic attenuation, target=%+.2f dBm\n', ...
            downInfo.TargetOutputTotalLevelDBm);
    end
    fprintf('  input range check     : up=%d, down=%d (typical -60..-10 dBm)\n', ...
        upInfo.InputWithinTypicalRange, downInfo.InputWithinTypicalRange);
    fprintf('  P1dB risk             : up=%d, down=%d\n', ...
        upInfo.CompressionRisk, downInfo.CompressionRisk);
    if adcInfo.Enabled
        fprintf(['  ADC equivalent        : %d bit, FS=%+.2f dBm, ', ...
            'backoff=%.2f dB, clip=%.4g%%, qSNR=%.2f dB\n'], ...
            adcInfo.Bits, adcInfo.FullScalePowerDBm, adcInfo.RMSBackoffDB, ...
            100*adcInfo.ClipFraction, adcInfo.QuantizationSNRDB);
    else
        fprintf('  ADC equivalent        : disabled (full-scale not yet calibrated)\n');
    end
end

function tf = localIsASMTrainingEqualizerMode(mode)
    tf = strcmpi(string(mode),'asm-training-nlms');
end

function [tf,reason] = localSupportsASMTrainingEqualizer( ...
        modStr,codeStr,opt,hasASM)
    modulation = upper(string(modStr));
    coding = lower(string(codeStr));
    pcmFormat = upper(string(getfieldwithdefault(opt,'PCMFormat','NRZ-L')));
    tf = false;
    if ~logical(hasASM)
        reason = 'asm-training-nlms requires hasASM=true';
        return;
    end
    if ~any(strcmp(modulation,["QPSK","16QAM"]))
        reason = sprintf( ...
            'asm-training-nlms is isolated to QPSK/16QAM; %s bypassed', ...
            char(modulation));
        return;
    end
    if any(strcmp(coding, ["convolutional", "concatenated"])) || contains(coding,'tpc')
        reason = sprintf( ...
            ['asm-training-nlms first version requires a raw transmitted ', ...
             'ASM; coding=%s encodes/groups the ASM and is bypassed'], ...
            char(coding));
        return;
    end
    if pcmFormat ~= "NRZ-L"
        reason = sprintf( ...
            'asm-training-nlms first version requires NRZ-L, not %s', ...
            char(pcmFormat));
        return;
    end
    tf = true;
    reason = 'supported';
end

function tf = localSupportsTMBlindAdaptiveModulation(modStr)
    s = upper(string(modStr));
    tf = any(contains(s, [ ...
        "BPSK", "QPSK", "8PSK", "16QAM", "32QAM", ...
        "16APSK", "32APSK"]));
    % UQPSK has a dedicated 2-sps timing/carrier front end, but its output is
    % a synchronized 1-sps rectangular four-point stream and can therefore
    % safely use the public common blind equalizer. OQPSK/CPM retain their
    % dedicated rail/continuous-phase processing.
    tf = tf && ~any(contains(s, [ ...
        "OQPSK", "MSK", "GMSK", "4D-8PSK-TCM", "FACM"]));
end

function info = localEmptyTMAdaptiveEqualizerInfo()
    info = struct( ...
        'Enabled',false, ...
        'Mode','off', ...
        'NumTaps',0, ...
        'CMADelay',0, ...
        'CMASymbols',0, ...
        'DDPasses',0, ...
        'DDPassesRequested',0, ...
        'CMAStep',NaN, ...
        'DDStep',NaN, ...
        'CMAR2',NaN, ...
        'BlindCostMode','off', ...
        'DecisionGate',NaN, ...
        'PhaseRotation_deg',NaN, ...
        'PhaseStructureScore',NaN, ...
        'CMASwitchMSE',NaN, ...
        'CMAConfidenceRate',NaN, ...
        'CMAQualified',false, ...
        'InputPower',NaN, ...
        'OutputPower',NaN, ...
        'AcceptedDecisions',0, ...
        'RejectedDecisions',0, ...
        'DecisionCount',0, ...
        'AcceptanceRate',NaN, ...
        'CMAMSE',NaN, ...
        'DDMSE',NaN, ...
        'FinalTapNorm',NaN, ...
        'EqualizerStructure','off', ...
        'SideTapEnergyRatio',NaN, ...
        'DDWindowSymbols',0, ...
        'DDMinWindowAcceptance',NaN, ...
        'DDWindowCount',0, ...
        'DDGoodWindows',0, ...
        'DDHoldWindows',0, ...
        'DDFadeHoldWindows',0, ...
        'DDFadeEnterEvents',0, ...
        'DDFadeRecoverEvents',0, ...
        'FadeHoldDB',NaN, ...
        'FadeRecoverDB',NaN, ...
        'FadeDetectorSymbols',0, ...
        'DDHoldReason','', ...
        'InputStructureMSE',NaN, ...
        'OutputStructureMSE',NaN, ...
        'QualityImprovement',NaN, ...
        'OutputAccepted',false, ...
        'RollbackReason','', ...
        'Converged',false, ...
        'Reason','disabled');
end

function info = localEmptyTMSyncDiagnostics()
    info = struct( ...
        'Enabled',false, ...
        'ConfiguredCFO_Hz',NaN, ...
        'CoarseCFOEstimate_Hz',NaN, ...
        'TimingInputSamples',0, ...
        'TimingInputSamplesPerSymbol',NaN, ...
        'TimingExpectedSymbols',NaN, ...
        'TimingOutputSymbols',0, ...
        'TimingRateError_ppm',NaN, ...
        'Stages',struct([]), ...
        'AdaptiveEqualizerDDMSE',NaN, ...
        'AdaptiveEqualizerAcceptanceRate',NaN, ...
        'ASMPhaseTimeline',struct('Available',false), ...
        'ASMPhaseCycleSlipCount',0, ...
        'ASMPhaseAmbiguousFrames',0, ...
        'SuspectTimingRate',false, ...
        'SuspectCarrierResidual',false, ...
        'SuspectPhaseCycleSlip',false, ...
        'SuspectEqualizerDegradation',false, ...
        'Summary','disabled');
end

function info = localBuildTMSyncDiagnostics( ...
        stages, refConst, symbolRate, configuredCFO, ...
        adaptiveEqInfo, berStats, opt)
    info = localEmptyTMSyncDiagnostics();
    info.Enabled = true;
    info.ConfiguredCFO_Hz = configuredCFO;
    info.CoarseCFOEstimate_Hz = stages.CoarseEstimate_Hz;
    info.TimingInputSamples = numel(stages.Filtered);
    info.TimingInputSamplesPerSymbol = stages.FilterSamplesPerSymbol;
    if isfinite(stages.FilterSamplesPerSymbol) && ...
            stages.FilterSamplesPerSymbol > 0
        info.TimingExpectedSymbols = ...
            numel(stages.Filtered)/stages.FilterSamplesPerSymbol;
        info.TimingOutputSymbols = numel(stages.Timing);
        info.TimingRateError_ppm = 1e6 * ...
            (info.TimingOutputSymbols-info.TimingExpectedSymbols) / ...
            max(info.TimingExpectedSymbols,1);
    end

    stageNames = {'postTiming','postCarrier','pilotInput','postPilot', ...
        'preEQTracker','postEqualizer','postEQTracker'};
    stageSignals = {stages.Timing,stages.Carrier,stages.PilotInput, ...
        stages.Pilot,stages.PreEQTracker,stages.Equalizer, ...
        stages.PostEQTracker};
    stageResult = repmat(localEmptyTMSymbolStageDiagnostics(),0,1);
    for iStage = 1:numel(stageNames)
        if isempty(stageSignals{iStage})
            continue;
        end
        stageResult(end+1,1) = localTMSymbolStageDiagnostics( ...
            stageNames{iStage},stageSignals{iStage},refConst, ...
            symbolRate,opt); %#ok<AGROW>
    end
    info.Stages = stageResult;

    info.AdaptiveEqualizerDDMSE = adaptiveEqInfo.DDMSE;
    info.AdaptiveEqualizerAcceptanceRate = adaptiveEqInfo.AcceptanceRate;

    if isstruct(berStats) && isfield(berStats,'ASMPhaseTimeline')
        info.ASMPhaseTimeline = berStats.ASMPhaseTimeline;
        if getLogicalField(info.ASMPhaseTimeline,'Available',false)
            info.ASMPhaseCycleSlipCount = ...
                info.ASMPhaseTimeline.CycleSlipCount;
            info.ASMPhaseAmbiguousFrames = ...
                info.ASMPhaseTimeline.AmbiguousFrames;
        end
    end

    timingRateThreshold = abs(getfieldnumeric(opt, ...
        'debugTimingRateErrorThreshold_ppm',5000));
    carrierResidualThreshold = abs(getfieldnumeric(opt, ...
        'debugCarrierResidualThreshold_Hz',100));
    info.SuspectTimingRate = isfinite(info.TimingRateError_ppm) && ...
        abs(info.TimingRateError_ppm) > timingRateThreshold;
    carrierStage = localFindTMSyncStage(info.Stages,'preEQTracker');
    if ~carrierStage.Available
        carrierStage = localFindTMSyncStage(info.Stages,'postPilot');
    end
    if ~carrierStage.Available
        carrierStage = localFindTMSyncStage(info.Stages,'postCarrier');
    end
    info.SuspectCarrierResidual = carrierStage.Available && ...
        isfinite(carrierStage.ResidualCFO_Hz) && ...
        abs(carrierStage.ResidualCFO_Hz) > carrierResidualThreshold;
    info.SuspectPhaseCycleSlip = info.ASMPhaseCycleSlipCount > 0;
    eqStage = localFindTMSyncStage(info.Stages,'postEqualizer');
    carrierStage = localFindTMSyncStage(info.Stages,'postCarrier');
    info.SuspectEqualizerDegradation = eqStage.Available && ...
        carrierStage.Available && isfinite(eqStage.StructureMSE) && ...
        isfinite(carrierStage.StructureMSE) && ...
        eqStage.StructureMSE > max(1.25*carrierStage.StructureMSE, ...
            carrierStage.StructureMSE+1e-3);

    suspects = strings(0,1);
    if info.SuspectTimingRate, suspects(end+1) = "timing-rate"; end
    if info.SuspectCarrierResidual, suspects(end+1) = "carrier-residual"; end
    if info.SuspectPhaseCycleSlip, suspects(end+1) = "ASM-phase-slip"; end
    if info.SuspectEqualizerDegradation, suspects(end+1) = "equalizer"; end
    if isempty(suspects)
        info.Summary = 'no scalar threshold fired; inspect segment and ASM timeline';
    else
        info.Summary = char(strjoin(suspects,','));
    end
end

function stage = localEmptyTMSymbolStageDiagnostics()
    stage = struct( ...
        'Available',false, ...
        'Name','', ...
        'NumSymbols',0, ...
        'Power_dB',NaN, ...
        'StructureMSE',NaN, ...
        'RadialEVM_pct',NaN, ...
        'TangentialEVM_pct',NaN, ...
        'RadiusRMS_dB',NaN, ...
        'ResidualCFO_Hz',NaN, ...
        'PhaseMean_deg',NaN, ...
        'PhaseJitter_deg',NaN, ...
        'SegmentIndex',zeros(0,1), ...
        'SegmentStartSymbol',zeros(0,1), ...
        'SegmentEndSymbol',zeros(0,1), ...
        'SegmentPower_dB',zeros(0,1), ...
        'SegmentStructureMSE',zeros(0,1), ...
        'SegmentResidualCFO_Hz',zeros(0,1), ...
        'SegmentPhaseMean_deg',zeros(0,1), ...
        'SegmentPhaseJitter_deg',zeros(0,1));
end

function stage = localTMSymbolStageDiagnostics( ...
        name,symbols,refConst,symbolRate,opt)
    stage = localEmptyTMSymbolStageDiagnostics();
    symbols = complex(symbols(:));
    refConst = complex(refConst(:));
    if isempty(symbols) || isempty(refConst)
        return;
    end
    stage.Available = true;
    stage.Name = char(name);
    stage.NumSymbols = numel(symbols);
    stage.Power_dB = 10*log10(mean(abs(symbols).^2)+eps);
    [stage.StructureMSE,stage.ResidualCFO_Hz, ...
        stage.PhaseMean_deg,stage.PhaseJitter_deg] = ...
        localTMSymbolResidualMetrics(symbols,refConst,symbolRate);
    [stage.RadialEVM_pct,stage.TangentialEVM_pct,~, ...
        stage.RadiusRMS_dB] = ...
        localConstellationResidualComponents(symbols,refConst);

    nSegments = max(1,round(getfieldnumeric(opt, ...
        'debugSyncSegmentCount',8)));
    nSegments = min(nSegments,max(1,floor(numel(symbols)/64)));
    edges = round(linspace(1,numel(symbols)+1,nSegments+1));
    stage.SegmentIndex = (1:nSegments).';
    stage.SegmentStartSymbol = edges(1:end-1).';
    stage.SegmentEndSymbol = (edges(2:end)-1).';
    stage.SegmentPower_dB = NaN(nSegments,1);
    stage.SegmentStructureMSE = NaN(nSegments,1);
    stage.SegmentResidualCFO_Hz = NaN(nSegments,1);
    stage.SegmentPhaseMean_deg = NaN(nSegments,1);
    stage.SegmentPhaseJitter_deg = NaN(nSegments,1);
    for iSegment = 1:nSegments
        index = edges(iSegment):edges(iSegment+1)-1;
        z = symbols(index);
        stage.SegmentPower_dB(iSegment) = ...
            10*log10(mean(abs(z).^2)+eps);
        [stage.SegmentStructureMSE(iSegment), ...
            stage.SegmentResidualCFO_Hz(iSegment), ...
            stage.SegmentPhaseMean_deg(iSegment), ...
            stage.SegmentPhaseJitter_deg(iSegment)] = ...
            localTMSymbolResidualMetrics(z,refConst,symbolRate);
    end
end

function [structureMSE,residualCFO,phaseMean,phaseJitter] = ...
        localTMSymbolResidualMetrics(symbols,refConst,symbolRate)
    symbols = complex(symbols(:));
    refConst = complex(refConst(:));
    structureMSE = NaN;
    residualCFO = NaN;
    phaseMean = NaN;
    phaseJitter = NaN;
    valid = isfinite(real(symbols)) & isfinite(imag(symbols));
    symbols = symbols(valid);
    if numel(symbols) < 16
        return;
    end
    z = symbols / sqrt(mean(abs(symbols).^2)+eps);
    refNorm = refConst / sqrt(mean(abs(refConst).^2)+eps);
    [distance,decisionIndex] = min(abs(z-refNorm.'),[],2);
    decisions = refNorm(decisionIndex);
    structureMSE = mean(distance.^2);
    phaseError = angle(z.*conj(decisions));
    phaseUnwrapped = unwrap(phaseError);
    n = (0:numel(z)-1).';
    coefficient = polyfit(n,phaseUnwrapped,1);
    residualCFO = coefficient(1)*symbolRate/(2*pi);
    detrended = phaseUnwrapped-polyval(coefficient,n);
    phaseMean = rad2deg(angle(mean(exp(1j*phaseError))));
    phaseJitter = rad2deg(sqrt(mean(detrended.^2)));
end

function stage = localFindTMSyncStage(stages,name)
    stage = localEmptyTMSymbolStageDiagnostics();
    if isempty(stages)
        return;
    end
    names = string({stages.Name});
    index = find(strcmpi(names,string(name)),1,'first');
    if ~isempty(index)
        stage = stages(index);
    end
end

function localPrintTMSyncDiagnostics(info)
    fprintf('\n[TM synchronization diagnostics]\n');
    fprintf(['  coarse CFO configured/estimated : %+.3f / %+.3f Hz\n'], ...
        info.ConfiguredCFO_Hz,info.CoarseCFOEstimate_Hz);
    fprintf(['  timing input/expected/output    : %d / %.3f / %d ', ...
        '(rate error=%+.1f ppm)\n'], ...
        info.TimingInputSamples,info.TimingExpectedSymbols, ...
        info.TimingOutputSymbols,info.TimingRateError_ppm);
    fprintf(['  stage             symbols  power(dB) structure radial%% tang%% ', ...
        'radiusdB resCFO(Hz) phaseMean phaseJitter\n']);
    for iStage = 1:numel(info.Stages)
        stage = info.Stages(iStage);
        fprintf(['  %-16s %7d %9.3f %9.4g %7.2f %6.2f %8.3f ', ...
            '%10.3f %9.2f %11.2f\n'], ...
            stage.Name,stage.NumSymbols,stage.Power_dB, ...
            stage.StructureMSE,stage.RadialEVM_pct, ...
            stage.TangentialEVM_pct,stage.RadiusRMS_dB, ...
            stage.ResidualCFO_Hz, ...
            stage.PhaseMean_deg,stage.PhaseJitter_deg);
    end
    eqStage = localFindTMSyncStage(info.Stages,'postEqualizer');
    if eqStage.Available
        fprintf(['  [postEqualizer segments] seg symbols power structure ', ...
            'resCFO phaseJitter\n']);
        for iSegment = 1:numel(eqStage.SegmentIndex)
            fprintf('      %2d %7d:%-7d %7.2f %9.4g %+9.2f %9.2f\n', ...
                eqStage.SegmentIndex(iSegment), ...
                eqStage.SegmentStartSymbol(iSegment), ...
                eqStage.SegmentEndSymbol(iSegment), ...
                eqStage.SegmentPower_dB(iSegment), ...
                eqStage.SegmentStructureMSE(iSegment), ...
                eqStage.SegmentResidualCFO_Hz(iSegment), ...
                eqStage.SegmentPhaseJitter_deg(iSegment));
        end
    end
    fprintf(['  flags timing/carrier/phaseSlip/equalizer = ', ...
        '%d/%d/%d/%d | %s\n\n'], ...
        info.SuspectTimingRate,info.SuspectCarrierResidual, ...
        info.SuspectPhaseCycleSlip,info.SuspectEqualizerDegradation, ...
        info.Summary);
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

function [radialPct,tangentialPct,phaseRMSDeg,radiusRMSDB] = ...
        localConstellationResidualComponents(rxSym,refConst)
% Decision-directed decomposition of the same tail segment used by EVM.
% Radial error exposes amplitude/ring-radius residuals; tangential error
% exposes phase residuals.  This is diagnostic only and does not alter the
% received symbols or use transmitted payload bits.
radialPct = NaN;
tangentialPct = NaN;
phaseRMSDeg = NaN;
radiusRMSDB = NaN;
if isempty(rxSym) || isempty(refConst), return; end

rx = rxSym(:);
L = min(numel(rx),5000);
rx = rx(end-L+1:end);
ref = refConst(:);
[~,idx] = min(abs(rx-ref.'),[],2);
ideal = ref(idx);
valid = isfinite(real(rx)) & isfinite(imag(rx)) & abs(ideal) > sqrt(eps);
if ~any(valid), return; end
rx = rx(valid);
ideal = ideal(valid);

unitIdeal = ideal./abs(ideal);
localError = (rx-ideal).*conj(unitIdeal);
referencePower = mean(abs(ref).^2);
radialPct = 100*sqrt(mean(real(localError).^2)/max(referencePower,eps));
tangentialPct = 100*sqrt(mean(imag(localError).^2)/max(referencePower,eps));
phaseError = angle(rx.*conj(ideal));
phaseRMSDeg = sqrt(mean(phaseError.^2))*180/pi;
radiusErrorDB = 20*log10(max(abs(rx),sqrt(eps))./abs(ideal));
radiusRMSDB = sqrt(mean(radiusErrorDB.^2));
end

function noiseVar = localEstimateDemodNoiseVariance(rxSym, refConst)
    % Receiver-observable LLR calibration.  Estimate complex residual
    % variance after the same unit-power normalization used by the soft
    % demapper.  A trimmed residual mean is less optimistic than a pure
    % nearest-point median, but rejects isolated cycle slips.
    noiseVar = 0.01;
    if isempty(rxSym) || isempty(refConst)
        return;
    end
    z = complex(rxSym(:));
    z = z(isfinite(real(z)) & isfinite(imag(z)));
    if isempty(z)
        return;
    end
    z = z ./ sqrt(mean(abs(z).^2) + eps);
    c = complex(refConst(:));
    c = c ./ sqrt(mean(abs(c).^2) + eps);
    [~, nearest] = min(abs(z-c.'), [], 2);
    residualPower = sort(abs(z-c(nearest)).^2);
    if isempty(residualPower)
        return;
    end
    keep = max(1, floor(0.90*numel(residualPower)));
    estimate = mean(residualPower(1:keep));
    if isfinite(estimate) && estimate > 0
        noiseVar = estimate;
    end
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
        elseif strcmpi(tmMod,'MSK')
            % 相邻符号差分会抵消固定载波相位。
            rotations = 1;
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
        if contains(tmMod,'GMSK') && ...
                strcmpi(string(getfieldwithdefault(opt, ...
                'GMSKDetectionMode', 'official-viterbi-frame-reset')), ...
                "official-viterbi-frame-reset")
            % localDemodForASM is a 1-sps legacy pre-selector.  The official
            % branch receives an oversampled waveform, so let the complete
            % decoder score the four phase hypotheses instead.
            phaseResolveMode = "ber";
        end

        rotationOrder = 1:length(rotations);
        asmResolveInfo = struct('enabled', false, 'selectedIdx', rotationOrder, ...
            'fallbackToBER', false, 'message', "");
        asmFramePhaseCorrectionInfo = localEmptyASMFramePhaseCorrectionInfo();
        if phaseResolveMode ~= "ber"
            asmResolveOpt = opt;
            % The generic legacy APSK path remains excluded: its historical
            % pilot/equalizer combinations can make a per-frame ASM decision
            % ambiguous.  The pilotless APSK receiver, however, deliberately
            % leaves the residual 90-degree ambiguity to ASM and therefore
            % needs this sparse phase anchor after a carrier cycle slip.
            receiverModeForASM = lower(strtrim(string( ...
                getfieldwithdefault(opt,'APSKReceiverMode','legacy'))));
            pilotlessAPSKForASM = contains(upper(string(tmMod)),'APSK') && ...
                any(receiverModeForASM == ["pilotless","pilotless-apsk", ...
                "pilotless-x4-nda-dd","pilotless-xm-nda-dd"]);
            qamBPSForASM = contains(upper(string(tmMod)),'QAM') && ...
                getLogicalField(opt,'QAMBlindPhaseSearchActive',false);
            supportsFramePhaseCorrection = ...
                strcmpi(strtrim(tmMod),'QPSK') || pilotlessAPSKForASM || ...
                qamBPSForASM;
            defaultFramePhaseCorrection = ...
                (pilotlessAPSKForASM || qamBPSForASM) && ...
                getLogicalField(opt,'enableHChannel',false);
            requestFramePhaseCorrection = ...
                getLogicalField(opt,'enableASMFramePhaseCorrection', ...
                    defaultFramePhaseCorrection) && ...
                supportsFramePhaseCorrection && ...
                strcmpi(string(getfieldwithdefault(opt,'DataPathMode','single')), ...
                    "single") && hasASM;
            if requestFramePhaseCorrection
                % The correction algorithm needs the complete periodic ASM
                % timeline even when verbose synchronization debug is off.
                asmResolveOpt.enableASMFramePhaseCorrection = true;
            end
            [rotationOrder, asmResolveInfo] = selectRotationsByASM( ...
                fineSynced, rotations, tmMod, tmCode, asmResolveOpt, btVal);
            if asmResolveInfo.enabled
                fprintf('   [ASM phase] %s\n', asmResolveInfo.message);
                if getLogicalField(opt, 'debugCodedBoundary', false) || ...
                        getLogicalField(opt, 'debugASMPhase', false) || ...
                        getLogicalField(opt, 'debugSynchronizationChain', ...
                            getLogicalField(opt, 'debugSyncChain', false))
                    localPrintASMRotationDebug(rotations, asmResolveInfo);
                end
            end
            if requestFramePhaseCorrection && ...
                    isfield(asmResolveInfo,'timeline')
                asmFramePhaseCorrectionInfo.BeforeTimeline = ...
                    asmResolveInfo.timeline;
                [correctedFineSynced,asmFramePhaseCorrectionInfo] = ...
                    localApplyASMFramePhaseCorrection( ...
                        fineSynced,asmResolveInfo.timeline,tmMod,opt, ...
                        asmFramePhaseCorrectionInfo);
                if asmFramePhaseCorrectionInfo.Applied
                    fineSynced = correctedFineSynced;
                    [rotationOrder,asmResolveInfoAfter] = ...
                        localEvaluateASMRotationsAtKnownTimeline( ...
                            fineSynced,rotations,tmMod,tmCode, ...
                            asmResolveOpt,btVal, ...
                            asmResolveInfo.timeline.BitPosition(1));
                    if isfield(asmResolveInfoAfter,'timeline')
                        asmFramePhaseCorrectionInfo.AfterTimeline = ...
                            asmResolveInfoAfter.timeline;
                    end
                    asmResolveInfo = asmResolveInfoAfter;
                    correctionStates = unique( ...
                        asmFramePhaseCorrectionInfo.UsedRotations_deg(:), ...
                        'stable');
                    correctionStates = correctionStates(isfinite(correctionStates));
                    fprintf(['   [ASM frame phase correction] mode=causal-holdover ', ...
                        'applied=%d reliable=%d/%d holdover=%d prefix=%d ', ...
                        'slips=%d states=%s\n'], ...
                        asmFramePhaseCorrectionInfo.Applied, ...
                        asmFramePhaseCorrectionInfo.ReliableFrames, ...
                        asmFramePhaseCorrectionInfo.TotalFrames, ...
                        asmFramePhaseCorrectionInfo.HoldoverFrames, ...
                        asmFramePhaseCorrectionInfo.UncorrectedPrefixFrames, ...
                        asmFramePhaseCorrectionInfo.CycleSlipCountBefore, ...
                        mat2str(correctionStates.'));
                    if getLogicalField(opt,'debugSynchronizationChain', ...
                            getLogicalField(opt,'debugSyncChain',false))
                        fprintf('   [ASM phase after frame correction]\n');
                        localPrintASMRotationDebug(rotations,asmResolveInfo);
                    end
                else
                    fprintf('   [ASM frame phase correction] not applied: %s\n', ...
                        asmFramePhaseCorrectionInfo.Reason);
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
        if isfield(asmResolveInfo, 'timeline')
            berStats.ASMPhaseTimeline = asmResolveInfo.timeline;
        end
        berStats.ASMFramePhaseCorrection = asmFramePhaseCorrectionInfo;
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
    collectTimeline = getLogicalField(opt, 'debugSynchronizationChain', ...
        getLogicalField(opt, 'debugSyncChain', false)) || ...
        getLogicalField(opt, 'enableASMFramePhaseCorrection', false);
    hardBitsByRotation = cell(1, length(rotations));

    for ii = 1:length(rotations)
        try
            demodData = localDemodForASM(fineSynced * rotations(ii), tmMod, tmCode, opt, btVal);
            if isempty(demodData)
                continue;
            end
            hardBits = int8(real(demodData(:)) > 0);
            if collectTimeline
                % Keep the complete demodulated stream only for the cheap
                % periodic timeline checks below.  The expensive sliding
                % acquisition search remains capped by maxSearchBits.
                hardBitsByRotation{ii} = hardBits;
            end
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
    if collectTimeline
        info.timeline = localBuildASMRotationTimeline( ...
            hardBitsByRotation, rotations, asmTemplates, asmPeriodBits, ...
            bestPos(order(1)), opt);
    end

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

function [selectedIdx,info] = localEvaluateASMRotationsAtKnownTimeline( ...
        fineSynced,rotations,tmMod,tmCode,opt,btVal,anchorPos)
    [asmTemplates,periodBits] = ...
        localASMTemplatesForPhaseResolve(tmMod,tmCode,opt);
    hardBitsByRotation = cell(1,numel(rotations));
    for iRotation = 1:numel(rotations)
        demodData = localDemodForASM( ...
            fineSynced*rotations(iRotation),tmMod,tmCode,opt,btVal);
        hardBitsByRotation{iRotation} = ...
            int8(real(demodData(:)) > 0);
    end
    timeline = localBuildASMRotationTimeline( ...
        hardBitsByRotation,rotations,asmTemplates,periodBits,anchorPos,opt);
    info = struct('enabled',timeline.Available, ...
        'selectedIdx',1:numel(rotations),'fallbackToBER',false, ...
        'message',"known-period ASM timeline unavailable", ...
        'timeline',timeline);
    selectedIdx = 1:numel(rotations);
    if ~timeline.Available
        return;
    end

    meanErrors = mean(timeline.ErrorsByRotation,1,'omitnan');
    meanErrors(~isfinite(meanErrors)) = inf;
    [sortedMean,order] = sort(meanErrors,'ascend');
    selectedIdx = order(1:min(2,numel(order)));
    info.selectedIdx = selectedIdx;
    info.scores = -meanErrors;
    info.bestErrs = min(timeline.ErrorsByRotation,[],1);
    info.bestPos = repmat(anchorPos,1,numel(rotations));
    info.meanErrs = meanErrors;
    info.periodicFrames = repmat(timeline.UsableFrames,1,numel(rotations));
    info.message = sprintf([ ...
        'known-period ASM after frame correction: best rot=%+.1f deg ', ...
        'mean=%.2f, second=%.2f, frames=%d'], ...
        rad2deg(angle(rotations(order(1)))),sortedMean(1), ...
        sortedMean(min(2,numel(sortedMean))),timeline.UsableFrames);
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
    if isfield(info, 'timeline') && isstruct(info.timeline) && ...
            getLogicalField(info.timeline, 'Available', false)
        timeline = info.timeline;
        fprintf(['   [ASM phase timeline] frame bitPos bestRot err ', ...
            'runner gap invErr jump\n']);
        nTimelineFrames = numel(timeline.FrameIndex);
        nPrintFrames = min(nTimelineFrames, max(1, round( ...
            getfieldnumeric(timeline, 'DebugPrintFrameLimit', 64))));
        for iFrame = 1:nPrintFrames
            fprintf(['      %4d %7d %+7.1f %4.0f %6.0f %4.0f ', ...
                '%6.0f %d\n'], ...
                timeline.FrameIndex(iFrame), ...
                timeline.BitPosition(iFrame), ...
                timeline.BestRotation_deg(iFrame), ...
                timeline.BestError(iFrame), ...
                timeline.RunnerUpError(iFrame), ...
                timeline.ErrorGap(iFrame), ...
                timeline.BestInvertedError(iFrame), ...
                timeline.CycleSlipDetected(iFrame));
        end
        if nPrintFrames < nTimelineFrames
            fprintf(['      ... (%d/%d frames printed; set ', ...
                'debugASMPhaseTimelineFrames to print more)\n'], ...
                nPrintFrames, nTimelineFrames);
        end
        fprintf(['   [ASM phase timeline summary] usable=%d slips=%d ', ...
            'ambiguous=%d\n'], ...
            timeline.UsableFrames, timeline.CycleSlipCount, ...
            timeline.AmbiguousFrames);
    end
end

function timeline = localBuildASMRotationTimeline( ...
        hardBitsByRotation, rotations, asmTemplates, periodBits, ...
        anchorPos, opt)
    timeline = struct( ...
        'Available',false, ...
        'Rotation_deg',rad2deg(angle(rotations(:))).', ...
        'FrameIndex',zeros(0,1), ...
        'BitPosition',zeros(0,1), ...
        'ErrorsByRotation',zeros(0,numel(rotations)), ...
        'InvertedErrorsByRotation',zeros(0,numel(rotations)), ...
        'BestRotation_deg',zeros(0,1), ...
        'BestError',zeros(0,1), ...
        'RunnerUpError',zeros(0,1), ...
        'ErrorGap',zeros(0,1), ...
        'BestInvertedError',zeros(0,1), ...
        'CycleSlipDetected',false(0,1), ...
        'CycleSlipCount',0, ...
        'AmbiguousFrames',0, ...
        'UsableFrames',0, ...
        'DebugPrintFrameLimit',64, ...
        'TotalFramesAvailable',0, ...
        'FullCoverage',false);

    if isempty(hardBitsByRotation) || isempty(asmTemplates) || ...
            ~isfinite(periodBits) || periodBits <= 0 || ...
            ~isfinite(anchorPos) || anchorPos < 1
        return;
    end

    anchorPos = round(double(anchorPos));
    periodBits = round(double(periodBits));
    while anchorPos-periodBits >= 1
        anchorPos = anchorPos-periodBits;
    end
    maxTimelineFrames = max(1, round(getfieldnumeric( ...
        opt, 'debugASMPhaseTimelineFrames', 64)));
    timeline.DebugPrintFrameLimit = maxTimelineFrames;
    availableLengths = cellfun(@numel, hardBitsByRotation);
    availableLengths = availableLengths(availableLengths > 0);
    if isempty(availableLengths)
        return;
    end
    asmLength = size(asmTemplates,1);
    maxFramesAvailable = floor((min(availableLengths)-anchorPos-asmLength+1) / ...
        periodBits) + 1;
    maxFramesAvailable = max(0,maxFramesAvailable);
    timeline.TotalFramesAvailable = maxFramesAvailable;
    if getLogicalField(opt,'enableASMFramePhaseCorrection',false)
        % This timeline is functional receiver state, not debug output.
        % Frame-phase correction must cover the complete waveform; otherwise
        % a debug print limit silently disables correction on later frames.
        nFrames = maxFramesAvailable;
        timeline.FullCoverage = true;
    else
        % When the timeline is collected only for diagnostics, retain the
        % user-selected print/work limit to avoid unnecessary processing.
        nFrames = min(maxTimelineFrames,maxFramesAvailable);
    end
    if nFrames < 1
        return;
    end

    errors = inf(nFrames,numel(rotations));
    invertedErrors = inf(nFrames,numel(rotations));
    bitPositions = anchorPos + (0:nFrames-1).'*periodBits;
    for iRotation = 1:numel(rotations)
        hardBits = hardBitsByRotation{iRotation};
        if isempty(hardBits)
            continue;
        end
        for iFrame = 1:nFrames
            [errors(iFrame,iRotation), invertedErrors(iFrame,iRotation)] = ...
                localASMTemplateErrorsAt( ...
                    hardBits, asmTemplates, bitPositions(iFrame));
        end
    end

    [sortedErrors, sortedOrder] = sort(errors,2,'ascend');
    bestError = sortedErrors(:,1);
    if size(sortedErrors,2) >= 2
        runnerUp = sortedErrors(:,2);
    else
        runnerUp = inf(size(bestError));
    end
    bestRotationIndex = sortedOrder(:,1);
    rotationDegrees = rad2deg(angle(rotations(:)));
    bestRotation = rotationDegrees(bestRotationIndex);
    bestInverted = min(invertedErrors,[],2);
    errorGap = runnerUp-bestError;
    ambiguousGap = max(0,getfieldnumeric(opt, ...
        'debugASMPhaseTimelineAmbiguousGap',2));
    ambiguous = ~isfinite(bestError) | errorGap <= ambiguousGap;

    cycleSlip = false(nFrames,1);
    for iFrame = 2:nFrames
        delta = mod(bestRotation(iFrame)-bestRotation(iFrame-1)+180,360)-180;
        cycleSlip(iFrame) = ~ambiguous(iFrame) && ...
            ~ambiguous(iFrame-1) && abs(delta) >= 45;
    end

    timeline.Available = true;
    timeline.FrameIndex = (1:nFrames).';
    timeline.BitPosition = bitPositions;
    timeline.ErrorsByRotation = errors;
    timeline.InvertedErrorsByRotation = invertedErrors;
    timeline.BestRotation_deg = bestRotation;
    timeline.BestError = bestError;
    timeline.RunnerUpError = runnerUp;
    timeline.ErrorGap = errorGap;
    timeline.BestInvertedError = bestInverted;
    timeline.CycleSlipDetected = cycleSlip;
    timeline.CycleSlipCount = nnz(cycleSlip);
    timeline.AmbiguousFrames = nnz(ambiguous);
    timeline.UsableFrames = nnz(isfinite(bestError));
end

function info = localEmptyASMFramePhaseCorrectionInfo()
    info = struct( ...
        'Enabled',false, ...
        'Applied',false, ...
        'Reason','disabled', ...
        'TotalFrames',0, ...
        'ReliableFrames',0, ...
        'HoldoverFrames',0, ...
        'UncorrectedPrefixFrames',0, ...
        'CorrectedFrames',0, ...
        'CycleSlipCountBefore',0, ...
        'UsedRotations_deg',zeros(0,1), ...
        'BeforeTimeline',struct('Available',false), ...
        'AfterTimeline',struct('Available',false));
end

function [corrected,info] = localApplyASMFramePhaseCorrection( ...
        symbols,timeline,tmMod,opt,info)
    corrected = symbols;
    info.Enabled = true;
    info.Reason = 'timeline unavailable';
    if ~isstruct(timeline) || ...
            ~getLogicalField(timeline,'Available',false)
        return;
    end
    if ~any(strcmpi(strtrim(char(tmMod)), ...
            {'QPSK','16QAM','32QAM','16APSK','32APSK'}))
        info.Reason = 'modulation does not have the supported 90-degree symmetry';
        return;
    end

    totalFrames = numel(timeline.FrameIndex);
    info.TotalFrames = totalFrames;
    info.CycleSlipCountBefore = timeline.CycleSlipCount;
    if totalFrames < 3
        info.Reason = 'fewer than three periodic ASM observations';
        return;
    end

    maxASMError = max(0,getfieldnumeric(opt, ...
        'asmFramePhaseCorrectionMaxError',6));
    minErrorGap = max(0,getfieldnumeric(opt, ...
        'asmFramePhaseCorrectionMinGap',4));
    minReliableFraction = min(1,max(0,getfieldnumeric(opt, ...
        'asmFramePhaseCorrectionMinReliableFraction',0.80)));
    reliable = isfinite(timeline.BestError) & ...
        timeline.BestError <= maxASMError & ...
        isfinite(timeline.ErrorGap) & timeline.ErrorGap >= minErrorGap;
    info.ReliableFrames = nnz(reliable);
    if info.ReliableFrames < max(3,ceil(minReliableFraction*totalFrames))
        info.Reason = sprintf('only %d/%d ASM frames are reliable', ...
            info.ReliableFrames,totalFrames);
        return;
    end

    rotationDegrees = double(timeline.BestRotation_deg(:));
    % A receiver cannot use a future ASM to correct the current frame.  An
    % unreliable ASM therefore keeps only the latest already-confirmed
    % state.  Frames before the first reliable ASM remain uncorrected.
    lastReliableRotation = NaN;
    for iFrame = 1:totalFrames
        if reliable(iFrame)
            lastReliableRotation = rotationDegrees(iFrame);
        elseif isfinite(lastReliableRotation)
            rotationDegrees(iFrame) = lastReliableRotation;
            info.HoldoverFrames = info.HoldoverFrames + 1;
        else
            rotationDegrees(iFrame) = NaN;
            info.UncorrectedPrefixFrames = ...
                info.UncorrectedPrefixFrames + 1;
        end
    end

    bitsPerSymbol = localBitsPerSymbolForDebug(tmMod);
    symbolStarts = floor((double(timeline.BitPosition(:))-1) / ...
        bitsPerSymbol) + 1;
    symbolStarts = min(max(symbolStarts,1),numel(symbols));
    if any(diff(symbolStarts) <= 0)
        info.Reason = 'ASM bit positions do not map to increasing symbols';
        return;
    end

    corrected = complex(symbols(:));
    for iFrame = 1:totalFrames
        if iFrame == 1
            firstSymbol = 1;
        else
            firstSymbol = symbolStarts(iFrame);
        end
        if iFrame < totalFrames
            lastSymbol = symbolStarts(iFrame+1)-1;
        else
            lastSymbol = numel(corrected);
        end
        if lastSymbol < firstSymbol
            continue;
        end
        if ~isfinite(rotationDegrees(iFrame))
            continue;
        end
        correction = exp(1j*deg2rad(rotationDegrees(iFrame)));
        corrected(firstSymbol:lastSymbol) = ...
            corrected(firstSymbol:lastSymbol)*correction;
    end

    info.Applied = true;
    info.Reason = 'causal periodic coded-ASM phase-state holdover applied';
    info.CorrectedFrames = nnz(isfinite(rotationDegrees));
    info.UsedRotations_deg = rotationDegrees;
end

function [normalError, invertedError] = localASMTemplateErrorsAt( ...
        hardBits, asmTemplates, bitPosition)
    normalError = inf;
    invertedError = inf;
    bitPosition = round(double(bitPosition));
    asmLength = size(asmTemplates,1);
    if bitPosition < 1 || bitPosition+asmLength-1 > numel(hardBits)
        return;
    end
    segment = int8(hardBits(bitPosition:bitPosition+asmLength-1) ~= 0);
    for iTemplate = 1:size(asmTemplates,2)
        template = int8(asmTemplates(:,iTemplate) ~= 0);
        normalError = min(normalError,nnz(segment ~= template));
        invertedError = min(invertedError,nnz(segment ~= ...
            int8(~logical(template))));
    end
end

function holdMask = localExpandQAMBPSHoldMask(blockHold, centers, nSymbols)
% Expand the feed-forward BPS block state onto its one-sample/symbol stream.
% This is a diagnostic trace only.  Nearest-centre expansion mirrors the
% block decision boundaries without introducing an oracle H threshold.
    nSymbols = max(0,round(double(nSymbols)));
    holdMask = false(nSymbols,1);
    blockHold = logical(blockHold(:));
    centers = double(centers(:));
    if nSymbols < 1 || isempty(centers) || ...
            numel(blockHold) ~= numel(centers)
        return;
    end
    valid = isfinite(centers) & centers >= 1 & centers <= nSymbols;
    blockHold = blockHold(valid);
    centers = centers(valid);
    if isempty(centers)
        return;
    end
    [centers,uniqueIndex] = unique(round(centers),'stable');
    blockHold = blockHold(uniqueIndex);
    if numel(centers) == 1
        holdMask(:) = blockHold(1);
        return;
    end
    holdMask = interp1(centers,double(blockHold), ...
        (1:nSymbols).','nearest','extrap') >= 0.5;
end

function stats = localEmptyBERStats()
    stats = struct( ...
        'FER', NaN, ...
        'FrameErrors', 0, ...
        'CountedFrames', 0, ...
        'MatchedFrames', 0, ...
        'NumRxFrames', 0, ...
        'CRCCheckedFrames', 0, ...
        'CRCErrorFrames', 0, ...
        'CRCErrorRate', NaN, ...
        'GMSKDetectorUsed', 'not-applicable', ...
        'AcquisitionFrames', NaN, ...
        'AcquisitionTime_s', NaN, ...
        'QAMBPSFadeBERDiagnosticApplied', false, ...
        'QAMBPSFadeBERRecoveryFrames', NaN, ...
        'QAMBPSFadeBERClassifiedFrames', 0, ...
        'BPSHoldFrames', 0, ...
        'BPSHoldBitErrors', 0, ...
        'BPSHoldBitsCompared', 0, ...
        'BPSRecoveryFrames', 0, ...
        'BPSRecoveryBitErrors', 0, ...
        'BPSRecoveryBitsCompared', 0, ...
        'BPSOutsideFrames', 0, ...
        'BPSOutsideBitErrors', 0, ...
        'BPSOutsideBitsCompared', 0, ...
        'BERInsideBPSHold', NaN, ...
        'BERRecoveryAfterBPSHold', NaN, ...
        'BEROutsideBPSHold', NaN, ...
        'BERInsideFade', NaN, ...
        'BERRecoveryAfterFade', NaN, ...
        'BEROutsideFade', NaN);
    predecoderMetricFields = localPredecoderResultFields();
    for k = 1:numel(predecoderMetricFields)
        stats.(predecoderMetricFields{k}) = NaN;
    end
    railMetricFields = localSplitRailMetricFields();
    for k = 1:numel(railMetricFields)
        stats.(railMetricFields{k}) = NaN;
    end
end

function stats = localUpdateCRCStats(stats, frameBits, opt)
    [crcEnabled, crcValid] = localTMFrameCRCStatus(frameBits, opt);
    if ~crcEnabled
        return;
    end
    stats.CRCCheckedFrames = stats.CRCCheckedFrames + 1;
    if ~crcValid
        stats.CRCErrorFrames = stats.CRCErrorFrames + 1;
    end
    stats.CRCErrorRate = stats.CRCErrorFrames / stats.CRCCheckedFrames;
end

function [crcEnabled, crcValid] = localTMFrameCRCStatus(frameBits, opt)
    crcEnabled = getLogicalField(opt, 'HasFECF', ...
        getLogicalField(opt, 'CRCEnabled', false));
    crcValid = true;
    if ~crcEnabled
        return;
    end
    parseOpt = struct( ...
        'InputIsBits', true, ...
        'HasFECF', true, ...
        'CRCType', char(getfieldwithdefault(opt, 'CRCType', 'CCITT')), ...
        'SecondaryHeaderLength', 0);
    if getLogicalField(opt, 'HasSecondaryHeader', false) && ...
            isfield(opt, 'SecondaryHeader') && ~isempty(opt.SecondaryHeader)
        parseOpt.SecondaryHeaderLength = numel(opt.SecondaryHeader);
    end
    try
        [~, fields] = parse_ccsds_tm_transfer_frame(frameBits, parseOpt);
        crcValid = logical(fields.FECFValid);
    catch
        % A malformed decoded frame is a CRC failure, not a reason to abort
        % an otherwise useful BER diagnostic run.
        crcValid = false;
    end
end

function stats = localCombineCRCStats(stats, varargin)
    checked = 0;
    errors = 0;
    for k = 1:numel(varargin)
        rail = varargin{k};
        checked = checked + getfieldnumeric(rail, 'CRCCheckedFrames', 0);
        errors = errors + getfieldnumeric(rail, 'CRCErrorFrames', 0);
    end
    stats.CRCCheckedFrames = checked;
    stats.CRCErrorFrames = errors;
    if checked > 0
        stats.CRCErrorRate = errors / checked;
    else
        stats.CRCErrorRate = NaN;
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

    measurementWarmUpFrames = 0;
    if getLogicalField(opt, 'excludeBERWarmUpFrames', false)
        measurementWarmUpFrames = numWarmUp;
    end

    [statsI, errsI, bitsI, berI] = localCountOneSplitRailBER( ...
        decodedI, txFramesI, bitsPerFrame, numWarmUp, 2, opt, ...
        measurementWarmUpFrames);
    [statsQ, errsQ, bitsQ, berQ] = localCountOneSplitRailBER( ...
        decodedQ, txFramesQ, bitsPerFrame, numWarmUp, 2, opt, ...
        measurementWarmUpFrames);

    errs = errsI + errsQ;
    bitsComp = bitsI + bitsQ;
    bothRailsMeasured = bitsI > 0 && bitsQ > 0 && ...
        statsI.CountedFrames > 0 && statsQ.CountedFrames > 0;
    if bothRailsMeasured
        berVal = errs / bitsComp;
    else
        % A dual-I/Q result is not valid when only one rail acquires.  The
        % historical aggregate silently divided by the surviving rail and
        % could therefore report BER=0/PASS while the other rail had no
        % decoded frames at all.
        berVal = 0.5;
    end

    stats = localEmptyBERStats();
    stats.NumRxFrames = statsI.NumRxFrames + statsQ.NumRxFrames;
    stats.MatchedFrames = statsI.MatchedFrames + statsQ.MatchedFrames;
    stats.CountedFrames = statsI.CountedFrames + statsQ.CountedFrames;
    stats.FrameErrors = statsI.FrameErrors + statsQ.FrameErrors;
    stats = localCombineCRCStats(stats, statsI, statsQ);
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

    if ~bothRailsMeasured
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
    bothRailsMeasured = bitsI > 0 && bitsQ > 0 && ...
        statsI.CountedFrames > 0 && statsQ.CountedFrames > 0;
    if bothRailsMeasured
        berVal = errs / bitsComp;
    else
        berVal = 0.5;
    end

    stats = localEmptyBERStats();
    stats.NumRxFrames = statsI.NumRxFrames + statsQ.NumRxFrames;
    stats.MatchedFrames = statsI.MatchedFrames + statsQ.MatchedFrames;
    stats.CountedFrames = statsI.CountedFrames + statsQ.CountedFrames;
    stats.FrameErrors = statsI.FrameErrors + statsQ.FrameErrors;
    stats = localCombineCRCStats(stats, statsI, statsQ);
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

    if ~bothRailsMeasured
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

    txCatalog = localBuildTMFrameCatalog(txFrames);
    firstMeasurementFrame = min( ...
        numel(txFrames) + 1, measurementWarmUpFrames + 1);

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
    lastMatchedTxIndex = NaN;

    for j = 1:numRx
        idx = (j-1)*bitsPerFrame + (1:bitsPerFrame);
        rxFr = double(decodedBits(idx));
        rxId = localTMFrameID(rxFr);

        [frameMatched, txFrame, txFrameIndex] = ...
            localMatchTMFrameOccurrence( ...
                rxFr, txFrames, txCatalog, lastMatchedTxIndex);
        if ~frameMatched
            hasLastId = false;
            consecIdCount = 0;
            continue;
        end

        stats.MatchedFrames = stats.MatchedFrames + 1;
        thisErrs = biterr(txFrame, rxFr);
        perFrameBER(j) = thisErrs / bitsPerFrame;

        % acquisition 阶段只接受“帧号连续 + 本帧 BER 不像随机”的匹配帧。
        % 这样既保留连续帧号防假锁，又不会把 numWarmUp 直接当成连续门限。
        [crcEnabledForAcq, crcValidForAcq] = ...
            localTMFrameCRCStatus(rxFr, opt);
        goodFrameForAcq = perFrameBER(j) <= acquisitionMaxFrameBER && ...
            (~crcEnabledForAcq || crcValidForAcq);
        if goodFrameForAcq
            lastMatchedTxIndex = txFrameIndex;
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
        counted = acquiredForBER && txFrameIndex >= firstMeasurementFrame;
        if counted
            stats.CountedFrames = stats.CountedFrames + 1;
            stats = localUpdateCRCStats(stats, rxFr, opt);
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
            'RolloffFactor', rolloffLocal, ...
            'FilterSpanInSymbols', getfieldnumeric(opt, ...
                'FilterSpanInSymbols', 10), ...
            'NoiseVariance', localOQPSKNoiseVariance(opt));
        demodData = demodobj(fineSynced);
    elseif strcmpi(tmMod,'MSK')
        demodData = localMSKSoftDemod( ...
            fineSynced, tmCode, opt);
    elseif contains(tmMod,'GMSK')
        demodobj = HelperCCSDSTMDemodulator( ...
            'Modulation', tmMod, ...
            'ChannelCoding', tmCode, ...
            'BandwidthTimeProduct', btVal);
        demodData = real(demodobj(fineSynced));
    else
        demodArgs = {'Modulation', tmMod, 'ChannelCoding', tmCode};
        if any(strcmpi(string(tmMod),["BPSK","QPSK","8PSK"]))
            demodArgs = [demodArgs, {'PCMFormat', pcmFormatRx}];
        end
        if contains(tmMod,'4D-8PSK-TCM')
            demodArgs = [demodArgs, {'ModulationEfficiency', getf(opt,'ModulationEfficiency',2)}];
        end
        demodobj = HelperCCSDSTMDemodulator(demodArgs{:});
        demodData = demodobj(fineSynced);
    end
end
function demodData = localMSKSoftDemod(symbols, tmCode, opt)

    if nargin < 3
        opt = struct();
    end
    spsMSK = max(1, round(getfieldnumeric(opt, ...
        'mskSoftSamplesPerSymbol', 1)));
    if spsMSK > 1
        demodData = localMSKOversampledSoftDemod(symbols, spsMSK);
        return;
    end

    demodObj = HelperCCSDSTMDemodulator( ...
        'Modulation','MSK', ...
        'ChannelCoding',tmCode);

    % Helper 的 MSK 约定：正=bit0、负=bit1。
    % 通用 TM Decoder 约定：正=bit1、负=bit0。
    demodData = -real(demodObj(symbols(:)));

    % bit contract 已证明：
    % 第一个输出没有真实的前一符号，第二个输出对应第一个 TX bit。
    % 因此固定删除首个无定义 metric。
    if ~isempty(demodData)
        demodData = demodData(2:end);
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

    if any(strcmp(codeKey, ["convolutional", "concatenated"]))
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

    if codeKey == "concatenated"
        rsK = getfieldnumeric(opt, 'RSMessageLength', 223);
        rsI = getfieldnumeric(opt, 'RSInterleavingDepth', 1);
        rsS = getfieldnumeric(opt, 'RSShortenedMessageLength', rsK);
        if ~getLogicalField(opt, 'IsRSMessageShortened', false)
            rsS = rsK;
        end
        rsCodewordBytes = rsI * (255 - rsK + rsS);
        convRate = localRateStringToDouble( ...
            getfieldwithdefault(opt, 'ConvolutionalCodeRate', '1/2'), 1/2);
        periodBits = round((rsCodewordBytes*8 + asmLen) / max(convRate, eps));
    elseif contains(codeKey, 'convolutional')
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
                "gmsk_ccsds_official_demodulate:") || ...
                strcmp(string(candidateError.identifier), ...
                "run_ccsds_tm_evaluation:GMSKProductionDetectorRemoved")
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
    predecoderStats = localEmptyPredecoderStats();
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

    % The frame-reset official Viterbi receiver is the sole production
    % GMSK path. Legacy detector helpers are not selectable here.
    gmskFrameResetAligned = false;

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
            'RolloffFactor', rolloffLocal, ...
            'FilterSpanInSymbols', getfieldnumeric(opt, ...
                'FilterSpanInSymbols', 10), ...
            'NoiseVariance', localOQPSKNoiseVariance(opt));

        demodData = demodobj(fineSynced);
    elseif strcmpi(tmMod,'MSK')
        debugMSK = getLogicalField(opt,'debugMSK',false) || ...
            getLogicalField(opt,'debugCodedBoundary',false);

        demodData = localMSKSoftDemod( ...
            fineSynced, tmCode, opt);

        if debugMSK && ~isempty(demodData)
            hardBits = demodData < 0;

            fprintf(['   [MSK DEBUG] softLen=%d, ', ...
                'mean=%+.3f, std=%.3f, ', ...
                'range=[%+.3f,%+.3f], ones=%.1f%%\n'], ...
                numel(demodData), ...
                mean(demodData), ...
                std(demodData), ...
                min(demodData), ...
                max(demodData), ...
                100*mean(hardBits));
        end

    elseif contains(tmMod,'GMSK')
        debugGMSK = getLogicalField(opt, 'debugGMSK', false) || ...
            getLogicalField(opt, 'debugCodedBoundary', false);
        gmskDetectionMode = "official-viterbi-frame-reset";
        if isfield(opt,'GMSKDetectionMode') && ~isempty(opt.GMSKDetectionMode)
            gmskDetectionMode = lower(string(opt.GMSKDetectionMode));
        end
        useOfficialFrameReset = strcmp(gmskDetectionMode, ...
            "official-viterbi-frame-reset");
        if ~useOfficialFrameReset
            error('run_ccsds_tm_evaluation:GMSKProductionDetectorRemoved', ...
                ['The production GMSK path only supports ', ...
                 'GMSKDetectionMode="official-viterbi-frame-reset".']);
        end

        if useOfficialFrameReset
            officialReceiverCfg = struct();
        officialReceiverCfg.ChannelCoding = tmCode;
        officialCodeKey = lower(string(tmCode));
        if any(strcmp(officialCodeKey, ["convolutional", "concatenated"]))
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
        elseif officialCodeKey == "rs"
            officialReceiverCfg.CodeRate = 'N/A';
            officialReceiverCfg.RSMessageLength = ...
                getfieldnumeric(opt, 'RSMessageLength', 223);
            officialReceiverCfg.RSInterleavingDepth = ...
                getfieldnumeric(opt, 'RSInterleavingDepth', 1);
            officialReceiverCfg.IsRSMessageShortened = ...
                getLogicalField(opt, 'IsRSMessageShortened', false);
            officialReceiverCfg.RSShortenedMessageLength = ...
                getfieldnumeric(opt, 'RSShortenedMessageLength', ...
                officialReceiverCfg.RSMessageLength);
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
        % Canonical GMSK soft convention at the detector/FEC boundary:
        % positive means encoded bit 0, negative means encoded bit 1.
        % Every FEC adapter below converts from this one convention;
        % detector choice is never allowed to change polarity.
        demodData = localCanonicalGMSKSoftMetric(demodData);
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
        end
        if debugGMSK
            hard0 = demodData(:) < 0;
            fprintf('   [GMSK DEBUG] demodData len=%d, mean=%+.3f, std=%.3f, min=%+.3f, max=%+.3f, ones=%.1f%%\n', ...
                numel(demodData), mean(demodData(:)), std(demodData(:)), ...
                min(demodData(:)), max(demodData(:)), 100*mean(hard0));
        end
        demodData = real(demodData);
    else
        demodArgs = {'Modulation',tmMod,'ChannelCoding',tmCode};
        if any(strcmpi(string(tmMod),["BPSK","QPSK","8PSK"]))
            demodArgs = [demodArgs, {'PCMFormat',pcmFormatRx}];
        end
        if (contains(tmMod,'QAM') || contains(tmMod,'APSK')) && ...
                isfield(opt,'DemodNoiseVariance') && ...
                ~isempty(opt.DemodNoiseVariance)
            demodArgs = [demodArgs, ...
                {'NoiseVariance', max(eps,double(opt.DemodNoiseVariance))}];
        end
        if contains(tmMod,'4D-8PSK-TCM')
            demodArgs = [demodArgs, {'ModulationEfficiency', getf(opt,'ModulationEfficiency',2)}];
        end
        demodobj = HelperCCSDSTMDemodulator(demodArgs{:});
        demodData = demodobj(fineSynced);
    end
    qamBPSRawDemodBits = numel(demodData);
    qamBPSFadeBERPartition = localEmptyQAMBPSFadeBERPartition();

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
        if ~getLogicalField(opt, 'debugCodedBoundary', false) && ...
                evalin('base','exist(''debugTPC_encodedBits'',''var'')')
            txEnc = evalin('base','debugTPC_encodedBits');
            localMeasureEncodedBoundaryStats(demodData, txEnc, tmMod, true, ...
                getfieldnumeric(opt, 'predecoderMaxOffsetBits', 256));
        end
    end

    debugCodedBoundary = getLogicalField(opt, 'debugCodedBoundary', false);
    collectPredecoderStats = getLogicalField(opt, 'collectPredecoderStats', false);
    measurePredecoderStats = debugCodedBoundary || ...
        (collectPredecoderStats && ~strcmpi(string(tmCode), "none"));
    if measurePredecoderStats && ...
            evalin('base','exist(''debugTMEncodedBits'',''var'')')
        txEnc = evalin('base','debugTMEncodedBits');
        demodForPredecoderStats = demodData;
        predecoderASMAligned = false;
        predecoderASMTrim = 0;
        if hasASM && strcmpi(string(dataPathMode), "single")
            % The matched-filter/timing path can discard the beginning of
            % the first transmitted frame.  Comparing that stream directly
            % with txEncodedBits(1) therefore reports about 0.5 BER even
            % when the later decoder produces error-free frames.  Align a
            % diagnostic copy to a periodic ASM first; do not alter the
            % actual decoder input here.
            [demodForPredecoderStats,predecoderASMTrim, ...
                predecoderASMAligned] = localTrimDemodToPeriodicASM( ...
                demodData,tmMod,tmCode,opt);
        end
        predecoderContext = struct( ...
            'NumTxFrames', numel(validTxFrames), ...
            'WarmUpFrames', max(0, round(double(numWarmUp))), ...
            'ASMAligned', predecoderASMAligned, ...
            'ASMTrimBits', predecoderASMTrim, ...
            'MaxBurstFrames', max(1, round(getfieldnumeric(opt, ...
                'debugPredecoderMaxBurstFrames', 12))));
        if ~strcmpi(string(dataPathMode), "single")
            % A packed split stream does not have one contiguous encoded
            % frame per validTxFrames entry.  Keep the global metric but do
            % not invent single-stream frame boundaries for it.
            predecoderContext.NumTxFrames = 0;
        end
        predecoderStats = localMeasureEncodedBoundaryStats( ...
            demodForPredecoderStats, txEnc, tmMod, ...
            debugCodedBoundary, ...
            getfieldnumeric(opt, 'predecoderMaxOffsetBits', 256), ...
            predecoderContext);
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
    frameSyncNames = { ...
        'FrameSyncBitSlipTolerance', ...
        'FrameSyncASMErrorThreshold', ...
        'FrameSyncLockThreshold', ...
        'FrameSyncUnlockThreshold'};
    for iFrameSyncName = 1:numel(frameSyncNames)
        frameSyncName = frameSyncNames{iFrameSyncName};
        if isfield(opt, frameSyncName) && ~isempty(opt.(frameSyncName))
            decArgs = [decArgs, {frameSyncName, double(opt.(frameSyncName))}]; %#ok<AGROW>
        end
    end
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
    if any(strcmp(lower(string(tmCode)), ["convolutional", "concatenated"]))
        if isfield(opt,'ConvolutionalCodeRate')
            rate = char(opt.ConvolutionalCodeRate);
            if ~strcmp(rate,'N/A'), decArgs=[decArgs,{'ConvolutionalCodeRate',rate}]; end
        else
            decArgs=[decArgs,{'ConvolutionalCodeRate','1/2'}];
        end
        convMode = char(getfieldwithdefault(opt, ...
            'ConvolutionalG1G2Mode', 'auto-ccsds'));
        decArgs = [decArgs, {'ConvolutionalG1G2Mode', convMode}];
        if getLogicalField(opt, 'debugConvolutionalG1G2', false)
            fprintf('[TM convolutional config] RX mode=%s rate=%s path=%s\n', ...
                convMode, char(getfieldwithdefault(opt, ...
                'ConvolutionalCodeRate', '1/2')), dataPathMode);
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
        if isfield(opt,'LDPCMaxIterations') && ~isempty(opt.LDPCMaxIterations)
            decArgs = [decArgs, {'LDPCMaxIterations', ...
                double(opt.LDPCMaxIterations)}];
        end
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
    txCatalog = localBuildTMFrameCatalog(validTxFrames);
    excludeBERWarmUpFrames = getLogicalField(opt, ...
        'excludeBERWarmUpFrames', false);
    firstMeasurementFrame = 1;
    if excludeBERWarmUpFrames
        firstMeasurementFrame = min(numel(validTxFrames) + 1, numWarmUp + 1);
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

            % Debug only: each carrier/IQ hypothesis may instantiate two
            % independent rail decoders.  Without resetting the shared print
            % counter, early wrong carrier rotations can consume the entire
            % frame-sync log budget and hide the later correct hypothesis.
            % This switch changes diagnostics only; it never changes decoder
            % state, thresholds, candidate scoring, or selected data.
            if splitDebug && getLogicalField(opt, ...
                    'debugResetCodedFrameSyncPerSplitCandidate', false)
                assignin('base', 'debugCodedFrameSyncPrintCount', 0);
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
        asmTrim = 0;
        asmFound = false;
        modKeyForAlign = upper(string(tmMod));
        codeKeyForAlign = lower(string(tmCode));
        isConvForAlign = any(strcmp(codeKeyForAlign, ...
            ["convolutional", "concatenated"]));
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
        qamBPSFadeBERPartition = localBuildQAMBPSFadeBERPartition( ...
            opt,tmMod,tmCode,qamBPSRawDemodBits,asmTrim, ...
            asmFound);

        codedSearchRate = "";
        if isfield(opt,'ConvolutionalCodeRate') && ~isempty(opt.ConvolutionalCodeRate)
            codedSearchRate = string(opt.ConvolutionalCodeRate);
        end
        isGMSKCodedSearch = contains(upper(string(tmMod)), 'GMSK');
        codedPhaseSearch = any(strcmp(lower(string(tmCode)), ...
            ["convolutional", "concatenated"])) && ...
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

    if strcmpi(string(tmCode), "TPC") && length(decodedBits) >= bitsPerFrame
        validFrameIds = cell2mat(keys(txMap));
        minConsecutive = max(2, round(getfieldnumeric(opt, ...
            'tpcDecodedAlignMinConsecutiveFrames', 3)));
        minCandidateConsecutive = max(minConsecutive, round( ...
            getfieldnumeric(opt, ...
            'tpcDecodedAlignMinCandidateConsecutiveFrames', 8)));
        alignDebug = getLogicalField(opt, 'debugTPC', false) || ...
            getLogicalField(opt, 'debugCodedBoundary', false);
        [decodedBits, tpcAlignInfo] = HelperTMTPCDecodedFrameAligner( ...
            decodedBits, bitsPerFrame, validFrameIds, ...
            'MinConsecutiveFrames', minConsecutive, ...
            'MinCandidateConsecutiveFrames', minCandidateConsecutive, ...
            'Debug', alignDebug);
        if alignDebug && ~tpcAlignInfo.Applied && ...
                tpcAlignInfo.BaselineMaxRun < minConsecutive
            fprintf(['   [TPC ALIGN] no verified replacement; keeping decoder ', ...
                'boundary rather than applying an unconfirmed bit shift.\n']);
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
    lastMatchedTxIndex = NaN;

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
        [frameMatched, txFrame, txFrameIndex] = ...
            localMatchTMFrameOccurrence( ...
                rxFr, validTxFrames, txCatalog, lastMatchedTxIndex);
        if frameMatched
            framesMatched = framesMatched + 1;          % 所有匹配帧计入 lockRate
            thisErrs = biterr(txFrame, rxFr);
            perFrameBER(j) = thisErrs / bitsPerFrame;
%             if rxId >= numWarmUp                          % 只用稳态帧算 BER
%                 errs = errs + thisErrs;
%                 bitsComp = bitsComp + bitsPerFrame;
%             end
            % acquisition 阶段只接受“帧号连续 + 本帧 BER 不像随机”的匹配帧。
            % 这样可以防止乱比特偶然撞上某个 frame ID 造成假同步。
            [crcEnabledForAcq, crcValidForAcq] = ...
                localTMFrameCRCStatus(rxFr, opt);
            goodFrameForAcq = perFrameBER(j) <= acquisitionMaxFrameBER && ...
                (~crcEnabledForAcq || crcValidForAcq);
            if goodFrameForAcq
                lastMatchedTxIndex = txFrameIndex;
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
            counted = acquiredForBER && txFrameIndex >= firstMeasurementFrame;

%             fprintf('\n   [FrameCheck] j=%d, rxId=%d, perBER=%.3f, counted=%d', ...
%                 j, rxId, perFrameBER(j), counted);

            if counted
                countedFrames = countedFrames + 1;
                frameStats = localUpdateCRCStats(frameStats, rxFr, opt);
                if thisErrs > 0
                    frameErrors = frameErrors + 1;
                end
                errs = errs + thisErrs;
                bitsComp = bitsComp + bitsPerFrame;
                frameStats = localAccumulateQAMBPSFadeBER( ...
                    frameStats,qamBPSFadeBERPartition,j, ...
                    thisErrs,bitsPerFrame);
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
    frameStats = localFinalizeQAMBPSFadeBER(frameStats);
    frameStats = localAttachPredecoderStats(frameStats, predecoderStats);
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
    if any(strcmp(lower(string(tmCode)), ["convolutional", "concatenated"]))
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

function stats = localMeasureEncodedBoundaryStats( ...
        demodData, txEncodedBits, tmMod, printDebug, maxOffsetBits, context)
    if nargin < 4
        printDebug = true;
    end
    if nargin < 5 || ~isfinite(maxOffsetBits)
        maxOffsetBits = 256;
    end
    if nargin < 6 || ~isstruct(context)
        context = struct();
    end
    stats = localEmptyPredecoderStats();
    if contains(upper(string(tmMod)), 'GMSK')
        % The canonical GMSK detector boundary is positive=bit0 and
        % negative=bit1. Report that fixed contract directly; do not make a
        % diagnostic oracle hide an inverted FEC adapter.
        rxHard0 = int8(demodData(:) < 0);
    else
        rxHard0 = int8(demodData(:) > 0);
    end
    txBits = int8(txEncodedBits(:) ~= 0);
    if isempty(rxHard0) || isempty(txBits)
        return;
    end

    maxOffset = max(0,round(double(maxOffsetBits)));
    numTxFrames = max(0,round(getfieldnumeric(context,'NumTxFrames',0)));
    frameLength = 0;
    if numTxFrames > 0 && mod(numel(txBits),numTxFrames) == 0
        frameLength = numel(txBits)/numTxFrames;
    end

    % Search both directions.  Positive offset drops RX bits; negative
    % offset drops TX bits.  When an ASM has established a frame boundary,
    % also search which transmitted frame is the first surviving frame.
    % A short probe chooses the hypothesis, then BER is evaluated over the
    % full common interval.  This keeps a 300-frame debug run inexpensive.
    if frameLength > 0 && getLogicalField(context,'ASMAligned',false)
        maxFrameShift = min(numTxFrames-1,max(64, ...
            round(getfieldnumeric(context,'WarmUpFrames',0))+16));
        frameShifts = 0:maxFrameShift;
        % localTrimDemodToPeriodicASM has already established an exact bit
        % boundary, so only the surviving TX frame index remains unknown.
        signedOffsets = 0;
    else
        frameShifts = 0;
        signedOffsets = -maxOffset:maxOffset;
    end
    probeLength = min(16384,min(numel(rxHard0),numel(txBits)));
    best = struct('err',inf,'probeErr',inf,'offset',0, ...
        'rxStart',1,'txStart',1,'txFrameOffset',0, ...
        'polarity',1,'len',0);
    for frameShift = frameShifts
        txFrameStart = 1 + frameShift*frameLength;
        for offset = signedOffsets
            rxStart = 1 + max(offset,0);
            txStart = txFrameStart + max(-offset,0);
            Lprobe = min([probeLength, ...
                numel(rxHard0)-rxStart+1,numel(txBits)-txStart+1]);
            if Lprobe <= 0
                continue;
            end
            errNormal = nnz(rxHard0(rxStart:rxStart+Lprobe-1) ~= ...
                txBits(txStart:txStart+Lprobe-1));
            probeErr = min(errNormal,Lprobe-errNormal);
            if probeErr < best.probeErr
                best.probeErr = probeErr;
                best.offset = offset;
                best.rxStart = rxStart;
                best.txStart = txStart;
                best.txFrameOffset = frameShift;
            end
        end
    end

    L = min(numel(rxHard0)-best.rxStart+1, ...
        numel(txBits)-best.txStart+1);
    if L > 0
        errNormal = nnz(rxHard0(best.rxStart:best.rxStart+L-1) ~= ...
            txBits(best.txStart:best.txStart+L-1));
        if errNormal <= L-errNormal
            best.err = errNormal;
            best.polarity = 1;
        else
            best.err = L-errNormal;
            best.polarity = -1;
        end
        best.len = L;
    end

    if best.len > 0
        assignin('base', 'debugTPC_demodBestOffset', best.offset);
        assignin('base', 'debugTPC_demodBestPolarity', best.polarity);
        stats.PredecoderBER = best.err / best.len;
        stats.PredecoderOffset = best.offset;
        stats.PredecoderTxFrameOffset = best.txFrameOffset;
        stats.PredecoderASMAligned = getLogicalField(context, ...
            'ASMAligned',false);
        stats.PredecoderPolarity = best.polarity;
        stats.PredecoderBitErrors = best.err;
        stats.PredecoderBitsCompared = best.len;
        stats = localAttachPredecoderFrameStats( ...
            stats, rxHard0, txBits, best, context);
        if printDebug
            fprintf(['   [Coded DEBUG] demod-vs-encoded (%s): ', ...
                'ASMAligned=%d, rx/txOffset=%+d bits, txFrameOffset=%d, ', ...
                'polarity=%+d, hardBER=%.6g (%d/%d)\n'], ...
                char(tmMod),stats.PredecoderASMAligned,best.offset, ...
                best.txFrameOffset,best.polarity, ...
                stats.PredecoderBER, best.err, best.len);
            if isfinite(stats.PredecoderSteadyBER)
                fprintf(['   [Coded DEBUG] steady hardBER=%.6g ', ...
                    '(%d/%d), frames=%d, frameBER p95/max=%.6g/%.6g\n'], ...
                    stats.PredecoderSteadyBER, ...
                    stats.PredecoderSteadyBitErrors, ...
                    stats.PredecoderSteadyBitsCompared, ...
                    stats.PredecoderFramesCompared, ...
                    stats.PredecoderFrameBERP95, ...
                    stats.PredecoderFrameBERMax);
            end
            localTPCPrintBitPlaneDebug(demodData, txBits, tmMod, best);
            localPrintPredecoderBurstDebug( ...
                demodData, txBits, tmMod, best, context);
        end
    end
end

function names = localQAMBPSFadeBERResultFields()
    names = { ...
        'QAMBPSFadeBERDiagnosticApplied', ...
        'QAMBPSFadeBERRecoveryFrames', ...
        'QAMBPSFadeBERClassifiedFrames', ...
        'BPSHoldFrames','BPSHoldBitErrors','BPSHoldBitsCompared', ...
        'BPSRecoveryFrames','BPSRecoveryBitErrors', ...
        'BPSRecoveryBitsCompared', ...
        'BPSOutsideFrames','BPSOutsideBitErrors','BPSOutsideBitsCompared', ...
        'BERInsideBPSHold','BERRecoveryAfterBPSHold', ...
        'BEROutsideBPSHold', ...
        'BERInsideFade','BERRecoveryAfterFade','BEROutsideFade'};
end

function partition = localEmptyQAMBPSFadeBERPartition()
    partition = struct( ...
        'Applied',false, ...
        'Reason','not-applicable', ...
        'Hold',false(0,1), ...
        'Recovery',false(0,1), ...
        'Outside',false(0,1), ...
        'HoldFraction',zeros(0,1), ...
        'RecoveryFrames',NaN);
end

function partition = localBuildQAMBPSFadeBERPartition( ...
        opt,tmMod,tmCode,rawDemodBits,trimBits,alignmentEstablished)
% Build receiver-observable fade classes from the BPS HOLD state.
% Scope is deliberately narrow: single-stream, uncoded QAM with a verified
% periodic ASM boundary.  Encoded paths have decoder latency/interleaving and
% need a separate mask transport contract; returning not-applicable is safer
% than publishing a one-frame-shifted BER.
    partition = localEmptyQAMBPSFadeBERPartition();
    if ~contains(upper(string(tmMod)),'QAM') || ...
            ~strcmpi(string(tmCode),'none') || ...
            ~strcmpi(string(getfieldwithdefault(opt,'DataPathMode','single')), ...
                'single')
        partition.Reason = 'requires single-stream uncoded QAM';
        return;
    end
    if ~alignmentEstablished
        partition.Reason = 'periodic ASM boundary not established';
        return;
    end
    if ~isfield(opt,'QAMBPSHoldMaskSymbols') || ...
            isempty(opt.QAMBPSHoldMaskSymbols)
        partition.Reason = 'BPS HOLD mask unavailable';
        return;
    end
    bitsPerSymbol = localBitsPerSymbolForDebug(tmMod);
    if ~isfinite(bitsPerSymbol) || bitsPerSymbol < 1
        partition.Reason = 'invalid QAM bits per symbol';
        return;
    end
    bitsPerSymbol = round(bitsPerSymbol);
    bitHold = repelem(logical(opt.QAMBPSHoldMaskSymbols(:)), ...
        bitsPerSymbol);
    rawDemodBits = max(0,round(double(rawDemodBits)));
    if numel(bitHold) ~= rawDemodBits
        partition.Reason = sprintf( ...
            'BPS mask/demod length mismatch (%d/%d bits)', ...
            numel(bitHold),rawDemodBits);
        return;
    end
    trimBits = max(0,round(double(trimBits)));
    if trimBits >= numel(bitHold)
        partition.Reason = 'ASM trim removed complete BPS mask';
        return;
    end
    bitHold = bitHold(trimBits+1:end);
    periodBits = localASMPeriodBits(tmMod,tmCode,opt);
    if ~isfinite(periodBits) || periodBits < 1
        partition.Reason = 'invalid TM frame period';
        return;
    end
    periodBits = round(periodBits);
    nFrames = floor(numel(bitHold)/periodBits);
    if nFrames < 1
        partition.Reason = 'BPS mask shorter than one aligned TM frame';
        return;
    end
    frameMask = reshape(bitHold(1:nFrames*periodBits),periodBits,nFrames);
    holdFraction = mean(frameMask,1).';
    minHoldFraction = min(1,max(0,getfieldnumeric(opt, ...
        'QAMBPSFadeBERHoldFrameMinFraction',0)));
    holdFrames = holdFraction > minHoldFraction;
    recoveryFrameCount = max(0,round(getfieldnumeric(opt, ...
        'QAMBPSFadeBERRecoveryFrames',1)));
    recoveryFrames = false(nFrames,1);
    recoveryRemaining = 0;
    for iFrame = 1:nFrames
        if holdFrames(iFrame)
            recoveryRemaining = recoveryFrameCount;
        elseif recoveryRemaining > 0
            recoveryFrames(iFrame) = true;
            recoveryRemaining = recoveryRemaining-1;
        end
    end
    partition.Applied = true;
    partition.Reason = 'receiver-observable QAM BPS HOLD';
    partition.Hold = holdFrames;
    partition.Recovery = recoveryFrames;
    partition.Outside = ~holdFrames & ~recoveryFrames;
    partition.HoldFraction = holdFraction;
    partition.RecoveryFrames = recoveryFrameCount;
end

function stats = localAccumulateQAMBPSFadeBER( ...
        stats,partition,rxFrameIndex,bitErrors,bitsCompared)
    if ~partition.Applied || rxFrameIndex < 1 || ...
            rxFrameIndex > numel(partition.Hold)
        return;
    end
    stats.QAMBPSFadeBERDiagnosticApplied = true;
    stats.QAMBPSFadeBERRecoveryFrames = partition.RecoveryFrames;
    stats.QAMBPSFadeBERClassifiedFrames = ...
        stats.QAMBPSFadeBERClassifiedFrames+1;
    if partition.Hold(rxFrameIndex)
        stats.BPSHoldFrames = stats.BPSHoldFrames+1;
        stats.BPSHoldBitErrors = stats.BPSHoldBitErrors+bitErrors;
        stats.BPSHoldBitsCompared = stats.BPSHoldBitsCompared+bitsCompared;
    elseif partition.Recovery(rxFrameIndex)
        stats.BPSRecoveryFrames = stats.BPSRecoveryFrames+1;
        stats.BPSRecoveryBitErrors = ...
            stats.BPSRecoveryBitErrors+bitErrors;
        stats.BPSRecoveryBitsCompared = ...
            stats.BPSRecoveryBitsCompared+bitsCompared;
    else
        stats.BPSOutsideFrames = stats.BPSOutsideFrames+1;
        stats.BPSOutsideBitErrors = stats.BPSOutsideBitErrors+bitErrors;
        stats.BPSOutsideBitsCompared = ...
            stats.BPSOutsideBitsCompared+bitsCompared;
    end
end

function stats = localFinalizeQAMBPSFadeBER(stats)
    if ~stats.QAMBPSFadeBERDiagnosticApplied
        return;
    end
    if stats.BPSHoldBitsCompared > 0
        stats.BERInsideBPSHold = ...
            stats.BPSHoldBitErrors/stats.BPSHoldBitsCompared;
    end
    if stats.BPSRecoveryBitsCompared > 0
        stats.BERRecoveryAfterBPSHold = ...
            stats.BPSRecoveryBitErrors/stats.BPSRecoveryBitsCompared;
    end
    if stats.BPSOutsideBitsCompared > 0
        stats.BEROutsideBPSHold = ...
            stats.BPSOutsideBitErrors/stats.BPSOutsideBitsCompared;
    end
    % Requested concise aliases.  Their reference is explicitly BPS HOLD,
    % not the true H coefficient or an oracle SNR threshold.
    stats.BERInsideFade = stats.BERInsideBPSHold;
    stats.BERRecoveryAfterFade = stats.BERRecoveryAfterBPSHold;
    stats.BEROutsideFade = stats.BEROutsideBPSHold;
end

function localPrintQAMBPSFadeBER(stats)
    if ~getLogicalField(stats,'QAMBPSFadeBERDiagnosticApplied',false)
        fprintf(['   [QAM BPS fade BER] not available; requires ', ...
            'single-stream uncoded QAM with periodic ASM alignment.\n']);
        return;
    end
    fprintf(['   [QAM BPS fade BER] HOLD=%.6g (%d/%d bits, %d frames) ', ...
        '| recovery[%d]=%.6g (%d/%d, %d frames) ', ...
        '| outside=%.6g (%d/%d, %d frames)\n'], ...
        stats.BERInsideBPSHold,stats.BPSHoldBitErrors, ...
        stats.BPSHoldBitsCompared,stats.BPSHoldFrames, ...
        stats.QAMBPSFadeBERRecoveryFrames, ...
        stats.BERRecoveryAfterBPSHold,stats.BPSRecoveryBitErrors, ...
        stats.BPSRecoveryBitsCompared,stats.BPSRecoveryFrames, ...
        stats.BEROutsideBPSHold,stats.BPSOutsideBitErrors, ...
        stats.BPSOutsideBitsCompared,stats.BPSOutsideFrames);
end

function [y, info] = localFourthPowerHighRatePhaseTrack(x, sps, windowSymbols)
%LOCALFOURTHPOWERHIGHRATEPHASETRACK Decision-free QPSK phase pre-tracker.
% Operates before matched-filter decimation.  Normalizing each sample keeps
% H-channel envelope motion out of the fourth-power phase observation.  The
% tracker removes only phase motion relative to acquisition, leaving the
% constant pi/2 ambiguity to the existing carrier/ASM rotation search.
    x = complex(x(:));
    sps = max(1, round(double(sps)));
    windowSymbols = max(2, double(windowSymbols));
    windowSamples = max(8, round(windowSymbols*sps));

    info = struct('Applied',false, ...
        'WindowSymbols',windowSymbols, ...
        'WindowSamples',windowSamples, ...
        'MeanConfidence',NaN, ...
        'HoldSamples',0, ...
        'FinalRelativePhase_deg',0);
    if isempty(x)
        y = x;
        return;
    end

    magnitude = abs(x);
    unit = x ./ max(magnitude, sqrt(eps));
    observation = unit.^4;
    initCount = min(numel(x), windowSamples);
    state = mean(observation(1:initCount));
    if ~isfinite(real(state)) || ~isfinite(imag(state)) || abs(state) < eps
        state = observation(1);
    end
    alpha = exp(-1/windowSamples);
    confidenceFloor = 0.02;
    phase4 = zeros(numel(x),1);
    confidence = zeros(numel(x),1);
    previousWrapped = angle(state);
    unwrappedPhase = previousWrapped;
    holdCount = 0;
    for k = 1:numel(x)
        state = alpha*state + (1-alpha)*observation(k);
        confidence(k) = abs(state);
        if confidence(k) >= confidenceFloor
            currentWrapped = angle(state);
            unwrappedPhase = unwrappedPhase + angle(exp( ...
                1j*(currentWrapped-previousWrapped)));
            previousWrapped = currentWrapped;
        else
            holdCount = holdCount + 1;
        end
        phase4(k) = unwrappedPhase;
    end
    relativePhase = (phase4-phase4(1))/4;
    y = x .* exp(-1j*relativePhase);

    info.Applied = true;
    info.MeanConfidence = mean(confidence);
    info.HoldSamples = holdCount;
    info.FinalRelativePhase_deg = rad2deg(relativePhase(end));
end

function [y, info] = localSecondPowerHighRatePhaseTrack(x, sps, windowSymbols)
%LOCALSECONDPOWERHIGHRATEPHASETRACK Blind rectangular-UQPSK phase tracker.
% For UQPSK with I amplitude 1 and Q amplitude 1/2,
% E{s^2}=E{I^2-Q^2}+j2E{IQ} is nonzero and aligned to the unequal-power
% axes.  Under a channel rotation exp(j*phi), E{x^2} rotates by 2*phi.
% This provides a data-independent phase observation that ordinary equal-
% power QPSK does not have.  Only relative phase motion is removed; the
% remaining pi ambiguity is handled by the existing ASM rotation search.
    x = complex(x(:));
    sps = max(1, round(double(sps)));
    windowSymbols = max(2, double(windowSymbols));
    windowSamples = max(8, round(windowSymbols*sps));

    info = struct('Applied',false, ...
        'WindowSymbols',windowSymbols, ...
        'WindowSamples',windowSamples, ...
        'MeanConfidence',NaN, ...
        'HoldSamples',0, ...
        'FinalRelativePhase_deg',0);
    if isempty(x)
        y = x;
        return;
    end

    magnitude = abs(x);
    unit = x ./ max(magnitude, sqrt(eps));
    observation = unit.^2;
    initCount = min(numel(x), windowSamples);
    state = mean(observation(1:initCount));
    if ~isfinite(real(state)) || ~isfinite(imag(state)) || abs(state) < eps
        state = observation(1);
    end
    alpha = exp(-1/windowSamples);
    confidenceFloor = 0.01;
    phase2 = zeros(numel(x),1);
    confidence = zeros(numel(x),1);
    previousWrapped = angle(state);
    unwrappedPhase = previousWrapped;
    holdCount = 0;
    for k = 1:numel(x)
        state = alpha*state + (1-alpha)*observation(k);
        confidence(k) = abs(state);
        if confidence(k) >= confidenceFloor
            currentWrapped = angle(state);
            unwrappedPhase = unwrappedPhase + angle(exp( ...
                1j*(currentWrapped-previousWrapped)));
            previousWrapped = currentWrapped;
        else
            holdCount = holdCount + 1;
        end
        phase2(k) = unwrappedPhase;
    end
    relativePhase = (phase2-phase2(1))/2;
    y = x .* exp(-1j*relativePhase);

    info.Applied = true;
    info.MeanConfidence = mean(confidence);
    info.HoldSamples = holdCount;
    info.FinalRelativePhase_deg = rad2deg(relativePhase(end));
end

function [evmPct, merDB] = localOQPSKRailQualityMetrics( ...
        x, sps, rolloff, span)
%LOCALOQPSKRAILQUALITYMETRICS Quality at the staggered I/Q eye centers.
% This is not ordinary QPSK constellation EVM: the I and Q rails are
% matched-filtered and sampled a half-symbol apart.  Timing phase is chosen
% from the minimum rail-envelope variance, without using transmitted bits.
    x = complex(x(:));
    sps = max(2, round(double(sps)));
    span = max(1, round(double(span)));
    if isempty(x) || mod(sps,2) ~= 0
        evmPct = NaN;
        merDB = NaN;
        return;
    end
    h = rcosdesign(double(rolloff), span, sps, 'sqrt');
    matched = filter(h, 1, x);
    bestScore = inf;
    bestI = zeros(0,1);
    bestQ = zeros(0,1);
    for offset = 0:sps-1
        iCandidate = real(matched(1+offset:sps:end));
        qCandidate = imag(matched(1+offset+sps/2:sps:end));
        n = min(numel(iCandidate), numel(qCandidate));
        if n <= max(8,2*span)
            continue;
        end
        iCandidate = iCandidate(1:n);
        qCandidate = qCandidate(1:n);
        guard = min(span, floor((n-1)/4));
        use = (1+guard):(n-guard);
        amplitude = sqrt(mean(iCandidate(use).^2 + ...
            qCandidate(use).^2)/2 + eps);
        score = mean((abs(iCandidate(use))-amplitude).^2 + ...
            (abs(qCandidate(use))-amplitude).^2)/(2*amplitude^2+eps);
        if score < bestScore
            bestScore = score;
            bestI = iCandidate(use)/amplitude;
            bestQ = qCandidate(use)/amplitude;
        end
    end
    if isempty(bestI)
        evmPct = NaN;
        merDB = NaN;
        return;
    end
    iDecision = sign(bestI);
    qDecision = sign(bestQ);
    iDecision(iDecision == 0) = 1;
    qDecision(qDecision == 0) = 1;
    normalizedMSE = mean((bestI-iDecision).^2 + ...
        (bestQ-qDecision).^2)/2;
    evmPct = 100*sqrt(max(normalizedMSE,0));
    merDB = -10*log10(max(normalizedMSE,eps));
end

function demodData = localMSKOversampledSoftDemod(samples, sps)
%LOCALMSKOVERSAMPLEDSOFTDEMOD Combine all within-symbol phase increments.
% Adjacent-symbol sampling uses only one phase difference.  This metric
% integrates the CPM phase trajectory over the full symbol and downweights
% samples inside a deep amplitude notch.
    samples = complex(samples(:));
    nSymbols = floor(numel(samples)/sps);
    if nSymbols <= 0
        demodData = zeros(0,1);
        return;
    end
    block = reshape(samples(1:nSymbols*sps), sps, nSymbols);
    d = block(2:end,:) .* conj(block(1:end-1,:));
    rawMetric = sum(imag(d), 1).';
    robustScale = median(abs(rawMetric));
    if ~isfinite(robustScale) || robustScale <= eps
        robustScale = sqrt(mean(rawMetric.^2) + eps);
    end
    demodData = 5 * rawMetric / max(robustScale, eps);
    demodData = max(min(double(demodData),20),-20);
end

function noiseVar = localOQPSKNoiseVariance(opt)
    noiseVar = getfieldnumeric(opt, 'DemodNoiseVariance', NaN);
    if ~isfinite(noiseVar) || noiseVar <= 0
        snrDB = getfieldnumeric(opt, 'snr', 20);
        noiseVar = 10.^(-snrDB/10);
    end
    noiseVar = min(1, max(1e-4, noiseVar));
end

function stats = localAttachPredecoderFrameStats( ...
        stats, rxHard0, txBits, best, context)
    numTxFrames = getfieldnumeric(context, 'NumTxFrames', 0);
    warmUpFrames = max(0, round(getfieldnumeric( ...
        context, 'WarmUpFrames', 0)));
    if ~isfinite(numTxFrames) || numTxFrames < 1 || ...
            mod(numel(txBits), round(numTxFrames)) ~= 0
        return;
    end

    numTxFrames = round(numTxFrames);
    frameLength = numel(txBits) / numTxFrames;
    numFrames = min(numTxFrames, floor(best.len / frameLength));
    if numFrames < 1
        return;
    end

    rxAligned = rxHard0(best.rxStart - 1 + (1:numFrames*frameLength));
    if best.polarity < 0
        rxAligned = int8(~logical(rxAligned));
    end
    txAligned = txBits(best.txStart - 1 + (1:numFrames*frameLength));
    frameErrors = sum(reshape( ...
        rxAligned ~= txAligned, frameLength, numFrames), 1);
    frameBER = double(frameErrors(:)) / frameLength;

    firstSteadyFrame = min(numFrames + 1, warmUpFrames + 1);
    steadyFrames = firstSteadyFrame:numFrames;
    if isempty(steadyFrames)
        return;
    end
    steadyErrors = sum(frameErrors(steadyFrames));
    steadyBits = numel(steadyFrames) * frameLength;
    sortedBER = sort(frameBER(steadyFrames));
    p95Index = max(1, ceil(0.95*numel(sortedBER)));

    stats.PredecoderSteadyBER = steadyErrors / steadyBits;
    stats.PredecoderSteadyBitErrors = double(steadyErrors);
    stats.PredecoderSteadyBitsCompared = double(steadyBits);
    stats.PredecoderFramesCompared = double(numel(steadyFrames));
    stats.PredecoderFrameBERP95 = sortedBER(p95Index);
    stats.PredecoderFrameBERMax = max(sortedBER);
end

function localPrintPredecoderBurstDebug( ...
        demodData, txBits, tmMod, best, context)
%LOCALPRINTPREDECODERBURSTDEBUG Locate and characterize coded-boundary bursts.
% A global BER cannot distinguish a persistent synchronization error from one
% channel transient that destroys a single FEC frame.  This diagnostic uses
% the already verified ASM/TX alignment and never changes decoder data.
    numTxFrames = round(getfieldnumeric(context, 'NumTxFrames', 0));
    warmUpFrames = max(0, round(getfieldnumeric( ...
        context, 'WarmUpFrames', 0)));
    maxFramesToPrint = max(1, round(getfieldnumeric( ...
        context, 'MaxBurstFrames', 12)));
    if numTxFrames < 1 || mod(numel(txBits),numTxFrames) ~= 0 || ...
            best.len <= 0
        return;
    end

    frameLength = numel(txBits)/numTxFrames;
    numFrames = min(numTxFrames,floor(best.len/frameLength));
    if numFrames < 1
        return;
    end

    rxSoft = double(demodData(:));
    rxSoft = rxSoft(best.rxStart-1+(1:numFrames*frameLength));
    if best.polarity < 0
        rxSoft = -rxSoft;
    end
    txAligned = int8(txBits(best.txStart-1+(1:numFrames*frameLength)));
    rxHard = int8(rxSoft > 0);

    errorMatrix = reshape(rxHard ~= txAligned,frameLength,numFrames);
    frameErrors = sum(errorMatrix,1);
    firstSteadyFrame = min(numFrames+1,warmUpFrames+1);
    burstFrames = find(frameErrors > 0 & ...
        (1:numFrames) >= firstSteadyFrame);
    if isempty(burstFrames)
        fprintf('   [Coded burst DEBUG] no nonzero steady frames.\n');
        return;
    end

    [worstErrors,worstPosition] = max(frameErrors(burstFrames));
    worstFrame = burstFrames(worstPosition);
    fprintf(['   [Coded burst DEBUG] nonzero steady frames=%d/%d, ', ...
        'first=%d worst=%d (%d/%d, BER=%.6g)\n'], ...
        numel(burstFrames),numFrames-firstSteadyFrame+1, ...
        burstFrames(1),worstFrame,worstErrors,frameLength, ...
        worstErrors/frameLength);

    selectedFrames = burstFrames(1:min(maxFramesToPrint,numel(burstFrames)));
    if ~ismember(worstFrame,selectedFrames)
        selectedFrames(end) = worstFrame;
        selectedFrames = sort(unique(selectedFrames));
    end
    bitsPerSymbol = localBitsPerSymbolForDebug(tmMod);
    for iFrame = selectedFrames(:).'
        frameRange = (iFrame-1)*frameLength+(1:frameLength);
        errorMask = errorMatrix(:,iFrame);
        errorPositions = find(errorMask);
        edge = diff([false; errorMask; false]);
        runStarts = find(edge == 1);
        runStops = find(edge == -1)-1;
        if isempty(runStarts)
            longestRun = 0;
            numRuns = 0;
            firstError = NaN;
            lastError = NaN;
            medianWrongLLR = NaN;
        else
            longestRun = max(runStops-runStarts+1);
            numRuns = numel(runStarts);
            firstError = errorPositions(1);
            lastError = errorPositions(end);
            medianWrongLLR = median(abs(rxSoft(frameRange(errorMask))));
        end
        correctMask = ~errorMask;
        if any(correctMask)
            medianCorrectLLR = median(abs(rxSoft(frameRange(correctMask))));
        else
            medianCorrectLLR = NaN;
        end
        txFrameIndex = best.txFrameOffset+iFrame-1;
        fprintf(['      rxFrame=%03d txFrame=%03d err=%5d BER=%.6g ', ...
            'span=%g:%g runs=%d longest=%d |LLR| wrong/correct=%.3g/%.3g'], ...
            iFrame,txFrameIndex,frameErrors(iFrame), ...
            frameErrors(iFrame)/frameLength,firstError,lastError, ...
            numRuns,longestRun,medianWrongLLR,medianCorrectLLR);
        if bitsPerSymbol > 1
            fprintf(' planeBER=[');
            for iPlane = 1:bitsPerSymbol
                planeMask = false(frameLength,1);
                planeMask(iPlane:bitsPerSymbol:end) = true;
                if iPlane > 1
                    fprintf(',');
                end
                fprintf('%.4g', ...
                    nnz(errorMask & planeMask)/nnz(planeMask));
            end
            fprintf(']');
        end
        fprintf('\n');
    end
end

function localTPCPrintBitPlaneDebug(demodData, txBits, tmMod, best)
    bitsPerSym = localBitsPerSymbolForDebug(tmMod);
    if bitsPerSym <= 1 || best.len <= 0
        return;
    end

    rxSoft = double(demodData(:));
    rxSoft = rxSoft(best.rxStart:best.rxStart+best.len-1);
    if best.polarity < 0
        rxSoft = -rxSoft;
    end
    rxHard = int8(rxSoft > 0);
    txAlign = int8(txBits(best.txStart:best.txStart+best.len-1));

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
        'CorrRatio', NaN, ...
        'FadeFraction', NaN, ...
        'DataFadeMask', false(0,1), ...
        'MaxAppliedGain_dB', NaN, ...
        'Regularization', NaN, ...
        'PilotNoiseVariance', NaN);
end

function names = localPredecoderResultFields()
    names = { ...
        'PredecoderBER','PredecoderOffset','PredecoderPolarity', ...
        'PredecoderTxFrameOffset','PredecoderASMAligned', ...
        'PredecoderBitErrors','PredecoderBitsCompared', ...
        'PredecoderSteadyBER','PredecoderSteadyBitErrors', ...
        'PredecoderSteadyBitsCompared','PredecoderFramesCompared', ...
        'PredecoderFrameBERP95','PredecoderFrameBERMax'};
end

function stats = localEmptyPredecoderStats()
    names = localPredecoderResultFields();
    stats = struct();
    for k = 1:numel(names)
        stats.(names{k}) = NaN;
    end
end

function stats = localAttachPredecoderStats(stats, predecoderStats)
    names = localPredecoderResultFields();
    for k = 1:numel(names)
        name = names{k};
        if isstruct(predecoderStats) && isfield(predecoderStats, name)
            stats.(name) = predecoderStats.(name);
        end
    end
end

function [dataSym, info, uncorrectedDataSym] = ...
        localCorrectAndRemoveTMAPSKPilots(rxSym, opt, symbolRate)
    dataSym = rxSym;
    uncorrectedDataSym = rxSym;
    info = localEmptyTMAPSKPilotInfo();
    info.Enabled = true;

    if isfield(opt,'HasTMAPSKPilots') && ~isempty(opt.HasTMAPSKPilots) && ...
            ~localFlagValue(opt.HasTMAPSKPilots)
        info.Reason = 'disabled by HasTMAPSKPilots';
        return;
    end

    rx = rxSym(:);
    rawFadeMask = false(numel(rx),1);
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
    uncorrectedDataSym = rx(dataMask);

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
    correctionGain = [];
    if correctionMode == "interp"
        ph = unwrap(angle(hPilot));
        phInterp = interp1(double(pilotPos), ph, double(allIdx), 'linear', 'extrap');
        ampInterp = interp1(double(pilotPos), amp, double(allIdx), 'linear', 'extrap');
        ampInterp = max(ampInterp, sqrt(eps));
        hInterp = ampInterp .* exp(1j * phInterp);
    elseif correctionMode == "phaseinterp" || correctionMode == "phase" || ...
            correctionMode == "mmseinterp" || correctionMode == "mmse"
        blockCentersPost = zeros(numBlocks, 1);
        blockHPost = complex(zeros(numBlocks, 1));
        blockNoisePost = nan(numBlocks, 1);
        for iBlock = 1:numBlocks
            idx = blockBreaks(iBlock):(blockBreaks(iBlock+1)-1);
            blockCentersPost(iBlock) = mean(double(pilotPos(idx)));
            hBlock = hPilot(idx);
            % A component-wise median prevents one damaged pilot symbol
            % from rotating the complete block estimate.
            blockHPost(iBlock) = median(real(hBlock)) + ...
                1j*median(imag(hBlock));
            blockNoisePost(iBlock) = median(abs(hBlock-blockHPost(iBlock)).^2);
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
            ampBlock = abs(blockHPost(validBlocks));
            amp0 = median(ampBlock(isfinite(ampBlock) & ampBlock > 0));
            if isempty(amp0) || ~isfinite(amp0) || amp0 < sqrt(eps)
                amp0 = 1;
            end
            if correctionMode == "mmseinterp" || correctionMode == "mmse"
                % Interpolate log amplitude so a single deep block cannot
                % produce a negative/overshooting linear amplitude trace.
                logAmpBlock = log(max(ampBlock, amp0*1e-4));
                if smoothWindow > 1 && numel(logAmpBlock) >= smoothWindow
                    logAmpBlock = movmedian(logAmpBlock, smoothWindow);
                end
                logAmpInterp = interp1( ...
                    double(blockCentersPost(validBlocks)), logAmpBlock, ...
                    double(allIdx), 'linear', 'extrap');
                ampInterp = exp(logAmpInterp);
                % In a deep fade, the pilot-derived inverse should not
                % chase a transient amplitude null.  Keep the phase
                % trajectory, but hold the amplitude at the local median;
                % the regularized inverse then avoids turning a short fade
                % into a large noise burst for the APSK equalizer.
                fadeThresholdDB = getfieldnumeric(opt, ...
                    'TMAPSKPilotFadeThresholdDB', -12);
                fadeThreshold = amp0 * 10^(fadeThresholdDB/20);
                rawFadeMask = ampInterp < fadeThreshold;
                fadeHoldEnabled = true;
                if isfield(opt,'TMAPSKPilotFadeHold') && ...
                        ~isempty(opt.TMAPSKPilotFadeHold)
                    fadeHoldEnabled = localFlagValue(opt.TMAPSKPilotFadeHold);
                end
                if fadeHoldEnabled && any(rawFadeMask)
                    ampInterp(rawFadeMask) = amp0;
                end
                hInterp = ampInterp .* exp(1j * phInterp);

                regFactor = getfieldnumeric(opt, ...
                    'TMAPSKPilotMMSERegularization', 0.01);
                regFactor = max(0, double(regFactor));
                lambda = max(eps, regFactor * amp0^2);
                correctionGain = conj(hInterp) ./ (abs(hInterp).^2 + lambda);

                maxGainDB = getfieldnumeric(opt, 'TMAPSKPilotMaxGainDB', 18);
                maxGainAbs = (1/amp0) * 10^(maxGainDB/20);
                gainAbs = abs(correctionGain);
                overGain = gainAbs > maxGainAbs;
                if any(overGain)
                    correctionGain(overGain) = correctionGain(overGain) .* ...
                        (maxGainAbs ./ gainAbs(overGain));
                end

                info.FadeFraction = mean(rawFadeMask);
                info.MaxAppliedGain_dB = 20*log10( ...
                    max(abs(correctionGain))*amp0 + eps);
                info.Regularization = lambda;
                validNoise = blockNoisePost(isfinite(blockNoisePost));
                if ~isempty(validNoise)
                    info.PilotNoiseVariance = median(validNoise) / ...
                        max(amp0^2, eps);
                end
            else
                hInterp = amp0 .* exp(1j * phInterp);
            end
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
    if isempty(correctionGain)
        rxCorr = rxCFO ./ hInterp;
    else
        % Regularized inverse: unlike direct division, a spectral null is
        % attenuated instead of being converted into an arbitrarily large
        % noise burst.
        rxCorr = rxCFO .* correctionGain;
    end

    dataSym = rxCorr(dataMask);
    if isempty(dataSym)
        info.Reason = 'pilot removal produced no data symbols';
        dataSym = rxSym;
        uncorrectedDataSym = rxSym;
        return;
    end

    info.Applied = true;
    info.Reason = 'applied';
    info.Start = startPos;
    info.NumPilots = numel(pilotPos);
    info.NumDataSymbols = numel(dataSym);
    info.DataFadeMask = logical(rawFadeMask(dataMask));
    info.CFO_Hz = totalSlopeRadPerSym * double(symbolRate) / (2*pi);
    info.MeanAmp = mean(amp);

    if evalin('base','exist(''DEBUG_APSK'',''var'') && logical(DEBUG_APSK)')
        fprintf(['[APSK TM pilots] applied=%d, start=%d, pilots=%d, data=%d, ', ...
            'corrRatio=%.3f, cfoEst=%.2f Hz, meanAmp=%.4f, ', ...
            'fade=%.1f%%, maxGain=%.1f dB, noiseVar=%.3g\n'], ...
            info.Applied, info.Start, info.NumPilots, info.NumDataSymbols, ...
            info.CorrRatio, info.CFO_Hz, info.MeanAmp, ...
            100*info.FadeFraction, info.MaxAppliedGain_dB, ...
            info.PilotNoiseVariance);
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

function catalog = localBuildTMFrameCatalog(txFrames)
    % VCFC is only eight bits and repeats every 256 frames.  A map keyed
    % only by VCFC overwrites earlier frames in a long simulation.  Store
    % every transmitted occurrence so BER/FER remains valid after wrap.
    catalog = cell(256, 1);
    for k = 1:numel(txFrames)
        if isempty(txFrames{k})
            continue;
        end
        id = localTMFrameID(txFrames{k});
        catalog{id + 1}(end + 1) = k; %#ok<AGROW>
    end
end

function [matched, txFrame, txFrameIndex] = ...
        localMatchTMFrameOccurrence( ...
            rxFrame, txFrames, catalog, lastMatchedTxIndex)
    matched = false;
    txFrame = [];
    txFrameIndex = NaN;
    rxId = localTMFrameID(rxFrame);
    candidates = catalog{rxId + 1};
    if isempty(candidates)
        return;
    end

    % Once acquisition has a reliable frame, decoded frames are ordered, so
    % choose the first same-VCFC occurrence after that absolute TX index.
    % This makes measurement-window membership deterministic after wrap.
    if nargin >= 4 && isfinite(lastMatchedTxIndex)
        forwardCandidates = candidates(candidates > lastMatchedTxIndex);
        if ~isempty(forwardCandidates)
            txFrameIndex = forwardCandidates(1);
            txFrame = txFrames{txFrameIndex};
            matched = true;
            return;
        end
    end

    % Before the first reliable frame, use payload distance only to resolve
    % which counter cycle supplied the acquisition frame.  This metadata is
    % used only by the offline metric engine and never enters the receiver.
    errorCounts = inf(size(candidates));
    rxBits = double(rxFrame(:));
    for k = 1:numel(candidates)
        refBits = double(txFrames{candidates(k)}(:));
        if numel(refBits) == numel(rxBits)
            errorCounts(k) = biterr(refBits, rxBits);
        end
    end
    [bestErrors, best] = min(errorCounts);
    if isempty(best) || ~isfinite(bestErrors)
        return;
    end
    txFrameIndex = candidates(best);
    txFrame = txFrames{txFrameIndex};
    matched = true;
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
    if isfield(fields, 'TMDataSource')
        fprintf('  Data source: %s (%s rail)', ...
            fields.TMDataSource, fields.TMDataSourceRail);
        if isfield(fields, 'TMDataSourcePolynomial') && ...
                ~isempty(fields.TMDataSourcePolynomial)
            fprintf(', polynomial=%s', fields.TMDataSourcePolynomial);
        end
        fprintf('\n');
    end
end

function printMetrics(res, opt)
    isGMSK = contains(upper(string(res.modType)), 'GMSK');
    isCPM = isGMSK || strcmpi(string(res.modType),'MSK');
    isOQPSK = strcmpi(string(res.modType),'OQPSK');

    fprintf('\n========= CCSDS 评估结果 =========\n');
    fprintf(' 调制方式 : %s\n', res.modType);
    if isfield(res,'centerFrequencyHz') && isfinite(res.centerFrequencyHz) && res.centerFrequencyHz > 0
        fprintf(' 中心频率 : %.3f MHz\n', res.centerFrequencyHz/1e6);
    end
    fprintf(' 输入 SNR : %.1f dB,  CFO=%.1f Hz,  Phase=%.1f deg,  Delay=%.3f\n', ...
        res.snr_in, res.cfo_in, res.phase_in, res.delay_in);
    if isfield(res,'NoiseMode') && strcmpi(char(res.NoiseMode), 'psd')
        fprintf(' Noise mode   : fixed PSD; the legacy snr field above is inactive\n');
    elseif isfield(res,'NoiseMode') && strcmpi(char(res.NoiseMode), 'off')
        fprintf(' Noise mode   : OFF (exactly noise-free diagnostic)\n');
    end
    if isfield(res,'ConverterChainEnabled') && res.ConverterChainEnabled
        fprintf([' Converter     : IF=%+.2f dBm -> up=%+.2f dBm -> ', ...
            'H=%+.2f dB -> down-in=%+.2f dBm -> down-out=%+.2f dBm\n'], ...
            res.BasebandIFLevel_dBm, res.UpconverterOutputLevel_dBm, ...
            res.HAppliedGain_dB, res.DownconverterInputLevel_dBm, ...
            res.DownconverterOutputLevel_dBm);
        fprintf(' Converter chk : down-input-range=%d, P1dB-risk(up/down)=%d/%d\n', ...
            res.DownconverterInputWithinTypicalRange, ...
            res.UpconverterCompressionRisk, res.DownconverterCompressionRisk);
        if isfield(res,'ADCEquivalentEnabled') && res.ADCEquivalentEnabled
            fprintf(' ADC model     : %d bit, backoff=%.2f dB, clip=%.4g%%\n', ...
                res.ADCBits, res.ADCRMSBackoff_dB, 100*res.ADCClipFraction);
        end
    end
    if isfield(res,'NoisePlacement')
        fprintf(' Noise order  : %s\n', res.NoisePlacement);
    end
    if isfield(res,'NoiseMode') && strcmpi(char(res.NoiseMode), 'psd')
        fprintf(' Noise PSD    : %.2f dBm/Hz over %.3g Hz -> %.2f dBm, EqSNR=%.2f dB\n', ...
            res.NoisePSD_dBmHz, res.NoiseBandwidthHz, ...
            res.NoisePower_dBm, res.NoiseEquivalentSNR_dB);
        if isfield(res,'NoiseReferenceLevel_dBm')
            fprintf(' Signal ref   : %.2f dBm before H/channel damage\n', ...
                res.NoiseReferenceLevel_dBm);
        end
    end
    if isfield(res,'GMSKDetectorUsed') && ...
            ~strcmpi(char(res.GMSKDetectorUsed), 'not-applicable')
        fprintf(' GMSK detector: %s\n', char(res.GMSKDetectorUsed));
    end
    if isfield(res,'TMDataSource')
        if strcmpi(char(res.TMDataSource), 'split')
            fprintf(' TM data source: I=%s, Q=%s\n', ...
                char(res.TMDataSourceI), char(res.TMDataSourceQ));
        else
            fprintf(' TM data source: %s\n', char(res.TMDataSource));
        end
    end
    fprintf(' --------------------------------\n');
    fprintf(' BER          : %.6f\n', res.BER);

    if isCPM
        fprintf(' CPM quality  : N/A (use BER / FER / frame lock)\n');
    elseif isOQPSK
        fprintf(' OQPSK rail EVM: %6.2f %%\n', res.EVM_post_pct);
        fprintf(' OQPSK rail MER: %6.2f dB\n', res.MER_dB);
    elseif isGMSK
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

function fe = buildFrontendArrays(ctx, res, includeRawData) %#ok<INUSD>
    if nargin < 3
        includeRawData = false;
    end
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
    if includeRawData
        fe.spectrum.cfo_estimator = buildCFOEstimatorSpectrum(ctx, res);
    else
        fe.spectrum.cfo_estimator = struct('valid', false);
    end

    % --- 信道功率轨迹（前端使用；仅传抽样曲线，不改变评估链路） ---
    if includeRawData && isfield(ctx,'channelInput') && ~isempty(ctx.channelInput)
        channelIn = ctx.channelInput(:);
    elseif includeRawData
        channelIn = ctx.txWaveform(:);
    else
        channelIn = [];
    end
    if includeRawData && isfield(ctx,'channelOutput') && ~isempty(ctx.channelOutput)
        channelOut = ctx.channelOutput(:);
    elseif includeRawData
        channelOut = ctx.rxWaveform(:);
    else
        channelOut = [];
    end
    if ~isempty(channelIn) && ~isempty(channelOut)
        sampleCount = min([5000, numel(channelIn), numel(channelOut)]);
        refPower = mean(abs(channelIn).^2);
        if ~isfinite(refPower) || refPower <= 0, refPower = 1; end
        inputLevelDbm = getfieldnumeric(res, 'inputLevelDbm', 0);
        inSamples = channelIn(1:sampleCount);
        outSamples = channelOut(1:sampleCount);
        fe.channelPower = struct( ...
            'time_ms', reshape((0:sampleCount-1).' / Fs * 1000, 1, []), ...
            'input_power_dbm', reshape(inputLevelDbm + 10*log10(max(abs(inSamples).^2 / refPower, realmin)), 1, []), ...
            'output_power_dbm', reshape(inputLevelDbm + 10*log10(max(abs(outSamples).^2 / refPower, realmin)), 1, []));
        [pIn, fPower] = pwelch(channelIn, [], [], 2048, Fs, 'centered');
        [pOut, ~] = pwelch(channelOut, [], [], 2048, Fs, 'centered');
        fe.channelPower.frequency_mhz = reshape(fPower / 1e6, 1, []);
        fe.channelPower.input_psd_dbmhz = reshape(inputLevelDbm + 10*log10(max(pIn / refPower, realmin)), 1, []);
        fe.channelPower.output_psd_dbmhz = reshape(inputLevelDbm + 10*log10(max(pOut / refPower, realmin)), 1, []);
    else
        fe.channelPower = struct('time_ms', [], 'input_power_dbm', [], ...
            'output_power_dbm', [], 'frequency_mhz', [], ...
            'input_psd_dbmhz', [], 'output_psd_dbmhz', []);
    end
    % --- 星座: 发送端兜底显示（未经过信道损伤）---
    fe.constTx   = sampleConst(normPwr(ctx.txWaveform(1:sps:end)), 1500);
    % --- 星座: 修复前 (raw, 信道损伤后, 无任何同步) ---

    fe.constRaw  = sampleConst(ctx.rawSym,     1500);
    % --- 星座: 修复后 (载波同步对齐到参考相位) ---
    fe.constSync = sampleConst(ctx.fineSynced, 1500);

    % --- 4 阶段管线星座仅在完整数据模式下计算 ---
    if includeRawData
        s1 = normPwr(ctx.rxWaveform(1:sps:end));
        s2 = normPwr(ctx.coarseSynced(1:sps:end));
        s3 = normPwr(ctx.TimeSynced);
        s4 = ctx.fineSynced;

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
    else
        fe.pipeline = struct();
    end

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
    actualWaveformDuration_s = numel(txWaveform) / Fs;
    fprintf(['[Test length] waveform=%.3f ms | warmup=%d | ', ...
        'BER=%d | total=%d frames\n'], ...
        1e3*actualWaveformDuration_s, simParams.InitalSyncFrames, ...
        simParams.NumFramesForBER, simParams.NumPLFrames);
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
    res.ActualWaveformDuration_s = actualWaveformDuration_s;
    res.ACMFormat = acmFmt;
    res.CodeRate = facmCodeRate(acmFmt);
    res.snr_in = snr_val;
    res.NoisePlacement = char(noisePlacement);
    res.NoiseMode = char(noiseInfo.Mode);
    if isfinite(noiseInfo.PSD_dBmHz)
        res.NoisePSD_dBmHz = noiseInfo.PSD_dBmHz;
        res.NoiseBandwidthHz = noiseInfo.BandwidthHz;
        res.NoisePower_dBm = noiseInfo.NoisePower_dBm;
        res.NoiseReferenceLevel_dBm = noiseInfo.ReferenceLevel_dBm;
    end
    res.NoiseEquivalentSNR_dB = noiseInfo.EquivalentSNR_dB;
    res.cfo_in = cfo_val;
    res.phase_in = phase_deg;
    res.delay_in = delay_val;
    res.centerFrequencyHz = getCenterFrequencyHz(opt, 0);
    res.IFHz = res.centerFrequencyHz;
    res.carrierFreqHz = res.centerFrequencyHz;
    res.inputLevelDbm = getInputLevelDbm(opt, -10);
    res.outputLevelDbm = res.inputLevelDbm;
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
    % 保持旧字段表示实际进入同步器的信号。
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
function [y, info] = uqpskCarrierRecover(x, aRatio, loopBW, opt, symbolRate)
%UQPSKCARRIERRECOVER UQPSK structure-aided second-order carrier PLL.
% Uses a wide acquisition bandwidth, a narrow tracking bandwidth, an
% amplitude-normalized teacher-style phase detector, and frequency coast
% through deep fades. No transmitted bits or known H coefficients are used.
    if nargin < 4 || isempty(opt), opt = struct(); end
    if nargin < 5 || isempty(symbolRate), symbolRate = 1; end
    if nargin < 3 || isempty(loopBW), loopBW = 0.002; end

    x = complex(x(:));
    y = zeros(size(x));
    info = localEmptyUQPSKCarrierPLLInfo();
    if isempty(x), return; end

    hEnabled = getLogicalField(opt,'enableHChannel',false);
    dualBandwidth = getLogicalField(opt, ...
        'enableUQPSKDualBandwidthCarrierPLL',hEnabled);
    acquireBW = getfieldnumeric(opt,'uqpskCarrierAcquireLoopBW',0.05);
    % The unequal-I/Q detector must follow normalized H phase through fast
    % fades.  A 0.02 H-path default can remain apparently locked while a
    % late phase excursion corrupts whole rail frames; 0.05 tracked the
    % normalized std7 profile without changing the NoH loopBW baseline.
    trackBW = getfieldnumeric(opt,'uqpskCarrierTrackLoopBW',max(loopBW,0.05));
    if ~dualBandwidth
        acquireBW = loopBW;
        trackBW = loopBW;
    end
    acquireBW = min(max(acquireBW,1e-5),0.2);
    trackBW = min(max(trackBW,1e-5),acquireBW);

    fadeThresholdDB = getfieldnumeric(opt,'uqpskCarrierFadeThresholdDB',-12);
    fadeRatio = 10^(min(fadeThresholdDB,0)/20);
    lockThreshold = getfieldnumeric(opt,'uqpskCarrierLockErrorThreshold',0.12);
    unlockThreshold = getfieldnumeric(opt,'uqpskCarrierUnlockErrorThreshold',0.40);
    lockSymbols = max(8,round(getfieldnumeric(opt,'uqpskCarrierLockSymbols',256)));
    unlockSymbols = max(8,round(getfieldnumeric(opt,'uqpskCarrierUnlockSymbols',128)));
    minAcquireSymbols = max(lockSymbols,round(getfieldnumeric(opt, ...
        'uqpskCarrierMinAcquireSymbols',4096)));
    errorTau = max(8,getfieldnumeric(opt,'uqpskCarrierErrorTauSymbols',64));
    errorAlpha = exp(-1/errorTau);
    maxFrequencyFraction = getfieldnumeric(opt, ...
        'uqpskCarrierMaxFrequencyFraction',0.10);
    maxFrequencyFraction = min(max(maxFrequencyFraction,1e-4),0.45);
    maxOmega = 2*pi*maxFrequencyFraction;
    [externalHoldMask,externalHoldProvided] = ...
        localReceiverExternalHoldMask(opt,numel(x));

    nInit = min(numel(x),128);
    amplitudeRef = median(abs(x(1:nInit)));
    if ~isfinite(amplitudeRef) || amplitudeRef <= 1e-8
        amplitudeRef = sqrt(mean(abs(x(1:nInit)).^2) + eps);
    end
    amplitudeRef = max(amplitudeRef,1e-8);
    referenceDecay = exp(-1/max(1024,lockSymbols));

    theta = 0;
    omega = 0;
    errorState = unlockThreshold;
    goodCount = 0;
    badCount = 0;
    locked = false;
    lockTransitions = 0;
    reacquisitions = 0;
    fadeHoldSymbols = 0;
    acceptedUpdates = 0;
    absErrorSum = 0;
    mode = 'acquire';
    acquireAge = 0;

    for n = 1:numel(x)
        if ~locked
            acquireAge = acquireAge + 1;
        end
        z = x(n)*exp(-1j*theta);
        y(n) = z;
        amplitude = abs(z);
        if isfinite(amplitude)
            amplitudeRef = max(amplitude,referenceDecay*amplitudeRef);
        end
        inFade = externalHoldMask(n) || ~isfinite(amplitude) || ...
            amplitude < fadeRatio*max(amplitudeRef,1e-8);

        if inFade
            theta = theta + omega;
            fadeHoldSymbols = fadeHoldSymbols + 1;
        else
            I = real(z);
            Q = imag(z);
            sI = sign(I); if sI == 0, sI = 1; end
            sQ = sign(Q); if sQ == 0, sQ = 1; end
            rawError = sI*Q*aRatio - sQ*I;
            phaseError = rawError/max(amplitude,fadeRatio*amplitudeRef);
            phaseError = min(max(phaseError,-1),1);

            if locked, activeBW = trackBW; else, activeBW = acquireBW; end
            Kp = activeBW;
            Ki = activeBW^2/4;
            omega = omega + Ki*phaseError;
            omega = min(max(omega,-maxOmega),maxOmega);
            theta = theta + omega + Kp*phaseError;

            errorState = errorAlpha*errorState + ...
                (1-errorAlpha)*abs(phaseError);
            acceptedUpdates = acceptedUpdates + 1;
            absErrorSum = absErrorSum + abs(phaseError);

            if ~locked
                if errorState <= lockThreshold
                    goodCount = goodCount + 1;
                else
                    goodCount = 0;
                end
                if goodCount >= lockSymbols && acquireAge >= minAcquireSymbols
                    locked = true;
                    mode = 'track';
                    lockTransitions = lockTransitions + 1;
                    badCount = 0;
                end
            else
                if errorState >= unlockThreshold
                    badCount = badCount + 1;
                else
                    badCount = 0;
                end
                if badCount >= unlockSymbols
                    locked = false;
                    mode = 'acquire';
                    reacquisitions = reacquisitions + 1;
                    goodCount = 0;
                    badCount = 0;
                    acquireAge = 0;
                end
            end
        end
        theta = mod(theta+pi,2*pi)-pi;
    end

    info.Applied = true;
    info.DualBandwidth = dualBandwidth;
    info.Locked = locked;
    info.FinalMode = mode;
    info.AcquireLoopBW = acquireBW;
    info.TrackLoopBW = trackBW;
    info.FinalFrequencyRadPerSymbol = omega;
    info.FinalFrequency_Hz = omega*symbolRate/(2*pi);
    info.LockTransitions = lockTransitions;
    info.Reacquisitions = reacquisitions;
    info.FadeHoldSymbols = fadeHoldSymbols;
    info.ExternalHoldMaskProvided = externalHoldProvided;
    info.ExternalHoldSymbols = nnz(externalHoldMask);
    info.ExternalHoldFraction = mean(externalHoldMask);
    info.UpdateAcceptanceRate = acceptedUpdates/max(numel(x),1);
    info.MeanAbsPhaseError = absErrorSum/max(acceptedUpdates,1);
    info.FinalErrorState = errorState;
end

function info = localEmptyUQPSKCarrierPLLInfo()
    info = struct( ...
        'Applied',false,'DualBandwidth',false,'Locked',false, ...
        'FinalMode','off','AcquireLoopBW',NaN,'TrackLoopBW',NaN, ...
        'FinalFrequencyRadPerSymbol',NaN,'FinalFrequency_Hz',NaN, ...
        'LockTransitions',0,'Reacquisitions',0,'FadeHoldSymbols',0, ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSymbols',0, ...
        'ExternalHoldFraction',0, ...
        'UpdateAcceptanceRate',NaN,'MeanAbsPhaseError',NaN, ...
        'FinalErrorState',NaN);
end

function y = uqpskCarrierRecoverLegacy(x, aRatio, loopBW)

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
function [y, cfoEst] = localMSKGMSKX2CoarseCFO( ...
        x, Fs, fSym, enabled)

    x = x(:);

    if ~enabled || numel(x) < 64
        cfoEst = 0;
        y = x;
        return;
    end

    Lfft = min(numel(x), 2^19);
    Nfft = 2^nextpow2(Lfft);

    win = hamming(Lfft);
    xSquared = x(1:Lfft).^2;

    spectrum = fftshift(fft(xSquared .* win, Nfft));
    powerSpectrum = abs(spectrum).^2;

    frequencyAxis = ...
        (-Nfft/2:Nfft/2-1).' * (Fs/Nfft);

    positiveIndices = find( ...
        frequencyAxis > 0.25*fSym & ...
        frequencyAxis < 1.00*fSym);

    negativeIndices = find( ...
        frequencyAxis < -0.25*fSym & ...
        frequencyAxis > -1.00*fSym);

    if isempty(positiveIndices) || isempty(negativeIndices)
        cfoEst = 0;
        y = x;
        return;
    end

    [~, positiveLocalIndex] = ...
        max(powerSpectrum(positiveIndices));

    [~, negativeLocalIndex] = ...
        max(powerSpectrum(negativeIndices));

    positivePeakIndex = ...
        positiveIndices(positiveLocalIndex);

    negativePeakIndex = ...
        negativeIndices(negativeLocalIndex);

    binHz = Fs/Nfft;

    positiveOffset = localParabolicSpectrumPeakOffset( ...
        powerSpectrum, positivePeakIndex);

    negativeOffset = localParabolicSpectrumPeakOffset( ...
        powerSpectrum, negativePeakIndex);

    positivePeakHz = ...
        frequencyAxis(positivePeakIndex) + ...
        positiveOffset*binHz;

    negativePeakHz = ...
        frequencyAxis(negativePeakIndex) + ...
        negativeOffset*binHz;

    % x^2 使 CFO 变成 2*CFO；
    % 正负谱峰中点仍需再除以 2。
    cfoEst = ...
        (positivePeakHz + negativePeakHz)/4;

    sampleIndex = (0:numel(x)-1).';

    y = x .* exp( ...
        -1j*2*pi*cfoEst*sampleIndex/Fs);
end

function [y, info] = localGMSKResidualDopplerTracker(x, Fs, fSym, opt)
%LOCALGMSKRESIDUALDOPPLERTRACKER Track residual Doppler on an 8-sps CPM wave.
% Every overlapping window estimates the midpoint of the two GMSK x^2
% spectral lines.  Interpolating and integrating those estimates produces
% one continuous phase correction with no block-boundary phase jumps.
    x = complex(x(:));
    y = x;
    info = localEmptyGMSKResidualTrackerInfo();
    enabled = getLogicalField(opt,'enableGMSKResidualDopplerTracker',true);
    debugTracker = getLogicalField(opt,'debugGMSKResidualTracker',false);
    % In debug mode an OFF run still computes the hypothetical estimate but
    % never applies it. This makes ON/OFF comparisons use the same evidence.
    if (~enabled && ~debugTracker) || numel(x) < 256 || ~isfinite(Fs) || Fs <= 0 || ...
            ~isfinite(fSym) || fSym <= 0
        return;
    end

    windowSymbols = max(256,round(getfieldnumeric(opt, ...
        'gmskResidualWindowSymbols',1024)));
    hopSymbols = max(64,round(getfieldnumeric(opt, ...
        'gmskResidualHopSymbols',256)));
    windowSamples = min(numel(x), ...
        max(256,round(windowSymbols*Fs/fSym)));
    hopSamples = max(64,round(hopSymbols*Fs/fSym));
    maxFFT = min(2^17,2^nextpow2(windowSamples));

    starts = 1:hopSamples:max(1,numel(x)-windowSamples+1);
    finalStart = max(1,numel(x)-windowSamples+1);
    if starts(end) ~= finalStart
        starts(end+1) = finalStart; %#ok<AGROW>
    end
    centers = starts(:)+(windowSamples-1)/2;
    estimates = nan(numel(starts),1);
    candidateEstimates = nan(numel(starts),1);
    confidence = nan(numel(starts),1);
    [externalHoldMask,externalHoldProvided] = ...
        localReceiverExternalHoldMask(opt,numel(x));
    externalHoldFraction = zeros(numel(starts),1);
    externalHoldMaxFraction = min(1,max(0,getfieldnumeric(opt, ...
        'gmskResidualExternalHoldMaxFraction',0)));
    minConfidenceDB = getfieldnumeric(opt,'gmskResidualMinConfidenceDB',8);
    maxResidualHz = abs(getfieldnumeric(opt, ...
        'gmskResidualMaxFrequencyFraction',0.02))*fSym;

    for k = 1:numel(starts)
        idx = starts(k):(starts(k)+windowSamples-1);
        [estimateHz,confidenceDB] = localGMSKX2CFOEstimate( ...
            x(idx),Fs,fSym,maxFFT);
        candidateEstimates(k) = estimateHz;
        confidence(k) = confidenceDB;
        externalHoldFraction(k) = mean(externalHoldMask(idx));
        if externalHoldFraction(k) <= externalHoldMaxFraction && ...
                isfinite(estimateHz) && isfinite(confidenceDB) && ...
                confidenceDB >= minConfidenceDB && ...
                abs(estimateHz) <= maxResidualHz
            estimates(k) = estimateHz;
        end
    end

    candidateFinite = isfinite(candidateEstimates);
    finiteCandidates = candidateEstimates(candidateFinite);
    if isempty(finiteCandidates)
        candidateMin = NaN; candidateMedian = NaN;
        candidateMax = NaN; candidateRMS = NaN;
    else
        candidateMin = min(finiteCandidates);
        candidateMedian = median(finiteCandidates);
        candidateMax = max(finiteCandidates);
        candidateRMS = sqrt(mean(finiteCandidates.^2));
    end
    nonfiniteWindows = nnz(~candidateFinite);
    confidenceRejected = nnz(candidateFinite & ...
        (~isfinite(confidence) | confidence < minConfidenceDB));
    rangeRejected = nnz(candidateFinite & isfinite(confidence) & ...
        confidence >= minConfidenceDB & abs(candidateEstimates) > maxResidualHz);

    rawEstimates = estimates;
    rawAccepted = isfinite(rawEstimates);
    rawFinite = rawEstimates(rawAccepted);
    if isempty(rawFinite)
        rawMin = NaN; rawMedian = NaN; rawMax = NaN; rawRMS = NaN;
        rawAcceptedRate = 0;
    else
        rawMin = min(rawFinite); rawMedian = median(rawFinite);
        rawMax = max(rawFinite); rawRMS = sqrt(mean(rawFinite.^2));
        rawAcceptedRate = nnz(rawAccepted)/numel(rawAccepted);
    end
    rawJumpsAll = diff(rawEstimates);
    adjacentAccepted = rawAccepted(1:end-1) & rawAccepted(2:end);
    rawJumps = rawJumpsAll(adjacentAccepted);
    if isempty(rawJumps)
        jumpMax = 0; jumpRMS = 0;
    else
        jumpMax = max(abs(rawJumps));
        jumpRMS = sqrt(mean(rawJumps.^2));
    end

    accepted = rawAccepted;
    info.WindowCount = numel(estimates);
    info.AcceptedWindows = nnz(accepted);
    info.HoldWindows = numel(estimates)-nnz(accepted);
    info.ExternalHoldMaskProvided = externalHoldProvided;
    info.ExternalHoldSamples = nnz(externalHoldMask);
    info.ExternalHoldFraction = mean(externalHoldMask);
    info.ExternalHoldRejectedWindows = nnz( ...
        externalHoldFraction > externalHoldMaxFraction);
    info.WindowSymbols = windowSymbols;
    info.HopSymbols = hopSymbols;
    info.CandidateFiniteRate = nnz(candidateFinite)/numel(candidateFinite);
    info.CandidateMin_Hz = candidateMin;
    info.CandidateMedian_Hz = candidateMedian;
    info.CandidateMax_Hz = candidateMax;
    info.CandidateRMS_Hz = candidateRMS;
    info.NonfiniteWindows = nonfiniteWindows;
    info.ConfidenceRejectedWindows = confidenceRejected;
    info.RangeRejectedWindows = rangeRejected;
    info.RawAcceptedRate = rawAcceptedRate;
    info.RawMin_Hz = rawMin;
    info.RawMedian_Hz = rawMedian;
    info.RawMax_Hz = rawMax;
    info.RawRMS_Hz = rawRMS;
    info.JumpMax_Hz = jumpMax;
    info.JumpRMS_Hz = jumpRMS;
    if any(accepted)
        info.MedianConfidence_dB = median(confidence(accepted));
    else
        return;
    end

    % Coast through fade windows using the nearest reliable estimate, then
    % reject isolated spectral-peak swaps with a short median smoother.
    if nnz(accepted) == 1
        estimates = repmat(estimates(accepted),numel(estimates),1);
    else
        estimates = interp1(centers(accepted),estimates(accepted),centers, ...
            'nearest','extrap');
    end
    smoothWindows = max(1,round(getfieldnumeric(opt, ...
        'gmskResidualMedianWindows',3)));
    if mod(smoothWindows,2) == 0
        smoothWindows = smoothWindows+1;
    end
    if smoothWindows > 1 && numel(estimates) > 1
        estimates = movmedian(estimates, ...
            min(smoothWindows,numel(estimates)),'Endpoints','shrink');
    end

    samplePositions = (1:numel(x)).';
    if numel(estimates) == 1
        frequencyTrace = repmat(estimates(1),numel(x),1);
    else
        frequencyTrace = interp1(centers,estimates,samplePositions, ...
            'linear',NaN);
        frequencyTrace(samplePositions < centers(1)) = estimates(1);
        frequencyTrace(samplePositions > centers(end)) = estimates(end);
    end
    frequencyTrace(~isfinite(frequencyTrace)) = 0;
    phaseCorrection = 2*pi/Fs*[0;cumsum(frequencyTrace(1:end-1))];
    if enabled
        y = x.*exp(-1j*phaseCorrection);
    end

    info.Applied = logical(enabled);
    info.ResidualMin_Hz = min(estimates);
    info.ResidualMedian_Hz = median(estimates);
    info.ResidualMax_Hz = max(estimates);
    info.ResidualRMS_Hz = sqrt(mean(estimates.^2));
    info.FinalResidual_Hz = estimates(end);
    info.PhaseCorrectionEnd_deg = rad2deg(phaseCorrection(end));
    if debugTracker
        maxPrint = max(0,round(getfieldnumeric(opt, ...
            'gmskResidualDebugMaxWindows',32)));
        debugIndices = localGMSKResidualDebugIndices( ...
            candidateEstimates,rawAccepted,maxPrint);
        take = numel(debugIndices);
        info.WindowDebug = struct( ...
            'WindowIndex',debugIndices(:), ...
            'CenterSample',centers(debugIndices), ...
            'CenterTime_s',(centers(debugIndices)-1)/Fs, ...
            'CandidateEstimate_Hz',candidateEstimates(debugIndices), ...
            'AcceptedEstimate_Hz',rawColumn(rawEstimates,rawAccepted,debugIndices), ...
            'Confidence_dB',confidence(debugIndices), ...
            'Accepted',rawAccepted(debugIndices));
        fprintf(['   [GMSK residual debug] correctionApplied=%d ', ...
            'finite/accepted=%.1f/%.1f%% ', ...
            'reject[nan/conf/range]=%d/%d/%d ', ...
            'rawHz[min/med/max/rms]=%+.1f/%+.1f/%+.1f/%.1f ', ...
            'jump[max/rms]=%.1f/%.1f Hz phaseEnd=%+.1f deg\n'], ...
            enabled,100*info.CandidateFiniteRate,100*rawAcceptedRate, ...
            nonfiniteWindows,confidenceRejected,rangeRejected, ...
            rawMin,rawMedian,rawMax,rawRMS, ...
            jumpMax,jumpRMS,info.PhaseCorrectionEnd_deg);
        for dbgIndex = 1:take
            windowIndex = debugIndices(dbgIndex);
            fprintf(['      win=%03d center=%.0f candidate=%+.2f Hz ', ...
                'conf=%.1f dB accepted=%d\n'], ...
                windowIndex,centers(windowIndex),candidateEstimates(windowIndex), ...
                confidence(windowIndex),rawAccepted(windowIndex));
        end
    end
end

function [mask,provided] = localReceiverExternalHoldMask(opt,n)
    provided = isstruct(opt) && isfield(opt,'ExternalHoldMask') && ...
        ~isempty(opt.ExternalHoldMask);
    mask = false(n,1);
    if ~provided
        return;
    end
    raw = logical(opt.ExternalHoldMask(:));
    if numel(raw) ~= n
        error('run_ccsds_tm_evaluation:ExternalHoldMaskLength', ...
            'ExternalHoldMask has %d samples; expected %d.', ...
            numel(raw),n);
    end
    mask = raw;
end

function indices = localGMSKResidualDebugIndices(candidates, accepted, maxPrint)
% Select a compact mix of endpoints, uniformly spaced windows, largest
% estimates, largest jumps, and rejected windows. This exposes late-frame
% failures without dumping hundreds of ordinary windows.
    n = numel(candidates);
    if n == 0 || maxPrint <= 0
        indices = zeros(0,1);
        return;
    end
    maxPrint = min(n,maxPrint);
    edgeCount = min(4,n);
    edge = [1:edgeCount, max(1,n-edgeCount+1):n];
    uniformCount = min(max(4,ceil(maxPrint/4)),n);
    uniform = round(linspace(1,n,uniformCount));
    finiteScore = abs(candidates);
    finiteScore(~isfinite(finiteScore)) = -Inf;
    [~,largeOrder] = sort(finiteScore,'descend');
    large = largeOrder(1:min(ceil(maxPrint/4),n));
    jumps = abs(diff(candidates));
    jumps(~isfinite(jumps)) = -Inf;
    [~,jumpOrder] = sort(jumps,'descend');
    jumpTake = jumpOrder(1:min(ceil(maxPrint/4),numel(jumpOrder)));
    jumpNeighbors = [jumpTake(:); jumpTake(:)+1];
    rejected = find(~accepted);
    proposed = unique([edge(:); uniform(:); large(:); ...
        jumpNeighbors(:); rejected(:)],'stable');
    if numel(proposed) > maxPrint
        proposed = proposed(1:maxPrint);
    end
    indices = sort(proposed(:));
end

function out = rawColumn(smoothed, accepted, indices)
% Preserve the raw per-window estimates for optional diagnostics.  The
% production correction still uses the smoothed/interpolated trace.
    out = smoothed(indices);
    if numel(out) ~= numel(indices)
        out = nan(numel(indices),1);
    end
    if nargin >= 2 && ~isempty(accepted)
        out(~accepted(indices)) = NaN;
    end
end

function [cfoEst,confidenceDB] = localGMSKX2CFOEstimate( ...
        x,Fs,fSym,maxFFT)
    x = complex(x(:));
    cfoEst = NaN;
    confidenceDB = -Inf;
    if numel(x) < 64
        return;
    end
    Lfft = min(numel(x),max(64,round(maxFFT)));
    Nfft = 2^nextpow2(Lfft);
    spectrum = fftshift(fft(x(1:Lfft).^2.*hamming(Lfft),Nfft));
    powerSpectrum = abs(spectrum).^2;
    frequencyAxis = (-Nfft/2:Nfft/2-1).'*(Fs/Nfft);
    positiveIndices = find(frequencyAxis > 0.25*fSym & ...
        frequencyAxis < 1.00*fSym);
    negativeIndices = find(frequencyAxis < -0.25*fSym & ...
        frequencyAxis > -1.00*fSym);
    if isempty(positiveIndices) || isempty(negativeIndices)
        return;
    end
    [positivePower,positiveLocal] = max(powerSpectrum(positiveIndices));
    [negativePower,negativeLocal] = max(powerSpectrum(negativeIndices));
    positivePeakIndex = positiveIndices(positiveLocal);
    negativePeakIndex = negativeIndices(negativeLocal);
    binHz = Fs/Nfft;
    positivePeakHz = frequencyAxis(positivePeakIndex)+ ...
        localParabolicSpectrumPeakOffset( ...
        powerSpectrum,positivePeakIndex)*binHz;
    negativePeakHz = frequencyAxis(negativePeakIndex)+ ...
        localParabolicSpectrumPeakOffset( ...
        powerSpectrum,negativePeakIndex)*binHz;
    cfoEst = (positivePeakHz+negativePeakHz)/4;
    searchPower = powerSpectrum([positiveIndices;negativeIndices]);
    confidenceDB = 10*log10( ...
        sqrt(max(positivePower,eps)*max(negativePower,eps))/ ...
        (median(searchPower)+eps));
end

function info = localEmptyGMSKResidualTrackerInfo()
    info = struct( ...
        'Applied',false,'WindowCount',0,'AcceptedWindows',0, ...
        'HoldWindows',0,'WindowSymbols',NaN,'HopSymbols',NaN, ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSamples',0, ...
        'ExternalHoldFraction',0,'ExternalHoldRejectedWindows',0, ...
        'ResidualMin_Hz',NaN,'ResidualMedian_Hz',NaN, ...
        'ResidualMax_Hz',NaN,'ResidualRMS_Hz',NaN, ...
        'FinalResidual_Hz',NaN,'MedianConfidence_dB',NaN, ...
        'RawAcceptedRate',0,'RawMin_Hz',NaN,'RawMedian_Hz',NaN, ...
        'RawMax_Hz',NaN,'RawRMS_Hz',NaN,'JumpMax_Hz',NaN, ...
        'JumpRMS_Hz',NaN,'PhaseCorrectionEnd_deg',NaN, ...
        'CandidateFiniteRate',0,'CandidateMin_Hz',NaN, ...
        'CandidateMedian_Hz',NaN,'CandidateMax_Hz',NaN, ...
        'CandidateRMS_Hz',NaN,'NonfiniteWindows',0, ...
        'ConfidenceRejectedWindows',0,'RangeRejectedWindows',0, ...
        'WindowDebug',struct());
end

function info = localEmptyGMSKSecondOrderPLLInfo()
    info = struct( ...
        'Applied',false,'Reason','disabled','SamplesPerSymbol',NaN, ...
        'AcquireLoopBandwidth',NaN,'TrackLoopBandwidth',NaN, ...
        'DetectorTauSymbols',NaN,'Locked',false, ...
        'FinalMode','off','LockTransitions',0,'Reacquisitions',0, ...
        'AcceptedUpdates',0,'FadeHoldSamples',0, ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSamples',0, ...
        'ExternalHoldFraction',0, ...
        'UpdateAcceptanceRate',NaN,'FinalFrequency_Hz',NaN, ...
        'FrequencyMin_Hz',NaN,'FrequencyMax_Hz',NaN, ...
        'FinalPhase_deg',NaN,'MeanAbsPhaseError',NaN, ...
        'RMSPhaseError',NaN);
end

function softMetric = localCanonicalGMSKSoftMetric(softMetric)
%LOCALCANONICALGMSKSOFTMETRIC Canonical detector/FEC boundary convention.
% The official production detector produces positive=bit0 and
% negative=bit1. Centralizing normalization here prevents FEC adapters from
% inventing detector-dependent polarity workarounds.
    softMetric = double(real(softMetric(:)));
    softMetric(~isfinite(softMetric)) = 0;
    scale = median(abs(softMetric(softMetric ~= 0)));
    if isfinite(scale) && scale > eps
        softMetric = 5*softMetric/scale;
    end
    softMetric = max(min(softMetric,20),-20);
end

function [symbols, bestPhase, bestScore, phaseScores] = ...
        localMSKFixedRateTiming(x, sps)

    x = x(:);
    sps = max(1, round(double(sps)));

    phaseScores = -inf(sps, 1);

    for phase = 1:sps
        candidate = x(phase:sps:end);

        if numel(candidate) < 3
            continue;
        end

        previous = candidate(1:end-1);
        current  = candidate(2:end);

        phaseDifference = angle(current .* conj(previous));

        % 正确的 MSK 符号边界上，相邻符号相位差接近 ±pi/2，
        % 因而 abs(sin(phaseDifference)) 接近 1。
        phaseConfidence = abs(sin(phaseDifference));

        % 深衰落位置权重较低，避免低幅度噪声主导定时选择。
        amplitudeWeight = abs(current) .* abs(previous);

        valid = isfinite(phaseConfidence) & ...
                isfinite(amplitudeWeight);

        if any(valid)
            phaseScores(phase) = ...
                sum(amplitudeWeight(valid) .* phaseConfidence(valid)) / ...
                (sum(amplitudeWeight(valid)) + eps);
        end
    end

    [bestScore, bestPhase] = max(phaseScores);

    if ~isfinite(bestScore)
        bestPhase = 1;
        bestScore = NaN;
    end

    % 固定 1 symbol/output，不允许中途插入或删除符号。
    symbols = x(bestPhase:sps:end);
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
