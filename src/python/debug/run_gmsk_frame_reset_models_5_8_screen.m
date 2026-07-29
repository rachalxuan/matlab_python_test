%% RUN_GMSK_FRAME_RESET_MODELS_5_8_SCREEN
% Stage-1 screen for the four legacy ChannelData_5..8 MAT traces.
%
% This script deliberately changes only the H trace.  It reuses the
% production transmitter, H loader, MMSE equalizer, synchronizers, GMSK
% frame-reset detector, channel decoder, and BER/FER counter.
%
% Noise remains in the existing 30 dB SNR mode for direct comparison with
% the completed TDL A/B test.  PSD noise is a separate stage.

clear classes
rng(20260716, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';
modelFiles = { ...
    'std5_likely_Jakes',   fullfile(channelDir, 'ChannelData_5.mat'); ...
    'std6_likely_CLoo',    fullfile(channelDir, 'ChannelData_6.mat'); ...
    'std7_likely_Corazza', fullfile(channelDir, 'ChannelData_7.mat'); ...
    'std8_likely_Lutz',    fullfile(channelDir, 'ChannelData_8.mat')  ...
};

for fileIndex = 1:size(modelFiles, 1)
    assert(isfile(modelFiles{fileIndex, 2}), ...
        'Channel file was not found: %s', modelFiles{fileIndex, 2});
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
outputDir = fullfile(srcPythonDir, 'sweep_results', ...
    ['gmsk_frame_reset_models_5_8_screen_' stamp]);
if ~isfolder(outputDir), mkdir(outputDir); end

opts = struct();
opts.outputDir = outputDir;
opts.hModelCases = modelFiles;
opts.modTypes = {'GMSK'};
opts.convRates = {'1/2','2/3','3/4','5/6','7/8'};

opts.includeNoHBaseline = true;
opts.includeHEqualized = true;
opts.includeNormHScenario = false;
opts.includeNoEqualizerScenario = false;
opts.includeLDPC = false;
opts.includeTurbo = false;
opts.includeTPC = false;

opts.symbolRate = 20e6;
opts.sps = 8;
opts.snr = 30;
opts.noisePlacement = 'afterChannel';
opts.noisePSDdBmHz = [];
opts.noiseBandwidthHz = [];
opts.cfo = 0;
opts.phaseOffset = 0;
opts.delay = 0;
opts.gmskBT = 0.5;
opts.hasASM = true;
opts.hasRandomizer = false;

% Same frame count as the completed TDL A/B test.  Depending on code rate,
% each case consumes about 0.054 to 0.107 seconds of its H trace.
opts.berWarmUpFrames = 20;
opts.berFrames = 100;

% Never silently reuse the beginning of a trace.
opts.channelOutOfRangeMode = 'error';
opts.channelInterpolationMethod = 'linear';
opts.interpolateChannelDelays = false;
opts.equalizerMode = 'mmse';
opts.normalizeEqualizerOutput = true;

% Only GMSK selects this branch; other modulation implementations are not
% modified by this script.
opts.GMSKDetectionMode = 'legacy-frame-reset';

opts.showFigures = false;
opts.showPipelineFigure = false;
opts.showDamageBudgetFigure = false;
opts.showPowerFigure = false;
opts.debugGMSK = false;
opts.debugCodedBoundary = false;
opts.debugPerFrameBERSummary = true;
opts.debugAllPerFrameBER = false;
opts.randomSeed = 20260716;
opts.clearFunctionCache = true;

fprintf('\n===== STAGE 1: GMSK FRAME-RESET, CHANNELDATA_5..8 =====\n');
T = sweep_h_channel_short_frames(opts);

% FER in the production table is calculated only from matched frames.
% Build a loss-aware metric where an unmatched frame also counts as a
% failure.  The matching NoH case supplies the expected counted-frame
% count after acquisition/warm-up for each coding configuration.
n = height(T);
T.ExpectedCountedFrames = nan(n, 1);
T.UnlockedFrames = nan(n, 1);
T.BadMatchedFrames = nan(n, 1);
T.EffectiveFailedFrames = nan(n, 1);
T.EffectiveFER_pct = nan(n, 1);
T.GoodFrames = nan(n, 1);

scenario = string(T.Scenario);
coding = string(T.ChannelCoding);
rate = string(T.Rate);
noH = scenario == "NoH_baseline";

for rowIndex = 1:n
    referenceIndex = find(noH & ...
        coding == coding(rowIndex) & rate == rate(rowIndex), 1, 'first');
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

summaryPath = fullfile(outputDir, 'gmsk_models_5_8_screen_summary.csv');
matPath = fullfile(outputDir, 'gmsk_models_5_8_screen_results.mat');
writetable(T, summaryPath);
save(matPath, 'T', 'opts', 'modelFiles');

keyColumns = {'Scenario','ChannelCoding','Rate','BER','LockRate_pct','FER', ...
    'UnlockedFrames','BadMatchedFrames','EffectiveFER_pct','GoodFrames', ...
    'WaveformDuration_s','HSourceDuration_s','ExceedsHDuration', ...
    'Success','Status'};
keyColumns = keyColumns(ismember(keyColumns, T.Properties.VariableNames));

fprintf('\n===== STAGE-1 KEY RESULTS =====\n');
disp(T(:, keyColumns));

hRows = ~noH;
infrastructureBad = ~T.Success | T.ExceedsHDuration;
needsFollowUp = hRows & ~infrastructureBad & ...
    (T.LockRate_pct < 99 | T.EffectiveFER_pct > 5);

fprintf('\nInfrastructure failures / H-duration overruns: %d\n', ...
    nnz(infrastructureBad));
fprintf('H cases needing focused follow-up (Lock < 99%% or effective FER > 5%%): %d/%d\n', ...
    nnz(needsFollowUp), nnz(hRows));
if any(needsFollowUp)
    disp(T(needsFollowUp, keyColumns));
end

fprintf('Summary CSV: %s\n', summaryPath);
fprintf('Results MAT: %s\n', matPath);

assignin('base', 'gmskModels58Screen', T);
