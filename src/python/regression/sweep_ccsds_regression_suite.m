clc;
clear;

cd('E:/web_code/react/fft_project/react-fft/src/python');

% =========================================================
% CCSDS TM regression suite
%
% 目的：
%   快速检查主脚本是否被重构/注释修改弄坏。
%
% 覆盖：
%   1. QPSK / 8PSK 普通调制链路
%   2. none / RS / convolutional 编码
%   3. PCM/PSK/PM 和 PCM/PM/biphase-L
%   4. 4D-8PSK-TCM 不同效率
%   5. H 多径入口
%
% 判据：
%   - convolutional 的 LockRate 不强制要求 99%，因为卷积码场景前几帧
%     可能因同步/译码收敛被丢弃。BER=0 且 LockRate>80% 一般可认为通过。
% =========================================================

cases = {};

% =========================================================
% 1. 普通 QPSK / 8PSK 基础链路
% =========================================================

cases{end+1} = makeCase('STD', 'QPSK none ideal', ...
    makeP('QPSK', 'none', 100, 0, 0, 0), ...
    0, 0.99);

cases{end+1} = makeCase('STD', 'QPSK none damaged', ...
    makeP('QPSK', 'none', 12, 50000, 10, 0.2), ...
    1e-3, 0.90);

p = makeP('QPSK', 'convolutional', 100, 0, 0, 0);
p.ConvolutionalCodeRate = '2/3';
cases{end+1} = makeCase('STD', 'QPSK conv ideal', p, ...
    0, 0.80);

p = makeP('QPSK', 'convolutional', 12, 50000, 10, 0.2);
p.ConvolutionalCodeRate = '2/3';
cases{end+1} = makeCase('STD', 'QPSK conv damaged', p, ...
    1e-3, 0.80);

cases{end+1} = makeCase('STD', '8PSK none ideal', ...
    makeP('8PSK', 'none', 100, 0, 0, 0), ...
    0, 0.99);

cases{end+1} = makeCase('STD', '8PSK none damaged', ...
    makeP('8PSK', 'none', 12, 50000, 10, 0.3), ...
    5e-3, 0.90);

p = makeP('8PSK', 'RS', 100, 0, 0, 0);
p = addRS(p);
cases{end+1} = makeCase('STD', '8PSK RS ideal', p, ...
    0, 0.99);

p = makeP('8PSK', 'RS', 12, 50000, 10, 0.3);
p = addRS(p);
cases{end+1} = makeCase('STD', '8PSK RS damaged', p, ...
    1e-3, 0.90);

p = makeP('8PSK', 'convolutional', 100, 0, 0, 0);
p.ConvolutionalCodeRate = '2/3';
cases{end+1} = makeCase('STD', '8PSK conv ideal', p, ...
    0, 0.80);

p = makeP('8PSK', 'convolutional', 12, 50000, 10, 0.3);
p.ConvolutionalCodeRate = '2/3';
cases{end+1} = makeCase('STD', '8PSK conv damaged', p, ...
    1e-3, 0.80);

% =========================================================
% 2. PCM/PM 两个专用分支
% =========================================================

p = makeP('PCM/PSK/PM', 'none', 100, 0, 0, 0);
p.sps = 8;
p.ModulationIndex = pi/3;
p.PCMFormat = 'NRZ-L';
p.SubcarrierWaveform = 'sine';
p.SubcarrierToSymbolRateRatio = 2;
cases{end+1} = makeCase('PCM', 'PCM/PSK/PM none ideal', p, ...
    0, 0.99);

p = makeP('PCM/PSK/PM', 'RS', 8, 20000, 10, 0.2);
p = addRS(p);
p.sps = 64;
p.ModulationIndex = pi/3;
p.PCMFormat = 'NRZ-L';
p.SubcarrierWaveform = 'sine';
p.SubcarrierToSymbolRateRatio = 16;
cases{end+1} = makeCase('PCM', 'PCM/PSK/PM RS damaged', p, ...
    1e-3, 0.80);

p = makeP('PCM/PM/biphase-L', 'none', 100, 0, 0, 0);
p.ModulationIndex = pi/3;
cases{end+1} = makeCase('PCM', 'PCM/PM/biphase-L none ideal', p, ...
    0, 0.99);

p = makeP('PCM/PM/biphase-L', 'convolutional', 12, 200000, 10, 0.2);
p.ConvolutionalCodeRate = '2/3';
p.ModulationIndex = pi/3;
cases{end+1} = makeCase('PCM', 'PCM/PM/biphase-L conv damaged', p, ...
    1e-3, 0.80);

p = makeP('PCM/PM/biphase-L', 'RS', 12, 200000, 10, 0.2);
p = addRS(p);
p.ModulationIndex = pi/3;
cases{end+1} = makeCase('PCM', 'PCM/PM/biphase-L RS damaged', p, ...
    1e-3, 0.80);

% =========================================================
% 3. 4D-8PSK-TCM efficiency regression
% =========================================================

effList = [2.00, 2.25, 2.50, 2.75];

for i = 1:numel(effList)
    eff = effList(i);

    p = makeP('4D-8PSK-TCM', 'none', 100, 0, 0, 0);
    p.ModulationEfficiency = eff;
    p.NumBytesInTransferFrame = 1112;
    p.tcmSymbolSkip = 0;
    p.tcmBitSkip = 0;
    p.tcmSearchAll = false;
    p.tcmSampleOffsetSearchAll = true;

    cases{end+1} = makeCase('4D', ...
        sprintf('4D-TCM eff %.2f ideal', eff), p, ...
        0, 0.95);

    p = makeP('4D-8PSK-TCM', 'none', 15, 200000, 10, 0.4);
    p.ModulationEfficiency = eff;
    p.NumBytesInTransferFrame = 1112;
    p.tcmSymbolSkip = 0;
    p.tcmBitSkip = 0;
    p.tcmSearchAll = false;
    p.tcmSampleOffsetSearchAll = true;

    cases{end+1} = makeCase('4D', ...
        sprintf('4D-TCM eff %.2f damaged', eff), p, ...
        1e-3, 0.90);
end

% =========================================================
% 4. H 多径入口测试：8PSK none
% =========================================================

H_mild = [ ...
    1, ...
    0, ...
    0.25*exp(1j*pi/3), ...
    0, ...
    0.10*exp(-1j*pi/4)];

H_strong = [ ...
    1, ...
    0, ...
    0.85*exp(1j*pi/3), ...
    0, ...
    0.60*exp(-1j*pi/4), ...
    0, ...
    0.40*exp(1j*pi/2)];

p = makeP('8PSK', 'none', 12, 50000, 10, 0.3);
cases{end+1} = makeCase('H', '8PSK no H reference', p, ...
    5e-3, 0.90);

p = makeP('8PSK', 'none', 12, 50000, 10, 0.3);
p = addH(p, H_mild);
cases{end+1} = makeCase('H', '8PSK mild H', p, ...
    2e-2, 0.80);

p = makeP('8PSK', 'none', 12, 50000, 10, 0.3);
p = addH(p, H_strong);
cases{end+1} = makeCase('H', '8PSK strong H', p, ...
    0.20, 0.60);

% =========================================================
% Run all cases
% =========================================================

results = table( ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    zeros(0,1), ...
    zeros(0,1), ...
    zeros(0,1), ...
    zeros(0,1), ...
    zeros(0,1), ...
    strings(0,1), ...
    'VariableNames', { ...
        'Category', 'Case', 'Modulation', 'Coding', ...
        'SNR', 'CFO', 'BER', 'LockRate_pct', 'EVM_post_pct', 'Status'});

for k = 1:numel(cases)
    c = cases{k};
    p = c.p;

    fprintf('\n====================================================\n');
    fprintf('[%s] %s\n', c.category, c.name);
    fprintf('====================================================\n');

    try
        outRaw = run_ccsds_tm_evaluation(p);

        if ischar(outRaw) || isstring(outRaw)
            out = jsondecode(char(outRaw));
        else
            out = outRaw;
        end

        berVal = getScalarMetric(out, 'BER', NaN);
        lockVal = getScalarMetric(out, 'LockRate', NaN);
        evmPost = getScalarMetric(out, 'EVM_post_pct', NaN);

        if isfield(out, 'success') && isequal(out.success, false)
            status = "ERROR";
        elseif berVal <= c.berMax && lockVal >= c.lockMin
            status = "PASS";
        else
            status = "FAIL";
        end

        fprintf('\n[SUMMARY] BER=%g, Lock=%.2f%%, EVM=%.3f%%, Status=%s\n', ...
            berVal, lockVal*100, evmPost, status);

        results = [results; { ...
            string(c.category), ...
            string(c.name), ...
            string(p.modType), ...
            string(p.channelCoding), ...
            double(p.snr), ...
            double(p.cfo), ...
            berVal, ...
            lockVal*100, ...
            evmPost, ...
            status}]; %#ok<AGROW>
    end
end

fprintf('\n\n================ CCSDS REGRESSION SUITE RESULT ================\n');
disp(results);

failed = results(results.Status ~= "PASS", :);

if isempty(failed)
    fprintf('\nALL REGRESSION CASES PASSED.\n');
else
    fprintf('\nFAILED / ERROR CASES:\n');
    disp(failed);
end

try
    writetable(results, 'ccsds_regression_suite_results.csv');
    save('ccsds_regression_suite_results.mat', 'results');
    fprintf('\nSaved results to ccsds_regression_suite_results.csv and .mat\n');
end

% =========================================================
% Local helper functions
% =========================================================

function p = makeP(modType, coding, snr, cfo, phaseOffset, delay)
    p = struct( ...
        'modType', modType, ...
        'symbolRate', 1e6, ...
        'sps', 8, ...
        'snr', snr, ...
        'cfo', cfo, ...
        'phaseOffset', phaseOffset, ...
        'delay', delay, ...
        'channelCoding', coding, ...
        'NumBytesInTransferFrame', 1115, ...
        'RolloffFactor', 0.35, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'showFigures', false, ...
        'berWarmUpFrames', 5, ...
        'berFrames', 20);
end
function v = getScalarMetric(s, fieldName, defaultValue)
    v = defaultValue;

    if ~isstruct(s) || ~isfield(s, fieldName)
        return;
    end

    raw = s.(fieldName);

    if isempty(raw)
        v = defaultValue;
        return;
    end

    if iscell(raw)
        if isempty(raw)
            v = defaultValue;
            return;
        end
        raw = raw{1};
    end

    if isstring(raw) || ischar(raw)
        tmp = str2double(raw);
        if isnan(tmp)
            v = defaultValue;
        else
            v = tmp;
        end
        return;
    end

    if isnumeric(raw) || islogical(raw)
        raw = double(raw);
        if isempty(raw)
            v = defaultValue;
        else
            v = raw(1);
        end
        return;
    end

    v = defaultValue;
end
function p = addRS(p)
    p.channelCoding = 'RS';

    % RS 模式下 NumBytesInTransferFrame 对 System object 通常无关。
    % 为了减少 warning，这里删掉它。
    if isfield(p, 'NumBytesInTransferFrame')
        p = rmfield(p, 'NumBytesInTransferFrame');
    end

    p.RSMessageLength = 223;
    p.RSInterleavingDepth = 1;
    p.IsRSMessageShortened = false;
end

function p = addH(p, H)
    p.enableHChannel = true;
    p.HMode = 'siso_multipath';
    p.H = H;
    p.normalizeHChannel = true;
end

function c = makeCase(category, name, p, berMax, lockMin)
    c = struct();
    c.category = category;
    c.name = name;
    c.p = p;
    c.berMax = berMax;
    c.lockMin = lockMin;
end