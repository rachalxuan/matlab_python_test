function outputDir = test_apsk_pulse_acceptance(suite)
% APSK ordinary-TM acceptance. No receiver tuning, oracle feedback or skips.
% all | uncoded | fec | buffer. Every receiver case measures 120 frames.
if nargin<1, suite='all'; end
assert(any(strcmp(suite,{'all','uncoded','fec','buffer'})));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('APSK pulse acceptance (%s): %s\n',suite,outputDir);
if any(strcmp(suite,{'all','buffer'}))
    BufferSummary=bufferChecks();
    writetable(BufferSummary,fullfile(outputDir,'buffer.csv'));
    save(fullfile(outputDir,'buffer.mat'),'BufferSummary');
end
rows={};
for modType=["16APSK","32APSK"]
    for pulse=["root raised cosine","none"]
        base=struct('modType',char(modType),'symbolRate',10e6,'sps',8, ...
            'channelCoding','none','NumBytesInTransferFrame',256, ...
            'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
            'PulseShapingFilter',char(pulse),'RolloffFactor',0.35,'FilterSpanInSymbols',10, ...
            'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
            'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
            'enableHChannel',false,'enableEqualizer',false, ...
            'APSKReceiverMode','pilotless','HasTMAPSKPilots',false, ...
            'enableReceiverTimeline',true,'debugSynchronizationChain',true, ...
            'captureBaselineData',true,'includeRawData',false,'showFigures',false,'randomSeed',917);
        cases={}; labels={};
        if any(strcmp(suite,{'all','uncoded'}))
            cases{end+1}=base; labels{end+1}='zero';
            for seed=[20260925 20260927]
                p=base; p.randomSeed=seed; cases{end+1}=p; labels{end+1}=sprintf('seed%d',seed); %#ok<AGROW>
            end
            for delay=[0.5 1]
                p=base; p.delay=delay; cases{end+1}=p; labels{end+1}=sprintf('delay%g',delay); %#ok<AGROW>
            end
            for phase=[-30 30]
                p=base; p.phaseOffset=phase; cases{end+1}=p; labels{end+1}=sprintf('phase%g',phase); %#ok<AGROW>
            end
            for cfo=[-50e3 50e3]
                p=base; p.cfo=cfo; cases{end+1}=p; labels{end+1}=sprintf('cfo%g',cfo); %#ok<AGROW>
            end
            for tf=[254 255 257 258]
                p=base; p.NumBytesInTransferFrame=tf;
                cases{end+1}=p; labels{end+1}=sprintf('tf%d',tf); %#ok<AGROW>
            end
            p=base; p.NumBytesInTransferFrame=255; p.delay=1;
            cases{end+1}=p; labels{end+1}='tf255_delay1';
        end
        if any(strcmp(suite,{'all','fec'}))
            p=base; p.channelCoding='LDPC'; p.CodeRate='1/2';
            p.NumBitsInInformationBlock=1024; p.IsLDPCOnSMTF=false;
            p.NumBytesInTransferFrame=128;
            cases{end+1}=p; labels{end+1}='ldpc1024_r12';
            for rs=[223 239]
                p=base; p.channelCoding='RS'; p.RSMessageLength=rs;
                p.RSInterleavingDepth=1+(rs==239); p.IsRSMessageShortened=false;
                p.NumBytesInTransferFrame=rs*p.RSInterleavingDepth;
                cases{end+1}=p; labels{end+1}=sprintf('rs%d_i%d',rs,p.RSInterleavingDepth); %#ok<AGROW>
            end
        end
        for k=1:numel(cases)
            p=cases{k}; name=sprintf('%s_%s_%s',modType,replace(pulse,' ','_'),labels{k});
            row=emptyRow(name,p); r=struct(); logText='';
            fprintf('\nRUN %s: seed=%d TF=%d delay=%g phase=%g CFO=%g\n', ...
                name,p.randomSeed,p.NumBytesInTransferFrame,p.delay,p.phaseOffset,p.cfo);
            try
                rng(p.randomSeed,'twister'); logText=evalc('r=run_ccsds_tm_evaluation(p);');
                assert(r.success,'%s',r.errorMsg);
                row=checkCase(row,p,r);
            catch ex
                row.Error=string(getReport(ex,'extended','hyperlinks','off'));
            end
            % Retain full captures on failures; successes retain results and checks.
            if row.Pass && isfield(r,'BaselineCapture'), r=rmfield(r,'BaselineCapture'); end
            save(fullfile(outputDir,[name '.mat']),'p','r','logText','row','-v7');
            rows{end+1}=row; %#ok<AGROW>
            Summary=struct2table(vertcat(rows{:}));
            writetable(Summary,fullfile(outputDir,'summary.csv'));
            save(fullfile(outputDir,'summary.mat'),'Summary');
            fprintf('RESULT BER=%g FER=%g coverage=%d/120 recoveredUncompared=%g pulse=%d ordinaryTM=%d pass=%d\n', ...
                row.BER,row.FER,row.ComparedFrames,row.RecoveredNotCompared,row.PulseVerified,row.OrdinaryTM,row.Pass);
            if strlength(row.Error)>0, fprintf('%s\n',row.Error); end
        end
    end
end
% A failed case must not prevent collecting the remaining matrix or baseline.
if strcmp(suite,'all')
    baselineOutput=test_apsk_none_timing_contract('baseline');
    save(fullfile(outputDir,'baseline_reference.mat'),'baselineOutput');
end
fprintf('\nAcceptance output: %s\n',outputDir);
if ~isempty(rows)
    fprintf('Passed %d/%d receiver cases.\n',nnz(Summary.Pass),height(Summary));
    disp(Summary(~Summary.Pass,{'Case','BER','FER','ComparedFrames','RecoveredNotCompared','Error'}));
    assert(all(Summary.Pass),'APSKPulse:AcceptanceFailed', ...
        'Some cases failed; results and failure captures retained at %s',outputDir);
end
fprintf('PASS %s\n',suite);
end

function row=emptyRow(name,p)
row=struct('Case',string(name),'ModType',string(p.modType),'Pulse',string(p.PulseShapingFilter), ...
    'FEC',string(p.channelCoding),'TFBytes',p.NumBytesInTransferFrame, ...
    'Seed',p.randomSeed,'Delay',p.delay,'Phase',p.phaseOffset,'CFO',p.cfo, ...
    'FrameMappingRemainder',NaN,'ActualTFBits',NaN,'BER',NaN,'FER',NaN, ...
    'ComparedFrames',0,'RecoveredNotCompared',NaN,'Unrecovered',NaN, ...
    'BufferedModulationBits',NaN,'OrdinaryTM',false,'PulseVerified',false, ...
    'TimelineVerified',false,'Pass',false,'Error',"");
if strcmp(p.channelCoding,'none')
    row.FrameMappingRemainder=mod(32+8*p.NumBytesInTransferFrame,log2(str2double(erase(p.modType,'APSK'))));
end
end

function row=checkCase(row,p,r)
row.BER=r.BER; row.FER=r.FER; row.ComparedFrames=r.CountedFrames;
c=r.MeasurementCoverage;
row.RecoveredNotCompared=c.RecoveredNotComparedFrames; row.Unrecovered=c.UnrecoveredFrames;
row.ActualTFBits=c.ComparedBits/max(1,c.ComparedFrames);
row.OrdinaryTM=strcmp(r.WaveformMode,'ordinaryTM') && strcmp(r.APSKReceiverMode,'pilotless') && ...
    ~r.HasTMAPSKPilots && r.PilotlessAPSKApplied && r.HasASM;
assert(row.OrdinaryTM,'Unexpected pilots/frame format/receiver mode.');
assert(r.Fs==p.symbolRate*p.sps && strcmp(r.PulseShapingFilter,p.PulseShapingFilter));
b=r.BurstCompletion; tx=r.BaselineCapture.TxWaveform;
row.BufferedModulationBits=b.BufferedModulationBits;
assert(b.Applied && b.AppendedSamples>0 && numel(tx)==b.OriginalWaveformSamples+b.AppendedSamples);
assert(mod(b.OriginalWaveformSamples,p.sps)==0 && mod(b.AppendedSamples,p.sps)==0);
bps=log2(str2double(erase(p.modType,'APSK')));
assert(b.OriginalModulatedBits==b.OriginalWaveformSamples/p.sps*bps);
assert(b.BufferedModulationBits>=0 && numel(tx)/p.sps*bps>=b.OriginalEncodedBits);
if strcmp(p.channelCoding,'none')
    assert(b.OriginalEncodedBits==(32+8*p.NumBytesInTransferFrame)*(p.berWarmUpFrames+p.berFrames), ...
        'Unexpected per-frame padding or measured TX frame count.');
end
if strcmp(p.PulseShapingFilter,'none')
    assert(b.RectangularSymbolHoldApplied && b.OriginalWaveformSamples==b.GeneratorOutputSamplesBeforeHold*p.sps);
    for part={tx(1:b.OriginalWaveformSamples),tx(b.OriginalWaveformSamples+1:end)}
        a=reshape(part{1},p.sps,[]); assert(all(all(a==a(1,:))));
    end
    assert(r.SyncDiagnostics.TimingInputSamplesPerSymbol==p.sps);
else
    assert(~b.RectangularSymbolHoldApplied && b.OriginalWaveformSamples==b.GeneratorOutputSamplesBeforeHold);
    assert(r.SyncDiagnostics.TimingInputSamplesPerSymbol==2);
end
row.PulseVerified=true;
assert(r.ReceiverTimeline.Available,'%s',r.ReceiverTimeline.Reason);
t=struct2table(r.ReceiverTimeline.Rows); m=t.MeasurementEligible;
row.TimelineVerified=nnz(m)==120 && all(t.ComparedBitsDelta(m)>0) && ...
    ~any(m & t.RecoveredCopies>0 & t.ComparedBitsDelta==0);
row.Pass=row.BER==0 && row.FER==0 && row.ComparedFrames==120 && c.Complete && ...
    c.ExpectedFrames==120 && c.ComparedFrames==120 && c.RecoveredNotComparedFrames==0 && ...
    c.UnrecoveredFrames==0 && c.DuplicateComparisons==0 && row.TimelineVerified;
end

function Summary=bufferChecks()
rows={};
for modType=["16APSK","32APSK"]
    for pulse=["root raised cosine","none"]
        for tf=254:258
            args={'Modulation',char(modType),'ChannelCoding','none', ...
                'NumBytesInTransferFrame',tf,'HasASM',true,'RandomizerEnabled',false, ...
                'HasTMAPSKPilots',false,'SamplesPerSymbol',8,'PulseShapingFilter',char(pulse)};
            if strcmp(pulse,'root raised cosine')
                args=[args,{'RolloffFactor',0.35,'FilterSpanInSymbols',10}]; %#ok<AGROW>
            end
            g=ccsdsTMWaveformGenerator(args{:}); batch=ccsdsTMWaveformGenerator(args{:});
            rng(917,'twister'); u=int8(randi([0 1],g.NumInputBits*17,1));
            xp=cell(17,1); bp=cell(17,1);
            for k=1:17, [xp{k},bp{k}]=g(u((k-1)*g.NumInputBits+(1:g.NumInputBits))); end
            x=vertcat(xp{:}); bits=vertcat(bp{:}); [xb,bb]=batch(u);
            assert(isequaln(x,xb) && isequal(bits,bb),'Chunk/batch TX mismatch.');
            assert(numel(bits)==17*(32+8*tf),'Unexpected per-frame bit insertion.');
            [completed,tail,guardBits]=HelperTMCompleteBurst(g,x,bits,u,80e6,struct());
            guard=int8(1)-repmat(u(end-g.NumInputBits+1:end),tail.GuardInputGroups,1);
            whole=ccsdsTMWaveformGenerator(args{:}); [expected,allbits]=whole([u;guard]);
            if strcmp(pulse,'none'), expected=repelem(expected,8); end
            assert(isequaln(completed,expected),'Continuation/reset/pulse mismatch.');
            assert(isequal([bits;guardBits],allbits),'Continuation encoded-bit mismatch.');
            assert(numel(completed)/8*log2(str2double(erase(modType,'APSK')))>=numel(bits));
            row=struct('ModType',modType,'Pulse',pulse,'TFBytes',tf, ...
                'Remainder',mod(32+8*tf,log2(str2double(erase(modType,'APSK')))), ...
                'BufferedBits',tail.BufferedModulationBits,'ChunkBatchIdentical',true,'ContinuationIdentical',true);
            rows{end+1}=row; %#ok<AGROW>
            fprintf('TX BUFFER %s %s TF=%d remainder=%d pending=%d: identical\n', ...
                modType,pulse,tf,row.Remainder,row.BufferedBits);
        end
    end
end
Summary=struct2table(vertcat(rows{:}));
end
