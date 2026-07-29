%% RUN_GMSK_OFFICIAL_VITERBI_LONG_CONFIRM
% One reusable entry point for the complete official-GMSK coding sweep.
%
% Select a stage from the MATLAB command line, then run this same script:
%
%   gmskTestStage = 'noh-impairments';
%   run('E:\web_code\react\fft_project\react-fft\src\python\debug\run_gmsk_official_viterbi_long_confirm.m');
%
%   gmskTestStage = 'representative-h';
%   run('E:\web_code\react\fft_project\react-fft\src\python\debug\run_gmsk_official_viterbi_long_confirm.m');
%
%   gmskTestStage = 'all-h';
%   run('E:\web_code\react\fft_project\react-fft\src\python\debug\run_gmsk_official_viterbi_long_confirm.m');
%
% Optional quick screening (2 warm-up + 4 counted frames):
%
%   gmskQuickMode = true;
%
% Leave gmskQuickMode false for the 10 + 30 frame confirmation run.
%
% Covered coding families/rates:
%   none
%   convolutional: 1/2, 2/3, 3/4, 5/6, 7/8
%   ordinary TM LDPC: 1/2, 2/3, 4/5, 7/8
%   Turbo: 1/2, 1/3, 1/4, 1/6
%   TPC: 1/2 x 8 blocks, 2/3 x 4 blocks
%
% RS, concatenated RS+convolutional, and LDPC-on-SMTF are intentionally not
% included: the official GMSK entry currently rejects those layouts instead
% of silently falling back to the legacy detector.

rng(20260724, 'twister');

if ~exist('gmskTestStage', 'var') || isempty(gmskTestStage)
    gmskTestStage = 'noh-impairments';
end
if ~exist('gmskQuickMode', 'var') || isempty(gmskQuickMode)
    gmskQuickMode = false;
end

testStage = lower(string(gmskTestStage));
quickMode = logical(gmskQuickMode);

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';
allModelFiles = { ...
    'default_ChannelData',    fullfile(channelDir, 'ChannelData.mat'); ...
    'std2_likely_TDL',        fullfile(channelDir, '2-ChannelData.mat'); ...
    'std3_likely_CDL',        fullfile(channelDir, '3-ChannelData.mat'); ...
    'std4_likely_ITU_P681',   fullfile(channelDir, '4-ChannelData.mat'); ...
    'std5_likely_Jakes',      fullfile(channelDir, 'ChannelData_5.mat'); ...
    'std6_likely_CLoo',       fullfile(channelDir, 'ChannelData_6.mat'); ...
    'std7_likely_Corazza',    fullfile(channelDir, 'ChannelData_7.mat'); ...
    'std8_likely_Lutz',       fullfile(channelDir, 'ChannelData_8.mat')  ...
};

impairmentProfiles = localAllImpairmentProfiles();
switch testStage
    case "noh-impairments"
        modelFiles = cell(0, 2);
        runProfiles = impairmentProfiles;
        includeHEqualized = false;

    case "representative-h"
        % Corazza is retained as the representative deep-fading case because
        % it was the original weak GMSK scenario in this project.
        modelFiles = allModelFiles(7, :);
        runProfiles = impairmentProfiles;
        includeHEqualized = true;

    case "all-h"
        modelFiles = allModelFiles;
        % Keep the final matrix attributable to H alone.  CFO/phase/delay
        % margins are established in the two earlier stages.
        runProfiles = impairmentProfiles(1);
        includeHEqualized = true;

    otherwise
        error('run_gmsk_official_viterbi_long_confirm:InvalidStage', ...
            ['Unknown gmskTestStage="%s". Use noh-impairments, ', ...
             'representative-h, or all-h.'], char(testStage));
end

for fileIndex = 1:size(modelFiles, 1)
    assert(isfile(modelFiles{fileIndex, 2}), ...
        'Channel file was not found: %s', modelFiles{fileIndex, 2});
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
outputDir = fullfile(srcPythonDir, 'sweep_results', ...
    sprintf('gmsk_full_coding_%s_%s', char(testStage), stamp));
if ~isfolder(outputDir), mkdir(outputDir); end

baseOpts = struct();
baseOpts.hModelCases = modelFiles;
baseOpts.modTypes = {'GMSK'};
baseOpts.convRates = {'1/2','2/3','3/4','5/6','7/8'};
baseOpts.includeLDPC = true;
baseOpts.ldpcRates = {'1/2','2/3','4/5','7/8'};
baseOpts.includeTurbo = true;
baseOpts.turboRates = {'1/2','1/3','1/4','1/6'};
baseOpts.includeTPC = true;
baseOpts.tpcCases = { ...
    struct('TPCCodeRate','1/2','TPCBlocksPerTF',8), ...
    struct('TPCCodeRate','2/3','TPCBlocksPerTF',4)};

baseOpts.includeNoHBaseline = true;
baseOpts.includeHEqualized = includeHEqualized;
baseOpts.includeNormHScenario = false;
baseOpts.includeNoEqualizerScenario = false;

baseOpts.symbolRate = 20e6;
baseOpts.sps = 8;
baseOpts.snr = 30;
baseOpts.noisePlacement = 'afterChannel';
baseOpts.noisePSDdBmHz = [];
baseOpts.noiseBandwidthHz = [];
baseOpts.gmskBT = 0.5;
baseOpts.hasASM = true;
baseOpts.RandomizerEnabled = true;
baseOpts.RandomizerFECPosition = 'afterEncoding';
baseOpts.DataPathMode = 'single';
baseOpts.GMSKDetectionMode = 'official-viterbi-frame-reset';

if quickMode
    baseOpts.berWarmUpFrames = 2;
    baseOpts.berFrames = 4;
else
    baseOpts.berWarmUpFrames = 10;
    baseOpts.berFrames = 30;
end

baseOpts.channelOutOfRangeMode = 'error';
baseOpts.channelInterpolationMethod = 'linear';
baseOpts.interpolateChannelDelays = false;
baseOpts.equalizerMode = 'mmse';
baseOpts.normalizeEqualizerOutput = true;

baseOpts.showFigures = false;
baseOpts.showPipelineFigure = false;
baseOpts.showDamageBudgetFigure = false;
baseOpts.showPowerFigure = false;
baseOpts.debugGMSK = false;
baseOpts.debugCodedBoundary = false;
baseOpts.debugPerFrameBERSummary = true;
baseOpts.debugAllPerFrameBER = false;
baseOpts.randomSeed = 20260724;
baseOpts.clearFunctionCache = true;

codingCasesPerScenario = 1 + numel(baseOpts.convRates) + ...
    numel(baseOpts.ldpcRates) + numel(baseOpts.turboRates) + ...
    numel(baseOpts.tpcCases);
scenarioCount = 1 + double(includeHEqualized) * size(modelFiles, 1);
plannedCases = codingCasesPerScenario * scenarioCount * numel(runProfiles);

fprintf('\n===== OFFICIAL GMSK COMPLETE CODING SWEEP =====\n');
fprintf('Stage             : %s\n', char(testStage));
fprintf('Quick mode        : %d\n', quickMode);
fprintf('Coding cases      : %d per scenario\n', codingCasesPerScenario);
fprintf('Channel scenarios : %d\n', scenarioCount);
fprintf('Damage profiles   : %d\n', numel(runProfiles));
fprintf('Planned cases     : %d\n', plannedCases);
fprintf('Output directory  : %s\n', outputDir);

tables = cell(numel(runProfiles), 1);
profileOpts = cell(numel(runProfiles), 1);
for profileIndex = 1:numel(runProfiles)
    profile = runProfiles(profileIndex);
    opts = baseOpts;
    opts.snr = profile.SNR_dB;
    opts.cfo = profile.CFO_Hz;
    opts.phaseOffset = profile.Phase_deg;
    opts.delay = profile.Delay;
    opts.outputDir = fullfile(outputDir, char(profile.Name));
    profileOpts{profileIndex} = opts;

    fprintf('\n===== PROFILE %d/%d: %s =====\n', ...
        profileIndex, numel(runProfiles), char(profile.Name));
    fprintf('SNR=%.1f dB, CFO=%+.1f Hz, phase=%+.1f deg, delay=%.3f\n', ...
        profile.SNR_dB, profile.CFO_Hz, profile.Phase_deg, profile.Delay);

    Ti = sweep_h_channel_short_frames(opts);
    Ti.TestStage = repmat(testStage, height(Ti), 1);
    Ti.ImpairmentProfile = repmat(profile.Name, height(Ti), 1);
    Ti.InputCFO_Hz = repmat(profile.CFO_Hz, height(Ti), 1);
    Ti.InputPhase_deg = repmat(profile.Phase_deg, height(Ti), 1);
    Ti.InputDelay = repmat(profile.Delay, height(Ti), 1);
    Ti = localAddLossAwareMetrics(Ti);
    tables{profileIndex} = Ti;
end

T = vertcat(tables{:});
T.ExceedsTrustedOneSecond = false(height(T), 1);
hRows = logical(T.HEnabled);
T.ExceedsTrustedOneSecond(hRows) = ...
    T.WaveformDuration_s(hRows) > 1.0;

summaryPath = fullfile(outputDir, 'gmsk_full_coding_summary.csv');
matPath = fullfile(outputDir, 'gmsk_full_coding_results.mat');
writetable(T, summaryPath);
save(matPath, 'T', 'baseOpts', 'profileOpts', 'runProfiles', ...
    'modelFiles', 'allModelFiles', 'testStage', 'quickMode');

invalidResult = ~isfinite(T.BER) | T.BER < 0;
detectorMismatch = string(T.GMSKDetectorUsed) ~= "official";
infrastructureBad = ~T.Success | T.ExceedsHDuration | ...
    T.ExceedsTrustedOneSecond | invalidResult | detectorMismatch;
performanceBad = ~infrastructureBad & ...
    (T.BER > 1e-3 | T.LockRate_pct < 90 | T.EffectiveFER_pct > 10);
badRows = infrastructureBad | performanceBad;

keyColumns = {'TestStage','ImpairmentProfile','Scenario', ...
    'ChannelCoding','Rate','BER','LockRate_pct','FER', ...
    'EffectiveFER_pct','CountedFrames','MatchedFrames', ...
    'GMSKDetectorUsed','WaveformDuration_s','ExceedsHDuration', ...
    'ExceedsTrustedOneSecond','Success','Status','ErrorMessage'};
keyColumns = keyColumns(ismember(keyColumns, T.Properties.VariableNames));

fprintf('\n===== OFFICIAL GMSK COMPLETE CODING SUMMARY =====\n');
fprintf('Completed rows              : %d/%d\n', height(T), plannedCases);
fprintf('Infrastructure/duration bad : %d\n', nnz(infrastructureBad));
fprintf('Performance threshold bad   : %d\n', nnz(performanceBad));
fprintf('Official detector rows      : %d/%d\n', ...
    nnz(string(T.GMSKDetectorUsed) == "official"), height(T));
if any(badRows)
    fprintf('\nRows requiring attention:\n');
    disp(T(badRows, keyColumns));
else
    fprintf('All rows passed the configured screening thresholds.\n');
end
fprintf('Summary CSV: %s\n', summaryPath);
fprintf('Results MAT: %s\n', matPath);

assignin('base', 'officialGMSKFullCodingResults', T);
assignin('base', 'officialGMSKFullCodingOutputDir', outputDir);

function profiles = localAllImpairmentProfiles()
    profiles = repmat(struct( ...
        'Name', "", 'SNR_dB', 30, 'CFO_Hz', 0, ...
        'Phase_deg', 0, 'Delay', 0), 4, 1);

    profiles(1) = struct( ...
        'Name', "baseline", ...
        'SNR_dB', 30, 'CFO_Hz', 0, ...
        'Phase_deg', 0, 'Delay', 0);
    profiles(2) = struct( ...
        'Name', "phase_90deg", ...
        'SNR_dB', 30, 'CFO_Hz', 0, ...
        'Phase_deg', 90, 'Delay', 0);
    profiles(3) = struct( ...
        'Name', "cfo_p2k_phase_30deg", ...
        'SNR_dB', 30, 'CFO_Hz', 2e3, ...
        'Phase_deg', 30, 'Delay', 0);
    profiles(4) = struct( ...
        'Name', "combined_cfo_m5k_phase_90_delay_0p25", ...
        'SNR_dB', 30, 'CFO_Hz', -5e3, ...
        'Phase_deg', 90, 'Delay', 0.25);
end

function T = localAddLossAwareMetrics(T)
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
            coding == coding(rowIndex) & rate == rate(rowIndex), ...
            1, 'first');
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
