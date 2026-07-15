clear classes
addpath('E:\web_code\react\fft_project\react-fft\src\python');

opts = struct();
opts.modTypes = {'BPSK','QPSK','8PSK','16QAM','32QAM'};
opts.convRates = {'1/2','2/3','3/4','5/6','7/8'};

opts.includeNoHBaseline = true;
opts.includeHEqualized = true;

opts.symbolRate = 10e6;
opts.sps = 8;
opts.snr = 100;

opts.berWarmUpFrames = 20;
opts.berFrames = 60;

opts.channelFilePath = 'E:\matlab_project\v3.0\v3.0\channel\ChannelData.mat';
opts.channelOutOfRangeMode = 'wrap';
opts.normalizeEqualizerOutput = true;
opts.equalizerMode = 'mmse';

opts.debugPerFrameBERSummary = true;
opts.debugAllPerFrameBER = false;

T = sweep_h_channel_short_frames(opts);
T(:, {'Scenario','ModType','ChannelCoding','Rate','BER','LockRate_pct','FER','WaveformDuration_s'})

%% 能切换信道模型的


clear classes
addpath('E:\web_code\react\fft_project\react-fft\src\python');

channelDir = 'E:\matlab_project\v3.0\v3.0\channel';

opts = struct();

opts.hModelCases = {
    'default_ChannelData',      fullfile(channelDir, 'ChannelData.mat');
    'std2_likely_TDL',          fullfile(channelDir, '2-ChannelData.mat');
    'std3_likely_CDL',          fullfile(channelDir, '3-ChannelData.mat');
    'std4_likely_ITU_P681',     fullfile(channelDir, '4-ChannelData.mat');
    'std5_likely_Jakes',        fullfile(channelDir, 'ChannelData_5.mat');
    'std6_likely_CLoo',         fullfile(channelDir, 'ChannelData_6.mat');
    'std7_likely_Corazza',      fullfile(channelDir, 'ChannelData_7.mat');
    'std8_likely_Lutz',         fullfile(channelDir, 'ChannelData_8.mat');
};

opts.modTypes = {'BPSK','QPSK','8PSK','16QAM','32QAM','GMSK'};
opts.convRates = {'1/2','2/3','3/4','5/6','7/8'};

opts.includeNoHBaseline = true;
opts.includeHEqualized = true;
opts.includeNormHScenario = false;
opts.includeNoEqualizerScenario = false;

opts.symbolRate = 20e6;
opts.sps = 8;
opts.snr = 30;
opts.berWarmUpFrames = 10;
opts.berFrames = 30;

% opts.channelOutOfRangeMode = 'wrap';
% opts.channelInterpolationMethod = 'linear';
% opts.interpolateChannelDelays = false;

opts.equalizerMode = 'mmse';
% opts.equalizerReg = 1e-4;
opts.normalizeEqualizerOutput=true;

opts.debugPerFrameBERSummary = true;
opts.debugAllPerFrameBER = false;

T_models = sweep_h_channel_short_frames(opts);
%% 测试信道
clear classes
addpath('E:\web_code\react\fft_project\react-fft\src\python');

chDir = 'E:\matlab_project\v3.0\v3.0\channel';

opts = struct();
opts.hModelCases = {
    'default_ChannelData',  fullfile(chDir,'ChannelData.mat');
    'std2_likely_TDL',      fullfile(chDir,'2-ChannelData.mat');
    'std3_likely_CDL',      fullfile(chDir,'3-ChannelData.mat');
    'std4_likely_ITU_P681', fullfile(chDir,'4-ChannelData.mat');
    'std5_likely_Jakes',    fullfile(chDir,'ChannelData_5.mat');
    'std6_likely_CLoo',     fullfile(chDir,'ChannelData_6.mat');
    'std7_likely_Corazza',  fullfile(chDir,'ChannelData_7.mat');
    'std8_likely_Lutz',     fullfile(chDir,'ChannelData_8.mat')
};

opts.includeNoHBaseline = true;
opts.includeHEqualized = true;
    opts.berWarmUpFrames = 10;
    opts.berFrames = 30;

opts.debugEqualizerStats = false;
opts.debugAllPerFrameBER = false;
opts.modTypes = {'GMSK'};
opts.convRates = {'1/2','2/3','3/4','5/6','7/8'};
opts.debugGMSK = true;
opts.debugASMPhase = true;
opts.debugPerFrameBERSummary = true;
opts.debugPerFrameBERNonzeroCount = 40;
opts.debugHFrameStats = true;
opts.debugHFrameStatsStart = 1;
opts.debugHFrameStatsCount = 60;
opts.debugEqualizerStats = true;
T = sweep_h_channel_short_frames(opts);

chDir = 'E:\matlab_project\v3.0\v3.0\channel';

opts.hModelCases = {
    'default_ChannelData', fullfile(chDir,'ChannelData.mat');
    'std2_TDL',            fullfile(chDir,'2-ChannelData.mat');
    'std3_CDL',            fullfile(chDir,'3-ChannelData.mat');
    'std4_ITU_P681',       fullfile(chDir,'4-ChannelData.mat');
    'std5_Jakes',          fullfile(chDir,'ChannelData_5.mat');
    'std6_CLoo',           fullfile(chDir,'ChannelData_6.mat');
    'std7_Corazza',        fullfile(chDir,'ChannelData_7.mat');
    'std8_Lutz',           fullfile(chDir,'ChannelData_8.mat')
};
opts.noisePlacement = 'afterChannel';
opts.equalizerMode = 'zf';
sweep_h_channel_short_frames(opts);
