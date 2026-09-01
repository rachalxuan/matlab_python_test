clearvars; clear classes; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');

% Isolated diagnosis only: all synchronization/equalizer parameters are
% identical.  The sole A/B variable is frame-wise ASM phase correction.
b = struct();
b.modTypes = {'16QAM'};
b.hModelCases = { ...
    'std7_Corazza', ...
    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat'};

b.includeNoHBaseline = false;
b.includeNoHEqualizedBaseline = false;
b.includeHEqualized = false;
b.includeNormHScenario = true;
b.includeNoEqualizerScenario = false;

b.includeUncoded = true;
b.includeConvolutional = false;
b.includeRS = false;
b.includeLDPC = false;
b.includeTurbo = false;
b.includeTPC = false;

b.symbolRate = 10e6;
b.sps = 8;
b.berWarmUpFrames = 8;
b.berFrames = 80;
b.excludeBERWarmUpFrames = true;

b.noisePlacement = 'afterChannel';
b.noiseMode = 'psd';
b.noisePSDdBmHz = -115.3;
b.noiseBandwidthHz = [];
b.inputLevelDbm = -10;

% Keep the current production QAM front end unchanged.
b.equalizerMode = 'blind-cma-lms';
b.enableQAMBlindPhaseSearch = true;
b.enableQAMPowerGainTracker = true;
b.enableQAMPostBPSAdaptiveEqualizer = false;
b.enableBlindReliabilityManager = false;

b.RandomizerEnabled = false;
b.randomSeed = 20260828;
b.SeedMode = 'pairedChannelProfile';

b.maxGoodBER = 1e-5;
b.maxGoodFER = 0;
b.minGoodLockPct = 90;
b.minGoodMERdB = 18;

% First 70 frames expose rotation, ASM error/inverted error and payload BER.
b.debugASMPhase = true;
b.debugASMPhaseTimelineFrames = 70;
b.debugFrameCheck = true;
b.debugFrameCheckCount = 70;
b.debugAllPerFrameBER = true;
b.debugPerFrameBERCount = 70;
b.debugQAMBPSFadeBER = true;
b.debugAdaptiveEqualizer = true;
b.QAMBPSFadeBERRecoveryFrames = 1;
b.QAMBPSFadeBERHoldFrameMinFraction = 0;
b.showFigures = false;

runTag = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
runRoot = fullfile( ...
    'E:/web_code/react/fft_project/react-fft/artifacts/ccsds', ...
    ['std7_16qam_asm_phase_ab_v1_' runTag]);

T = table();
asmCorrectionValues = [true false];
asmCorrectionLabels = {'asm_correction_on','asm_correction_off'};
for iAB = 1:numel(asmCorrectionValues)
    o = b;
    o.enableASMFramePhaseCorrection = asmCorrectionValues(iAB);
    o.outputDir = fullfile(runRoot,asmCorrectionLabels{iAB});
    o.Resume = false;
    o.RerunFailed = false;

    fprintf('\n============================================================\n');
    fprintf(' std7 + 16QAM A/B: enableASMFramePhaseCorrection = %d\n', ...
        o.enableASMFramePhaseCorrection);
    fprintf('============================================================\n');
    part = sweep_h_channel_short_frames(o);
    part.ASMFrameCorrectionRequested = repmat( ...
        logical(asmCorrectionValues(iAB)),height(part),1);
    T = [T; part]; %#ok<AGROW>
end

displayFields = { ...
    'ASMFrameCorrectionRequested','Scenario','ModType', ...
    'BER','LockRate_pct','FER','EVM_post_pct','MER_dB', ...
    'QAMBlindPhaseSearchFadeHolds','QAMBlindPhaseSearchFadeRecoveries', ...
    'ASMFramePhaseCycleSlipsBefore','ASMFramePhaseCycleSlipsAfter', ...
    'ASMFramePhaseCorrectionReliableFrames', ...
    'ASMFramePhaseCorrectionHoldoverFrames', ...
    'BERInsideBPSHold','BERRecoveryAfterBPSHold','BEROutsideBPSHold', ...
    'BPSHoldFrames','BPSRecoveryFrames','BPSOutsideFrames','Status'};
displayFields = displayFields(ismember(displayFields,T.Properties.VariableNames));
disp(T(:,displayFields));

comparisonFile = fullfile(runRoot,'std7_16qam_asm_phase_ab.csv');
writetable(T,comparisonFile);
fprintf('\nA/B comparison CSV: %s\n',comparisonFile);
