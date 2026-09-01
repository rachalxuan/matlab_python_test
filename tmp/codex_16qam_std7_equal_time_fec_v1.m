clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Compare coding schemes over approximately the same physical waveform
% duration.  A fixed frame count is not a fair burst-channel comparison
% because the coded frame lengths differ by almost one order of magnitude.
profiles = { ...
    struct('Name','none',       'Coding','none',          'RSI',1, 'BERFrames',81); ...
    struct('Name','rs_i1',      'Coding','RS',            'RSI',1, 'BERFrames',378); ...
    struct('Name','rs_i8',      'Coding','RS',            'RSI',8, 'BERFrames',41); ...
    struct('Name','conv_1_2',   'Coding','convolutional', 'RSI',1, 'BERFrames',37); ...
    struct('Name','concat_i1',  'Coding','concatenated',  'RSI',1, 'BERFrames',185); ...
    struct('Name','concat_i8',  'Coding','concatenated',  'RSI',8, 'BERFrames',17)};

runTag = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
runRoot = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['16qam_std7_equal_time_fec_v1_' runTag]);

T = table();
for iProfile = 1:numel(profiles)
    cfg = profiles{iProfile};
    o = struct();
    o.modTypes = {'16QAM'};
    o.hModelCases = { ...
        'std7_Corazza', ...
        'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};

    o.includeNoHBaseline = true;
    o.includeNoHEqualizedBaseline = false;
    o.includeHEqualized = false;
    o.includeNormHScenario = true;
    o.includeNoEqualizerScenario = false;

    o.includeUncoded = strcmp(cfg.Coding,'none');
    o.includeRS = strcmp(cfg.Coding,'RS');
    o.rsInterleavingDepths = cfg.RSI;
    o.includeConvolutional = strcmp(cfg.Coding,'convolutional');
    o.convRates = {'1/2'};
    o.includeConcatenated = strcmp(cfg.Coding,'concatenated');
    o.concatenatedConvRates = {'1/2'};
    o.concatenatedRSInterleavingDepths = cfg.RSI;
    o.includeLDPC = false;
    o.includeTurbo = false;
    o.includeTPC = false;

    o.symbolRate = 10e6;
    o.sps = 8;
    o.berWarmUpFrames = 8;
    o.berFrames = cfg.BERFrames;
    o.excludeBERWarmUpFrames = true;

    o.noisePlacement = 'afterChannel';
    o.noiseMode = 'psd';
    o.noisePSDdBmHz = -115.3;
    o.noiseBandwidthHz = [];
    o.inputLevelDbm = -10;

    o.equalizerMode = 'blind-cma-lms';
    o.enableQAMBlindPhaseSearch = true;
    o.enableQAMPowerGainTracker = true;
    o.enableBlindReliabilityManager = false;
    o.enableASMFramePhaseCorrection = true;
    o.enableQAMBPSHoldLLRErasure = false;

    o.RandomizerEnabled = false;
    o.ConvolutionalG1G2Mode = 'G1G2-inverted';
    o.randomSeed = 20260829;
    o.SeedMode = 'pairedChannelProfile';

    o.debugCodedBoundary = false;
    o.collectPredecoderStats = true;
    o.debugASMPhase = false;
    o.debugQAMBPSFadeBER = true;
    o.showFigures = false;

    o.maxGoodBER = 1e-5;
    o.maxGoodFER = 0;
    o.minGoodLockPct = 90;
    o.minGoodMERdB = 18;

    o.outputDir = fullfile(runRoot,cfg.Name);
    o.Resume = false;
    o.RerunFailed = false;

    fprintf('\n============================================================\n');
    fprintf(' Equal-time FEC %d/%d: %s, BER frames=%d\n', ...
        iProfile,numel(profiles),cfg.Name,cfg.BERFrames);
    fprintf('============================================================\n');

    part = sweep_h_channel_short_frames(o);
    part.EqualTimeProfile = repmat(string(cfg.Name),height(part),1);
    T = [T; part]; %#ok<AGROW>
end

wanted = { ...
    'EqualTimeProfile','Scenario','ChannelCoding','Rate', ...
    'ActualWaveformDuration_s','BER','PredecoderBER', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB','Status'};
wanted = wanted(ismember(wanted,T.Properties.VariableNames));
D = T(:,wanted);
disp(D);
writetable(D,fullfile(runRoot,'equal_time_fec_summary.csv'));
fprintf('\nEqual-time result: %s\n', ...
    fullfile(runRoot,'equal_time_fec_summary.csv'));
