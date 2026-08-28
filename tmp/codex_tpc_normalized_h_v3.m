clearvars; clear classes; rehash;
rootDir = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(rootDir, 'src/python'), '-begin');

rootOut = fullfile(rootDir, ...
    'artifacts/ccsds/tpc_normalized_h_v3');
profiles = { ...
    'scramble_off',   false, 'afterEncoding'; ...
    'scramble_after', true,  'afterEncoding'; ...
    'scramble_before',true,  'beforeEncoding'};

base = struct();
base.modTypes = {'BPSK','QPSK','OQPSK','UQPSK','8PSK', ...
    '16QAM','32QAM','16APSK','32APSK','MSK','GMSK'};
base.hModelCases = { ...
    'std2_TDL',      'E:/matlab_project/v3.0/v3.0/channel/2-ChannelData.mat'; ...
    'std3_CDL',      'E:/matlab_project/v3.0/v3.0/channel/3-ChannelData.mat'; ...
    'std4_ITU_P681', 'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'; ...
    'std5_Jakes',    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_5.mat'; ...
    'std6_CLoo',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_6.mat'; ...
    'std7_Corazza',  'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'; ...
    'std8_Lutz',     'E:/matlab_project/v3.0/v3.0/channel/ChannelData_8.mat'};
base.includeNoHBaseline = true;
base.includeNoHEqualizedBaseline = false;
base.includeHEqualized = false;
base.includeNormHScenario = true;
base.includeNoEqualizerScenario = false;
base.includeUncoded = false;
base.includeRS = false;
base.includeConvolutional = false;
base.includeLDPC = false;
base.includeTurbo = false;
base.includeTPC = true;
base.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};
base.symbolRate = 10e6;
base.sps = 8;
base.berWarmUpFrames = 8;
base.berFrames = 30;
base.excludeBERWarmUpFrames = true;
base.noisePlacement = 'afterChannel';
base.noiseMode = 'psd';
base.noisePSDdBmHz = -115.3;
base.noiseBandwidthHz = [];
base.inputLevelDbm = -10;
base.channelOutOfRangeMode = 'wrap';
base.equalizerMode = 'blind-cma-lms';
base.useTMAPSKPilots = false;
base.APSKReceiverMode = 'pilotless';
base.enableQAMBlindPhaseSearch = true;
% The generic BPS is deliberately excluded only for TPC.  Set true solely
% when reproducing the former BER=0.5 failure as an A/B diagnostic.
base.enableQAMBlindPhaseSearchForTPC = false;
base.enableQAMPowerGainTracker = true;
base.GMSKDetectionMode = 'official-viterbi-frame-reset';
base.randomSeed = 20260824;
base.SeedMode = 'pairedChannelProfile';
base.maxGoodBER = 1e-5;
base.maxGoodFER = 0;
base.minGoodLockPct = 90;
base.minGoodMERdB = 18;
base.collectPredecoderStats = true;
base.debugCodedBoundary = false;
base.debugAdaptiveEqualizer = false;
base.showFigures = false;
base.Resume = true;
base.RerunFailed = false;
base.MaxNewCases = Inf;

allResults = table();
for iProfile = 1:size(profiles,1)
    o = base;
    profileName = profiles{iProfile,1};
    o.RandomizerEnabled = profiles{iProfile,2};
    o.RandomizerFECPosition = profiles{iProfile,3};
    o.outputDir = fullfile(rootOut, profileName);
    o.clearFunctionCache = iProfile == 1;
    T = sweep_h_channel_short_frames(o);
    T.TPCProfile = repmat(string(profileName), height(T), 1);
    allResults = [allResults; T]; %#ok<AGROW>
end

S = groupsummary(allResults, {'TPCProfile','ModType','Status'});
disp(S(:, {'TPCProfile','ModType','Status','GroupCount'}));

failed = allResults(string(allResults.Status) ~= "PASS", { ...
    'TPCProfile','Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied','GMSKDetectorUsed', ...
    'Status','ErrorMessage'});
disp(failed);

% Every profile has its own checkpoint/CSV.  A viewer locking this optional
% combined CSV must not destroy a completed long sweep.
try
    writetable(allResults, fullfile(rootOut, 'tpc_normalized_h_all.csv'));
    writetable(failed, fullfile(rootOut, 'tpc_normalized_h_failed.csv'));
catch ME
    warning('TPCV3:CombinedCSVWriteFailed', ...
        ['Per-profile checkpoints are complete, but combined CSV output ', ...
         'failed: %s'], ME.message);
end
