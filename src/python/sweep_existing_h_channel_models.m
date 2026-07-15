% sweep_existing_h_channel_models.m
% Small smoke sweep over existing H-channel MAT files.
%
% This script does not generate new channel files. It reuses the existing
% files under E:\matlab_project\v3.0\v3.0\channel and checks whether the
% CCSDS receiver can recover a small set of modulations with H equalization.

clear classes;
addpath('E:\web_code\react\fft_project\react-fft\src\python');

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';
channelCases = {
    'default_ChannelData',      fullfile(channelDir, 'ChannelData.mat');
    'std2_likely_TDL',          fullfile(channelDir, '2-ChannelData.mat');
    'std3_likely_CDL',          fullfile(channelDir, '3-ChannelData.mat');
    'std4_likely_ITU_P681',     fullfile(channelDir, '4-ChannelData.mat');
    'std5_likely_Jakes',        fullfile(channelDir, 'ChannelData_5.mat');
    'std6_likely_CLoo',         fullfile(channelDir, 'ChannelData_6.mat');
    'std7_likely_Corazza',      fullfile(channelDir, 'ChannelData_7.mat');
    'std8_likely_Lutz',         fullfile(channelDir, 'ChannelData_8.mat');
};

modTypes = {'BPSK','QPSK','8PSK','16QAM','32QAM','GMSK'};
convRate = '1/2';

% Keep this short first. If these pass, increase berFrames or add more rates.
symbolRate = 20e6;
sps = 8;
snr = 30;
berWarmUpFrames = 20;
berFrames = 30;

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outDir = fullfile(fileparts(mfilename('fullpath')), ...
    'sweep_results', ['existing_h_models_', timestamp]);
if exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

rows = {};
fprintf('\n==== Existing H-channel model smoke sweep ====\n');
fprintf('Output directory: %s\n', outDir);
fprintf('Modulations: %s\n', strjoin(modTypes, ', '));
fprintf('Coding: convolutional %s, symbolRate=%.3g, SNR=%.1f dB\n', ...
    convRate, symbolRate, snr);

caseIndex = 0;
totalCases = size(channelCases, 1) * numel(modTypes);
for c = 1:size(channelCases, 1)
    channelLabel = channelCases{c, 1};
    channelFile = channelCases{c, 2};

    if exist(channelFile, 'file') ~= 2
        warning('Missing channel file, skipped: %s', channelFile);
        continue;
    end

    for mIdx = 1:numel(modTypes)
        caseIndex = caseIndex + 1;
        modType = modTypes{mIdx};

        fprintf('\n[%03d/%03d] %s | %s | conv %s\n', ...
            caseIndex, totalCases, channelLabel, modType, convRate);

        p = struct( ...
            'modType', modType, ...
            'symbolRate', symbolRate, ...
            'sps', sps, ...
            'snr', snr, ...
            'cfo', 0, ...
            'phaseOffset', 0, ...
            'delay', 0, ...
            'channelCoding', 'convolutional', ...
            'ConvolutionalCodeRate', convRate, ...
            'NumBytesInTransferFrame', 1115, ...
            'RolloffFactor', 0.35, ...
            'hasASM', true, ...
            'hasRandomizer', false, ...
            'berWarmUpFrames', berWarmUpFrames, ...
            'berFrames', berFrames, ...
            'enableHChannel', true, ...
            'HMode', 'h_matrix_file', ...
            'channelFilePath', channelFile, ...
            'channelOutOfRangeMode', 'wrap', ...
            'channelInterpolationMethod', 'linear', ...
            'interpolateChannelDelays', false, ...
            'normalizeHChannel', false, ...
            'enableEqualizer', true, ...
            'equalizerMode', 'mmse', ...
            'equalizerReg', 1e-4, ...
            'normalizeEqualizerOutput', true, ...
            'showFigures', false, ...
            'showPipelineFigure', false, ...
            'showDamageBudgetFigure', false, ...
            'showPowerFigure', false, ...
            'debugGMSK', false, ...
            'debugPerFrameBERSummary', true, ...
            'debugAllPerFrameBER', false, ...
            'debugHFrameStats', false);

        success = true;
        errMsg = "";
        ber = NaN;
        lockPct = NaN;
        evmPost = NaN;
        mer = NaN;
        countedFrames = NaN;
        matchedFrames = NaN;
        decodedFrames = NaN;
        hGainDb = NaN;
        waveformDuration = NaN;
        channelDuration = NaN;

        try
            msg = run_ccsds_tm_evaluation(p);
            r = jsondecode(msg);
            ber = localField(r, 'BER', localField(r, 'ber', NaN));
            lockRaw = localField(r, 'LockRate', NaN);
            if isfinite(lockRaw) && lockRaw <= 1
                lockPct = 100 * lockRaw;
            else
                lockPct = lockRaw;
            end
            evmPost = localField(r, 'EVM_post_pct', NaN);
            mer = localField(r, 'MER_dB', NaN);
            countedFrames = localField(r, 'CountedFrames', NaN);
            matchedFrames = localField(r, 'MatchedFrames', NaN);
            decodedFrames = localField(r, 'DecodedFrames', NaN);
            hGainDb = localNestedField(r, 'stats', 'HGain_dB', ...
                localField(r, 'HGain_dB', localField(r, 'HChannelGain_dB', NaN)));
            waveformDuration = localNestedField(r, 'stats', 'HWaveformDuration_s', ...
                localField(r, 'HWaveformDuration_s', NaN));
            channelDuration = localNestedField(r, 'stats', 'HSourceDuration_s', ...
                localField(r, 'HSourceDuration_s', NaN));
        catch ME
            success = false;
            errMsg = string(ME.message);
            fprintf('   ERROR: %s\n', ME.message);
        end

        fprintf('   BER=%g, Lock=%.1f%%, EVM=%.2f%%, MER=%.2f dB\n', ...
            ber, lockPct, evmPost, mer);

        rows(end+1, :) = { ...
            string(channelLabel), string(channelFile), string(modType), ...
            string('convolutional'), string(convRate), success, ...
            ber, lockPct, evmPost, mer, countedFrames, matchedFrames, ...
            decodedFrames, hGainDb, waveformDuration, channelDuration, errMsg}; %#ok<SAGROW>
    end
end

T_existing_h_models = cell2table(rows, 'VariableNames', { ...
    'ChannelLabel', 'ChannelFile', 'ModType', 'ChannelCoding', 'Rate', ...
    'Success', 'BER', 'LockRate_pct', 'EVM_post_pct', 'MER_dB', ...
    'CountedFrames', 'MatchedFrames', 'DecodedFrames', 'HGain_dB', ...
    'WaveformDuration_s', 'ChannelDuration_s', 'ErrorMessage'});

csvPath = fullfile(outDir, 'existing_h_channel_model_sweep.csv');
matPath = fullfile(outDir, 'existing_h_channel_model_sweep.mat');
writetable(T_existing_h_models, csvPath);
save(matPath, 'T_existing_h_models', 'channelCases', 'modTypes', 'convRate');

fprintf('\n==== Sweep saved ====\n');
fprintf('CSV: %s\n', csvPath);
fprintf('MAT: %s\n', matPath);

weak = T_existing_h_models(~T_existing_h_models.Success | ...
    T_existing_h_models.BER > 1e-3 | ...
    T_existing_h_models.LockRate_pct < 90, :);

fprintf('\n==== Weak / failed cases ====\n');
if isempty(weak)
    fprintf('None under thresholds: BER <= 1e-3 and Lock >= 90%%.\n');
else
    disp(weak(:, {'ChannelLabel','ModType','Rate','BER','LockRate_pct', ...
        'EVM_post_pct','MER_dB','CountedFrames','Success','ErrorMessage'}));
end

disp(T_existing_h_models);

function value = localField(s, name, fallback)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = fallback;
    end
end

function value = localNestedField(s, parentName, childName, fallback)
    if isstruct(s) && isfield(s, parentName) && isstruct(s.(parentName)) && ...
            isfield(s.(parentName), childName) && ~isempty(s.(parentName).(childName))
        value = s.(parentName).(childName);
    else
        value = fallback;
    end
end
