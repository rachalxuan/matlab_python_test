function [T,details] = test_apsk_pilotless_receiver_v4(phaseListDeg)
%TEST_APSK_PILOTLESS_RECEIVER_V4  Pilotless 32APSK fixed-phase sweep.
%
%   T = test_apsk_pilotless_receiver_v4()
%   T = test_apsk_pilotless_receiver_v4([0 30 60 100 170])
%   [T,details] = test_apsk_pilotless_receiver_v4(...)
%
% Purpose
%   Stage-3 regression of the isolated, no-pilot APSK receiver:
%
%     ccsdsTMWaveformGenerator
%       -> fixed phase impairment (No H, No AWGN, CFO=0)
%       -> SRRC matched filter
%       -> Gardner timing
%       -> HelperTMAPSKCarrierRecovery (NDA + gated DD PLL)
%       -> HelperTMAPSKASMResolver (0/90/180/270 ambiguity + bit phase)
%       -> APSK demod
%       -> TX-truth BER verification ONLY
%
% The receiver does NOT use txEncodedBits for carrier/ASM decisions.
% All phase cases reuse the SAME transmitted waveform and bits, so the sweep
% is a paired A/B comparison.
%
% Final command-window output is one summary table with:
%   Phase / NDA CFO / DD accept / ASM rot / ASM gap / EVM / BER / PASS
%
% Notes
%   - This Stage-3 file intentionally keeps H=OFF, AWGN=OFF, CFO=0.
%   - 10 frames are excluded from steady BER/EVM to cover acquisition.
%   - If a case throws an error, the row is marked FAIL and the error text is
%     stored in details(k).ErrorMessage.

if nargin < 1 || isempty(phaseListDeg)
    phaseListDeg = [0 30 60 100 170];
end
phaseListDeg = double(phaseListDeg(:).');

addpath('E:/web_code/react/fft_project/react-fft/src/python');
rng(20260819,'twister');

%% ========================================================================
% Shared configuration
% =========================================================================
cfg = struct();
cfg.ModType = '16APSK';
cfg.Rs = 10e6;
cfg.SPS = 8;
cfg.Fs = cfg.Rs*cfg.SPS;
cfg.Rolloff = 0.35;
cfg.FilterSpan = 10;
cfg.NumFrames = 60;
cfg.NumBytesInTransferFrame = 1115;
cfg.BERWarmUpFrames = 10;
cfg.TestCFOHz = 0;
cfg.TestSNRdB = Inf;
cfg.UsePilots = false;

% Carrier-recovery options -- exactly the Stage-2 baseline.
cfg.CROpt = struct();
cfg.CROpt.SymbolRateHz = cfg.Rs;
cfg.CROpt.NormalizeInputPower = true;
cfg.CROpt.AcquisitionSymbols = 4096;
cfg.CROpt.AcquisitionBlockSymbols = 16;
cfg.CROpt.AcquisitionPhaseGridSize = 181;
cfg.CROpt.AcquisitionTrimFraction = 0.10;
cfg.CROpt.MaxAcquisitionCFOHz = 200e3;
cfg.CROpt.RequireAcquisitionQualification = true;
cfg.CROpt.DDLoopBandwidth = 0.002;
cfg.CROpt.DampingFactor = 1/sqrt(2);
cfg.CROpt.DecisionGate = NaN;
cfg.CROpt.DecisionMarginMin = 0.12;
cfg.CROpt.MaxPhaseErrorRad = pi/5;
cfg.CROpt.MaxResidualCFOHz = 100e3;
cfg.CROpt.HoldEnterBadSymbols = 4;
cfg.CROpt.RecoverGoodSymbols = 8;
cfg.CROpt.EnableFadeHold = true;
cfg.CROpt.FadePowerTauSymbols = 64;
cfg.CROpt.FadeEnterDB = -10;
cfg.CROpt.FadeExitDB = -6;
cfg.CROpt.Debug = false;

% ASM ambiguity resolver -- same policy as Stage 2.
cfg.ASMOpt = struct();
cfg.ASMOpt.ChannelCoding = 'none';
cfg.ASMOpt.PCMFormat = 'NRZ-L';
cfg.ASMOpt.NumBytesInTransferFrame = cfg.NumBytesInTransferFrame;
cfg.ASMOpt.ASMHex = '1ACFFC1D';
cfg.ASMOpt.DemodNoiseVariance = 0.01;
cfg.ASMOpt.MaxSearchBits = 250000;
cfg.ASMOpt.ASMMaxErr = 6;
cfg.ASMOpt.ASMMinScoreGap = 4;
cfg.ASMOpt.PeriodicCandidates = 32;
cfg.ASMOpt.PeriodicFrames = 8;
cfg.ASMOpt.ASMErrMargin = 4;
cfg.ASMOpt.AllowASMInversion = true;
cfg.ASMOpt.RequireQualification = true;
cfg.ASMOpt.Debug = false;

% Stage-3 pass criteria.  These are intentionally strict because H/AWGN are off.
cfg.MinDDAcceptance = 0.95;
cfg.MaxSteadyEVM_pct = 2.0;
cfg.MaxSteadyBER = 1e-5;
cfg.MaxPhaseErrorRMS_deg = 1.5;

%% ========================================================================
% Generate ONE common transmitted waveform for every phase case
% =========================================================================
tmWaveGen = ccsdsTMWaveformGenerator( ...
    'WaveformSource','synchronization and channel coding', ...
    'NumBytesInTransferFrame',cfg.NumBytesInTransferFrame, ...
    'RandomizerEnabled',false, ...
    'RandomizerFECPosition','afterEncoding', ...
    'DataPathMode','single', ...
    'HasASM',true, ...
    'ChannelCoding','none', ...
    'Modulation',cfg.ModType, ...
    'RolloffFactor',cfg.Rolloff, ...
    'FilterSpanInSymbols',cfg.FilterSpan, ...
    'SamplesPerSymbol',cfg.SPS, ...
    'HasTMAPSKPilots',cfg.UsePilots);

bitsPerCall = tmWaveGen.NumInputBits;
txInputBits = int8(randi([0 1],bitsPerCall*cfg.NumFrames,1));

% Capture generator chatter so the sweep ends with one compact table.
evalc('[txWaveform,txEncodedBits] = tmWaveGen(txInputBits);');
txWaveform = complex(txWaveform(:));
txEncodedBits = int8(txEncodedBits(:) ~= 0);

%% ========================================================================
% Phase sweep
% =========================================================================
nCase = numel(phaseListDeg);
rows = repmat(struct( ...
    'Phase_deg',NaN, ...
    'NDA_CFO_Hz',NaN, ...
    'DD_Accept_pct',NaN, ...
    'ASM_Rot_deg',NaN, ...
    'ASM_Gap',NaN, ...
    'EVM_pct',NaN, ...
    'BER',NaN, ...
    'PASS',false),nCase,1);

details = repmat(localEmptyDetail(),nCase,1);

for k = 1:nCase
    ph = phaseListDeg(k);
    rows(k).Phase_deg = ph;

    try
        d = localRunOneCase(txWaveform,txEncodedBits,ph,cfg);
        details(k) = d;

        rows(k).NDA_CFO_Hz = d.NDA_CFO_Hz;
        rows(k).DD_Accept_pct = d.DD_Accept_pct;
        rows(k).ASM_Rot_deg = d.ASM_Rot_deg;
        rows(k).ASM_Gap = d.ASM_Gap;
        rows(k).EVM_pct = d.EVM_pct;
        rows(k).BER = d.BER;
        rows(k).PASS = d.PASS;
    catch ME
        details(k).Phase_deg = ph;
        details(k).ErrorIdentifier = ME.identifier;
        details(k).ErrorMessage = ME.message;
        rows(k).PASS = false;
    end
end

T = struct2table(rows);

fprintf('\n===============================================================\n');
fprintf(' PILOTLESS 16APSK STAGE-3 FIXED-PHASE SWEEP\n');
fprintf(' No H | No AWGN | CFO=0 | Pilots OFF | warm-up=%d frames\n', ...
    cfg.BERWarmUpFrames);
fprintf('===============================================================\n');
disp(T);

if all(T.PASS)
    fprintf('[PASS-STAGE3] All %d fixed initial phases passed.\n',height(T));
else
    bad = find(~T.PASS);
    fprintf(2,'[FAIL-STAGE3] Failed phase case(s):');
    fprintf(2,' %g',T.Phase_deg(bad));
    fprintf(2,' deg\n');
    fprintf(2,'Inspect details(k).ErrorMessage / acquisition / ASM fields before adding CFO or H.\n');
end

end

%% ========================================================================
% One fixed-phase receiver case
% =========================================================================
function d = localRunOneCase(txWaveform,txEncodedBits,testPhaseDeg,cfg)

Rs = cfg.Rs;
Fs = cfg.Fs;
sps = cfg.SPS;

%% 1) Controlled impairment: phase only
n = (0:numel(txWaveform)-1).';
rx = txWaveform .* exp(1j*(2*pi*cfg.TestCFOHz/Fs*n + deg2rad(testPhaseDeg)));

if isfinite(cfg.TestSNRdB)
    rx = awgn(rx,cfg.TestSNRdB,'measured');
end

%% 2) Matched SRRC
rxFilterDecimationFactor = sps/2;
rxFilter = comm.RaisedCosineReceiveFilter( ...
    'Shape','Square root', ...
    'RolloffFactor',cfg.Rolloff, ...
    'FilterSpanInSymbols',cfg.FilterSpan, ...
    'InputSamplesPerSymbol',sps, ...
    'DecimationFactor',rxFilterDecimationFactor);

nTrim = mod(numel(rx),rxFilterDecimationFactor);
if nTrim ~= 0
    rxForFilter = rx(1:end-nTrim);
else
    rxForFilter = rx;
end
filtered = rxFilter(rxForFilter);
spsAfter = sps/rxFilterDecimationFactor;

%% 3) Gardner NDA timing
Kp = 1/(pi*(1-((cfg.Rolloff^2)/4))) * cos(pi*cfg.Rolloff/2);
timingCfg = struct( ...
    'SamplesPerSymbol',spsAfter, ...
    'DetectorGain',Kp, ...
    'Modulation','PAM/PSK/QAM', ...
    'NormalizedLoopBandwidth',0.005, ...
    'ChunkSizeSamples',50000);

% Capture any diagnostic chatter from the chunked helper.
evalc('[timeSynced,timingInfo] = HelperTMSymbolSynchronizerChunked(filtered,timingCfg);'); %#ok<NASGU>
timeSynced = complex(timeSynced(:));

frameSymbolsApprox = numel(timeSynced)/cfg.NumFrames;

%% 4) Pilotless APSK carrier recovery
crOpt = cfg.CROpt;
crOpt.AcquisitionSymbols = min(crOpt.AcquisitionSymbols,numel(timeSynced));
evalc(['[carrierSynced,carrierState,carrierInfo] = ', ...
    'HelperTMAPSKCarrierRecovery(timeSynced,cfg.ModType,crOpt);']);

if ~carrierInfo.Applied || ~carrierInfo.AcquisitionQualified
    error('APSKStage3:CarrierFailed', ...
        'Phase %+g deg: carrier acquisition failed: %s', ...
        testPhaseDeg,carrierInfo.Reason);
end

%% 5) ASM-based 0/90/180/270 ambiguity + frame bit phase
asmOpt = cfg.ASMOpt;
evalc(['[asmResolved,asmInfo] = ', ...
    'HelperTMAPSKASMResolver(carrierSynced,cfg.ModType,asmOpt);']);

if ~asmInfo.Applied || ~asmInfo.Qualified
    error('APSKStage3:ASMFailed', ...
        'Phase %+g deg: ASM ambiguity resolution failed: %s', ...
        testPhaseDeg,asmInfo.Reason);
end

%% 6) Demodulate selected rotation and apply ASM-derived bit trim
% txEncodedBits is NOT used until after all receiver decisions are complete.
demodObj = HelperCCSDSTMDemodulator( ...
    'Modulation',cfg.ModType, ...
    'ChannelCoding','none', ...
    'PCMFormat','NRZ-L', ...
    'NoiseVariance',0.01);

evalc('softResolved = double(demodObj(asmResolved));');
rxHardRaw = int8(real(softResolved(:)) > 0);

if asmInfo.TrimBits >= numel(rxHardRaw)
    error('APSKStage3:TrimTooLarge', ...
        'Phase %+g deg: ASM TrimBits=%d exceeds RX bit stream.', ...
        testPhaseDeg,asmInfo.TrimBits);
end
rxHardAligned = rxHardRaw(asmInfo.TrimBits+1:end);

%% 7) Steady EVM/MER
refConst = localAPSKReference(cfg.ModType);
refConst = refConst/sqrt(mean(abs(refConst).^2)+eps);

warmupSymbols = min(max(0,numel(asmResolved)-1), ...
    round(cfg.BERWarmUpFrames*frameSymbolsApprox));
if warmupSymbols < numel(asmResolved)
    steadySymbols = asmResolved(warmupSymbols+1:end);
else
    steadySymbols = complex([]);
end
[evmSteady,merSteady] = localNearestEVM(steadySymbols,refConst);

%% 8) TX-truth BER verification ONLY
L = min(numel(rxHardAligned),numel(txEncodedBits));
if L <= 0
    error('APSKStage3:NoBits','No aligned RX bits are available.');
end
rxCheck = rxHardAligned(1:L);
txCheck = txEncodedBits(1:L);

bitsPerReferenceFrame = numel(txEncodedBits)/cfg.NumFrames;
if abs(bitsPerReferenceFrame-round(bitsPerReferenceFrame)) > 1e-9
    error('APSKStage3:FrameLength','Reference stream is not an integer number of frames.');
end
bitsPerReferenceFrame = round(bitsPerReferenceFrame);
warmupBits = cfg.BERWarmUpFrames*bitsPerReferenceFrame;

if warmupBits >= L
    error('APSKStage3:WarmupTooLong','Warm-up removes the complete BER interval.');
end

rxSteady = rxCheck(warmupBits+1:end);
txSteady = txCheck(warmupBits+1:end);
steadyErr = nnz(rxSteady ~= txSteady);
steadyLen = numel(rxSteady);
berSteady = steadyErr/max(1,steadyLen);

%% 9) Strict Stage-3 verdict
selected = asmInfo.SelectedRotationIndex;
isTrack = strcmpi(string(carrierState.Mode),'TRACK');

passFlag = ...
    carrierInfo.AcquisitionQualified && ...
    asmInfo.Qualified && ...
    asmInfo.BestErrors(selected) <= asmOpt.ASMMaxErr && ...
    asmInfo.ScoreGap >= asmOpt.ASMMinScoreGap && ...
    ~logical(asmInfo.SelectedASMInverted) && ...
    carrierInfo.AcceptanceRate >= cfg.MinDDAcceptance && ...
    carrierInfo.PhaseErrorRMS_deg <= cfg.MaxPhaseErrorRMS_deg && ...
    evmSteady <= cfg.MaxSteadyEVM_pct && ...
    berSteady <= cfg.MaxSteadyBER && ...
    isTrack;

%% 10) Return compact + debug fields
d = localEmptyDetail();
d.Phase_deg = testPhaseDeg;
d.NDA_CFO_Hz = carrierInfo.AcquisitionCFO_Hz;
d.DD_Accept_pct = 100*carrierInfo.AcceptanceRate;
d.ASM_Rot_deg = asmInfo.SelectedRotation_deg;
d.ASM_Gap = asmInfo.ScoreGap;
d.EVM_pct = evmSteady;
d.MER_dB = merSteady;
d.BER = berSteady;
d.BERErrors = steadyErr;
d.BERBits = steadyLen;
d.PASS = passFlag;

d.NDAQualified = carrierInfo.AcquisitionQualified;
d.NDA_Phase_deg = carrierInfo.AcquisitionPhase_deg;
d.DD_PhaseErrorRMS_deg = carrierInfo.PhaseErrorRMS_deg;
d.DD_HoldFraction_pct = 100*carrierInfo.HoldFraction;
d.FinalResidualFrequency_Hz = carrierInfo.FinalResidualFrequency_Hz;
d.FinalCarrierState = char(string(carrierState.Mode));

d.ASMQualified = asmInfo.Qualified;
d.ASMBestError = asmInfo.BestErrors(selected);
d.ASMMeanError = asmInfo.MeanErrors(selected);
d.ASMPeriodicFrames = asmInfo.PeriodicFramesByRotation(selected);
d.ASMFirstPosition = asmInfo.FirstASMBitPosition;
d.ASMTrimBits = asmInfo.TrimBits;
d.ASMInverted = asmInfo.SelectedASMInverted;
d.ErrorIdentifier = '';
d.ErrorMessage = '';

end

%% ========================================================================
% Utilities
% =========================================================================
function d = localEmptyDetail()
d = struct( ...
    'Phase_deg',NaN, ...
    'NDA_CFO_Hz',NaN, ...
    'DD_Accept_pct',NaN, ...
    'ASM_Rot_deg',NaN, ...
    'ASM_Gap',NaN, ...
    'EVM_pct',NaN, ...
    'MER_dB',NaN, ...
    'BER',NaN, ...
    'BERErrors',NaN, ...
    'BERBits',NaN, ...
    'PASS',false, ...
    'NDAQualified',false, ...
    'NDA_Phase_deg',NaN, ...
    'DD_PhaseErrorRMS_deg',NaN, ...
    'DD_HoldFraction_pct',NaN, ...
    'FinalResidualFrequency_Hz',NaN, ...
    'FinalCarrierState','', ...
    'ASMQualified',false, ...
    'ASMBestError',NaN, ...
    'ASMMeanError',NaN, ...
    'ASMPeriodicFrames',NaN, ...
    'ASMFirstPosition',NaN, ...
    'ASMTrimBits',NaN, ...
    'ASMInverted',false, ...
    'ErrorIdentifier','', ...
    'ErrorMessage','');
end

function refConst = localAPSKReference(modType)
if strcmpi(modType,'16APSK')
    refConst = HelperCCSDSFACMReferenceConstellation(14);
elseif strcmpi(modType,'32APSK')
    refConst = HelperCCSDSFACMReferenceConstellation(21);
else
    error('Unsupported modulation %s',modType);
end
refConst = complex(refConst(:));
end

function [evmPct,merDB] = localNearestEVM(x,refConst)
x = complex(x(:));
if isempty(x)
    evmPct = NaN;
    merDB = NaN;
    return;
end
x = x/sqrt(mean(abs(x).^2)+eps);
refConst = refConst/sqrt(mean(abs(refConst).^2)+eps);
chunk = 10000;
errPower = 0;
idealPower = 0;
count = 0;
for i1 = 1:chunk:numel(x)
    i2 = min(numel(x),i1+chunk-1);
    xb = x(i1:i2);
    [~,idx] = min(abs(xb-refConst.'),[],2);
    ideal = refConst(idx);
    err = xb-ideal;
    errPower = errPower+sum(abs(err).^2);
    idealPower = idealPower+sum(abs(ideal).^2);
    count = count+numel(xb);
end
evmPct = 100*sqrt((errPower/max(1,count))/((idealPower/max(1,count))+eps));
merDB = -20*log10(evmPct/100+eps);
end
