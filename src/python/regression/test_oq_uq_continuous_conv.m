function outputFile = test_oq_uq_continuous_conv(stage,baselineFile)
% One bounded regression driver. Save compact records, not full waveforms.
% Baseline hashes permit exact old-path comparisons without GB-sized MATs.
if nargin<1, stage='half'; end
if nargin<2, baselineFile=''; end
assert(any(strcmp(stage,{'baseline','legacy','half','three','high','rs','phase','timing','existing','contract','guards'})));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputFile=[tempname(fullfile(root,'tmp')) '_oq_uq.mat'];
records={}; checkSoftContract();
if strcmp(stage,'contract')
    records=checkConvChunks(); save(outputFile,'records','stage','-v7');
    fprintf('PASS contract: %d checks; %s\n',numel(records),outputFile); return;
end
p=struct('symbolRate',10e6,'sps',8,'NumBytesInTransferFrame',258, ...
    'channelCoding','convolutional','ConvolutionalCodeRate','1/2', ...
    'ConvolutionalReceiveMode','stream-raw-asm','hasASM',true, ...
    'PCMFormat','NRZ-L','RandomizerEnabled',false,'DataPathMode','single', ...
    'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableEqualizer',false,'enableReceiverTimeline',true, ...
    'captureBaselineData',true,'showFigures',false,'randomSeed',917, ...
    'debugContinuousConvReceiver',true,'debugUQPSK',true);
if strcmp(stage,'guards')
    bad={struct('RandomizerEnabled',true),struct('PCMFormat','NRZ-M'), ...
        struct('hasASM',false),struct('DataPathMode','dualIQ'), ...
        struct('channelCoding','concatenated','RSMessageLength',223,'RSInterleavingDepth',6), ...
        struct('channelCoding','concatenated','RSMessageLength',223,'RSInterleavingDepth',1, ...
            'IsRSMessageShortened',true,'RSShortenedMessageLength',200), ...
        struct('ConvolutionalReceiveMode','legacy-coded-asm')};
    for modType=["OQPSK","UQPSK"]
        for k=1:numel(bad)
            q=p; q.modType=char(modType); q.ConvolutionalCodeRate='5/6';
            names=fieldnames(bad{k});
            for j=1:numel(names), q.(names{j})=bad{k}.(names{j}); end
            evalc('r=run_ccsds_tm_evaluation(q);');
            assert(~r.success && contains(r.errorIdentifier,'Unsupported'), ...
                'Unsupported request silently accepted: %s case %d',modType,k);
            records{end+1}=struct('Options',q,'ErrorIdentifier',r.errorIdentifier,'Pass',true); %#ok<AGROW>
        end
    end
    save(outputFile,'records','stage','-v7');
    fprintf('PASS guards: %d rejected requests; %s\n',numel(records),outputFile); return;
end
cases={};
mods=["OQPSK","UQPSK"];
if strcmp(stage,'existing'), mods=["BPSK","QPSK","8PSK","16QAM","32QAM","16APSK","32APSK"]; end
for modType=mods
 for pulse=["root raised cosine","none"]
    q=p; q.modType=char(modType); q.PulseShapingFilter=char(pulse);
    switch stage
     case {'baseline','legacy'}
        q.ConvolutionalReceiveMode='legacy-coded-asm';
        for coding=["none","RS","convolutional"]
            t=q; t.channelCoding=char(coding);
            if coding=="RS"
                t.NumBytesInTransferFrame=223; t.RSMessageLength=223;
                t.RSInterleavingDepth=1; t.IsRSMessageShortened=false;
            end
            cases{end+1}=t; %#ok<AGROW>
        end
     case 'half'
        cases{end+1}=q; %#ok<AGROW>
     case 'three'
        q.ConvolutionalCodeRate='3/4';
        for bytes=[256 257 258]
            t=q; t.NumBytesInTransferFrame=bytes; cases{end+1}=t; %#ok<AGROW>
        end
     case 'high'
        for rate=["2/3","5/6","7/8"]
            t=q; t.ConvolutionalCodeRate=char(rate); cases{end+1}=t; %#ok<AGROW>
        end
     case 'rs'
        for cfg=[223 1 3;239 1 5;223 4 7;239 8 2].'
            t=q; t.channelCoding='concatenated'; t.RSMessageLength=cfg(1);
            t.RSInterleavingDepth=cfg(2); t.IsRSMessageShortened=false;
            t.NumBytesInTransferFrame=cfg(1)*cfg(2);
            t.ConvolutionalCodeRate=sprintf('%d/%d',cfg(3),cfg(3)+1);
            cases{end+1}=t; %#ok<AGROW>
        end
     case 'phase'
        q.ConvolutionalCodeRate='3/4'; q.randomSeed=20260927;
        for phase=[90 -90]
            t=q; t.phaseOffset=phase; cases{end+1}=t; %#ok<AGROW>
        end
     case 'timing'
        q.ConvolutionalCodeRate='3/4'; q.randomSeed=20260927;
        for delay=[0.5 1]
            t=q; t.delay=delay; cases{end+1}=t; %#ok<AGROW>
        end
     case 'existing'
        q.ConvolutionalCodeRate='3/4'; cases{end+1}=q; %#ok<AGROW>
    end
 end
end
if strcmp(stage,'legacy'), before=load(baselineFile,'records'); end
fprintf('OQ/UQ continuous %s: %s (%d cases)\n',stage,outputFile,numel(cases));
for k=1:numel(cases)
    p=cases{k}; rng(p.randomSeed,'twister');
    fprintf('RUN %d/%d %s %s %s %s TF=%d phase=%g\n',k,numel(cases), ...
        p.modType,p.PulseShapingFilter,p.channelCoding,p.ConvolutionalCodeRate, ...
        p.NumBytesInTransferFrame,p.phaseOffset);
    logText=evalc('r=run_ccsds_tm_evaluation(p);');
    rec=struct('Options',p,'Pass',false,'Error','','Hashes',struct(), ...
        'BER',NaN,'FER',NaN,'Compared',0,'Log',logText);
    try
        assert(r.success,'%s',r.errorMsg);
        rec.BER=r.BER; rec.FER=r.FER; rec.Compared=r.CountedFrames;
        rec.Coverage=r.MeasurementCoverage; rec.Burst=r.BurstCompletion;
        c=r.BaselineCapture;
        for field={'TxWaveform','ReferenceConstellation','RawReceiverSymbols', ...
                'CoarseSynchronizedWaveform','TimeSynchronizedSymbols', ...
                'FineSynchronizedSymbols','BestRotation_deg'}
            rec.Hashes.(field{1})=fingerprint(c.(field{1}));
        end
        assert(r.Fs==p.symbolRate*p.sps && r.BurstCompletion.Applied);
        assert(numel(c.TxWaveform)==r.BurstCompletion.OriginalWaveformSamples+ ...
            r.BurstCompletion.AppendedSamples);
        assert(r.BER==0 && r.FER==0 && r.CountedFrames==120 && ...
            r.MeasurementCoverage.Complete && r.MeasurementCoverage.ExpectedFrames==120 && ...
            r.MeasurementCoverage.UnrecoveredFrames==0 && ...
            r.MeasurementCoverage.RecoveredNotComparedFrames==0,'Incomplete or erroneous measurement.');
        if strcmp(p.ConvolutionalReceiveMode,'stream-raw-asm')
            assert(strcmp(r.ConvolutionalReceiveMode,'stream-raw-asm') && ...
                r.ContinuousConvReceiverAvailable && r.ContinuousConvLongestGoodASMRun>=4);
            rec.Offset=r.ContinuousConvSelectedOffset;
            rec.ASMRun=r.ContinuousConvLongestGoodASMRun;
            if strcmp(p.modType,'UQPSK')
                assert(strcmp(r.UQPSKSymSkipSelectionMethod,'continuous-raw-asm'));
                rec.GroupSkip=r.UQPSKSymSkip;
            end
            if strcmp(p.channelCoding,'concatenated')
                rec.RSRawErrors=r.ContinuousConvOuterRSMeasurementRawCodewordBitErrors;
                rec.RSCorrections=r.ContinuousConvOuterRSMeasurementCorrectedSymbols;
                assert(rec.RSRawErrors==0 && rec.RSCorrections==0 && ...
                    r.ContinuousConvOuterRSMeasurementMappedFrames==120 && ...
                    r.ContinuousConvOuterRSMeasurementUncorrectableFrames==0);
            end
        end
        if strcmp(stage,'legacy')
            b=before.records{k};
            assert(isequaln(rec.Options,b.Options) && isequaln(rec.Hashes,b.Hashes));
            assert(isequaln(rec.Coverage,b.Coverage) && isequaln(rec.Burst,b.Burst));
        end
        rec.Pass=true;
    catch ex
        rec.Error=getReport(ex,'extended','hyperlinks','off');
    end
    records{end+1}=rec; %#ok<AGROW>
    % Full arrays exist only in RAM. Failed runs retain seed/options and log
    % for deterministic reproduction; no automatic large failure dumps.
    save(outputFile,'records','stage','-v7');
    fprintf('RESULT BER=%g FER=%g frames=%d/120 PASS=%d\n',rec.BER,rec.FER,rec.Compared,rec.Pass);
    assert(rec.Pass,'OQUQConv:Failure','%s\nRecord: %s',rec.Error,outputFile);
end
fprintf('PASS %s: %d/%d\n',stage,numel(records),numel(cases));
end

function hash=fingerprint(x)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(getByteStreamFromArray(x));
hash=reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]);
end

function checkSoftContract()
% Actual generator, no shadow mapping. Truth used only for this assertion.
for modType=["OQPSK","UQPSK"]
    rng(917,'twister');
    g=ccsdsTMWaveformGenerator('Modulation',char(modType),'ChannelCoding','none', ...
        'NumBytesInTransferFrame',258,'SamplesPerSymbol',8,'PulseShapingFilter','none');
    data=int8(randi([0 1],double(g.NumInputBits)*16,1));
    [x,bits]=g(data);
    args={};
    if modType=="OQPSK", args={'SamplesPerSymbol',8,'PulseShapingFilter','none'}; end
    d=HelperCCSDSTMDemodulator('Modulation',char(modType), ...
        'ChannelCoding','convolutional',args{:});
    soft=d(x); hard=int8(soft>0); best=Inf; selectedLag=NaN;
    for lag=-64:64
        a=1+max(0,lag); b=1+max(0,-lag);
        n=min(numel(bits)-a+1,numel(hard)-b+1);
        idx=(513:n-512).';
        if isempty(idx), continue; end
        errors=nnz(bits(a+idx-1)~=hard(b+idx-1));
        if errors<best, best=errors; selectedLag=lag; end
    end
    assert(best==0,'OQ/UQ production demapper bit polarity/order mismatch.');
    g2=clone(g); reset(g2); split=double(g.NumInputBits)*7;
    [xa,ba]=g2(data(1:split)); [xb,bb]=g2(data(split+1:end));
    assert(isequal(x,[xa;xb]) && isequal(bits,[ba;bb]),'TX changed across calls.');
    fprintf('SOFT %s: positive=1, production bit order PASS, offline lag=%d\n',modType,selectedLag);
    release(g); release(g2); release(d);
end
end

function records=checkConvChunks()
records={};
for modType=["OQPSK","UQPSK"]
 for rate=["1/2","2/3","3/4","5/6","7/8"]
    rng(917,'twister');
    g=ccsdsTMWaveformGenerator('Modulation',char(modType),'ChannelCoding','convolutional', ...
        'ConvolutionalCodeRate',char(rate),'AllowContinuousPuncturingAcrossFrames',true, ...
        'NumBytesInTransferFrame',258,'SamplesPerSymbol',8,'PulseShapingFilter','none');
    data=int8(randi([0 1],double(g.NumInputBits)*16,1));
    [x,bits]=g(data); g2=clone(g); reset(g2); split=double(g.NumInputBits)*7;
    [xa,ba]=g2(data(1:split)); [xb,bb]=g2(data(split+1:end));
    assert(isequal(x,[xa;xb]) && isequal(bits,[ba;bb]),'TX call boundary changed coded stream.');
    args={}; if modType=="OQPSK", args={'SamplesPerSymbol',8,'PulseShapingFilter','none'}; end
    d=HelperCCSDSTMDemodulator('Modulation',char(modType),'ChannelCoding','convolutional',args{:});
    soft=d(x);
    % Same production soft stream, with a received-bit offset and chunks not
    % aligned to any puncture period. No mapper state reset is inferred here.
    soft=soft(2:end); clip=max(abs(soft));
    rxArgs={'CodeRate',char(rate),'FramePayloadBits',258*8,'SoftClip',clip,'Verbose',false};
    a=HelperTMContinuousConvReceiver(rxArgs{:}); a.append(soft); [pa,ia]=a.finalize();
    b=HelperTMContinuousConvReceiver(rxArgs{:}); first=1;
    b.append([]);
    for count=[1 2 3]
        b.append(soft(first:first+count-1)); first=first+count;
    end
    while first<=numel(soft)
        last=min(numel(soft),first+randi([101 4096])-1);
        b.append(soft(first:last)); first=last+1;
    end
    [pb,ib]=b.finalize();
    assert(ia.Available && isequal(pa,pb) && isequaln(ia,ib),'RX chunk/state mismatch.');
    records{end+1}=struct('ModType',modType,'Rate',rate,'Pass',true, ...
        'Frames',size(pa,2),'SelectedOffset',ia.SelectedOffset); %#ok<AGROW>
    fprintf('CHUNKS %s %s TX=batch/split RX=whole/random PASS frames=%d\n',modType,rate,size(pa,2));
    % Short data and all-zero soft evidence must never masquerade as frames.
    for badSoft={soft(1:7),zeros(10000,1)}
        neg=HelperTMContinuousConvReceiver(rxArgs{:}); neg.append(badSoft{1});
        [pn,in]=neg.finalize(); assert(~in.Available && isempty(pn));
    end
    release(g); release(g2); release(d);
 end
end
end
