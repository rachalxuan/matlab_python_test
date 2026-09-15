%% New-channel PSD-noise synchronization sweep (one MAT file per run)
% Each MAT file in ChannelDir is treated as an independent channel case.
% The files are NOT concatenated: CDL/TDL/ITU and antenna variants are
% alternative channel configurations, not consecutive time snapshots.
%
% Optional caller workspace variable:
%   NewChannelPSDSweepOptions = struct(...)
%
% Useful fields:
%   ChannelDir, FilePattern, StartFile, MaxFiles, ListOnly
%   ModType, ChannelCoding, SymbolRate, SamplesPerSymbol
%   BERWarmUpFrames, BERFrames
%   NoiseMode, NoisePSDdBmHz, InputLevelDbm, NoiseBandwidthHz
%   NormalizeHChannel, ChannelSampleRateHz
%   ReceiverOverrides, VerboseReceiverLog, SaveCSV, CSVPath

if exist('NewChannelPSDSweepOptions','var') && ...
        isstruct(NewChannelPSDSweepOptions)
    userOptions = NewChannelPSDSweepOptions;
else
    userOptions = struct();
end

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(scriptDir);
addpath(fullfile(repoRoot,'src','python'));

cfg = localDefaults();
cfg = localMerge(cfg,userOptions);
cfg.ChannelDir = char(string(cfg.ChannelDir));
cfg.FilePattern = char(string(cfg.FilePattern));

if ~isfolder(cfg.ChannelDir)
    error('codex_new_channel_psd_sync_sweep:MissingDirectory', ...
        'Channel directory does not exist: %s',cfg.ChannelDir);
end

files = dir(fullfile(cfg.ChannelDir,cfg.FilePattern));
files = files(~[files.isdir]);
if isempty(files)
    error('codex_new_channel_psd_sync_sweep:NoMATFiles', ...
        'No files matched %s in %s.',cfg.FilePattern,cfg.ChannelDir);
end
[~,order] = sort(lower(string({files.name})));
files = files(order);

catalog = localBuildCatalog(files);
fprintf('\n================ NEW CHANNEL MAT CATALOG ================\n');
disp(catalog);
if logical(cfg.ListOnly)
    NewChannelPSDSweepCatalog = catalog;
    NewChannelPSDSweepResults = table();
    NewChannelPSDSweepLogs = cell(0,1);
    NewChannelPSDSweepTimelines = cell(0,1);
    fprintf('ListOnly=true: no receiver simulation was run.\n');
    return;
end

nFiles = numel(files);
startFile = max(1,round(double(cfg.StartFile)));
if startFile > nFiles
    error('codex_new_channel_psd_sync_sweep:StartFileOutOfRange', ...
        'StartFile=%d exceeds the %d discovered MAT files.',startFile,nFiles);
end
maxFiles = double(cfg.MaxFiles);
if ~isscalar(maxFiles) || isnan(maxFiles) || maxFiles <= 0
    error('codex_new_channel_psd_sync_sweep:InvalidMaxFiles', ...
        'MaxFiles must be a positive scalar or Inf.');
end
if isinf(maxFiles)
    stopFile = nFiles;
else
    stopFile = min(nFiles,startFile+floor(maxFiles)-1);
end
selected = startFile:stopFile;

if isempty(cfg.NoiseBandwidthHz)
    nominalNoiseBandwidthHz = ...
        (1+double(cfg.RolloffFactor))*double(cfg.SymbolRate);
else
    nominalNoiseBandwidthHz = double(cfg.NoiseBandwidthHz);
end
nominalNoisePowerDBm = double(cfg.NoisePSDdBmHz) + ...
    10*log10(nominalNoiseBandwidthHz);
nominalPreHMarginDB = double(cfg.InputLevelDbm)-nominalNoisePowerDBm;

fprintf('\n================ NEW CHANNEL PSD SYNC SWEEP ================\n');
fprintf('Files selected : %d:%d of %d\n',startFile,stopFile,nFiles);
fprintf('Receiver       : %s + %s, %g Msym/s, %d sps\n', ...
    char(string(cfg.ModType)),char(string(cfg.ChannelCoding)), ...
    double(cfg.SymbolRate)/1e6,round(double(cfg.SamplesPerSymbol)));
fprintf('H handling     : one file/run, normalize=%d, H Fs=%g kHz\n', ...
    logical(cfg.NormalizeHChannel),double(cfg.ChannelSampleRateHz)/1e3);
if lower(string(cfg.NoiseMode)) == "psd"
    fprintf('Noise          : PSD=%+.3f dBm/Hz, BW=%g MHz, Pn=%+.3f dBm\n', ...
        double(cfg.NoisePSDdBmHz),nominalNoiseBandwidthHz/1e6, ...
        nominalNoisePowerDBm);
    fprintf('Level reference: input=%+.3f dBm, nominal pre-H C/N=%+.3f dB\n', ...
        double(cfg.InputLevelDbm),nominalPreHMarginDB);
    fprintf(['Important      : p.snr is not the PSD-mode SNR control; ', ...
        'the level, PSD and bandwidth above determine it.\n']);
else
    fprintf('Noise          : %s (noiseless control; PSD fields are ignored)\n', ...
        upper(char(string(cfg.NoiseMode))));
end
fprintf(['Verdict        : short synchronization screen only. ', ...
    'It does not demonstrate BER < 1e-6.\n\n']);

rows = repmat(localEmptyRow(),numel(selected),1);
logs = cell(numel(selected),1);
% Retain each selected case's timeline; do not keep full waveforms.
NewChannelPSDSweepTimelines = cell(numel(selected),1);

for k = 1:numel(selected)
    fileIndex = selected(k);
    filePath = fullfile(files(fileIndex).folder,files(fileIndex).name);
    row = localEmptyRow();
    row.FileIndex = fileIndex;
    row.Family = catalog.Family(fileIndex);
    row.Profile = catalog.Profile(fileIndex);
    row.FileName = string(files(fileIndex).name);

    p = localBaseReceiver(cfg,filePath);
    p = localMerge(p,cfg.ReceiverOverrides);
    fprintf('[%02d/%02d] %-4s | %s ...\n', ...
        fileIndex,nFiles,char(row.Family),char(row.FileName));
    NewChannelPSDSweepTimelines{k} = struct('Available',false, ...
        'Reason','receiver did not return a timeline', ...
        'Mode','offline-simulation-timeline');
    runTimer = tic;
    try
        rng(double(cfg.Seed),'twister');
        result = struct();
        logs{k} = evalc('[result,~] = run_ccsds_tm_evaluation(p);');
        if isfield(result,'ReceiverTimeline')
            NewChannelPSDSweepTimelines{k} = result.ReceiverTimeline;
        end
        row.Elapsed_s = toc(runTimer);
        row.Success = localLogical(result,'success',false);
        if ~row.Success
            row.Verdict = "RUN_ERROR";
            row.ErrorIdentifier = localString(result,'errorIdentifier',"");
            row.ErrorMessage = localString(result,'errorMsg', ...
                localString(result,'error',"receiver returned success=false"));
        else
            row = localFillResult(row,result,cfg);
        end
    catch ME
        row.Elapsed_s = toc(runTimer);
        row.Success = false;
        row.Verdict = "RUN_ERROR";
        row.ErrorIdentifier = string(ME.identifier);
        row.ErrorMessage = string(ME.message);
        logs{k} = getReport(ME,'extended','hyperlinks','off');
    end
    rows(k) = row;

    fprintf(['  %s | BER=%g FER=%g EqSNR=%+.2f dB | ', ...
        'C/T/F lock=%s/%s/%s | losses=%g/%g/%g | %.2fs\n'], ...
        char(row.Verdict),row.BER,row.FER,row.EquivalentSNR_dB, ...
        localPctText(row.CarrierAvailable,row.CarrierLock_pct), ...
        localPctText(row.TimingAvailable,row.TimingLock_pct), ...
        localPctText(row.FrameAvailable,row.FrameLock_pct), ...
        row.CarrierLosses,row.TimingLosses,row.FrameLosses,row.Elapsed_s);
    if row.Verdict == "RUN_ERROR"
        fprintf(2,'  %s: %s\n',char(row.ErrorIdentifier),char(row.ErrorMessage));
    end
    if logical(cfg.VerboseReceiverLog)
        fprintf('%s',logs{k});
    end
end

NewChannelPSDSweepResults = struct2table(rows,'AsArray',true);
NewChannelPSDSweepLogs = logs;
NewChannelPSDSweepCatalog = catalog;
fprintf('Per-case offline timelines: NewChannelPSDSweepTimelines (same row order as results).\n');

fprintf('\n================ PSD SYNC SWEEP SUMMARY ================\n');
summaryGroups = groupsummary(NewChannelPSDSweepResults,'Verdict');
disp(summaryGroups(:,{'Verdict','GroupCount'}));
disp(NewChannelPSDSweepResults(:,{ ...
    'FileIndex','Family','Profile','BER','FER','EquivalentSNR_dB', ...
    'CoarseCFOEstimate_Hz','PSKCoarseCFOAttempted', ...
    'PSKCoarseCFOAccepted','PSKCoarseCFOConsistentWindows', ...
    'PSKCoarseCFOWindowCount','PSKCoarseCFOReason', ...
    'PostFSECFOAccepted','PostFSECFOEstimate_Hz','TotalCFOCorrection_Hz', ...
    'EqualizerSamplingMode','EqualizerModeActual','EqualizerTaps', ...
    'EqualizerApplied','EqualizerOutputAccepted','FSEErrorMSE', ...
    'FSEDualApplied','FSEDualSwitchApplied','FSEDualSwitchSymbol', ...
    'FSEDualCMAConfidence_pct','FSEDualCMAPhaseCoherence', ...
    'FSEDualAcceptance_pct','FSEDualDDMSE', ...
    'FSEDualCarrierMeanAbsError_deg', ...
    'PredecoderSteadyBER','PredecoderFrameBERP95', ...
    'PredecoderFrameBERMax','PredecoderASMAligned', ...
    'FSEPostMode','FSEPostApplied','FSEPostAccepted', ...
    'FSEPostForwardTaps','FSEPostFeedbackTaps', ...
    'FSEPostAcceptance_pct','FSEPostDDMSE','FSEPostQualityImprovement', ...
    'CarrierLock_pct','TimingLock_pct','FrameLock_pct', ...
    'CarrierLosses','TimingLosses','FrameLosses','FrameReacquisitions', ...
    'HDelaySpreadSymbols','HFSESpanSymbols','HFSESpanMarginSymbols', ...
    'HFrequencyMin_dB','HFrequencyP01_dB', ...
    'HPathPowerMode','HDynamicRange_dB','HDeepFadeBelow20_pct', ...
    'MeasurementComparedFrames','MeasurementExpectedFrames', ...
    'MeasurementCoverage_pct','UnrecoveredMeasurementFrames', ...
    'RecoveredNotComparedFrames','MeasurementCoverageStatus','Verdict'}));

if logical(cfg.SaveCSV)
    csvPath = char(string(cfg.CSVPath));
    if isempty(strtrim(csvPath))
        csvPath = fullfile(scriptDir,'new_channel_psd_sync_sweep.csv');
    end
    writetable(NewChannelPSDSweepResults,csvPath);
    fprintf('CSV written: %s\n',csvPath);
else
    fprintf(['No files were written; results are in ', ...
        'NewChannelPSDSweepResults and logs in ', ...
        'NewChannelPSDSweepLogs.\n']);
end

function cfg = localDefaults()
cfg = struct();
cfg.ChannelDir = [ ...
    'C:\Users\admin\xwechat_files\wxid_95czmz1vt20422_de63\msg\file\', ...
    '2026-09\mat文件\mat文件'];
cfg.FilePattern = '*.mat';
cfg.StartFile = 1;
cfg.MaxFiles = inf;
cfg.ListOnly = false;
cfg.ModType = 'QPSK';
cfg.ChannelCoding = 'none';
cfg.SymbolRate = 1e6;
cfg.SamplesPerSymbol = 8;
cfg.RolloffFactor = 0.35;
cfg.NumBytesInTransferFrame = 1115;
cfg.BERWarmUpFrames = 8;
cfg.BERFrames = 32;
cfg.NoiseMode = 'psd';
cfg.NoisePSDdBmHz = -115.3;
cfg.NoiseBandwidthHz = [];
cfg.InputLevelDbm = -10;
cfg.NormalizeHChannel = true;
cfg.ChannelSampleRateHz = 1e5;
cfg.ChannelInterpolationMethod = 'linear';
cfg.ChannelOutOfRangeMode = 'hold';
cfg.InterpolateChannelDelays = true;
cfg.Seed = 364232726;
cfg.ReceiverOverrides = struct();
cfg.VerboseReceiverLog = false;
cfg.SaveCSV = false;
cfg.CSVPath = '';
end

function p = localBaseReceiver(cfg,filePath)
p = struct();
p.modType = char(string(cfg.ModType));
p.channelCoding = char(string(cfg.ChannelCoding));
p.symbolRate = double(cfg.SymbolRate);
p.sps = round(double(cfg.SamplesPerSymbol));
% Retained for compatibility and display.  PSD mode does not use this as
% the noise control; NoisePSDdBmHz + bandwidth + level define C/N.
p.snr = 100;
p.noiseMode = char(string(cfg.NoiseMode));
p.noisePSDdBmHz = double(cfg.NoisePSDdBmHz);
if ~isempty(cfg.NoiseBandwidthHz)
    p.noiseBandwidthHz = double(cfg.NoiseBandwidthHz);
end
p.noisePlacement = 'afterChannel';
p.signalReferenceLevelDbm = double(cfg.InputLevelDbm);
p.inputLevelDbm = double(cfg.InputLevelDbm);
p.cfo = 0;
p.phaseOffset = 0;
p.delay = 0;
p.RolloffFactor = double(cfg.RolloffFactor);

p.WaveformMode = 'ordinaryTM';
p.NumBytesInTransferFrame = round(double(cfg.NumBytesInTransferFrame));
p.hasASM = true;
p.RandomizerEnabled = false;
p.RandomizerFECPosition = 'afterEncoding';
p.DataPathMode = 'single';
p.TMDataSource = 'random';
p.PCMFormat = 'NRZ-L';
p.berWarmUpFrames = round(double(cfg.BERWarmUpFrames));
p.berFrames = round(double(cfg.BERFrames));
p.excludeBERWarmUpFrames = true;

p.enableHChannel = true;
p.HMode = 'h_matrix_file';
p.channelFilePath = filePath;
p.channelSampleRateHz = double(cfg.ChannelSampleRateHz);
p.channelInterpolationMethod = char(string(cfg.ChannelInterpolationMethod));
p.channelOutOfRangeMode = char(string(cfg.ChannelOutOfRangeMode));
p.interpolateChannelDelays = logical(cfg.InterpolateChannelDelays);
p.normalizeHChannel = logical(cfg.NormalizeHChannel);

% Receiver-observable adaptive path; oracle/known-H compensation is off.
p.enableEqualizer = true;
p.equalizerMode = 'blind-cma-lms';
p.normalizeEqualizerOutput = true;
p.enableKnownHPreEqualizer = false;
p.enableQAMBlindPhaseSearch = true;
p.enableQAMPowerGainTracker = true;
p.enableQAMPostBPSAdaptiveEqualizer = false;
p.enableASMFramePhaseCorrection = true;
p.enableBlindReliabilityManager = false;
p.timingLoopBandwidth = 0.01;

p.enableConverterChain = false;
p.enableADCEquivalent = false;
p.AGCEnabled = false;

% Diagnostic-only time-indexed lock detectors; these do not alter samples.
p.enableRuntimeLockTelemetry = true;
p.runtimeStatusUpdateMs = 200;
p.debugRuntimeLockTelemetry = false;

p.showFigures = false;
p.showPipelineFigure = false;
p.showDamageBudgetFigure = false;
p.showPowerFigure = false;
p.debugAdaptiveEqualizer = false;
p.debugHFrameStats = false;
p.debugPerFrameBERSummary = false;
end

function catalog = localBuildCatalog(files)
n = numel(files);
fileIndex = (1:n).';
family = strings(n,1);
profile = strings(n,1);
fileName = strings(n,1);
for k = 1:n
    name = string(files(k).name);
    fileName(k) = name;
    if startsWith(name,"3GPPNTN-CDL_")
        family(k) = "CDL";
        token = regexp(char(name), ...
            '^3GPPNTN-CDL_([^_]+_[^_]+)_AntennaGain_\d+\.mat$', ...
            'tokens','once');
    elseif startsWith(name,"3GPPNTN-TDL_")
        family(k) = "TDL";
        token = regexp(char(name), ...
            '^3GPPNTN-TDL_([^_]+_[^_]+)_AntennaGain_\d+\.mat$', ...
            'tokens','once');
    elseif startsWith(name,"ITU-")
        family(k) = "ITU";
        token = regexp(char(name), ...
            '^ITU-([^_]+)_AntennaGain_\d+\.mat$','tokens','once');
    else
        family(k) = "OTHER";
        token = {};
    end
    if isempty(token)
        profile(k) = erase(name,'.mat');
    else
        profile(k) = string(token{1});
    end
end
catalog = table(fileIndex,family,profile,fileName, ...
    'VariableNames',{'FileIndex','Family','Profile','FileName'});
end

function row = localFillResult(row,result,cfg)
row.BER = localNumber(result,'BER',NaN);
row.FER = localNumber(result,'FER',NaN);
row.CountedFrames = localNumber(result,'CountedFrames',NaN);
row.FrameErrors = localNumber(result,'FrameErrors',NaN);
coverage = localStruct(result,'MeasurementCoverage');
row.MeasurementCoverageStatus = localString(coverage,'Status',"UNAVAILABLE");
row.MeasurementExpectedFrames = localNumber(coverage,'ExpectedFrames',NaN);
row.MeasurementComparedFrames = localNumber(coverage,'ComparedFrames',NaN);
row.MeasurementCoverage_pct = 100*localNumber(coverage,'Fraction',NaN);
row.UnrecoveredMeasurementFrames = localNumber(coverage,'UnrecoveredFrames',NaN);
row.RecoveredNotComparedFrames = localNumber(coverage,'RecoveredNotComparedFrames',NaN);
row.MeasurementDuration_s = localNumber(result,'MeasurementDuration_s',NaN);
row.LegacyFrameMatch_pct = 100*localNumber(result,'LockRate',NaN);
row.CoarseCFOEstimate_Hz = localNumber(result,'cfo_est_Hz',NaN);
row.PSKCoarseCFOApplied = localLogical( ...
    result,'PSKCoarseFrequencyCompensatorApplied',false);
row.PSKCoarseCFOAttempted = localLogical( ...
    result,'PSKCoarseFrequencyCompensatorAttempted',false);
row.PSKCoarseCFOAccepted = localLogical( ...
    result,'PSKCoarseFrequencyCompensatorAccepted',false);
row.PSKCoarseCFOConsistentWindows = localNumber( ...
    result,'PSKCoarseFrequencyConsistentSegments',NaN);
row.PSKCoarseCFOWindowCount = localNumber( ...
    result,'PSKCoarseFrequencySegmentCount',NaN);
row.PSKCoarseCFOReason = localString( ...
    result,'PSKCoarseFrequencyCompensatorReason',"");
row.PostFSECFOAttempted = localLogical(result,'PSKPostFSEFrequencyAttempted',false);
row.PostFSECFOAccepted = localLogical(result,'PSKPostFSEFrequencyAccepted',false);
row.PostFSECFOEstimate_Hz = localNumber(result,'PSKPostFSEFrequencyEstimate_Hz',0);
row.PostFSECFOReason = localString(result,'PSKPostFSEFrequencyReason',"");
row.TotalCFOCorrection_Hz = localNumber(result,'PSKTotalFrequencyCorrection_Hz',NaN);
row.NoisePower_dBm = localNumber(result,'NoisePower_dBm',NaN);
row.EquivalentSNR_dB = localNumber(result,'NoiseEquivalentSNR_dB',NaN);
row.EqualizerSamplingMode = localString( ...
    result,'AdaptiveEqualizerSamplingMode',"");
row.EqualizerModeActual = localString(result,'AdaptiveEqualizerMode',"");
row.EqualizerTaps = localNumber(result,'AdaptiveEqualizerTaps',NaN);
row.EqualizerApplied = localLogical(result,'AdaptiveEqualizerEnabled',false);
row.EqualizerOutputAccepted = localLogical( ...
    result,'AdaptiveEqualizerOutputAccepted',false);
row.FSEErrorMSE = localNumber( ...
    result,'AdaptiveFractionalEqualizerErrorMSE',NaN);
row.FSEDualApplied = localLogical( ...
    result,'AdaptiveFractionalDualModeApplied',false);
row.FSEDualSwitchApplied = localLogical( ...
    result,'AdaptiveFractionalDualSwitchApplied',false);
row.FSEDualSwitchSymbol = localNumber( ...
    result,'AdaptiveFractionalDualSwitchSymbol',NaN);
row.FSEDualCMAConfidence_pct = 100*localNumber( ...
    result,'AdaptiveFractionalDualCMAConfidenceRate',NaN);
row.FSEDualCMAPhaseCoherence = localNumber( ...
    result,'AdaptiveFractionalDualCMAPhaseCoherence',NaN);
row.FSEDualAcceptance_pct = 100*localNumber( ...
    result,'AdaptiveFractionalDualAcceptanceRate',NaN);
row.FSEDualDDMSE = localNumber( ...
    result,'AdaptiveFractionalDualDDMSE',NaN);
row.FSEDualCarrierMeanAbsError_deg = localNumber( ...
    result,'AdaptiveFractionalDualCarrierMeanAbsError_deg',NaN);
row.FSEDualCarrierFrequency_Hz = localNumber( ...
    result,'AdaptiveFractionalDualCarrierFrequency_Hz',NaN);
row.FSEDualReason = localString(result,'AdaptiveFractionalDualReason',"");
row.PredecoderBER = localNumber(result,'PredecoderBER',NaN);
row.PredecoderSteadyBER = localNumber( ...
    result,'PredecoderSteadyBER',NaN);
row.PredecoderFrameBERP95 = localNumber( ...
    result,'PredecoderFrameBERP95',NaN);
row.PredecoderFrameBERMax = localNumber( ...
    result,'PredecoderFrameBERMax',NaN);
row.PredecoderWorstFrameIndex = localNumber( ...
    result,'PredecoderWorstFrameIndex',NaN);
row.PredecoderWorstFrameBitErrors = localNumber( ...
    result,'PredecoderWorstFrameBitErrors',NaN);
row.PredecoderCodedBitsPerFrame = localNumber( ...
    result,'PredecoderCodedBitsPerFrame',NaN);
row.PredecoderNonzeroErrorFrames = localNumber( ...
    result,'PredecoderNonzeroErrorFrames',NaN);
row.PredecoderWorstFrameTPCMaxCodewordErrors = localNumber( ...
    result,'PredecoderWorstFrameTPCMaxCodewordErrors',NaN);
row.PredecoderWorstFrameTPCNonzeroCodewords = localNumber( ...
    result,'PredecoderWorstFrameTPCNonzeroCodewords',NaN);
row.PredecoderTxFrameOffset = localNumber( ...
    result,'PredecoderTxFrameOffset',NaN);
row.PredecoderASMAligned = localNumber( ...
    result,'PredecoderASMAligned',NaN);
row.FSEPostMode = localString(result,'AdaptiveFractionalPostMode',"off");
row.FSEPostApplied = localLogical( ...
    result,'AdaptiveFractionalPostApplied',false);
row.FSEPostAccepted = localLogical( ...
    result,'AdaptiveFractionalPostOutputAccepted',false);
row.FSEPostForwardTaps = localNumber( ...
    result,'AdaptiveFractionalPostForwardTaps',NaN);
row.FSEPostFeedbackTaps = localNumber( ...
    result,'AdaptiveFractionalPostFeedbackTaps',NaN);
row.FSEPostStep = localNumber(result,'AdaptiveFractionalPostStep',NaN);
row.FSEPostAcceptance_pct = 100*localNumber( ...
    result,'AdaptiveFractionalPostAcceptanceRate',NaN);
row.FSEPostDDMSE = localNumber( ...
    result,'AdaptiveFractionalPostDDMSE',NaN);
row.FSEPostQualityImprovement = localNumber( ...
    result,'AdaptiveFractionalPostQualityImprovement',NaN);
row.FSEPostConverged = localLogical( ...
    result,'AdaptiveFractionalPostConverged',false);
row.PSKPostFSEPhaseTrackerMode = localString( ...
    result,'PSKPostFSEPhaseTrackerMode',"not-applicable");
row.QPSKPostFSEPhaseTrackerMode = localString( ...
    result,'QPSKPostFSEPhaseTrackerMode',"not-applicable");
row.TPCDecoderMode = localString(result,'TPCDecoderMode',"iterative");
row.ASMFramePhaseCorrectionApplied = localLogical( ...
    result,'ASMFramePhaseCorrectionApplied',false);
row.ASMFramePhaseCorrectionReason = localString( ...
    result,'ASMFramePhaseCorrectionReason',"");
row.ASMFramePhaseCorrectionFrames = localNumber( ...
    result,'ASMFramePhaseCorrectionFrames',NaN);
row.ASMFramePhaseCorrectionReliableFrames = localNumber( ...
    result,'ASMFramePhaseCorrectionReliableFrames',NaN);
row.ASMFramePhaseCycleSlipsBefore = localNumber( ...
    result,'ASMFramePhaseCycleSlipsBefore',NaN);
row.ASMFramePhaseCycleSlipsAfter = localNumber( ...
    result,'ASMFramePhaseCycleSlipsAfter',NaN);

h = localStruct(result,'HChannelMeta');
row.HMeanGain_dB = localNumber(h,'MeanGain_dB',NaN);
row.HNormalizationGain_dB = localNumber(h,'NormalizationGain_dB',NaN);
row.HDynamicRange_dB = ...
    localNumber(h,'DominantMagnitudeDynamicRange_dB',NaN);
row.HDeepFadeBelow20_pct = 100*localNumber( ...
    h,'DominantDeepFadeFractionBelowMinus20dB',NaN);
row.HSourceSamples = localNumber(h,'ChannelSourceSamples',NaN);
row.HSourceDuration_s = localNumber(h,'ChannelSourceDuration_s',NaN);
row.WaveformDuration_s = localNumber(h,'WaveformDuration_s',NaN);
if ~isfinite(row.WaveformDuration_s)
    row.WaveformDuration_s = localNumber(result,'ActualWaveformDuration_s',NaN);
end
row.ExceedsHDuration = localLogical(h,'ExceedsChannelDuration',false);
row.HDelaySpreadSymbols = localNumber(h,'DelaySpreadSymbols',NaN);
row.HFSESpanSymbols = localNumber(h,'FSEConfiguredSpanSymbols',NaN);
row.HFSESpanMarginSymbols = localNumber(h,'FSESpanMarginSymbols',NaN);
row.HFSECoversDelaySpread = localLogical(h,'FSECoversDelaySpread',false);
row.HFrequencyMin_dB = localNumber(h,'FrequencyResponseMin_dB',NaN);
row.HFrequencyP01_dB = localNumber(h,'FrequencyResponseP01_dB',NaN);
row.HFrequencyP05_dB = localNumber(h,'FrequencyResponseP05_dB',NaN);
row.HPathPowerMode = localString(h,'PathPowerMode',"");

telemetry = localStruct(result,'RuntimeLockTelemetry');
[row.CarrierAvailable,row.CarrierLock_pct,row.CarrierLockedAtEnd, ...
    row.CarrierLosses,row.CarrierReacquisitions] = ...
    localTrack(localStruct(telemetry,'Carrier'));
[row.TimingAvailable,row.TimingLock_pct,row.TimingLockedAtEnd, ...
    row.TimingLosses,row.TimingReacquisitions] = ...
    localTrack(localStruct(telemetry,'Timing'));
[row.FrameAvailable,row.FrameLock_pct,row.FrameLockedAtEnd, ...
    row.FrameLosses,row.FrameReacquisitions] = ...
    localTrack(localStruct(telemetry,'Frame'));

bitsObserved = max(0,row.CountedFrames) * ...
    round(double(cfg.NumBytesInTransferFrame))*8;
if localLogical(coverage,'Available',false)
    bitsObserved=localNumber(coverage,'ComparedBits',bitsObserved);
end
row.BitsObservedApprox = bitsObserved;
if row.BER == 0 && bitsObserved > 0
    row.ZeroErrorUpper95 = -log(0.05)/bitsObserved;
end

usesFSE = contains(row.EqualizerSamplingMode,"2sps", ...
    'IgnoreCase',true) && row.EqualizerApplied;
if usesFSE && isfinite(row.HFSESpanMarginSymbols) && ...
        row.HFSESpanMarginSymbols < 0 && ~(row.BER == 0 && row.FER == 0)
    row.Verdict = "EQUALIZER_SPAN_INSUFFICIENT";
elseif usesFSE && ~row.FSEDualSwitchApplied && isfinite(row.FSEErrorMSE) && ...
        row.FSEErrorMSE > 0.1 && ~(row.BER == 0 && row.FER == 0)
    % FSEErrorMSE covers only the CMA prefix in dual mode. It must not label
    % an active DD stage as failed solely because the acquisition cost was high.
    row.Verdict = "EQUALIZER_ACQUISITION_FAILED";
elseif ~row.FrameAvailable
    row.Verdict = "TELEMETRY_MISSING";
elseif ~row.FrameLockedAtEnd
    row.Verdict = "FRAME_UNLOCKED_AT_END";
elseif (row.CarrierAvailable && ~row.CarrierLockedAtEnd) || ...
        (row.TimingAvailable && ~row.TimingLockedAtEnd)
    row.Verdict = "LOOP_UNLOCKED_AT_END";
elseif row.BER > 0 || row.FER > 0
    row.Verdict = "DECODE_ERRORS";
elseif ~localLogical(coverage,'Available',false)
    row.Verdict = "MEASUREMENT_COVERAGE_UNAVAILABLE";
elseif ~localLogical(coverage,'Complete',false)
    row.Verdict = "MEASUREMENT_INCOMPLETE";
else
    row.Verdict = "SHORT_PASS";
end
end

function [available,lockPct,lockedAtEnd,losses,reacquisitions] = ...
        localTrack(track)
available = localLogical(track,'Available',false);
lockPct = 100*localNumber(track,'LockRate',NaN);
lockedAtEnd = localLogical(track,'LockedAtEnd',false);
losses = localNumber(track,'LossEvents',NaN);
reacquisitions = localNumber(track,'Reacquisitions',NaN);
end

function row = localEmptyRow()
row = struct( ...
    'FileIndex',NaN,'Family',"",'Profile',"",'FileName',"", ...
    'Success',false,'BER',NaN,'FER',NaN, ...
    'CountedFrames',NaN,'FrameErrors',NaN, ...
    'MeasurementCoverageStatus',"UNAVAILABLE", ...
    'MeasurementExpectedFrames',NaN,'MeasurementComparedFrames',NaN, ...
    'MeasurementCoverage_pct',NaN,'UnrecoveredMeasurementFrames',NaN, ...
    'RecoveredNotComparedFrames',NaN,'MeasurementDuration_s',NaN, ...
    'BitsObservedApprox',NaN,'ZeroErrorUpper95',NaN, ...
    'LegacyFrameMatch_pct',NaN, ...
    'CoarseCFOEstimate_Hz',NaN,'PSKCoarseCFOApplied',false, ...
    'PSKCoarseCFOAttempted',false,'PSKCoarseCFOAccepted',false, ...
    'PSKCoarseCFOConsistentWindows',NaN, ...
    'PSKCoarseCFOWindowCount',NaN,'PSKCoarseCFOReason',"", ...
    'PostFSECFOAttempted',false,'PostFSECFOAccepted',false, ...
    'PostFSECFOEstimate_Hz',0,'PostFSECFOReason',"", ...
    'TotalCFOCorrection_Hz',NaN, ...
    'NoisePower_dBm',NaN, ...
    'EquivalentSNR_dB',NaN, ...
    'EqualizerSamplingMode',"",'EqualizerModeActual',"", ...
    'EqualizerTaps',NaN,'EqualizerApplied',false, ...
    'EqualizerOutputAccepted',false,'FSEErrorMSE',NaN, ...
    'FSEDualApplied',false,'FSEDualSwitchApplied',false, ...
    'FSEDualSwitchSymbol',NaN,'FSEDualCMAConfidence_pct',NaN, ...
    'FSEDualCMAPhaseCoherence',NaN,'FSEDualAcceptance_pct',NaN, ...
    'FSEDualDDMSE',NaN,'FSEDualCarrierMeanAbsError_deg',NaN, ...
    'FSEDualCarrierFrequency_Hz',NaN,'FSEDualReason',"", ...
    'PredecoderBER',NaN,'PredecoderSteadyBER',NaN, ...
    'PredecoderFrameBERP95',NaN,'PredecoderFrameBERMax',NaN, ...
    'PredecoderWorstFrameIndex',NaN, ...
    'PredecoderWorstFrameBitErrors',NaN, ...
    'PredecoderCodedBitsPerFrame',NaN, ...
    'PredecoderNonzeroErrorFrames',NaN, ...
    'PredecoderWorstFrameTPCMaxCodewordErrors',NaN, ...
    'PredecoderWorstFrameTPCNonzeroCodewords',NaN, ...
    'PredecoderTxFrameOffset',NaN,'PredecoderASMAligned',NaN, ...
    'FSEPostMode',"off",'FSEPostApplied',false, ...
    'FSEPostAccepted',false,'FSEPostForwardTaps',NaN, ...
    'FSEPostFeedbackTaps',NaN,'FSEPostStep',NaN, ...
    'FSEPostAcceptance_pct',NaN,'FSEPostDDMSE',NaN, ...
    'FSEPostQualityImprovement',NaN,'FSEPostConverged',false, ...
    'PSKPostFSEPhaseTrackerMode',"not-applicable", ...
    'QPSKPostFSEPhaseTrackerMode',"not-applicable", ...
    'TPCDecoderMode',"iterative", ...
    'ASMFramePhaseCorrectionApplied',false, ...
    'ASMFramePhaseCorrectionReason',"", ...
    'ASMFramePhaseCorrectionFrames',NaN, ...
    'ASMFramePhaseCorrectionReliableFrames',NaN, ...
    'ASMFramePhaseCycleSlipsBefore',NaN, ...
    'ASMFramePhaseCycleSlipsAfter',NaN, ...
    'HMeanGain_dB',NaN, ...
    'HNormalizationGain_dB',NaN,'HDynamicRange_dB',NaN, ...
    'HDeepFadeBelow20_pct',NaN,'HSourceSamples',NaN, ...
    'HSourceDuration_s',NaN,'WaveformDuration_s',NaN, ...
    'ExceedsHDuration',false,'HDelaySpreadSymbols',NaN, ...
    'HFSESpanSymbols',NaN,'HFSESpanMarginSymbols',NaN, ...
    'HFSECoversDelaySpread',false,'HFrequencyMin_dB',NaN, ...
    'HFrequencyP01_dB',NaN,'HFrequencyP05_dB',NaN, ...
    'HPathPowerMode',"", ...
    'CarrierAvailable',false,'CarrierLock_pct',NaN, ...
    'CarrierLockedAtEnd',false,'CarrierLosses',NaN, ...
    'CarrierReacquisitions',NaN, ...
    'TimingAvailable',false,'TimingLock_pct',NaN, ...
    'TimingLockedAtEnd',false,'TimingLosses',NaN, ...
    'TimingReacquisitions',NaN, ...
    'FrameAvailable',false,'FrameLock_pct',NaN, ...
    'FrameLockedAtEnd',false,'FrameLosses',NaN, ...
    'FrameReacquisitions',NaN,'Verdict',"NOT_RUN", ...
    'Elapsed_s',NaN,'ErrorIdentifier',"",'ErrorMessage',"");
end

function out = localMerge(out,extra)
if isempty(extra)
    return;
end
if ~isstruct(extra) || ~isscalar(extra)
    error('codex_new_channel_psd_sync_sweep:InvalidOverrides', ...
        'Options and ReceiverOverrides must be scalar structs.');
end
names = fieldnames(extra);
for k = 1:numel(names)
    out.(names{k}) = extra.(names{k});
end
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = double(s.(name));
    if isscalar(candidate)
        value = candidate;
    end
end
end

function value = localLogical(s,name,defaultValue)
value = logical(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = logical(s.(name));
    if ~isscalar(value)
        value = logical(defaultValue);
    end
end
end

function value = localString(s,name,defaultValue)
value = string(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = string(s.(name));
    if ~isscalar(value)
        value = strjoin(value(:).'," | ");
    end
end
end

function value = localStruct(s,name)
value = struct();
if isstruct(s) && isfield(s,name) && isstruct(s.(name))
    value = s.(name);
end
end

function value = localPctText(available,pct)
if ~available || ~isfinite(pct)
    value = 'N/A';
else
    value = sprintf('%.1f%%',pct);
end
end
