function [y, info] = HelperGMSKSecondOrderPLL(x, sampleRateHz, symbolRateHz, options)
%HELPERGMSKSECONDORDERPLL Decision-free residual Doppler loop for GMSK.
%
% Squaring a GMSK waveform exposes conjugate spectral lines around
% +/-symbolRate/2.  The detector mixes both lines to DC, low-pass filters
% them, estimates their data-independent relative phase, and coherently
% combines them.  The combined phase is twice the residual carrier phase.
% A second-order phase/frequency loop removes that time-varying common
% phase while coasting through fades.  This helper is independent of the
% official Viterbi detector and intentionally does not equalize CPM memory.

if nargin < 4 || isempty(options)
    options = struct();
end
x = complex(x(:));
y = x;
info = localEmptyInfo();

if isempty(x) || ~isscalar(sampleRateHz) || ~isfinite(sampleRateHz) || ...
        sampleRateHz <= 0 || ~isscalar(symbolRateHz) || ...
        ~isfinite(symbolRateHz) || symbolRateHz <= 0
    info.Reason = 'invalid or empty input';
    return;
end

sps = max(1, round(sampleRateHz/symbolRateHz));
if numel(x) < 8*sps
    info.Reason = 'input is too short for the GMSK differential detector';
    return;
end

acquireBW = localNumber(options, 'gmskPLLAcquireLoopBandwidth', 0.020);
trackBW = localNumber(options, 'gmskPLLTrackLoopBandwidth', 0.003);
detectorTauSymbols = localNumber(options, 'gmskPLLDetectorTauSymbols', 16);
normalizeDetectorInput = localLogical(options, ...
    'gmskPLLNormalizeDetectorInput', false);
detectorNormalizationFloorDB = localNumber(options, ...
    'gmskPLLDetectorNormalizationFloorDB', -80);
lockThreshold = localNumber(options, 'gmskPLLLockErrorThreshold', 0.12);
unlockThreshold = localNumber(options, 'gmskPLLUnlockErrorThreshold', 0.30);
lockSymbols = localNumber(options, 'gmskPLLLockSymbols', 128);
unlockSymbols = localNumber(options, 'gmskPLLUnlockSymbols', 32);
minAcquireSymbols = localNumber(options, 'gmskPLLMinAcquireSymbols', 256);
fadeThresholdDB = localNumber(options, 'gmskPLLFadeThresholdDB', -15);
maxFrequencyFraction = localNumber(options, ...
    'gmskPLLMaxFrequencyFraction', 0.05);
fastTransientReacquire = localLogical(options, ...
    'gmskPLLFastTransientReacquire', false);

acquireBW = min(max(acquireBW, 1e-5), 0.20);
trackBW = min(max(trackBW, 1e-5), acquireBW);
detectorTauSymbols = max(0.25, detectorTauSymbols);
detectorNormalizationFloorDB = min(max( ...
    detectorNormalizationFloorDB, -300), 0);
lockThreshold = min(max(lockThreshold, 1e-3), pi/2);
unlockThreshold = min(max(unlockThreshold, lockThreshold), pi/2);
lockSamples = max(sps, round(lockSymbols*sps));
unlockSamples = max(sps, round(unlockSymbols*sps));
minAcquireSamples = max(2*sps, round(minAcquireSymbols*sps));
maxFrequency = 2*pi*maxFrequencyFraction*symbolRateHz/sampleRateHz;

% The loop bandwidth options are normalized to symbol rate.  Convert them
% to sample-rate proportional/integral gains.  The conservative integral
% gain is deliberate: the detector observes a full-symbol phase increment.
[kpAcquire, kiAcquire] = localLoopGains(acquireBW/sps);
[kpTrack, kiTrack] = localLoopGains(trackBW/sps);
detectorAlpha = exp(-1/max(detectorTauSymbols*sps,1));
relativeAlpha = exp(-1/max(4*detectorTauSymbols*sps,1));
powerAlpha = exp(-1/max(16*sps,1));

nInit = min(numel(x), max(32*sps, 256));
powerState = max(mean(abs(x(1:nInit)).^2), 1e-12);
referencePower = powerState;
fadePower = referencePower*10^(fadeThresholdDB/10);
detectorNormalizationFloorPower = referencePower* ...
    10^(detectorNormalizationFloorDB/10);
[externalHoldMask,externalHoldProvided] = ...
    localExternalHoldMask(options,numel(x));

phaseState = 0;
frequencyState = 0;
positiveLineState = 0 + 0j;
negativeLineState = 0 + 0j;
relativePhaseState = 0 + 0j;
locked = false;
goodRun = 0;
badRun = 0;
lockTransitions = 0;
reacquisitions = 0;
accepted = 0;
fadeHolds = 0;
detectorFloorLimitedSamples = 0;
phaseErrors = nan(numel(x),1);
frequencyTrace = zeros(numel(x),1);
phaseTrace = zeros(numel(x),1);

for k = 1:numel(x)
    phaseState = phaseState + frequencyState;
    z = x(k)*exp(-1j*phaseState);
    y(k) = z;

    p = abs(x(k))^2;
    if isfinite(p)
        powerState = powerAlpha*powerState + (1-powerAlpha)*p;
    end
    inFade = powerState < fadePower || externalHoldMask(k);

    if ~inFade
        tonePhase = pi*(k-1)/sps;
        detectorSample = z;
        if normalizeDetectorInput
            % GMSK is constant-envelope before the scalar H channel.  Use
            % its phase, rather than its instantaneous magnitude, to drive
            % the conjugate-line detector.  Otherwise z^2 weights a deep
            % fade twice and the fixed detector gates silently stop phase
            % tracking even in an exactly noiseless waveform.  The floor
            % keeps the operation bounded if a sample is zero/non-finite;
            % noisy operation leaves this mode disabled by default.
            samplePower = abs(z)^2;
            if ~isfinite(samplePower)
                samplePower = 0;
            end
            if samplePower < detectorNormalizationFloorPower
                detectorFloorLimitedSamples = ...
                    detectorFloorLimitedSamples + 1;
            end
            detectorSample = z/sqrt(max( ...
                samplePower,detectorNormalizationFloorPower));
        end
        squaredSample = detectorSample.^2;
        positiveObservation = squaredSample*exp(-1j*tonePhase);
        negativeObservation = squaredSample*exp(1j*tonePhase);
        positiveLineState = detectorAlpha*positiveLineState + ...
            (1-detectorAlpha)*positiveObservation;
        negativeLineState = detectorAlpha*negativeLineState + ...
            (1-detectorAlpha)*negativeObservation;
        crossLine = positiveLineState*conj(negativeLineState);
        relativePhaseState = relativeAlpha*relativePhaseState + ...
            (1-relativeAlpha)*crossLine;
        if k > max(4*sps,round(2*detectorTauSymbols*sps)) && ...
                abs(relativePhaseState) > 1e-10
            alignedNegative = negativeLineState* ...
                exp(1j*angle(relativePhaseState));
            detectorState = positiveLineState+alignedNegative;
            if abs(detectorState) > 1e-9
                phaseError = 0.5*angle(detectorState);
                % A deep complex fade can create a short, physically real
                % carrier-phase excursion without keeping the detector bad
                % long enough to declare the whole loop unlocked.  Use the
                % acquisition gains only while that large innovation is
                % present, then return immediately to the quiet tracking
                % gains.  This is still decision-free and uses no true H.
                if locked && (~fastTransientReacquire || ...
                        abs(phaseError) < unlockThreshold)
                    kp = kpTrack;
                    ki = kiTrack;
                    phaseErrorForCorrection = phaseError;
                else
                    kp = kpAcquire;
                    ki = kiAcquire;
                    phaseErrorForCorrection = phaseError;
                end
                frequencyState = frequencyState + ki*phaseError;
                frequencyState = min(max(frequencyState, ...
                    -maxFrequency), maxFrequency);
                phaseState = phaseState + kp*phaseErrorForCorrection;
                y(k) = x(k)*exp(-1j*phaseState);
                phaseErrors(k) = phaseError;
                accepted = accepted + 1;

                if abs(phaseError) <= lockThreshold
                    goodRun = goodRun + 1;
                    badRun = 0;
                elseif abs(phaseError) >= unlockThreshold
                    badRun = badRun + 1;
                    goodRun = 0;
                else
                    goodRun = max(goodRun-1,0);
                    badRun = max(badRun-1,0);
                end
                if ~locked && k >= minAcquireSamples && goodRun >= lockSamples
                    locked = true;
                    lockTransitions = lockTransitions + 1;
                    goodRun = 0;
                    badRun = 0;
                elseif locked && badRun >= unlockSamples
                    locked = false;
                    reacquisitions = reacquisitions + 1;
                    goodRun = 0;
                    badRun = 0;
                end
            end
        end
    elseif inFade
        fadeHolds = fadeHolds + 1;
    end

    frequencyTrace(k) = frequencyState;
    phaseTrace(k) = phaseState;
end

finiteErrors = phaseErrors(isfinite(phaseErrors));
transientMask = isfinite(phaseErrors) & ...
    abs(phaseErrors) >= unlockThreshold;
transientMask(1:min(minAcquireSamples-1,numel(transientMask))) = false;
transientIntervals = localLogicalIntervals(transientMask);
info.Applied = true;
info.Reason = 'GMSK conjugate spectral-line detector plus second-order PLL';
info.SamplesPerSymbol = sps;
info.AcquireLoopBandwidth = acquireBW;
info.TrackLoopBandwidth = trackBW;
info.DetectorTauSymbols = detectorTauSymbols;
info.DetectorInputNormalized = normalizeDetectorInput;
info.DetectorNormalizationFloorDB = detectorNormalizationFloorDB;
info.DetectorFloorLimitedSamples = detectorFloorLimitedSamples;
info.Locked = locked;
info.FinalMode = char(localModeName(locked));
info.LockTransitions = lockTransitions;
info.Reacquisitions = reacquisitions;
info.AcceptedUpdates = accepted;
info.FadeHoldSamples = fadeHolds;
info.PhaseTransientSamples = nnz(transientMask);
info.PhaseTransientIntervalsSamples = transientIntervals;
info.ExternalHoldMaskProvided = externalHoldProvided;
info.ExternalHoldSamples = nnz(externalHoldMask);
info.ExternalHoldFraction = mean(externalHoldMask);
info.UpdateAcceptanceRate = accepted/max(numel(x)-sps,1);
info.FinalFrequency_Hz = frequencyState*sampleRateHz/(2*pi);
info.FrequencyMin_Hz = min(frequencyTrace)*sampleRateHz/(2*pi);
info.FrequencyMax_Hz = max(frequencyTrace)*sampleRateHz/(2*pi);
info.FinalPhase_deg = rad2deg(phaseTrace(end));
if ~isempty(finiteErrors)
    info.MeanAbsPhaseError = mean(abs(finiteErrors));
    info.RMSPhaseError = sqrt(mean(finiteErrors.^2));
end
if localLogical(options, 'debugGMSKSecondOrderPLLTrace', false)
    % Keep the diagnostic opt-in and bounded.  A normal GMSK regression can
    % contain millions of samples, so exporting the full internal traces
    % would retain hundreds of MB after the receiver has finished.
    defaultStride = max(1, 8*sps);
    traceStride = max(1, round(localNumber(options, ...
        'gmskPLLDebugTraceDecimationSamples', defaultStride)));
    traceFirst = 1;
    traceLast = numel(x);
    traceWindow = [];
    if isstruct(options) && isfield(options, ...
            'gmskPLLDebugTraceTimeWindow_s') && ...
            ~isempty(options.gmskPLLDebugTraceTimeWindow_s)
        traceWindow = double(options.gmskPLLDebugTraceTimeWindow_s(:));
    elseif isstruct(options) && isfield(options, ...
            'debugCPMFadeTimeWindow_s') && ...
            ~isempty(options.debugCPMFadeTimeWindow_s)
        traceWindow = double(options.debugCPMFadeTimeWindow_s(:));
    end
    if numel(traceWindow) >= 2 && all(isfinite(traceWindow(1:2)))
        traceWindow = sort(max(0,traceWindow(1:2)));
        traceFirst = max(1,round(traceWindow(1)*sampleRateHz)+1);
        traceLast = min(numel(x),round(traceWindow(2)*sampleRateHz)+1);
    end
    if traceLast < traceFirst
        traceIndex = zeros(0,1);
    else
        traceIndex = (traceFirst:traceStride:traceLast).';
    end
    if ~isempty(traceIndex) && traceIndex(end) ~= traceLast
        traceIndex(end+1,1) = traceLast;
    end
    referenceMagnitude = sqrt(max(referencePower, eps));
    traceMagnitude = abs(x(traceIndex));
    info.DebugTrace = struct( ...
        'SampleIndex', uint32(traceIndex), ...
        'Time_s', (double(traceIndex)-1)/double(sampleRateHz), ...
        'InputMagnitude', traceMagnitude, ...
        'InputMagnitude_dBRelative', 20*log10(max( ...
            traceMagnitude,eps)/referenceMagnitude), ...
        'PhaseCorrection_rad', phaseTrace(traceIndex), ...
        'Frequency_Hz', frequencyTrace(traceIndex)*sampleRateHz/(2*pi), ...
        'DetectorPhaseError_rad', phaseErrors(traceIndex), ...
        'StrideSamples', traceStride, ...
        'SampleRate_Hz', double(sampleRateHz));
end
if localLogical(options, 'debugGMSKSecondOrderPLL', false)
    fprintf(['   [GMSK second-order PLL] mode=%s locked=%d ', ...
        'updates=%.1f%% fadeHold=%d norm=%d floorHits=%d freq=%+.1f Hz ', ...
        'range=[%+.1f,%+.1f] Hz mean|e|=%.4g rad transients=%d/%d\n'], ...
        info.FinalMode, info.Locked, 100*info.UpdateAcceptanceRate, ...
        info.FadeHoldSamples, info.DetectorInputNormalized, ...
        info.DetectorFloorLimitedSamples, info.FinalFrequency_Hz, ...
        info.FrequencyMin_Hz, info.FrequencyMax_Hz, ...
        info.MeanAbsPhaseError,info.PhaseTransientSamples, ...
        size(info.PhaseTransientIntervalsSamples,1));
end
end

function intervals = localLogicalIntervals(mask)
mask = logical(mask(:));
edges = diff([false;mask;false]);
intervals = [find(edges == 1),find(edges == -1)-1];
end

function [kp, ki] = localLoopGains(normalizedBW)
    damping = 1/sqrt(2);
    theta = normalizedBW/(damping + 1/(4*damping));
    denominator = 1 + 2*damping*theta + theta^2;
    kp = (4*damping*theta)/denominator;
    ki = (4*theta^2)/denominator;
end

function value = localNumber(s, name, fallback)
    value = fallback;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        candidate = double(s.(name));
        if isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end

function [mask,provided] = localExternalHoldMask(options,n)
    provided = isstruct(options) && isfield(options,'ExternalHoldMask') && ...
        ~isempty(options.ExternalHoldMask);
    mask = false(n,1);
    if ~provided
        return;
    end
    raw = logical(options.ExternalHoldMask(:));
    if numel(raw) ~= n
        error('HelperGMSKSecondOrderPLL:ExternalHoldMaskLength', ...
            'ExternalHoldMask has %d samples; expected %d.',numel(raw),n);
    end
    mask = raw;
end

function value = localLogical(s, name, fallback)
    value = fallback;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function name = localModeName(locked)
    if locked
        name = "track";
    else
        name = "acquire";
    end
end

function info = localEmptyInfo()
    info = struct( ...
        'Applied',false,'Reason','disabled','SamplesPerSymbol',NaN, ...
        'AcquireLoopBandwidth',NaN,'TrackLoopBandwidth',NaN, ...
        'DetectorTauSymbols',NaN,'DetectorInputNormalized',false, ...
        'DetectorNormalizationFloorDB',NaN, ...
        'DetectorFloorLimitedSamples',0,'Locked',false, ...
        'FinalMode','off','LockTransitions',0,'Reacquisitions',0, ...
        'AcceptedUpdates',0,'FadeHoldSamples',0, ...
        'PhaseTransientSamples',0, ...
        'PhaseTransientIntervalsSamples',zeros(0,2), ...
        'ExternalHoldMaskProvided',false,'ExternalHoldSamples',0, ...
        'ExternalHoldFraction',0, ...
        'UpdateAcceptanceRate',NaN,'FinalFrequency_Hz',NaN, ...
        'FrequencyMin_Hz',NaN,'FrequencyMax_Hz',NaN, ...
        'FinalPhase_deg',NaN,'MeanAbsPhaseError',NaN, ...
        'RMSPhaseError',NaN);
end
