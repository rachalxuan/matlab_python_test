% Focused, exact-noise-free tau sweep for the normalized std7 16QAM case.
% This script calls the evaluator directly: it does not create regression
% checkpoints, CSV files, MAT files, figures, or artifact directories.
clearvars; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python');
dbclear all;

p = struct();
p.modType = '16QAM';
p.channelCoding = 'none';
p.symbolRate = 10e6;
p.sps = 8;
p.snr = 100;
p.noiseMode = 'off';
p.noisePlacement = 'afterChannel';
p.cfo = 0;
p.phaseOffset = 0;
p.delay = 0;
p.RolloffFactor = 0.35;

p.WaveformMode = 'ordinaryTM';
p.NumBytesInTransferFrame = 1115;
p.hasASM = true;
p.RandomizerEnabled = false;
p.RandomizerFECPosition = 'afterEncoding';
p.DataPathMode = 'single';
p.TMDataSource = 'random';

p.berWarmUpFrames = 8;
p.berFrames = 60;
p.excludeBERWarmUpFrames = true;

p.enableHChannel = true;
p.HMode = 'h_matrix_file';
p.channelFilePath = ...
    'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat';
p.channelInterpolationMethod = 'linear';
p.channelOutOfRangeMode = 'wrap';
p.interpolateChannelDelays = false;
p.normalizeHChannel = true;

p.enableEqualizer = true;
p.equalizerMode = 'blind-cma-lms';
p.normalizeEqualizerOutput = true;
p.timingLoopBandwidth = 0.01;

p.enableQAMBlindPhaseSearch = true;
p.enableQAMPowerGainTracker = true;
p.enableQAMPostBPSAdaptiveEqualizer = false;
p.enableASMFramePhaseCorrection = true;

p.enableBlindReliabilityManager = true;
p.blindReliabilityWindowSymbols = 32;
p.blindReliabilityAcquireSymbols = 256;
p.blindReliabilityReferenceTauSymbols = 4096;
p.blindReliabilityFadeEnterDB = -12;
p.blindReliabilityFadeExitDB = -8;
p.blindReliabilityFadeEnterWindows = 2;
p.blindReliabilityRecoverWindows = 4;
p.blindReliabilityMaxInverseGainDB = 30;

p.QAMPowerGainTracker = struct( ...
    'MagnitudeEstimationMode','power', ...
    'TrackPowerMagnitudeDuringFade',true, ...
    'FadePowerTauSymbols',128, ... % Replaced inside the loop.
    'UpdatePowerReference',false, ...
    'MaxInverseGainDB',30, ...
    'Regularization',0, ...
    'TrackMagnitude',true, ...
    'TrackPhase',false);

p.inputLevelDbm = -10;
p.AGCEnabled = false;
p.debugCodedBoundary = true;
p.collectPredecoderStats = true;
p.predecoderMaxOffsetBits = 32;
% Print every nonzero steady predecoder frame into the captured in-memory
% log, so frame 67 is not hidden when errors spread to several frames.
p.debugPredecoderMaxBurstFrames = 100;
p.debugQAMBPSFadeBER = true;
p.debugAdaptiveEqualizer = true;
p.debugASMPhase = false;
p.debugHFrameStats = false;
p.debugFrameCheck = false;
p.showFigures = false;
p.showPipelineFigure = false;
p.showDamageBudgetFigure = false;
p.showPowerFigure = false;

tauSymbols = [16; 32; 64; 128; 256];
pairedSeed = 364232726;
nCases = numel(tauSymbols);

BER = nan(nCases,1);
FER = nan(nCases,1);
PredecoderSteadyBER = nan(nCases,1);
PredecoderSteadyBitErrors = nan(nCases,1);
BPSHoldBER = nan(nCases,1);
BPSHoldBitErrors = nan(nCases,1);
BPSRecoveryBER = nan(nCases,1);
BPSOutsideBER = nan(nCases,1);
Frame67ErrorBits = nan(nCases,1);
InverseGainMax_dB = nan(nCases,1);
GainAcceptance_pct = nan(nCases,1);
EVM_post_pct = nan(nCases,1);
MER_dB = nan(nCases,1);
Elapsed_s = nan(nCases,1);
TauSweepLogs = cell(nCases,1);

for iCase = 1:nCases
    tau = tauSymbols(iCase);
    p.QAMPowerGainTracker.FadePowerTauSymbols = tau;

    % Reset inside the loop.  Resetting once before the loop would give
    % every tau a different transmitted data realization.
    rng(pairedSeed,'twister');
    fprintf('\n[tau sweep %d/%d] FadePowerTauSymbols=%d ...\n', ...
        iCase,nCases,tau);
    caseTimer = tic;
    runLog = evalc('[runResult,~] = run_ccsds_tm_evaluation(p);');
    Elapsed_s(iCase) = toc(caseTimer);
    TauSweepLogs{iCase} = runLog;

    BER(iCase) = runResult.BER;
    FER(iCase) = runResult.FER;
    PredecoderSteadyBER(iCase) = runResult.PredecoderSteadyBER;
    PredecoderSteadyBitErrors(iCase) = ...
        runResult.PredecoderSteadyBitErrors;
    BPSHoldBER(iCase) = runResult.BERInsideBPSHold;
    BPSHoldBitErrors(iCase) = runResult.BPSHoldBitErrors;
    BPSRecoveryBER(iCase) = runResult.BERRecoveryAfterBPSHold;
    BPSOutsideBER(iCase) = runResult.BEROutsideBPSHold;
    InverseGainMax_dB(iCase) = ...
        runResult.QAMPowerGainInverseMaxObserved_dB;
    GainAcceptance_pct(iCase) = ...
        100*runResult.QAMPowerGainAcceptanceRate;
    EVM_post_pct(iCase) = runResult.EVM_post_pct;
    MER_dB(iCase) = runResult.MER_dB;

    % Restrict parsing to the correctly ASM-aligned predecoder diagnostic.
    % A wrong phase candidate can contain thousands of errors in frame 67;
    % treating that line as the selected result would invalidate the sweep.
    alignedSections = regexp(runLog, ...
        ['(?s)\[Coded DEBUG\] demod-vs-encoded \(16QAM\): ', ...
         'ASMAligned=1.*?(?=\[Coded DEBUG\] demod soft)'], ...
        'match');
    frame67Errors = [];
    for iSection = 1:numel(alignedSections)
        tokens = regexp(alignedSections{iSection}, ...
            'rxFrame=067\s+txFrame=\s*\d+\s+err=\s*(\d+)', ...
            'tokens');
        for iToken = 1:numel(tokens)
            frame67Errors(end+1,1) = ... %#ok<SAGROW>
                str2double(tokens{iToken}{1});
        end
    end
    if isempty(alignedSections)
        % Do not silently turn a failed diagnostic alignment into a
        % seemingly perfect frame.
        Frame67ErrorBits(iCase) = NaN;
    elseif isempty(frame67Errors)
        % Burst debug prints only nonzero frames.  Absence in the verified
        % ASM-aligned section therefore means zero errors in frame 67.
        Frame67ErrorBits(iCase) = 0;
    else
        Frame67ErrorBits(iCase) = min(frame67Errors);
    end

    fprintf(['  BER=%.6g | steady=%g bits | frame67=%g bits | ', ...
        'BPS-HOLD BER=%.6g | invMax=%+.3f dB | %.2f s\n'], ...
        BER(iCase),PredecoderSteadyBitErrors(iCase), ...
        Frame67ErrorBits(iCase),BPSHoldBER(iCase), ...
        InverseGainMax_dB(iCase),Elapsed_s(iCase));
end

Tau_us = tauSymbols/p.symbolRate*1e6;
TauSweepResults = table( ...
    tauSymbols,Tau_us,BER,FER, ...
    PredecoderSteadyBER,PredecoderSteadyBitErrors, ...
    Frame67ErrorBits,BPSHoldBER,BPSHoldBitErrors, ...
    BPSRecoveryBER,BPSOutsideBER,InverseGainMax_dB, ...
    GainAcceptance_pct,EVM_post_pct,MER_dB,Elapsed_s, ...
    'VariableNames',{ ...
    'TauSymbols','Tau_us','BER','FER', ...
    'PredecoderSteadyBER','PredecoderSteadyBitErrors', ...
    'Frame67ErrorBits','BPSHoldBER','BPSHoldBitErrors', ...
    'BPSRecoveryBER','BPSOutsideBER','InverseGainMax_dB', ...
    'GainAcceptance_pct','EVM_post_pct','MER_dB','Elapsed_s'});

fprintf('\n=== 16QAM normalized-std7 noiseless tau sweep ===\n');
disp(TauSweepResults);
fprintf(['BPSHoldBER is classified by receiver BPS HOLD, not by an ', ...
    'oracle threshold on the true |H|.\n']);
fprintf(['Results remain in TauSweepResults; full captured logs remain ', ...
    'in TauSweepLogs. Nothing was written to artifacts.\n']);
