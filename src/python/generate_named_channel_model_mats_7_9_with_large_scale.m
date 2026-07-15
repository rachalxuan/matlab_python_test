% Generate long, clearly named replacements for the old channel MAT files.
%
% Old model labels:
%   default_ChannelData -> ChannelData.mat
%   std2_TDL            -> 2-ChannelData.mat
%   std3_CDL            -> 3-ChannelData.mat
%   std4_ITU_P681       -> 4-ChannelData.mat
%   std5_Jakes          -> ChannelData_5.mat
%   std6_CLoo           -> ChannelData_6.mat
%   std7_Corazza        -> ChannelData_7.mat
%   std8_Lutz           -> ChannelData_8.mat
%
% This script writes new files under:
%   E:\matlab_project\v3.0\v3.0\channel\generated_7_9_withLargeScale
%
% Large-scale losses are enabled and baked into H_Martix_tMode by applying
% the generated LdB field as an amplitude scale: H <- H * 10^(-LdB/20).

clear classes
addpath('E:\web_code\react\fft_project\react-fft\src\python');

modelRoot = 'E:\matlab_project\v3.0\v3.0\ChannelModel _7_9';
outDir = 'E:\matlab_project\v3.0\v3.0\channel\generated_7_9_withLargeScale';
antFile = fullfile(modelRoot, 'external_data', 'AnnexGain', 'Gain.csv');

durationSec = 60;
sampleRateHz = 1e5;

if exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

base = struct( ...
    'sample_rate', sampleRateHz, ...
    'time', durationSec, ...
    'carrier_freq', 4, ...
    'constellation_scene', '1', ...
    'ntn_model', 'B', ...
    'ntn_scene', '1', ...
    'los_status', '1', ...
    'itu_scene', '2', ...
    'free_space_loss', true, ...
    'atmos_absorption', true, ...
    'rain_attenuation', true, ...
    'cloud_fog_attenuation', true, ...
    'tropospheric_scintillation', true, ...
    'ionospheric_scintillation', true, ...
    'beam_diffusion', true, ...
    'shadow_fading', true, ...
    'clutter_loss', true, ...
    'clutter_model', '2', ...
    'polarization_mismatch', true, ...
    'location_probability_p', 50, ...
    'path_num', 3, ...
    'rayleigh_std', 1, ...
    'rice_k_factor', 10, ...
    'log_normal_mean', 3, ...
    'log_normal_std', 1, ...
    'lutz_state', true, ...
    'socket_enable', false, ...
    'antenna_pattern_file', antFile);

models = {
    'default_ChannelData', '1', 'LargeScaleSingle';
    'std2_TDL',            '2', 'TDL_B';
    'std3_CDL',            '3', 'CDL_B';
    'std4_ITU_P681',       '4', 'ITU_P681';
    'std5_Jakes',          '5', 'CustomJakes';
    'std6_CLoo',           '6', 'CLoo';
    'std7_Corazza',        '7', 'Corazza';
    'std8_Lutz',           '8', 'Lutz'
};

results = table('Size', [0 11], ...
    'VariableTypes', {'string','string','string','string','double','double','double','double','double','double','string'}, ...
    'VariableNames', {'OldLabel','Std','Model','File','Seconds','SampleRateHz', ...
        'RMSMean','MeanAbsMean','ZeroPctMax','LdBMean','Status'});

for k = 1:size(models, 1)
    oldLabel = models{k, 1};
    stdCode = models{k, 2};
    modelTag = models{k, 3};

    cp = base;
    cp.channel_standard = stdCode;

    outFile = fullfile(outDir, sprintf( ...
        'ChannelData_7_9_%s_std%s_%s_withLargeScaleLoss_%ds.mat', ...
        oldLabel, stdCode, modelTag, durationSec));

    fprintf('\n==== [%d/%d] Generating %s / std%s_%s -> %s ====\n', ...
        k, size(models, 1), oldLabel, stdCode, modelTag, outFile);

    status = "OK";
    seconds = NaN;
    rmsMean = NaN;
    meanAbsMean = NaN;
    zeroPctMax = NaN;
    ldBMean = NaN;

    try
        generate_channel_model_mat(cp, outFile, ...
            'ChannelModelRoot', modelRoot, ...
            'AntennaIndex', 1, ...
            'CleanOutData', true, ...
            'ApplyLdBToH', true);

        stats = localSummarizeChannelFile(outFile);
        seconds = stats.Seconds;
        rmsMean = stats.RMSMean;
        meanAbsMean = stats.MeanAbsMean;
        zeroPctMax = stats.ZeroPctMax;
        ldBMean = stats.LdBMean;

        fprintf('Check: seconds=%d, rmsMean=%.4g, meanAbsMean=%.4g, zeroPctMax=%.2f%%, LdBMean=%.2f dB\n', ...
            seconds, rmsMean, meanAbsMean, zeroPctMax, ldBMean);
    catch ME
        status = "ERROR: " + string(ME.message);
        fprintf(2, 'FAILED %s / std%s_%s: %s\n', oldLabel, stdCode, modelTag, ME.message);
    end

    newRow = table(string(oldLabel), string(stdCode), string(modelTag), string(outFile), ...
        seconds, sampleRateHz, rmsMean, meanAbsMean, zeroPctMax, ldBMean, status, ...
        'VariableNames', results.Properties.VariableNames);
    results = [results; newRow]; %#ok<AGROW>
end

summaryCsv = fullfile(outDir, sprintf('ChannelData_7_9_withLargeScale_generation_summary_%ds.csv', durationSec));
writetable(results, summaryCsv);

disp(results);
fprintf('\nSummary CSV: %s\n', summaryCsv);
fprintf('Output dir : %s\n', outDir);

function stats = localSummarizeChannelFile(filePath)
    s = load(filePath);
    H = s.H_Martix_tMode;
    if ndims(H) < 3
        H = reshape(H, size(H, 1), size(H, 2), 1);
    end

    nSec = size(H, 3);
    rmsVals = zeros(nSec, 1);
    meanAbsVals = zeros(nSec, 1);
    zeroPctVals = zeros(nSec, 1);

    for idx = 1:nSec
        hk = H(:, :, idx);
        mag = abs(hk(:));
        rmsVals(idx) = sqrt(mean(mag.^2));
        meanAbsVals(idx) = mean(mag);
        zeroPctVals(idx) = 100 * mean(mag < 1e-12);
    end

    if isfield(s, 'LdB') && ~isempty(s.LdB)
        ldB = double(s.LdB(:));
        ldB = ldB(isfinite(ldB));
        if isempty(ldB)
            ldBMean = NaN;
        else
            ldBMean = mean(ldB);
        end
    else
        ldBMean = NaN;
    end

    stats = struct();
    stats.Seconds = nSec;
    stats.RMSMean = mean(rmsVals);
    stats.MeanAbsMean = mean(meanAbsVals);
    stats.ZeroPctMax = max(zeroPctVals);
    stats.LdBMean = ldBMean;
end
