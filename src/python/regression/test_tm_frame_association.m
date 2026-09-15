function report = test_tm_frame_association(runReceiver)
% Deterministic accounting faults, without H sweeps or decoder retuning.
if nargin<1, runReceiver=false; end
addpath(fileparts(fileparts(mfilename('fullpath'))));
rng(31415,'twister'); bpf=256; n=300;
tx=cell(n,1);
for k=1:n
    tx{k}=int8(randi([0 1],bpf,1));
    tx{k}(25:32)=int8(bitget(mod(k-1,256),8:-1:1));
end
L=400; ids=(1:60).'; rx=tx(ids);
% User's failure: physical frame 12 has VCFC=43 during the first 30 frames.
rx{12}(25:32)=int8(bitget(43,8:-1:1));
% The same defect in the measurement region must remain in BER, not vanish.
rx{40}(25:32)=int8(bitget(3,8:-1:1));
rx{41}=1-rx{41}; % Even a completely wrong measured frame must remain counted.
p=struct('Available',true,'InputStartBit',127+(ids-1)*L,'InputFrameLength',L);
a=HelperTMBERFrameAssociation(vertcat(rx{:}),tx,p,3,.1);
assert(isequal(a.TxFrameIndex,ids));
assert(a.VCFCValid(12)==0 && a.TxFrameIndex(12)<=30);
assert(a.VCFCValid(40)==0 && a.TxFrameIndex(40)>30);
err=cellfun(@(x,y) nnz(x~=y),rx,tx(ids));
assert(a.TxFrameIndex(41)==41 && ...
    sum(err(a.TxFrameIndex>30))==nnz(rx{40}~=tx{40})+bpf);
% Decoder omits physical slot 35. Slot 36 must NOT become TX35.
keep=ids~=35; p.InputStartBit=p.InputStartBit(keep);
gap=HelperTMBERFrameAssociation(vertcat(rx{keep}),tx,p,3,.1);
assert(isequal(gap.TxFrameIndex,ids(keep)) && ~any(gap.TxFrameIndex==35));
% First recovered frame is TX21: warm-up still ends at TX30, not RX30.
ids=(21:60).'; p.InputStartBit=127+(0:numel(ids)-1).'*L;
late=HelperTMBERFrameAssociation(vertcat(tx{ids}),tx,p,3,.1);
assert(isequal(late.TxFrameIndex,ids) && nnz(late.TxFrameIndex>30)==30);
% VCFC wraps but absolute reference indices must not wrap or jump cycles.
ids=(245:280).'; p.InputStartBit=127+(0:numel(ids)-1).'*L;
wrap=HelperTMBERFrameAssociation(vertcat(tx{ids}),tx,p,3,.1);
assert(isequal(wrap.TxFrameIndex,ids));
% A non-integral re-alignment begins a segment, not a guessed +1 frame.
ids=[(1:8)';(15:25)']; p.InputStartBit=127+(ids-1)*L;
p.InputStartBit(9:end)=p.InputStartBit(9:end)+2;
reacq=HelperTMBERFrameAssociation(vertcat(tx{ids}),tx,p,3,.1);
assert(isequal(reacq.TxFrameIndex,ids) && max(reacq.SegmentIndex)==2);
% Ambiguous/no anchor: do not count garbage just because an ID is in range.
garbage=zeros(6*bpf,1,'int8'); p.InputStartBit=(1:L:6*L).';
unknown=HelperTMBERFrameAssociation(garbage,tx,p,3,.1);
assert(unknown.Available && all(isnan(unknown.TxFrameIndex)));
fprintf('Physical frame association: 6 fault/accounting checks passed.\n');
% Exercise REAL decoder omission and buffering, not just synthetic positions.
args={'Modulation','QPSK','ChannelCoding','RS', ...
    'RSMessageLength',223,'RSInterleavingDepth',1,'IsRSMessageShortened',false, ...
    'HasASM',true,'RandomizerEnabled',false, ...
    'FrameSyncLockThreshold',1,'FrameSyncUnlockThreshold',1};
asm=int8(reshape(dec2bin(hex2dec('1ACFFC1D'),32)-'0',[],1));
rsFrames=cell(9,1); softFrames=zeros(2072,9);
for k=1:9
    f=int8(randi([0 1],1784,1)); f(25:32)=int8(bitget(k-1,8:-1:1));
    rsFrames{k}=f;
    encoded=ccsdsRSEncode(logical(f),223,1,223);
    softFrames(:,k)=2*double([asm;encoded])-1;
end
damaged=softFrames; damaged(:,6)=0;
decoder=HelperCCSDSTMDecoder(args{:}); bits=decoder(damaged(:));
pos=decoder.getDecodedFramePositions();
expected=[1:5 7:9].';
assert(isequal(pos.InputStartBit,1+(expected-1)*2072));
paired=HelperTMBERFrameAssociation(bits,rsFrames,pos,3,.1);
assert(isequal(paired.TxFrameIndex,expected));
assert(isequal(int8(bits),vertcat(rsFrames{expected})));
% The second call's positions remain in the SAME input-stream coordinates.
decoder=HelperCCSDSTMDecoder(args{:}); input=softFrames(:); cut=3*2072+13;
b1=decoder(input(1:cut)); p1=decoder.getDecodedFramePositions();
b2=decoder(input(cut+1:end)); p2=decoder.getDecodedFramePositions();
assert(isequal([p1.InputStartBit;p2.InputStartBit],(1:2072:9*2072).'));
assert(isequal(int8([b1;b2]),vertcat(rsFrames{:})));
fprintf('Decoder provenance: RS erasure and two-call buffering passed.\n');
report=struct('FaultChecks',6,'DecoderChecks',2,'Receiver',struct([]));
if ~runReceiver, return; end
% Common on/off instrument regression also exercises decoder provenance.
report.Receiver=test_receiver_timeline(true);
p=struct('modType','8PSK','channelCoding','none','symbolRate',10e6,'sps',8, ...
    'snr',100,'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'WaveformMode','ordinaryTM','NumBytesInTransferFrame',223, ...
    'hasASM',true,'RandomizerEnabled',false,'RandomizerFECPosition','afterEncoding', ...
    'DataPathMode','single','TMDataSource','random','RolloffFactor',.35, ...
    'berWarmUpFrames',4,'berFrames',12,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableEqualizer',false,'showFigures',false, ...
    'showPipelineFigure',false,'showPowerFigure',false, ...
    'enableReceiverTimeline',true);
codes={'none','convolutional','RS','concatenated','LDPC','Turbo','TPC'};
for k=1:numel(codes)
    q=p; q.channelCoding=codes{k}; q.ConvolutionalCodeRate='1/2';
    q.RSMessageLength=223; q.RSInterleavingDepth=1; q.IsRSMessageShortened=false;
    q.CodeRate='1/2'; q.NumBitsInInformationBlock=1024;
    if strcmp(q.channelCoding,'Turbo'), q.NumBitsInInformationBlock=3568; end
    q.TPCCodeRate='1/2'; q.TPCBlocksPerTF=8;
    q.TPCInterleaver='auto'; q.TPCDecoderMode='iterative';
    rng(364232726,'twister'); log=evalc('[r,~]=run_ccsds_tm_evaluation(q);');
    if ~r.success, fprintf('%s\n',log); disp(r); end
    assert(r.success && r.ReceiverTimeline.Available,'Receiver/telemetry failed.');
    a=r.FrameAssociation;
    assert(a.Available && all(diff(a.TxFrameIndex(isfinite(a.TxFrameIndex)))>0));
    assert(r.BER==0 && r.FER==0 && r.CountedFrames>0, ...
        'No-H/noiseless FEC path regressed.');
    assert(r.CountedFrames==q.berFrames && r.MeasurementCoverage.Complete, ...
        'Every originally requested measurement frame must be compared.');
    fprintf('8PSK + %s: BER=0 FER=0, physical pairing, counted=%d.\n', ...
        q.channelCoding,r.CountedFrames);
end
% The user's active same-tap FSE path, without a long impaired TPC run.
q.enableEqualizer=true; q.equalizerMode='blind-cma-lms';
q.adaptiveEqualizerSamplingMode='2sps-dual';
q.adaptiveFractionalEqualizerTaps=129; q.symbolRate=30e6;
q.carrierLoopBandwidth=.0025; q.PSKPostFSEPhaseTrackerMode='off';
q.berWarmUpFrames=8; q.berFrames=4;
rng(364232726,'twister'); log=evalc('[r,~]=run_ccsds_tm_evaluation(q);');
if ~r.success, fprintf('%s',log); end
assert(r.success && r.BER==0 && r.FER==0 && ...
    r.CountedFrames==4 && r.MeasurementCoverage.Complete);
fprintf('8PSK/TPC 2-sps dual No-H: BER=0, all 4 requested frames compared.\n');
mods={'BPSK','16QAM','32QAM','16APSK','32APSK'};
for k=1:numel(mods)
    q=p; q.modType=mods{k}; q.HasTMAPSKPilots=false;
    q.berWarmUpFrames=8; q.berFrames=6;
    rng(364232726,'twister'); log=evalc('[r,~]=run_ccsds_tm_evaluation(q);');
    if ~r.success, fprintf('%s',log); end
    assert(r.success && r.BER==0 && r.FER==0 && ...
        r.CountedFrames==6 && r.MeasurementCoverage.Complete);
    fprintf('%s none No-H: BER=0, all 6 requested frames compared.\n',mods{k});
end
end
