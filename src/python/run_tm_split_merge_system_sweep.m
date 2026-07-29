function Summary = run_tm_split_merge_system_sweep(profile, startAt, maxCases)
%RUN_TM_SPLIT_MERGE_SYSTEM_SWEEP Comprehensive TM single/dualIQ regression.
%
% Usage from MATLAB:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   Summary = run_tm_split_merge_system_sweep("full");
%   Summary = run_tm_split_merge_system_sweep("full", 11);      % resume at case 11
%   Summary = run_tm_split_merge_system_sweep("full", 1, 20);   % run first 20 cases
%   Summary = run_tm_split_merge_system_sweep("full", 256, 258);% run cases 256..258
%
% Profiles:
%   "smoke" : shorter subset, useful after small edits.
%   "full"  : all Phase-1 split mods and coding families, plus merge extras.
%   "deep"  : full plus clean/sync channel profiles and extra LDPC/turbo rates.

if nargin < 1 || isempty(profile)
    profile = "full";
end
profile = lower(string(profile));
if nargin < 2 || isempty(startAt)
    startAt = [];
end
if nargin < 3 || isempty(maxCases)
    maxCases = [];
end

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);

cfg = localDefaultConfig(profile, scriptDir);
if ~isempty(startAt)
    cfg.startAt = max(1, round(double(startAt)));
end
if ~isempty(maxCases)
    cfg.maxCases = max(1, round(double(maxCases)));
end
cases = localBuildCases(cfg);

if cfg.maxCases < inf
    cases = cases(1:min(numel(cases), cfg.maxCases));
end

fprintf('\n===== TM single/dualIQ data-path system sweep =====\n');
fprintf('profile=%s, cases=%d, output=%s\n', char(cfg.profile), numel(cases), cfg.outDir);
fprintf(['pass rule: success && BER <= %.3g && LockRate >= %.1f%% ' ...
    '&& FER <= %.3g (FER NaN ignored)\n'], ...
    cfg.passBER, cfg.passLockRate * 100, cfg.passFER);

if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end

Results = repmat(localEmptyResult(), 0, 1);
for iCase = cfg.startAt:numel(cases)
    c = cases(iCase);
    fprintf('\n[%03d/%03d] %s\n', iCase, numel(cases), c.name);

    r = localEmptyResult();
    r.Idx = iCase;
    r.Name = string(c.name);
    r.PathMode = string(c.pathMode);
    r.Modulation = string(c.modType);
    r.Coding = string(c.coding);
    r.Rate = string(c.rate);
    r.Randomizer = string(c.randLabel);
    r.Position = string(c.position);
    r.ChannelProfile = string(c.channelProfile);

    tCase = tic;
    try
        raw = run_ccsds_tm_evaluation(c.params);
        if ischar(raw) || isstring(raw)
            m = jsondecode(char(raw));
        else
            m = raw;
        end

        r.Success = logical(localGet(m, 'success', false));
        r.BER = double(localGet(m, 'BER', NaN));
        r.LockRate = double(localGet(m, 'LockRate', NaN));
        r.FER = double(localGet(m, 'FER', localGet(m, 'FrameErrorRate', NaN)));
        r.FrameErrors = double(localGet(m, 'FrameErrors', NaN));
        r.CountedFrames = double(localGet(m, 'CountedFrames', NaN));
        r.AcquisitionFrames = double(localGet(m, 'AcquisitionFrames', NaN));
        r.ElapsedTime = double(localGet(m, 'ElapsedTime', toc(tCase)));
        r.Error = string(localGet(m, 'errorMsg', localGet(m, 'error', '')));
    catch ME
        r.Success = false;
        r.BER = -2;
        r.ElapsedTime = toc(tCase);
        r.Error = string(ME.message);
    end

    if isfinite(r.BER) && r.BER < 0
        r.Success = false;
        if strlength(r.Error) == 0
            r.Error = sprintf('run_ccsds_tm_evaluation returned BER=%g sentinel.', r.BER);
        end
    end

    r.Pass = r.Success && isfinite(r.BER) && r.BER >= 0 && r.BER <= cfg.passBER && ...
        isfinite(r.LockRate) && r.LockRate >= cfg.passLockRate && ...
        (~isfinite(r.FER) || r.FER <= cfg.passFER);

    if r.Pass
        r.Status = "PASS";
    elseif r.Success
        r.Status = "FAIL_METRIC";
    else
        r.Status = "ERROR";
    end

    Results(end+1, 1) = r; %#ok<AGROW>
    fprintf('[%s] BER=%.4g, Lock=%.1f%%, FER=%.4g, time=%.1fs\n', ...
        char(r.Status), r.BER, r.LockRate*100, r.FER, r.ElapsedTime);
    if strlength(r.Error) > 0
        fprintf('      error: %s\n', char(r.Error));
    end

    localSaveProgress(cfg.matFile, Results, cases, cfg);
end

Summary = struct2table(Results);
if ~isempty(Results)
    try
        writetable(Summary, cfg.csvFile);
    catch ME
        warning('run_tm_split_merge_system_sweep:WriteSummaryFailed', ...
            'CSV summary write failed: %s.', ME.message);
    end
end

fprintf('\n===== Sweep summary =====\n');
if isempty(Results)
    fprintf('No cases were run.\n');
else
    disp(Summary(:, {'Idx','Status','PathMode','Modulation','Coding','Rate', ...
        'Randomizer','Position','ChannelProfile','BER','LockRate','FER','Error'}));
    fprintf('PASS=%d, FAIL_METRIC=%d, ERROR=%d, total=%d\n', ...
        nnz(Summary.Status == "PASS"), ...
        nnz(Summary.Status == "FAIL_METRIC"), ...
        nnz(Summary.Status == "ERROR"), height(Summary));
    fprintf('Saved MAT: %s\n', cfg.matFile);
    fprintf('Saved CSV: %s\n', cfg.csvFile);
end
end

function cfg = localDefaultConfig(profile, scriptDir)
cfg = struct();
cfg.profile = profile;
cfg.symbolRate = 1e6;
cfg.sps = 4;
cfg.rolloff = 0.35;
cfg.berWarmUpFrames = 6;
cfg.berFrames = 16;
cfg.passBER = 1e-5;
cfg.passFER = 1e-5;
cfg.passLockRate = 0.90;
cfg.startAt = 1;
cfg.maxCases = inf;
cfg.splitPathDebug = false;
cfg.includeFACMAPSK = false;
cfg.includeUnsupportedSplitNegativeTests = false;
cfg.outDir = fullfile(scriptDir, 'sweep_results');
cfg.matFile = fullfile(cfg.outDir, sprintf('tm_split_merge_%s_results.mat', profile));
cfg.csvFile = fullfile(cfg.outDir, sprintf('tm_split_merge_%s_summary.csv', profile));

switch profile
    case "smoke"
        cfg.splitMods = {'QPSK','8PSK','32QAM'};
        cfg.mergeExtraMods = {'BPSK','GMSK'};
        cfg.convRates = {'1/2','5/6','7/8'};
        cfg.ldpcRates = {'1/2'};
        cfg.turboRates = {'1/2'};
        cfg.randCases = localRandCases("smoke");
        cfg.channelProfiles = localChannelProfiles("sync");
        cfg.berFrames = 8;
    case "deep"
        cfg.splitMods = {'QPSK','OQPSK','8PSK','16QAM','32QAM'};
        cfg.mergeExtraMods = {'BPSK','GMSK','FM','UQPSK'};
        cfg.convRates = {'1/2','2/3','3/4','5/6','7/8'};
        cfg.ldpcRates = {'1/2','2/3','4/5'};
        cfg.turboRates = {'1/2','1/3','1/4','1/6'};
        cfg.randCases = localRandCases("full");
        cfg.channelProfiles = localChannelProfiles("deep");
        cfg.berFrames = 24;
    otherwise
        cfg.profile = "full";
        cfg.splitMods = {'QPSK','OQPSK','8PSK','16QAM','32QAM'};
        cfg.mergeExtraMods = {'BPSK','GMSK','FM','UQPSK'};
        cfg.convRates = {'1/2','2/3','3/4','5/6','7/8'};
        cfg.ldpcRates = {'1/2'};
        cfg.turboRates = {'1/2'};
        cfg.randCases = localRandCases("full");
        cfg.channelProfiles = localChannelProfiles("sync");
end
end

function randCases = localRandCases(kind)
randCases = struct('label',{},'enabled',{},'position',{});
randCases(end+1) = struct('label',"randOff",'enabled',false,'position',"afterEncoding");
randCases(end+1) = struct('label',"randAfterFEC",'enabled',true,'position',"afterEncoding");
if kind ~= "smoke"
    randCases(end+1) = struct('label',"randBeforeFEC",'enabled',true,'position',"beforeEncoding");
end
end

function profiles = localChannelProfiles(kind)
profiles = struct('name',{},'snr',{},'cfo',{},'phaseOffset',{},'delay',{});
if kind == "deep"
    profiles(end+1) = struct('name',"clean",'snr',35,'cfo',0,'phaseOffset',0,'delay',0);
end
profiles(end+1) = struct('name',"sync",'snr',30,'cfo',2000,'phaseOffset',10,'delay',0.2);
end

function cases = localBuildCases(cfg)
cases = struct('name',{},'pathMode',{},'modType',{},'coding',{},'rate',{}, ...
    'randLabel',{},'position',{},'channelProfile',{},'params',{});

mainCodeCases = localMainCodeCases(cfg);

for iProf = 1:numel(cfg.channelProfiles)
    ch = cfg.channelProfiles(iProf);
    for iMod = 1:numel(cfg.splitMods)
        modType = cfg.splitMods{iMod};
        pathModes = {'single','dualIQ'};
        for iPath = 1:numel(pathModes)
            pathMode = pathModes{iPath};
            for iCode = 1:numel(mainCodeCases)
                cc = mainCodeCases(iCode);
                if strcmp(pathMode, 'dualIQ') && ~localSplitSupports(cc.coding, modType)
                    continue;
                end
                for iRand = 1:numel(cfg.randCases)
                    rc = cfg.randCases(iRand);
                    c = localMakeCase(cfg, ch, pathMode, modType, cc, rc);
                    cases(end+1, 1) = c; %#ok<AGROW>
                end
            end
        end
    end

    mergeOnlyCodeCases = localMergeOnlyCodeCases();
    mergeOnlyMods = [{'QPSK'}, cfg.mergeExtraMods];
    for iMod = 1:numel(mergeOnlyMods)
        modType = mergeOnlyMods{iMod};
        for iCode = 1:numel(mergeOnlyCodeCases)
            cc = mergeOnlyCodeCases(iCode);
            for iRand = 1:numel(cfg.randCases)
                rc = cfg.randCases(iRand);
                if localSkipUnsupportedCase('single', modType, cc, rc)
                    continue;
                end
                c = localMakeCase(cfg, ch, 'single', modType, cc, rc);
                cases(end+1, 1) = c; %#ok<AGROW>
            end
        end
    end

    if cfg.includeFACMAPSK
        apskCases = localFACMAPSKCases(cfg, ch);
        cases = [cases; apskCases(:)]; %#ok<AGROW>
    end
end
end

function codeCases = localMainCodeCases(cfg)
codeCases = struct('coding',{},'rate',{},'extra',{});
codeCases(end+1) = localCodeCase('none', '-', struct());
codeCases(end+1) = localCodeCase('RS', '223/255', localRSExtra());
for i = 1:numel(cfg.convRates)
    rate = cfg.convRates{i};
    extra = struct('ConvolutionalCodeRate', rate);
    codeCases(end+1) = localCodeCase('convolutional', rate, extra); %#ok<AGROW>
end
for i = 1:numel(cfg.ldpcRates)
    rate = cfg.ldpcRates{i};
    k = localLDPCInfoLength(rate);
    extra = struct('CodeRate', rate, 'NumBitsInInformationBlock', k, ...
        'IsLDPCOnSMTF', false);
    codeCases(end+1) = localCodeCase('LDPC', rate, extra); %#ok<AGROW>
end
for i = 1:numel(cfg.turboRates)
    rate = cfg.turboRates{i};
    extra = struct('CodeRate', rate, 'NumBitsInInformationBlock', 1784);
    codeCases(end+1) = localCodeCase('turbo', rate, extra); %#ok<AGROW>
end
end

function codeCases = localMergeOnlyCodeCases()
codeCases = struct('coding',{},'rate',{},'extra',{});
extra = localRSExtra();
extra.ConvolutionalCodeRate = '1/2';
codeCases(end+1) = localCodeCase('concatenated', 'RS+conv1/2', extra);
codeCases(end+1) = localCodeCase('TPC', '56x56', ...
    struct('TPCCodeRate','56','TPCBlocksPerTF',1,'TPCInterleaver','auto'));
end

function tf = localSplitSupports(coding, modType)
splitMods = {'QPSK','OQPSK','8PSK','16QAM','32QAM'};
splitCodes = {'none','RS','convolutional','LDPC','turbo'};
tf = any(strcmp(modType, splitMods)) && any(strcmp(coding, splitCodes));
end

function tf = localSkipUnsupportedCase(pathMode, modType, cc, rc) %#ok<INUSD>
tf = strcmp(pathMode, 'single') && strcmp(cc.coding, 'TPC') && ...
    logical(rc.enabled) && strcmp(string(rc.position), "afterEncoding");
end

function cc = localCodeCase(coding, rate, extra)
cc = struct('coding', coding, 'rate', string(rate), 'extra', extra);
end

function extra = localRSExtra()
extra = struct('RSMessageLength', 223, 'RSInterleavingDepth', 1, ...
    'IsRSMessageShortened', false);
end

function k = localLDPCInfoLength(rate)
switch char(rate)
    case '7/8'
        k = 7136;
    otherwise
        k = 1024;
end
end

function c = localMakeCase(cfg, ch, pathMode, modType, cc, rc)
p = struct('modType', modType, ...
    'symbolRate', cfg.symbolRate, ...
    'sps', cfg.sps, ...
    'snr', ch.snr, ...
    'cfo', ch.cfo, ...
    'phaseOffset', ch.phaseOffset, ...
    'delay', ch.delay, ...
    'channelCoding', cc.coding, ...
    'RolloffFactor', cfg.rolloff, ...
    'hasASM', true, ...
    'RandomizerEnabled', rc.enabled, ...
    'RandomizerFECPosition', char(rc.position), ...
    'DataPathMode', pathMode, ...
    'NumBytesInTransferFrame', localTFBytes(modType, cc), ...
    'SpacecraftID', 1, ...
    'VirtualChannelID', 0, ...
    'HasSecondaryHeader', false, ...
    'HasOCF', false, ...
    'HasFECF', false, ...
    'berWarmUpFrames', cfg.berWarmUpFrames, ...
    'berFrames', cfg.berFrames, ...
    'showFigures', false, ...
    'splitPathDebug', cfg.splitPathDebug, ...
    'splitIQPhaseTwoPass', true);

p = localMergeStruct(p, cc.extra);

name = sprintf('%s_%s_%s_%s_%s_%s', pathMode, modType, cc.coding, ...
    char(cc.rate), char(rc.label), char(ch.name));
name = regexprep(name, '[^\w]+', '_');

c = struct('name', name, ...
    'pathMode', pathMode, ...
    'modType', modType, ...
    'coding', cc.coding, ...
    'rate', cc.rate, ...
    'randLabel', rc.label, ...
    'position', rc.position, ...
    'channelProfile', ch.name, ...
    'params', p);
end

function n = localTFBytes(modType, cc)
n = 1115;
if strcmp(cc.coding, 'convolutional')
    rate = char(cc.rate);
    if strcmp(rate, '3/4') && strcmp(modType, '32QAM')
        % 32QAM carries 5 coded bits/symbol. 1121 bytes makes the
        % convolutional 3/4 encoded CADU length land on a symbol boundary.
        n = 1121;
    elseif strcmp(rate, '5/6')
        n = 1116;
    elseif strcmp(rate, '7/8')
        n = 1123;
    end
elseif strcmp(cc.coding, 'none') && strcmp(modType, '32QAM')
    % Two split rails with one 32-bit ASM per rail give
    % 2*(1116*8+32)=17920 bits, divisible by 5 bits/symbol.
    n = 1116;
elseif strcmp(cc.coding, 'none') && strcmp(modType, '8PSK')
    % Keep 1115 bytes: 2*(1115*8+32)=17904 bits is divisible by
    % 3 bits/symbol. 1116 bytes shifts the symbol grouping by one bit per
    % split-frame pair and causes periodic ASM lock loss.
    n = 1115;
end
end

function out = localMergeStruct(a, b)
out = a;
if isempty(fieldnames(b))
    return;
end
names = fieldnames(b);
for i = 1:numel(names)
    out.(names{i}) = b.(names{i});
end
end

function cases = localFACMAPSKCases(cfg, ch)
cases = struct('name',{},'pathMode',{},'modType',{},'coding',{},'rate',{}, ...
    'randLabel',{},'position',{},'channelProfile',{},'params',{});
mods = {'16APSK','32APSK'};
for iMod = 1:numel(mods)
    p = struct('modType', mods{iMod}, 'symbolRate', cfg.symbolRate, 'sps', 8, ...
        'snr', max(ch.snr, 20), 'cfo', ch.cfo, 'phaseOffset', ch.phaseOffset, ...
        'delay', ch.delay, 'channelCoding', 'none', 'RolloffFactor', cfg.rolloff, ...
        'hasASM', true, 'hasPilots', true, 'RandomizerEnabled', false, ...
        'RandomizerFECPosition', 'afterEncoding', 'DataPathMode', 'single', ...
        'showFigures', false);
    name = sprintf('facm_%s_none_%s', mods{iMod}, char(ch.name));
    cases(end+1, 1) = struct('name', name, 'pathMode', 'single', ...
        'modType', mods{iMod}, 'coding', 'FACM-none', 'rate', '-', ...
        'randLabel', 'randOff', 'position', 'afterEncoding', ...
        'channelProfile', ch.name, 'params', p); %#ok<AGROW>
end
end

function r = localEmptyResult()
r = struct('Idx', NaN, 'Name', "", 'PathMode', "", 'Modulation', "", ...
    'Coding', "", 'Rate', "", 'Randomizer', "", 'Position', "", ...
    'ChannelProfile', "", 'Status', "", 'Success', false, 'Pass', false, ...
    'BER', NaN, 'LockRate', NaN, 'FER', NaN, 'FrameErrors', NaN, ...
    'CountedFrames', NaN, 'AcquisitionFrames', NaN, 'ElapsedTime', NaN, ...
    'Error', "");
end

function v = localGet(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = defaultValue;
end
end

function localSaveProgress(matFile, Results, cases, cfg)
try
    tmpFile = [matFile '.tmp'];
    save(tmpFile, 'Results', 'cases', 'cfg');
    if exist(matFile, 'file')
        delete(matFile);
    end
    movefile(tmpFile, matFile);
catch ME
    warning('run_tm_split_merge_system_sweep:SaveProgressFailed', ...
        'Progress MAT save failed: %s. Sweep will continue.', ME.message);
end
end
