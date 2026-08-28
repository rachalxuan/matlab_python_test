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
%  7. Four-fold ambiguity diagnostic + existing APSK soft demod
%
% The APSK point SET is invariant to 90-degree rotation, so EVM alone cannot
% resolve the quadrant.  In this isolated laboratory test only, try all four
% rotations and select by BER against txEncodedBits.  The production receiver
% must replace this oracle by ASM/frame-marker ambiguity resolution.
% =================================================================
refConst = localAPSKReference(modType);
refConst = refConst/sqrt(mean(abs(refConst).^2)+eps);
rotations = exp(1j*(0:3)*pi/2);

maxOffsetBits = 512;
bestBER = inf;                 % full-stream diagnostic BER
bestSteadyBER = inf;           % BER after acquisition/warm-up
bestEVM = inf;
bestSteadyEVM = inf;
bestMER = -inf;
bestSteadyMER = -inf;
bestRot = 1;
bestOffset = 0;
bestComparedBits = 0;
bestErrorBits = inf;
bestSteadyComparedBits = 0;
bestSteadyErrorBits = inf;
bestPolarity = +1;
bestRxHard = int8([]);

bitsPerReferenceFrame = numel(txEncodedBits)/numFrames;
if abs(bitsPerReferenceFrame-round(bitsPerReferenceFrame)) > 1e-9
    error('Reference bit stream is not an integer number of frames.');
end
bitsPerReferenceFrame = round(bitsPerReferenceFrame);
warmupBits = berWarmUpFrames*bitsPerReferenceFrame;
warmupSymbols = min(numel(carrierSynced)-1, ...
    round(berWarmUpFrames*frameSymbolsApprox));

for k = 1:4
    z = carrierSynced*rotations(k);
    [evmNow,merNow] = localNearestEVM(z,refConst);
    [steadyEVMNow,steadyMERNow] = localNearestEVM( ...
        z(warmupSymbols+1:end),refConst);

    demodObj = HelperCCSDSTMDemodulator( ...
        'Modulation',modType, ...
        'ChannelCoding','none', ...
        'PCMFormat','NRZ-L', ...
        'NoiseVariance',0.01);
    softNow = double(demodObj(z));
    rxHardNow = int8(real(softNow(:)) > 0);

    [berNow,offNow,lenNow,errNow,polNow,rAligned,tAligned] = ...
        localBestBitAlignment(rxHardNow,txEncodedBits,maxOffsetBits);

    if warmupBits < numel(rAligned)
        rSteady = rAligned(warmupBits+1:end);
        tSteady = tAligned(warmupBits+1:end);
        steadyErrNow = nnz(rSteady ~= tSteady);
        steadyLenNow = numel(rSteady);
        steadyBERNow = steadyErrNow/max(1,steadyLenNow);
    else
        steadyErrNow = inf;
        steadyLenNow = 0;
        steadyBERNow = inf;
    end

    fprintf(['[ROT diagnostic] rot=%+6.1f deg ', ...
        'EVM(all/steady)=%6.3f/%6.3f%% ', ...
        'BER(all/steady)=%.6g/%.6g offset=%+d polarity=%+d\n'], ...
        rad2deg(angle(rotations(k))),evmNow,steadyEVMNow, ...
        berNow,steadyBERNow,offNow,polNow);

    if steadyBERNow < bestSteadyBER || ...
            (abs(steadyBERNow-bestSteadyBER) < 1e-15 && steadyEVMNow < bestSteadyEVM)
        bestBER = berNow;
        bestSteadyBER = steadyBERNow;
        bestEVM = evmNow;
        bestSteadyEVM = steadyEVMNow;
        bestMER = merNow;
        bestSteadyMER = steadyMERNow;
        bestRot = k;
        bestOffset = offNow;
        bestComparedBits = lenNow;
        bestErrorBits = errNow;
        bestSteadyComparedBits = steadyLenNow;
        bestSteadyErrorBits = steadyErrNow;
        bestPolarity = polNow;
        bestRxHard = rxHardNow;
    end
end

fprintf('\n============================================================\n');
fprintf(' PILOTLESS APSK ISOLATED RECEIVER RESULT\n');
fprintf('============================================================\n');
fprintf(' modulation            : %s\n',modType);
fprintf(' pilots                 : OFF\n');
fprintf(' H                      : OFF\n');
fprintf(' configured CFO         : %+.3f Hz\n',testCFOHz);
fprintf(' configured phase       : %+.3f deg\n',testPhaseDeg);
fprintf(' NDA estimated CFO      : %+.3f Hz\n',carrierInfo.AcquisitionCFO_Hz);
fprintf(' NDA phase (mod 90 deg) : %+.3f deg\n',carrierInfo.AcquisitionPhase_deg);
fprintf(' DD acceptance          : %.2f %%\n',100*carrierInfo.AcceptanceRate);
fprintf(' HOLD/fade fraction     : %.3f / %.3f %%\n', ...
    100*carrierInfo.HoldFraction,100*carrierInfo.FadeFraction);
fprintf(' DD phase-error RMS     : %.3f deg\n',carrierInfo.PhaseErrorRMS_deg);
fprintf(' selected ambiguity rot : %+.1f deg (LAB TX-truth diagnostic)\n', ...
    rad2deg(angle(rotations(bestRot))));
fprintf(' EVM / MER (all)        : %.3f %% / %.2f dB\n',bestEVM,bestMER);
fprintf(' EVM / MER (steady)     : %.3f %% / %.2f dB\n',bestSteadyEVM,bestSteadyMER);
fprintf(' BER diagnostic (all)   : %.6g (%d/%d)\n', ...
    bestBER,bestErrorBits,bestComparedBits);
fprintf(' BER steady (%d-frame warm-up): %.6g (%d/%d)\n', ...
    berWarmUpFrames,bestSteadyBER,bestSteadyErrorBits,bestSteadyComparedBits);
fprintf(' best bit offset        : %+d\n',bestOffset);
fprintf(' best hard polarity     : %+d\n',bestPolarity);
fprintf(' final state            : %s\n',carrierState.Mode);
fprintf('============================================================\n\n');

% Per-frame BER after the selected ambiguity/alignment.  This is the key
% diagnostic for distinguishing acquisition transient from steady errors.
if ~isempty(bestRxHard)
    [~,~,~,~,~,rAlignedBest,tAlignedBest] = ...
        localBestBitAlignment(bestRxHard,txEncodedBits,maxOffsetBits);
    nAlignedFrames = floor(min(numel(rAlignedBest),numel(tAlignedBest))/bitsPerReferenceFrame);
    frameBER = NaN(nAlignedFrames,1);
    for jf = 1:nAlignedFrames
        ii = (jf-1)*bitsPerReferenceFrame + (1:bitsPerReferenceFrame);
        frameBER(jf) = mean(rAlignedBest(ii) ~= tAlignedBest(ii));
    end
    nz = find(frameBER>0);
    fprintf('[PER-FRAME BER] frames=%d, nonzero=%d, warm-up=%d frames\n', ...
        nAlignedFrames,numel(nz),berWarmUpFrames);
    if isempty(nz)
        fprintf('[PER-FRAME BER] all aligned frames are zero BER.\n');
    else
        show = nz(1:min(numel(nz),20));
        fprintf('[PER-FRAME BER nonzero] ');
        for q = 1:numel(show)
            fprintf('%d:%.3g ',show(q),frameBER(show(q)));
        end
        fprintf('\n');
    end
end

% Stage-1 acceptance is based on STEADY-STATE BER/EVM after acquisition.
% Acquisition/transient errors are reported separately rather than hidden.
% Polarity must remain +1; otherwise a demod polarity bug is being hidden.
if bestSteadyBER <= 1e-5 && bestSteadyEVM <= 3 && ...
        carrierInfo.AcquisitionQualified && bestPolarity == +1
    fprintf('[PASS-STAGE1] Steady-state NoH / no-pilot APSK carrier receiver is usable.\n');
else
    fprintf(2,['[FAIL-STAGE1] Do NOT add H yet.  Inspect NDA acquisition, ', ...
        'timing, quadrant ambiguity and DD acceptance first.\n']);
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
    % Remove only one global scalar amplitude for diagnostic comparison.
    % Evaluate the WHOLE supplied interval (chunked to control memory).
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
        errPower = errPower + sum(abs(err).^2);
        idealPower = idealPower + sum(abs(ideal).^2);
        count = count + numel(xb);
    end
    evmPct = 100*sqrt((errPower/max(1,count))/((idealPower/max(1,count))+eps));
    merDB = -20*log10(evmPct/100+eps);
end

function [ber,bestOffset,bestLength,bestErrors,bestPolarity,rAligned,tAligned] = ...
        localBestBitAlignment(rxBits,txBits,maxOffset)
    rxBits = int8(rxBits(:) ~= 0);
    txBits = int8(txBits(:) ~= 0);
    maxOffset = max(0,round(maxOffset));

    ber = inf;
    bestOffset = 0;
    bestLength = 0;
    bestErrors = inf;
    bestPolarity = +1;
    rAligned = int8([]);
    tAligned = int8([]);

    % offset > 0 means TX begins later than RX; offset < 0 means RX begins later.
    for polarity = [+1 -1]
        if polarity > 0
            r = rxBits;
        else
            r = int8(~logical(rxBits));
        end
        for off = -maxOffset:maxOffset
            if off >= 0
                r0 = 1;
                t0 = 1+off;
            else
                r0 = 1-off;
                t0 = 1;
            end
            L = min(numel(r)-r0+1,numel(txBits)-t0+1);
            if L <= 0
                continue;
            end
            err = nnz(r(r0:r0+L-1) ~= txBits(t0:t0+L-1));
            b = err/L;
            if b < ber
                ber = b;
                bestOffset = off;
                bestLength = L;
                bestErrors = err;
                bestPolarity = polarity;
                rAligned = r(r0:r0+L-1);
                tAligned = txBits(t0:t0+L-1);
            end
        end
    end
end

function t = localNumText(x)
    if isinf(x)
        t = 'Inf';
    else
        t = sprintf('%.2f',x);
    end
end
