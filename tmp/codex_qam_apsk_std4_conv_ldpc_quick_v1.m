clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Fast front-end/coding triage after the shared-reliability A/B test.
% 4 modulations x 2 coding modes x (NoH + normalized std4) = 16 cases.
% Thirty measured frames are long enough for these encoded frames to reach
% the first strong std4 fade near 9-10 ms; TPC is excluded because it was
% already tested separately and dominates runtime.
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

% Representative operational coding paths.  Uncoded and the already
% diagnosed TPC path are intentionally excluded from this quick pass.
o.includeUncoded = false;
o.includeRS = false;
o.includeConvolutional = true;
o.convRates = {'1/2'};
o.includeLDPC = true;
o.ldpcRates = {'1/2'};
o.includeTurbo = false;
o.includeTPC = false;

o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 6;
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
o.randomSeed = 20260828;
o.SeedMode = 'pairedChannelProfile';

% Keep the failed experimental shared-HOLD controller OFF.  QAM continues
% to use its current BPS/gain path; APSK uses the current pilotless path.
o.enableBlindReliabilityManager = false;
o.enableQAMBlindPhaseSearch = [];
o.enableQAMPowerGainTracker = true;
o.useTMAPSKPilots = false;
o.APSKReceiverMode = 'pilotless';

o.collectPredecoderStats = true;
o.debugCodedBoundary = false;
o.debugAdaptiveEqualizer = false;
o.debugPilotlessAPSK = false;
o.debugHFrameStats = false;
o.showFigures = false;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

% Empty selects a new timestamped result folder automatically, so the
% command can be repeated without editing a RunId or overwriting a run.
o.outputDir = '';
o.Resume = false;
o.RerunFailed = false;

T = sweep_h_channel_short_frames(o);

fields = { ...
    'Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','PredecoderSteadyBER', ...
    'LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchApplied', ...
    'QAMBlindPhaseSearchReliableRate_pct', ...
    'QAMBlindPhaseSearchFadeEvents', ...
    'QAMBlindPhaseSearchReacquisitions', ...
    'PilotlessAPSKApplied', ...
    'PilotlessAPSKBlindPhaseSearchReliableRate_pct', ...
    'PilotlessAPSKCarrierHoldFraction_pct', ...
    'PilotlessAPSKCarrierPhaseErrorRMS_deg', ...
    'PilotlessAPSKResidualFrequency_Hz', ...
    'BlindReliabilityApplied','Status','ErrorMessage'};
fields = fields(ismember(fields,T.Properties.VariableNames));
D = T(:,fields);
disp(D);

F = D(string(D.Status) ~= "PASS",:);
fprintf('\n================ FAILED / WEAK ================\n');
disp(F);

