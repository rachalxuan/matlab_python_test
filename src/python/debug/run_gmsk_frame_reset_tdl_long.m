%% RUN_GMSK_FRAME_RESET_TDL_LONG
% Long test for the real TDL MAT trace.  Run this file manually in MATLAB.
%
% It uses the same transmitter, H-channel loader, equalizer, synchronizers,
% decoder, and BER counter as the production evaluation.  The only A/B
% variable is GMSKDetectionMode.

clear classes
rng(20260715, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';
tdlFile = fullfile(channelDir, '2-ChannelData.mat');
assert(isfile(tdlFile), 'TDL channel file was not found: %s', tdlFile);

% Set either flag false when only one side of the A/B comparison is needed.
runLegacy = true;
runFrameReset = true;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
rootOutput = fullfile(srcPythonDir, 'sweep_results', ...
    ['gmsk_frame_reset_tdl_' stamp]);
if ~isfolder(rootOutput), mkdir(rootOutput); end

base = struct();
base.hModelCases = { ...
    'std2_likely_TDL', tdlFile ...
};
base.modTypes = {'GMSK'};
base.convRates = {'1/2','2/3','3/4','5/6','7/8'};
base.includeNoHBaseline = true;
base.includeHEqualized = true;
base.includeNormHScenario = false;
base.includeNoEqualizerScenario = false;
base.includeLDPC = false;
base.includeTurbo = false;
base.includeTPC = false;

base.symbolRate = 20e6;
base.sps = 8;
base.snr = 30;
base.noisePlacement = 'afterChannel';
% Deliberately keep PSD disabled in this algorithm A/B test.  PSD/link-
% budget validation is a separate experiment and would change two variables.
base.noisePSDdBmHz = [];
base.noiseBandwidthHz = [];
base.cfo = 0;
base.phaseOffset = 0;
base.delay = 0;
base.gmskBT = 0.5;
base.hasASM = true;
base.RandomizerEnabled = false;

% 120 generated frames cover both observed TDL fades near 18.5 ms and
% 39.6 ms while staying far below the MAT trace duration.
base.berWarmUpFrames = 20;
base.berFrames = 100;
base.channelOutOfRangeMode = 'error';
base.channelInterpolationMethod = 'linear';
base.interpolateChannelDelays = false;
base.equalizerMode = 'mmse';
base.normalizeEqualizerOutput = true;

base.showFigures = false;
base.showPipelineFigure = false;
base.showDamageBudgetFigure = false;
base.showPowerFigure = false;
base.debugGMSK = false;
base.debugCodedBoundary = false;
base.debugPerFrameBERSummary = true;
base.debugAllPerFrameBER = false;
base.randomSeed = 20260715;
base.clearFunctionCache = true;

TLegacy = table();
TFrameReset = table();

if runLegacy
    legacyOpts = base;
    legacyOpts.GMSKDetectionMode = 'legacy-diff';
    legacyOpts.outputDir = fullfile(rootOutput, 'legacy_diff');
    fprintf('\n===== LONG A: legacy-diff =====\n');
    TLegacy = sweep_h_channel_short_frames(legacyOpts);
    TLegacy.DetectionMode = repmat("legacy-diff", height(TLegacy), 1);
end

if runFrameReset
    resetOpts = base;
    resetOpts.GMSKDetectionMode = 'legacy-frame-reset';
    resetOpts.outputDir = fullfile(rootOutput, 'legacy_frame_reset');
    fprintf('\n===== LONG B: legacy-frame-reset =====\n');
    TFrameReset = sweep_h_channel_short_frames(resetOpts);
    TFrameReset.DetectionMode = repmat("legacy-frame-reset", ...
        height(TFrameReset), 1);
end

if ~isempty(TLegacy) && ~isempty(TFrameReset)
    comparison = [TLegacy; TFrameReset];
elseif ~isempty(TLegacy)
    comparison = TLegacy;
else
    comparison = TFrameReset;
end

comparisonPath = fullfile(rootOutput, 'gmsk_tdl_ab_comparison.csv');
matPath = fullfile(rootOutput, 'gmsk_tdl_ab_comparison.mat');
writetable(comparison, comparisonPath);
save(matPath, 'comparison', 'TLegacy', 'TFrameReset', 'base');

keyColumns = {'DetectionMode','Scenario','ChannelCoding','Rate', ...
    'NumBytesInTransferFrame','BER','LockRate_pct','FER', ...
    'CountedFrames','MatchedFrames','WaveformDuration_s', ...
    'HSourceDuration_s','ExceedsHDuration','Success','Status'};
keyColumns = keyColumns(ismember(keyColumns, comparison.Properties.VariableNames));
fprintf('\n===== GMSK TDL A/B KEY RESULTS =====\n');
disp(comparison(:, keyColumns));
fprintf('Comparison CSV: %s\n', comparisonPath);
fprintf('Comparison MAT: %s\n', matPath);

bad = ~comparison.Success | comparison.ExceedsHDuration;
if any(bad)
    warning('run_gmsk_frame_reset_tdl_long:InfrastructureFailure', ...
        '%d cases failed or exceeded the channel duration. Inspect Status/ErrorMessage.', ...
        nnz(bad));
end

assignin('base', 'gmskTDLComparison', comparison);
