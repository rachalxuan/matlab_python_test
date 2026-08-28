clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

o = struct();
o.outputDir = ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds/tpc_alignment_regression_v1';

% TPC only: four high-order modulations, NoH + seven normalized H files,
% and all three randomizer positions used by the full system sweep.
o.ProfileNames = { ...
    'combined_scramble_off', ...
    'combined_scramble_after', ...
    'combined_scramble_before'};
o.includeDualIQ = false;
o.includeUnequalUQPSK = false;
o.includeBeforeEncodingRandomizer = true;
o.singleModTypes = {'16QAM','32QAM','16APSK','32APSK'};

o.includeUncoded = false;
o.includeRS = false;
o.includeConvolutional = false;
o.includeLDPC = false;
o.includeTurbo = false;
o.includeTPC = true;
o.tpcCases = {struct('TPCCodeRate','1/2','TPCBlocksPerTF',8)};

o.includeNoHBaseline = true;
o.useRawH = false;
o.symbolRate = 10e6;
o.sps = 8;
o.berWarmUpFrames = 8;
o.berFrames = 30;
o.excludeBERWarmUpFrames = true;

o.noisePlacement = 'afterChannel';
o.noiseMode = 'psd';
o.noisePSDdBmHz = -115.3;
o.noiseBandwidthHz = [];
o.inputLevelDbm = -10;

o.collectPredecoderStats = true;
o.debugCodedBoundary = true;
o.debugTPC = true;
o.showFigures = false;

o.maxGoodBER = 1e-5;
o.maxGoodFER = 0;
o.minGoodLockPct = 90;
o.minGoodMERdB = 18;

o.Resume = true;
o.RerunFailed = false;
o.MaxNewCases = Inf;
o.FailOnFailure = false;

[T, S] = sweep_tm_normalized_h_system(o);
disp(S);

F = T(string(T.Status) ~= "PASS", { ...
    'SystemProfile','Scenario','ModType','ChannelCoding','Rate', ...
    'BER','PredecoderBER','LockRate_pct','FER', ...
    'EVM_post_pct','MER_dB','Status','ErrorMessage'});
disp(F);
writetable(F, fullfile(o.outputDir, 'tpc_failed_cases_filtered.csv'));
