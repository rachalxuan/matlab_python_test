% Generate receiver-ready ChannelData MAT files from ChannelModel _7_9.
%
% Run this script from MATLAB. It writes combined H-matrix files to:
%   E:\matlab_project\v3.0\v3.0\channel\generated_7_9
%
% The generated files keep large-scale/link-budget losses disabled so they
% are suitable for receiver synchronization/equalization tests. Path loss
% and noise PSD tests should be run separately.

clear classes
addpath('E:\web_code\react\fft_project\react-fft\src\python');

modelRoot = 'E:\matlab_project\v3.0\v3.0\ChannelModel _7_9';
outDir = 'E:\matlab_project\v3.0\v3.0\channel\generated_7_9';
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
    'free_space_loss', false, ...
    'atmos_absorption', false, ...
    'rain_attenuation', false, ...
    'cloud_fog_attenuation', false, ...
    'tropospheric_scintillation', false, ...
    'ionospheric_scintillation', false, ...
    'beam_diffusion', false, ...
    'shadow_fading', false, ...
    'clutter_loss', false, ...
    'clutter_model', '2', ...
    'polarization_mismatch', false, ...
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
    '1', 'LargeScaleSingle';
    '2', 'TDL_B';
    '3', 'CDL_B';
    '4', 'ITU_P681';
    '5', 'CustomJakes';
    '6', 'CLoo';
    '7', 'Corazza';
    '8', 'Lutz'
};

results = table('Size', [0 9], ...
    'VariableTypes', {'string','string','string','double','double','double','double','double','string'}, ...
    'VariableNames', {'Std','Model','File','Seconds','SampleRateHz','RMSMean','MeanAbsMean','ZeroPctMax','Status'});

for k = 1:size(models, 1)
    cp = base;
    cp.channel_standard = models{k, 1};

    modelTag = models{k, 2};
    outFile = fullfile(outDir, sprintf( ...
        'ChannelData_7_9_std%s_%s_smallScaleOnly_%ds.mat', ...
        models{k, 1}, modelTag, durationSec));

    fprintf('\n==== [%d/%d] Generating std%s_%s -> %s ====\n', ...
        k, size(models, 1), models{k, 1}, modelTag, outFile);

    status = "OK";
    seconds = NaN;
    rmsMean = NaN;
    meanAbsMean = NaN;
    zeroPctMax = NaN;

    try
        generate_channel_model_mat(cp, outFile, ...
            'ChannelModelRoot', modelRoot, ...
            'AntennaIndex', 1, ...
            'CleanOutData', true);

        stats = localSummarizeChannelFile(outFile);
        seconds = stats.Seconds;
        rmsMean = stats.RMSMean;
        meanAbsMean = stats.MeanAbsMean;
        zeroPctMax = stats.ZeroPctMax;

        fprintf('Check: seconds=%d, rmsMean=%.4g, meanAbsMean=%.4g, zeroPctMax=%.2f%%\n', ...
            seconds, rmsMean, meanAbsMean, zeroPctMax);
    catch ME
        status = "ERROR: " + string(ME.message);
        fprintf(2, 'FAILED std%s_%s: %s\n', models{k, 1}, modelTag, ME.message);
    end

    newRow = table(string(models{k, 1}), string(modelTag), string(outFile), ...
        seconds, sampleRateHz, rmsMean, meanAbsMean, zeroPctMax, status, ...
        'VariableNames', results.Properties.VariableNames);
    results = [results; newRow]; %#ok<AGROW>
end

summaryCsv = fullfile(outDir, sprintf('ChannelData_7_9_generation_summary_%ds.csv', durationSec));
writetable(results, summaryCsv);

disp(results);
fprintf('\nSummary CSV: %s\n', summaryCsv);
fprintf('Output dir : %s\n', outDir);

function stats = localSummarizeChannelFile(filePath)
    s = load(filePath, 'H_Martix_tMode');
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

    stats = struct();
    stats.Seconds = nSec;
    stats.RMSMean = mean(rmsVals);
    stats.MeanAbsMean = mean(meanAbsVals);
    stats.ZeroPctMax = max(zeroPctVals);
end
