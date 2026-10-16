function [D,path] = diagnose_tm_system_failures(whichCase)
% Fixed saved cases only. TX truth is used by this read-only instrument,
% never returned to the receiver. No DSP parameters or frame counts change.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
whichCase=lower(string(whichCase));
afterRepair=endsWith(whichCase,'-after');
whichCase=erase(whichCase,'-after');
if whichCase=="report"
    [D,path]=localReport(root);
    return;
end
if whichCase=="apsk16-report"
    [D,path]=localAPSK16Report(root);
    return;
end
switch whichCase
    case "bpsk", source='TM_EQ_cd_20261011_184320_360.mat'; k=6; focus=[.0404 .0414];
    case "qam", source='TM_EQ_psd_20261011_201140_162.mat'; k=41; focus=[.0314 .0324];
    case "apsk", source='TM_EQ_cd_20261011_184320_360.mat'; k=67; focus=[0 .001];
    case "apsk16", source='TM_EQ_cd_20261011_184320_360.mat'; k=60; focus=[.0095 .0105];
    case "apsk16-seed", source='TM_EQ_cd_20261011_184320_360.mat'; k=60; focus=[.0095 .0105];
    case "apsk16-none", source='TM_EQ_cd_20261011_184320_360.mat'; k=64; focus=[.0095 .0105];
    otherwise, error('Use bpsk, qam, apsk, apsk16, or apsk16-none.');
end

if afterRepair && whichCase=="apsk", k=68; focus=[.0095 .0105]; end

s=load(fullfile(root,'artifacts','ccsds','system-eq',source));
p=s.inputs{k}; expected=s.T(k,:);
sameOriginalConfiguration=whichCase~="apsk16-seed";
if ~sameOriginalConfiguration, p.randomSeed=918; end
D=struct('Source',source,'CaseIndex',k,'Input',p,'Expected',expected, ...
    'ReferenceSameConfiguration',sameOriginalConfiguration, ...
    'StageTables',struct(),'Captures',struct(),'Alignment',struct());
truth=[]; ref=[]; inputPrefix=[]; inputPower=NaN;
p.DiagnosticStageObserver=@observe;
if startsWith(whichCase,"apsk16")
    % Existing capture switch affects diagnostics only, not the algorithm.
    p.PilotlessAPSKCarrierRecovery=struct('CapturePhaseStages',true);
end
fprintf('Read-only diagnosis: %s case %d. No receiver tuning.\n',whichCase,k);
rng(p.randomSeed,'twister');
r=struct(); % Explicit binding for evalc in this nested-function workspace.
D.Log=evalc('r=run_ccsds_tm_evaluation(p);');
D.Success=r.success;
if r.success
    D.Actual=struct('BER',r.BER,'FER',r.FER,'Coverage',r.MeasurementCoverage);
    D.Reproduced=isequaln(r.BER,expected.BER) && isequaln(r.FER,expected.FER) && ...
        r.MeasurementCoverage.ComparedFrames==expected.ComparedFrames;
else
    D.Actual=r;
    D.Reproduced=~expected.RunCompleted && contains(string(r.errorMsg),'carrier acquisition failed');
end
if ~afterRepair && sameOriginalConfiguration
    assert(D.Reproduced,'Instrumentation did not reproduce the saved result: %s',D.Log);
end
if whichCase=="apsk" && ~afterRepair
    a=D.APSKAcquisition; opts=a.Options;
    opts.NormalizeInputPower=false;
    normInput=inputPrefix/sqrt(inputPower);
    [~,~,c]=HelperTMAPSKCarrierRecovery(normInput,p.modType,opts);
    D.CoarseReplayExact=c.CoarseAcquisition.Qualified==a.Info.CoarseAcquisition.Qualified && ...
        abs(c.CoarseAcquisition.CFOHz-a.Info.CoarseAcquisition.CFOHz)<1e-6 && ...
        max(abs(c.CoarseAcquisition.CandidateValidationStatistics-a.Info.CoarseAcquisition.CandidateValidationStatistics))<1e-8;
    assert(D.CoarseReplayExact,'Coarse prefix replay is not identical.');
    % Store only the acquisition prefix, not the full 82-ms receiver waveform.
    D.AcquisitionPrefix=normInput;
end
if afterRepair, tag='RepairTrace_'; else, tag='Diagnosis_'; end
if ~sameOriginalConfiguration
    % A second seed needs summary evidence, not another waveform archive.
    D.Captures=struct();
end
path=fullfile(root,'artifacts','ccsds','system-eq', ...
    [tag char(whichCase) '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.mat']);
save(path,'D','-v7');
names=fieldnames(D.StageTables);
for printIndex=1:numel(names)
    t=D.StageTables.(names{printIndex});
    fprintf('\n%s: lag=%d, anchor coherence=%.5f\n',names{printIndex},D.Alignment.(names{printIndex}).Lag,D.Alignment.(names{printIndex}).Coherence);
    near=t.Time_s>=focus(1) & t.Time_s<=focus(2);
    shown=find(near); shown=shown(unique(round(linspace(1,numel(shown),min(5,numel(shown))))));
    disp(t(shown,:));
end
if isfield(D,'APSKAcquisition'), disp(D.APSKAcquisition.Info.CoarseAcquisition); end
fprintf('OriginalArchiveMatch=%d (same configuration=%d). Saved %s\n', ...
    D.Reproduced,sameOriginalConfiguration,path);

    function observe(name,x)
        if strcmp(name,'TxEncodedBits')
            bits=double(x(:));
            if strcmp(p.modType,'BPSK')
                truth=complex(2*bits-1); ref=[-1;1];
            elseif strcmp(p.modType,'32QAM')
                bits=bits(1:5*floor(numel(bits)/5));
                truth=qammod(bits,32,'InputType','bit','UnitAveragePower',true);
                ref=qammod((0:31)',32,'UnitAveragePower',true);
            else
                if strcmp(p.modType,'16APSK'), format=14; else, format=21; end
                ref=HelperCCSDSFACMReferenceConstellation(format); ref=ref(:);
                bps=log2(numel(ref));
                labels=reshape(bits(1:bps*floor(numel(bits)/bps)),bps,[]).'*2.^(bps-1:-1:0).';
                truth=ref(labels+1);
            end
            return;
        end
        if strcmp(name,'APSKAcquisition')
            D.APSKAcquisition=x;
            return;
        end
        if strcmp(name,'APSKInternalStages')
            stages=fieldnames(x.PhaseStages);
            for stageIndex=1:numel(stages)
                score(['APSK_' stages{stageIndex}],x.PhaseStages.(stages{stageIndex}));
            end
            D.BPSInfo=x.PhaseStageInfo.BlindPhaseSearch;
            b=x.BlindPhaseSearch; centers=b.Centers;
            % Keep a sparse overview plus dense startup/focus windows only.
            keep=unique([1:64:numel(centers),find(centers<16384).', ...
                find(centers/p.symbolRate>=focus(1) & centers/p.symbolRate<=focus(2)).']);
            fields=fieldnames(b);
            for fieldIndex=1:numel(fields)
                value=b.(fields{fieldIndex});
                if numel(value)==numel(centers), value=value(keep); end
                D.BPSState.(fields{fieldIndex})=value;
            end
            return;
        end
        if strcmp(name,'CarrierPhase')
            idx=captureIndices(numel(x));
            D.Captures.(name)=struct('Index',idx,'Samples',x(idx));
            return;
        end
        if strcmp(name,'MatchedFilter')
            filterSPS=x.SamplesPerSymbol;
            assert(filterSPS==fix(filterSPS) && filterSPS>=1);
            for samplePhase=1:filterSPS
                score(sprintf('FilterPhase%d',samplePhase), ...
                    x.Samples(samplePhase:filterSPS:end));
            end
            return;
        end
        if strcmp(name,'CarrierInput') && whichCase=="apsk"
            inputPrefix=x(1:min(numel(x),32768)); inputPower=mean(abs(x).^2)+eps;
        end
        score(name,x);
    end

    function idx=captureIndices(n)
        idx=unique([100001:104096, max(1,floor(focus(1)*p.symbolRate)): ...
            min(n,ceil(focus(2)*p.symbolRate))]).';
        if startsWith(whichCase,"apsk16"), idx=unique([idx;(1:16384)']); end
        idx=idx(idx<=n); assert(numel(idx)<=65536);
    end

    function score(name,x)
        x=x(:); n=min(numel(x),numel(truth))-256;
        anchor=(100001:104096)';
        best=-Inf; lag=0;
        for delta=-128:128
            z=truth(anchor+delta); v=x(anchor);
            if startsWith(whichCase,"apsk")
                z=abs(z)-mean(abs(z)); v=abs(v)-mean(abs(v));
            end
            c=abs(z'*v)/sqrt(sum(abs(z).^2)*sum(abs(v).^2));
            if c>best, best=c; lag=delta; end
        end
        g0=truth(anchor+lag)'*x(anchor)/sum(abs(truth(anchor+lag)).^2);
        D.Alignment.(name)=struct('Lag',lag,'Coherence',best,'Gain',g0);
        starts=unique([257:4096:n-4096, max(257,floor(focus(1)*p.symbolRate)):512:min(n-512,ceil(focus(2)*p.symbolRate))]);
        rows=zeros(numel(starts),7);
        for j=1:numel(starts)
            ix=(starts(j):starts(j)+511)'; z=truth(ix+lag); v=x(ix);
            g=z'*v/sum(abs(z).^2);
            fixed=v/g0; local=v/g;
            [~,ti]=min(abs(z-ref.').^2,[],2);
            [~,fi]=min(abs(fixed-ref.').^2,[],2);
            [~,li]=min(abs(local-ref.').^2,[],2);
            rows(j,:)=[mean(ix)/p.symbolRate,mean(fi~=ti),mean(li~=ti), ...
                180/pi*angle(g/g0),sqrt(mean(abs(local-z).^2)/mean(abs(z).^2)), ...
                abs(g),mean(abs(v).^2)];
        end
        D.StageTables.(name)=array2table(rows,'VariableNames', ...
            {'Time_s','FixedAnchorSER','LocalScalarSER','Phase_deg','LocalEVM','Gain','Power'});
        idx=captureIndices(n);
        idx=idx(idx+lag>=1 & idx+lag<=numel(truth));
        D.Captures.(name)=struct('Index',idx,'Samples',x(idx),'Truth',truth(idx+lag));
    end
end

function [R,path]=localAPSK16Report(root)
% Saved waveform only. Reference-aided fits are OFFLINE bounds, never RX.
folder=fullfile(root,'artifacts','ccsds','system-eq');
files=dir(fullfile(folder,'Diagnosis_apsk16_*.mat'));
files=files(~cellfun('isempty',regexp({files.name}, ...
    '^Diagnosis_apsk16_\d{8}_\d{6}_\d{3}\.mat$','once')));
assert(~isempty(files),'Run apsk16 first.');
[~,last]=max([files.datenum]); source=fullfile(files(last).folder,files(last).name);
s=load(source,'D'); D=s.D;
addpath(fullfile(root,'src','python','apsk_pilotless_stage2_asm'));
c=D.Captures.APSK_NormalizedInput; use=c.Index<=16384;
x=c.Samples(use); tr=c.Truth(use); assert(all(diff(c.Index(use))==1));
ref=HelperCCSDSFACMReferenceConstellation(14); ref=ref(:);
Rs=D.Input.symbolRate; n=(1:numel(x))';
train=n>=513 & n<=8192; test=n>=8704 & n<=16000;
ix=find(train); count=64*floor(numel(ix)/64); ix=ix(1:count);
bx=reshape(x(ix),64,[]); bt=reshape(tr(ix),64,[]);
gains=sum(conj(bt).*bx)./sum(abs(bt).^2);
times=mean(reshape(ix,64,[]));
fit=polyfit(times,unwrap(angle(gains)),1);
cfo=fit(1)*Rs/(2*pi); y=x.*exp(-1j*fit(1)*n);
g=tr(train)'*y(train)/(tr(train)'*tr(train));
X=zeros(numel(x),17);
for lag=-8:8
    valid=n+lag>=1 & n+lag<=numel(x);
    X(valid,lag+9)=y(n(valid)+lag);
end
w=X(train,:)\tr(train);
[blind,blindInfo]=HelperTMBlindAcquisitionEqualizer(x,ref,struct('AcquisitionSymbols',8192));
blindCorrected=blind.*exp(-1j*fit(1)*n);
gb=tr(train)'*blindCorrected(train)/(tr(train)'*tr(train));
signals={y/g,X*w,blindCorrected/gb}; labels=["scalar-CFO-only","oracle-FIR-17","blind-RDE-17"];
rows=cell(3,1);
for k=1:3
    v=signals{k}; [~,a]=min(abs(v(test)-ref.').^2,[],2);
    [~,b]=min(abs(tr(test)-ref.').^2,[],2);
    rows{k}=struct('Method',labels(k),'OfflineTruthFitSymbols',nnz(train),'ValidationSymbols',nnz(test), ...
        'SER',mean(a~=b),'EVM',norm(v(test)-tr(test))/norm(tr(test)));
end
R=struct('Source',source,'OfflineOnly',true,'TrainingCFO_Hz',cfo, ...
    'FIRComparison',struct2table(vertcat(rows{:})),'BlindEQ',blindInfo,'OracleTaps',w);
% Same captured PREFIX for every carrier-only comparison, starting at the
% same index (11). This is not a replay of the complete 82-ms receiver state.
opts=D.APSKAcquisition.Options; opts.NormalizeInputPower=false;
opts.CapturePhaseStages=false; rows=cell(4,1);
labels=["original-prefix","no-NDA-residual","no-ring-normalizer","blind-FIR-before-acquisition"];
for k=1:4
    opt=opts; signal=x;
    if k==2, opt.ApplyNDAResidualCFO=false; end
    if k==3, opt.EnableRingNormalizer=false; end
    if k==4, signal=blind; end
    [v,~,info]=HelperTMAPSKCarrierRecovery(signal,'16APSK',opt);
    anchor=1025:2048; g0=tr(anchor)'*v(anchor)/(tr(anchor)'*tr(anchor));
    quadrant=round(angle(g0)/(pi/2))*(pi/2);
    scale=sqrt(mean(abs(v(train)).^2)/mean(abs(tr(train)).^2));
    corrected=v/scale*exp(-1j*quadrant);
    [~,a]=min(abs(corrected(test)-ref.').^2,[],2);
    [~,b]=min(abs(tr(test)-ref.').^2,[],2);
    rows{k}=struct('Method',labels(k),'Qualified',info.AcquisitionQualified, ...
        'CoarseCFO_Hz',info.FourthPowerCFO_Hz,'NDAResidualCFO_Hz',info.NDAResidualCFO_Hz, ...
        'SER',mean(a~=b),'EVM',norm(corrected(test)-tr(test))/norm(tr(test)), ...
        'AnchorQuadrant_deg',rad2deg(quadrant));
end
R.PrefixCarrierComparison=struct2table(vertcat(rows{:}));
path=fullfile(folder,'Diagnosis_apsk16_report.mat');
save(path,'R','-v7');
disp(R.FIRComparison); disp(R.PrefixCarrierComparison);
fprintf('OFFLINE local diagnosis, NOT full-link BER acceptance. Training CFO %.3f Hz.\nSaved %s\n',cfo,path);
end

function [R,path]=localReport(root)
% All fits below are OFFLINE instruments, never production receiver choices.
folder=fullfile(root,'artifacts','ccsds','system-eq');
allD=cell(3,1); names={'bpsk','qam','apsk'};
R=struct('OfflineOnly',true,'Sources',strings(3,1));
for k=1:3
    files=dir(fullfile(folder,['Diagnosis_' names{k} '_*.mat']));
    assert(~isempty(files),'Run each fixed case before report.');
    [~,last]=max([files.datenum]);
    R.Sources(k)=fullfile(files(last).folder,files(last).name);
    s=load(R.Sources(k),'D'); allD{k}=s.D;
    assert(s.D.Reproduced);
end
B=allD{1}; Q=allD{2}; A=allD{3};
rows={};
for name=["CarrierInput","CarrierOutput","PreTrackerOutput","PostTrackerOutput"]
    c=B.Captures.(name);
    for ms=[40.6 41.1]
        [~,center]=min(abs(c.Index-ms*30000)); ix=(center-256:center+255)';
        X=zeros(512,21);
        for lag=-10:10, X(:,lag+11)=c.Truth(ix+lag); end
        w=X\c.Samples(ix); [~,top]=sort(abs(w),'descend'); top=top(1:2);
        two=X(:,top)\c.Samples(ix);
        rows{end+1}=struct('Stage',name,'Time_ms',ms, ...
            'FirstLag',top(1)-11,'SecondLag',top(2)-11, ...
            'FirstCoefficient',two(1),'SecondCoefficient',two(2), ...
            'TwoSymbolResidual',norm(X(:,top)*two-c.Samples(ix))/norm(c.Samples(ix)), ...
            'RelativePhase_deg',angle(two(2)/two(1))*180/pi); %#ok<AGROW>
    end
end
R.BPSKMixture=struct2table(vertcat(rows{:}));
R.BPSKStages=B.StageTables;
R.QAMStages=Q.StageTables;
c=Q.Captures.CarrierPhase; times=[31.65 31.86 31.90 32.10 32.35]'; phase=zeros(size(times));
for k=1:numel(times)
    use=abs(c.Index/30000-times(k))<.005;
    phase(k)=median(c.Samples(use))*180/pi;
end
R.QAMCarrierPhase=table(times,phase,'VariableNames',{'Time_ms','Estimate_deg'});

% A single 17-tap least-squares upper bound, with separated training/test
% intervals. Even CFO is fitted from TRAINING truth only, never test labels.
addpath(fullfile(root,'src','python','apsk_pilotless_stage2_asm'));
x=A.AcquisitionPrefix; c=A.Captures.CarrierInput; Rs=A.Input.symbolRate;
use=c.Index>512 & c.Index<30000; ix=c.Index(use); tr=c.Truth(use);
train=ix<16000; test=ix>17000 & ix<29000;
ti=ix(train); tt=tr(train); count=64*floor(numel(ti)/64);
blocksX=reshape(x(ti(1:count)),64,[]); blocksT=reshape(tt(1:count),64,[]);
gain=sum(conj(blocksT).*blocksX)./sum(abs(blocksT).^2);
clock=mean(reshape(ti(1:count),64,[]))/Rs;
line=polyfit(clock,unwrap(angle(gain)),1); cfo=line(1)/(2*pi);
y=x.*exp(-1j*2*pi*cfo*(0:numel(x)-1)'/Rs);
g=tr(train)'*y(ix(train))/(tr(train)'*tr(train));
X=zeros(numel(ix),17);
for lag=-8:8, X(:,lag+9)=y(ix+lag); end
w=X(train,:)\tr(train); after=X(test,:)*w; before=y(ix(test))/g;
ref=HelperCCSDSFACMReferenceConstellation(21); ref=ref(:);
[~,truthLabel]=min(abs(tr(test)-ref.').^2,[],2);
[~,beforeLabel]=min(abs(before-ref.').^2,[],2);
[~,afterLabel]=min(abs(after-ref.').^2,[],2);
R.APSK=struct('TrainingOnlyCFO_Hz',cfo,'TrainSymbols',nnz(train), ...
    'ValidationSymbols',nnz(test),'BeforeSER',mean(beforeLabel~=truthLabel), ...
    'AfterOracleFIR_SER',mean(afterLabel~=truthLabel), ...
    'BeforeEVM',norm(before-tr(test))/norm(tr(test)), ...
    'AfterOracleFIR_EVM',norm(after-tr(test))/norm(tr(test)), ...
    'OracleTaps',w,'OriginalCoarse',A.APSKAcquisition.Info.CoarseAcquisition);
% Restore the carrier we removed for fitting; the CFO estimator must still
% acquire it. The estimator itself sees no reference sequence or true CFO.
fullIndex=(9:numel(x)-8)'; X=zeros(numel(fullIndex),17);
for lag=-8:8, X(:,lag+9)=y(fullIndex+lag); end
restored=(X*w).*exp(1j*2*pi*cfo*(fullIndex-1)/Rs);
acq=A.APSKAcquisition.Info.CoarseAcquisition;
opts=struct('AcquisitionSymbols',acq.CandidateSymbols,'FFTLength',acq.FFTLength, ...
    'MaxCFOHz',acq.MaxCFOHz,'PowerOrder',acq.PowerOrder,'MinConfidenceDB',6, ...
    'UseUnitMagnitude',acq.UseUnitMagnitude,'VerifyOnHoldout',acq.VerifyOnHoldout, ...
    'RadiusMax',acq.RadiusMax,'MinSelectedSymbols',acq.MinSelectedSymbols);
[~,R.APSK.AfterOracleFIR_Coarse]=HelperTMAPSKFourthPowerCoarseCFO(restored,Rs,opts);
path=fullfile(folder,'Diagnosis_fixed_cases_report.mat');
save(path,'R','-v7');
disp(R.BPSKMixture); disp(R.QAMCarrierPhase); disp(R.APSK);
fprintf('OFFLINE upper bound, NOT a production repair or full-link BER acceptance.\nSaved %s\n',path);
end
