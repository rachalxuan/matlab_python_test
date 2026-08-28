clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Two-case diagnostic only: correlate the coded-boundary error burst with
% per-frame H amplitude/Doppler and post-equalizer residual statistics.
o = struct();
o.modTypes = {'16QAM','32QAM'};
o.hModelCases = { ...
    'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};

o.includeNoHBaseline = false;
o.includeNoHEqualizedBaseline = false;
o.includeHEqualized = false;
o.includeNormHScenario = true;
o.includeNoEqualizerScenario = false;

o.includeUncoded = false;
o.includeRS = false;
o.includeConvolutional = false;
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = true;
o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 8;
o.berFrames = 30;
o.excludeBERWarmUpFrames = true;
o.channelOutOfRangeMode = 'wrap';

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';
o.randomSeed = 1;
o.SeedMode = 'pairedChannelProfile';

o.enableQAMPowerGainTracker = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','decision', ...
    'UpdatePowerReference',false, ...
    'TrackMagnitude',true, ...
    'TrackPhase',false);

o.collectPredecoderStats = true;
o.debugCodedBoundary = true;
o.debugPredecoderMaxBurstFrames = 16;
o.debugTPC = true;
o.debugAdaptiveEqualizer = true;
o.debugSynchronizationChain = true;

% Thirty-eight coded frames are generated in this configuration.  Matching
% both diagnostics to that count makes a burst such as rxFrame=23 directly
% comparable with H-frame 23 and synchronization segment 23.
o.debugHFrameStats = true;
o.debugHFrameStatsStart = 1;
o.debugHFrameStatsCount = 40;
o.debugSyncSegmentCount = 38;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;
o.showFigures = false;

o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/tpc_std4_burst_debug_v3';
o.Resume = false;
o.RerunFailed = false;

if ~isfolder(o.outputDir)
    mkdir(o.outputDir);
end
debugLogFile = fullfile(o.outputDir,'burst_debug_console.txt');
diary off;
diary(debugLogFile);
diaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>

T = sweep_h_channel_short_frames(o);

fields = { ...
    'Scenario','ModType','BER','PredecoderBER','PredecoderSteadyBER', ...
    'PredecoderFrameBERP95','PredecoderFrameBERMax', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB','Status','ErrorMessage'};
fields = fields(ismember(fields,T.Properties.VariableNames));
disp(T(:,fields));
fprintf('\nFull diagnostic log: %s\n',debugLogFile);
