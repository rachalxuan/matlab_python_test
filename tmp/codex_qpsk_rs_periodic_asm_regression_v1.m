%% QPSK + RS(255,223) periodic-ASM regression
% Short deterministic regression for the RS frame-alignment route.
% Cases: no H, CDL A2, CDL A3, CDL A4. No artifacts are written.

dbclear all;
rehash;

repoRoot = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(repoRoot,'src','python'));

channelDir = [ ...
    'C:/Users/admin/xwechat_files/wxid_95czmz1vt20422_de63/msg/file/', ...
    '2026-09/mat文件/mat文件'];

caseNames = ["No-H"; "CDL A2"; "CDL A3"; "CDL A4"];
channelFiles = [ ...
    ""
    fullfile(channelDir,'3GPPNTN-CDL_A_2_AntennaGain_1.mat')
    fullfile(channelDir,'3GPPNTN-CDL_A_3_AntennaGain_1.mat')
    fullfile(channelDir,'3GPPNTN-CDL_A_4_AntennaGain_1.mat')
];

nCase = numel(caseNames);
BER = nan(nCase,1);
FER = nan(nCase,1);
CountedFrames = zeros(nCase,1);
FrameErrors = zeros(nCase,1);
FrameLock_pct = nan(nCase,1);
FrameLockedAtEnd = false(nCase,1);
FSEErrorMSE = nan(nCase,1);
EqualizerOutputAccepted = false(nCase,1);
Success = false(nCase,1);
Pass = false(nCase,1);
RSPeriodicASMRegressionLogs = cell(nCase,1);

for iCase = 1:nCase
    p = struct();
    p.modType = 'QPSK';
    p.channelCoding = 'RS';
    p.RSMessageLength = 223;
    p.RSInterleavingDepth = 1;
    p.IsRSMessageShortened = false;
    p.NumBytesInTransferFrame = 223;

    p.symbolRate = 30e6;
    p.sps = 8;
    p.RolloffFactor = 0.35;
    p.snr = 100;
    p.noiseMode = 'off';
    p.noisePlacement = 'afterChannel';
    p.cfo = 0;
    p.phaseOffset = 0;
    p.delay = 0;

    p.WaveformMode = 'ordinaryTM';
    p.hasASM = true;
    p.RandomizerEnabled = false;
    p.RandomizerFECPosition = 'afterEncoding';
    p.DataPathMode = 'single';
    p.TMDataSource = 'random';
    p.PCMFormat = 'NRZ-L';

    % A3 needs more absolute acquisition symbols than eight short RS
    % frames provide. Keep this regression short but outside that known
    % equalizer transient.
    p.berWarmUpFrames = 16;
    p.berFrames = 16;
    p.excludeBERWarmUpFrames = true;

    p.enableEqualizer = true;
    p.equalizerMode = 'blind-cma-lms';
    p.normalizeEqualizerOutput = true;
    p.enableKnownHPreEqualizer = false;
    p.enableQAMBlindPhaseSearch = true;
    p.enableASMFramePhaseCorrection = true;
    p.adaptiveEqualizerSamplingMode = '2sps';
    p.adaptiveFractionalEqualizerTaps = 129;
    p.adaptiveFractionalEqualizerStep = 2e-4;
    p.adaptiveFractionalEqualizerWeightUpdatePeriod = 1;
    p.adaptiveFractionalPostMode = 'off';
    p.timingLoopBandwidth = 0.01;

    p.enableConverterChain = false;
    p.enableADCEquivalent = false;
    p.AGCEnabled = false;
    p.enableRuntimeLockTelemetry = true;
    p.runtimeStatusUpdateMs = 200;

    p.enableHChannel = iCase > 1;
    if p.enableHChannel
        p.HMode = 'h_matrix_file';
        p.channelFilePath = char(channelFiles(iCase));
        p.channelPathPowerMode = 'embedded';
        p.channelSampleRateHz = 1e5;
        p.channelInterpolationMethod = 'linear';
        p.channelOutOfRangeMode = 'hold';
        p.interpolateChannelDelays = true;
        p.normalizeHChannel = true;
    end

    p.showFigures = false;
    p.showPipelineFigure = false;
    p.showDamageBudgetFigure = false;
    p.showPowerFigure = false;
    p.debugAdaptiveEqualizer = false;
    p.debugCodedBoundary = false;

    fprintf('[RS periodic ASM regression %d/%d] %s ...\n', ...
        iCase,nCase,caseNames(iCase));
    rng(364232726,'twister');
    r = struct();
    RSPeriodicASMRegressionLogs{iCase} = evalc( ...
        '[r,~] = run_ccsds_tm_evaluation(p);');

    Success(iCase) = isfield(r,'success') && logical(r.success);
    if Success(iCase)
        BER(iCase) = r.BER;
        FER(iCase) = r.FER;
        CountedFrames(iCase) = r.CountedFrames;
        FrameErrors(iCase) = r.FrameErrors;
        FSEErrorMSE(iCase) = r.AdaptiveFractionalEqualizerErrorMSE;
        EqualizerOutputAccepted(iCase) = ...
            logical(r.AdaptiveEqualizerOutputAccepted);
        if isfield(r,'RuntimeLockTelemetry') && ...
                isfield(r.RuntimeLockTelemetry,'Frame') && ...
                r.RuntimeLockTelemetry.Frame.Available
            FrameLock_pct(iCase) = ...
                100*r.RuntimeLockTelemetry.Frame.LockRate;
            FrameLockedAtEnd(iCase) = ...
                logical(r.RuntimeLockTelemetry.Frame.LockedAtEnd);
        end
    end

    Pass(iCase) = Success(iCase) && CountedFrames(iCase) > 0 && ...
        BER(iCase) == 0 && FER(iCase) == 0 && ...
        FrameLockedAtEnd(iCase);
    fprintf('  BER=%g FER=%g frames=%d frameLock=%.2f%% end=%d pass=%d\n', ...
        BER(iCase),FER(iCase),CountedFrames(iCase), ...
        FrameLock_pct(iCase),FrameLockedAtEnd(iCase),Pass(iCase));
end

RSPeriodicASMRegressionResults = table( ...
    caseNames,Success,BER,FER,CountedFrames,FrameErrors, ...
    FSEErrorMSE,EqualizerOutputAccepted,FrameLock_pct, ...
    FrameLockedAtEnd,Pass, ...
    'VariableNames',{'CaseName','Success','BER','FER', ...
    'CountedFrames','FrameErrors','FSEErrorMSE', ...
    'EqualizerOutputAccepted','FrameLock_pct', ...
    'FrameLockedAtEnd','Pass'});

fprintf('\n================ QPSK + RS PERIODIC ASM REGRESSION ================\n');
disp(RSPeriodicASMRegressionResults);

assert(all(Pass), ...
    'QPSK+RS periodic-ASM regression failed. Inspect RSPeriodicASMRegressionLogs.');
fprintf('PASS: no-H and CDL A2/A3/A4 all decoded with final frame lock.\n');
