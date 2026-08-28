function [res,dbg] = run_apsk_pilotless_receiver(userOpt)
%RUN_APSK_PILOTLESS_RECEIVER Isolated configurable pilotless CCSDS-TM APSK RX.
%
%   res = run_apsk_pilotless_receiver()
%   res = run_apsk_pilotless_receiver(opt)
%   [res,dbg] = run_apsk_pilotless_receiver(opt)
%
% The function intentionally stays independent of run_ccsds_tm_evaluation.m
% while using the same impairment objects/order so that validated logic can
% later be migrated into the main receiver with minimal risk.
%
% Signal chain (current standalone scope)
%
%   ccsdsTMWaveformGenerator (16/32APSK, pilots OFF, uncoded)
%       -> comm.PhaseFrequencyOffset          [CFO + fixed phase]
%       -> dsp.VariableFractionalDelay/Farrow [sample delay]
%       -> receiver noise                     [PSD model or awgn measured-SNR]
%       -> SRRC matched receive filter
%       -> Gardner timing recovery
%       -> HelperTMAPSKCarrierRecovery        [NDA + gated DD PLL]
%       -> HelperTMAPSKASMResolver            [0/90/180/270 + bit phase]
%       -> HelperCCSDSTMDemodulator
%       -> TX-truth BER verification ONLY
%
% Main-evaluator-compatible impairment names
%   opt.cfo              Hz
%   opt.phaseOffset      degrees
%   opt.delay            samples (fractional allowed)
%   opt.noiseMode        'off' | 'psd' | 'snr'
%   opt.noisePSDdBmHz    dBm/Hz
%   opt.noiseBandwidthHz Hz ([] => occupied RRC bandwidth)
%   opt.inputLevelDbm    dBm physical signal reference for PSD mode
%   opt.snr              dB, used for noiseMode='snr'
%
% Example
%   o = apskPilotlessDefaultConfig();
%   o.modType = '32APSK';
%   o.cfo = 20e3;
%   o.phaseOffset = 60;
%   o.delay = 0.2;
%   o.noiseMode = 'psd';
%   o.noisePSDdBmHz = -115.3;
%   o.inputLevelDbm = -10;
%   R = run_apsk_pilotless_receiver(o);
%
% IMPORTANT DIFFERENCE FROM THE CURRENT MAIN FILE
%   comm.PhaseFrequencyOffset.PhaseOffset is documented by MathWorks in
%   DEGREES.  This function therefore passes opt.phaseOffset directly.  Do
%   not convert degrees to radians before assigning the property.
%
% Current deliberate limitations
%   * 16APSK / 32APSK only
%   * ChannelCoding='none' only
%   * custom APSK pilots must be OFF
%   * H is deliberately not enabled yet; opt.enableH=true throws an error
%
% res contains only compact metrics/decisions.  dbg contains receiver state
% and, when opt.ReturnWaveforms=true, intermediate waveforms.

if nargin < 1 || isempty(userOpt)
    userOpt = struct();
end
if ~isstruct(userOpt)
    error('run_apsk_pilotless_receiver:InvalidOptions', ...
        'Input must be a configuration struct.');
end

opt = localMergeStruct(apskPilotlessDefaultConfig(),userOpt);
opt = localNormalizeAliases(opt,userOpt);
localValidateOptions(opt);

rng(double(opt.RandomSeed),'twister');

modType = upper(strtrim(char(string(opt.modType))));
Rs = double(opt.symbolRate);
sps = double(opt.sps);
Fs = Rs*sps;
rolloff = double(opt.RolloffFactor);
filterSpan = double(opt.FilterSpanInSymbols);
numFrames = round(double(opt.NumFrames));
numBytes = round(double(opt.NumBytesInTransferFrame));

cfoHz = double(opt.cfo);
phaseDeg = double(opt.phaseOffset);
delaySamples = double(opt.delay);
snrDB = double(opt.snr);

%% ========================================================================
% 1) CCSDS TM generator -- one physical waveform, custom APSK pilots OFF
% =========================================================================
tmWaveGen = ccsdsTMWaveformGenerator( ...
    'WaveformSource','synchronization and channel coding', ...
    'NumBytesInTransferFrame',numBytes, ...
    'RandomizerEnabled',logical(opt.RandomizerEnabled), ...
    'RandomizerFECPosition',char(string(opt.RandomizerFECPosition)), ...
    'DataPathMode',char(string(opt.DataPathMode)), ...
    'HasASM',logical(opt.hasASM), ...
    'ASMHex',char(string(opt.ASMHex)), ...
    'ChannelCoding','none', ...
    'Modulation',modType, ...
    'RolloffFactor',rolloff, ...
    'FilterSpanInSymbols',filterSpan, ...
    'SamplesPerSymbol',sps, ...
    'HasTMAPSKPilots',false);

bitsPerCall = tmWaveGen.NumInputBits;
txInputBits = int8(randi([0 1],bitsPerCall*numFrames,1));

if logical(opt.Debug)
    [txWaveform,txEncodedBits] = tmWaveGen(txInputBits);
else
    evalc('[txWaveform,txEncodedBits] = tmWaveGen(txInputBits);');
end

txWaveform = complex(txWaveform(:));
txEncodedBits = int8(txEncodedBits(:) ~= 0);

%% ========================================================================
% 2) Controlled impairments -- same ordering/objects as main evaluator
% =========================================================================
% Main order is CFO/phase -> fractional delay -> channel -> receiver noise.
% H is intentionally absent here, therefore receiver noise follows delay.
rxPFO = txWaveform;
if cfoHz ~= 0 || phaseDeg ~= 0
    % MathWorks documents PhaseOffset in DEGREES.
    pfo = comm.PhaseFrequencyOffset( ...
        'FrequencyOffset',cfoHz, ...
        'PhaseOffset',phaseDeg, ...
        'SampleRate',Fs);
    rxPFO = pfo(txWaveform);
end

rxDelay = rxPFO;
if delaySamples ~= 0
    maxDelay = round(double(opt.delayMaximumSamples));
    if delaySamples > maxDelay
        error('run_apsk_pilotless_receiver:DelayTooLarge', ...
            'delay=%.6g samples exceeds delayMaximumSamples=%d.', ...
            delaySamples,maxDelay);
    end

    delayMethod = char(string(opt.delayInterpolationMethod));
    if strcmpi(delayMethod,'Farrow')
        varDelay = dsp.VariableFractionalDelay( ...
            'InterpolationMethod','Farrow', ...
            'MaximumDelay',maxDelay, ...
            'FarrowSmallDelayAction',char(string(opt.delayFarrowSmallDelayAction)));
    else
        varDelay = dsp.VariableFractionalDelay( ...
            'InterpolationMethod',delayMethod, ...
            'MaximumDelay',maxDelay);
    end
    rxDelay = varDelay(rxPFO,delaySamples);
end

% Placeholder is explicit: do not accidentally pretend H has been tested.
if logical(opt.enableH)
    error('run_apsk_pilotless_receiver:HNotEnabledYet', ...
        ['The standalone receiver deliberately keeps H disabled until CFO/', ...
         'phase/delay/noise regression passes.  Set enableH=false.']);
end

[rx,noiseInfo] = localAddReceiverNoise( ...
    rxDelay,opt,Fs,snrDB,rxDelay,Rs,rolloff);

if logical(opt.DebugImpairments)
    fprintf('\n[APSK standalone impairments]\n');
    fprintf('  Fs / Rs          : %.6f / %.6f MHz\n',Fs/1e6,Rs/1e6);
    fprintf('  CFO              : %+.3f Hz  [comm.PhaseFrequencyOffset]\n',cfoHz);
    fprintf('  phase offset     : %+.3f deg [comm.PhaseFrequencyOffset]\n',phaseDeg);
    fprintf('  delay            : %.6f samples [dsp.VariableFractionalDelay/%s]\n', ...
        delaySamples,char(string(opt.delayInterpolationMethod)));
    fprintf('  noise mode       : %s\n',char(noiseInfo.Mode));
    if strcmpi(char(noiseInfo.Mode),'psd')
        fprintf('  noise PSD        : %.3f dBm/Hz\n',noiseInfo.PSD_dBmHz);
        fprintf('  noise bandwidth  : %.6f MHz\n',noiseInfo.BandwidthHz/1e6);
        fprintf('  noise power      : %.3f dBm\n',noiseInfo.NoisePower_dBm);
        fprintf('  signal reference : %.3f dBm\n',noiseInfo.ReferenceLevel_dBm);
        fprintf('  equivalent SNR   : %.3f dB\n',noiseInfo.EquivalentSNR_dB);
    elseif strcmpi(char(noiseInfo.Mode),'snr')
        fprintf('  measured SNR     : %.3f dB\n',noiseInfo.SNR_dB);
    end
end

%% ========================================================================
% 3) SRRC matched receive filter, 8 sps -> 2 sps for the validated baseline
% =========================================================================
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
spsAfter = sps/rxFilterDecimationFactor;

%% ========================================================================
% 4) Gardner NDA timing
% =========================================================================
Kp = 1/(pi*(1-((rolloff^2)/4))) * cos(pi*rolloff/2);
timingCfg = struct( ...
    'SamplesPerSymbol',spsAfter, ...
    'DetectorGain',Kp, ...
    'Modulation','PAM/PSK/QAM', ...
    'NormalizedLoopBandwidth',double(opt.timingNormalizedLoopBandwidth), ...
    'ChunkSizeSamples',round(double(opt.timingChunkSizeSamples)));

if logical(opt.DebugReceiver)
    [timeSynced,timingInfo] = HelperTMSymbolSynchronizerChunked(filtered,timingCfg);
else
    evalc('[timeSynced,timingInfo] = HelperTMSymbolSynchronizerChunked(filtered,timingCfg);');
end
timeSynced = complex(timeSynced(:));
frameSymbolsApprox = numel(timeSynced)/numFrames;

%% ========================================================================
% 5) Pilotless APSK carrier recovery
% =========================================================================
crOpt = opt.CarrierRecovery;
crOpt.SymbolRateHz = Rs;
crOpt.AcquisitionSymbols = min(round(double(crOpt.AcquisitionSymbols)),numel(timeSynced));
crOpt.Debug = logical(crOpt.Debug) || logical(opt.DebugReceiver);

[carrierSynced,carrierState,carrierInfo] = ...
    HelperTMAPSKCarrierRecovery(timeSynced,modType,crOpt);

if ~carrierInfo.Applied || ~carrierInfo.AcquisitionQualified
    error('run_apsk_pilotless_receiver:CarrierFailed', ...
        'Carrier acquisition failed: %s',carrierInfo.Reason);
end

%% ========================================================================
% 6) Periodic ASM resolves 0/90/180/270 ambiguity + bit phase
% =========================================================================
asmOpt = opt.ASM;
asmOpt.ChannelCoding = 'none';
asmOpt.PCMFormat = char(string(opt.PCMFormat));
asmOpt.NumBytesInTransferFrame = numBytes;
asmOpt.ASMHex = char(string(opt.ASMHex));
asmOpt.Debug = logical(asmOpt.Debug) || logical(opt.DebugReceiver);

[asmResolved,asmInfo] = HelperTMAPSKASMResolver( ...
    carrierSynced,modType,asmOpt);

if ~asmInfo.Applied || ~asmInfo.Qualified
    error('run_apsk_pilotless_receiver:ASMFailed', ...
        'ASM ambiguity resolution failed: %s',asmInfo.Reason);
end

%% ========================================================================
% 7) APSK demod + ASM-derived BIT alignment
% =========================================================================
demodObj = HelperCCSDSTMDemodulator( ...
    'Modulation',modType, ...
    'ChannelCoding','none', ...
    'PCMFormat',char(string(opt.PCMFormat)), ...
    'NoiseVariance',double(asmOpt.DemodNoiseVariance));

softResolved = double(demodObj(asmResolved));
rxHardRaw = int8(real(softResolved(:)) > 0);

if asmInfo.TrimBits >= numel(rxHardRaw)
    error('run_apsk_pilotless_receiver:TrimTooLarge', ...
        'ASM TrimBits=%d exceeds RX bit stream length %d.', ...
        asmInfo.TrimBits,numel(rxHardRaw));
end
rxHardAligned = rxHardRaw(asmInfo.TrimBits+1:end);

%% ========================================================================
% 8) Steady-state EVM/MER -- acquisition/warm-up excluded
% =========================================================================
refConst = localAPSKReference(modType);
refConst = refConst/sqrt(mean(abs(refConst).^2)+eps);

warmupFrames = round(double(opt.BERWarmUpFrames));
warmupSymbols = min(max(0,numel(asmResolved)-1), ...
    round(warmupFrames*frameSymbolsApprox));
if warmupSymbols < numel(asmResolved)
    steadySymbols = asmResolved(warmupSymbols+1:end);
else
    steadySymbols = complex([]);
end
[evmSteady,merSteady] = localNearestEVM(steadySymbols,refConst);
[evmAll,merAll] = localNearestEVM(asmResolved,refConst);

%% ========================================================================
% 9) TX-truth BER verification ONLY -- never used by receiver decisions
% =========================================================================
L = min(numel(rxHardAligned),numel(txEncodedBits));
if L <= 0
    error('run_apsk_pilotless_receiver:NoBits','No aligned RX bits are available.');
end
rxCheck = rxHardAligned(1:L);
txCheck = txEncodedBits(1:L);

allErr = nnz(rxCheck ~= txCheck);
berAll = allErr/max(1,L);

bitsPerReferenceFrame = numel(txEncodedBits)/numFrames;
if abs(bitsPerReferenceFrame-round(bitsPerReferenceFrame)) > 1e-9
    error('run_apsk_pilotless_receiver:FrameLength', ...
        'Reference stream is not an integer number of frames.');
end
bitsPerReferenceFrame = round(bitsPerReferenceFrame);
warmupBits = warmupFrames*bitsPerReferenceFrame;
if warmupBits >= L
    error('run_apsk_pilotless_receiver:WarmupTooLong', ...
        'BER warm-up removes the complete BER interval.');
end
rxSteady = rxCheck(warmupBits+1:end);
txSteady = txCheck(warmupBits+1:end);
steadyErr = nnz(rxSteady ~= txSteady);
steadyLen = numel(rxSteady);
berSteady = steadyErr/max(1,steadyLen);

%% ========================================================================
% 10) Verdict + compact result
% =========================================================================
selected = asmInfo.SelectedRotationIndex;
isTrack = strcmpi(string(carrierState.Mode),'TRACK');
ddQualityPass = ~logical(carrierInfo.DDPhaseTrackerEnabled) || ...
    (carrierInfo.AcceptanceRate >= double(opt.MinDDAcceptance) && ...
     carrierInfo.PhaseErrorRMS_deg <= double(opt.MaxPhaseErrorRMS_deg));

passFlag = ...
    carrierInfo.AcquisitionQualified && ...
    asmInfo.Qualified && ...
    asmInfo.BestErrors(selected) <= double(asmOpt.ASMMaxErr) && ...
    asmInfo.ScoreGap >= double(asmOpt.ASMMinScoreGap) && ...
    ~logical(asmInfo.SelectedASMInverted) && ...
    ddQualityPass && ...
    evmSteady <= double(opt.MaxSteadyEVM_pct) && ...
    berSteady <= double(opt.MaxSteadyBER) && ...
    isTrack;

res = struct();
res.Modulation = modType;
res.NumFrames = numFrames;
res.NumBytesInTransferFrame = numBytes;
res.SymbolRate_Hz = Rs;
res.SampleRate_Hz = Fs;
res.SamplesPerSymbol = sps;
res.PilotsEnabled = false;

res.cfo_in_Hz = cfoHz;
res.phase_in_deg = phaseDeg;
res.delay_in_samples = delaySamples;
res.NoiseMode = char(noiseInfo.Mode);
res.NoisePSD_dBmHz = noiseInfo.PSD_dBmHz;
res.NoiseBandwidth_Hz = noiseInfo.BandwidthHz;
res.NoisePower_dBm = noiseInfo.NoisePower_dBm;
res.NoiseReferenceLevel_dBm = noiseInfo.ReferenceLevel_dBm;
res.NoiseEquivalentSNR_dB = noiseInfo.EquivalentSNR_dB;
res.SNRInput_dB = snrDB;

res.NDAQualified = carrierInfo.AcquisitionQualified;
res.NDAEstimatedCFO_Hz = carrierInfo.AcquisitionCFO_Hz;
res.NDAPhase_deg = carrierInfo.AcquisitionPhase_deg;
res.FourthPowerCFO_Hz = carrierInfo.FourthPowerCFO_Hz;
res.FourthPowerConfidence_dB = carrierInfo.FourthPowerConfidence_dB;
res.CoarsePowerOrder = carrierInfo.CoarsePowerOrder;
res.WideRangeRingCoarseEnabled = ...
    carrierInfo.WideRangeRingCoarseEnabled;
res.CoarseSelectedSymbols = carrierInfo.CoarseSelectedSymbols;
res.CoarseSelectionFraction = carrierInfo.CoarseSelectionFraction;
res.CoarseUnambiguousMaxCFO_Hz = ...
    carrierInfo.CoarseUnambiguousMaxCFO_Hz;
res.NDAResidualCFO_Hz = carrierInfo.NDAResidualCFO_Hz;
res.NDAResidualCFOApplied = carrierInfo.NDAResidualCFOApplied;
res.GlobalNDAPhase_deg = carrierInfo.GlobalNDAPhase_deg;
res.GlobalNDAMetric = carrierInfo.GlobalNDAMetric;
res.DDAcceptance_pct = 100*carrierInfo.AcceptanceRate;
res.DDPhaseErrorRMS_deg = carrierInfo.PhaseErrorRMS_deg;
res.HoldFraction_pct = 100*carrierInfo.HoldFraction;
res.FinalResidualFrequency_Hz = carrierInfo.FinalResidualFrequency_Hz;
res.FinalCarrierState = char(string(carrierState.Mode));

res.ASMQualified = asmInfo.Qualified;
res.ASMRotation_deg = asmInfo.SelectedRotation_deg;
res.ASMScoreGap = asmInfo.ScoreGap;
res.ASMBestError = asmInfo.BestErrors(selected);
res.ASMMeanError = asmInfo.MeanErrors(selected);
res.ASMPeriodicFrames = asmInfo.PeriodicFramesByRotation(selected);
res.ASMFirstPosition_bits = asmInfo.FirstASMBitPosition;
res.ASMTrimBits = asmInfo.TrimBits;
res.ASMInverted = logical(asmInfo.SelectedASMInverted);

res.EVMAll_pct = evmAll;
res.MERAll_dB = merAll;
res.EVMSteady_pct = evmSteady;
res.MERSteady_dB = merSteady;
res.BERAll = berAll;
res.BERAllErrors = allErr;
res.BERAllBits = L;
res.BERSteady = berSteady;
res.BERSteadyErrors = steadyErr;
res.BERSteadyBits = steadyLen;
res.BERWarmUpFrames = warmupFrames;

res.AcquisitionSymbols = crOpt.AcquisitionSymbols;
res.AcquisitionTime_s = crOpt.AcquisitionSymbols/Rs;
res.AcquisitionFramesApprox = crOpt.AcquisitionSymbols/max(frameSymbolsApprox,eps);
res.Pass = passFlag;
res.Status = ternary(passFlag,'PASS','FAIL_METRIC');

%% Debug output
if logical(opt.Debug)
    fprintf('\n============================================================\n');
    fprintf(' PILOTLESS APSK STANDALONE RECEIVER RESULT\n');
    fprintf('============================================================\n');
    fprintf(' modulation            : %s\n',res.Modulation);
    fprintf(' pilots                 : OFF\n');
    fprintf(' CFO / phase / delay    : %+.3f Hz / %+.3f deg / %.6f samples\n', ...
        res.cfo_in_Hz,res.phase_in_deg,res.delay_in_samples);
    if strcmpi(res.NoiseMode,'psd')
        fprintf(' noise                  : %.3f dBm/Hz over %.6f MHz, EqSNR=%.3f dB\n', ...
            res.NoisePSD_dBmHz,res.NoiseBandwidth_Hz/1e6,res.NoiseEquivalentSNR_dB);
    elseif strcmpi(res.NoiseMode,'snr')
        fprintf(' noise                  : measured SNR %.3f dB\n',res.SNRInput_dB);
    else
        fprintf(' noise                  : OFF\n');
    end
    fprintf([' x^M FFT CFO            : M=%g, %+.3f Hz ', ...
        '(confidence %.2f dB)\n'], ...
        res.CoarsePowerOrder,res.FourthPowerCFO_Hz, ...
        res.FourthPowerConfidence_dB);
    fprintf([' wide ring acquisition  : %d, selected %.2f%%, ', ...
        'unambiguous +/-%.3f kHz\n'], ...
        res.WideRangeRingCoarseEnabled, ...
        100*res.CoarseSelectionFraction, ...
        res.CoarseUnambiguousMaxCFO_Hz/1e3);
    fprintf(' NDA residual / total   : %+.3f / %+.3f Hz (applied=%d)\n', ...
        res.NDAResidualCFO_Hz,res.NDAEstimatedCFO_Hz, ...
        res.NDAResidualCFOApplied);
    fprintf(' global NDA phase       : %+.3f deg, metric %.5g\n', ...
        res.GlobalNDAPhase_deg,res.GlobalNDAMetric);
    fprintf(' DD acceptance          : %.3f %%\n',res.DDAcceptance_pct);
    fprintf(' DD phase RMS           : %.3f deg\n',res.DDPhaseErrorRMS_deg);
    fprintf(' ASM rotation / gap     : %+.1f deg / %.3f\n', ...
        res.ASMRotation_deg,res.ASMScoreGap);
    fprintf(' ASM trim               : %d bits\n',res.ASMTrimBits);
    fprintf(' acquisition            : %d symbols = %.3f us ~= %.2f frames\n', ...
        res.AcquisitionSymbols,1e6*res.AcquisitionTime_s,res.AcquisitionFramesApprox);
    fprintf(' EVM / MER steady       : %.3f %% / %.2f dB\n', ...
        res.EVMSteady_pct,res.MERSteady_dB);
    fprintf(' BER all / steady       : %.6g / %.6g (%d/%d)\n', ...
        res.BERAll,res.BERSteady,res.BERSteadyErrors,res.BERSteadyBits);
    fprintf(' final carrier state    : %s\n',res.FinalCarrierState);
    fprintf(' status                 : %s\n',res.Status);
    fprintf('============================================================\n');
end

%% Optional debug package
if nargout > 1
    dbg = struct();
    dbg.Options = opt;
    dbg.NoiseInfo = noiseInfo;
    dbg.TimingInfo = timingInfo;
    dbg.CarrierInfo = carrierInfo;
    dbg.CarrierState = carrierState;
    dbg.ASMInfo = asmInfo;
    if logical(opt.ReturnWaveforms)
        dbg.TxWaveform = txWaveform;
        dbg.AfterPhaseFrequencyOffset = rxPFO;
        dbg.AfterDelay = rxDelay;
        dbg.AfterNoise = rx;
        dbg.Filtered = filtered;
        dbg.TimeSynced = timeSynced;
        dbg.CarrierSynced = carrierSynced;
        dbg.ASMResolved = asmResolved;
        dbg.RXHardAligned = rxHardAligned;
        dbg.TXEncodedBits = txEncodedBits;
    end
else
    dbg = struct();
end
end

% ========================================================================
% Receiver noise -- mirrors run_ccsds_tm_evaluation/addReceiverNoise.
% ========================================================================
function [yOut,noiseInfo] = localAddReceiverNoise( ...
        xIn,opt,sampleRateHz,snrDB,referenceSignal,symbolRateHz,rolloff)

xIn = xIn(:);
referenceSignal = referenceSignal(:);
mode = lower(strtrim(char(string(opt.noiseMode))));
modeKey = erase(string(mode),["_","-"," "]);

if any(modeKey == ["off","none","disabled","disable","no"])
    yOut = xIn;
    noiseInfo = localNoiseInfoOff(snrDB);
    return;
end

if any(modeKey == ["snr","measured","legacy","legacymeasured","awgn"])
    if ~isfinite(snrDB)
        yOut = xIn;
    else
        yOut = awgn(xIn,snrDB,'measured');
    end
    noiseInfo = struct( ...
        'Mode',"snr", ...
        'SNR_dB',snrDB, ...
        'PSD_dBmHz',NaN, ...
        'BandwidthHz',NaN, ...
        'NoisePower_dBm',NaN, ...
        'ReferenceLevel_dBm',NaN, ...
        'EquivalentSNR_dB',snrDB, ...
        'NoiseVarianceDigital',NaN);
    return;
end

if ~strcmp(modeKey,"psd")
    error('run_apsk_pilotless_receiver:UnknownNoiseMode', ...
        'noiseMode must be ''off'', ''psd'', or ''snr''; got "%s".',mode);
end

psdDBmHz = double(opt.noisePSDdBmHz);
if ~isfinite(psdDBmHz)
    psdDBmHz = -115.3;
end

noiseBandwidthHz = [];
if isfield(opt,'noiseBandwidthHz') && ~isempty(opt.noiseBandwidthHz)
    noiseBandwidthHz = double(opt.noiseBandwidthHz);
end
if isempty(noiseBandwidthHz) || ~isfinite(noiseBandwidthHz) || noiseBandwidthHz <= 0
    noiseBandwidthHz = min(sampleRateHz,(1+rolloff)*symbolRateHz);
end

referencePowerDigital = mean(abs(referenceSignal).^2) + eps;
referenceLevelDBm = double(opt.inputLevelDbm);
signalPowerW = 1e-3 * 10.^(referenceLevelDBm/10);
digitalUnitsPerWatt = referencePowerDigital/max(signalPowerW,realmin);

noisePSD_WHz = 1e-3 * 10.^(psdDBmHz/10);
noisePowerW = noisePSD_WHz*noiseBandwidthHz;
noiseVarianceDigital = noisePowerW*digitalUnitsPerWatt;

if isreal(xIn)
    n = sqrt(noiseVarianceDigital).*randn(size(xIn));
else
    n = sqrt(noiseVarianceDigital/2).* ...
        (randn(size(xIn)) + 1j*randn(size(xIn)));
end
yOut = xIn+n;

currentSignalPowerDigital = mean(abs(xIn).^2)+eps;
noiseInfo = struct( ...
    'Mode',"psd", ...
    'SNR_dB',snrDB, ...
    'PSD_dBmHz',psdDBmHz, ...
    'BandwidthHz',noiseBandwidthHz, ...
    'NoisePower_dBm',psdDBmHz + 10*log10(noiseBandwidthHz), ...
    'ReferenceLevel_dBm',referenceLevelDBm, ...
    'EquivalentSNR_dB',10*log10(currentSignalPowerDigital/max(noiseVarianceDigital,realmin)), ...
    'NoiseVarianceDigital',noiseVarianceDigital);
end

function info = localNoiseInfoOff(snrDB)
info = struct( ...
    'Mode',"off", ...
    'SNR_dB',snrDB, ...
    'PSD_dBmHz',NaN, ...
    'BandwidthHz',NaN, ...
    'NoisePower_dBm',NaN, ...
    'ReferenceLevel_dBm',NaN, ...
    'EquivalentSNR_dB',Inf, ...
    'NoiseVarianceDigital',0);
end

% ========================================================================
% Option handling
% ========================================================================
function out = localMergeStruct(defaults,user)
out = defaults;
fn = fieldnames(user);
for k = 1:numel(fn)
    name = fn{k};
    if isstruct(user.(name)) && isfield(out,name) && isstruct(out.(name))
        out.(name) = localMergeStruct(out.(name),user.(name));
    else
        out.(name) = user.(name);
    end
end
end

function opt = localNormalizeAliases(opt,user)
% Accept the newer descriptive aliases while keeping main-script names as
% the canonical fields in the returned option struct.
opt.modType = localAlias(user,{'modType','Modulation'},opt.modType);
opt.symbolRate = localAlias(user,{'symbolRate','SymbolRate'},opt.symbolRate);
opt.sps = localAlias(user,{'sps','SamplesPerSymbol'},opt.sps);
opt.cfo = localAlias(user,{'cfo','CFOHz'},opt.cfo);
opt.phaseOffset = localAlias(user,{'phaseOffset','PhaseOffsetDeg'},opt.phaseOffset);
opt.delay = localAlias(user,{'delay','DelaySamples'},opt.delay);
opt.noisePSDdBmHz = localAlias(user,{'noisePSDdBmHz','NoisePSDdBmHz'},opt.noisePSDdBmHz);
opt.noiseBandwidthHz = localAlias(user,{'noiseBandwidthHz','NoiseBandwidthHz'},opt.noiseBandwidthHz);
opt.inputLevelDbm = localAlias(user,{'inputLevelDbm','InputLevelDBm','signalReferenceLevelDbm'},opt.inputLevelDbm);
end

function value = localAlias(s,names,defaultValue)
value = defaultValue;
for k = 1:numel(names)
    if isfield(s,names{k}) && ~isempty(s.(names{k}))
        value = s.(names{k});
        return;
    end
end
end

function localValidateOptions(opt)
modType = upper(strtrim(char(string(opt.modType))));
if ~any(strcmp(modType,{'16APSK','32APSK'}))
    error('run_apsk_pilotless_receiver:UnsupportedModulation', ...
        'modType must be 16APSK or 32APSK.');
end
if ~strcmpi(strtrim(char(string(opt.channelCoding))),'none')
    error('run_apsk_pilotless_receiver:UnsupportedCoding', ...
        'The standalone receiver currently supports channelCoding=''none'' only.');
end
if logical(opt.HasTMAPSKPilots)
    error('run_apsk_pilotless_receiver:PilotsMustBeOff', ...
        'HasTMAPSKPilots must remain false in the pilotless receiver.');
end
if logical(opt.enableH)
    % Also checked at the exact insertion point for an explicit error.
end
if ~isfinite(double(opt.symbolRate)) || double(opt.symbolRate) <= 0
    error('run_apsk_pilotless_receiver:InvalidSymbolRate','symbolRate must be > 0.');
end
sps = double(opt.sps);
if ~isfinite(sps) || sps < 2 || abs(sps-round(sps)) > 0 || mod(round(sps),2) ~= 0
    error('run_apsk_pilotless_receiver:InvalidSPS', ...
        'sps must be a positive even integer for the current 2-sps timing path.');
end
if ~isfinite(double(opt.delay)) || double(opt.delay) < 0
    error('run_apsk_pilotless_receiver:InvalidDelay', ...
        'delay must be a finite nonnegative number of input samples.');
end
if ~isfinite(double(opt.phaseOffset))
    error('run_apsk_pilotless_receiver:InvalidPhase','phaseOffset must be finite degrees.');
end
if ~isfinite(double(opt.cfo))
    error('run_apsk_pilotless_receiver:InvalidCFO','cfo must be finite Hz.');
end
if round(double(opt.NumFrames)) <= double(opt.BERWarmUpFrames)
    error('run_apsk_pilotless_receiver:TooFewFrames', ...
        'NumFrames must exceed BERWarmUpFrames.');
end
end

% ========================================================================
% Metrics
% ========================================================================
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
    errPower = errPower + sum(abs(err).^2);
    idealPower = idealPower + sum(abs(ideal).^2);
    count = count + numel(xb);
end
evmPct = 100*sqrt((errPower/max(1,count))/((idealPower/max(1,count))+eps));
merDB = -20*log10(evmPct/100+eps);
end

function y = ternary(cond,a,b)
if cond
    y = a;
else
    y = b;
end
end
