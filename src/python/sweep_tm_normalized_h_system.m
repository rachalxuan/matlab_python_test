function [T, S] = sweep_tm_normalized_h_system(userOpts)
%SWEEP_TM_NORMALIZED_H_SYSTEM Full ordinary-TM normalized-H system matrix.
%   This wrapper keeps every inner sweep independently resumable while
%   covering modulation, representative coding rates, randomizer on/off,
%   and the implemented combined/split information paths.
%
%   The default matrix uses NoH plus seven normalized-H scenarios. It does
%   not run raw-H link-budget cases; set useRawH=true only after the
%   normalized-H receiver matrix is understood.
%
%   Example:
%     o = struct('outputDir','E:/.../tm_system_normh_v1');
%     [T,S] = sweep_tm_normalized_h_system(o);

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);
    opts = localDefaults(thisDir);
    opts = localMerge(opts, userOpts);

    if isempty(opts.outputDir)
        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        repoRoot = fileparts(fileparts(thisDir));
        opts.outputDir = fullfile(repoRoot, 'artifacts', 'ccsds', ...
            'tm_system_normalized_h', ['tm_system_normalized_h_' stamp]);
    end
    if ~isfolder(opts.outputDir)
        mkdir(opts.outputDir);
    end

    capabilities = tm_data_path_capabilities();
    profiles = localProfiles(opts, capabilities);
    T = table();

    for iProfile = 1:numel(profiles)
        profile = profiles(iProfile);
        if ~isempty(opts.ProfileNames) && ...
                ~any(strcmpi(profile.Name, cellstr(string(opts.ProfileNames))))
            continue;
        end

        fprintf('\n============================================================\n');
        fprintf('[TM system sweep] profile %d/%d: %s\n', ...
            iProfile, numel(profiles), profile.Name);
        fprintf('  path=%s randomizer=%d position=%s mods=%s\n', ...
            profile.DataPathMode, profile.RandomizerEnabled, ...
            profile.RandomizerFECPosition, strjoin(profile.ModTypes, ','));
        fprintf('============================================================\n');

        o = opts;
        o.outputDir = fullfile(opts.outputDir, profile.Name);
        o.RunId = profile.Name; % ignored when outputDir is explicit
        o.DataPathMode = profile.DataPathMode;
        o.RandomizerEnabled = profile.RandomizerEnabled;
        o.RandomizerFECPosition = profile.RandomizerFECPosition;
        o.modTypes = profile.ModTypes;
        o.includeTPC = opts.includeTPC && strcmpi(profile.DataPathMode, 'single');
        o.clearFunctionCache = opts.clearFunctionCache && iProfile == 1;

        part = sweep_h_channel_short_frames(o);
        part.SystemProfile = repmat(string(profile.Name), height(part), 1);
        if isempty(T)
            T = part;
        else
            T = [T; part]; %#ok<AGROW>
        end

        if ~opts.DryRun
            localWriteTable(T, fullfile(opts.outputDir, ...
                'tm_system_normalized_h_combined.csv'));
            save(fullfile(opts.outputDir, ...
                'tm_system_normalized_h_combined.mat'), 'T', 'opts', 'profiles');
        end
    end

    S = localSummary(T);
    if ~opts.DryRun
        localWriteTable(S, fullfile(opts.outputDir, ...
            'tm_system_normalized_h_summary.csv'));
        coverage = localCoverage(capabilities);
        localWriteTable(coverage, fullfile(opts.outputDir, ...
            'tm_system_split_coverage.csv'));
        fprintf('\n===== TM normalized-H system result =====\n');
        fprintf('Root     : %s\n', opts.outputDir);
        fprintf('Cases    : %d\n', height(T));
        if ~isempty(T)
            fprintf('PASS     : %d\n', nnz(string(T.Status) == "PASS"));
            fprintf('FAIL     : %d\n', nnz(string(T.Status) == "FAIL_METRIC"));
            fprintf('ERROR    : %d\n', nnz(string(T.Status) == "ERROR"));
            fprintf('PENDING  : %d\n', nnz(ismember(string(T.Status), ...
                ["PENDING","RUNNING"])));
        end
        fprintf('Combined : %s\n', fullfile(opts.outputDir, ...
            'tm_system_normalized_h_combined.csv'));
        fprintf('Summary  : %s\n', fullfile(opts.outputDir, ...
            'tm_system_normalized_h_summary.csv'));
        fprintf('Coverage : %s\n', fullfile(opts.outputDir, ...
            'tm_system_split_coverage.csv'));
    end
end

function opts = localDefaults(thisDir)
    opts = struct();
    opts.outputDir = '';
    opts.ProfileNames = {};
    opts.Resume = true;
    opts.RerunFailed = false;
    opts.MaxNewCases = Inf;
    opts.DryRun = false;
    opts.FailOnFailure = false;
    opts.Verbose = true;
    opts.clearFunctionCache = true;

    opts.singleModTypes = { ...
        'BPSK','QPSK','OQPSK','UQPSK','8PSK', ...
        '16QAM','32QAM','16APSK','32APSK','MSK','GMSK'};
    opts.includeDualIQ = true;
    opts.includeUnequalUQPSK = true;
    opts.includeBeforeEncodingRandomizer = true;

    opts.hModelCases = { ...
        'std2_TDL',      'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
        'std3_CDL',      'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
        'std4_ITU_P681', 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
        'std5_Jakes',    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
        'std6_CLoo',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
        'std7_Corazza',  'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
        'std8_Lutz',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};
    opts.includeNoHBaseline = true;
    opts.includeNoHEqualizedBaseline = false;
    opts.includeHEqualized = false;
    opts.includeNormHScenario = true;
    opts.includeNoEqualizerScenario = false;
    opts.useRawH = false;

    opts.includeUncoded = true;
    opts.includeRS = true;
    opts.includeConvolutional = true;
    % Opt-in only. The ordinary full-system matrix keeps its previous case
    % list unless the caller explicitly requests concatenated coding.
    opts.includeConcatenated = false;
    opts.rsInterleavingDepths = 1;
    opts.concatenatedConvRates = {'1/2'};
    opts.concatenatedRSInterleavingDepths = 8;
    opts.includeLDPC = true;
    opts.includeTurbo = true;
    opts.includeTPC = true;
    opts.convRates = {'1/2'};
    opts.ldpcRates = {'1/2'};
    opts.turboRates = {'1/2'};
    opts.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
    opts.ConvolutionalG1G2Mode = 'G1G2-inverted';

    opts.symbolRate = 10e6;
    opts.sps = 8;
    opts.berWarmUpFrames = 8;
    opts.berFrames = 30;
    opts.excludeBERWarmUpFrames = true;
    opts.noisePlacement = 'afterChannel';
    opts.noiseMode = 'psd';
    opts.noisePSDdBmHz = -115.3;
    opts.noiseBandwidthHz = [];
    opts.inputLevelDbm = -10;
    opts.channelOutOfRangeMode = 'wrap';
    opts.equalizerMode = 'blind-cma-lms';
    opts.RandomizerFECPosition = 'afterEncoding';
    opts.WaveformMode = 'ordinaryTM';
    opts.hasASM = true;
    opts.randomSeed = 20260824;
    opts.SeedMode = 'pairedChannelProfile';

    opts.useTMAPSKPilots = false;
    opts.APSKReceiverMode = 'pilotless';
    % Let the evaluator select BPS by channel state: disabled for clean NoH
    % baselines and enabled for H-channel cases.  Forcing true here makes
    % no-scramble dual-IQ 32QAM vulnerable to data-dependent 90-degree
    % window slips even though the underlying NoH constellation is clean.
    opts.enableQAMBlindPhaseSearch = [];
    opts.enableQAMPowerGainTracker = true;
    opts.GMSKDetectionMode = 'official-viterbi-frame-reset';

    opts.maxGoodBER = 1e-5;
    opts.maxGoodFER = 0;
    opts.minGoodLockPct = 90;
    opts.minGoodMERdB = 18;
    opts.minCountedFrames = 1;
    opts.showFigures = false;

    if exist(fullfile(thisDir, 'sweep_h_channel_short_frames.m'), 'file') ~= 2
        error('sweep_tm_normalized_h_system:MissingInnerSweep', ...
            'sweep_h_channel_short_frames.m is missing.');
    end
end

function profiles = localProfiles(opts, capabilities)
    randomizers = struct( ...
        'Name', {'scramble_off','scramble_after'}, ...
        'Enabled', {false,true}, ...
        'Position', {'afterEncoding','afterEncoding'});
    if opts.includeBeforeEncodingRandomizer
        randomizers(end+1) = struct( ...
            'Name','scramble_before', 'Enabled',true, ...
            'Position','beforeEncoding'); %#ok<AGROW>
    end

    pathDefs = struct('Name',{},'Mode',{},'Mods',{});
    pathDefs(end+1) = struct('Name','combined','Mode','single', ...
        'Mods',{cellstr(string(opts.singleModTypes))}); %#ok<AGROW>
    if opts.includeDualIQ
        pathDefs(end+1) = struct('Name','split','Mode','dualIQ', ...
            'Mods',{cellstr(capabilities.SupportedModulations)}); %#ok<AGROW>
    end
    if opts.includeUnequalUQPSK
        pathDefs(end+1) = struct('Name','split_uqpsk','Mode','unequalDualIQ', ...
            'Mods',{{'UQPSK'}}); %#ok<AGROW>
    end

    profiles = struct('Name',{},'DataPathMode',{}, ...
        'RandomizerEnabled',{},'RandomizerFECPosition',{},'ModTypes',{});
    for iPath = 1:numel(pathDefs)
        for iRand = 1:numel(randomizers)
            profiles(end+1) = struct( ... %#ok<AGROW>
                'Name', [pathDefs(iPath).Name '_' randomizers(iRand).Name], ...
                'DataPathMode', pathDefs(iPath).Mode, ...
                'RandomizerEnabled', randomizers(iRand).Enabled, ...
                'RandomizerFECPosition', randomizers(iRand).Position, ...
                'ModTypes', {pathDefs(iPath).Mods});
        end
    end
end

function S = localSummary(T)
    if isempty(T)
        S = table();
        return;
    end
    keys = unique(T(:, {'SystemProfile','DataPathMode', ...
        'RandomizerEnabled','RandomizerFECPosition'}), 'rows', 'stable');
    rows = cell(height(keys), 9);
    for i = 1:height(keys)
        mask = string(T.SystemProfile) == string(keys.SystemProfile(i));
        status = string(T.Status(mask));
        rows(i,:) = {keys.SystemProfile(i), keys.DataPathMode(i), ...
            keys.RandomizerEnabled(i), keys.RandomizerFECPosition(i), ...
            nnz(mask), nnz(status == "PASS"), ...
            nnz(status == "FAIL_METRIC"), nnz(status == "ERROR"), ...
            nnz(ismember(status, ["PENDING","RUNNING"]))};
    end
    S = cell2table(rows, 'VariableNames', { ...
        'SystemProfile','DataPathMode','RandomizerEnabled', ...
        'RandomizerFECPosition','Total','Pass','FailMetric','Error','Pending'});
end

function coverage = localCoverage(capabilities)
    mods = string(capabilities.AllOrdinaryTMModulations(:));
    status = repmat("combined-only", numel(mods), 1);
    status(ismember(mods, capabilities.SupportedModulations)) = ...
        "combined-and-dualIQ";
    status(mods == capabilities.UnequalDualIQ.Modulation) = ...
        "combined-and-unequalDualIQ";
    coverage = table(mods, status, ...
        'VariableNames', {'ModType','ImplementedPathCoverage'});
end

function opts = localMerge(opts, userOpts)
    if ~isstruct(userOpts)
        error('sweep_tm_normalized_h_system:InvalidOptions', ...
            'userOpts must be a struct.');
    end
    names = fieldnames(userOpts);
    for i = 1:numel(names)
        opts.(names{i}) = userOpts.(names{i});
    end
    if opts.useRawH
        opts.includeHEqualized = true;
        opts.includeNormHScenario = false;
    end
end

function localWriteTable(T, path)
    parent = fileparts(path);
    if ~isfolder(parent)
        mkdir(parent);
    end
    writetable(T, path);
end
