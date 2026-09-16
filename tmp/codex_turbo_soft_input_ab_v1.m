function D=codex_turbo_soft_input_ab_v1(cached)
% Same received Turbo codewords, same boundaries, same decoder: only LLR
% scale changes. TX bits are used AFTER reception for diagnostic scoring.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
if nargin<1
    period=7208; % CCSDS Turbo K=3568, rate 1/2: 7144 coded + 64 ASM.
    softAuditConfig=struct('SymbolRange',[floor(100*period/3)-128 ceil(120*period/3)+128], ...
        'AnchorRange',[50000 51023]);
    NewChannelFECRepresentativeOptions=struct( ...
        'StartFEC',6,'MaxFEC',1,'StartFile',4,'MaxFiles',1, ...
        'ModType','8PSK','SymbolRate',30e6,'SamplesPerSymbol',8, ...
        'BERWarmUpFrames',100,'BERFrames',120,'NoiseMode','off', ...
        'NormalizeHChannel',true,'VerboseReceiverLog',false,'SaveCSV',false, ...
        'ReceiverOverrides',struct('cfo',0,'enablePSKCoarseFrequencyCompensator',true, ...
        'carrierCaptureRangeHz',2e6,'carrierLoopBandwidth',0.0025, ...
        'adaptiveEqualizerSamplingMode','2sps-dual','adaptiveFractionalEqualizerTaps',129, ...
        'PSKPostFSEPhaseTrackerMode','off','collectPredecoderStats',true, ...
        'DemodNoiseVariance',1,'FSEDiagnostics',softAuditConfig)); %#ok<NASGU>
    fprintf('Capture original Turbo A4 record once; keep frontend/decoder unchanged.\n');
    cacheFile=fullfile(root,'tmp','turbo_soft_input_capture.mat');
    if isfile(cacheFile)
        saved=load(cacheFile,'softAuditCache');
        result=saved.softAuditCache.Result; p=saved.softAuditCache.Parameters;
        captureLog=saved.softAuditCache.Log; tx=saved.softAuditCache.TXEncoded;
        fprintf('Using frozen pre-fix capture: %s\n',cacheFile);
    else
        captureLog=evalc('run(fullfile(root,''tmp'',''codex_new_channel_psd_fec_representative_sweep_v1.m''));');
        tx=evalin('base','debugTMEncodedBits');
        softAuditCache=struct('Result',result,'Parameters',p,'Log',captureLog,'TXEncoded',tx);
        save(cacheFile,'softAuditCache','-v7');
        fprintf('Frozen baseline captured at %s\n',cacheFile);
    end
    r=result;
    assert(r.success && r.PredecoderASMAligned && r.MeasurementCoverage.Complete);
    assert(numel(tx)==220*period,'Unexpected Turbo framing.');
    cap=r.FSEDiagnostics.Stages.AfterASM;
    select=cap.SymbolIndex>=softAuditConfig.SymbolRange(1) & cap.SymbolIndex<=softAuditConfig.SymbolRange(2);
    idx=cap.SymbolIndex(select); z=cap.Samples(select);
    assert(all(diff(idx)==1),'Diagnostic samples must be contiguous.');
    dm=comm.PSKDemodulator(8,pi/8,'BitOutput',true, ...
        'DecisionMethod','Approximate log-likelihood ratio', ...
        'SymbolMapping','Custom','CustomSymbolMapping',[0 4 6 2 3 7 5 1],'Variance',1);
    soft=-dm(z); firstBit=(idx(1)-1)*3+1;
    capture=r.FSEDiagnostics.Demapper;
    [~,ia,ib]=intersect((firstBit:firstBit+numel(soft)-1).',capture.BitIndex);
    assert(~isempty(ia) && all((soft(ia)>0)==capture.HardBits(ib)), ...
        'Replayed demapper differs from the actual selected receive path.');
    c=exp(1j*(pi/8+(0:7).'*pi/4));
    variance=HelperTMPSKResidualVariance(z,c);
    association=r.FrameAssociation;
    frames=(101:120).';
    [found,j]=ismember(frames,association.TxFrameIndex);
    assert(all(found),'Selected physical frames were not recovered.');
    start=association.InputStartBit(j);
    assert(all(diff(start)==period));
    raw=zeros(period-64,numel(frames)); truth=zeros(size(raw),'int8');
    for k=1:numel(frames)
        loc=start(k)+64-firstBit+1;
        assert(loc>=1 && loc+period-65<=numel(soft));
        raw(:,k)=soft(loc:loc+period-65);
        truth(:,k)=tx((frames(k)-1)*period+(65:period));
    end
    ideal=localDecoder(); reference=ideal(20*(2*double(truth(:))-1));
    timeline=struct2table(r.ReceiverTimeline.Rows);
    [found,j]=ismember(frames,timeline.TxFrameIndex); assert(all(found));
    D=struct('Parameters',p,'BaselineBER',r.BER,'BaselineFER',r.FER, ...
        'Log',captureLog,'Frames',frames,'RawSoft',raw,'TXCoded',truth, ...
        'Reference',reference,'ResidualVariance',variance, ...
        'BaselineFrameErrors',timeline.ErrorBitsDelta(j), ...
        'TimeStart_s',timeline.TimeStart_s(j),'TimeEnd_s',timeline.TimeEnd_s(j));
else
    D=cached;
end
variants=["original";"receiver-residual-calibrated"];
rows=cell(2,1); frameErrors=zeros(numel(D.Frames),2);
for k=1:2
    soft=D.RawSoft;
    if k==2, soft=max(-50,min(50,soft/D.ResidualVariance)); end
    hardChanges=nnz((soft>0)~=(D.RawSoft>0));
    assert(hardChanges==0,'Calibration must not change signs or bit positions.');
    decoder=localDecoder(); out=decoder(soft(:));
    errors=reshape(out~=D.Reference,3568,[]);
    frameErrors(:,k)=sum(errors,1).';
    if k==1
        assert(isequal(frameErrors(:,k),D.BaselineFrameErrors), ...
            'Fixed-codeword replay does not reproduce original per-frame errors.');
    end
    rows{k}=table(variants(k),D.ResidualVariance,hardChanges, ...
        nnz((D.RawSoft>0)~=D.TXCoded)/numel(soft), ...
        nnz(errors),nnz(errors)/numel(errors),nnz(frameErrors(:,k)), ...
        numel(D.Frames),'VariableNames',{'Variant','ResidualVariance','HardBitChanges', ...
        'RawCodewordBER','DecodedErrorBits','DecodedBER','ErrorFrames','ComparedFrames'});
end
D.Summary=vertcat(rows{:});
D.PerFrame=table(D.Frames,1e3*D.TimeStart_s,1e3*D.TimeEnd_s, ...
    D.BaselineFrameErrors,frameErrors(:,1),frameErrors(:,2), ...
    'VariableNames',{'TxFrame','TimeStart_ms','TimeEnd_ms','OriginalRunErrors', ...
    'ReplayOriginalErrors','ReplayCalibratedErrors'});
disp(D.Summary); disp(D.PerFrame);
fprintf('Same codewords and six Turbo iterations; no synchronization rerun or TX-aided correction.\n');
fprintf('Pass D again to repeat only the decoder A/B; the frozen capture is never overwritten.\n');
end

function d=localDecoder
d=HelperCCSDSTMDecoder('ChannelCoding','turbo','Modulation','8PSK', ...
    'CodeRate','1/2','NumBitsInInformationBlock',3568,'HasASM',false, ...
    'RandomizerEnabled',false,'DisablePhaseAmbiguityResolution',true);
end
