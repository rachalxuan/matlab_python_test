function T = run_tm_dualiq_triage(channelFilePath, userOpts)
%RUN_TM_DUALIQ_TRIAGE Run six paired-seed dual-I/Q diagnostic configs.
%
% The plan contains 6 transmitter/data-path configurations x 4 channel
% profiles = 24 cases.  Cases that differ only by channel profile receive
% the same deterministic seed.
%
% Example:
%   channelFile = ...
%       'E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat';
%   opts = struct('RunId','tm_dualiq_triage_v1','Resume',true);
%   T = run_tm_dualiq_triage(channelFile, opts);

    if nargin < 1 || isempty(channelFilePath)
        channelFilePath = ...
            'E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat';
    end
    if nargin < 2 || isempty(userOpts)
        userOpts = struct();
    end
    if ~isstruct(userOpts) || ~isscalar(userOpts)
        error('run_tm_dualiq_triage:InvalidOptions', ...
            'userOpts must be one scalar struct.');
    end

    channelFilePath = char(string(channelFilePath));
    if exist(channelFilePath, 'file') ~= 2
        error('run_tm_dualiq_triage:MissingChannelFile', ...
            'H-matrix channel file not found: %s', channelFilePath);
    end

    noHExtra = struct( ...
        'enableHChannel', false, ...
        'enableEqualizer', false);
    hExtra = struct( ...
        'enableHChannel', true, ...
        'HMode', 'h_matrix_file', ...
        'channelFilePath', channelFilePath, ...
        'channelInterpolationMethod', 'linear', ...
        'channelOutOfRangeMode', 'wrap', ...
        'interpolateChannelDelays', false, ...
        'normalizeHChannel', false, ...
        'enableEqualizer', true, ...
        'equalizerMode', 'mmse', ...
        'normalizeEqualizerOutput', true);

    profiles = struct( ...
        'Name',{},'SNR',{},'CFO',{},'PhaseOffset',{},'Delay',{},'Extra',{});
    profiles(end+1) = localProfile( ... %#ok<AGROW>
        "noH_clean", 100, 0, 0, 0, noHExtra);
    profiles(end+1) = localProfile( ... %#ok<AGROW>
        "noH_sync", 30, 20000, 10, 0.2, noHExtra);
    profiles(end+1) = localProfile( ... %#ok<AGROW>
        "H_mmse_clean", 100, 0, 0, 0, hExtra);
    profiles(end+1) = localProfile( ... %#ok<AGROW>
        "H_mmse_sync", 30, 20000, 10, 0.2, hExtra);

    randomizerOff = struct( ...
        'Label',"off",'Enabled',false,'Position',"afterEncoding");
    debugOverrides = struct( ...
        'splitPathDebug', true, ...
        'debugASMPhase', true, ...
        'debugCodedBoundary', true, ...
        'debugPerFrameBERSummary', true, ...
        'debugPerFrameBERFormat', 'scientific', ...
        'debugPerFrameBERNonzeroCount', 32, ...
        'showFigures', false);

    opts = struct();
    opts.RunId = 'tm_dualiq_triage_v1';
    opts.OutputDir = '';
    opts.Resume = true;
    opts.RerunFailed = false;
    opts.BaseSeed = 20260730;
    opts.MaxNewCases = Inf;
    opts.DryRun = false;
    opts.FailOnFailure = false;
    opts.Verbose = true;
    opts.SymbolRate = 1e6;
    opts.SamplesPerSymbol = 8;
    opts.BERWarmUpFrames = 8;
    opts.BERFrames = 24;
    opts.DataPathModes = {'dualIQ'};
    opts.DualIQModulations = {'8PSK','16QAM','32QAM'};
    opts.SingleExtraModulations = {};
    opts.ConvolutionalRates = {'1/2','3/4','7/8'};
    opts.LDPCRates = {};
    opts.TurboRates = {};
    opts.RandomizerCases = randomizerOff;
    opts.ChannelProfiles = profiles;
    opts.IncludeOrdinaryTMAPSK = false;
    opts.SplitPathDebug = true;
    opts.EvaluationOverrides = debugOverrides;
    opts.CaseIds = localRepresentativeCaseIds();
    opts.SelectedOnlyPlan = true;
    opts.SeedMode = 'pairedChannelProfile';

    opts = localApplyUserOptions(opts, userOpts);
    T = run_tm_data_path_sweep("deep", opts);
    localPrintSeedPairing(T);
end

function profile = localProfile(name, snr, cfo, phaseOffset, delay, extra)
    profile = struct( ...
        'Name',string(name), ...
        'SNR',double(snr), ...
        'CFO',double(cfo), ...
        'PhaseOffset',double(phaseOffset), ...
        'Delay',double(delay), ...
        'Extra',extra);
end

function ids = localRepresentativeCaseIds()
    baseIds = [
        "tm.path.dualiq.8psk.none.random.off"
        "tm.path.dualiq.8psk.convolutional.1.2.random.off"
        "tm.path.dualiq.16qam.none.random.off"
        "tm.path.dualiq.16qam.convolutional.7.8.random.off"
        "tm.path.dualiq.32qam.none.random.off"
        "tm.path.dualiq.32qam.convolutional.3.4.random.off"
    ];
    profileIds = [
        "noh.clean"
        "noh.sync"
        "h.mmse.clean"
        "h.mmse.sync"
    ];

    ids = strings(numel(baseIds) * numel(profileIds), 1);
    n = 0;
    for iProfile = 1:numel(profileIds)
        for iCase = 1:numel(baseIds)
            n = n + 1;
            ids(n) = baseIds(iCase) + "." + profileIds(iProfile);
        end
    end
end

function opts = localApplyUserOptions(opts, userOpts)
    allowed = [ ...
        "RunId","OutputDir","Resume","RerunFailed","BaseSeed", ...
        "MaxNewCases","DryRun","FailOnFailure","Verbose", ...
        "BERWarmUpFrames","BERFrames"];
    names = fieldnames(userOpts);
    for k = 1:numel(names)
        name = string(names{k});
        if ~any(name == allowed)
            error('run_tm_dualiq_triage:UnknownOption', ...
                'Unsupported triage option "%s".', char(name));
        end
        opts.(char(name)) = userOpts.(char(name));
    end
end

function localPrintSeedPairing(T)
    if isempty(T) || ~ismember('Seed', T.Properties.VariableNames) || ...
            ~any(isfinite(T.Seed))
        return;
    end

    keys = lower(T.Modulation) + "|" + lower(T.Coding) + "|" + ...
        lower(T.Rate) + "|" + string(T.RandomizerEnabled) + "|" + ...
        lower(T.RandomizerFECPosition);
    uniqueKeys = unique(keys, 'stable');
    pairedGroups = 0;
    for k = 1:numel(uniqueKeys)
        mask = keys == uniqueKeys(k);
        seeds = unique(T.Seed(mask & isfinite(T.Seed)));
        if numel(seeds) == 1 && nnz(mask) == 4
            pairedGroups = pairedGroups + 1;
        end
    end
    fprintf('[tm_dualiq_triage] paired seed groups: %d/%d (expected 6/6)\n', ...
        pairedGroups, numel(uniqueKeys));
end
