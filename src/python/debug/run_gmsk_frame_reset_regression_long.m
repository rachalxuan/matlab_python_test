%% RUN_GMSK_FRAME_RESET_REGRESSION_LONG
% Manual regression for modulation branches that must remain untouched.
% Ten NoH cases: none + convolutional 1/2 for five baseline modulations.

clear classes
rng(20260715, 'twister');

debugDir = fileparts(mfilename('fullpath'));
srcPythonDir = fileparts(debugDir);
addpath(srcPythonDir);

stamp = datestr(now, 'yyyymmdd_HHMMSS');
outputDir = fullfile(srcPythonDir, 'sweep_results', ...
    ['gmsk_frame_reset_other_mod_regression_' stamp]);

opts = struct();
opts.outputDir = outputDir;
opts.modTypes = {'BPSK','QPSK','8PSK','16QAM','32QAM'};
opts.convRates = {'1/2'};
opts.includeNoHBaseline = true;
opts.includeHEqualized = false;
opts.includeNormHScenario = false;
opts.includeNoEqualizerScenario = false;
opts.includeLDPC = false;
opts.includeTurbo = false;
opts.includeTPC = false;

opts.symbolRate = 20e6;
opts.sps = 8;
opts.snr = 100;
opts.noisePlacement = 'afterChannel';
opts.noisePSDdBmHz = [];
opts.cfo = 0;
opts.phaseOffset = 0;
opts.delay = 0;
opts.hasASM = true;
opts.RandomizerEnabled = false;
opts.berWarmUpFrames = 5;
opts.berFrames = 20;
opts.showFigures = false;
opts.randomSeed = 20260715;
opts.clearFunctionCache = true;

% This option is deliberately present during regression.  Non-GMSK branches
% must ignore it and preserve their existing result.
opts.GMSKDetectionMode = 'legacy-frame-reset';

T = sweep_h_channel_short_frames(opts);
regressionPath = fullfile(outputDir, 'other_modulation_regression_key.csv');
writetable(T, regressionPath);

disp(T(:, {'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','LockRate_pct','FER','Success','Status'}));

failed = ~T.Success | T.BER > 1e-8 | T.LockRate_pct < 95;
if any(failed)
    warning('run_gmsk_frame_reset_regression_long:Regression', ...
        '%d/%d cases missed the BER/lock requirement. Return the CSV and log.', ...
        nnz(failed), height(T));
else
    fprintf('[Other modulation regression] PASS: %d/%d cases.\n', ...
        height(T), height(T));
end
fprintf('Regression CSV: %s\n', regressionPath);
assignin('base', 'gmskOtherModRegression', T);
