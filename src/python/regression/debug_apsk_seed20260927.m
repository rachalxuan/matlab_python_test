function outputDir=debug_apsk_seed20260927(inputDir)
% Fixed saved-waveform diagnosis. No TX/channel rerun and no parameter scan.
% Truth is used ONLY for offline alignment, bit comparison and margins.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
if nargin<1, inputDir=fullfile(root,'tmp','tp63073790_9ecf_426c_af05_892069c58600'); end
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Fixed seed diagnosis: %s\n',outputDir);
n=load(fullfile(inputDir,'32APSK_none_seed20260927.mat'));
tx=reshape(n.r.BaselineCapture.TxWaveform,8,[]);
assert(all(all(tx==tx(1,:)))); truth=tx(1,:).';
ref=HelperCCSDSFACMReferenceConstellation(21); ref=ref(:);
[~,truthLabel]=min(abs(truth-ref.').^2,[],2);
assert(max(abs(truth-ref(truthLabel)))<1e-12);
truthBits=reshape(int2bit((truthLabel-1).',5),[],1);
assert(isequal(HelperCCSDSFACMDemodulate(ref,21,1)>0,reshape(int2bit(0:31,5),[],1)>0));
spf=416; first=8*spf+1; last=128*spf;
for pulse=["root_raised_cosine","none"]
    s=load(fullfile(inputDir,['32APSK_' char(pulse) '_seed20260927.mat']));
    p=s.p; r=s.r; c=r.BaselineCapture;
    % Historical fault replay: retain the original power estimator even
    % after the production default changes to decision-directed tracking.
    p.PilotlessAPSKComplexGainTracker=struct('MagnitudeEstimationMode','power');
    assert(p.randomSeed==20260927 && strcmp(p.channelCoding,'none') && p.delay==0 && p.cfo==0 && p.phaseOffset==0);
    cfg=c.PulseStageCapture.TimingConfiguration; cfg.CollectTimingError=true;
    [timing,timingInfo]=HelperTMSymbolSynchronizerChunked(c.PulseStageCapture.Filtered,cfg);
    assert(isequaln(timing,c.TimeSynchronizedSymbols));
    [pilot,info]=HelperTMAPSKPilotlessFrontEnd(timing,'32APSK',p);
    assert(isequaln(pilot,c.PulseStageCapture.PilotlessOutput));
    % Obtain the identical carrier output BEFORE the final scalar gain stage.
    noGain=p; noGain.enablePilotlessAPSKComplexGainTracker=false;
    carrier=HelperTMAPSKPilotlessFrontEnd(timing,'32APSK',noGain);
    [lag,g]=alignment(timing,truth,first,last);
    ti=(first:last).'; yi=ti-lag; expected=truthLabel(ti);
    final=c.FineSynchronizedSymbols;
    final=final/sqrt(mean(abs(final).^2)); % same normalization as APSK demapper
    stages={timing/g,carrier,pilot,final};
    names={'postTiming_offlineFixedGain','postCarrier_beforeGain','postPilotless_afterGain','postASM_demapperInput'};
    stageRows={}; zStages=zeros(numel(ti),4);
    for k=1:4
        z=stages{k}(yi); zStages(:,k)=z;
        [~,label]=min(abs(z-ref.').^2,[],2);
        bitErrors=nnz(int2bit((label-1).',5)~=int2bit((expected-1).',5));
        stageRows{k}=struct('Stage',string(names{k}),'SymbolErrors',nnz(label~=expected), ...
            'BitErrorsIncludingASM',bitErrors,'EVM_pct',100*sqrt(mean(abs(z-truth(ti)).^2)/mean(abs(truth(ti)).^2))); %#ok<AGROW>
    end
    StageSummary=struct2table(vertcat(stageRows{:}));
    % Exact production demapper, no oracle gain or phase adjustment.
    allLLR=HelperCCSDSFACMDemodulate(final,21,1); bits=allLLR>0;
    fullBitIndex=reshape((ti.'-1)*5+(1:5).',[],1);
    rxBitIndex=reshape((yi.'-1)*5+(1:5).',[],1);
    wrong=find(bits(rxBitIndex)~=logical(truthBits(fullBitIndex)));
    txBit=fullBitIndex(wrong); rxBit=rxBitIndex(wrong);
    frame=ceil(txBit/2080); frameBit=mod(txBit-1,2080)+1; tfBit=frameBit-32;
    Errors=table(frame,txBit,frameBit,tfBit,ceil(tfBit/8),mod(tfBit-1,8)+1, ...
        ceil(txBit/5),mod(txBit-1,5)+1,truthBits(txBit),bits(rxBit), ...
        'VariableNames',{'TxFrame','StreamBit','ASMAndTFBit','TFBit','TFByte','BitInByteMSBFirst', ...
        'TxSymbol','BitInSymbolMSBFirst','ExpectedBit','ReceivedBit'});
    assert(all(tfBit>0),'Unexpected ASM errors.');
    t=struct2table(r.ReceiverTimeline.Rows);
    assert(height(Errors)==sum(t.ErrorBitsDelta(t.MeasurementEligible)), ...
        'Exact demapper mismatch: captured signal does not reproduce receiver bit count.');
    for f=unique(frame).'
        assert(nnz(frame==f)==sum(t.ErrorBitsDelta(t.TxFrameIndex==f & t.MeasurementEligible)));
    end
    ByteErrors=table();
    for f=unique(frame).'
        for by=unique(ceil(tfBit(frame==f)/8)).'
            txIndices=(f-1)*2080+32+(by-1)*8+(1:8).';
            rxIndices=txIndices-lag*5;
            expectedByte=double(truthBits(txIndices)).'*(2.^(7:-1:0)).';
            receivedByte=double(bits(rxIndices)).'*(2.^(7:-1:0)).';
            ByteErrors=[ByteErrors;table(f,by,string(dec2hex(expectedByte,2)), ...
                string(dec2hex(receivedByte,2)), ...
                'VariableNames',{'TxFrame','TFByte','ExpectedHex','ReceivedHex'})]; %#ok<AGROW>
        end
    end
    badSymbols=unique(ceil(txBit/5)); symbolRows={};
    for j=1:numel(badSymbols)
        txi=badSymbols(j); rxi=txi-lag; a=truth(txi);
        [~,di]=min(abs(final(rxi)-ref).^2); b=ref(di);
        for k=1:4
            z=stages{k}(rxi);
            signedBoundary=(abs(z-b)^2-abs(z-a)^2)/(2*abs(b-a));
            symbolRows{end+1}=struct('TxSymbol',txi,'RxSymbol',rxi,'FrameSymbol',mod(txi-1,spf)+1, ...
                'Stage',string(names{k}),'ExpectedLabel',truthLabel(txi)-1,'WrongLabel',di-1, ...
                'ExpectedI',real(a),'ExpectedQ',imag(a),'WrongI',real(b),'WrongQ',imag(b), ...
                'I',real(z),'Q',imag(z),'Radius',abs(z),'ExpectedRadius',abs(a),'WrongRadius',abs(b), ...
                'PhaseError_deg',rad2deg(angle(z*conj(a))),'DistanceExpected',abs(z-a), ...
                'DistanceWrong',abs(z-b),'SignedBoundaryDistance',signedBoundary, ...
                'BoundaryRadiusAtTrueAngle',(abs(b)^2-abs(a)^2)/(2*real(exp(1j*angle(a))*conj(b-a)))); %#ok<AGROW>
        end
    end
    Symbols=struct2table(vertcat(symbolRows{:}));
    % Reconstruct ONLY the documented scalar-power equation for attribution.
    % It is not a proposed replacement receiver and never uses TX truth.
    a=exp(-1/16); init=median(abs(carrier(1:512)).^2)+eps;
    envelope=filter(1-a,[1 -a],abs(carrier).^2,a*init);
    predicted=carrier./sqrt(envelope/mean(abs(ref/sqrt(mean(abs(ref).^2)+eps)).^2));
    powerReplayMaxDifference=max(abs(predicted-pilot));
    assert(powerReplayMaxDifference<1e-12,'Scalar-power attribution did not reproduce actual samples.');
    finalScale=(pilot'*final)/(pilot'*pilot);
    finalScalarResidual=max(abs(final-finalScale*pilot));
    actualInverse=abs(pilot./carrier);
    wi=(min(badSymbols)-64:max(badSymbols)+16).'; ri=wi-lag;
    radii=unique(round(abs(ref)*1e10)/1e10); [~,ring]=min(abs(abs(truth(wi))-radii.'),[],2);
    Neighborhood=table(wi,ri,truthLabel(wi)-1,ring,abs(truth(wi)).^2,abs(carrier(ri)).^2, ...
        envelope(ri),actualInverse(ri),abs(carrier(ri)),abs(pilot(ri)),abs(final(ri)), ...
        'VariableNames',{'TxSymbol','RxSymbol','ExpectedLabel','Ring','TrueSymbolPower','CarrierPower', ...
        'EstimatedPower','InverseGain','BeforeGainRadius','AfterGainRadius','FinalRadius'});
    fprintf('\n%s: lag=%d, early timing gain=%g%+gi; exact error bits=%d\n',pulse,lag,real(g),imag(g),height(Errors));
    disp(StageSummary); disp(Errors); disp(ByteErrors); disp(Symbols);
    fprintf('Scalar power equation replay max difference = %.16g; mode=%s\n',powerReplayMaxDifference,info.ComplexGain.MagnitudeEstimationMode);
    fprintf('Final output / pilotless = %.12g%+.12gi, max scalar-fit residual %.12g\n',real(finalScale),imag(finalScale),finalScalarResidual);
    disp(Neighborhood(ismember(Neighborhood.TxSymbol,badSymbols),:));
    fprintf('Preceding 32-symbol ring counts per bad symbol (inner/middle/outer):\n');
    for j=1:numel(badSymbols)
        idx=(badSymbols(j)-32:badSymbols(j)-1).';
        [~,rings]=min(abs(abs(truth(idx))-radii.'),[],2);
        fprintf('%d: %d / %d / %d; mean true power %.6g\n',badSymbols(j),nnz(rings==1),nnz(rings==2),nnz(rings==3),mean(abs(truth(idx)).^2));
    end
    save(fullfile(outputDir,[char(pulse) '.mat']),'p','StageSummary','Errors','ByteErrors','Symbols','Neighborhood', ...
        'info','timingInfo','lag','g','powerReplayMaxDifference','finalScale','finalScalarResidual','-v7');
    for pair={{'stages',StageSummary},{'bits',Errors},{'bytes',ByteErrors},{'symbols',Symbols},{'neighborhood',Neighborhood}}
        item=pair{1}; writetable(item{2},fullfile(outputDir,[char(pulse) '_' item{1} '.csv']));
    end
end
fprintf('Saved fixed-case diagnosis: %s\n',outputDir);
end

function [lag,g]=alignment(y,t,first,last)
best=Inf; lag=0; g=1;
ti=(first:min(first+4095,last)).';
for l=-32:32
    v=y(ti-l); q=t(ti); gain=(q'*v)/(q'*q);
    e=mean(abs(v-gain*q).^2);
    if e<best, best=e; lag=l; g=gain; end
end
end
