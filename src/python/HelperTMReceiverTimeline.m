function monitor = HelperTMReceiverTimeline(observationSets,locks,duration,countedFrames,frameErrors,ber)
%HELPERTMRECEIVERTIMELINE Selected-hypothesis, offline receiver accounting.
% Frames with no comparable output NEVER become zero-error observations.
% Counters cover the decoded transfer frame, INCLUDING its header (or TPC
% diagnostics if that decoder was explicitly selected by the caller).
% This function neither processes samples nor claims streaming reception.
monitor = struct('SchemaVersion',1,'Mode','offline-simulation-timeline', ...
    'Available',false,'Reason','','TimeReference', ...
    'uniform transmitted-frame grid over actual generated waveform duration', ...
    'TimeAlignment','approximate: RX lock traces retain pipeline latency', ...
    'FrameAssociation',['see Observations.Association for each lane: physical-slot ', ...
    'anchored where decoder provenance is available; otherwise legacy matching'], ...
    'LockMeaning','receiver quality/ASM evidence, not proof of correct bits', ...
    'LossMeaning',['missing-in-observed-span is a TX frame not recovered between ', ...
    'two recovered frames; not proof of its physical loss mechanism'], ...
    'Rows',struct([]),'Observations',{observationSets},'LockTracks',locks, ...
    'Summary',struct());
if isempty(observationSets)
    monitor.Reason = 'selected decoder route did not export frame observations';
    return;
end
if ~isscalar(duration) || ~isfinite(duration) || duration<=0
    monitor.Reason = 'no valid generated waveform duration';
    return;
end
laneTables=cell(numel(observationSets),1);
unmatched=0; matchedObservations=0; nonforwardMatches=0; physicalLanes=0; vcfcErrors=0; guardObservations=0;
for laneIndex=1:numel(observationSets)
    obs=observationSets{laneIndex};
    if isfield(obs,'Association') && obs.Association.Available
        physicalLanes=physicalLanes+1;
        vcfcErrors=vcfcErrors+nnz(obs.Association.VCFCValid==0);
    end
    n=obs.ExpectedFrames; bpf=obs.PayloadBitsPerFrame;
    assert(n>=1 && n==floor(n) && bpf>0 && bpf==floor(bpf), ...
        'ReceiverTimeline:InvalidSize','Invalid frame dimensions.');
    rx=double(obs.RxFrameIndex(:)); tx=double(obs.TxFrameIndex(:));
    err=double(obs.ErrorBits(:)); counted=logical(obs.Counted(:));
    assert(numel(rx)==numel(tx) && numel(tx)==numel(err) && numel(err)==numel(counted), ...
        'ReceiverTimeline:InvalidObservations','Observation lengths disagree.');
    matched=isfinite(tx) & tx>=1 & tx<=n & tx==floor(tx) & ...
        isfinite(err) & err>=0 & err<=bpf & err==floor(err);
    assert(~any(counted & ~matched),'ReceiverTimeline:CountedUnmatched', ...
        'A counted frame must have a valid matched TX frame and error count.');
    measured=(1:n).'>=obs.FirstMeasurementFrame;
    assert(~any(counted & tx<obs.FirstMeasurementFrame), ...
        'ReceiverTimeline:Warmup','Excluded warm-up frame was counted.');
    matchedObservations=matchedObservations+nnz(matched);
    beyond=false(size(matched));
    if isfield(obs,'Association') && isfield(obs.Association,'BeyondReference')
        beyond=obs.Association.BeyondReference(:);
    end
    unmatched=unmatched+nnz(~matched & ~beyond);
    guardObservations=guardObservations+nnz(beyond);
    nonforwardMatches=nonforwardMatches+nnz(diff(tx(matched))<=0);
    recoveredCount=accumarray(tx(matched),1,[n 1]);
    comparisons=accumarray(tx(counted),1,[n 1]);
    errors=accumarray(tx(counted),err(counted),[n 1]);
    badFrames=accumarray(tx(counted),double(err(counted)>0),[n 1]);
    bits=comparisons*bpf;
    firstRx=nan(n,1); observedErrors=nan(n,1);
    decodedVCFC=nan(n,1); expectedVCFC=nan(n,1); vcfcValid=nan(n,1);
    for oi=find(matched).'
        ti=tx(oi);
        if isnan(firstRx(ti)), firstRx(ti)=rx(oi); observedErrors(ti)=0; end
        observedErrors(ti)=observedErrors(ti)+err(oi);
        if isfield(obs,'Association') && obs.Association.Available && recoveredCount(ti)==1
            decodedVCFC(ti)=obs.Association.DecodedVCFC(oi);
            expectedVCFC(ti)=obs.Association.ExpectedVCFC(oi);
            vcfcValid(ti)=obs.Association.VCFCValid(oi);
        end
    end
    recovered=recoveredCount>0;
    coverage=repmat("no-frame-recovered",n,1);
    recoveredIds=find(recovered);
    if ~isempty(recoveredIds)
        coverage(1:recoveredIds(1)-1)="unobserved-leading";
        coverage(recoveredIds(end)+1:end)="unobserved-trailing";
        coverage(recoveredIds(1):recoveredIds(end))="missing-in-observed-span";
    end
    coverage(recovered & comparisons==0)="recovered-not-counted";
    coverage(comparisons>0 & errors==0)="compared-clean";
    coverage(comparisons>0 & errors>0)="compared-errors";
    missing=measured & ~recovered;
    gaps=missing & coverage=="missing-in-observed-span";
    boundary=missing & coverage~="missing-in-observed-span";
    starts=(0:n-1).'*duration/n; ends=(1:n).'*duration/n;
    localBER=nan(n,1); localBER(bits>0)=errors(bits>0)./bits(bits>0);
    laneTables{laneIndex}=table(repmat(string(obs.Lane),n,1),(1:n).', ...
        starts,ends,firstRx,measured,coverage,recoveredCount,observedErrors, ...
        comparisons,bits,errors,badFrames,localBER,measured*bpf, ...
        double(missing),double(gaps),double(boundary),decodedVCFC,expectedVCFC,vcfcValid, ...
        'VariableNames',{'Lane','TxFrameIndex','TimeStart_s','TimeEnd_s', ...
        'FirstRxFrameIndex','MeasurementEligible','Coverage','RecoveredCopies', ...
        'ObservedErrorBits','ComparedFramesDelta','ComparedBitsDelta', ...
        'ErrorBitsDelta','ErrorFramesDelta','FrameBER','ExpectedBitsDelta', ...
        'UnrecoveredFramesDelta','MissingWithinSpanDelta','BoundaryUnobservedDelta', ...
        'DecodedVCFC','ExpectedVCFC','VCFCValid'});
end
T=sortrows(vertcat(laneTables{:}),{'TimeEnd_s','Lane','TxFrameIndex'});
% Equal-time I/Q rows form one publication group for any future live adapter.
% Do not publish a partial group as though the other rail were already done.
T.CumulativeComparedBits=cumsum(T.ComparedBitsDelta);
T.CumulativeErrorBits=cumsum(T.ErrorBitsDelta);
T.CumulativeComparedFrames=cumsum(T.ComparedFramesDelta);
T.CumulativeErrorFrames=cumsum(T.ErrorFramesDelta);
T.CumulativeExpectedBits=cumsum(T.ExpectedBitsDelta);
T.CumulativeUnrecoveredFrames=cumsum(T.UnrecoveredFramesDelta);
T.CumulativeMissingWithinSpan=cumsum(T.MissingWithinSpanDelta);
T.CumulativeBoundaryUnobserved=cumsum(T.BoundaryUnobservedDelta);
T.CumulativeBER=nan(height(T),1);
valid=T.CumulativeComparedBits>0;
T.CumulativeBER(valid)=T.CumulativeErrorBits(valid)./T.CumulativeComparedBits(valid);
trackNames={'Carrier','Timing','Frame'};
for ti=1:numel(trackNames)
    name=trackNames{ti};
    [state,rate,quality,changes,age]=localLockWindows(locks,name,T.TimeStart_s,T.TimeEnd_s);
    T.([name 'LastObservedState'])=state;
    T.([name 'EvidenceAge_s'])=age;
    T.([name 'LockFraction'])=rate;
    T.([name 'MeanQuality'])=quality;
    T.([name 'Transitions'])=changes;
end
assert(sum(T.ComparedFramesDelta)==countedFrames && sum(T.ErrorFramesDelta)==frameErrors, ...
    'ReceiverTimeline:CounterMismatch','Timeline and selected BER/FER counters disagree.');
actualBER=T.CumulativeBER(end);
% Some legacy paths deliberately return a failure sentinel even when bits
% exist (e.g. only one I/Q rail measured). Preserve and explicitly label it.
berMatches=isfinite(actualBER) && isfinite(ber) && abs(actualBER-ber)<1e-12;
monitor.Available=true;
monitor.Rows=table2struct(T);
monitor.MeasurementCoverage=HelperTMMeasurementCoverage(observationSets);
monitor.Summary=struct('ComparedBits',sum(T.ComparedBitsDelta), ...
    'ErrorBits',sum(T.ErrorBitsDelta),'ComparedFrames',countedFrames, ...
    'ErrorFrames',frameErrors,'MeasuredBER',actualBER,'LegacyBER',ber, ...
    'LegacyBERMatchesCounters',berMatches, ...
    'MeasurementExpectedFrames',nnz(T.MeasurementEligible), ...
    'MeasurementRecoveredFrames',nnz(T.MeasurementEligible & T.RecoveredCopies>0), ...
    'UnrecoveredMeasurementFrames',sum(T.UnrecoveredFramesDelta), ...
    'MissingWithinObservedSpan',sum(T.MissingWithinSpanDelta), ...
    'BoundaryOrUnlocalizedMissing',sum(T.BoundaryUnobservedDelta), ...
    'UnmatchedRxFrames',unmatched,'MatchedRxObservations',matchedObservations, ...
    'BeyondReferenceRxFrames',guardObservations, ...
    'DuplicateRecoveredFrames',sum(max(0,T.RecoveredCopies-1)), ...
    'NonForwardRxMatches',nonforwardMatches, ...
    'FrameAssociationSuspect',nonforwardMatches>0 || any(T.RecoveredCopies>1), ...
    'PhysicalAssociationLanes',physicalLanes,'VCFCDisagreements',vcfcErrors, ...
    'Duration_s',duration);
end

function [lastState,fraction,qualityMean,transitions,age]=localLockWindows(locks,name,starts,ends)
n=numel(starts);
lastState=nan(n,1); fraction=nan(n,1); qualityMean=nan(n,1);
transitions=nan(n,1); age=nan(n,1);
if ~isfield(locks,name), return; end
track=locks.(name);
if ~isfield(track,'Available') || ~track.Available || isempty(track.Time_s), return; end
time=double(track.Time_s(:)); state=double(track.State(:));
quality=double(track.Quality(:));
assert(numel(time)==numel(state) && numel(state)==numel(quality) && ...
    all(diff(time)>=0),'ReceiverTimeline:LockTrace','Malformed lock timeline.');
edge=[false;diff(state)~=0];
% Report last OBSERVED state plus evidence age, never an asserted live lock.
% A consumer must not interpret an indefinitely stale green state as success.
if numel(time)>1
    latest=interp1(time,(1:numel(time)).',ends,'previous',NaN);
    latest(ends>=time(end))=numel(time);
else
    latest=nan(n,1); latest(ends>=time)=1;
end
known=isfinite(latest);
lastState(known)=state(latest(known));
age(known)=ends(known)-time(latest(known));
for i=1:n
    take=time>=starts(i) & time<ends(i);
    if ~any(take), continue; end
    fraction(i)=mean(state(take));
    qualityMean(i)=mean(quality(take),'omitnan');
    transitions(i)=nnz(edge(take));
end
end
