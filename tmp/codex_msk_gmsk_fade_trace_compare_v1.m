%% MSK versus GMSK trace at the same ChannelData_7 deep fade
% Diagnostic only.  Runs one normalized-H, exactly noiseless case per
% modulation and keeps all comparison tables in the MATLAB workspace.
% No CSV/MAT/artifact file is written.

projectRoot = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(projectRoot,'src','python'));

p = struct();
p.channelCoding = 'convolutional';
p.ConvolutionalCodeRate = '1/2';
p.symbolRate = 10e6;
p.sps = 8;
p.snr = 100;
p.noiseMode = 'off';
p.noisePlacement = 'afterChannel';
p.cfo = 0;
p.phaseOffset = 0;
p.delay = 0;
p.RolloffFactor = 0.35;
p.WaveformMode = 'ordinaryTM';
p.NumBytesInTransferFrame = 1115;
p.hasASM = true;
p.RandomizerEnabled = false;
p.RandomizerFECPosition = 'afterEncoding';
p.DataPathMode = 'single';
p.TMDataSource = 'random';
p.PCMFormat = 'NRZ-L';
p.berWarmUpFrames = 8;
p.berFrames = 60;
p.excludeBERWarmUpFrames = true;

p.enableHChannel = true;
p.HMode = 'h_matrix_file';
p.channelFilePath = ...
    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat';
p.channelInterpolationMethod = 'linear';
p.channelOutOfRangeMode = 'wrap';
p.interpolateChannelDelays = false;
p.normalizeHChannel = true;
p.enableKnownHPreEqualizer = false;
p.enableEqualizer = true;
p.equalizerMode = 'blind-cma-lms';
p.normalizeEqualizerOutput = true;
p.enableConverterChain = false;
p.enableADCEquivalent = false;
p.inputLevelDbm = -10;
p.AGCEnabled = false;

p.showFigures = false;
p.showPipelineFigure = false;
p.showDamageBudgetFigure = false;
p.showPowerFigure = false;
p.debugHFrameStats = false;
p.debugPerFrameBERSummary = false;
p.debugCPMFadeTrace = true;
p.debugCPMFadeTimeWindow_s = [0.094 0.098];
p.debugCPMFadeStep_s = 0.2e-6;

% MSK: use exactly the production oversampled differential-metric path.
pMSK = p;
pMSK.modType = 'MSK';
pMSK.enableCPMCoarseFrequencyCompensator = true;
rng(364232726,'twister');
mskLog = evalc('[MSKFadeResult,~] = run_ccsds_tm_evaluation(pMSK);'); %#ok<NASGU>

% GMSK: use the current production PLL and official Viterbi/frame-reset path.
pGMSK = p;
pGMSK.modType = 'GMSK';
pGMSK.BandwidthTimeProduct = 0.5;
pGMSK.GMSKDetectionMode = 'official-viterbi-frame-reset';
pGMSK.enableGMSKCoarseFrequencyCompensator = true;
pGMSK.enableGMSKSecondOrderPLL = true;
pGMSK.enableGMSKNoiselessContinuousTracking = true;
rng(364232726,'twister');
gmskLog = evalc('[GMSKFadeResult,~] = run_ccsds_tm_evaluation(pGMSK);'); %#ok<NASGU>

assert(MSKFadeResult.success && GMSKFadeResult.success, ...
    'One of the two receiver runs failed. Inspect mskLog and gmskLog.');
assert(isfield(MSKFadeResult,'CPMFadeTrace') && ...
    isfield(GMSKFadeResult,'CPMFadeTrace'), ...
    'CPMFadeTrace was not returned by the receiver.');

m = MSKFadeResult.CPMFadeTrace;
g = GMSKFadeResult.CPMFadeTrace;
sameFs = abs(MSKFadeResult.Fs-GMSKFadeResult.Fs) < 1e-9;
sameDuration = abs(MSKFadeResult.ActualWaveformDuration_s - ...
    GMSKFadeResult.ActualWaveformDuration_s) <= 1/max(MSKFadeResult.Fs,1);
sameGrid = numel(m.Time_s) == numel(g.Time_s) && ...
    all(abs(m.Time_s-g.Time_s) <= 0.5/max(MSKFadeResult.Fs,1));
if ~sameGrid
    error('MSK/GMSK diagnostic time grids differ; comparison is invalid.');
end

hPhaseMismatch = max(abs(rad2deg(angle(exp(1j*deg2rad( ...
    m.HPhaseWrapped_deg-g.HPhaseWrapped_deg))))));

CPMFadeCompareFull = table( ...
    1e3*m.Time_s, ...
    m.HAbs_dBRelative, ...
    m.HPhaseWrapped_deg, ...
    m.HPhaseChange_deg, ...
    m.RxAbs_dBRelative, ...
    m.RxPhaseWrapped_deg, ...
    m.MSKDifferentialMetric, ...
    m.MSKDifferentialMetricAbs, ...
    g.RxAbs_dBRelative, ...
    g.RxPhaseWrapped_deg, ...
    g.GMSKPLLAppliedCorrectionChange_deg, ...
    g.GMSKPLLDetectorError_deg, ...
    g.GMSKPLLFrequency_Hz, ...
    'VariableNames',{ ...
    'Time_ms','HAbs_dB','HPhase_deg','HPhaseChange_deg', ...
    'MSKRxAbs_dB','MSKRxPhase_deg','MSKDiffMetric','MSKDiffAbs', ...
    'GMSKRxAbs_dB','GMSKRxPhase_deg','GMSKPLLCorrection_deg', ...
    'GMSKPLLDetectorError_deg','GMSKPLLFrequency_Hz'});

dt = median(diff(m.Time_s));
coarseStride = max(1,round(50e-6/max(dt,eps)));
coarseIndex = unique([1:coarseStride:height(CPMFadeCompareFull), ...
    height(CPMFadeCompareFull)]);
CPMFadeCompareCoarse = CPMFadeCompareFull(coarseIndex,:);

[~,fadeMinimumIndex] = min(CPMFadeCompareFull.HAbs_dB);
fadeMinimumTime_s = CPMFadeCompareFull.Time_ms(fadeMinimumIndex)*1e-3;
fineMask = abs(m.Time_s-fadeMinimumTime_s) <= 20e-6;
fineAllIndex = find(fineMask);
finePrintStride = max(1,round(0.5e-6/max(dt,eps)));
finePrintIndex = unique([fineAllIndex(1:finePrintStride:end); ...
    fadeMinimumIndex;fineAllIndex(end)]);
CPMFadeCompareFineFull = CPMFadeCompareFull(fineAllIndex,:);
CPMFadeCompareFine = CPMFadeCompareFull(finePrintIndex,:);

eventMSKMetric = CPMFadeCompareFull.MSKDiffAbs(fineMask);
eventGMSKCorrection = ...
    CPMFadeCompareFull.GMSKPLLCorrection_deg(fineMask);
eventGMSKError = ...
    CPMFadeCompareFull.GMSKPLLDetectorError_deg(fineMask);
eventGMSKFrequency = ...
    CPMFadeCompareFull.GMSKPLLFrequency_Hz(fineMask);
eventGMSKCorrection = eventGMSKCorrection(isfinite(eventGMSKCorrection));
eventGMSKError = eventGMSKError(isfinite(eventGMSKError));
eventGMSKFrequency = eventGMSKFrequency(isfinite(eventGMSKFrequency));

fprintf('\n============ MSK / GMSK SAME-FADE TRACE ============\n');
fprintf(['MSK : BER=%g FER=%g duration=%.9f s Fs=%.9g Hz\n'], ...
    MSKFadeResult.BER,MSKFadeResult.FER, ...
    MSKFadeResult.ActualWaveformDuration_s,MSKFadeResult.Fs);
fprintf(['GMSK: BER=%g FER=%g duration=%.9f s Fs=%.9g Hz\n'], ...
    GMSKFadeResult.BER,GMSKFadeResult.FER, ...
    GMSKFadeResult.ActualWaveformDuration_s,GMSKFadeResult.Fs);
fprintf(['Comparable: sameFs=%d sameDuration=%d sameTimeGrid=%d ', ...
    'H-phase mismatch=%.3g deg\n'], ...
    sameFs,sameDuration,sameGrid,hPhaseMismatch);
fprintf('Deepest sampled H in trace: t=%.9f s, %.3f dB relative\n', ...
    fadeMinimumTime_s,CPMFadeCompareFull.HAbs_dB(fadeMinimumIndex));
fprintf(['At deepest H: |MSK differential metric|=%.6g; ', ...
    'GMSK correction change=%+.3f deg; detector error=%+.3f deg\n'], ...
    CPMFadeCompareFull.MSKDiffAbs(fadeMinimumIndex), ...
    CPMFadeCompareFull.GMSKPLLCorrection_deg(fadeMinimumIndex), ...
    CPMFadeCompareFull.GMSKPLLDetectorError_deg(fadeMinimumIndex));
fprintf(['Deepest +/-20 us: GMSK correction swing=%.3f deg, ', ...
    'max|detector error|=%.3f deg, frequency=[%+.1f,%+.1f] Hz\n'], ...
    max(eventGMSKCorrection)-min(eventGMSKCorrection), ...
    max(abs(eventGMSKError)),min(eventGMSKFrequency), ...
    max(eventGMSKFrequency));
fprintf(['GMSK PLL transient samples/intervals: %d/%d\n'], ...
    GMSKFadeResult.GMSKSecondOrderPLLPhaseTransientSamples, ...
    size(GMSKFadeResult. ...
    GMSKSecondOrderPLLPhaseTransientIntervalsSamples,1));

fprintf('\n--- Whole 0.094-0.098 s window, one row per 50 us ---\n');
disp(CPMFadeCompareCoarse);
fprintf('\n--- Deepest H +/-20 us, printed about every 0.5 us ---\n');
disp(CPMFadeCompareFine);
fprintf(['\nFull %.3f us trace remains in CPMFadeCompareFull; ', ...
    'the unthinned event is CPMFadeCompareFineFull; ', ...
    'receiver logs remain in mskLog/gmskLog. No file was written.\n'], ...
    1e6*dt);
