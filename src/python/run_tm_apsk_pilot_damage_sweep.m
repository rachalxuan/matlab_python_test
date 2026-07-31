function Summary = run_tm_apsk_pilot_damage_sweep(profile, startAt, maxCases)
%RUN_TM_APSK_PILOT_DAMAGE_SWEEP Sweep ordinary-TM APSK pilot robustness.
%
% Usage:
%   cd E:\web_code\react\fft_project\react-fft\src\python
%   Summary = run_tm_apsk_pilot_damage_sweep("smoke");
%   Summary = run_tm_apsk_pilot_damage_sweep("full");
%   Summary = run_tm_apsk_pilot_damage_sweep("full", 20);      % resume at case 20
%   Summary = run_tm_apsk_pilot_damage_sweep("full", 1, 30);   % first 30 cases
%
% Profiles:
%   smoke : 16/32APSK, none/RS/conv 1/2/7/8, clean/light/medium damage.
%   full  : all main coding families and light/medium/strong damage.
%   deep  : full plus more LDPC/turbo rates and a stress damage point.

if nargin < 1 || isempty(profile)
    profile = "smoke";
end
profile = lower(string(profile));
if nargin < 2 || isempty(startAt)
    startAt = 1;
end
if nargin < 3 || isempty(maxCases)
    maxCases = inf;
end

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);

cfg = localConfig(profile, scriptDir);
cases = localBuildCases(cfg);
startAt = max(1, round(double(startAt)));
if isfinite(maxCases)
    cases = cases(1:min(numel(cases), round(double(maxCases))));
end

if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end

fprintf('\n===== Ordinary TM APSK pilot damage sweep =====\n');
fprintf('profile=%s, cases=%d, output=%s\n', char(profile), numel(cases), cfg.outDir);
fprintf('pass hint: BER <= %.3g, FER <= %.3g, Lock >= %.2f\n', ...
    cfg.passBER, cfg.passFER, cfg.passLock);

Results = repmat(localEmptyResult(), 0, 1);
for iCase = startAt:numel(cases)
    c = cases(iCase);
    fprintf('\n[%03d/%03d] %s | %s | %s | %s\n', ...
        iCase, numel(cases), c.Mod, c.CodingName, c.Rate, c.Damage);

    r = localEmptyResult();
    r.Idx = iCase;
    r.Mod = string(c.Mod);
    r.CodingName = string(c.CodingName);
    r.ChannelCoding = string(c.Params.channelCoding);
    r.Rate = string(c.Rate);
    r.Damage = string(c.Damage);
    r.SNR_dB = c.Params.snr;
    r.CFO_Hz = c.Params.cfo;
    r.Phase_deg = c.Params.phaseOffset;
    r.Delay_sym = c.Params.delay;
    r.PilotMode = string(localGet(c.Params, 'TMAPSKPilotCorrectionMode', 'auto'));

    tCase = tic;
    try
        raw = run_ccsds_tm_evaluation(c.Params);
        if ischar(raw) || isstring(raw)
            m = jsondecode(char(raw));
        else
            m = raw;
        end

        r.Success = logical(localGet(m, 'success', false));
        r.BER = double(localGet(m, 'BER', NaN));
        r.FER = double(localGet(m, 'FER', localGet(m, 'FrameErrorRate', NaN)));
        r.LockRate = double(localGet(m, 'LockRate', NaN));
        r.EVM_post_pct = double(localGet(m, 'EVM_post_pct', NaN));
        r.MER_dB = double(localGet(m, 'MER_dB', NaN));
        r.ResidualCFO_Hz = double(localGet(m, 'ResidualCFO_Hz', localGet(m, 'residCFO_Hz', NaN)));
        r.TMAPSKPilotsApplied = logical(localGet(m, 'TMAPSKPilotsApplied', false));
        r.TMAPSKPilotCFO_Hz = double(localGet(m, 'TMAPSKPilotCFO_Hz', NaN));
        r.TMAPSKPilotDataSymbols = double(localGet(m, 'TMAPSKPilotDataSymbols', NaN));
        r.PilotMode = string(localGet(m, 'TMAPSKPilotCorrectionMode', r.PilotMode));
        r.FrameErrors = double(localGet(m, 'FrameErrors', NaN));
        r.CountedFrames = double(localGet(m, 'CountedFrames', NaN));
        r.ElapsedTime_s = double(localGet(m, 'ElapsedTime', toc(tCase)));
        r.Error = string(localGet(m, 'errorMsg', ''));
    catch ME
        r.Success = false;
        r.BER = NaN;
        r.FER = NaN;
        r.LockRate = NaN;
        r.ElapsedTime_s = toc(tCase);
        r.Error = string(ME.message);
    end

    r.Pass = r.Success && r.BER <= cfg.passBER && ...
        (isnan(r.FER) || r.FER <= cfg.passFER) && ...
        (isnan(r.LockRate) || r.LockRate >= cfg.passLock);
    Results(end+1, 1) = r; %#ok<AGROW>

    fprintf('  BER=%g, FER=%g, Lock=%.1f%%, EVM=%.2f%%, pilotCFO=%.2f Hz, pass=%d\n', ...
        r.BER, r.FER, 100*r.LockRate, r.EVM_post_pct, r.TMAPSKPilotCFO_Hz, r.Pass);

    if cfg.saveEveryCase
        localWriteOutputs(cfg, Results);
    end
end

Summary = struct();
Summary.Profile = profile;
Summary.Results = struct2table(Results);
Summary.PassCount = sum([Results.Pass]);
Summary.FailCount = numel(Results) - Summary.PassCount;
Summary.OutputDir = cfg.outDir;

localWriteOutputs(cfg, Results);
fprintf('\nDone: pass=%d, fail=%d\n', Summary.PassCount, Summary.FailCount);
fprintf('Saved: %s\n', fullfile(cfg.outDir, 'tm_apsk_pilot_damage_results.csv'));
end

function cfg = localConfig(profile, scriptDir)
cfg = struct();
cfg.profile = profile;
cfg.outDir = fullfile(scriptDir, 'sweep_results', ...
    ['tm_apsk_pilot_damage_' datestr(now, 'yyyymmdd_HHMMSS')]);
cfg.mods = {'16APSK','32APSK'};
cfg.symbolRate = 1e6;
cfg.sps = 8;
cfg.rolloff = 0.35;
cfg.berWarmUpFrames = 3;
cfg.berFrames = 12;
cfg.passBER = 1e-4;
cfg.passFER = 0.2;
cfg.passLock = 0.9;
cfg.saveEveryCase = true;

switch profile
    case "smoke"
        cfg.convRates = {'1/2','7/8'};
        cfg.ldpcRates = {};
        cfg.turboRates = {};
        cfg.includeTPC = false;
        cfg.includeConcatenated = false;
        cfg.damage = localDamageProfiles("smoke");
    case "full"
        cfg.convRates = {'1/2','2/3','3/4','5/6','7/8'};
        cfg.ldpcRates = {'1/2','7/8'};
        cfg.turboRates = {'1/2'};
        cfg.includeTPC = true;
        cfg.includeConcatenated = true;
        cfg.damage = localDamageProfiles("full");
    case "deep"
        cfg.convRates = {'1/2','2/3','3/4','5/6','7/8'};
        cfg.ldpcRates = {'1/2','2/3','4/5','7/8'};
        cfg.turboRates = {'1/2','1/3','1/4','1/6'};
        cfg.includeTPC = true;
        cfg.includeConcatenated = true;
        cfg.damage = localDamageProfiles("deep");
        cfg.berFrames = 20;
    otherwise
        error('run_tm_apsk_pilot_damage_sweep:BadProfile', ...
            'Unknown profile "%s". Use smoke, full, or deep.', profile);
end
end

function damage = localDamageProfiles(profile)
damage = struct('name',{},'snr',{},'cfo',{},'phaseOffset',{},'delay',{});
damage(end+1) = struct('name',"clean",'snr',30,'cfo',0,'phaseOffset',0,'delay',0);
damage(end+1) = struct('name',"light",'snr',25,'cfo',1000,'phaseOffset',5,'delay',0.1);
damage(end+1) = struct('name',"medium",'snr',20,'cfo',3000,'phaseOffset',10,'delay',0.25);
if profile == "full" || profile == "deep"
    damage(end+1) = struct('name',"strong",'snr',16,'cfo',5000,'phaseOffset',20,'delay',0.4);
end
if profile == "deep"
    damage(end+1) = struct('name',"stress",'snr',14,'cfo',8000,'phaseOffset',35,'delay',0.45);
end
end

function cases = localBuildCases(cfg)
codeCases = localCodeCases(cfg);
cases = struct('Mod',{},'CodingName',{},'Rate',{},'Damage',{},'Params',{});
for iMod = 1:numel(cfg.mods)
    modType = cfg.mods{iMod};
    for iDamage = 1:numel(cfg.damage)
        d = cfg.damage(iDamage);
        for iCode = 1:numel(codeCases)
            cc = codeCases(iCode);
            p = localBaseParams(cfg, modType, d);
            p.channelCoding = cc.ChannelCoding;
            p.NumBytesInTransferFrame = localTFBytes(cc);
            p = localMergeStruct(p, cc.Extra);
            cases(end+1, 1) = struct( ...
                'Mod', string(modType), ...
                'CodingName', string(cc.Name), ...
                'Rate', string(cc.Rate), ...
                'Damage', string(d.name), ...
                'Params', p); %#ok<AGROW>
        end
    end
end
end

function p = localBaseParams(cfg, modType, d)
p = struct( ...
    'modType', modType, ...
    'WaveformMode', 'ordinaryTM', ...
    'HasTMAPSKPilots', true, ...
    'TMAPSKPilotInterval', 512, ...
    'TMAPSKPilotLength', 32, ...
    'TMAPSKPilotPreambleLength', 64, ...
    'symbolRate', cfg.symbolRate, ...
    'sps', cfg.sps, ...
    'snr', d.snr, ...
    'cfo', d.cfo, ...
    'phaseOffset', d.phaseOffset, ...
    'delay', d.delay, ...
    'RolloffFactor', cfg.rolloff, ...
    'hasASM', true, ...
    'RandomizerEnabled', false, ...
    'RandomizerFECPosition', 'afterEncoding', ...
    'DataPathMode', 'single', ...
    'showFigures', false, ...
    'berWarmUpFrames', cfg.berWarmUpFrames, ...
    'berFrames', cfg.berFrames);
end

function codeCases = localCodeCases(cfg)
codeCases = struct('Name',{},'ChannelCoding',{},'Rate',{},'Extra',{});
codeCases(end+1) = localCodeCase('none', 'none', '-', struct());
codeCases(end+1) = localCodeCase('RS', 'RS', '223/255', ...
    struct('RSMessageLength', 223, 'RSInterleavingDepth', 1, 'IsRSMessageShortened', false));
for i = 1:numel(cfg.convRates)
    rate = cfg.convRates{i};
    codeCases(end+1) = localCodeCase(['conv_' strrep(rate,'/','_')], ...
        'convolutional', rate, struct('ConvolutionalCodeRate', rate)); %#ok<AGROW>
end
for i = 1:numel(cfg.ldpcRates)
    rate = cfg.ldpcRates{i};
    codeCases(end+1) = localCodeCase(['LDPC_' strrep(rate,'/','_')], ...
        'LDPC', rate, struct('CodeRate', rate, ...
        'NumBitsInInformationBlock', localLDPCInfoLength(rate), 'IsLDPCOnSMTF', false)); %#ok<AGROW>
end
for i = 1:numel(cfg.turboRates)
    rate = cfg.turboRates{i};
    codeCases(end+1) = localCodeCase(['turbo_' strrep(rate,'/','_')], ...
        'turbo', rate, struct('CodeRate', rate, 'NumBitsInInformationBlock', 1784)); %#ok<AGROW>
end
if cfg.includeTPC
    codeCases(end+1) = localCodeCase('TPC', 'TPC', 'native', ...
        struct('TPCCodeRate', 'native', 'TPCBlocksPerTF', 1, 'TPCInterleaver', 'auto'));
end
if cfg.includeConcatenated
    codeCases(end+1) = localCodeCase('concatenated', 'concatenated', 'RS+conv1/2', ...
        struct('ConvolutionalCodeRate', '1/2', ...
        'RSMessageLength', 223, 'RSInterleavingDepth', 1, 'IsRSMessageShortened', false));
end
end

function cc = localCodeCase(name, channelCoding, rate, extra)
cc = struct('Name', name, 'ChannelCoding', channelCoding, ...
    'Rate', string(rate), 'Extra', extra);
end

function n = localTFBytes(cc)
n = 1115;
if strcmpi(cc.ChannelCoding, 'convolutional')
    switch char(cc.Rate)
        case '5/6'
            n = 1116;
        case '7/8'
            n = 1123;
    end
elseif strcmpi(cc.ChannelCoding, 'TPC')
    n = 392;
end
end

function k = localLDPCInfoLength(rate)
switch char(rate)
    case '7/8'
        k = 7136;
    otherwise
        k = 1024;
end
end

function out = localMergeStruct(a, b)
out = a;
if isempty(b)
    return;
end
names = fieldnames(b);
for i = 1:numel(names)
    out.(names{i}) = b.(names{i});
end
end

function v = localGet(s, name, defaultValue)
v = defaultValue;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end

function r = localEmptyResult()
r = struct( ...
    'Idx', 0, ...
    'Mod', "", ...
    'CodingName', "", ...
    'ChannelCoding', "", ...
    'Rate', "", ...
    'Damage', "", ...
    'SNR_dB', NaN, ...
    'CFO_Hz', NaN, ...
    'Phase_deg', NaN, ...
    'Delay_sym', NaN, ...
    'PilotMode', "", ...
    'Success', false, ...
    'Pass', false, ...
    'BER', NaN, ...
    'FER', NaN, ...
    'LockRate', NaN, ...
    'EVM_post_pct', NaN, ...
    'MER_dB', NaN, ...
    'ResidualCFO_Hz', NaN, ...
    'TMAPSKPilotsApplied', false, ...
    'TMAPSKPilotCFO_Hz', NaN, ...
    'TMAPSKPilotDataSymbols', NaN, ...
    'FrameErrors', NaN, ...
    'CountedFrames', NaN, ...
    'ElapsedTime_s', NaN, ...
    'Error', "");
end

function localWriteOutputs(cfg, Results)
T = struct2table(Results);
writetable(T, fullfile(cfg.outDir, 'tm_apsk_pilot_damage_results.csv'));
save(fullfile(cfg.outDir, 'tm_apsk_pilot_damage_results.mat'), 'T', 'Results');
end
