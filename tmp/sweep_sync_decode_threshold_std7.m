dbclear all;
rehash;

addpath('E:/web_code/react/fft_project/react-fft/src/python');

clear run_ccsds_tm_evaluation ...
      HelperGMSKSecondOrderPLL ...
      HelperTMComplexGainTracker ...
      HelperTMFeedforwardBlindPhaseSearch ...
      HelperTMAPSKPilotlessFrontEnd;

assert(exist('p','var') == 1,'当前工作区没有 p');

%% =========================================================
% STD7 + LDPC
% 同步门限 / 译码门限 SNR Sweep
%
% 固定：
%   H channel
%   TX净增益 +10 dB
%   RX +50 dB
%   LDPC 1/2
%
% Sweep：
%   Noise PSD
%
% 输出：
%   EqSNR -> LockRate
%   EqSNR -> BER / FER
%   同步门限
%   译码门限
%   零误码门限
%   对应 -155 dBm/Hz 噪声下所需 TX 净增益
%% =========================================================

mods = { ...
    'QPSK', ...
    '16QAM', ...
    '32QAM', ...
    '16APSK', ...
    '32APSK'};

chName = 'STD7';
chFile = 'E:/matlab_project/v3.0/v3.0/channel/ChannelData_7.mat';

%% =========================================================
% Sweep 参数
%% =========================================================

% 从信号好 -> 信号差
noisePSDList = -170:2:-140;

% 当前程序自动得到的带宽一直是 13.5 MHz
% 这里显式固定，便于 EqSNR 精确计算
noiseBW = 13.5e6;

%% ---------- 门限定义 ----------

SYNC_LOCK_MIN = 0.99;

DECODE_LOCK_MIN = 0.99;
DECODE_BER_MAX  = 1e-5;
DECODE_FER_MAX  = 0.02;

MIN_COUNTED_FRAMES = 50;

%% ---------- 参考条件 ----------
% 最后会计算：
% 如果噪声 PSD 固定在 -155 dBm/Hz，
% 为达到门限需要多少 TX 净增益

REF_NOISE_PSD_DBMHZ = -155;

%% =========================================================
% Result allocation
%% =========================================================

Nmod = numel(mods);
Npsd = numel(noisePSDList);
N    = Nmod * Npsd;

ModType          = strings(N,1);
NoisePSD_dBmHz   = nan(N,1);
NoisePower_dBm   = nan(N,1);

EqSNR_dB         = nan(N,1);

LockRate         = nan(N,1);
LockPct          = nan(N,1);

BER              = nan(N,1);
FER              = nan(N,1);

CountedFrames    = nan(N,1);
FrameErrors      = nan(N,1);
AcquisitionFrames = nan(N,1);

HGain_dB         = nan(N,1);

Status           = strings(N,1);

row = 0;

%% =========================================================
% SWEEP
%% =========================================================

for k = 1:Nmod

    fprintf('\n\n');
    fprintf('########################################################\n');
    fprintf(' MODULATION: %s\n',mods{k});
    fprintf(' CHANNEL   : %s\n',chName);
    fprintf('########################################################\n');

    for ip = 1:Npsd

        row = row + 1;

        psd = noisePSDList(ip);

        q = p;

        if isfield(q,'QAMPowerGainTracker')
            q = rmfield(q,'QAMPowerGainTracker');
        end

        %% =================================================
        % Modulation + LDPC
        %% =================================================

        q.modType = mods{k};

        q.channelCoding = 'LDPC';
        q.CodeRate = '1/2';
        q.NumBitsInInformationBlock = 1024;
        q.LDPCMaxIterations = 50;
        q.IsLDPCOnSMTF = false;

        %% =================================================
        % H channel
        %% =================================================

        q.enableHChannel = true;
        q.HMode = 'h_matrix_file';

        q.channelFilePath = chFile;

        q.normalizeHChannel = false;
        q.channelInterpolationMethod = 'linear';
        q.channelOutOfRangeMode = 'wrap';
        q.interpolateChannelDelays = false;

        %% =================================================
        % Noise
        %% =================================================

        q.noiseMode = 'psd';

        q.noisePSDdBmHz = psd;

        % 显式使用当前程序实际采用的 13.5 MHz
        q.noiseBandwidthHz = noiseBW;

        q.noisePlacement = 'afterChannel';

        %% =================================================
        % Converter
        %% =================================================

        q.enableConverterChain = true;

        q.inputLevelDbm = -10;

        % ★ TX净增益仍然保持 +10 dB
        q.upconverterFixedGainDB = 31;
        q.upconverterAttenuationDB = 21;

        % RX +50 dB
        q.downconverterFixedGainDB = 50;
        q.downconverterAttenuationDB = 0;

        q.downconverterAutoAttenuation = false;
        q.enableADCEquivalent = false;

        %% =================================================
        % AGC
        %% =================================================

        q.AGCEnabled = true;
        q.AGCUseTransmitReference = false;

        q.AGCTargetSignalPower = 10^(-18/10);

        q.AGCMinGainDB = -40;
        q.AGCMaxGainDB = 40;
        q.AGCTimeConstantMs = 1;

        %% =================================================
        % Receiver
        %% =================================================

        q.enableEqualizer = true;
        q.equalizerMode = 'blind-cma-lms';
        q.normalizeEqualizerOutput = true;

        q.enableQAMBlindPhaseSearch = true;
        q.enableQAMPowerGainTracker = true;
        q.enableQAMPostBPSAdaptiveEqualizer = false;

        q.enableASMFramePhaseCorrection = true;
        q.enableBlindReliabilityManager = true;

        q.APSKReceiverMode = 'pilotless';
        q.HasTMAPSKPilots = false;

        %% =================================================
        % Length
        %% =================================================

        q.berWarmUpFrames = 8;
        q.berFrames = 82;
        q.excludeBERWarmUpFrames = true;

        q.DataPathMode = 'single';

        %% =================================================
        % Debug OFF
        %% =================================================

        q.showFigures = false;
        q.showPipelineFigure = false;
        q.showDamageBudgetFigure = false;
        q.showPowerFigure = false;

        q.debugConverterChain = false;
        q.debugAGC = false;
        q.debugAdaptiveEqualizer = false;
        q.debugASMPhase = false;
        q.debugHFrameStats = false;

        q.debugPerFrameBERCount = 0;
        q.debugPerFrameBERSummary = false;

        %% =================================================
        % Run
        %% =================================================

        fprintf('\n-------------------------------------------------\n');
        fprintf('[%03d/%03d] %-8s | PSD=%7.1f dBm/Hz\n', ...
            row,N,mods{k},psd);
        fprintf('-------------------------------------------------\n');

        % 每个 SNR 点使用同一个噪声序列，仅改变噪声幅度
        % 更适合看门限转折
        rng(364232726,'twister');

        try

            [r,~] = run_ccsds_tm_evaluation(q);

            %% ---------- 基本结果 ----------

            ModType(row) = string(mods{k});

            NoisePSD_dBmHz(row) = psd;

            NoisePower_dBm(row) = ...
                psd + 10*log10(noiseBW);

            BER(row) = r.BER;

            if isfield(r,'FER')
                FER(row) = r.FER;
            end

            LockRate(row) = r.LockRate;
            LockPct(row)  = 100*r.LockRate;

            if isfield(r,'CountedFrames')
                CountedFrames(row) = r.CountedFrames;
            end

            if isfield(r,'FrameErrors')
                FrameErrors(row) = r.FrameErrors;
            end

            if isfield(r,'AcquisitionFrames')
                AcquisitionFrames(row) = ...
                    r.AcquisitionFrames;
            end

            if isfield(r,'HGain_dB')
                HGain_dB(row) = r.HGain_dB;
            end

            %% =================================================
            % EqSNR
            %
            % TX输出：
            % -10 + 31 - 21 = 0 dBm
            %
            % H后信号：
            % 0 + HGain
            %
            % EqSNR：
            % H后信号 - 带内噪声
            %% =================================================

            txNetGain_dB = ...
                q.upconverterFixedGainDB ...
                - q.upconverterAttenuationDB;

            signalBeforeH_dBm = ...
                q.inputLevelDbm + txNetGain_dB;

            signalAfterH_dBm = ...
                signalBeforeH_dBm + HGain_dB(row);

            EqSNR_dB(row) = ...
                signalAfterH_dBm ...
                - NoisePower_dBm(row);

            %% ---------- 分类 ----------

            syncOK = ...
                isfinite(LockRate(row)) && ...
                LockRate(row) >= SYNC_LOCK_MIN;

            decodeOK = ...
                syncOK && ...
                isfinite(BER(row)) && ...
                isfinite(FER(row)) && ...
                BER(row) <= DECODE_BER_MAX && ...
                FER(row) <= DECODE_FER_MAX && ...
                CountedFrames(row) >= MIN_COUNTED_FRAMES;

            zeroErrorOK = ...
                syncOK && ...
                BER(row) == 0 && ...
                FER(row) == 0 && ...
                CountedFrames(row) >= MIN_COUNTED_FRAMES;

            if zeroErrorOK
                Status(row) = "ZERO_ERROR";

            elseif decodeOK
                Status(row) = "DECODE_OK";

            elseif syncOK
                Status(row) = "SYNC_ONLY";

            else
                Status(row) = "NO_SYNC";
            end

            fprintf( ...
                'EqSNR=%6.2f dB | Lock=%6.2f%% | BER=%9.3g | FER=%8.3g | Frames=%g | %s\n', ...
                EqSNR_dB(row), ...
                LockPct(row), ...
                BER(row), ...
                FER(row), ...
                CountedFrames(row), ...
                Status(row));

        catch ME

            ModType(row) = string(mods{k});
            NoisePSD_dBmHz(row) = psd;

            Status(row) = "ERROR";

            fprintf(2,'ERROR: %s\n',ME.message);

        end
    end
end

%% =========================================================
% RAW TABLE
%% =========================================================

T = table( ...
    ModType, ...
    NoisePSD_dBmHz, ...
    NoisePower_dBm, ...
    EqSNR_dB, ...
    LockPct, ...
    BER, ...
    FER, ...
    CountedFrames, ...
    FrameErrors, ...
    AcquisitionFrames, ...
    HGain_dB, ...
    Status);

T = sortrows(T,{'ModType','EqSNR_dB'}, ...
    {'ascend','ascend'});

fprintf('\n\n');
fprintf('=========================================================\n');
fprintf(' RAW SYNC / DECODE THRESHOLD SWEEP\n');
fprintf('=========================================================\n');

disp(T);

%% =========================================================
% THRESHOLD SUMMARY
%% =========================================================

SummaryMod = strings(Nmod,1);

SyncThreshold_EqSNR_dB = nan(Nmod,1);
SyncThreshold_NoisePSD = nan(Nmod,1);

DecodeThreshold_EqSNR_dB = nan(Nmod,1);
DecodeThreshold_NoisePSD = nan(Nmod,1);

ZeroErrorThreshold_EqSNR_dB = nan(Nmod,1);
ZeroErrorThreshold_NoisePSD = nan(Nmod,1);

RequiredTXNetGain_Sync_dB = nan(Nmod,1);
RequiredTXNetGain_Decode_dB = nan(Nmod,1);
RequiredTXNetGain_Zero_dB = nan(Nmod,1);

refNoisePower_dBm = ...
    REF_NOISE_PSD_DBMHZ + 10*log10(noiseBW);

for k = 1:Nmod

    m = string(mods{k});

    SummaryMod(k) = m;

    S = T(T.ModType == m,:);

    % S 已按照 EqSNR 从低到高排序
    S = sortrows(S,'EqSNR_dB','ascend');

    %% ---------- Sync threshold ----------

    syncMask = ...
        S.LockPct >= 100*SYNC_LOCK_MIN;

    idx = find(syncMask,1,'first');

    if ~isempty(idx)

        SyncThreshold_EqSNR_dB(k) = ...
            S.EqSNR_dB(idx);

        SyncThreshold_NoisePSD(k) = ...
            S.NoisePSD_dBmHz(idx);
    end

    %% ---------- Decode threshold ----------

    decodeMask = ...
        S.LockPct >= 100*DECODE_LOCK_MIN & ...
        S.BER <= DECODE_BER_MAX & ...
        S.FER <= DECODE_FER_MAX & ...
        S.CountedFrames >= MIN_COUNTED_FRAMES;

    idx = find(decodeMask,1,'first');

    if ~isempty(idx)

        DecodeThreshold_EqSNR_dB(k) = ...
            S.EqSNR_dB(idx);

        DecodeThreshold_NoisePSD(k) = ...
            S.NoisePSD_dBmHz(idx);
    end

    %% ---------- Zero-error threshold ----------

    zeroMask = ...
        S.LockPct >= 100*DECODE_LOCK_MIN & ...
        S.BER == 0 & ...
        S.FER == 0 & ...
        S.CountedFrames >= MIN_COUNTED_FRAMES;

    idx = find(zeroMask,1,'first');

    if ~isempty(idx)

        ZeroErrorThreshold_EqSNR_dB(k) = ...
            S.EqSNR_dB(idx);

        ZeroErrorThreshold_NoisePSD(k) = ...
            S.NoisePSD_dBmHz(idx);
    end

    %% =====================================================
    % 在固定 PSD=-155 dBm/Hz 时，
    % 达到这些门限理论上需要多少 TX 净增益
    %
    % EqSNR =
    % inputLevel + TXnetGain + HGain - NoisePower
    %
    % TXnetGain =
    % EqSNR - inputLevel - HGain + NoisePower
    %% =====================================================

    Hmed = median(S.HGain_dB,'omitnan');

    inputLevel = -10;

    if isfinite(SyncThreshold_EqSNR_dB(k))

        RequiredTXNetGain_Sync_dB(k) = ...
            SyncThreshold_EqSNR_dB(k) ...
            - inputLevel ...
            - Hmed ...
            + refNoisePower_dBm;
    end

    if isfinite(DecodeThreshold_EqSNR_dB(k))

        RequiredTXNetGain_Decode_dB(k) = ...
            DecodeThreshold_EqSNR_dB(k) ...
            - inputLevel ...
            - Hmed ...
            + refNoisePower_dBm;
    end

    if isfinite(ZeroErrorThreshold_EqSNR_dB(k))

        RequiredTXNetGain_Zero_dB(k) = ...
            ZeroErrorThreshold_EqSNR_dB(k) ...
            - inputLevel ...
            - Hmed ...
            + refNoisePower_dBm;
    end
end

ThresholdSummary = table( ...
    SummaryMod, ...
    SyncThreshold_EqSNR_dB, ...
    SyncThreshold_NoisePSD, ...
    DecodeThreshold_EqSNR_dB, ...
    DecodeThreshold_NoisePSD, ...
    ZeroErrorThreshold_EqSNR_dB, ...
    ZeroErrorThreshold_NoisePSD, ...
    RequiredTXNetGain_Sync_dB, ...
    RequiredTXNetGain_Decode_dB, ...
    RequiredTXNetGain_Zero_dB);

fprintf('\n\n');
fprintf('=========================================================\n');
fprintf(' THRESHOLD SUMMARY | %s\n',chName);
fprintf('=========================================================\n');

disp(ThresholdSummary);

%% =========================================================
% Save
%% =========================================================

writetable(T, ...
    'STD7_sync_decode_threshold_raw.csv');

writetable(ThresholdSummary, ...
    'STD7_sync_decode_threshold_summary.csv');

%% =========================================================
% Plot 1: Synchronization threshold
%% =========================================================

figure;
hold on;
grid on;

for k = 1:Nmod

    S = T(T.ModType == string(mods{k}),:);
    S = sortrows(S,'EqSNR_dB');

    plot( ...
        S.EqSNR_dB, ...
        S.LockPct, ...
        '-o', ...
        'DisplayName',mods{k});
end

yline(100*SYNC_LOCK_MIN,'--');

xlabel('EqSNR (dB)');
ylabel('Frame Lock (%)');

title('STD7 Synchronization Threshold');

legend('Location','best');

%% =========================================================
% Plot 2: BER threshold
%% =========================================================

figure;
hold on;
grid on;

for k = 1:Nmod

    S = T(T.ModType == string(mods{k}),:);
    S = sortrows(S,'EqSNR_dB');

    berPlot = S.BER;

    % BER=0 时为了 log 图显示
    berPlot(berPlot == 0) = 1e-8;

    semilogy( ...
        S.EqSNR_dB, ...
        berPlot, ...
        '-o', ...
        'DisplayName',mods{k});
end

yline(DECODE_BER_MAX,'--');

xlabel('EqSNR (dB)');
ylabel('BER');

title('STD7 LDPC Decoding BER Threshold');

legend('Location','best');

%% =========================================================
% Plot 3: FER threshold
%% =========================================================

figure;
hold on;
grid on;

for k = 1:Nmod

    S = T(T.ModType == string(mods{k}),:);
    S = sortrows(S,'EqSNR_dB');

    ferPlot = S.FER;

    ferPlot(ferPlot == 0) = 1e-3;

    semilogy( ...
        S.EqSNR_dB, ...
        ferPlot, ...
        '-o', ...
        'DisplayName',mods{k});
end

yline(DECODE_FER_MAX,'--');

xlabel('EqSNR (dB)');
ylabel('FER');

title('STD7 LDPC Decoding FER Threshold');

legend('Location','best');