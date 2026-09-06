%% Shared full-program sweep engine: clean No-H baseline by default
% This file is intentionally a script so the result table remains in the
% MATLAB base workspace.
%
% Clean run:
%   run('E:/web_code/react/fft_project/react-fft/tmp/codex_noh_program_sweep_v1.m');
%
% Optional command-line overrides (set BEFORE run):
%   NoHSweepUserOptions = struct('StartJob',1,'MaxJobs',10, ...
%       'RunModulationSweep',true,'RunCodingSweep',true, ...
%       'CodingSweepModType','8PSK','Include4DTCM',true, ...
%       'VerboseReceiverLog',false,'SaveCSV',false);
%
% Companion wrappers select impairment or normalized-H mode and then run
% this same case engine.  No-H modes force H/equalizer OFF.  Normalized-H
% mode uses the adaptive/modulation-specific receiver and never uses known H.
% The impairment mode uses measured-SNR AWGN; it is a synchronization stress
% test, not a physical PSD/link-budget test.

% dbclear all;
% clearvars;
% clear functions;
% rehash;
% 
% NoHSweepUserOptions = struct( ...
%     'RunModulationSweep',false, ...
%     'RunCodingSweep',true, ...
%     'CodingSweepModType','GMSK', ...
%     'Include4DTCM',false, ...
%     'StartJob',1, ...              % 卷积码 2/3
%     'MaxJobs',32, ...
%     'BERWarmUpFrames',8, ...
%     'BERFrames',132, ...
%     'ChannelFilePath', ...
%         'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat', ...
%     'VerboseReceiverLog',true, ...
%     'SaveCSV',false, ...
%     'ReceiverOverrides',struct( ...
%         'GMSKReceiverMode','differential-one-symbol'));
% 
% run('E:/web_code/react/fft_project/react-fft/tmp/codex_normalized_h_program_sweep_v1.m');
% 
% NormalizedHSweepResults(:,{ ...
%     'CaseName','ActualModulation','ActualCoding','Rate', ...
%     'BER','FER','LockRate_pct','HDynamicRange_dB', ...
%     'WaveformDuration_s','RouteEvidence','Verdict'})
if exist('NoHSweepRequestedMode','var') && ~isempty(NoHSweepRequestedMode)
    noHSweepMode = lower(string(NoHSweepRequestedMode));
else
    noHSweepMode = "clean";
end
if exist('NoHSweepUserOptions','var') && isstruct(NoHSweepUserOptions)
    noHSweepUserOptions = NoHSweepUserOptions;
else
    noHSweepUserOptions = struct();
end
clear NoHSweepRequestedMode NoHSweepUserOptions;

noHSweepThisFile = mfilename('fullpath');
noHSweepTmpDir = fileparts(noHSweepThisFile);
noHSweepProjectDir = fileparts(noHSweepTmpDir);
noHSweepSourceDir = fullfile(noHSweepProjectDir,'src','python');
addpath(noHSweepSourceDir,'-begin');
rehash;

noHSweepCfg = localNoHConfig(noHSweepMode,noHSweepUserOptions,noHSweepTmpDir);
noHSweepCases = localBuildNoHCases(noHSweepCfg);
noHSweepProfiles = localBuildImpairmentProfiles(noHSweepCfg);
noHSweepJobs = localBuildJobs(noHSweepCases,noHSweepProfiles);

noHSweepFirstJob = max(1,round(noHSweepCfg.StartJob));
noHSweepLastJob = min(numel(noHSweepJobs), ...
    noHSweepFirstJob + max(0,round(noHSweepCfg.MaxJobs)) - 1);
if isinf(noHSweepCfg.MaxJobs)
    noHSweepLastJob = numel(noHSweepJobs);
end

fprintf('\n================ %s PROGRAM SWEEP ================\n', ...
    char(noHSweepCfg.DisplayName));
fprintf('Mode             : %s\n',noHSweepCfg.Mode);
fprintf('Case definitions : %d (%d modulation, %d coding/line-code)\n', ...
    numel(noHSweepCases),nnz([noHSweepCases.Family] == "modulation"), ...
    nnz([noHSweepCases.Family] == "coding"));
if noHSweepCfg.RunCodingSweep
    fprintf('Coding modulation: %s (4D-TCM standalone cases=%d)\n', ...
        char(string(noHSweepCfg.CodingSweepModType)), ...
        logical(noHSweepCfg.Include4DTCM));
end
fprintf('Damage profiles  : %d\n',numel(noHSweepProfiles));
fprintf('Jobs selected    : %d:%d of %d\n', ...
    noHSweepFirstJob,noHSweepLastJob,numel(noHSweepJobs));
if noHSweepCfg.Mode == "normalizedh"
    fprintf('H channel        : ON, normalized, %s\n',noHSweepCfg.ChannelFilePath);
    fprintf('Equalizer        : ON, %s (known-H/oracle equalizer forced OFF)\n', ...
        noHSweepCfg.EqualizerMode);
else
    fprintf('H/equalizer      : forced OFF / forced OFF\n');
end
if noHSweepCfg.Mode == "impairment"
    fprintf(['Noise convention : noiseMode=snr (AWGN at measured digital SNR); ' ...
        'not PSD/link margin\n']);
end
fprintf(['Pass meaning     : short integration screen only; it does not prove ' ...
    'a BER waterfall or long-run FER\n\n']);

noHSweepRows = repmat(localEmptyNoHRow(),0,1);
if noHSweepFirstJob <= noHSweepLastJob
    for noHSweepJobIndex = noHSweepFirstJob:noHSweepLastJob
        noHSweepJob = noHSweepJobs(noHSweepJobIndex);
        fprintf('[%03d/%03d] %-10s | %-30s | %s\n', ...
            noHSweepJobIndex,numel(noHSweepJobs), ...
            char(noHSweepJob.Case.Family),char(noHSweepJob.Case.Name), ...
            char(noHSweepJob.Profile.Name));

        noHSweepRow = localRunNoHJob(noHSweepJob,noHSweepCfg,noHSweepJobIndex);
        noHSweepRows(end+1,1) = noHSweepRow; %#ok<SAGROW>
        fprintf('  BER=%-10.4g FER=%-9.4g Lock=%6.2f%% Route=%-10s %s (%.2fs)\n', ...
            noHSweepRow.BER,noHSweepRow.FER,noHSweepRow.LockRate_pct, ...
            char(noHSweepRow.RouteStatus),char(noHSweepRow.Verdict), ...
            noHSweepRow.Elapsed_s);
        if noHSweepRow.Verdict == "RUN_ERROR"
            fprintf(2,'  %s: %s\n',noHSweepRow.ErrorIdentifier, ...
                noHSweepRow.ErrorMessage);
        end

        if noHSweepCfg.SaveCSV
            writetable(struct2table(noHSweepRows),noHSweepCfg.OutputCSV);
        end
    end
end

NoHSweepResults = struct2table(noHSweepRows);
NoHSweepCaseDefinitions = noHSweepCases;
NoHSweepImpairmentProfiles = noHSweepProfiles;
if noHSweepCfg.Mode == "clean"
    NoHCleanSweepResults = NoHSweepResults;
    NoHCleanSweepCaseDefinitions = NoHSweepCaseDefinitions;
elseif noHSweepCfg.Mode == "impairment"
    NoHImpairmentSweepResults = NoHSweepResults;
    NoHImpairmentSweepCaseDefinitions = NoHSweepCaseDefinitions;
    NoHImpairmentProfiles = NoHSweepImpairmentProfiles;
else
    NormalizedHSweepResults = NoHSweepResults;
    NormalizedHSweepCaseDefinitions = NoHSweepCaseDefinitions;
end

fprintf('\n================ %s SWEEP SUMMARY ================\n', ...
    char(noHSweepCfg.DisplayName));
if isempty(NoHSweepResults)
    fprintf('No jobs were selected.\n');
else
    noHSweepVerdicts = unique(NoHSweepResults.Verdict,'stable');
    for noHSweepVerdictIndex = 1:numel(noHSweepVerdicts)
        noHSweepVerdict = noHSweepVerdicts(noHSweepVerdictIndex);
        fprintf('%-18s %4d\n',char(noHSweepVerdict), ...
            nnz(NoHSweepResults.Verdict == noHSweepVerdict));
    end
    if noHSweepCfg.Mode == "normalizedh"
        disp(NoHSweepResults(:,{'JobIndex','Family','CaseName', ...
            'BER','FER','LockRate_pct','HActual','HGain_dB', ...
            'HNormalizationGain_dB','HNetMeanGain_dB', ...
            'HDynamicRange_dB','WaveformDuration_s','EqualizerActual', ...
            'EqualizerModeActual','RouteStatus','Verdict'}));
    else
        disp(NoHSweepResults(:,{'JobIndex','Family','CaseName', ...
            'Impairment','ImpairmentPoint','BER','FER','LockRate_pct', ...
            'RouteStatus','Verdict'}));
    end
end
if noHSweepCfg.SaveCSV
    fprintf('CSV: %s\n',noHSweepCfg.OutputCSV);
else
    fprintf('No files were written; results remain in the MATLAB workspace.\n');
end

%% Local functions
function cfg = localNoHConfig(mode,user,tmpDir)
    if ~any(mode == ["clean","impairment","normalizedh"])
        error('codex_noh_program_sweep_v1:InvalidMode', ...
            'Mode must be clean, impairment, or normalizedh, not "%s".',mode);
    end
    cfg = struct();
    cfg.Mode = mode;
    cfg.DisplayName = "No-H";
    cfg.BaseSeed = 364232726;
    cfg.RunModulationSweep = true;
    cfg.RunCodingSweep = true;
    cfg.CodingSweepModType = '8PSK';
    cfg.Include4DTCM = true;
    cfg.StartJob = 1;
    cfg.MaxJobs = Inf;
    cfg.VerboseReceiverLog = false;
    cfg.SaveCSV = false;
    cfg.OutputCSV = fullfile(tmpDir,sprintf('noh_%s_program_sweep_%s.csv', ...
        mode,datestr(now,'yyyymmdd_HHMMSS')));
    cfg.SymbolRate = 10e6;
    cfg.SamplesPerSymbol = 8;
    cfg.BERWarmUpFrames = 4;
    cfg.BERFrames = 12;
    cfg.MaxBER = 0;
    cfg.MinLockRate = 0.80;
    cfg.NoiseSNRdB = [30 20 15 10];
    cfg.CFOHz = [5e3 20e3 50e3];
    cfg.PhaseDeg = [15 45 90];
    cfg.DelaySamples = [0.10 0.25 0.45];
    cfg.IncludeCombinedPoint = true;
    cfg.ImpairmentGroups = ["baseline","noise","cfo","phase","delay","combined"];
    cfg.ChannelFilePath = ...
        'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat';
    cfg.ChannelInterpolationMethod = 'linear';
    cfg.ChannelOutOfRangeMode = 'wrap';
    cfg.InterpolateChannelDelays = false;
    cfg.EqualizerMode = 'blind-cma-lms';
    cfg.ReceiverOverrides = struct();
    if mode == "impairment"
        cfg.BERFrames = 8;
        cfg.MaxBER = 1e-3;
    elseif mode == "normalizedh"
        cfg.DisplayName = "Normalized-H";
        % Cover the known late std7 fade; callers can shorten this explicitly.
        cfg.BERWarmUpFrames = 8;
        cfg.BERFrames = 60;
    end
    userNames = fieldnames(user);
    for k = 1:numel(userNames)
        cfg.(userNames{k}) = user.(userNames{k});
    end
    cfg.Mode = mode;
    if mode == "normalizedh"
        cfg.DisplayName = "Normalized-H";
        if ~isfile(cfg.ChannelFilePath)
            error('codex_noh_program_sweep_v1:MissingChannelFile', ...
                'Normalized-H channel file does not exist: %s', ...
                cfg.ChannelFilePath);
        end
    end
end

function cases = localBuildNoHCases(cfg)
    cases = repmat(localEmptyNoHCase(),0,1);
    base = localNoHBaseParams(cfg);

    if cfg.RunModulationSweep
        modulationDefs = {
            'BPSK',   'BPSK'
            'QPSK',   'QPSK'
            'OQPSK',  'OQPSK'
            '8PSK',   '8PSK'
            '16QAM',  '16QAM'
            '16APSK', '16APSK'
            '32APSK', '32APSK'
            '32QAM',  '32QAM'
            'GMSK',   'GMSK'
            'MSK',    'MSK'
            'UQPSK',  'UQPSK'
            'PCM-FM', 'FM'};
        for k = 1:size(modulationDefs,1)
            displayName = string(modulationDefs{k,1});
            backendName = char(modulationDefs{k,2});
            p = localClearCodingFields(base);
            p.modType = backendName;
            p.channelCoding = 'convolutional';
            p.ConvolutionalCodeRate = '1/2';
            p = localApplyModulationParams(p,backendName);
            cases(end+1,1) = localNoHCase( ... %#ok<AGROW>
                "modulation","mod." + lower(displayName), ...
                displayName + " + convolutional 1/2",backendName, ...
                'convolutional',"1/2","NRZ-L",p, ...
                "Fixed convolutional 1/2; modulation is the only changed axis.");
        end
    end

    if ~cfg.RunCodingSweep
        return;
    end

    % Hold one ordinary modulation fixed while channel coding/rate changes.
    cases = localAppendCodingCase(cases,base,'none','none',struct(),1115,"NRZ-L","");
    convRates = {'1/2','2/3','3/4','5/6','7/8'};
    for k = 1:numel(convRates)
        rate = convRates{k};
        tfBytes = 1115;
        if strcmp(rate,'5/6'), tfBytes = 1116; end
        if strcmp(rate,'7/8'), tfBytes = 1123; end
        cases = localAppendCodingCase(cases,base,'convolutional',rate, ...
            struct('ConvolutionalCodeRate',rate),tfBytes,"NRZ-L","");
    end
    cases = localAppendCodingCase(cases,base,'RS','223/255', ...
        struct('RSMessageLength',223,'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false),223,"NRZ-L","");
    cases = localAppendCodingCase(cases,base,'RS','239/255', ...
        struct('RSMessageLength',239,'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false),239,"NRZ-L","");
    cases = localAppendCodingCase(cases,base,'concatenated','RS223+conv1/2', ...
        struct('RSMessageLength',223,'RSInterleavingDepth',1, ...
        'IsRSMessageShortened',false,'ConvolutionalCodeRate','1/2'), ...
        223,"NRZ-L","Concatenated RS + convolutional is one combined code.");

    ldpcRates = {'1/2','2/3','4/5','7/8'};
    for k = 1:numel(ldpcRates)
        rate = ldpcRates{k};
        informationBits = 1024;
        if strcmp(rate,'7/8'), informationBits = 7136; end
        extra = struct('CodeRate',rate, ...
            'NumBitsInInformationBlock',informationBits, ...
            'IsLDPCOnSMTF',false);
        cases = localAppendCodingCase(cases,base,'LDPC',rate,extra,1115,"NRZ-L","");
    end

    turboRates = {'1/2','1/3','1/4','1/6'};
    for k = 1:numel(turboRates)
        rate = turboRates{k};
        extra = struct('CodeRate',rate,'NumBitsInInformationBlock',1784);
        cases = localAppendCodingCase(cases,base,'Turbo',rate,extra,1115,"NRZ-L","");
    end

    % Ordinary-TM TPC exposes only the two deployable shortened rates.
    % Rate 1/2 needs 8 blocks for byte alignment (2025 bytes/TF).  The
    % established rate-2/3 profile uses 4 blocks (1352 bytes/TF).  Native
    % 57x57 is intentionally excluded: its first byte-aligned frame needs
    % 8 blocks = 3249 bytes, above the generator's 2048-byte TF limit.
    tpcDefs = {
        '1/2',   8
        '2/3',   4};
    for k = 1:size(tpcDefs,1)
        rate = tpcDefs{k,1};
        blocks = tpcDefs{k,2};
        extra = struct('TPCCodeRate',rate,'TPCBlocksPerTF',blocks, ...
            'TPCInterleaver','auto','berWarmUpFrames',4,'berFrames',12);
        cases = localAppendCodingCase(cases,base,'TPC', ...
            sprintf('%s x%d',rate,blocks),extra,1115,"NRZ-L", ...
            "TPC frame bytes are recomputed by the evaluator from rate and block count.");
    end

    % Differential is PCM line coding, not a channelCoding value.
    cases = localAppendCodingCase(cases,base,'none','differential NRZ-M', ...
        struct(),1115,"NRZ-M", ...
        "Differential/NRZ-M is line coding; channelCoding remains none.");
    cases = localAppendCodingCase(cases,base,'none','differential NRZ-S', ...
        struct(),1115,"NRZ-S", ...
        "Differential/NRZ-S is line coding; channelCoding remains none.");

    % 4D-TCM is a standalone joint coded-modulation waveform.  It does not
    % inherit CodingSweepModType and can be excluded from an ordinary-code
    % sweep (for example, a GMSK + FEC compatibility sweep).
    if cfg.Include4DTCM
        effDefs = [2.00 8; 2.25 14; 2.50 16; 2.75 18];
        for k = 1:size(effDefs,1)
            eff = effDefs(k,1);
            tfBytes = effDefs(k,2);
            p = localClearCodingFields(base);
            p.modType = '4D-8PSK-TCM';
            p.channelCoding = 'none';
            p.ModulationEfficiency = eff;
            p.NumBytesInTransferFrame = tfBytes;
            p.berWarmUpFrames = 2;
            p.berFrames = 3;
            p.tcmSymbolSkip = 0;
            p.tcmBitSkip = 0;
            p.tcmSearchAll = false;
            p.tcmSampleOffsetSearchAll = true;
            cases(end+1,1) = localNoHCase( ... %#ok<AGROW>
                "coding",sprintf('code.4dtcm.eff%03d',round(100*eff)), ...
                sprintf('4D-TCM efficiency %.2f',eff),'4D-8PSK-TCM', ...
                'none',sprintf('eff %.2f',eff),"NRZ-L",p, ...
                "Standalone 4D-8PSK-TCM; it is not ordinary modulation plus a channel code.");
        end
    end
end

function p = localNoHBaseParams(cfg)
    p = struct();
    p.modType = char(string(cfg.CodingSweepModType));
    p.channelCoding = 'none';
    p.symbolRate = cfg.SymbolRate;
    p.sps = cfg.SamplesPerSymbol;
    p.snr = 40;
    p.noiseMode = 'off';
    p.noisePlacement = 'afterChannel';
    p.cfo = 0;
    p.phaseOffset = 0;
    p.delay = 0;
    p.RolloffFactor = 0.35;
    p.WaveformMode = 'ordinaryTM';
    p.NumBytesInTransferFrame = 1115;
    p.hasASM = true;
    p.RandomizerEnabled = false;
    p.RandomizerFECPosition = 'afterEncoding';
    p.DataPathMode = 'single';
    p.TMDataSource = 'random';
    p.PCMFormat = 'NRZ-L';
    p.berWarmUpFrames = cfg.BERWarmUpFrames;
    p.berFrames = cfg.BERFrames;
    p.excludeBERWarmUpFrames = true;
    p.enableHChannel = false;
    p.HMode = 'none';
    p.normalizeHChannel = false;
    p.enableEqualizer = false;
    p.equalizerMode = 'off';
    p.enableKnownHPreEqualizer = false;
    p.normalizeEqualizerOutput = false;
    p.enableConverterChain = false;
    p.enableADCEquivalent = false;
    p.inputLevelDbm = -10;
    p.AGCEnabled = false;
    p.showFigures = false;
    p.showPipelineFigure = false;
    p.showDamageBudgetFigure = false;
    p.showPowerFigure = false;
    p.debugAdaptiveEqualizer = false;
    p.debugHFrameStats = false;
    p.debugPerFrameBERSummary = false;
    if cfg.Mode == "normalizedh"
        p.enableHChannel = true;
        p.HMode = 'h_matrix_file';
        p.channelFilePath = cfg.ChannelFilePath;
        p.channelInterpolationMethod = cfg.ChannelInterpolationMethod;
        p.channelOutOfRangeMode = cfg.ChannelOutOfRangeMode;
        p.interpolateChannelDelays = cfg.InterpolateChannelDelays;
        p.normalizeHChannel = true;
        p.enableEqualizer = true;
        p.equalizerMode = cfg.EqualizerMode;
        p.normalizeEqualizerOutput = true;
        % These are receiver-observable paths.  No oracle H is supplied.
        p.enablePilotlessAPSKPostFrontEndAdaptiveEqualizer = false;
        p.enableQAMPowerGainTracker = true;
        p.enableQAMPostBPSAdaptiveEqualizer = false;
        p.enableOQPSKHighRateTracking = true;
        p.enableUQPSKHighRateTracking = true;
        p.enableUQPSKPostCarrierAdaptiveEqualizer = true;
        p.enableUQPSKDualBandwidthCarrierPLL = true;
        p.enableGMSKResidualDopplerTracker = true;
        p.enableBlindReliabilityManager = false;
    end
end

function p = localApplyModulationParams(p,modulation)
    key = upper(string(modulation));
    if contains(key,'APSK')
        p.APSKReceiverMode = 'pilotless';
        p.HasTMAPSKPilots = false;
        p.enablePilotlessAPSKComplexGainTracker = true;
    elseif key == "GMSK"
        p.BandwidthTimeProduct = 0.5;
        p.GMSKDetectionMode = 'official-viterbi-frame-reset';
        p.enableGMSKCoarseFrequencyCompensator = true;
    elseif key == "MSK"
        p.enableCPMCoarseFrequencyCompensator = true;
    elseif key == "UQPSK"
        p.RRatio = 2;
        p.ARatio = 2;
        p.enableUQPSKFFTCoarseCFO = true;
    elseif key == "FM"
        p.RolloffFactor = 0.5;
        p.TZZS = 0.715;
        p.debugFM = false;
    end
end

function cases = localAppendCodingCase(cases,base,coding,rate,extra,tfBytes,pcm,note)
    p = localClearCodingFields(base);
    p.modType = char(string(base.modType));
    p.channelCoding = coding;
    p.NumBytesInTransferFrame = tfBytes;
    p.PCMFormat = char(pcm);
    p = localMergeStruct(p,extra);
    p = localApplyModulationParams(p,p.modType);
    idText = string(coding) + "." + string(rate);
    id = "code." + lower(regexprep(idText,'[^a-zA-Z0-9]+','_'));
    name = string(p.modType) + " + " + string(coding) + " " + string(rate);
    cases(end+1,1) = localNoHCase( ... %#ok<AGROW>
        "coding",id,name,p.modType,coding,string(rate),string(pcm),p,string(note));
end

function p = localClearCodingFields(p)
    names = {'ConvolutionalCodeRate','CodeRate','NumBitsInInformationBlock', ...
        'IsLDPCOnSMTF','LDPCCodeblockSize','TPCCodeRate','TPCBlocksPerTF', ...
        'TPCInterleaver','RSMessageLength','RSInterleavingDepth', ...
        'IsRSMessageShortened','RSShortenedMessageLength','ModulationEfficiency'};
    for k = 1:numel(names)
        if isfield(p,names{k}), p = rmfield(p,names{k}); end
    end
end

function out = localMergeStruct(out,extra)
    names = fieldnames(extra);
    for k = 1:numel(names)
        out.(names{k}) = extra.(names{k});
    end
end

function profiles = localBuildImpairmentProfiles(cfg)
    profiles = repmat(localEmptyProfile(),0,1);
    profiles(end+1,1) = localProfile('baseline','clean', ...
        'off',100,0,0,0); %#ok<AGROW>
    if any(cfg.Mode == ["clean","normalizedh"])
        return;
    end
    groups = lower(string(cfg.ImpairmentGroups));
    if any(groups == "noise")
        for value = double(cfg.NoiseSNRdB(:).')
            profiles(end+1,1) = localProfile('noise', ... %#ok<AGROW>
                sprintf('SNR %.1f dB',value),'snr',value,0,0,0);
        end
    end
    if any(groups == "cfo")
        for value = double(cfg.CFOHz(:).')
            profiles(end+1,1) = localProfile('cfo', ... %#ok<AGROW>
                sprintf('CFO %+.0f Hz',value),'off',100,value,0,0);
        end
    end
    if any(groups == "phase")
        for value = double(cfg.PhaseDeg(:).')
            profiles(end+1,1) = localProfile('phase', ... %#ok<AGROW>
                sprintf('phase %+.1f deg',value),'off',100,0,value,0);
        end
    end
    if any(groups == "delay")
        for value = double(cfg.DelaySamples(:).')
            profiles(end+1,1) = localProfile('delay', ... %#ok<AGROW>
                sprintf('delay %.2f sample',value),'off',100,0,0,value);
        end
    end
    if cfg.IncludeCombinedPoint && any(groups == "combined")
        profiles(end+1,1) = localProfile('combined', ... %#ok<AGROW>
            'SNR20+CFO20k+phase15+delay0.25','snr',20,20e3,15,0.25);
    end
end

function jobs = localBuildJobs(cases,profiles)
    jobs = repmat(struct('Case',localEmptyNoHCase(), ...
        'Profile',localEmptyProfile()),0,1);
    % Profile-major order makes the clean reference for every case finish
    % before the first damaged profile starts.
    for iProfile = 1:numel(profiles)
        for iCase = 1:numel(cases)
            jobs(end+1,1) = struct('Case',cases(iCase), ... %#ok<AGROW>
                'Profile',profiles(iProfile));
        end
    end
end

function row = localRunNoHJob(job,cfg,jobIndex)
    row = localEmptyNoHRow();
    p = job.Case.Params;
    if cfg.Mode == "normalizedh"
        p.enableHChannel = true;
        p.HMode = 'h_matrix_file';
        p.channelFilePath = cfg.ChannelFilePath;
        p.channelInterpolationMethod = cfg.ChannelInterpolationMethod;
        p.channelOutOfRangeMode = cfg.ChannelOutOfRangeMode;
        p.interpolateChannelDelays = cfg.InterpolateChannelDelays;
        p.normalizeHChannel = true;
        p.enableEqualizer = true;
        p.equalizerMode = cfg.EqualizerMode;
        p.normalizeEqualizerOutput = true;
    else
        p.enableHChannel = false;
        p.HMode = 'none';
        p.normalizeHChannel = false;
        p.enableEqualizer = false;
        p.equalizerMode = 'off';
        p.normalizeEqualizerOutput = false;
    end
    p.enableKnownHPreEqualizer = false;
    p.noiseMode = char(job.Profile.NoiseMode);
    p.snr = job.Profile.SNR_dB;
    p.cfo = job.Profile.CFO_Hz;
    p.phaseOffset = job.Profile.Phase_deg;
    p.delay = job.Profile.Delay_samples;
    if cfg.VerboseReceiverLog && ...
            strcmpi(string(job.Case.ExpectedModulation),'GMSK')
        p.debugGMSK = false;
        p.debugGMSKSecondOrderPLL = true;
        p.debugGMSKSecondOrderPLLTrace = true;
        p.gmskPLLDebugTraceDecimationSamples = 64;
        p.debugGMSKErrorBits = true;
        p.debugHFrameStats = true;
        p.debugHFrameStatsCount = 1000;
        p.debugHFrameStatsPrint = false;
        p.debugPerFrameBERCount = 0;
        p.debugPerFrameBERSummary = true;
        p.debugPerFrameBERNonzeroCount = 12;
    end
    if ~isempty(cfg.ReceiverOverrides)
        p = localMergeStruct(p,cfg.ReceiverOverrides);
    end

    row.JobIndex = jobIndex;
    row.Family = job.Case.Family;
    row.CaseID = job.Case.ID;
    row.CaseName = job.Case.Name;
    row.Impairment = job.Profile.Group;
    row.ImpairmentPoint = job.Profile.Name;
    row.RequestedModulation = string(job.Case.ExpectedModulation);
    row.RequestedCoding = string(job.Case.ExpectedCoding);
    row.Rate = job.Case.Rate;
    row.PCMFormat = job.Case.PCMFormat;
    row.NoiseMode = job.Profile.NoiseMode;
    row.SNR_dB = job.Profile.SNR_dB;
    row.CFO_Hz = job.Profile.CFO_Hz;
    row.CFO_ppm_of_Rs = 1e6*job.Profile.CFO_Hz/double(p.symbolRate);
    row.Phase_deg = job.Profile.Phase_deg;
    row.Delay_samples = job.Profile.Delay_samples;
    row.Notes = job.Case.Notes;

    rng(cfg.BaseSeed,'twister');
    t0 = tic;
    try
        if cfg.VerboseReceiverLog
            [raw,~] = run_ccsds_tm_evaluation(p);
        else
            receiverLog = evalc('[raw,~] = run_ccsds_tm_evaluation(p);'); %#ok<NASGU>
        end
        out = localDecodeNoHOutput(raw);
        if cfg.VerboseReceiverLog && ...
                strcmpi(string(job.Case.ExpectedModulation),'GMSK')
            assignin('base','GMSKDebugResult',out);
        end
        row.EngineSuccess = localLogicalField(out,'success',true);
        row.ActualModulation = localStringField(out,'modType',"");
        row.ActualCoding = localStringField(out,'channelCoding',"");
        row.BER = localNumericField(out,{'BER','ber'},NaN);
        row.FER = localNumericField(out,{'FER','FrameErrorRate'},NaN);
        row.FrameErrors = localNumericField(out,'FrameErrors',NaN);
        row.CountedFrames = localNumericField(out,'CountedFrames',NaN);
        row.MatchedFrames = localNumericField(out,'MatchedFrames',NaN);
        row.LockRate_pct = 100*localNumericField(out,{'LockRate','lockRate'},NaN);
        row.EVM_post_pct = localNumericField(out,'EVM_post_pct',NaN);
        row.MER_dB = localNumericField(out,'MER_dB',NaN);
        row.SNR_est_dB = localNumericField(out,'SNR_est_dB',NaN);
        row.NoiseEquivalentSNR_dB = localNumericField(out, ...
            'NoiseEquivalentSNR_dB',NaN);
        row.ResidualCFO_Hz = localNumericField(out, ...
            {'ResidualCFO_Hz','residCFO_Hz'},NaN);
        row.HActual = localLogicalField(out,'HEnabled',false);
        row.HModeActual = localStringField(out,'HMode',"");
        row.HGain_dB = localNumericField(out,'HGain_dB',NaN);
        if isfield(out,'HChannelMeta') && isstruct(out.HChannelMeta)
            row.HNormalizationGain_dB = localNumericField( ...
                out.HChannelMeta,'NormalizationGain_dB',NaN);
            row.HDynamicRange_dB = localNumericField( ...
                out.HChannelMeta,'DominantMagnitudeDynamicRange_dB',NaN);
            row.WaveformDuration_s = localNumericField( ...
                out.HChannelMeta,'WaveformDuration_s',NaN);
            row.HSourceDuration_s = localNumericField( ...
                out.HChannelMeta,'ChannelSourceDuration_s',NaN);
        end
        row.HNetMeanGain_dB = row.HGain_dB + row.HNormalizationGain_dB;
        row.EqualizerActual = localLogicalField(out, ...
            'AdaptiveEqualizerEnabled',false);
        row.EqualizerModeActual = localStringField( ...
            out,'AdaptiveEqualizerMode',"");
        row.EqualizerReason = localStringField( ...
            out,'AdaptiveEqualizerReason',"");
        row.QAMBlindPhaseSearchApplied = localLogicalField( ...
            out,'QAMBlindPhaseSearchApplied',false);
        row.QAMPowerGainApplied = localLogicalField( ...
            out,'QAMPowerGainApplied',false);
        row.PilotlessAPSKApplied = localLogicalField( ...
            out,'PilotlessAPSKApplied',false);
        row.GMSKResidualTrackerApplied = localLogicalField( ...
            out,'GMSKResidualTrackerApplied',false);
        row.UQPSKCarrierPLLApplied = localLogicalField( ...
            out,'UQPSKCarrierPLLApplied',false);
        [row.RouteStatus,row.RouteEvidence] = localNoHRouteStatus( ...
            out,job.Case,row.HActual,row.EqualizerActual,cfg, ...
            row.HGain_dB,row.HNormalizationGain_dB);
        if ~row.EngineSuccess
            row.ErrorMessage = localStringField(out,'errorMsg', ...
                "Evaluator returned success=false.");
        end
    catch ME
        row.EngineSuccess = false;
        row.RouteStatus = "UNVERIFIED";
        row.ErrorIdentifier = string(ME.identifier);
        row.ErrorMessage = string(ME.message);
    end
    row.Elapsed_s = toc(t0);

    enoughFrames = isfinite(row.CountedFrames) && row.CountedFrames >= 1;
    row.MetricPass = row.EngineSuccess && row.RouteStatus == "VERIFIED" && ...
        enoughFrames && isfinite(row.BER) && row.BER <= cfg.MaxBER && ...
        isfinite(row.LockRate_pct) && row.LockRate_pct >= 100*cfg.MinLockRate;
    if ~row.EngineSuccess
        row.Verdict = "RUN_ERROR";
    elseif row.RouteStatus == "MISMATCH"
        row.Verdict = "ROUTE_MISMATCH";
    elseif row.RouteStatus == "UNVERIFIED"
        row.Verdict = "ROUTE_UNVERIFIED";
    elseif row.MetricPass
        row.Verdict = "PASS";
    else
        row.Verdict = "DECODE_FAIL";
    end
end

function [status,evidence] = localNoHRouteStatus( ...
        out,c,hActual,eqActual,cfg,hGainDB,hNormalizationGainDB)
    actualMod = localStringField(out,'modType',"");
    actualCoding = localStringField(out,'channelCoding',"");
    expectedMod = string(c.ExpectedModulation);
    expectedCoding = string(c.ExpectedCoding);
    evidence = "mod=" + actualMod + "; coding=" + actualCoding + ...
        "; H=" + string(hActual) + "; adaptiveEq=" + string(eqActual);
    if cfg.Mode == "normalizedh"
        evidence = evidence + sprintf('; Hraw=%+.3f dB; Hnorm=%+.3f dB', ...
            hGainDB,hNormalizationGainDB);
    end
    if strlength(actualMod) == 0 || strlength(actualCoding) == 0
        status = "UNVERIFIED";
        return;
    end
    expectedH = cfg.Mode == "normalizedh";
    normalizedHVerified = ~expectedH || ...
        (isfinite(hGainDB) && isfinite(hNormalizationGainDB) && ...
        abs(hGainDB + hNormalizationGainDB) <= 0.05);
    if ~strcmpi(actualMod,expectedMod) || ...
            ~strcmpi(actualCoding,expectedCoding) || hActual ~= expectedH || ...
            (~expectedH && eqActual) || ~normalizedHVerified
        status = "MISMATCH";
        return;
    end
    status = "VERIFIED";
    key = upper(expectedMod);
    if contains(key,'APSK')
        route = localStringField(out,'APSKReceiverMode',"");
        evidence = evidence + "; APSK=" + route;
        if strlength(route) == 0, status = "UNVERIFIED"; end
    elseif key == "GMSK"
        route = localStringField(out,'GMSKDetectorUsed',"");
        evidence = evidence + "; GMSK=" + route;
        if strlength(route) == 0, status = "UNVERIFIED"; end
    elseif key == "UQPSK"
        dataPathMode = lower(localStringField(out,'DataPathMode',""));
        if dataPathMode == "single"
            % IFramesPerQFrame describes unequalDualIQ frame scheduling and
            % is intentionally absent in a single-stream UQPSK run.  Verify
            % this route through the dedicated UQPSK carrier loop instead.
            pllApplied = localLogicalField(out, ...
                'UQPSKCarrierPLLApplied',false);
            evidence = evidence + sprintf('; UQPSK single PLL=%d', ...
                pllApplied);
            if ~pllApplied, status = "UNVERIFIED"; end
        else
            rRatio = localNumericField(out,'UQPSKRRatio',NaN);
            aRatio = localNumericField(out,'UQPSKARatio',NaN);
            iPerQ = localNumericField(out,'IFramesPerQFrame',NaN);
            evidence = evidence + sprintf('; UQPSK R=%g A=%g I/Q=%g', ...
                rRatio,aRatio,iPerQ);
            uqpskMetadataOK = all(isfinite([rRatio,aRatio,iPerQ])) && ...
                max(abs([rRatio,aRatio,iPerQ] - 2)) < 1e-12;
            if ~uqpskMetadataOK, status = "UNVERIFIED"; end
        end
    elseif key == "FM"
        route = localStringField(out,'fmReceiverMode',"");
        evidence = evidence + "; FM=" + route;
        if strlength(route) == 0, status = "UNVERIFIED"; end
    end
end

function out = localDecodeNoHOutput(raw)
    if isstruct(raw)
        out = raw;
    elseif ischar(raw) || isstring(raw)
        out = jsondecode(char(raw));
    else
        error('codex_noh_program_sweep_v1:UnexpectedOutput', ...
            'Unsupported evaluator output class %s.',class(raw));
    end
end

function value = localNumericField(s,names,defaultValue)
    value = defaultValue;
    if ischar(names) || isstring(names), names = cellstr(names); end
    for k = 1:numel(names)
        name = names{k};
        if isfield(s,name) && ~isempty(s.(name))
            candidate = double(s.(name));
            if isscalar(candidate), value = candidate; return; end
        end
    end
end

function value = localStringField(s,name,defaultValue)
    value = string(defaultValue);
    if isfield(s,name) && ~isempty(s.(name))
        value = string(s.(name));
        if ~isscalar(value), value = join(value,','); end
    end
end

function value = localLogicalField(s,name,defaultValue)
    value = logical(defaultValue);
    if isfield(s,name) && ~isempty(s.(name))
        raw = s.(name);
        if islogical(raw) || isnumeric(raw)
            value = logical(raw(1));
        else
            value = any(lower(string(raw)) == ["true","1","yes","on"]);
        end
    end
end

function c = localNoHCase(family,id,name,expectedMod,expectedCoding,rate,pcm,p,note)
    c = struct('Family',string(family),'ID',string(id),'Name',string(name), ...
        'ExpectedModulation',string(expectedMod), ...
        'ExpectedCoding',string(expectedCoding),'Rate',string(rate), ...
        'PCMFormat',string(pcm),'Params',p,'Notes',string(note));
end

function c = localEmptyNoHCase()
    c = localNoHCase("","","","","","","",struct(),"");
end

function p = localProfile(group,name,noiseMode,snr,cfo,phase,delay)
    p = struct('Group',string(group),'Name',string(name), ...
        'NoiseMode',string(noiseMode),'SNR_dB',double(snr), ...
        'CFO_Hz',double(cfo),'Phase_deg',double(phase), ...
        'Delay_samples',double(delay));
end

function p = localEmptyProfile()
    p = localProfile("","","off",100,0,0,0);
end

function row = localEmptyNoHRow()
    row = struct( ...
        'JobIndex',NaN,'Family',"",'CaseID',"",'CaseName',"", ...
        'Impairment',"",'ImpairmentPoint',"", ...
        'RequestedModulation',"",'ActualModulation',"", ...
        'RequestedCoding',"",'ActualCoding',"",'Rate',"", ...
        'PCMFormat',"",'NoiseMode',"",'SNR_dB',NaN, ...
        'NoiseEquivalentSNR_dB',NaN,'CFO_Hz',NaN, ...
        'CFO_ppm_of_Rs',NaN,'Phase_deg',NaN,'Delay_samples',NaN, ...
        'HActual',false,'HModeActual',"",'HGain_dB',NaN, ...
        'HNormalizationGain_dB',NaN,'HNetMeanGain_dB',NaN, ...
        'HDynamicRange_dB',NaN,'WaveformDuration_s',NaN, ...
        'HSourceDuration_s',NaN, ...
        'EqualizerActual',false,'EqualizerModeActual',"", ...
        'EqualizerReason',"",'QAMBlindPhaseSearchApplied',false, ...
        'QAMPowerGainApplied',false,'PilotlessAPSKApplied',false, ...
        'GMSKResidualTrackerApplied',false,'UQPSKCarrierPLLApplied',false, ...
        'RouteStatus',"", ...
        'RouteEvidence',"",'EngineSuccess',false,'BER',NaN,'FER',NaN, ...
        'FrameErrors',NaN,'CountedFrames',NaN,'MatchedFrames',NaN, ...
        'LockRate_pct',NaN,'EVM_post_pct',NaN,'MER_dB',NaN, ...
        'SNR_est_dB',NaN,'ResidualCFO_Hz',NaN,'MetricPass',false, ...
        'Verdict',"",'ErrorIdentifier',"",'ErrorMessage',"", ...
        'Elapsed_s',NaN,'Notes',"");
end
