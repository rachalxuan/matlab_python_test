function T = run_tm_data_path_sweep(profile, userOpts)
%RUN_TM_DATA_PATH_SWEEP Check ordinary-TM single/dualIQ data paths.
%
% Short planning check (does not execute simulations):
%   T = run_tm_data_path_sweep("smoke", struct('DryRun',true));
%
% Run at most five new cases and save a resumable checkpoint:
%   opts = struct('RunId','smoke_local','MaxNewCases',5);
%   T = run_tm_data_path_sweep("smoke", opts);
%
% Resume the same run:
%   opts = struct('RunId','smoke_local','Resume',true);
%   T = run_tm_data_path_sweep("smoke", opts);

    if nargin < 1 || isempty(profile)
        profile = "smoke";
    end
    if nargin < 2 || isempty(userOpts)
        userOpts = struct();
    end
    if ~isstruct(userOpts)
        error('run_tm_data_path_sweep:InvalidOptions', ...
            'userOpts must be a struct.');
    end

    profile = lower(string(profile));
    thisDir = fileparts(mfilename('fullpath'));
    regressionDir = fullfile(thisDir, 'regression');
    addpath(thisDir);
    addpath(regressionDir);

    cfg = localConfig(profile, userOpts);
    cases = localBuildCases(cfg);
    runnerCaseIds = cfg.CaseIds;
    if cfg.SelectedOnlyPlan
        [cases, runnerCaseIds] = localSelectOnlyRequestedCases( ...
            cases, cfg.CaseIds);
    end

    runnerOpts = struct( ...
        'OutputDir', cfg.OutputDir, ...
        'RunId', cfg.RunId, ...
        'PlanVersion', "tm-data-path-v3-" + cfg.Profile + "-" + ...
            lower(string(cfg.SeedMode)), ...
        'Resume', cfg.Resume, ...
        'MaxNewCases', cfg.MaxNewCases, ...
        'RerunFailed', cfg.RerunFailed, ...
        'BaseSeed', cfg.BaseSeed, ...
        'SeedMode', cfg.SeedMode, ...
        'CaseIds', runnerCaseIds, ...
        'DryRun', cfg.DryRun, ...
        'FailOnFailure', cfg.FailOnFailure, ...
        'Verbose', cfg.Verbose);

    [T, state] = reg_run_cases("tm_data_path", cases, runnerOpts);
    T = localAttachMetadata(T, cases, state);

    if ~cfg.DryRun
        summaryPath = fullfile(char(state.OutputDir), 'tm_data_path_summary.csv');
        localWriteTable(T, summaryPath);
    end
end

function cfg = localConfig(profile, userOpts)
    cfg = struct( ...
        'Profile', profile, ...
        'OutputDir', '', ...
        'RunId', char(profile + "_v1"), ...
        'Resume', true, ...
        'MaxNewCases', Inf, ...
        'RerunFailed', false, ...
        'BaseSeed', 20260729, ...
        'SeedMode', 'pairedChannelProfile', ...
        'CaseIds', strings(0,1), ...
        'SelectedOnlyPlan', false, ...
        'DryRun', false, ...
        'FailOnFailure', false, ...
        'Verbose', true, ...
        'SymbolRate', 1e6, ...
        'SamplesPerSymbol', 4, ...
        'RolloffFactor', 0.35, ...
        'BERWarmUpFrames', 6, ...
        'BERFrames', 16, ...
        'MaxBER', 1e-5, ...
        'MinLockRate', 0.90, ...
        'MaxFER', 1e-5, ...
        'IncludeOrdinaryTMAPSK', true, ...
        'SplitPathDebug', false, ...
        'DataPathModes', {{'single','dualIQ'}}, ...
        'EvaluationOverrides', struct());

    switch profile
        case "smoke"
            cfg.DualIQModulations = {'QPSK','8PSK','32QAM'};
            cfg.SingleExtraModulations = {'BPSK','GMSK'};
            cfg.ConvolutionalRates = {'1/2'};
            cfg.LDPCRates = {'1/2'};
            cfg.TurboRates = {'1/2'};
            cfg.RandomizerCases = localRandomizerCases(false);
            cfg.ChannelProfiles = localChannelProfiles(false);
            cfg.BERWarmUpFrames = 3;
            cfg.BERFrames = 8;
        case "full"
            cfg.DualIQModulations = {'QPSK','OQPSK','8PSK','16QAM','32QAM'};
            cfg.SingleExtraModulations = {'BPSK','GMSK','FM','UQPSK'};
            cfg.ConvolutionalRates = {'1/2','2/3','3/4','5/6','7/8'};
            cfg.LDPCRates = {'1/2'};
            cfg.TurboRates = {'1/2'};
            cfg.RandomizerCases = localRandomizerCases(true);
            cfg.ChannelProfiles = localChannelProfiles(false);
        case "deep"
            cfg.DualIQModulations = {'QPSK','OQPSK','8PSK','16QAM','32QAM'};
            cfg.SingleExtraModulations = {'BPSK','GMSK','FM','UQPSK'};
            cfg.ConvolutionalRates = {'1/2','2/3','3/4','5/6','7/8'};
            cfg.LDPCRates = {'1/2','2/3','4/5'};
            cfg.TurboRates = {'1/2','1/3','1/4','1/6'};
            cfg.RandomizerCases = localRandomizerCases(true);
            cfg.ChannelProfiles = localChannelProfiles(true);
            cfg.BERWarmUpFrames = 8;
            cfg.BERFrames = 24;
        otherwise
            error('run_tm_data_path_sweep:UnknownProfile', ...
                'Unknown profile "%s". Use smoke, full, or deep.', profile);
    end

    names = fieldnames(userOpts);
    for k = 1:numel(names)
        if ~isfield(cfg, names{k})
            error('run_tm_data_path_sweep:UnknownOption', ...
                'Unknown option "%s".', names{k});
        end
        cfg.(names{k}) = userOpts.(names{k});
    end
    cfg.SeedMode = char(string(cfg.SeedMode));
    cfg.SelectedOnlyPlan = logical(cfg.SelectedOnlyPlan);
end

function [cases, runnerCaseIds] = localSelectOnlyRequestedCases(cases, requestedIds)
    requestedIds = string(requestedIds(:));
    if isempty(requestedIds)
        error('run_tm_data_path_sweep:SelectedOnlyWithoutCaseIds', ...
            'SelectedOnlyPlan=true requires nonempty CaseIds.');
    end

    availableIds = string({cases.Id})';
    missingIds = requestedIds(~ismember(requestedIds, availableIds));
    if ~isempty(missingIds)
        error('run_tm_data_path_sweep:UnknownCaseIds', ...
            'Requested CaseIds are not in the current plan:%s%s', ...
            newline, strjoin(missingIds, newline));
    end

    cases = cases(ismember(availableIds, requestedIds));
    runnerCaseIds = strings(0,1);
end

function randomizers = localRandomizerCases(includeBeforeEncoding)
    randomizers = struct('Label',{},'Enabled',{},'Position',{});
    randomizers(end+1) = struct( ...
        'Label',"off",'Enabled',false,'Position',"afterEncoding");
    randomizers(end+1) = struct( ...
        'Label',"after",'Enabled',true,'Position',"afterEncoding");
    if includeBeforeEncoding
        randomizers(end+1) = struct( ...
            'Label',"before",'Enabled',true,'Position',"beforeEncoding");
    end
end

function profiles = localChannelProfiles(includeClean)
    profiles = struct( ...
        'Name',{},'SNR',{},'CFO',{},'PhaseOffset',{},'Delay',{},'Extra',{});
    if includeClean
        profiles(end+1) = struct( ...
            'Name',"clean",'SNR',35,'CFO',0,'PhaseOffset',0,'Delay',0, ...
            'Extra',struct('enableHChannel',false));
    end
    profiles(end+1) = struct( ...
        'Name',"sync",'SNR',30,'CFO',2000,'PhaseOffset',10,'Delay',0.2, ...
        'Extra',struct('enableHChannel',false));
end

function cases = localBuildCases(cfg)
    cases = localEmptyCases();
    mainCoding = localMainCodingCases(cfg);
    singleCoding = localSingleOnlyCodingCases();

    for iProfile = 1:numel(cfg.ChannelProfiles)
        channel = cfg.ChannelProfiles(iProfile);

        for iMod = 1:numel(cfg.DualIQModulations)
            modulation = cfg.DualIQModulations{iMod};
            for iPathMode = 1:numel(cfg.DataPathModes)
                pathMode = char(string(cfg.DataPathModes{iPathMode}));
                if ~any(strcmpi(pathMode, {'single','dualIQ','unequalDualIQ'}))
                    error('run_tm_data_path_sweep:InvalidDataPathMode', ...
                        'DataPathModes contains unsupported value "%s".', pathMode);
                end
                if strcmpi(pathMode, 'unequalDualIQ') && ...
                        ~strcmpi(string(modulation), "UQPSK")
                    error('run_tm_data_path_sweep:InvalidUnequalIQCombination', ...
                        'unequalDualIQ currently supports only Modulation="UQPSK".');
                end
                if strcmpi(pathMode, 'dualIQ') && ...
                        strcmpi(string(modulation), "UQPSK")
                    error('run_tm_data_path_sweep:UQPSKRequiresUnequalIQ', ...
                        ['UQPSK cannot use DataPathMode="dualIQ". ', ...
                         'Use DataPathMode="unequalDualIQ".']);
                end
                for iCoding = 1:numel(mainCoding)
                    coding = mainCoding(iCoding);
                    for iRandomizer = 1:numel(cfg.RandomizerCases)
                        randomizer = cfg.RandomizerCases(iRandomizer);
                        cases(end+1,1) = localMakeCase( ... %#ok<AGROW>
                            cfg, channel, pathMode, modulation, ...
                            coding, randomizer);
                    end
                end
            end
        end

        includesSinglePath = any(strcmpi( ...
            string(cfg.DataPathModes), "single"));
        if includesSinglePath
            singleMods = [{'QPSK'}, cfg.SingleExtraModulations];
            for iMod = 1:numel(singleMods)
                modulation = singleMods{iMod};
                for iCoding = 1:numel(singleCoding)
                    coding = singleCoding(iCoding);
                    for iRandomizer = 1:numel(cfg.RandomizerCases)
                        randomizer = cfg.RandomizerCases(iRandomizer);
                        if strcmpi(coding.Coding, 'TPC') && randomizer.Enabled
                            continue;
                        end
                        cases(end+1,1) = localMakeCase( ... %#ok<AGROW>
                            cfg, channel, 'single', modulation, coding, randomizer);
                    end
                end
            end
        end

        if includesSinglePath && cfg.IncludeOrdinaryTMAPSK
            apskMods = {'16APSK','32APSK'};
            noCoding = localCodingCase('none', '-', struct());
            randomizer = struct( ...
                'Label',"off",'Enabled',false,'Position',"afterEncoding");
            for iMod = 1:numel(apskMods)
                cases(end+1,1) = localMakeCase( ... %#ok<AGROW>
                    cfg, channel, 'single', apskMods{iMod}, noCoding, randomizer);
            end
        end
    end
end

function cases = localEmptyCases()
    cases = struct('Id',{},'Name',{},'Category',{}, ...
        'Params',{},'Expected',{},'Meta',{});
end

function codingCases = localMainCodingCases(cfg)
    codingCases = struct('Coding',{},'Rate',{},'Extra',{});
    codingCases(end+1) = localCodingCase('none', '-', struct());
    codingCases(end+1) = localCodingCase('RS', '223/255', ...
        struct('RSMessageLength',223,'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false));
    for k = 1:numel(cfg.ConvolutionalRates)
        rate = cfg.ConvolutionalRates{k};
        codingCases(end+1) = localCodingCase('convolutional', rate, ... %#ok<AGROW>
            struct('ConvolutionalCodeRate',rate));
    end
    for k = 1:numel(cfg.LDPCRates)
        rate = cfg.LDPCRates{k};
        informationBits = 1024;
        if strcmp(rate, '7/8')
            informationBits = 7136;
        end
        codingCases(end+1) = localCodingCase('LDPC', rate, ... %#ok<AGROW>
            struct('CodeRate',rate,'NumBitsInInformationBlock',informationBits, ...
            'IsLDPCOnSMTF',false));
    end
    for k = 1:numel(cfg.TurboRates)
        rate = cfg.TurboRates{k};
        codingCases(end+1) = localCodingCase('turbo', rate, ... %#ok<AGROW>
            struct('CodeRate',rate,'NumBitsInInformationBlock',1784));
    end
end

function codingCases = localSingleOnlyCodingCases()
    codingCases = struct('Coding',{},'Rate',{},'Extra',{});
    codingCases(end+1) = localCodingCase('concatenated', 'RS+conv1/2', ...
        struct('RSMessageLength',223,'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false,'ConvolutionalCodeRate','1/2'));
    codingCases(end+1) = localCodingCase('TPC', '56x56', ...
        struct('TPCCodeRate','56','TPCBlocksPerTF',1,'TPCInterleaver','auto'));
end

function coding = localCodingCase(name, rate, extra)
    coding = struct('Coding',char(name),'Rate',string(rate),'Extra',extra);
end

function caseDef = localMakeCase(cfg, channel, dataPathMode, modulation, coding, randomizer)
    params = struct( ...
        'modType', modulation, ...
        'symbolRate', cfg.SymbolRate, ...
        'sps', cfg.SamplesPerSymbol, ...
        'snr', channel.SNR, ...
        'cfo', channel.CFO, ...
        'phaseOffset', channel.PhaseOffset, ...
        'delay', channel.Delay, ...
        'channelCoding', coding.Coding, ...
        'RolloffFactor', cfg.RolloffFactor, ...
        'hasASM', true, ...
        'RandomizerEnabled', logical(randomizer.Enabled), ...
        'RandomizerFECPosition', char(randomizer.Position), ...
        'DataPathMode', dataPathMode, ...
        'WaveformMode', 'ordinaryTM', ...
        'NumBytesInTransferFrame', localTransferFrameBytes(modulation, coding), ...
        'SpacecraftID', 1, ...
        'VirtualChannelID', 0, ...
        'HasSecondaryHeader', false, ...
        'HasOCF', false, ...
        'HasFECF', false, ...
        'berWarmUpFrames', cfg.BERWarmUpFrames, ...
        'berFrames', cfg.BERFrames, ...
        'showFigures', false, ...
        'splitPathDebug', cfg.SplitPathDebug, ...
        'splitIQPhaseTwoPass', true);
    if strcmpi(dataPathMode, 'unequalDualIQ')
        % UQPSK has unequal I/Q symbol rates.  Keep this branch explicit so
        % ordinary equal-rate dualIQ cases cannot silently enter it.
        params.RRatio = 2;
        params.ARatio = 2;
        params.carrierRecoveryMode = 'uqpsk-teacher';
        params.enableUQPSKFFTCoarseCFO = true;
    end
    params = localMerge(params, cfg.EvaluationOverrides);
    params = localMerge(params, coding.Extra);
    if isfield(channel, 'Extra') && ~isempty(channel.Extra)
        params = localMerge(params, channel.Extra);
    end
    if contains(upper(string(modulation)), 'APSK')
        params.sps = max(8, params.sps);
        params.HasTMAPSKPilots = true;
    end

    name = sprintf('%s_%s_%s_%s_random_%s_%s', ...
        dataPathMode, modulation, coding.Coding, char(coding.Rate), ...
        char(randomizer.Label), char(channel.Name));
    caseId = "tm.path." + localId(name);
    expected = localExpected(cfg, dataPathMode, randomizer);
    meta = struct( ...
        'DataPathMode', string(dataPathMode), ...
        'Modulation', string(modulation), ...
        'Coding', string(coding.Coding), ...
        'Rate', string(coding.Rate), ...
        'RandomizerEnabled', logical(randomizer.Enabled), ...
        'RandomizerFECPosition', string(randomizer.Position), ...
        'ChannelProfile', string(channel.Name), ...
        'SNR_dB', double(channel.SNR), ...
        'CFO_Hz', double(channel.CFO), ...
        'PhaseOffset_deg', double(channel.PhaseOffset), ...
        'Delay_samples', double(channel.Delay), ...
        'HEnabled', localStructLogical(params, 'enableHChannel', false), ...
        'HMode', localStructString(params, 'HMode', "none"), ...
        'EqualizerEnabled', localStructLogical(params, 'enableEqualizer', false), ...
        'EqualizerMode', localStructString(params, 'equalizerMode', "none"));
    caseDef = struct( ...
        'Id', caseId, ...
        'Name', string(name), ...
        'Category', "tm_data_path", ...
        'Params', params, ...
        'Expected', expected, ...
        'Meta', meta);
end

function expected = localExpected(cfg, dataPathMode, randomizer)
    expected = struct( ...
        'RequiredMetrics', ["BER","LockRate"], ...
        'MaxBER', cfg.MaxBER, ...
        'MinLockRate', cfg.MinLockRate, ...
        'MaxFER', cfg.MaxFER, ...
        'MinMERdB', [], ...
        'MinCountedFrames', 1, ...
        'ExpectedDataPathMode', string(dataPathMode), ...
        'ExpectedWaveformMode', "ordinaryTM", ...
        'ExpectedRandomizerFECPosition', string(randomizer.Position), ...
        'ExpectedRandomizerEnabled', logical(randomizer.Enabled), ...
        'ExpectedGMSKDetector', "", ...
        'ExpectedErrorIdentifier', "", ...
        'ExpectedErrorMessage', "");
end

function bytes = localTransferFrameBytes(modulation, coding)
    bytes = 1115;
    if strcmpi(coding.Coding, 'TPC')
        bytes = 392;
    elseif strcmpi(coding.Coding, 'convolutional')
        rate = char(coding.Rate);
        if strcmp(rate, '3/4') && strcmpi(modulation, '32QAM')
            bytes = 1121;
        elseif strcmp(rate, '5/6')
            bytes = 1116;
        elseif strcmp(rate, '7/8')
            bytes = 1123;
        end
    elseif strcmpi(coding.Coding, 'none') && strcmpi(modulation, '32QAM')
        bytes = 1116;
    end
end

function T = localAttachMetadata(T, cases, state)
    n = height(T);
    T.DataPathMode = strings(n,1);
    T.Modulation = strings(n,1);
    T.Coding = strings(n,1);
    T.Rate = strings(n,1);
    T.RandomizerEnabled = false(n,1);
    T.RandomizerFECPosition = strings(n,1);
    T.ChannelProfile = strings(n,1);
    T.SNR_dB = nan(n,1);
    T.CFO_Hz = nan(n,1);
    T.PhaseOffset_deg = nan(n,1);
    T.Delay_samples = nan(n,1);
    T.HEnabled = false(n,1);
    T.HMode = strings(n,1);
    T.EqualizerEnabled = false(n,1);
    T.EqualizerMode = strings(n,1);
    T.LockRate_pct = 100*T.LockRate;
    T.I_LockRate_pct = 100*T.I_LockRate;
    T.Q_LockRate_pct = 100*T.Q_LockRate;
    T.ResidualCFO_Hz = nan(n,1);
    T.WaveformDuration_s = nan(n,1);
    for k = 1:n
        meta = cases(k).Meta;
        T.DataPathMode(k) = meta.DataPathMode;
        T.Modulation(k) = meta.Modulation;
        T.Coding(k) = meta.Coding;
        T.Rate(k) = meta.Rate;
        T.RandomizerEnabled(k) = meta.RandomizerEnabled;
        T.RandomizerFECPosition(k) = meta.RandomizerFECPosition;
        T.ChannelProfile(k) = meta.ChannelProfile;
        T.SNR_dB(k) = meta.SNR_dB;
        T.CFO_Hz(k) = meta.CFO_Hz;
        T.PhaseOffset_deg(k) = meta.PhaseOffset_deg;
        T.Delay_samples(k) = meta.Delay_samples;
        T.HEnabled(k) = meta.HEnabled;
        T.HMode(k) = meta.HMode;
        T.EqualizerEnabled(k) = meta.EqualizerEnabled;
        T.EqualizerMode(k) = meta.EqualizerMode;
        if k <= numel(state.Results)
            record = state.Results(k);
            T.ResidualCFO_Hz(k) = localStructNumeric( ...
                record, 'ResidualCFO_Hz', NaN);
            T.WaveformDuration_s(k) = localStructNumeric( ...
                record, 'WaveformDuration_s', NaN);
        end
    end
    leading = {'CaseId','Status','Pass','DataPathMode','Modulation','Coding', ...
        'Rate','RandomizerEnabled','RandomizerFECPosition','ChannelProfile', ...
        'SNR_dB','CFO_Hz','PhaseOffset_deg','Delay_samples', ...
        'HEnabled','HMode','EqualizerEnabled','EqualizerMode', ...
        'I_PredecoderBER','I_PredecoderOffset','I_PredecoderPolarity', ...
        'I_BER','I_LockRate_pct','I_FER','I_BitErrors','I_BitsCompared', ...
        'I_FrameErrors','I_CountedFrames','I_MatchedFrames','I_DecodedFrames', ...
        'Q_PredecoderBER','Q_PredecoderOffset','Q_PredecoderPolarity', ...
        'Q_BER','Q_LockRate_pct','Q_FER','Q_BitErrors','Q_BitsCompared', ...
        'Q_FrameErrors','Q_CountedFrames','Q_MatchedFrames','Q_DecodedFrames'};
    T = movevars(T, leading, 'Before', 1);
end

function out = localMerge(out, extra)
    names = fieldnames(extra);
    for k = 1:numel(names)
        out.(names{k}) = extra.(names{k});
    end
end

function value = localStructLogical(s, name, defaultValue)
    value = logical(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function value = localStructString(s, name, defaultValue)
    value = string(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = string(s.(name));
    end
end

function value = localStructNumeric(s, name, defaultValue)
    value = double(defaultValue);
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        candidate = double(s.(name));
        if isscalar(candidate)
            value = candidate;
        end
    end
end

function id = localId(text)
    id = lower(regexprep(string(text), '[^a-zA-Z0-9]+', '.'));
    id = strip(id, '.');
end

function localWriteTable(T, pathValue)
    outputDir = fileparts(pathValue);
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end
    temporaryPath = [tempname(outputDir), '.csv'];
    cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
    writetable(T, temporaryPath);
    [ok, message] = movefile(temporaryPath, pathValue, 'f');
    if ~ok
        warning('run_tm_data_path_sweep:SummaryWriteFailed', ...
            'Could not write "%s": %s', pathValue, message);
    end
    clear cleanup;
end

function localDeleteIfPresent(pathValue)
    if exist(pathValue, 'file') == 2
        delete(pathValue);
    end
end
