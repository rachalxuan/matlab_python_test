clearvars;
clear classes;
rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

base = struct();
base.modTypes = {'32APSK'};
base.hModelCases = {'std4_ITU_P681', ...
    'E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat'};
base.includeNoHBaseline = false;
base.includeNoHEqualizedBaseline = false;
base.includeHEqualized = false;
base.includeNormHScenario = true;
base.includeNoEqualizerScenario = false;
base.includeUncoded = true;
base.includeRS = false;
base.includeConvolutional = false;
base.includeLDPC = false;
base.includeTurbo = false;
base.includeTPC = false;
base.symbolRate = 10e6;
base.sps = 8;
base.berWarmUpFrames = 2;
base.berFrames = 8;
base.excludeBERWarmUpFrames = true;
base.noiseMode = 'psd';
base.noisePlacement = 'afterChannel';
base.noisePSDdBmHz = -115.3;
base.inputLevelDbm = -10;
base.APSKReceiverMode = 'pilotless';
base.useTMAPSKPilots = false;
base.equalizerMode = 'off';
base.enablePilotlessAPSKComplexGainTracker = true;
base.enableASMFramePhaseCorrection = true;
base.debugPilotlessAPSK = false;
base.debugAdaptiveEqualizer = false;
base.debugCodedBoundary = false;
base.debugASMPhase = false;
base.showFigures = false;
base.Resume = false;
base.RerunFailed = false;
base.randomSeed = 20260827;
base.SeedMode = 'pairedChannelProfile';

steps = [0.005 0.01 0.02 0.04];
rows = cell(numel(steps),1);
for k = 1:numel(steps)
    o = base;
    o.PilotlessAPSKCarrierRecovery = struct( ...
        'EnableRingNormalizer',true, ...
        'RingNormalizer',struct( ...
            'EstimatorMode','rde', ...
            'EnableFadeHold',true, ...
            'FadeEnterDB',-10, ...
            'FadeExitDB',-6, ...
            'StepSize',steps(k), ...
            'Debug',false), ...
        'EnableBlindPhaseSearch',true, ...
        'EnableDDPhaseTracker',false);
    o.outputDir = fullfile( ...
        'E:/web_code/react/fft_project/react-fft/tmp', ...
        sprintf('validate_apsk_rde_mu_%g',steps(k)));
    T = sweep_h_channel_short_frames(o);
    rows{k} = table(steps(k),T.BER(1),T.LockRate_pct(1),T.FER(1), ...
        T.EVM_post_pct(1),T.EVMRadial_pct(1), ...
        T.EVMTangential_pct(1),T.MER_dB(1),string(T.Status(1)), ...
        'VariableNames',{'StepSize','BER','Lock_pct','FER','EVM_pct', ...
        'RadialEVM_pct','TangentialEVM_pct','MER_dB','Status'});
end

R = vertcat(rows{:});
disp(R);
writetable(R, ...
    'E:/web_code/react/fft_project/react-fft/tmp/validate_apsk_rde_step.csv');
