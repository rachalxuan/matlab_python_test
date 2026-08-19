%% sweep_qpsk_8psk_rs_allH.m
% 测试内容：
%   调制：QPSK、8PSK
%   编码：纯 RS，不是 concatenated
%   RSMessageLength：223、239
%   RSInterleavingDepth：1、2、3、4、5、8
%   信道：NoH baseline + 8 个 H 信道文件
%
% 说明：
%   RS(255,223)：每个 RS 码字可纠正 16 个错误字节
%   RS(255,239)：每个 RS 码字可纠正 8 个错误字节
%
%   完整 RS 模式下不需要设置 NumBytesInTransferFrame：
%   实际输入帧长度 = RSMessageLength × RSInterleavingDepth 字节
%
%   默认每个组合只跑 1 个随机种子。
%   需要多 seed 时，把 seedList = 1 改成 seedList = 1:10。

clear classes
clear run_ccsds_tm_evaluation HelperCCSDSTMDecoder ...
      HelperCCSDSTMDemodulator ccsdsTMWaveformGenerator
clear satcom.internal.ccsds.tmBase
rehash toolboxcache

%% =========================================================
% 1. 路径
% =========================================================
codeDir = 'E:\web_code\react\fft_project\react-fft\src\python';
chDir   = 'E:\matlab_project\v3.0\v3.0\channel';
outRoot = fullfile(codeDir, 'sweep_results');

addpath(codeDir);

hCases = {
    'NoH_baseline',         '';
    'default_ChannelData',  fullfile(chDir,'ChannelData.mat');
    'std2_TDL',             fullfile(chDir,'2-ChannelData.mat');
    'std3_CDL',             fullfile(chDir,'3-ChannelData.mat');
    'std4_ITU_P681',        fullfile(chDir,'4-ChannelData.mat');
    'std5_Jakes',           fullfile(chDir,'ChannelData_5.mat');
    'std6_CLoo',            fullfile(chDir,'ChannelData_6.mat');
    'std7_Corazza',         fullfile(chDir,'ChannelData_7.mat');
    'std8_Lutz',            fullfile(chDir,'ChannelData_8.mat')
};

% hCases = {
%     'NoH_baseline',         '';
%     'default_ChannelData',  fullfile(chDir,'ChannelData.mat');
%     'std2_TDL',             fullfile(chDir,'2-ChannelData.mat');
%     'std3_CDL',             fullfile(chDir,'3-ChannelData.mat');
%     'std4_ITU_P681',        fullfile(chDir,'4-ChannelData.mat');
%     'std5_Jakes',           fullfile(chDir,'ChannelData_5.mat');
%     'std6_CLoo',            fullfile(chDir,'ChannelData_6.mat');
%     'std7_Corazza',         fullfile(chDir,'ChannelData_7.mat');
%     'std8_Lutz',            fullfile(chDir,'ChannelData_8.mat')
% };

%% =========================================================
% 2. Sweep 参数
% =========================================================
modTypes = {'QPSK','8PSK','16QAM','GMSK'};

% CCSDS RS 支持的两个完整码：
rsMessageLengths = [223 239];

% 你当前对象支持的交织深度：
rsDepths = [1 2 3 4 5 8];

% 默认只跑一个随机种子；多 seed 改成 1:10
seedList = 1;

maxGoodBER = 1e-3;
minGoodLockPct = 90;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
outDir = fullfile(outRoot, ['qpsk_8psk_rs_allH_' stamp]);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% =========================================================
% 3. 公共链路参数
% =========================================================
base = struct();

base.symbolRate = 1e6;
base.sps = 8;

base.snr = 30;
base.cfo = 0;
base.phaseOffset = 0;
base.delay = 0;

% 纯 RS 编码
base.channelCoding = 'RS';
base.IsRSMessageShortened = false;

base.RolloffFactor = 0.35;

base.hasASM = true;
base.RandomizerEnabled = false;
base.RandomizerFECPosition = 'afterEncoding';
base.DataPathMode = 'single';

base.berWarmUpFrames = 5;
base.berFrames = 30;

% H 信道设置
base.HMode = 'h_matrix_file';
base.channelInterpolationMethod = 'linear';
base.channelOutOfRangeMode = 'wrap';
base.interpolateChannelDelays = false;

base.applyPMode = true;
base.normalizeHChannel = false;

% 均衡
base.enableEqualizer = true;
base.equalizerMode = 'mmse';

% 空值表示使用程序内部自动计算的 MMSE 正则项
base.equalizerReg = [];
base.normalizeEqualizerOutput = true;

% 你当前版本若支持该参数就会使用；不支持时通常会被忽略
base.noisePlacement = 'afterChannel';

% Debug 默认关闭，批量跑更清爽
base.debugAllPerFrameBER = false;
base.debugPerFrameBERSummary = false;
base.debugASMPhase = false;
base.debugEqualizerStats = false;
base.debugHFrameStats = false;
base.debugFrameCheck = false;

base.showFigures = false;
base.showPipelineFigure = false;
base.showPowerFigure = false;
base.showDamageBudgetFigure = false;

%% =========================================================
% 4. 运行 Sweep
% =========================================================
rows = {};
caseIdx = 0;

totalCases = size(hCases,1) * numel(modTypes) * ...
             numel(rsMessageLengths) * numel(rsDepths) * ...
             numel(seedList);

fprintf('\n============================================================\n');
fprintf('QPSK / 8PSK + 纯 RS sweep\n');
fprintf('总 case 数：%d\n', totalCases);
fprintf('RSMessageLength = %s\n', mat2str(rsMessageLengths));
fprintf('RSInterleavingDepth = %s\n', mat2str(rsDepths));
fprintf('============================================================\n');

for iH = 1:size(hCases,1)

    scenario = hCases{iH,1};
    channelFile = hCases{iH,2};

    isNoH = strcmpi(scenario, 'NoH_baseline');

    if ~isNoH
        assert(exist(channelFile, 'file') == 2, ...
            '找不到信道文件：%s', channelFile);
    end

    for iM = 1:numel(modTypes)

        modType = modTypes{iM};

        for iK = 1:numel(rsMessageLengths)

            kRS = rsMessageLengths(iK);

            for iD = 1:numel(rsDepths)

                depth = rsDepths(iD);

                % 完整 RS 模式下：
                % 输入 TF 字节数 = kRS × depth
                % 编码后字节数 = 255 × depth
                inputBytes = kRS * depth;
                codedBytes = 255 * depth;

                for seed = seedList

                    caseIdx = caseIdx + 1;

                    p = base;

                    p.modType = modType;
                    p.RSMessageLength = kRS;
                    p.RSInterleavingDepth = depth;

                    if isNoH
                        p.enableHChannel = false;
                    else
                        p.enableHChannel = true;
                        p.channelFilePath = channelFile;
                    end

                    rng(seed, 'twister');

                    rsName = sprintf('RS(255,%d)_D%d', kRS, depth);

                    fprintf('\n[%03d/%03d] %s | %s | %s | seed=%d\n', ...
                        caseIdx, totalCases, scenario, modType, rsName, seed);
                    fprintf('    输入=%d byte，编码后=%d byte\n', ...
                        inputBytes, codedBytes);

                    tCase = tic;

                    try
                        m = run_ccsds_tm_evaluation(p);
                        r = jsondecode(m);

                        elapsed = toc(tCase);

                        success = localLogicalField(r, 'success', true);
                        errorMsg = localTextField(r, 'errorMsg', '');

                        BER = localNumericField(r, 'BER', NaN);
                        lockPct = 100 * localNumericField(r, 'LockRate', NaN);
                        FER = localNumericField(r, 'FER', NaN);

                        EVM = localNumericField(r, 'EVM_post_pct', NaN);
                        MER = localNumericField(r, 'MER_dB', NaN);
                        SNR_est = localNumericField(r, 'SNR_est_dB', NaN);

                        frameErrors = localNumericField(r, 'FrameErrors', NaN);
                        countedFrames = localNumericField(r, 'CountedFrames', NaN);
                        matchedFrames = localNumericField(r, 'MatchedFrames', NaN);
                        decodedFrames = localNumericField(r, 'DecodedFrames', NaN);

                        hGain = localNumericField(r, 'HGain_dB', NaN);

                    catch ME
                        elapsed = toc(tCase);

                        success = false;
                        errorMsg = string(ME.message);

                        BER = NaN;
                        lockPct = NaN;
                        FER = NaN;
                        EVM = NaN;
                        MER = NaN;
                        SNR_est = NaN;
                        frameErrors = NaN;
                        countedFrames = NaN;
                        matchedFrames = NaN;
                        decodedFrames = NaN;
                        hGain = NaN;

                        fprintf(2, '[CASE ERROR] %s\n', ME.message);
                    end

                    pass = success && ...
                        isfinite(BER) && BER <= maxGoodBER && ...
                        isfinite(lockPct) && lockPct >= minGoodLockPct;

                    rows(end+1,:) = { ...
                        string(scenario), ...
                        string(modType), ...
                        string(rsName), ...
                        kRS, ...
                        depth, ...
                        inputBytes, ...
                        codedBytes, ...
                        seed, ...
                        BER, ...
                        lockPct, ...
                        FER, ...
                        EVM, ...
                        MER, ...
                        SNR_est, ...
                        frameErrors, ...
                        countedFrames, ...
                        matchedFrames, ...
                        decodedFrames, ...
                        hGain, ...
                        pass, ...
                        success, ...
                        string(errorMsg), ...
                        elapsed}; %#ok<SAGROW>

                    fprintf(['    BER=%g, Lock=%.1f%%, FER=%g, ', ...
                             'EVM=%.2f%%, MER=%.2f dB, Pass=%d\n'], ...
                        BER, lockPct, FER, EVM, MER, pass);
                end
            end
        end
    end
end

%% =========================================================
% 5. 保存原始结果
% =========================================================
T = cell2table(rows, 'VariableNames', { ...
    'Scenario', ...
    'ModType', ...
    'RSName', ...
    'RSMessageLength', ...
    'RSInterleavingDepth', ...
    'InputBytes', ...
    'CodedBytes', ...
    'Seed', ...
    'BER', ...
    'LockRate_pct', ...
    'FER', ...
    'EVM_post_pct', ...
    'MER_dB', ...
    'SNR_est_dB', ...
    'FrameErrors', ...
    'CountedFrames', ...
    'MatchedFrames', ...
    'DecodedFrames', ...
    'HGain_dB', ...
    'Pass', ...
    'Success', ...
    'ErrorMsg', ...
    'ElapsedTime_s'});

rawCsv = fullfile(outDir, 'qpsk_8psk_rs_allH_raw.csv');
writetable(T, rawCsv);

%% =========================================================
% 6. 分组汇总
% =========================================================
groupKeys = unique(T(:, { ...
    'Scenario', ...
    'ModType', ...
    'RSName', ...
    'RSMessageLength', ...
    'RSInterleavingDepth', ...
    'InputBytes', ...
    'CodedBytes'}), ...
    'rows', 'stable');

summaryRows = {};

for i = 1:height(groupKeys)

    mask = ...
        T.Scenario == groupKeys.Scenario(i) & ...
        T.ModType == groupKeys.ModType(i) & ...
        T.RSName == groupKeys.RSName(i) & ...
        T.RSMessageLength == groupKeys.RSMessageLength(i) & ...
        T.RSInterleavingDepth == groupKeys.RSInterleavingDepth(i);

    X = T(mask,:);

    berValid = X.BER(isfinite(X.BER));
    lockValid = X.LockRate_pct(isfinite(X.LockRate_pct));
    ferValid = X.FER(isfinite(X.FER));
    merValid = X.MER_dB(isfinite(X.MER_dB));

    summaryRows(end+1,:) = { ...
        groupKeys.Scenario(i), ...
        groupKeys.ModType(i), ...
        groupKeys.RSName(i), ...
        groupKeys.RSMessageLength(i), ...
        groupKeys.RSInterleavingDepth(i), ...
        groupKeys.InputBytes(i), ...
        groupKeys.CodedBytes(i), ...
        height(X), ...
        localSafeMean(berValid), ...
        localSafeMedian(berValid), ...
        localSafeMax(berValid), ...
        localSafeMean(lockValid), ...
        localSafeMin(lockValid), ...
        localSafeMean(ferValid), ...
        localSafeMean(merValid), ...
        100 * mean(X.Pass), ...
        100 * mean(isfinite(X.BER) & X.BER == 0), ...
        sum(~X.Success)}; %#ok<SAGROW>
end

Tsummary = cell2table(summaryRows, 'VariableNames', { ...
    'Scenario', ...
    'ModType', ...
    'RSName', ...
    'RSMessageLength', ...
    'RSInterleavingDepth', ...
    'InputBytes', ...
    'CodedBytes', ...
    'Runs', ...
    'BER_mean', ...
    'BER_median', ...
    'BER_worst', ...
    'Lock_mean_pct', ...
    'Lock_worst_pct', ...
    'FER_mean', ...
    'MER_mean_dB', ...
    'PassRate_pct', ...
    'ZeroBERRate_pct', ...
    'ErrorRuns'});

summaryCsv = fullfile(outDir, 'qpsk_8psk_rs_allH_summary.csv');
writetable(Tsummary, summaryCsv);

%% =========================================================
% 7. 单独保存弱项
% =========================================================
Tweak = T(~T.Pass, :);

weakCsv = fullfile(outDir, 'qpsk_8psk_rs_allH_weak.csv');
writetable(Tweak, weakCsv);

matFile = fullfile(outDir, 'qpsk_8psk_rs_allH.mat');
save(matFile, ...
    'T', 'Tsummary', 'Tweak', ...
    'base', 'hCases', 'modTypes', ...
    'rsMessageLengths', 'rsDepths', 'seedList');

%% =========================================================
% 8. 命令行显示
% =========================================================
fprintf('\n============================================================\n');
fprintf('Sweep 完成\n');
fprintf('============================================================\n');

disp(Tsummary(:, { ...
    'Scenario', ...
    'ModType', ...
    'RSName', ...
    'InputBytes', ...
    'BER_mean', ...
    'BER_worst', ...
    'Lock_mean_pct', ...
    'Lock_worst_pct', ...
    'FER_mean', ...
    'PassRate_pct'}));

fprintf('\n弱项数量：%d / %d\n', height(Tweak), height(T));

if ~isempty(Tweak)
    disp(Tweak(:, { ...
        'Scenario', ...
        'ModType', ...
        'RSName', ...
        'Seed', ...
        'BER', ...
        'LockRate_pct', ...
        'FER', ...
        'MER_dB', ...
        'ErrorMsg'}));
end

fprintf('\n原始 CSV：%s\n', rawCsv);
fprintf('汇总 CSV：%s\n', summaryCsv);
fprintf('弱项 CSV：%s\n', weakCsv);
fprintf('MAT 文件 ：%s\n', matFile);
fprintf('输出目录 ：%s\n', outDir);

%% =========================================================
% 局部辅助函数
% =========================================================
function v = localNumericField(s, name, defaultValue)

v = defaultValue;

if ~isstruct(s) || ~isfield(s, name) || isempty(s.(name))
    return;
end

raw = s.(name);

if isnumeric(raw) || islogical(raw)
    raw = double(raw);
    v = raw(1);
else
    x = str2double(string(raw));
    if ~isempty(x) && isfinite(x(1))
        v = double(x(1));
    end
end
end

function v = localLogicalField(s, name, defaultValue)

v = defaultValue;

if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = logical(s.(name));
end
end

function v = localTextField(s, name, defaultValue)

v = string(defaultValue);

if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = string(s.(name));
end
end

function v = localSafeMean(x)
if isempty(x)
    v = NaN;
else
    v = mean(x);
end
end

function v = localSafeMedian(x)
if isempty(x)
    v = NaN;
else
    v = median(x);
end
end

function v = localSafeMax(x)
if isempty(x)
    v = NaN;
else
    v = max(x);
end
end

function v = localSafeMin(x)
if isempty(x)
    v = NaN;
else
    v = min(x);
end
end
%% 
clearvars; clear classes;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();

o.modTypes = {'QPSK','OQPSK','UQPSK','MSK','32APSK','16QAM','8PSK'};

o.hModelCases = { ...
    'std2_TDL',       'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std3_CDL',       'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
    'std4_ITU_P681',  'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std5_Jakes',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
    'std6_CLoo',      'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
    'std7_Corazza',   'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
    'std8_Lutz',      'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};

o.includeNoHBaseline = true;
o.includeHEqualized = true;
o.includeNormHScenario = false;
o.includeNoEqualizerScenario = false;

o.includeUncoded = false;
o.includeConvolutional = true;
o.convRates = {'1/2'};
o.includeRS = false;
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = false;

o.symbolRate = 10e6;
o.sps = 8;
o.snr = 35;
o.noisePlacement = 'afterChannel';

o.berWarmUpFrames = 8;
o.berFrames = 40;

o.equalizerMode = 'blind-cma-lms';
o.enableOQPSKHighRateTracking = true;
o.oqpskEnvelopeTauSymbols = 16;
o.oqpskHighRatePhaseWindowSymbols = 16;
o.enableUQPSKHighRateTracking = true;
o.uqpskEnvelopeTauSymbols = 16;
o.uqpskHighRatePhaseWindowSymbols = 16;
o.enableCPMCoarseFrequencyCompensator = false;

o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';

o.maxGoodBER = 1e-5;
o.minGoodLockPct = 90;
o.maxGoodFER = 0;
o.minGoodMERdB = 18;

o.Resume = false;
o.RerunFailed = false;
o.outputDir = '';
o.showFigures = false;
o.debugCodedBoundary = true;
o.collectPredecoderStats = true;

T = sweep_h_channel_short_frames(o);

disp(T(:,{'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','HighRatePhaseTrackingApplied','Status'}));
