function T = sweep_h_channel_short_frames(userOpts)
%SWEEP_H_CHANNEL_SHORT_FRAMES Resumable short-frame H-channel sweep.
%
% Typical use:
%   addpath('E:\web_code\react\fft_project\react-fft\src\python');
%   T = sweep_h_channel_short_frames();
%
% Resume requires reusing an explicit outputDir:
%   opts = struct('outputDir','E:\ccsds_artifacts\h_run_01', ...
%       'includeLDPC',true,'Resume',true);
%   T = sweep_h_channel_short_frames(opts);

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);
    addpath(fullfile(thisDir, 'regression'));

    opts = localDefaultOptions(thisDir);
    opts = localMergeStruct(opts, userOpts);

    if opts.clearFunctionCache
        clear('run_ccsds_tm_evaluation');
        clear('HelperCCSDSTMDecoder');
        clear('HelperCCSDSTMDemodulator');
        clear('ccsdsTMWaveformGenerator');
        clear('satcom.internal.ccsds.tmBase');
    end

    codingCases = localBuildCodingCases(opts);
    channelCases = localBuildChannelCases(opts);
    cases = localBuildRunnerCases(opts, channelCases, codingCases);

    runnerOpts = struct( ...
        'OutputDir', opts.outputDir, ...
        'RunId', opts.RunId, ...
        'PlanVersion', "h-channel-short-v1", ...
        'Resume', opts.Resume, ...
        'MaxNewCases', opts.MaxNewCases, ...
        'RerunFailed', opts.RerunFailed, ...
        'BaseSeed', opts.randomSeed, ...
        'CaseIds', opts.CaseIds, ...
        'DryRun', opts.DryRun, ...
        'FailOnFailure', opts.FailOnFailure, ...
        'Verbose', opts.Verbose);
    [~, state] = reg_run_cases("h_channel_short", cases, runnerOpts);

    rows = cell(numel(cases), numel(localVariableNames()));
    for k = 1:numel(cases)
        meta = cases(k).Meta;
        record = state.Results(k);
        errorMessage = record.ErrorMessage;
        if strlength(errorMessage) == 0
            errorMessage = record.FailedChecks;
        end
        rows(k, :) = localMakeRow(k, meta.Channel, char(meta.ModType), ...
            meta.Coding, cases(k).Params, record.Actual, record.Success, ...
            record.Status, errorMessage, record.ElapsedTime);
    end
    T = cell2table(rows, 'VariableNames', localVariableNames());

    if ~opts.DryRun
        csvPath = fullfile(char(state.OutputDir), 'h_channel_short_sweep.csv');
        matPath = fullfile(char(state.OutputDir), 'h_channel_short_sweep.mat');
        localWriteTable(T, csvPath);
        localSaveFinalMat(matPath, T, opts, cases);
        fprintf('\n==== H-channel sweep state ====\n');
        fprintf('Checkpoint: %s\n', fullfile(char(state.OutputDir), 'checkpoint.mat'));
        fprintf('CSV       : %s\n', csvPath);
        fprintf('MAT       : %s\n', matPath);
        localPrintWeakCases(T, opts);
    end
end

function cases = localBuildRunnerCases(opts, channelCases, codingCases)
    cases = struct('Id',{},'Name',{},'Category',{}, ...
        'Params',{},'Expected',{},'Meta',{});
    for iChannel = 1:numel(channelCases)
        channel = channelCases{iChannel};
        for iModulation = 1:numel(opts.modTypes)
            modulation = char(opts.modTypes{iModulation});
            for iCoding = 1:numel(codingCases)
                coding = codingCases{iCoding};
                if ~localIsCaseCompatible(modulation, coding, opts)
                    continue;
                end

                params = localBaseParams(opts);
                params.modType = modulation;
                params = localApplyModulationParams(params, modulation, opts);
                params = localApplyCodingParams(params, coding);
                params = localApplyChannelParams(params, channel, opts);

                name = sprintf('%s | %s | %s | %s', ...
                    channel.Name, modulation, coding.ChannelCoding, coding.RateLabel);
                id = "h." + localId(channel.Name) + "." + ...
                    localId(modulation) + "." + localId(coding.ChannelCoding) + ...
                    "." + localId(coding.RateLabel);
                expected = localExpected(opts, params, modulation);
                meta = struct( ...
                    'Channel', channel, ...
                    'ModType', string(modulation), ...
                    'Coding', coding);
                cases(end+1,1) = struct( ... %#ok<AGROW>
                    'Id', id, ...
                    'Name', string(name), ...
                    'Category', "h_channel", ...
                    'Params', params, ...
                    'Expected', expected, ...
                    'Meta', meta);
            end
        end
    end
end

function expected = localExpected(opts, params, modulation)
    required = ["BER","LockRate"];
    if ~isempty(opts.minGoodMERdB)
        required(end+1) = "MER_dB";
    end
    detector = "";
    if strcmpi(modulation, 'GMSK')
        detector = string(opts.GMSKDetectionMode);
        if detector == "official-viterbi-frame-reset"
            detector = "official";
        end
    end
    expected = struct( ...
        'RequiredMetrics', required, ...
        'MaxBER', opts.maxGoodBER, ...
        'MinLockRate', opts.minGoodLockPct / 100, ...
        'MaxFER', opts.maxGoodFER, ...
        'MinMERdB', opts.minGoodMERdB, ...
        'MinCountedFrames', opts.minCountedFrames, ...
        'ExpectedDataPathMode', string(params.DataPathMode), ...
        'ExpectedWaveformMode', string(params.WaveformMode), ...
        'ExpectedRandomizerFECPosition', string(params.RandomizerFECPosition), ...
        'ExpectedRandomizerEnabled', logical(params.RandomizerEnabled), ...
        'ExpectedGMSKDetector', detector, ...
        'ExpectedErrorIdentifier', "", ...
        'ExpectedErrorMessage', "");
end

function opts = localDefaultOptions(thisDir)
    opts = struct();
    opts.channelFilePath = 'E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat';
    opts.outputDir = '';
    opts.RunId = ['h_channel_short_' datestr(now, 'yyyymmdd_HHMMSS')];
    opts.Resume = true;
    opts.MaxNewCases = Inf;
    opts.RerunFailed = false;
    opts.CaseIds = strings(0,1);
    opts.DryRun = false;
    opts.FailOnFailure = false;
    opts.Verbose = true;
    % 多个已有 H 信道模型文件；默认空，表示只用 opts.channelFilePath
    opts.hModelCases = {};

    opts.modTypes = {'QPSK','8PSK','16APSK','32APSK','GMSK'};
    opts.convRates = {'1/2','2/3','3/4','5/6','7/8'};

    opts.includeNoHBaseline = true;
    opts.includeHEqualized = true;
    opts.includeNormHScenario = false;
    opts.includeNoEqualizerScenario = false;

    opts.includeLDPC = false;
    opts.includeTurbo = false;
    opts.includeTPC = false;
    opts.ldpcRates = {'1/2'};
    opts.turboRates = {'1/2'};
    opts.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8), ...
                     struct('TPCCodeRate','2/3','TPCBlocksPerTF',4)};

    opts.symbolRate = 1e6;
    opts.sps = 8;
    opts.snr = 30;
    opts.noisePlacement = 'afterChannel';
    opts.noisePSDdBmHz = [];
    opts.noiseBandwidthHz = [];
    opts.cfo = 0;
    opts.phaseOffset = 0;
    opts.delay = 0;
    opts.RolloffFactor = 0.35;
    opts.hasASM = true;
    opts.RandomizerEnabled = false;
    opts.RandomizerFECPosition = 'afterEncoding';
    opts.DataPathMode = 'single';
    opts.WaveformMode = 'ordinaryTM';
    opts.NumBytesInTransferFrame = 1115;
    opts.forceNumBytesInTransferFrame = [];
    opts.berWarmUpFrames = 15;
    opts.berFrames = 30;

    opts.equalizerMode = 'mmse';
    opts.equalizerReg = [];
    opts.channelInterpolationMethod = 'linear';
    opts.channelOutOfRangeMode = 'wrap';
    opts.interpolateChannelDelays = false;
    opts.normalizeEqualizerOutput = true;

    opts.useTMAPSKPilots = true;
    opts.TMAPSKPilotInterval = 512;
    opts.TMAPSKPilotLength = 32;
    opts.TMAPSKPilotPreambleLength = 64;
    opts.TMAPSKPilotCorrectionMode = 'phaseinterp';
    opts.TMAPSKPilotPhaseSmoothWindow = 3;
    opts.facmWarmupFrames = [];
    opts.facmBERFrames = [];
    opts.facmNumIterations = [];
    opts.debugFACM = false;
    opts.enableFACMEqualizer = [];
    opts.facmEqualizerMode = '';
    opts.facmEqualizerReg = [];
    opts.facmEqualizerTaps = [];

    opts.gmskBT = 0.5;
    opts.GMSKDetectionMode = 'legacy-diff';
    opts.gmskFrameResetASMMaxErrors = [];
    opts.gmskFrameResetASMMinGap = [];
    opts.gmskFrameResetMaxSearchFrames = 8;
    opts.gmskFrameResetMinSearchFrames = 2;
    opts.randomSeed = 1;
    opts.clearFunctionCache = true;

    opts.debugCodedBoundary = false;
    opts.debugFrameCheck = false;
    opts.debugFrameCheckCount = 20;
    opts.debugAllPerFrameBER = false;
    opts.debugPerFrameBERCount = 25;
    opts.debugPerFrameBERFormat = '';
    opts.debugPerFrameBERSummary = [];
    opts.debugPerFrameBERNonzeroCount = 24;
    opts.debugGMSK = false;
    opts.debugASMPhase = false;
    opts.debugEqualizerStats = false;
    opts.debugHFrameStats = false;
    opts.debugHFrameStatsStart = 1;
    opts.debugHFrameStatsCount = 16;
    opts.debugCodedFrameSyncPrintLimit = 80;
    opts.enableCodedPhaseSearch = [];
    opts.phaseResolveFallback = [];
    opts.phaseResolveMode = '';

    opts.showFigures = false;
    opts.showPipelineFigure = false;
    opts.showDamageBudgetFigure = false;
    opts.showPowerFigure = false;
    opts.inputLevelDbm = -10;

    opts.maxGoodBER = 1e-3;
    opts.minGoodLockPct = 90;
    opts.minGoodMERdB = 18;
    opts.maxGoodFER = [];
    opts.minCountedFrames = 1;

    if nargin > 0 && exist(fullfile(thisDir, 'run_ccsds_tm_evaluation.m'), 'file') ~= 2
        warning('sweep_h_channel_short_frames:MissingMain', ...
            'run_ccsds_tm_evaluation.m was not found next to this file.');
    end
end

function opts = localMergeStruct(opts, userOpts)
    if ~isstruct(userOpts)
        error('sweep_h_channel_short_frames:InvalidOptions', ...
            'userOpts must be a struct.');
    end
    names = fieldnames(userOpts);
    for i = 1:numel(names)
        opts.(names{i}) = userOpts.(names{i});
    end
end

function p = localBaseParams(opts)
    p = struct( ...
        'symbolRate', opts.symbolRate, ...
        'sps', opts.sps, ...
        'snr', opts.snr, ...
        'noisePlacement', opts.noisePlacement, ...
        'cfo', opts.cfo, ...
        'phaseOffset', opts.phaseOffset, ...
        'delay', opts.delay, ...
        'RolloffFactor', opts.RolloffFactor, ...
        'hasASM', opts.hasASM, ...
        'RandomizerEnabled', opts.RandomizerEnabled, ...
        'RandomizerFECPosition', opts.RandomizerFECPosition, ...
        'DataPathMode', opts.DataPathMode, ...
        'WaveformMode', opts.WaveformMode, ...
        'NumBytesInTransferFrame', opts.NumBytesInTransferFrame, ...
        'berWarmUpFrames', opts.berWarmUpFrames, ...
        'berFrames', opts.berFrames, ...
        'showFigures', opts.showFigures, ...
        'showPipelineFigure', opts.showPipelineFigure, ...
        'showDamageBudgetFigure', opts.showDamageBudgetFigure, ...
        'showPowerFigure', opts.showPowerFigure, ...
        'inputLevelDbm', opts.inputLevelDbm);

    if isfield(opts, 'noisePSDdBmHz') && ~isempty(opts.noisePSDdBmHz)
        p.noisePSDdBmHz = double(opts.noisePSDdBmHz);
    end
    if isfield(opts, 'noiseBandwidthHz') && ~isempty(opts.noiseBandwidthHz)
        p.noiseBandwidthHz = double(opts.noiseBandwidthHz);
    end
    if isfield(opts, 'GMSKDetectionMode') && ~isempty(opts.GMSKDetectionMode)
        p.GMSKDetectionMode = char(opts.GMSKDetectionMode);
    end
    resetFields = {'gmskFrameResetASMMaxErrors', ...
        'gmskFrameResetASMMinGap', 'gmskFrameResetMaxSearchFrames', ...
        'gmskFrameResetMinSearchFrames'};
    for resetIndex = 1:numel(resetFields)
        resetName = resetFields{resetIndex};
        if isfield(opts, resetName) && ~isempty(opts.(resetName))
            p.(resetName) = double(opts.(resetName));
        end
    end

    if isfield(opts, 'debugCodedBoundary') && ~isempty(opts.debugCodedBoundary)
        p.debugCodedBoundary = logical(opts.debugCodedBoundary);
    end
    if isfield(opts, 'debugFrameCheck') && ~isempty(opts.debugFrameCheck)
        p.debugFrameCheck = logical(opts.debugFrameCheck);
    end
    if isfield(opts, 'debugFrameCheckCount') && ~isempty(opts.debugFrameCheckCount)
        p.debugFrameCheckCount = double(opts.debugFrameCheckCount);
    end
    if isfield(opts, 'debugAllPerFrameBER') && ~isempty(opts.debugAllPerFrameBER)
        p.debugAllPerFrameBER = logical(opts.debugAllPerFrameBER);
    end
    if isfield(opts, 'debugPerFrameBERCount') && ~isempty(opts.debugPerFrameBERCount)
        p.debugPerFrameBERCount = double(opts.debugPerFrameBERCount);
    end
    if isfield(opts, 'debugPerFrameBERFormat') && ~isempty(opts.debugPerFrameBERFormat)
        p.debugPerFrameBERFormat = char(opts.debugPerFrameBERFormat);
    end
    if isfield(opts, 'debugPerFrameBERSummary') && ~isempty(opts.debugPerFrameBERSummary)
        p.debugPerFrameBERSummary = logical(opts.debugPerFrameBERSummary);
    end
    if isfield(opts, 'debugPerFrameBERNonzeroCount') && ~isempty(opts.debugPerFrameBERNonzeroCount)
        p.debugPerFrameBERNonzeroCount = double(opts.debugPerFrameBERNonzeroCount);
    end
    if isfield(opts, 'debugGMSK') && ~isempty(opts.debugGMSK)
        p.debugGMSK = logical(opts.debugGMSK);
    end
    if isfield(opts, 'debugASMPhase') && ~isempty(opts.debugASMPhase)
        p.debugASMPhase = logical(opts.debugASMPhase);
    end
    if isfield(opts, 'debugEqualizerStats') && ~isempty(opts.debugEqualizerStats)
        p.debugEqualizerStats = logical(opts.debugEqualizerStats);
    end
    if isfield(opts, 'debugHFrameStats') && ~isempty(opts.debugHFrameStats)
        p.debugHFrameStats = logical(opts.debugHFrameStats);
    end
    if isfield(opts, 'debugHFrameStatsStart') && ~isempty(opts.debugHFrameStatsStart)
        p.debugHFrameStatsStart = double(opts.debugHFrameStatsStart);
    end
    if isfield(opts, 'debugHFrameStatsCount') && ~isempty(opts.debugHFrameStatsCount)
        p.debugHFrameStatsCount = double(opts.debugHFrameStatsCount);
    end
    if isfield(opts, 'debugCodedFrameSyncPrintLimit') && ~isempty(opts.debugCodedFrameSyncPrintLimit)
        p.debugCodedFrameSyncPrintLimit = double(opts.debugCodedFrameSyncPrintLimit);
    end
    if isfield(opts, 'enableCodedPhaseSearch') && ~isempty(opts.enableCodedPhaseSearch)
        p.enableCodedPhaseSearch = logical(opts.enableCodedPhaseSearch);
    end
    if isfield(opts, 'phaseResolveFallback') && ~isempty(opts.phaseResolveFallback)
        p.phaseResolveFallback = logical(opts.phaseResolveFallback);
    end
    if isfield(opts, 'phaseResolveMode') && ~isempty(opts.phaseResolveMode)
        p.phaseResolveMode = char(opts.phaseResolveMode);
    end
end

function p = localApplyModulationParams(p, modType, opts)
    if contains(upper(modType), 'APSK')
        p.WaveformMode = char(opts.WaveformMode);
        p.HasTMAPSKPilots = logical(opts.useTMAPSKPilots);
        p.TMAPSKPilotInterval = opts.TMAPSKPilotInterval;
        p.TMAPSKPilotLength = opts.TMAPSKPilotLength;
        p.TMAPSKPilotPreambleLength = opts.TMAPSKPilotPreambleLength;
        p.TMAPSKPilotCorrectionMode = opts.TMAPSKPilotCorrectionMode;
        p.TMAPSKPilotPhaseSmoothWindow = opts.TMAPSKPilotPhaseSmoothWindow;
        if ~isempty(opts.facmWarmupFrames)
            p.facmWarmupFrames = double(opts.facmWarmupFrames);
        end
        if ~isempty(opts.facmBERFrames)
            p.facmBERFrames = double(opts.facmBERFrames);
        end
        if ~isempty(opts.facmNumIterations)
            p.facmNumIterations = double(opts.facmNumIterations);
        end
        if isfield(opts, 'debugFACM') && ~isempty(opts.debugFACM)
            p.debugFACM = logical(opts.debugFACM);
        end
        if ~isempty(opts.enableFACMEqualizer)
            p.enableFACMEqualizer = logical(opts.enableFACMEqualizer);
        end
        if ~isempty(opts.facmEqualizerMode)
            p.facmEqualizerMode = char(opts.facmEqualizerMode);
        end
        if ~isempty(opts.facmEqualizerReg)
            p.facmEqualizerReg = double(opts.facmEqualizerReg);
        end
        if ~isempty(opts.facmEqualizerTaps)
            p.facmEqualizerTaps = double(opts.facmEqualizerTaps);
        end
    end

    if strcmpi(modType, 'GMSK')
        p.BandwidthTimeProduct = opts.gmskBT;
    end
end

function p = localApplyCodingParams(p, code)
    clearFields = {'ConvolutionalCodeRate','CodeRate','NumBitsInInformationBlock', ...
        'IsLDPCOnSMTF','LDPCCodeblockSize','TPCCodeRate','TPCBlocksPerTF'};
    for i = 1:numel(clearFields)
        if isfield(p, clearFields{i})
            p = rmfield(p, clearFields{i});
        end
    end

    p.channelCoding = code.ChannelCoding;
    p.NumBytesInTransferFrame = code.NumBytesInTransferFrame;

    extraNames = fieldnames(code.Extra);
    for i = 1:numel(extraNames)
        p.(extraNames{i}) = code.Extra.(extraNames{i});
    end
end

function p = localApplyChannelParams(p, ch, opts)
    p.enableHChannel = ch.EnableHChannel;
    p.enableEqualizer = ch.EnableEqualizer;
    p.normalizeHChannel = ch.NormalizeHChannel;
    p.normalizeEqualizerOutput = ch.NormalizeEqualizerOutput;

    if ch.EnableHChannel
        p.HMode = 'h_matrix_file';

        if isfield(ch, 'ChannelFilePath') && ~isempty(ch.ChannelFilePath)
            p.channelFilePath = ch.ChannelFilePath;
        else
            p.channelFilePath = opts.channelFilePath;
        end

        p.channelInterpolationMethod = opts.channelInterpolationMethod;
        if isfield(opts, 'channelOutOfRangeMode') && ~isempty(opts.channelOutOfRangeMode)
            p.channelOutOfRangeMode = char(opts.channelOutOfRangeMode);
        end
        p.interpolateChannelDelays = opts.interpolateChannelDelays;
    end

    if ch.EnableEqualizer
        p.equalizerMode = opts.equalizerMode;
        if ~isempty(opts.equalizerReg)
            p.equalizerReg = opts.equalizerReg;
        end
    end
end

function cases = localBuildChannelCases(opts)
    cases = {};

    if opts.includeNoHBaseline
        cases{end+1} = struct( ...
            'Name', 'NoH_baseline', ...
            'EnableHChannel', false, ...
            'EnableEqualizer', false, ...
            'NormalizeHChannel', false, ...
            'NormalizeEqualizerOutput', false, ...
            'ChannelFilePath', ''); %#ok<AGROW>
    end

    % 这里新增：支持多个 H 文件
    if isfield(opts, 'hModelCases') && ~isempty(opts.hModelCases)
        hModelCases = opts.hModelCases;
    else
        hModelCases = { ...
            'H_EQ_rawGain', opts.channelFilePath};
    end

    if opts.includeHEqualized
        for i = 1:size(hModelCases, 1)
            hLabel = char(hModelCases{i, 1});
            hFile  = char(hModelCases{i, 2});

            cases{end+1} = struct( ...
                'Name', ['H_EQ_rawGain_' hLabel], ...
                'EnableHChannel', true, ...
                'EnableEqualizer', true, ...
                'NormalizeHChannel', false, ...
                'NormalizeEqualizerOutput', opts.normalizeEqualizerOutput, ...
                'ChannelFilePath', hFile); %#ok<AGROW>
        end
    end

    if opts.includeNormHScenario
        for i = 1:size(hModelCases, 1)
            hLabel = char(hModelCases{i, 1});
            hFile  = char(hModelCases{i, 2});

            cases{end+1} = struct( ...
                'Name', ['H_EQ_normH_' hLabel], ...
                'EnableHChannel', true, ...
                'EnableEqualizer', true, ...
                'NormalizeHChannel', true, ...
                'NormalizeEqualizerOutput', opts.normalizeEqualizerOutput, ...
                'ChannelFilePath', hFile); %#ok<AGROW>
        end
    end

    if opts.includeNoEqualizerScenario
        for i = 1:size(hModelCases, 1)
            hLabel = char(hModelCases{i, 1});
            hFile  = char(hModelCases{i, 2});

            cases{end+1} = struct( ...
                'Name', ['H_noEQ_rawGain_' hLabel], ...
                'EnableHChannel', true, ...
                'EnableEqualizer', false, ...
                'NormalizeHChannel', false, ...
                'NormalizeEqualizerOutput', false, ...
                'ChannelFilePath', hFile); %#ok<AGROW>
        end
    end
end

function cases = localBuildCodingCases(opts)
    cases = {};

    cases{end+1} = localCodingCase('none', 'none', ...
        localMaybeOverrideTransferFrameBytes(1115, opts), struct()); %#ok<AGROW>

    for i = 1:numel(opts.convRates)
        rate = char(opts.convRates{i});
        extra = struct('ConvolutionalCodeRate', rate);
        cases{end+1} = localCodingCase('convolutional', rate, ...
            localMaybeOverrideTransferFrameBytes(localConvTransferFrameBytes(rate), opts), extra); %#ok<AGROW>
    end

    if opts.includeLDPC
        for i = 1:numel(opts.ldpcRates)
            rate = char(opts.ldpcRates{i});
            if strcmp(rate, '7/8')
                informationBits = 7136;
            else
                informationBits = 1024;
            end
            extra = struct( ...
                'CodeRate', rate, ...
                'NumBitsInInformationBlock', informationBits, ...
                'IsLDPCOnSMTF', false);
            cases{end+1} = localCodingCase('LDPC', rate, 1115, extra); %#ok<AGROW>
        end
    end

    if opts.includeTurbo
        for i = 1:numel(opts.turboRates)
            rate = char(opts.turboRates{i});
            extra = struct( ...
                'CodeRate', rate, ...
                'NumBitsInInformationBlock', 1784);
            cases{end+1} = localCodingCase('Turbo', rate, 1115, extra); %#ok<AGROW>
        end
    end

    if opts.includeTPC
        for i = 1:numel(opts.tpcCases)
            tpc = opts.tpcCases{i};
            tfBytes = localTPCTransferFrameBytes(tpc.TPCCodeRate, tpc.TPCBlocksPerTF);
            if ~isfinite(tfBytes) || tfBytes > 2048
                fprintf(2, '[skip] TPC %s, blocks %d gives invalid TF bytes %.0f.\n', ...
                    char(tpc.TPCCodeRate), double(tpc.TPCBlocksPerTF), tfBytes);
                continue;
            end
            label = sprintf('%s_x%d', char(tpc.TPCCodeRate), double(tpc.TPCBlocksPerTF));
            extra = struct( ...
                'TPCCodeRate', char(tpc.TPCCodeRate), ...
                'TPCBlocksPerTF', double(tpc.TPCBlocksPerTF));
            cases{end+1} = localCodingCase('TPC', label, tfBytes, extra); %#ok<AGROW>
        end
    end
end

function tfBytes = localMaybeOverrideTransferFrameBytes(defaultBytes, opts)
    tfBytes = double(defaultBytes);
    override = [];
    if isfield(opts, 'forceNumBytesInTransferFrame') && ~isempty(opts.forceNumBytesInTransferFrame)
        override = opts.forceNumBytesInTransferFrame;
    elseif isfield(opts, 'NumBytesInTransferFrame') && ~isempty(opts.NumBytesInTransferFrame) && ...
            double(opts.NumBytesInTransferFrame) ~= 1115
        override = opts.NumBytesInTransferFrame;
    end
    if ~isempty(override)
        tfBytes = round(double(override));
    end
    if ~isfinite(tfBytes) || tfBytes < 8
        error('sweep_h_channel_short_frames:InvalidTransferFrameBytes', ...
            'NumBytesInTransferFrame override must be at least 8 bytes.');
    end
end

function c = localCodingCase(channelCoding, rateLabel, numBytes, extra)
    c = struct( ...
        'ChannelCoding', char(channelCoding), ...
        'RateLabel', char(rateLabel), ...
        'NumBytesInTransferFrame', double(numBytes), ...
        'Extra', extra);
end

function tfBytes = localConvTransferFrameBytes(rate)
    switch char(rate)
        case '5/6'
            tfBytes = 1116;
        case '7/8'
            tfBytes = 1123;
        otherwise
            tfBytes = 1115;
    end
end

function tfBytes = localTPCTransferFrameBytes(rateName, blocksPerTF)
    payloadBits = localTPCPayloadBits(rateName) * max(1, round(double(blocksPerTF)));
    if mod(payloadBits, 8) == 0
        tfBytes = payloadBits / 8;
    else
        tfBytes = NaN;
    end
end

function bits = localTPCPayloadBits(rateName)
    switch char(rateName)
        case '1/2'
            side = 32;
        case '2/3'
            side = 52;
        case 'native'
            side = 57;
        otherwise
            val = str2double(char(rateName));
            if isfinite(val) && val > 0 && val <= 57 && mod(val, 1) == 0
                side = val;
            else
                error('sweep_h_channel_short_frames:InvalidTPCCodeRate', ...
                    'Unsupported TPCCodeRate="%s".', char(rateName));
            end
    end
    bits = side * side;
end

function tf = localIsCaseCompatible(modType, code, opts)
    tf = true;

    if strcmpi(modType, '4D-8PSK-TCM') && ~strcmpi(code.ChannelCoding, 'none')
        tf = false;
        return;
    end

    isAPSK = contains(upper(string(modType)), 'APSK');
    if isAPSK && strcmpi(char(opts.WaveformMode), 'FACM') && ...
            ~strcmpi(code.ChannelCoding, 'none')
        tf = false;
        return;
    end
end

function row = localMakeRow(idx, ch, modType, code, p, r, ok, status, err, elapsed)
    hNormGain = NaN;
    hMeanCoeff = NaN;
    hOutOfRangeMode = "";
    hSourceDuration_s = NaN;
    hWaveformDuration_s = NaN;
    hExceedsDuration = false;
    if isfield(r, 'channelMeta') && isstruct(r.channelMeta)
        hNormGain = localField(r.channelMeta, 'NormalizationGain_dB', NaN);
        hMeanCoeff = localField(r.channelMeta, 'MeanCoeffMagnitude', NaN);
        hOutOfRangeMode = string(localStructChar(r.channelMeta, 'OutOfRangeMode', ""));
        hSourceDuration_s = localField(r.channelMeta, 'ChannelSourceDuration_s', NaN);
        hWaveformDuration_s = localField(r.channelMeta, 'WaveformDuration_s', NaN);
        hExceedsDuration = logical(localField(r.channelMeta, 'ExceedsChannelDuration', false));
    end

    infoBits = NaN;
    if isfield(p, 'NumBitsInInformationBlock')
        infoBits = double(p.NumBitsInInformationBlock);
    end

    ldpcOnSMTF = false;
    if isfield(p, 'IsLDPCOnSMTF')
        ldpcOnSMTF = logical(p.IsLDPCOnSMTF);
    end

    tpcBlocks = NaN;
    if isfield(p, 'TPCBlocksPerTF')
        tpcBlocks = double(p.TPCBlocksPerTF);
    end
    frameDuration_s = localFrameDurationSeconds(modType, p);
    countedFrames = localField(r, 'CountedFrames', NaN);
    matchedFrames = localField(r, 'MatchedFrames', NaN);

    row = { ...
        double(idx), ...
        string(ch.Name), ...
        string(modType), ...
        string(code.ChannelCoding), ...
        string(code.RateLabel), ...
        double(p.NumBytesInTransferFrame), ...
        infoBits, ...
        ldpcOnSMTF, ...
        tpcBlocks, ...
        logical(ch.EnableHChannel), ...
        logical(ch.EnableEqualizer), ...
        logical(ch.NormalizeHChannel), ...
        logical(ch.NormalizeEqualizerOutput), ...
        localField(r, 'BER', NaN), ...
        100 * localField(r, 'LockRate', NaN), ...
        localField(r, 'FER', NaN), ...
        countedFrames, ...
        matchedFrames, ...
        frameDuration_s, ...
        matchedFrames * frameDuration_s, ...
        countedFrames * frameDuration_s, ...
        localField(r, 'EVM_post_pct', NaN), ...
        localField(r, 'MER_dB', NaN), ...
        localField(r, 'SNR_est_dB', NaN), ...
        localField(r, 'ResidualCFO_Hz', NaN), ...
        localField(r, 'HGain_dB', NaN), ...
        hNormGain, ...
        hMeanCoeff, ...
        hOutOfRangeMode, ...
        hSourceDuration_s, ...
        hWaveformDuration_s, ...
        hExceedsDuration, ...
        string(localStructChar(p, 'noisePlacement', localStructChar(r, 'NoisePlacement', 'afterChannel'))), ...
        string(localStructChar(r, 'NoiseMode', localStructChar(p, 'NoiseMode', 'snr'))), ...
        localField(r, 'NoisePSD_dBmHz', localStructNumeric(p, 'noisePSDdBmHz', NaN)), ...
        localField(r, 'NoiseBandwidthHz', localStructNumeric(p, 'noiseBandwidthHz', NaN)), ...
        localField(r, 'NoisePower_dBm', NaN), ...
        localField(r, 'NoiseEquivalentSNR_dB', NaN), ...
        string(localStructChar(p, 'equalizerMode', '')), ...
        string(localGMSKDetectorUsed(r, p, modType)), ...
        logical(ok), ...
        string(status), ...
        string(err), ...
        double(elapsed)};
end

function names = localVariableNames()
    names = {'CaseIndex', ...
        'Scenario', 'ModType', 'ChannelCoding', 'Rate', ...
        'NumBytesInTransferFrame', 'NumBitsInInformationBlock', ...
        'IsLDPCOnSMTF', 'TPCBlocksPerTF', ...
        'HEnabled', 'EqualizerEnabled', 'NormalizeHChannel', ...
        'NormalizeEqualizerOutput', ...
        'BER', 'LockRate_pct', 'FER', 'CountedFrames', 'MatchedFrames', ...
        'FrameDuration_s', 'MatchedDuration_s', 'CountedDuration_s', ...
        'EVM_post_pct', 'MER_dB', 'SNR_est_dB', 'ResidualCFO_Hz', ...
        'HGain_dB', 'HNormalizationGain_dB', 'HMeanCoeffMagnitude', ...
        'HOutOfRangeMode', 'HSourceDuration_s', 'WaveformDuration_s', ...
        'ExceedsHDuration', ...
        'NoisePlacement', 'NoiseMode', 'NoisePSD_dBmHz', ...
        'NoiseBandwidthHz', 'NoisePower_dBm', 'NoiseEquivalentSNR_dB', ...
        'EqualizerMode', ...
        'GMSKDetectorUsed', ...
        'Success', 'Status', 'ErrorMessage', 'Runtime_s'};
end

function duration_s = localFrameDurationSeconds(modType, p)
    duration_s = NaN;
    symbolRate = localStructNumeric(p, 'symbolRate', NaN);
    numBytes = localStructNumeric(p, 'NumBytesInTransferFrame', NaN);
    bps = localBitsPerSymbol(modType);
    codeRate = localCodeRate(p);
    if isfinite(symbolRate) && symbolRate > 0 && ...
            isfinite(numBytes) && numBytes > 0 && ...
            isfinite(bps) && bps > 0 && ...
            isfinite(codeRate) && codeRate > 0
        duration_s = (numBytes * 8) / codeRate / bps / symbolRate;
    end
end

function bps = localBitsPerSymbol(modType)
    key = upper(string(modType));
    if contains(key, '32QAM') || contains(key, '32APSK')
        bps = 5;
    elseif contains(key, '16QAM') || contains(key, '16APSK')
        bps = 4;
    elseif contains(key, '8PSK')
        bps = 3;
    elseif contains(key, 'QPSK')
        bps = 2;
    else
        bps = 1;
    end
end

function rate = localCodeRate(p)
    code = lower(string(localStructChar(p, 'channelCoding', 'none')));
    if contains(code, 'convolutional')
        rate = localRateStringToDouble(localStructChar(p, 'ConvolutionalCodeRate', '1/2'), 1/2);
    elseif contains(code, 'turbo') || contains(code, 'ldpc')
        rate = localRateStringToDouble(localStructChar(p, 'CodeRate', '1/2'), 1/2);
    elseif contains(code, 'rs')
        rate = 223/255;
    elseif contains(code, 'tpc')
        rate = localRateStringToDouble(localStructChar(p, 'TPCCodeRate', '1'), 1);
    else
        rate = 1;
    end
end

function rate = localRateStringToDouble(rawRate, defaultRate)
    rate = defaultRate;
    text = strtrim(char(string(rawRate)));
    parts = split(string(text), '/');
    if numel(parts) == 2
        num = str2double(parts(1));
        den = str2double(parts(2));
        if isfinite(num) && isfinite(den) && den ~= 0
            rate = num / den;
        end
    else
        val = str2double(text);
        if isfinite(val) && val > 0
            rate = val;
        end
    end
end

function value = localStructNumeric(s, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = double(s.(fieldName));
    end
end

function value = localStructChar(s, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = char(string(s.(fieldName)));
    end
end

function detector = localGMSKDetectorUsed(result, params, modType)
    detector = 'not-applicable';
    if ~strcmpi(string(modType), "GMSK")
        return;
    end
    if isstruct(result) && isfield(result, 'GMSKDetectorUsed') && ...
            ~isempty(result.GMSKDetectorUsed)
        detector = char(string(result.GMSKDetectorUsed));
        return;
    end
    detector = localStructChar(params, 'GMSKDetectionMode', 'legacy-diff');
    if strcmpi(detector, 'official-viterbi-frame-reset')
        detector = 'official';
    end
end

function v = localField(s, fieldName, defaultValue)
    v = defaultValue;
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        v = s.(fieldName);
        if islogical(v)
            v = double(v);
        end
        if ischar(v) || isstring(v)
            n = str2double(char(v));
            if isfinite(n)
                v = n;
            else
                v = defaultValue;
            end
        end
    end
end

function localPrintWeakCases(T, opts)
    if isempty(T)
        fprintf('\nNo cases were executed.\n');
        return;
    end

    pending = T.Status == "PENDING" | T.Status == "RUNNING";
    weak = ~pending & (~T.Success | T.BER < 0 | isnan(T.BER) | isnan(T.LockRate_pct));
    if ~isempty(opts.maxGoodBER)
        weak = weak | (~pending & T.BER > opts.maxGoodBER);
    end
    if ~isempty(opts.minGoodLockPct)
        weak = weak | (~pending & T.LockRate_pct < opts.minGoodLockPct);
    end
    if ~isempty(opts.minGoodMERdB)
        weak = weak | (~pending & (isnan(T.MER_dB) | T.MER_dB < opts.minGoodMERdB));
    end
    if ~isempty(opts.maxGoodFER)
        weak = weak | (~pending & (isnan(T.FER) | T.FER > opts.maxGoodFER));
    end
    W = T(weak, :);

    fprintf('\n==== Weak / failed cases ====\n');
    if isempty(W)
        fprintf('None under the configured PASS thresholds.\n');
        if any(pending)
            fprintf('%d case(s) remain pending and were not classified as failures.\n', nnz(pending));
        end
        return;
    end

    cols = {'Scenario','ModType','ChannelCoding','Rate','BER','LockRate_pct', ...
        'EVM_post_pct','MER_dB','CountedFrames','Success','ErrorMessage'};
    disp(W(1:min(height(W), 30), cols));
    if height(W) > 30
        fprintf('... %d more weak cases in the CSV.\n', height(W) - 30);
    end
end

function id = localId(text)
    id = lower(regexprep(string(text), '[^a-zA-Z0-9]+', '.'));
    id = strip(id, '.');
end

function localWriteTable(T, pathValue)
    outputDir = fileparts(pathValue);
    temporaryPath = [tempname(outputDir), '.csv'];
    cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
    writetable(T, temporaryPath);
    [ok, message] = movefile(temporaryPath, pathValue, 'f');
    if ~ok
        warning('sweep_h_channel_short_frames:SummaryWriteFailed', ...
            'Could not write "%s": %s', pathValue, message);
    end
    clear cleanup;
end

function localSaveFinalMat(pathValue, T, opts, cases)
    outputDir = fileparts(pathValue);
    temporaryPath = [tempname(outputDir), '.mat'];
    cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
    save(temporaryPath, 'T', 'opts', 'cases', '-v7.3');
    [ok, message] = movefile(temporaryPath, pathValue, 'f');
    if ~ok
        warning('sweep_h_channel_short_frames:MatWriteFailed', ...
            'Could not write "%s": %s', pathValue, message);
    end
    clear cleanup;
end

function localDeleteIfPresent(pathValue)
    if exist(pathValue, 'file') == 2
        delete(pathValue);
    end
end
