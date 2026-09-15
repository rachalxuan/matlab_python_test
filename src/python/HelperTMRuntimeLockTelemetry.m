function telemetry = HelperTMRuntimeLockTelemetry(cfg)
%HELPERTMRUNTIMELOCKTELEMETRY Build receiver-observable lock timelines.
%
% This helper is diagnostic only.  It never changes carrier, timing, frame
% synchronization, demodulation, or decoding samples.  "Runtime" means
% simulation time, not wall-clock GUI execution time.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
options = localStruct(cfg,'Options');
statusPeriod = 1e-3*localNumber(options,'runtimeStatusUpdateMs',200);
statusPeriod = max(statusPeriod,eps);

telemetry = struct( ...
    'Enabled',true, ...
    'Meaning',['time-indexed receiver telemetry; the display period is ', ...
        'not the synchronization-loop update period'], ...
    'StatusUpdatePeriod_s',statusPeriod, ...
    'Carrier',localEmptyTrack('carrier'), ...
    'Timing',localEmptyTrack('timing'), ...
    'Frame',localEmptyTrack('frame'));

telemetry.Carrier = localCarrierTrack(cfg,options,statusPeriod);
telemetry.Timing = localTimingTrack(cfg,options,statusPeriod);
telemetry.Frame = localFrameTrack(cfg,statusPeriod);
% Unmeasured burst-continuation data must not change the reported end of
% the observation window. This clips telemetry only, never receiver samples.
observationEnd = localNumber(cfg,'ObservationEndTime_s',Inf);
telemetry.ObservationEndTime_s = observationEnd;
if isfinite(observationEnd)
    names={'Carrier','Timing','Frame'};
    for k=1:numel(names)
        track=telemetry.(names{k});
        if ~track.Available, continue; end
        keep=track.Time_s<=observationEnd;
        if ~any(keep)
            track=localEmptyTrack(names{k});
            track.Reason='no lock observations inside the measured burst';
        else
            fields={'Time_s','State','EvidenceGood','Quality'};
            for j=1:numel(fields), track.(fields{j})=track.(fields{j})(keep); end
            track.FirstLockTime_s=NaN;
            track=localFinalizeTrack(track,statusPeriod);
        end
        telemetry.(names{k})=track;
    end
end
end

function track = localCarrierTrack(cfg,options,statusPeriod)
track = localEmptyTrack('carrier');
symbolRate = localNumber(cfg,'SymbolRateHz',NaN);
modulation = upper(string(localText(cfg,'Modulation','')));

% Prefer the actual feed-forward phase-search reliability decisions.  They
% are receiver-observable and already operate at the carrier estimator's
% native block cadence.
qamState = localStruct(cfg,'QAMBlindPhaseState');
if localValidBPSTrace(qamState)
    track = localTrackFromBPS(qamState,symbolRate,options, ...
        'QAM feed-forward BPS reliability',statusPeriod);
    return;
end

apskState = localStruct(cfg,'PilotlessAPSKState');
if isfield(apskState,'Carrier') && isstruct(apskState.Carrier) && ...
        isfield(apskState.Carrier,'BlindPhaseSearch')
    apskBPS = apskState.Carrier.BlindPhaseSearch;
    if localValidBPSTrace(apskBPS)
        track = localTrackFromBPS(apskBPS,symbolRate,options, ...
            'APSK feed-forward BPS reliability',statusPeriod);
        return;
    end
end

gmskInfo = localStruct(cfg,'GMSKSecondOrderPLLInfo');
if isfield(gmskInfo,'RuntimeLockTrace') && ...
        isstruct(gmskInfo.RuntimeLockTrace) && ...
        localLogical(gmskInfo.RuntimeLockTrace,'Available',false)
    source = gmskInfo.RuntimeLockTrace;
    track.Available = true;
    track.Source = 'GMSK conjugate-line PLL lock detector';
    track.Cadence = 'PLL diagnostic decimation';
    track.Time_s = double(source.Time_s(:));
    track.EvidenceGood = logical(source.EvidenceGood(:));
    track.State = logical(source.Locked(:));
    track.Quality = double(source.ErrorState_rad(:));
    track.QualityName = 'decimated absolute PLL detector phase error (rad)';
    track.Threshold = localNumber(source,'UnlockThreshold_rad',NaN);
    track = localFinalizeTrack(track,statusPeriod);
    return;
end

if any(contains(modulation,["MSK","GMSK"]))
    track.Source = 'unavailable';
    track.Reason = ['the selected CPM path has no observable continuous ', ...
        'carrier-lock trace'];
    return;
end

signal = localVector(cfg,'CarrierSignal');
reference = localVector(cfg,'ReferenceConstellation');
if isempty(signal) || isempty(reference) || ~isfinite(symbolRate) || ...
        symbolRate <= 0
    track.Reason = 'no carrier detector trace or symbol-rate constellation';
    return;
end

windowSymbols = max(8,round(localNumber(options, ...
    'runtimeCarrierWindowSymbols',64)));
maxNormalizedError = max(0.01,localNumber(options, ...
    'runtimeCarrierMaxNormalizedError',0.45));
[time,quality] = localConstellationWindowMetric( ...
    signal,reference,windowSymbols,symbolRate);
good = isfinite(quality) & quality <= maxNormalizedError;
state = localHysteresis(good, ...
    localNumber(options,'runtimeCarrierAcquireWindows',3), ...
    localNumber(options,'runtimeCarrierLoseWindows',2));
track.Available = ~isempty(time);
track.Source = 'post-carrier nearest-constellation reliability';
track.Cadence = sprintf('%d-symbol non-overlapping windows',windowSymbols);
track.Reason = ['lock is modulo the constellation rotational symmetry; ', ...
    'frame lock must detect a quadrant/cycle slip'];
track.Time_s = time;
track.EvidenceGood = good;
track.State = state;
track.Quality = quality;
track.QualityName = 'trimmed RMS error / minimum constellation distance';
track.Threshold = maxNormalizedError;
track = localFinalizeTrack(track,statusPeriod);
end

function track = localTrackFromBPS(state,symbolRate,options,label,statusPeriod)
track = localEmptyTrack('carrier');
centers = double(state.Centers(:));
good = logical(state.Reliable(:));
n = min(numel(centers),numel(good));
centers = centers(1:n);
good = good(1:n);
quality = nan(n,1);
if isfield(state,'BestMetric')
    raw = double(state.BestMetric(:));
    quality(1:min(n,numel(raw))) = raw(1:min(n,numel(raw)));
end
stateTrace = localHysteresis(good, ...
    localNumber(options,'runtimeCarrierAcquireWindows',3), ...
    localNumber(options,'runtimeCarrierLoseWindows',2));
track.Available = n > 0 && isfinite(symbolRate) && symbolRate > 0;
track.Source = label;
track.Cadence = 'native BPS block centers';
track.Time_s = (centers-1)/max(symbolRate,eps);
track.EvidenceGood = good;
track.State = stateTrace;
track.Quality = quality;
track.QualityName = 'BPS nearest-constellation metric';
track.Threshold = NaN;
track = localFinalizeTrack(track,statusPeriod);
end

function track = localTimingTrack(cfg,options,statusPeriod)
track = localEmptyTrack('timing');
timingError = localVector(cfg,'TimingErrorTrace');
symbolRate = localNumber(cfg,'SymbolRateHz',NaN);
if isempty(timingError) || ~isfinite(symbolRate) || symbolRate <= 0
    track.Source = localText(cfg,'TimingSource','unavailable');
    track.Reason = localText(cfg,'TimingUnavailableReason', ...
        'selected receiver path does not expose a continuous timing error');
    return;
end

windowSymbols = max(8,round(localNumber(options, ...
    'runtimeTimingWindowSymbols',64)));
maxRMS = max(1e-5,localNumber(options,'runtimeTimingMaxJitterRMS',0.02));
% comm.SymbolSynchronizer returns a normalized fractional timing estimate
% on [0,1].  Its absolute value is an arbitrary sampling phase, not an
% error-to-zero.  Lock evidence is therefore the short-window jitter of
% its circular increment; a wrap from 1 back to 0 is not a loss of lock.
timingIncrement = [0;angle(exp(1j*2*pi*diff(timingError)))/(2*pi)];
nWindow = floor(numel(timingError)/windowSymbols);
time = zeros(nWindow,1);
quality = nan(nWindow,1);
for k = 1:nWindow
    index = (k-1)*windowSymbols+(1:windowSymbols);
    value = double(timingIncrement(index));
    value = value(isfinite(value));
    time(k) = (mean(index)-1)/symbolRate;
    if ~isempty(value)
        centered = abs(value-median(value));
        centered = sort(centered.^2);
        keep = max(1,floor(0.90*numel(centered)));
        quality(k) = sqrt(mean(centered(1:keep)));
    end
end
good = isfinite(quality) & quality <= maxRMS;
state = localHysteresis(good, ...
    localNumber(options,'runtimeTimingAcquireWindows',3), ...
    localNumber(options,'runtimeTimingLoseWindows',2));
track.Available = nWindow > 0;
track.Source = localText(cfg,'TimingSource','Gardner timing-error detector');
track.Cadence = sprintf('%d-symbol non-overlapping windows',windowSymbols);
track.Time_s = time;
track.EvidenceGood = good;
track.State = state;
track.Quality = quality;
track.QualityName = ...
    'fractional-timing increment jitter RMS (symbols/update)';
track.Threshold = maxRMS;
track = localFinalizeTrack(track,statusPeriod);
end

function track = localFrameTrack(cfg,statusPeriod)
track = localEmptyTrack('frame');
frame = localStruct(cfg,'FrameSyncTelemetry');
if ~localLogical(frame,'Available',false)
    track.Source = localText(frame,'Source','unavailable');
    track.Reason = ['no receiver ASM observations were exported for the ', ...
        'selected decoder path'];
    return;
end
frameDuration = localNumber(cfg,'FrameDuration_s',NaN);
index = localVector(frame,'ObservationIndex');
locked = localLogicalVector(frame,'Locked');
accepted = localLogicalVector(frame,'ASMObservationAccepted');
n = min([numel(index),numel(locked),numel(accepted)]);
if n < 1
    return;
end
index = index(1:n);
if isfinite(frameDuration) && frameDuration > 0
    time = (index-0.5)*frameDuration;
else
    time = index;
end
quality = nan(n,1);
if isfield(frame,'Correlation')
    raw = double(frame.Correlation(:));
    quality(1:min(n,numel(raw))) = raw(1:min(n,numel(raw)));
end
track.Available = true;
track.Source = localText(frame,'Source','decoder ASM state machine');
track.Cadence = 'one receiver ASM observation per decoded frame';
track.Time_s = time;
track.EvidenceGood = accepted(1:n);
track.State = locked(1:n);
track.Quality = quality;
track.QualityName = 'normalized soft ASM correlation';
track.Threshold = localFirstFinite(frame,'MinimumCorrelation',NaN);
track = localFinalizeTrack(track,statusPeriod);
end

function [time,quality] = localConstellationWindowMetric( ...
        signal,reference,windowSymbols,symbolRate)
signal = complex(signal(:));
reference = complex(reference(:));
signal = signal(isfinite(real(signal)) & isfinite(imag(signal)));
reference = reference(isfinite(real(reference)) & isfinite(imag(reference)));
nWindow = floor(numel(signal)/windowSymbols);
time = zeros(nWindow,1);
quality = nan(nWindow,1);
if nWindow < 1 || isempty(reference)
    return;
end
reference = reference/sqrt(mean(abs(reference).^2)+eps);
distance = abs(reference-reference.');
distance(distance == 0) = inf;
minimumDistance = min(distance(:));
signal = signal/sqrt(mean(abs(signal).^2)+eps);
for k = 1:nWindow
    index = (k-1)*windowSymbols+(1:windowSymbols);
    z = signal(index);
    nearestDistance = min(abs(z-reference.'),[],2);
    nearestDistance = sort(nearestDistance.^2);
    keep = max(1,floor(0.90*numel(nearestDistance)));
    quality(k) = sqrt(mean(nearestDistance(1:keep))) / ...
        max(minimumDistance,eps);
    time(k) = (mean(index)-1)/symbolRate;
end
end

function state = localHysteresis(good,acquireCount,loseCount)
good = logical(good(:));
acquireCount = max(1,round(double(acquireCount)));
loseCount = max(1,round(double(loseCount)));
state = false(size(good));
locked = false;
goodRun = 0;
badRun = 0;
for k = 1:numel(good)
    if good(k)
        goodRun = goodRun+1;
        badRun = 0;
        if ~locked && goodRun >= acquireCount
            locked = true;
        end
    else
        goodRun = 0;
        badRun = badRun+1;
        if locked && badRun >= loseCount
            locked = false;
        end
    end
    state(k) = locked;
end
end

function track = localFinalizeTrack(track,statusPeriod)
if ~track.Available || isempty(track.State)
    return;
end
track.Time_s = double(track.Time_s(:));
track.State = logical(track.State(:));
track.EvidenceGood = logical(track.EvidenceGood(:));
track.Quality = double(track.Quality(:));
edges = diff([false;track.State]);
lockIndex = find(edges == 1);
lossIndex = find(edges == -1);
track.LockEvents = numel(lockIndex);
track.LossEvents = numel(lossIndex);
track.Reacquisitions = max(0,numel(lockIndex)-1);
track.LockRate = mean(double(track.State));
track.LockedAtEnd = track.State(end);
if ~isempty(lockIndex)
    track.FirstLockTime_s = track.Time_s(lockIndex(1));
end
reacquisition = nan(numel(lossIndex),1);
reacquisitionCount = 0;
for k = 1:numel(lossIndex)
    nextLock = lockIndex(lockIndex > lossIndex(k));
    if ~isempty(nextLock)
        reacquisitionCount = reacquisitionCount+1;
        reacquisition(reacquisitionCount) = ...
            track.Time_s(nextLock(1))-track.Time_s(lossIndex(k));
    end
end
track.ReacquisitionTime_s = reacquisition(1:reacquisitionCount);

tEnd = track.Time_s(end);
displayTime = unique([0;(0:statusPeriod:tEnd).';tEnd]);
displayState = false(size(displayTime));
for k = 1:numel(displayTime)
    prior = find(track.Time_s <= displayTime(k),1,'last');
    if ~isempty(prior)
        displayState(k) = track.State(prior);
    end
end
track.DisplayTime_s = displayTime;
track.DisplayState = displayState;
end

function track = localEmptyTrack(name)
track = struct( ...
    'Name',char(name), ...
    'Available',false, ...
    'Source','unavailable', ...
    'Cadence','', ...
    'Reason','', ...
    'Time_s',zeros(0,1), ...
    'EvidenceGood',false(0,1), ...
    'State',false(0,1), ...
    'Quality',zeros(0,1), ...
    'QualityName','', ...
    'Threshold',NaN, ...
    'LockRate',NaN, ...
    'LockedAtEnd',false, ...
    'LockEvents',0, ...
    'LossEvents',0, ...
    'Reacquisitions',0, ...
    'FirstLockTime_s',NaN, ...
    'ReacquisitionTime_s',zeros(0,1), ...
    'DisplayTime_s',zeros(0,1), ...
    'DisplayState',false(0,1));
end

function tf = localValidBPSTrace(state)
tf = isstruct(state) && isfield(state,'Centers') && ...
    isfield(state,'Reliable') && ~isempty(state.Centers) && ...
    numel(state.Centers) == numel(state.Reliable);
end

function s = localStruct(parent,name)
s = struct();
if isstruct(parent) && isfield(parent,name) && isstruct(parent.(name))
    s = parent.(name);
end
end

function value = localNumber(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    raw = double(s.(name));
    if isscalar(raw) && isfinite(raw)
        value = raw;
    end
end
end

function value = localText(s,name,defaultValue)
value = char(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = char(string(s.(name)));
end
end

function value = localLogical(s,name,defaultValue)
value = logical(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = logical(s.(name)(1));
end
end

function value = localVector(s,name)
value = zeros(0,1);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = s.(name)(:);
end
end

function value = localLogicalVector(s,name)
value = false(0,1);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = logical(s.(name)(:));
end
end

function value = localFirstFinite(s,name,defaultValue)
value = defaultValue;
raw = localVector(s,name);
raw = double(raw(isfinite(raw)));
if ~isempty(raw)
    value = raw(1);
end
end
