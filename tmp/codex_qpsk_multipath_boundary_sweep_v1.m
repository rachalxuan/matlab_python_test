% Controlled QPSK multipath-memory boundary screen.
%
% Purpose
%   Hold modulation, coding, noise, carrier/timing impairments, path powers,
%   and path phases fixed.  Change only the maximum path-delay spread in
%   symbol units, then compare no equalizer, the legacy 1-sps equalizer,
%   and the experimental 2-sps fractionally spaced equalizer.
%
% Important limitation
%   Maximum delay spread alone does not define channel difficulty.  This
%   script measures one deterministic, static, A1-like three-path family;
%   it is not a universal guarantee for every channel with the same delay.
%
% Optional caller configuration (set before run):
%   MultipathBoundaryOptions = struct( ...
%       'SymbolRate',30e6, ...
%       'DelayLevelsSymbols',[1 5 10 20 30], ...
%       'IncludeFlatControl',true, ...
%       'EqualizerModes',["none" "1sps" "2sps"], ...
%       'BERWarmUpFrames',4, ...
%       'BERFrames',12, ...
%       'VerboseReceiverLog',false, ...
%       'SaveCSV',false);

thisFile = mfilename('fullpath');
if isempty(thisFile)
    error('codex_qpsk_multipath_boundary_sweep:NoScriptPath', ...
        'Run this file with run(...); mfilename(''fullpath'') is empty.');
end
scriptDir = fileparts(thisFile);
projectRoot = fileparts(scriptDir);
sourceDir = fullfile(projectRoot,'src','python');
addpath(sourceDir);

userOptions = struct();
if exist('MultipathBoundaryOptions','var') && ...
        isstruct(MultipathBoundaryOptions)
    userOptions = MultipathBoundaryOptions;
end
cfg = localMerge(localDefaults(),userOptions);
cfg = localValidate(cfg);

delayLevels = double(cfg.DelayLevelsSymbols(:).');
if logical(cfg.IncludeFlatControl) && ~any(abs(delayLevels) < 1e-12)
    delayLevels = [0 delayLevels];
end
delayLevels = unique(delayLevels,'stable');
equalizerModes = lower(string(cfg.EqualizerModes(:).'));

fprintf('\n================ QPSK MULTIPATH BOUNDARY SCREEN ================\n');
fprintf('Signal          : QPSK, uncoded, noise OFF, CFO/phase/delay=0\n');
fprintf('Symbol rate     : %.6g Msym/s, waveform sps=%d, rolloff=%.3f\n', ...
    cfg.SymbolRate/1e6,cfg.SamplesPerSymbol,cfg.RolloffFactor);
fprintf('Delay levels    : %s symbols\n',mat2str(delayLevels));
fprintf('Equalizer modes : %s\n',strjoin(cellstr(equalizerModes),', '));
fprintf('Equalizer spans : 1-sps %d taps = %.1f sym; 2-sps %d taps = %.1f sym\n', ...
    cfg.OneSPSTaps,cfg.OneSPSTaps-1,cfg.TwoSPSTaps, ...
    (cfg.TwoSPSTaps-1)/2);
fprintf('Channel         : static 3-path, delays=%s * Dmax\n', ...
    mat2str(cfg.PathDelayFractions,4));
fprintf('Path powers     : %s dB; phases=%s deg\n', ...
    mat2str(cfg.PathPowerDB,4),mat2str(cfg.PathPhaseDeg,4));
fprintf(['Verdict         : short zero-error/acquisition screen only; ', ...
    'it does not prove BER < 1e-6.\n']);
fprintf(['Regions         : <=20 sym primary design; (20,50] stress; ', ...
    '>50 extreme.\n\n']);

temporaryRoot = tempname(tempdir);
mkdir(temporaryRoot);
temporaryCleanup = onCleanup(@()localCleanupTemporaryRoot(temporaryRoot));

numberOfCases = numel(delayLevels)*numel(equalizerModes);
rows = repmat(localEmptyRow(),numberOfCases,1);
logs = cell(numberOfCases,1);
rowIndex = 0;

for delayIndex = 1:numel(delayLevels)
    requestedDelaySymbols = delayLevels(delayIndex);
    channelPath = fullfile(temporaryRoot,sprintf( ...
        'qpsk_static_3path_delay_%03d.mat',round(requestedDelaySymbols)));
    localWriteStaticChannel(channelPath,requestedDelaySymbols,cfg);

    for modeIndex = 1:numel(equalizerModes)
        rowIndex = rowIndex+1;
        mode = equalizerModes(modeIndex);
        row = localEmptyRow();
        row.CaseIndex = rowIndex;
        row.RequestedDelaySymbols = requestedDelaySymbols;
        row.Region = localRegion(requestedDelaySymbols);
        row.EqualizerMode = mode;

        p = localBaseReceiver(cfg,channelPath,mode);
        p = localMerge(p,cfg.ReceiverOverrides);

        fprintf('[%02d/%02d] Dmax=%5.1f sym | %-4s ...\n', ...
            rowIndex,numberOfCases,requestedDelaySymbols,char(mode));
        runTimer = tic;
        try
            rng(cfg.Seed,'twister');
            result = struct();
            logs{rowIndex} = evalc( ...
                '[result,~] = run_ccsds_tm_evaluation(p);');
            row.Elapsed_s = toc(runTimer);
            row = localFillRow(row,result,cfg);
        catch ME
            row.Elapsed_s = toc(runTimer);
            row.Success = false;
            row.Verdict = "RUN_ERROR";
            row.ErrorIdentifier = string(ME.identifier);
            row.ErrorMessage = string(ME.message);
            logs{rowIndex} = getReport(ME,'extended','hyperlinks','off');
        end
        rows(rowIndex) = row;

        fprintf(['  %-18s BER=%-10.4g errors~=%-6g FER=%-9.4g ', ...
            'Lock=%6.2f%% actualD=%6.2f sym EQaccepted=%d ', ...
            'CMA/FSE-MSE=%-9.4g %.2fs\n'], ...
            char(row.Verdict),row.BER,row.EstimatedBitErrors,row.FER, ...
            row.LockRate_pct,row.ActualDelaySymbols, ...
            row.EqualizerOutputAccepted,row.EqualizerMSE,row.Elapsed_s);
        if row.Verdict == "RUN_ERROR"
            fprintf(2,'  %s: %s\n',char(row.ErrorIdentifier), ...
                char(row.ErrorMessage));
        end
        if logical(cfg.VerboseReceiverLog)
            fprintf('%s',logs{rowIndex});
        end
    end
end

QPSKMultipathBoundaryResults = struct2table(rows,'AsArray',true);
QPSKMultipathBoundaryLogs = logs;
QPSKMultipathBoundarySummary = localBuildSummary( ...
    QPSKMultipathBoundaryResults,equalizerModes);

fprintf('\n================ BOUNDARY RESULTS ================\n');
disp(QPSKMultipathBoundaryResults(:,{ ...
    'CaseIndex','RequestedDelaySymbols','ActualDelaySymbols','Region', ...
    'EqualizerMode','BER','EstimatedBitErrors','FER','LockRate_pct', ...
    'EqualizerApplied','EqualizerOutputAccepted','EqualizerConverged', ...
    'EqualizerTaps','EqualizerMSE','HFrequencyMin_dB', ...
    'HFrequencyP01_dB','Verdict'}));

fprintf('\n================ MODE SUMMARY ================\n');
disp(QPSKMultipathBoundarySummary);
fprintf(['Interpretation: ZERO_ERRORS_SHORT means zero errors in only the ', ...
    'counted bits shown.  Delay-only performance need not be monotonic, ', ...
    'so the largest zero-error level is not a universal delay limit.\n']);

if logical(cfg.SaveCSV)
    csvPath = char(string(cfg.CSVPath));
    if isempty(strtrim(csvPath))
        csvPath = fullfile(scriptDir,'qpsk_multipath_boundary_results.csv');
    end
    writetable(QPSKMultipathBoundaryResults,csvPath);
    fprintf('CSV written: %s\n',csvPath);
else
    fprintf(['No result file was written. Results remain in ', ...
        'QPSKMultipathBoundaryResults, QPSKMultipathBoundarySummary, ', ...
        'and QPSKMultipathBoundaryLogs.\n']);
end

function cfg = localDefaults()
cfg = struct();
cfg.SymbolRate = 30e6;
cfg.SamplesPerSymbol = 8;
cfg.RolloffFactor = 0.35;
cfg.NumBytesInTransferFrame = 1115;
cfg.BERWarmUpFrames = 4;
cfg.BERFrames = 12;
cfg.DelayLevelsSymbols = [1 5 10 20 30];
cfg.IncludeFlatControl = true;
cfg.EqualizerModes = ["none" "1sps" "2sps"];

% A1-like relative geometry and powers, but deliberately time invariant.
% The receiver's embedded path-power mode means H already contains these
% voltage amplitudes; P_nMode is saved as metadata only.
cfg.PathDelayFractions = [0 0.38046 1];
cfg.PathPowerDB = [0 -4.675 -6.482];
cfg.PathPhaseDeg = [0 0 0];
cfg.ChannelSampleRateHz = 100e3;
cfg.NormalizeHChannel = true;

% Equal temporal coverage: both equalizers span 64 symbols.
cfg.OneSPSTaps = 65;
cfg.TwoSPSTaps = 129;
cfg.OneSPSCMAWarmupSymbols = 8000;
cfg.OneSPSCMAStep = 0.005;
cfg.OneSPSDDStep = 5e-4;
cfg.TwoSPSCMAstep = 2e-4;
cfg.TwoSPSConvergenceMSEThreshold = 0.05;

cfg.Seed = 364232726;
cfg.ReceiverOverrides = struct();
cfg.VerboseReceiverLog = false;
cfg.SaveCSV = false;
cfg.CSVPath = '';
end

function cfg = localValidate(cfg)
positiveScalars = {'SymbolRate','SamplesPerSymbol','RolloffFactor', ...
    'NumBytesInTransferFrame','BERFrames','ChannelSampleRateHz', ...
    'OneSPSTaps','TwoSPSTaps','OneSPSCMAWarmupSymbols', ...
    'OneSPSCMAStep','OneSPSDDStep','TwoSPSCMAstep', ...
    'TwoSPSConvergenceMSEThreshold'};
for k = 1:numel(positiveScalars)
    name = positiveScalars{k};
    value = double(cfg.(name));
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('codex_qpsk_multipath_boundary_sweep:InvalidOption', ...
            '%s must be one finite positive scalar.',name);
    end
end
if ~isscalar(cfg.BERWarmUpFrames) || ~isfinite(cfg.BERWarmUpFrames) || ...
        cfg.BERWarmUpFrames < 0
    error('codex_qpsk_multipath_boundary_sweep:InvalidWarmup', ...
        'BERWarmUpFrames must be one finite nonnegative scalar.');
end
cfg.SamplesPerSymbol = round(double(cfg.SamplesPerSymbol));
cfg.NumBytesInTransferFrame = round(double(cfg.NumBytesInTransferFrame));
cfg.BERWarmUpFrames = round(double(cfg.BERWarmUpFrames));
cfg.BERFrames = round(double(cfg.BERFrames));
cfg.OneSPSTaps = localOdd(round(double(cfg.OneSPSTaps)));
cfg.TwoSPSTaps = localOdd(round(double(cfg.TwoSPSTaps)));
if cfg.SamplesPerSymbol < 2 || mod(cfg.SamplesPerSymbol,2) ~= 0
    error('codex_qpsk_multipath_boundary_sweep:InvalidSPS', ...
        'SamplesPerSymbol must be an even integer >= 2.');
end
if any(~isfinite(cfg.DelayLevelsSymbols(:))) || ...
        any(cfg.DelayLevelsSymbols(:) < 0)
    error('codex_qpsk_multipath_boundary_sweep:InvalidDelays', ...
        'DelayLevelsSymbols must contain finite nonnegative values.');
end
fractions = double(cfg.PathDelayFractions(:).');
powers = double(cfg.PathPowerDB(:).');
phases = double(cfg.PathPhaseDeg(:).');
if numel(fractions) < 2 || numel(fractions) ~= numel(powers) || ...
        numel(fractions) ~= numel(phases) || ...
        any(~isfinite([fractions powers phases])) || ...
        any(fractions < 0) || abs(min(fractions)) > 1e-12 || ...
        abs(max(fractions)-1) > 1e-12
    error('codex_qpsk_multipath_boundary_sweep:InvalidPathTemplate', ...
        ['Path vectors must have equal length; delay fractions must be ', ...
         'finite, nonnegative, start at 0, and end at 1.']);
end
cfg.PathDelayFractions = fractions;
cfg.PathPowerDB = powers;
cfg.PathPhaseDeg = phases;

modes = lower(string(cfg.EqualizerModes(:).'));
if isempty(modes) || any(~ismember(modes,["none" "1sps" "2sps"]))
    error('codex_qpsk_multipath_boundary_sweep:InvalidModes', ...
        'EqualizerModes may contain only none, 1sps, and 2sps.');
end
cfg.EqualizerModes = unique(modes,'stable');
if ~isstruct(cfg.ReceiverOverrides) || ~isscalar(cfg.ReceiverOverrides)
    error('codex_qpsk_multipath_boundary_sweep:InvalidOverrides', ...
        'ReceiverOverrides must be one scalar struct.');
end
end

function p = localBaseReceiver(cfg,channelPath,mode)
p = struct();
p.modType = 'QPSK';
p.channelCoding = 'none';
p.symbolRate = cfg.SymbolRate;
p.sps = cfg.SamplesPerSymbol;
p.snr = 100;
p.noiseMode = 'off';
p.noisePlacement = 'afterChannel';
p.cfo = 0;
p.phaseOffset = 0;
p.delay = 0;
p.RolloffFactor = cfg.RolloffFactor;

p.WaveformMode = 'ordinaryTM';
p.NumBytesInTransferFrame = cfg.NumBytesInTransferFrame;
p.hasASM = true;
p.RandomizerEnabled = false;
p.RandomizerFECPosition = 'afterEncoding';
p.DataPathMode = 'single';
p.TMDataSource = 'random';
p.PCMFormat = 'NRZ-L';
p.berWarmUpFrames = cfg.BERWarmUpFrames;
p.berFrames = cfg.BERFrames;
p.excludeBERWarmUpFrames = true;

p.enableHChannel = true;
p.HMode = 'h_matrix_file';
p.channelFilePath = channelPath;
p.channelSampleRateHz = cfg.ChannelSampleRateHz;
p.channelInterpolationMethod = 'linear';
p.channelOutOfRangeMode = 'hold';
p.interpolateChannelDelays = false;
p.channelPathPowerMode = 'embedded';
p.normalizeHChannel = logical(cfg.NormalizeHChannel);

p.enableKnownHPreEqualizer = false;
p.normalizeEqualizerOutput = true;
p.enableBlindReliabilityManager = false;
p.timingLoopBandwidth = 0.005;
p.carrierLoopBandwidth = 0.01;
p.enableConverterChain = false;
p.enableADCEquivalent = false;
p.AGCEnabled = false;

switch mode
    case "none"
        p.enableEqualizer = false;
        p.equalizerMode = 'off';
        p.adaptiveEqualizerSamplingMode = 'off';
    case "1sps"
        p.enableEqualizer = true;
        p.equalizerMode = 'blind-cma-lms';
        p.adaptiveEqualizerSamplingMode = '1sps';
        p.adaptiveEqualizerTaps = cfg.OneSPSTaps;
        p.adaptiveEqualizerCMAWarmupSymbols = ...
            cfg.OneSPSCMAWarmupSymbols;
        p.adaptiveEqualizerCMAStep = cfg.OneSPSCMAStep;
        p.adaptiveEqualizerDDStep = cfg.OneSPSDDStep;
        p.adaptiveEqualizerDDPasses = 1;
    case "2sps"
        p.enableEqualizer = true;
        p.equalizerMode = 'blind-cma-lms';
        p.adaptiveEqualizerSamplingMode = '2sps';
        p.adaptiveFractionalEqualizerInputSamplesPerSymbol = 2;
        p.adaptiveFractionalEqualizerTaps = cfg.TwoSPSTaps;
        p.adaptiveFractionalEqualizerStep = cfg.TwoSPSCMAstep;
        p.adaptiveFractionalEqualizerMetricWarmupSymbols = ...
            cfg.OneSPSCMAWarmupSymbols;
        p.adaptiveFractionalEqualizerConvergenceMSEThreshold = ...
            cfg.TwoSPSConvergenceMSEThreshold;
        p.adaptiveFractionalPostMode = 'off';
end

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

function localWriteStaticChannel(filePath,delaySymbols,cfg)
pathPowerLinear = 10.^(cfg.PathPowerDB(:)/10);
pathVoltage = sqrt(pathPowerLinear);
pathPhase = exp(1j*deg2rad(cfg.PathPhaseDeg(:)));
pathCoefficients = pathVoltage.*pathPhase;
pathCoefficients = pathCoefficients/sqrt(sum(abs(pathCoefficients).^2));

% Keep enough constant snapshots that ordinary short and confirmation runs
% do not need wrapping.  The hold mode remains correct for longer runs.
symbolsPerFrame = cfg.NumBytesInTransferFrame*8/2+32;
estimatedDuration = (cfg.BERWarmUpFrames+cfg.BERFrames+2)* ...
    symbolsPerFrame/cfg.SymbolRate;
numberOfSnapshots = max(2,ceil(1.2*estimatedDuration* ...
    cfg.ChannelSampleRateHz)+4);

H_Martix_tMode = repmat(pathCoefficients,1,numberOfSnapshots);
tao_nMode = cfg.PathDelayFractions(:)*delaySymbols/cfg.SymbolRate;
P_nMode = pathPowerLinear;
doppler = 0;
ChannelModelMeta = struct( ...
    'ChannelSampleRateHz',cfg.ChannelSampleRateHz, ...
    'SyntheticBoundaryChannel',true, ...
    'RequestedMaxDelaySymbols',delaySymbols, ...
    'PathDelayFractions',cfg.PathDelayFractions, ...
    'PathPowerDB',cfg.PathPowerDB, ...
    'PathPhaseDeg',cfg.PathPhaseDeg);
save(filePath,'H_Martix_tMode','tao_nMode','P_nMode','doppler', ...
    'ChannelModelMeta','-v7');
end

function row = localFillRow(row,result,cfg)
row.Success = localLogical(result,'success',false);
if ~row.Success
    row.Verdict = "RUN_ERROR";
    row.ErrorIdentifier = localString(result,'errorIdentifier',"");
    row.ErrorMessage = localString(result,'errorMsg', ...
        localString(result,'error',"receiver returned success=false"));
    return;
end

row.BER = localNumber(result,'BER',NaN);
row.FER = localNumber(result,'FER',NaN);
row.LockRate_pct = 100*localNumber(result,'LockRate',NaN);
row.FrameErrors = localNumber(result,'FrameErrors',NaN);
row.CountedFrames = localNumber(result,'CountedFrames',NaN);
row.CountedBits = row.CountedFrames*cfg.NumBytesInTransferFrame*8;
if isfinite(row.BER) && isfinite(row.CountedBits)
    row.EstimatedBitErrors = round(row.BER*row.CountedBits);
end

row.EqualizerApplied = localLogical( ...
    result,'AdaptiveEqualizerEnabled',false) || localLogical( ...
    result,'AdaptiveFractionalEqualizerApplied',false);
row.EqualizerOutputAccepted = localLogical( ...
    result,'AdaptiveEqualizerOutputAccepted',false);
row.EqualizerConverged = localLogical( ...
    result,'AdaptiveEqualizerConverged',false);
row.EqualizerTaps = localNumber(result,'AdaptiveEqualizerTaps',NaN);
if row.EqualizerMode == "2sps"
    row.EqualizerTaps = localNumber( ...
        result,'AdaptiveFractionalEqualizerTaps',row.EqualizerTaps);
    row.EqualizerMSE = localNumber( ...
        result,'AdaptiveFractionalEqualizerErrorMSE',NaN);
else
    row.EqualizerMSE = localNumber(result,'AdaptiveEqualizerCMAMSE',NaN);
end

h = localStruct(result,'HChannelMeta');
row.ActualDelaySymbols = localNumber(h,'DelaySpreadSymbols',NaN);
row.HFrequencyMin_dB = localNumber(h,'FrequencyResponseMin_dB',NaN);
row.HFrequencyP01_dB = localNumber(h,'FrequencyResponseP01_dB',NaN);
row.HFrequencyP05_dB = localNumber(h,'FrequencyResponseP05_dB',NaN);
row.WaveformDuration_s = localNumber(h,'WaveformDuration_s',NaN);

if ~isfinite(row.CountedFrames) || row.CountedFrames < 1 || ...
        ~isfinite(row.LockRate_pct) || row.LockRate_pct < 80
    row.Verdict = "NO_FRAME_LOCK";
elseif isfinite(row.EstimatedBitErrors) && row.EstimatedBitErrors == 0
    row.Verdict = "ZERO_ERRORS_SHORT";
else
    row.Verdict = "ERROR_OBSERVED";
end
end

function summary = localBuildSummary(results,modes)
summaryRows = repmat(struct( ...
    'EqualizerMode',"", ...
    'TestedLevels',0, ...
    'ZeroErrorLevels',0, ...
    'PrimaryLevelsTested',0, ...
    'PrimaryZeroErrorLevels',0, ...
    'PrimaryAllTestedZeroError',false, ...
    'LargestTestedZeroErrorDelaySymbols',NaN, ...
    'SmallestObservedFailureDelaySymbols',NaN),numel(modes),1);
for k = 1:numel(modes)
    selected = results.EqualizerMode == modes(k);
    primary = selected & results.RequestedDelaySymbols > 0 & ...
        results.RequestedDelaySymbols <= 20;
    zeroError = selected & results.Verdict == "ZERO_ERRORS_SHORT";
    failed = selected & results.RequestedDelaySymbols > 0 & ...
        results.Verdict ~= "ZERO_ERRORS_SHORT";
    summaryRows(k).EqualizerMode = modes(k);
    summaryRows(k).TestedLevels = nnz(selected);
    summaryRows(k).ZeroErrorLevels = nnz(zeroError);
    summaryRows(k).PrimaryLevelsTested = nnz(primary);
    summaryRows(k).PrimaryZeroErrorLevels = nnz(primary & zeroError);
    summaryRows(k).PrimaryAllTestedZeroError = ...
        any(primary) && all(results.Verdict(primary) == "ZERO_ERRORS_SHORT");
    if any(zeroError)
        summaryRows(k).LargestTestedZeroErrorDelaySymbols = max( ...
            results.RequestedDelaySymbols(zeroError));
    end
    if any(failed)
        summaryRows(k).SmallestObservedFailureDelaySymbols = min( ...
            results.RequestedDelaySymbols(failed));
    end
end
summary = struct2table(summaryRows,'AsArray',true);
end

function row = localEmptyRow()
row = struct( ...
    'CaseIndex',0, ...
    'RequestedDelaySymbols',NaN, ...
    'ActualDelaySymbols',NaN, ...
    'Region',"", ...
    'EqualizerMode',"", ...
    'BER',NaN, ...
    'EstimatedBitErrors',NaN, ...
    'CountedBits',NaN, ...
    'FER',NaN, ...
    'FrameErrors',NaN, ...
    'CountedFrames',NaN, ...
    'LockRate_pct',NaN, ...
    'EqualizerApplied',false, ...
    'EqualizerOutputAccepted',false, ...
    'EqualizerConverged',false, ...
    'EqualizerTaps',NaN, ...
    'EqualizerMSE',NaN, ...
    'HFrequencyMin_dB',NaN, ...
    'HFrequencyP01_dB',NaN, ...
    'HFrequencyP05_dB',NaN, ...
    'WaveformDuration_s',NaN, ...
    'Elapsed_s',NaN, ...
    'Success',false, ...
    'Verdict',"NOT_RUN", ...
    'ErrorIdentifier',"", ...
    'ErrorMessage',"");
end

function region = localRegion(delaySymbols)
if delaySymbols == 0
    region = "flat-control";
elseif delaySymbols <= 20
    region = "primary";
elseif delaySymbols <= 50
    region = "stress";
else
    region = "extreme";
end
end

function merged = localMerge(base,override)
merged = base;
if isempty(override)
    return;
end
names = fieldnames(override);
for k = 1:numel(names)
    merged.(names{k}) = override.(names{k});
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
    candidate = s.(name);
    if islogical(candidate) && isscalar(candidate)
        value = candidate;
    elseif isnumeric(candidate) && isscalar(candidate) && ...
            isfinite(candidate)
        value = logical(candidate);
    end
end
end

function value = localString(s,name,defaultValue)
value = string(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = string(s.(name));
    if isscalar(candidate)
        value = candidate;
    end
end
end

function value = localStruct(s,name)
value = struct();
if isstruct(s) && isfield(s,name) && isstruct(s.(name))
    value = s.(name);
end
end

function value = localOdd(value)
value = max(1,round(value));
if value > 1 && mod(value,2) == 0
    value = value+1;
end
end

function localCleanupTemporaryRoot(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,'s');
end
end
