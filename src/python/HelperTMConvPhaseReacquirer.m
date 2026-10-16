function [payload,info] = HelperTMConvPhaseReacquirer(softProvider,rotations,receiverArgs,loseFrames)
%HELPERTMCONVPHASEREACQUIRER Offline, RX-only phase continuity coordinator.
% Each hypothesis decodes the SAME input span with independent continuous
% Viterbi/puncture state. No TX bits, BER, VCFC, or channel identity enters.
% softProvider(k) returns a vector, or a cell array of consecutive chunks.
% Whole-burst candidate decoding is offline; confirmation is then consumed
% in time order. This is NOT a real-time streaming receiver implementation.
% Only phase changes are handled. A different puncture offset or raw frame
% grid is NOT silently treated as a phase change (sample slips need reacquisition).
validateattributes(loseFrames,{'numeric'},{'scalar','integer','positive'});
rotations=double(rotations(:)); nb=numel(rotations);
assert(nb>=1 && all(isfinite(rotations)),'Invalid phase hypotheses.');
banks=cell(nb,1); evidence=cell(nb,1); first=inf(nb,1);
for b=1:nb
    soft=softProvider(b);
    if ~iscell(soft), soft={soft}; end
    peak=0;
    for j=1:numel(soft), peak=max([peak;abs(double(soft{j}(:)))]); end
    rx=HelperTMContinuousConvReceiver(receiverArgs{:},'SoftClip',max(peak,realmin));
    for j=1:numel(soft), rx.append(soft{j}); end
    [banks{b},evidence{b}]=rx.finalize();
    ev=evidence{b}; c=ev.Candidates(ev.SelectedCandidate);
    assert(ev.InputBitsSeen==evidence{1}.InputBitsSeen, ...
        'Phase hypotheses must describe the same coded input span.');
    if ev.Available
        first(b)=c.FirstFrameStart+c.Offset*ev.PunctureInputBits/ev.PunctureOutputBits;
    end
end
% Earliest independently confirmed boundary, not the longest late good run.
[~,anchor]=min(first); info=evidence{anchor};
payload=banks{anchor}(:,[]);
info.Available=false; info.RecoveredFrames=0;
info.PhaseRecovery=struct('Enabled',true,'Mode','offline-rx-evidence', ...
    'Available',false,'SwitchCount',0,'Reason','no confirmed raw ASM boundary', ...
    'FrameSyncTelemetry',struct('Available',false, ...
        'Source','continuous-conv-phase-reacquisition'));
if ~isfinite(first(anchor)), return; end
if nnz(abs(first-first(anchor))<1e-9)>1
    info.Ambiguous=true;
    info.Reason='ambiguous earliest phase acquisition';
    info.PhaseRecovery.Reason=info.Reason;
    return;
end
c0=info.Candidates(info.SelectedCandidate); L=info.FrameLengthRawBits;
minRun=info.MinASMFrames; origin=c0.FirstFrameStart;
n=floor((c0.DecodedBitsAfterTraceback-origin+1)/L);
starts=origin+(0:n-1)'*L; errors=inf(n,nb); columns=zeros(n,nb);
compatible=false(nb,1);
for b=1:nb
    ev=evidence{b}; c=ev.Candidates(ev.SelectedCandidate);
    if ~ev.Available || c.Offset~=c0.Offset || ...
            any(mod(c.FrameStarts-origin,L)~=0)
        continue;
    end
    compatible(b)=true;
    slot=(c.FrameStarts-origin)/L+1;
    keep=slot>=1 & slot<=n; col=find(keep); slot=slot(keep);
    columns(slot,b)=col; errors(slot,b)=c.ASMErrors(keep);
end
good=errors<=info.ASMErrorThreshold;
chosen=zeros(n,1); locked=false(n,1); holdover=false(n,1);
observedErrors=nan(n,1); accepted=false(n,1);
run=zeros(1,nb); active=0; previous=0; badRun=0; lastCommitted=0;
events=struct('ConfirmedSlot',{},'FirstConfirmedRunSlot',{}, ...
    'RunStartBit',{},'ConfirmedAtBit',{},'FromRotation_deg',{},'ToRotation_deg',{});
for k=1:n
    run=(run+1).*good(k,:);
    if active>0
        chosen(k)=active; lastCommitted=k;
        observedErrors(k)=errors(k,active); accepted(k)=good(k,active);
        if good(k,active), badRun=0; else, badRun=badRun+1; end
        holdover(k)=badRun>0 && badRun<loseFrames;
        if badRun>=loseFrames, active=0; end
        locked(k)=active>0;
    end
    if active==0
        qualified=find(run>=minRun);
        if numel(qualified)~=1, continue; end % ambiguity is not a tie-break by BER
        next=qualified(1);
        firstConfirmed=k-minRun+1;
        events(end+1)=struct('ConfirmedSlot',k, ... %#ok<AGROW>
            'FirstConfirmedRunSlot',firstConfirmed, ...
            'RunStartBit',starts(firstConfirmed),'ConfirmedAtBit',starts(k), ...
            'FromRotation_deg',NaN,'ToRotation_deg',rotations(next));
        if previous>0, events(end).FromRotation_deg=rotations(previous); end
        % Confirmation may release pending frames, but never rewrite an
        % already committed erroneous frame using a later/better hypothesis.
        pending=max(firstConfirmed,lastCommitted+1):k;
        chosen(pending)=next;
        observedErrors(pending)=errors(pending,next);
        accepted(pending)=good(pending,next);
        active=next; previous=next; badRun=0; lastCommitted=k;
        locked(k)=true;
    end
end
keep=find(chosen>0); payload=zeros(size(payload,1),numel(keep),'int8');
for j=1:numel(keep)
    k=keep(j); b=chosen(k);
    payload(:,j)=banks{b}(:,columns(k,b));
end
% Expose one canonical physical grid to the existing BER association.
% Candidate state is never transplanted into another decoder.
c=c0; c.FrameStarts=starts(keep); c.ASMErrors=observedErrors(keep);
c.CompleteFrames=numel(keep); c.FirstFrameStart=NaN;
if ~isempty(keep), c.FirstFrameStart=c.FrameStarts(1); end
c.GoodASMCount=nnz(c.ASMErrors<=info.ASMErrorThreshold);
c.LongestGoodRun=localLongestRun(c.ASMErrors<=info.ASMErrorThreshold);
c.MeanASMErrors=mean(c.ASMErrors); c.WorstASMErrors=max(c.ASMErrors);
c.Locked=~isempty(keep);
info.Candidates=c; info.SelectedCandidate=1; info.SelectedOffset=c.Offset;
info.Available=~isempty(keep); info.Ambiguous=false;
info.RecoveredFrames=numel(keep); info.Reason='RX ASM phase continuity';
phase=nan(n,1); phase(keep)=rotations(chosen(keep));
switches=0;
for j=1:numel(events)
    switches=switches+(isfinite(events(j).FromRotation_deg) && ...
        events(j).FromRotation_deg~=events(j).ToRotation_deg);
end
offset=c.Offset*info.PunctureInputBits/info.PunctureOutputBits;
asmLength=L-size(payload,1);
telemetry=struct('Available',n>0,'Source','continuous-conv-phase-reacquisition', ...
    'PositionDomain','decoded-raw-bit','InputFrameLength',L, ...
    'NominalRawBitOffset',offset,'ObservationIndex',(1:n)', ...
    'PeakPosition',starts,'ASMObservationAccepted',accepted,'Locked',locked, ...
    'Holdover',holdover,'Correlation',asmLength-2*observedErrors, ...
    'MinimumCorrelation',repmat(asmLength-2*info.ASMErrorThreshold,n,1), ...
    'PhaseIndex',chosen,'AcquireThresholdFrames',minRun,'LoseThresholdFrames',loseFrames, ...
    'LockRate',mean(locked),'LockedAtEnd',locked(end), ...
    'LockEvents',numel(events),'LossEvents',nnz(diff([false;locked])==-1), ...
    'Reacquisitions',max(0,numel(events)-1));
info.PhaseRecovery=struct('Enabled',true,'Mode','offline-rx-evidence', ...
    'Available',info.Available,'Reason',info.Reason,'SwitchCount',switches, ...
    'Rotations_deg',rotations,'CompatibleCandidates',compatible, ...
    'InputStartBit',starts,'FrameLengthRawBits',L, ...
    'SelectedRotation_deg',phase,'Committed',chosen>0,'Events',events, ...
    'FrameSyncTelemetry',telemetry, ...
    'MissingFramesAfterAcquisition',nnz(chosen==0), ...
    'SingleRotation_deg',NaN);
uniquePhase=unique(phase(isfinite(phase)));
if numel(uniquePhase)==1, info.PhaseRecovery.SingleRotation_deg=uniquePhase; end
end

function n=localLongestRun(mask)
edges=diff([false;mask(:);false]); a=find(edges==1); b=find(edges==-1);
if isempty(a), n=0; else, n=max(b-a); end
end
