%% TEST_APSK_PILOTLESS_RECEIVER
% Isolated pilotless APSK receiver laboratory test.
%
% Stage-1 goal:
%   TM generator -> SRRC channel waveform -> matched filter -> Gardner timing
%   -> NEW HelperTMAPSKCarrierRecovery -> APSK soft demod
%
% It deliberately does NOT call run_ccsds_tm_evaluation and does NOT use the
% custom APSK pilots.  Start with No-H / no-noise / CFO=0 / phase=0.  Only
% after this passes should CFO, AWGN and H be introduced.

clearvars;
clear classes;
clc;

addpath('E:/web_code/react/fft_project/react-fft/src/python');

DEBUG_APSK = true; %#ok<NASGU>
rng(20260819,'twister');

%% ================================================================
%  1. Test configuration -- FIRST RUN: do not make it harder
% =================================================================
modType = '32APSK';       % after 32APSK passes, repeat with '16APSK'
Rs = 10e6;
sps = 8;
Fs = Rs*sps;
rolloff = 0.35;
filterSpan = 10;
numFrames = 60;

% BER acquisition / warm-up policy.  This mirrors the main evaluator:
% frames before lock/settling are reported, but are NOT counted in steady BER.
berWarmUpFrames = 10;

% First acceptance run:
testCFOHz = 0;
testPhaseDeg = 0;
testSNRdB = Inf;          % Inf = no AWGN in this isolated unit test

% Absolutely no custom APSK pilot.
usePilots = false;

%% ================================================================
%  2. CCSDS TM waveform generator
% =================================================================
tmWaveGen = ccsdsTMWaveformGenerator( ...
    'WaveformSource','synchronization and channel coding', ...
    'NumBytesInTransferFrame',1115, ...
    'RandomizerEnabled',false, ...
    'RandomizerFECPosition','afterEncoding', ...
    'DataPathMode','single', ...
    'HasASM',true, ...
    'ChannelCoding','none', ...
    'Modulation',modType, ...
    'RolloffFactor',rolloff, ...
    'FilterSpanInSymbols',filterSpan, ...
    'SamplesPerSymbol',sps, ...
    'HasTMAPSKPilots',usePilots);

disp(tmWaveGen);
tmInfo = info(tmWaveGen);
disp(tmInfo);

bitsPerCall = tmWaveGen.NumInputBits;
txInputBits = int8(randi([0 1],bitsPerCall*numFrames,1));

% encodedBits is the exact bit stream presented to the modulator, including
% the generator's standard framing/synchronization handling.  It is used ONLY
% for laboratory BER diagnostics below, not by the carrier recovery helper.
[txWaveform,txEncodedBits] = tmWaveGen(txInputBits);
txEncodedBits = int8(txEncodedBits(:) ~= 0);

fprintf('\n[TX] mod=%s frames=%d inputBits=%d encodedBits=%d waveform=%d samples\n', ...
    modType,numFrames,numel(txInputBits),numel(txEncodedBits),numel(txWaveform));
fprintf('[TX] HasTMAPSKPilots=%d, Rs=%.3f MHz, Fs=%.3f MHz\n', ...
    usePilots,Rs/1e6,Fs/1e6);

%% ================================================================
%  3. Controlled channel impairment -- No H in stage 1
% =================================================================
n = (0:numel(txWaveform)-1).';
rx = txWaveform(:) .* exp(1j*(2*pi*testCFOHz/Fs*n + deg2rad(testPhaseDeg)));

if isfinite(testSNRdB)
    rx = awgn(rx,testSNRdB,'measured');
end

fprintf('[CHANNEL] H=OFF CFO=%+.3f Hz phase=%+.2f deg SNR=%s dB\n', ...
    testCFOHz,testPhaseDeg,localNumText(testSNRdB));

%% ================================================================
%  4. Matched SRRC filter -- same ordinary-TM structure as main receiver
% =================================================================
rxFilterDecimationFactor = sps/2;
rxFilter = comm.RaisedCosineReceiveFilter( ...
    'Shape','Square root', ...
    'RolloffFactor',rolloff, ...
    'FilterSpanInSymbols',filterSpan, ...
    'InputSamplesPerSymbol',sps, ...
    'DecimationFactor',rxFilterDecimationFactor);

nTrim = mod(numel(rx),rxFilterDecimationFactor);
if nTrim ~= 0
    rxForFilter = rx(1:end-nTrim);
else
    rxForFilter = rx;
end
filtered = rxFilter(rxForFilter);
spsAfter = sps/rxFilterDecimationFactor;  % should be 2

%% ================================================================
%  5. Gardner NDA timing -- copied from current main receiver structure
% =================================================================
Kp = 1/(pi*(1-((rolloff^2)/4))) * cos(pi*rolloff/2);
timingCfg = struct( ...
    'SamplesPerSymbol',spsAfter, ...
    'DetectorGain',Kp, ...
    'Modulation','PAM/PSK/QAM', ...
    'NormalizedLoopBandwidth',0.005, ...
    'ChunkSizeSamples',50000);

[timeSynced,timingInfo] = HelperTMSymbolSynchronizerChunked(filtered,timingCfg);

fprintf('[TIMING] input=%d filtered=%d symbols=%d chunks=%d rateError=%+.2f ppm\n', ...
    numel(rx),numel(filtered),numel(timeSynced), ...
    timingInfo.NumChunks,timingInfo.RateError_ppm);

frameSymbolsApprox = numel(timeSynced)/numFrames;
frameDurationSecApprox = frameSymbolsApprox/Rs;

% Keep the carrier helper's input contract explicit: exactly one sample/symbol.
timeSynced = complex(timeSynced(:));

%% ================================================================
%  6. NEW pilotless APSK carrier recovery
% =================================================================
crOpt = struct();
crOpt.SymbolRateHz = Rs;
crOpt.NormalizeInputPower = true;

% Feed-forward NDA acquisition.  16-symbol blocks are intentionally short:
% at 10 MBd they can follow tens-of-kHz residual CFO without phase changing
% too far inside one block.
crOpt.AcquisitionSymbols = min(4096,numel(timeSynced));
crOpt.AcquisitionBlockSymbols = 16;
crOpt.AcquisitionPhaseGridSize = 181;
crOpt.AcquisitionTrimFraction = 0.10;
crOpt.MaxAcquisitionCFOHz = 200e3;
crOpt.RequireAcquisitionQualification = true;

% DD PLL.
crOpt.DDLoopBandwidth = 0.002;
crOpt.DampingFactor = 1/sqrt(2);
crOpt.DecisionGate = NaN;       % auto = 0.40*dmin
crOpt.DecisionMarginMin = 0.12;
crOpt.MaxPhaseErrorRad = pi/5;
crOpt.MaxResidualCFOHz = 100e3;

% Pilotless protection state.
crOpt.HoldEnterBadSymbols = 4;
crOpt.RecoverGoodSymbols = 8;
crOpt.EnableFadeHold = true;
crOpt.FadePowerTauSymbols = 64;
crOpt.FadeEnterDB = -10;
crOpt.FadeExitDB = -6;
crOpt.Debug = true;

[carrierSynced,carrierState,carrierInfo] = ...
    HelperTMAPSKCarrierRecovery(timeSynced,modType,crOpt);

if ~carrierInfo.Applied
    error('test_apsk_pilotless_receiver:CarrierAcquisitionFailed', ...
        'Carrier recovery failed: %s',carrierInfo.Reason);
end

acqDurationSec = carrierInfo.AcquisitionSymbols/Rs;
acqFramesApprox = carrierInfo.AcquisitionSymbols/frameSymbolsApprox;
minWarmupFrames = ceil(acqFramesApprox) + 1;
fprintf('[ACQUISITION] NDA uses %d symbols = %.3f us = %.2f frames\n', ...
    carrierInfo.AcquisitionSymbols,1e6*acqDurationSec,acqFramesApprox);
fprintf('[ACQUISITION] BER warm-up=%d frames (minimum suggested here >=%d frames)\n', ...
    berWarmUpFrames,minWarmupFrames);
if berWarmUpFrames < minWarmupFrames
    warning('BER warm-up is shorter than acquisition + one settling frame.');
end

%% ================================================================
%  7. ASM-based 0/90/180/270 ambiguity resolution
%
% IMPORTANT:
%   The receiver decision below uses ONLY received symbols + known CCSDS ASM.
%   txEncodedBits is NOT passed to HelperTMAPSKASMResolver.
%   TX truth is retained only after all receiver decisions for laboratory BER
%   verification, exactly like a test instrument/reference checker.
% =================================================================
asmOpt = struct();
asmOpt.ChannelCoding = 'none';
asmOpt.PCMFormat = 'NRZ-L';
asmOpt.NumBytesInTransferFrame = 1115;
asmOpt.ASMHex = '1ACFFC1D';
asmOpt.DemodNoiseVariance = 0.01;

% Match the core selectRotationsByASM policy in run_ccsds_tm_evaluation.
asmOpt.MaxSearchBits = 250000;
asmOpt.ASMMaxErr = 6;
asmOpt.ASMMinScoreGap = 4;
asmOpt.PeriodicCandidates = 32;
asmOpt.PeriodicFrames = 8;
asmOpt.ASMErrMargin = 4;
asmOpt.AllowASMInversion = true;
asmOpt.RequireQualification = true;
asmOpt.Debug = true;

[asmResolved,asmInfo] = ...
    HelperTMAPSKASMResolver(carrierSynced,modType,asmOpt);

if ~asmInfo.Applied || ~asmInfo.Qualified
    error('test_apsk_pilotless_receiver_v3:ASMResolveFailed', ...
        'ASM ambiguity resolution failed: %s',asmInfo.Reason);
end

% A global bit trim is applied AFTER demodulation.  Do not convert it into
% a symbol trim: 8952 bits/frame is not divisible by 5 for 32APSK.
demodObj = HelperCCSDSTMDemodulator( ...
    'Modulation',modType, ...
    'ChannelCoding','none', ...
    'PCMFormat','NRZ-L', ...
    'NoiseVariance',0.01);
softResolved = double(demodObj(asmResolved));
rxHardRaw = int8(real(softResolved(:)) > 0);

if asmInfo.TrimBits >= numel(rxHardRaw)
    error('ASM TrimBits exceeds demodulated bit stream.');
end
rxHardAligned = rxHardRaw(asmInfo.TrimBits+1:end);

% Receiver-observable ASM verification after trim.
asmBits = localHexToBits('1ACFFC1D');
if numel(rxHardAligned) >= numel(asmBits)
    firstASMErr = nnz(rxHardAligned(1:numel(asmBits)) ~= asmBits);
    firstASMErrInv = nnz(rxHardAligned(1:numel(asmBits)) ~= int8(~logical(asmBits)));
else
    firstASMErr = inf;
    firstASMErrInv = inf;
end
fprintf('[ASM aligned] selected rot=%+.1f deg, trim=%d bits, first ASM err=%g (inv=%g)\n', ...
    asmInfo.SelectedRotation_deg,asmInfo.TrimBits,firstASMErr,firstASMErrInv);

%% ================================================================
%  8. Metrics -- TX truth is diagnostic ONLY, never used for receiver choice
% =================================================================
refConst = localAPSKReference(modType);
refConst = refConst/sqrt(mean(abs(refConst).^2)+eps);

warmupSymbols = min(numel(asmResolved)-1, ...
    round(berWarmUpFrames*frameSymbolsApprox));
[evmAll,merAll] = localNearestEVM(asmResolved,refConst);
[evmSteady,merSteady] = localNearestEVM( ...
    asmResolved(warmupSymbols+1:end),refConst);

% No bit-offset search and no polarity search here.  The ASM resolver has
% already selected the phase and bit phase.  TX bits only measure performance.
L = min(numel(rxHardAligned),numel(txEncodedBits));
rxCheck = rxHardAligned(1:L);
txCheck = txEncodedBits(1:L);
errAll = nnz(rxCheck ~= txCheck);
berAll = errAll/max(1,L);

bitsPerReferenceFrame = numel(txEncodedBits)/numFrames;
if abs(bitsPerReferenceFrame-round(bitsPerReferenceFrame)) > 1e-9
    error('Reference bit stream is not an integer number of frames.');
end
bitsPerReferenceFrame = round(bitsPerReferenceFrame);
warmupBits = berWarmUpFrames*bitsPerReferenceFrame;
if warmupBits < L
    rxSteady = rxCheck(warmupBits+1:end);
    txSteady = txCheck(warmupBits+1:end);
    steadyErr = nnz(rxSteady ~= txSteady);
    steadyLen = numel(rxSteady);
    berSteady = steadyErr/max(1,steadyLen);
else
    steadyErr = inf;
    steadyLen = 0;
    berSteady = inf;
end

fprintf('\n============================================================\n');
fprintf(' PILOTLESS APSK + ASM AUTONOMOUS RECEIVER RESULT\n');
fprintf('============================================================\n');
fprintf(' modulation            : %s\n',modType);
fprintf(' pilots                 : OFF\n');
fprintf(' H                      : OFF\n');
fprintf(' configured CFO         : %+.3f Hz\n',testCFOHz);
fprintf(' configured phase       : %+.3f deg\n',testPhaseDeg);
fprintf(' NDA estimated CFO      : %+.3f Hz\n',carrierInfo.AcquisitionCFO_Hz);
fprintf(' DD acceptance          : %.2f %%\n',100*carrierInfo.AcceptanceRate);
fprintf(' DD phase-error RMS     : %.3f deg\n',carrierInfo.PhaseErrorRMS_deg);
fprintf(' ASM selected rotation  : %+.1f deg  <-- receiver decision, no TX truth\n', ...
    asmInfo.SelectedRotation_deg);
fprintf(' ASM score gap          : %.3f\n',asmInfo.ScoreGap);
fprintf(' ASM best/mean error    : %.0f / %.3f bits\n', ...
    asmInfo.BestErrors(asmInfo.SelectedRotationIndex), ...
    asmInfo.MeanErrors(asmInfo.SelectedRotationIndex));
fprintf(' ASM periodic frames    : %d\n', ...
    asmInfo.PeriodicFramesByRotation(asmInfo.SelectedRotationIndex));
fprintf(' ASM first candidate pos: %d bits\n',asmInfo.FirstASMBitPosition);
fprintf(' ASM alignment trim     : %d bits\n',asmInfo.TrimBits);
fprintf(' ASM inverted hypothesis: %d\n',asmInfo.SelectedASMInverted);
fprintf(' EVM / MER (all)        : %.3f %% / %.2f dB\n',evmAll,merAll);
fprintf(' EVM / MER (steady)     : %.3f %% / %.2f dB\n',evmSteady,merSteady);
fprintf(' BER verify (all)       : %.6g (%d/%d) [TX truth diagnostic only]\n', ...
    berAll,errAll,L);
fprintf(' BER verify steady      : %.6g (%d/%d), warm-up=%d frames\n', ...
    berSteady,steadyErr,steadyLen,berWarmUpFrames);
fprintf(' final carrier state    : %s\n',carrierState.Mode);
fprintf('============================================================\n\n');

% Per-frame BER is still laboratory verification only.
nAlignedFrames = floor(L/bitsPerReferenceFrame);
frameBER = NaN(nAlignedFrames,1);
for jf = 1:nAlignedFrames
    ii = (jf-1)*bitsPerReferenceFrame + (1:bitsPerReferenceFrame);
    frameBER(jf) = mean(rxCheck(ii) ~= txCheck(ii));
end
nz = find(frameBER>0);
fprintf('[PER-FRAME BER verify] frames=%d, nonzero=%d, warm-up=%d\n', ...
    nAlignedFrames,numel(nz),berWarmUpFrames);
if isempty(nz)
    fprintf('[PER-FRAME BER verify] all frames zero BER.\n');
else
    show = nz(1:min(numel(nz),20));
    fprintf('[PER-FRAME BER verify nonzero] ');
    for q = 1:numel(show)
        fprintf('%d:%.3g ',show(q),frameBER(show(q)));
    end
    fprintf('\n');
end

% Stage-2 criteria: the receiver itself must qualify ASM, no oracle offset or
% oracle rotation is permitted.  TX truth is used only to verify steady BER.
selected = asmInfo.SelectedRotationIndex;
if asmInfo.Qualified && ...
        asmInfo.BestErrors(selected) <= asmOpt.ASMMaxErr && ...
        asmInfo.ScoreGap >= asmOpt.ASMMinScoreGap && ...
        berSteady <= 1e-5 && evmSteady <= 3
    fprintf('[PASS-STAGE2] APSK phase ambiguity and bit alignment are resolved by ASM without TX-truth selection.\n');
else
    fprintf(2,['[FAIL-STAGE2] Keep H/AWGN off. Inspect ASM score table, ', ...
        'selected rotation, TrimBits and periodic frame recurrence.\n']);
end

%% ========================================================================
% Local utilities
% =========================================================================
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

function bits = localHexToBits(hexText)
    hexText = regexprep(upper(strtrim(char(hexText))),'\s','');
    bits = zeros(4*numel(hexText),1,'int8');
    p = 1;
    for k = 1:numel(hexText)
        nib = dec2bin(hex2dec(hexText(k)),4)-'0';
        bits(p:p+3) = int8(nib(:));
        p = p+4;
    end
end

function t = localNumText(x)
    if isinf(x)
        t = 'Inf';
    else
        t = sprintf('%.2f',x);
    end
end
