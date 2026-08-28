clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Focused post-fix check.  This deliberately uses a new output directory so
% results produced before the QAM/ASM/TPC guard changes cannot be resumed or
% mixed with this run.
o = struct();
o.modTypes = {'16QAM','32QAM','16APSK','32APSK'};
o.hModelCases = { ...
    'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};

o.includeNoHBaseline = true;
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

% Keep the deliberately difficult non-whitened TPC profile.  If this check
% improves, the gain is from the receiver changes rather than randomization.
o.RandomizerEnabled = false;
o.RandomizerFECPosition = 'afterEncoding';

% QAM: estimate channel magnitude from gated constellation decisions instead
% of interpreting the data-dependent 16-symbol power as fading.
o.enableQAMPowerGainTracker = true;
o.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','decision', ...
    'UpdatePowerReference',false, ...
    'TrackMagnitude',true, ...
    'TrackPhase',false);

% APSK: use the standard pilotless receiver and the existing sparse ASM
% timeline to repair reliable frame-to-frame quadrant slips under H.
o.APSKReceiverMode = 'pilotless';
o.useTMAPSKPilots = false;
o.enableASMFramePhaseCorrection = true;
o.asmFramePhaseCorrectionMaxError = 6;
o.asmFramePhaseCorrectionMinGap = 4;
o.asmFramePhaseCorrectionMinReliableFraction = 0.80;
o.debugASMPhaseTimelineFrames = 64;

o.collectPredecoderStats = true;
o.debugCodedBoundary = true;
o.debugTPC = true;
o.debugAdaptiveEqualizer = true;
o.debugPilotlessAPSK = true;
o.debugASMPhase = true;
o.debugSynchronizationChain = true;
o.showFigures = false;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/tpc_frontend_fix_check_v2';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

displayFields = { ...
    'Scenario','ModType','BER','PredecoderBER','PredecoderSteadyBER', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMPowerGainApplied','QAMPowerGainAcceptanceRate_pct', ...
    'ASMFramePhaseCorrectionEnabled','ASMFramePhaseCorrectionApplied', ...
    'ASMFramePhaseCorrectionFrames','ASMFramePhaseCorrectionReliableFrames', ...
    'ASMFramePhaseCycleSlipsBefore','ASMFramePhaseCycleSlipsAfter', ...
    'Status','ErrorMessage'};
displayFields = displayFields(ismember(displayFields,T.Properties.VariableNames));
disp(T(:,displayFields));

