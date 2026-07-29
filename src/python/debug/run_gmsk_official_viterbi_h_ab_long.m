%% RUN_GMSK_OFFICIAL_VITERBI_H_AB_LONG
% Focused real-H comparison for the two GMSK detectors:
%   1. legacy-frame-reset
%   2. official-viterbi-frame-reset
%
% The script contains no copied receiver algorithm.  It reuses the
% production transmitter, H loader, known-H MMSE equalizer, GMSK front end,
% official/custom detector branches, ASM recovery, channel decoder, and
% BER/FER counter through sweep_h_channel_short_frames.

clear classes
rng(20260716, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';
tdlFile = fullfile(channelDir, '2-ChannelData.mat');
corazzaFile = fullfile(channelDir, 'ChannelData_7.mat');
assert(isfile(tdlFile), 'TDL channel file was not found: %s', tdlFile);
assert(isfile(corazzaFile), ...
    'Corazza channel file was not found: %s', corazzaFile);

% Enable legacy-diff only when a full three-way rerun is needed.  The
% completed 20260715 sweep already provides the old reference; leaving this
% false keeps the manual test shorter.
runLegacyDiff = false;
runLegacyFrameReset = true;
runOfficialViterbi = true;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
rootOutput = fullfile(srcPythonDir, 'sweep_results', ...
    ['gmsk_official_viterbi_h_ab_' stamp]);
if ~isfolder(rootOutput), mkdir(rootOutput); end

base = struct();
base.hModelCases = { ...
    'std2_likely_TDL',     tdlFile; ...
    'std7_likely_Corazza', corazzaFile ...
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
% Keep PSD disabled until the detector comparison is complete.
base.noisePSDdBmHz = [];
base.noiseBandwidthHz = [];
base.cfo = 0;
base.phaseOffset = 0;
base.delay = 0;
base.gmskBT = 0.5;
base.hasASM = true;
base.hasRandomizer = false;

% Forty generated frames reproduce the duration of the old 20260715 short
% sweep while keeping the oversampled official Viterbi run manageable.
base.berWarmUpFrames = 10;
base.berFrames = 30;
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
base.randomSeed = 20260716;
base.clearFunctionCache = true;

allResults = table();

if runLegacyDiff
    opts = base;
    opts.GMSKDetectionMode = 'legacy-diff';
    opts.outputDir = fullfile(rootOutput, 'legacy_diff');
    fprintf('\n===== A: legacy-diff =====\n');
    T = sweep_h_channel_short_frames(opts);
    T.DetectionMode = repmat("legacy-diff", height(T), 1);
    allResults = [allResults; T]; %#ok<AGROW>
end

if runLegacyFrameReset
    opts = base;
    opts.GMSKDetectionMode = 'legacy-frame-reset';
    opts.outputDir = fullfile(rootOutput, 'legacy_frame_reset');
    fprintf('\n===== B: legacy-frame-reset =====\n');
    T = sweep_h_channel_short_frames(opts);
    T.DetectionMode = repmat("legacy-frame-reset", height(T), 1);
    allResults = [allResults; T]; %#ok<AGROW>
end

if runOfficialViterbi
    opts = base;
    opts.GMSKDetectionMode = 'official-viterbi-frame-reset';
    opts.outputDir = fullfile(rootOutput, 'official_viterbi_frame_reset');
    fprintf('\n===== C: official-viterbi-frame-reset =====\n');
    T = sweep_h_channel_short_frames(opts);
    T.DetectionMode = repmat( ...
        "official-viterbi-frame-reset", height(T), 1);
    allResults = [allResults; T]; %#ok<AGROW>
end

comparison = localAddLossAwareMetrics(allResults);
comparisonPath = fullfile(rootOutput, ...
    'gmsk_official_viterbi_h_ab_comparison.csv');
matPath = fullfile(rootOutput, ...
    'gmsk_official_viterbi_h_ab_comparison.mat');
writetable(comparison, comparisonPath);
save(matPath, 'comparison', 'base', 'runLegacyDiff', ...
    'runLegacyFrameReset', 'runOfficialViterbi');

keyColumns = {'DetectionMode','Scenario','ChannelCoding','Rate','BER', ...
    'LockRate_pct','FER','UnlockedFrames','BadMatchedFrames', ...
    'EffectiveFER_pct','GoodFrames','CountedFrames','MatchedFrames', ...
    'WaveformDuration_s','HSourceDuration_s','ExceedsHDuration', ...
    'Success','Status'};
keyColumns = keyColumns( ...
    ismember(keyColumns, comparison.Properties.VariableNames));

fprintf('\n===== OFFICIAL VITERBI H A/B KEY RESULTS =====\n');
disp(comparison(:, keyColumns));

badInfrastructure = ~comparison.Success | comparison.ExceedsHDuration;
fprintf('Infrastructure failures / H-duration overruns: %d\n', ...
    nnz(badInfrastructure));
fprintf('Comparison CSV: %s\n', comparisonPath);
fprintf('Comparison MAT: %s\n', matPath);

assignin('base', 'gmskOfficialViterbiHAB', comparison);

function T = localAddLossAwareMetrics(T)
    n = height(T);
    T.ExpectedCountedFrames = nan(n, 1);
    T.UnlockedFrames = nan(n, 1);
    T.BadMatchedFrames = nan(n, 1);
    T.EffectiveFailedFrames = nan(n, 1);
    T.EffectiveFER_pct = nan(n, 1);
    T.GoodFrames = nan(n, 1);

    mode = string(T.DetectionMode);
    scenario = string(T.Scenario);
    coding = string(T.ChannelCoding);
    rate = string(T.Rate);
    noH = scenario == "NoH_baseline";

    for rowIndex = 1:n
        referenceIndex = find(noH & ...
            mode == mode(rowIndex) & ...
            coding == coding(rowIndex) & ...
            rate == rate(rowIndex), 1, 'first');
        if isempty(referenceIndex)
            continue;
        end

        expected = double(T.CountedFrames(referenceIndex));
        counted = double(T.CountedFrames(rowIndex));
        badMatched = round(double(T.FER(rowIndex)) * counted);
        unlocked = max(expected - counted, 0);
        failed = unlocked + badMatched;

        T.ExpectedCountedFrames(rowIndex) = expected;
        T.UnlockedFrames(rowIndex) = unlocked;
        T.BadMatchedFrames(rowIndex) = badMatched;
        T.EffectiveFailedFrames(rowIndex) = failed;
        T.GoodFrames(rowIndex) = max(expected - failed, 0);
        if expected > 0
            T.EffectiveFER_pct(rowIndex) = 100 * failed / expected;
        end
    end
end
