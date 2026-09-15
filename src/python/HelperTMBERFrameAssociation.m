function association = HelperTMBERFrameAssociation(decodedBits,txFrames,positions,minRun,maxAnchorBER)
%HELPERTMBERFRAMEASSOCIATION OFFLINE reference pairing, never RX feedback.
% A reliable consecutive run establishes one immutable TX/physical-slot
% offset. Thereafter corrupted VCFC/payload bits CANNOT select a new TX frame
% or measurement window. Missing decoder outputs retain their physical gaps.
% A non-integral bit realignment starts a new segment requiring a new anchor.
if nargin<4, minRun=3; end
if nargin<5, maxAnchorBER=.1; end
bpf=numel(txFrames{1}); nr=floor(numel(decodedBits)/bpf);
association=struct('Available',false,'Method','physical-slot-anchored', ...
    'Reason','decoder did not supply physical frame positions', ...
    'TxFrameIndex',nan(nr,1),'PhysicalSlotIndex',nan(nr,1), ...
    'SegmentIndex',zeros(nr,1),'AnchorRxIndex',nan(nr,1), ...
    'DecodedVCFC',nan(nr,1),'ExpectedVCFC',nan(nr,1), ...
    'VCFCValid',nan(nr,1),'InputStartBit',nan(nr,1), ...
    'BeyondReference',false(nr,1));
if ~isstruct(positions) || ~isfield(positions,'Available') || ~positions.Available
    return;
end
association.Available=true;
association.Reason='no verified physical-slot anchor';
start=double(positions.InputStartBit(:)); L=double(positions.InputFrameLength);
if numel(start)~=nr || ~isscalar(L) || ~isfinite(L) || L<=0 || bpf<32
    association.Reason='decoded output and physical position dimensions disagree';
    return; % Available but unmapped: never fall back to corrupted headers.
end
association.InputStartBit=start;
if nr==0, return; end
rx=reshape(double(decodedBits(1:nr*bpf)),bpf,nr);
weights=2.^(7:-1:0);
rxId=(weights*rx(25:32,:)).';
txId=cellfun(@(v) weights*double(reshape(v(25:32),[],1)),txFrames(:));
association.DecodedVCFC=rxId;
catalog=cell(256,1);
for i=1:numel(txFrames), catalog{txId(i)+1}(end+1)=i; end
candidate=nan(nr,1);
% Header is only a candidate lookup for the INITIAL anchor. The full known
% test sequence distinguishes VCFC wraparound; equal-distance ties are unknown.
for i=1:nr
    if ~isfinite(start(i)), continue; end
    ids=catalog{rxId(i)+1}; distances=inf(size(ids));
    for k=1:numel(ids)
        distances(k)=nnz(rx(:,i)~=double(txFrames{ids(k)}(:)));
    end
    if isempty(ids), continue; end
    best=min(distances); winner=find(distances==best);
    if numel(winner)==1 && best/bpf<=maxAnchorBER
        candidate(i)=ids(winner);
    end
end
segment=0; slot=NaN; previous=NaN;
for i=1:nr
    if ~isfinite(start(i)), previous=NaN; continue; end
    step=(start(i)-previous)/L;
    if ~isfinite(step) || step<=0 || abs(step-round(step))>1e-8
        segment=segment+1; slot=0;
    else
        slot=slot+round(step);
    end
    association.SegmentIndex(i)=segment;
    association.PhysicalSlotIndex(i)=slot;
    previous=start(i);
end
minRun=max(2,round(minRun));
for s=1:segment
    indices=find(association.SegmentIndex==s);
    slots=association.PhysicalSlotIndex(indices);
    count=0; offset=NaN; anchor=NaN;
    for j=1:numel(indices)
        i=indices(j); proposed=candidate(i)-slots(j);
        if ~isfinite(proposed)
            count=0; offset=NaN;
        elseif count>0 && proposed==offset && slots(j)==slots(j-1)+1
            count=count+1;
        else
            count=1; offset=proposed;
        end
        if count>=minRun, anchor=i; break; end
    end
    if ~isfinite(anchor), continue; end
    mapped=slots+offset;
    association.BeyondReference(indices)=mapped>numel(txFrames);
    valid=mapped>=1 & mapped<=numel(txFrames);
    ii=indices(valid); mapped=mapped(valid);
    association.TxFrameIndex(ii)=mapped;
    association.AnchorRxIndex(ii)=anchor;
    association.ExpectedVCFC(ii)=txId(mapped);
    association.VCFCValid(ii)=double(rxId(ii)==txId(mapped));
end
if any(isfinite(association.TxFrameIndex))
    association.Reason='reference follows input position; VCFC is diagnostic only after anchoring';
end
end
