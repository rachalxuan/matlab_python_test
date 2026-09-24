% Fixed failing case, plus RRC control. No DSP/warmup/FEC tuning.
% TX truth is accessed ONLY after run_ccsds_tm_evaluation returns.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
outDir=fullfile(root,'tmp','uqpsk_rc_stage_debug');
if ~exist(outDir,'dir'), mkdir(outDir); end
diary(fullfile(outDir,'console.txt'));
diaryGuard=onCleanup(@() diary('off'));
UQRC_Debug=struct(); UQRC_Debug.Runs=cell(2,1);
shapes=["raised cosine","root raised cosine"];
for ic=1:2
    fprintf('\n========== UQPSK STAGE DEBUG %d/2: %s ==========\n',ic,shapes(ic));
    p=struct('modType','UQPSK','symbolRate',10e6,'sps',8, ...
        'channelCoding','none','NumBytesInTransferFrame',256, ...
        'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
        'PCMFormat','NRZ-L','PulseShapingFilter',char(shapes(ic)), ...
        'RolloffFactor',.35,'FilterSpanInSymbols',10,'noiseMode','off', ...
        'cfo',0,'phaseOffset',0,'delay',0,'berWarmUpFrames',8, ...
        'berFrames',120,'excludeBERWarmUpFrames',true,'enableHChannel',false, ...
        'enableEqualizer',false,'showFigures',false,'enableReceiverTimeline',true);
    fprintf('[1 CONFIG] No-H/noise-off, TF=256, warmup=8, measured=120, seed=917\n');
    fprintf('Fs=80 MHz, Rs=10 Msym/s, 2080 coded bits/TF, 3 bits -> 2 UQPSK symbols.\n');
    rng(917,'twister'); baseLog=evalc('baseline=run_ccsds_tm_evaluation(p);');
    assert(baseline.success,'Baseline failed: %s',getError(baseline));
    p.debugUQPSKPulseStages=true;
    p.debugUQPSK=true; % printing only; do NOT enable debugSynchronizationChain
    rng(917,'twister'); debugLog=evalc('m=run_ccsds_tm_evaluation(p);');
    assert(m.success,'Debug run failed: %s',getError(m));
    d=m.UQPSKPulseDebug;
    same=isequaln(baseline.BER,m.BER) && isequaln(baseline.FER,m.FER) && ...
        isequaln(baseline.MeasurementCoverage,m.MeasurementCoverage) && ...
        isequaln(baseline.ReceiverTimeline.Rows,m.ReceiverTimeline.Rows) && ...
        isequaln(baseline.PhaseAmbiguityRotation_deg,m.PhaseAmbiguityRotation_deg) && ...
        isequaln(baseline.UQPSKSymSkip,m.UQPSKSymSkip);
    fprintf('[2 NON-INTERFERENCE] debug off/on identical = %d\n',same);
    % Save before assertions so unexpected changes remain inspectable.
    UQRC_Debug.Runs{ic}=struct('Parameters',p,'Baseline',baseline, ...
        'Metrics',m,'BaselineLog',baseLog,'DebugLog',debugLog,'Unchanged',same);
    save(fullfile(outDir,'latest.mat'),'UQRC_Debug','-v7.3');
    assert(same,'Debug changed receiver output; do not interpret diagnostics.');
    fprintf('[3 FRONT END] CFO=%+.6f Hz; filter=%d samples @ %g sps; timing=%d; carrier=%d\n', ...
        d.CoarseCFO_Hz,numel(d.Filtered),d.FilterSPS,numel(d.Timing),numel(d.Carrier));
    fprintf('Selected receiver rotation=%+.1f deg; grouping symSkip=%g\n', ...
        d.SelectedRotation_deg,d.SelectedSymbolSkip);
    disp(d.CarrierInfo);
    truth=uqpskMapBitsLocal(d.EncodedBits,2,2);
    [mf,mfa]=stageWindows(d.Filtered,truth,d.FilterSPS,'matched-filter fixed-grid');
    [tm,tma]=stageWindows(d.Timing,truth,1,'post-timing');
    [cr,cra]=stageWindows(d.Carrier,truth,1,'post-carrier');
    fprintf('[4 STAGES] Fixed lag + ONE late-window complex gain; NO per-window phase correction.\n');
    fprintf('MF is an offline fixed-grid probe, not the production timing decision.\n');
    fprintf('TXFrame windows are approximate symbol ranges (2080/1.5 is noninteger).\n');
    disp(mfa); disp(mf); disp(tma); disp(tm); disp(cra); disp(cr);
    fprintf('[5 SOFT + ASM] Actual selected demapper output; positive soft means bit 1.\n');
    [soft,softAnchor]=softWindows(d.SelectedFrameDebug.RawSoft,d.EncodedBits);
    disp(softAnchor); disp(soft);
    fprintf('[6 COUNTING GATE] Selected candidate only (not rejected phase/group hypotheses).\n');
    f=d.SelectedFrameDebug;
    fprintf('First measurement TX frame=%d; required consecutive=%d; acquisition max BER=%g\n', ...
        f.FirstMeasurementFrame,f.AcquisitionConsecutiveFrames,f.AcquisitionMaxFrameBER);
    disp(f.Gate(f.Gate.RxFrame<=24,:));
    fprintf('[7 TIMELINE] All measurement holes/errors, including observed-but-not-counted errors.\n');
    T=struct2table(m.ReceiverTimeline.Rows);
    disp(T(T.MeasurementEligible & (T.ComparedBitsDelta==0 | T.ErrorBitsDelta>0), ...
        {'TxFrameIndex','Coverage','ObservedErrorBits','ComparedBitsDelta','ErrorBitsDelta','VCFCValid'}));
    fprintf('FINAL BER=%g FER=%g compared=%d/%d coverage=%s\n',m.BER,m.FER, ...
        m.CountedFrames,m.MeasurementCoverage.ExpectedFrames,m.MeasurementCoverage.Status);
    UQRC_Debug.Runs{ic}.Stages=struct('MatchedFilter',mf,'Timing',tm,'Carrier',cr, ...
        'MFAnchor',mfa,'TimingAnchor',tma,'CarrierAnchor',cra,'Soft',soft,'SoftAnchor',softAnchor);
    save(fullfile(outDir,'latest.mat'),'UQRC_Debug','-v7.3');
end
fprintf('\nDEBUG COMPLETE (not a BER pass verdict). Send this console.txt; raw captures are in latest.mat.\n');
fprintf('%s\n',outDir);
clear diaryGuard;

function message=getError(m)
message=''; if isfield(m,'errorMsg'), message=m.errorMsg; end
end

function [T,A]=stageWindows(x,ref,sps,name)
% Anchor against a single late 4096-symbol block. This is an offline ruler,
% not a recovered timing track. Wrong lag/low correlation must stay visible.
probe=(floor(numel(ref)*.6)+(1:4096)).';
best=-Inf; bestLag=0; bestPhase=1; bestGain=NaN;
for phase=1:sps
    seq=x(phase:sps:end);
    for lag=-128:128
        k=probe+lag;
        if k(1)<1 || k(end)>numel(seq), continue; end
        z=seq(k); r=ref(probe);
        score=abs(r'*z)/sqrt(sum(abs(r).^2)*sum(abs(z).^2)+eps);
        if score>best
            best=score; bestLag=lag; bestPhase=phase; bestGain=(r'*z)/(r'*r);
        end
    end
end
A=table(string(name),bestPhase,bestLag,best,abs(bestGain),rad2deg(angle(bestGain)), ...
    'VariableNames',{'Stage','DecimationPhase','FixedLag','AnchorCorrelation','Gain','ConstantPhase_deg'});
seq=x(bestPhase:sps:end)/bestGain;
rows=zeros(24,8);
for f=1:24
    t=(ceil((f-1)*2080/1.5)+1:floor(f*2080/1.5)).';
    t=t(t+bestLag>=1 & t+bestLag<=numel(seq) & t<=numel(ref));
    z=seq(t+bestLag); r=ref(t);
    err=(real(z)<0)~=(real(r)<0) | (imag(z)<0)~=(imag(r)<0);
    ph=angle(z.*conj(r)); mu=angle(mean(exp(1j*ph)));
    lagSER=nan(1,5);
    for j=1:5
        k=t+bestLag+j-3;
        ok=k>=1 & k<=numel(seq);
        zz=seq(k(ok)); rr=r(ok);
        lagSER(j)=mean((real(zz)<0)~=(real(rr)<0) | (imag(zz)<0)~=(imag(rr)<0));
    end
    [~,ii]=min(lagSER);
    rows(f,:)=[f,numel(t),nnz(err),100*mean(err), ...
        100*sqrt(mean(abs(z-r).^2)/mean(abs(r).^2)),rad2deg(mu), ...
        rad2deg(sqrt(mean(angle(exp(1j*(ph-mu))).^2))),ii-3];
end
T=array2table(rows,'VariableNames',{'TXFrame','Symbols','SymbolErrors','SER_pct', ...
    'FixedGainEVM_pct','PhaseMean_deg','PhaseJitter_deg','BestLocalLagDelta'});
end

function [T,A]=softWindows(soft,bits)
bits=logical(bits(:)); h=soft(:)>0;
probe=(floor(numel(bits)*.6)+(1:4096)).';
scores=inf(1,1025);
for lag=-512:512
    k=probe+lag;
    if k(1)>=1 && k(end)<=numel(h), scores(lag+513)=mean(h(k)~=bits(probe)); end
end
[anchorBER,idx]=min(scores); lag=idx-513;
A=table(lag,anchorBER,'VariableNames',{'SoftBitLag','LateAnchorBER'});
rows=zeros(24,6);
for f=1:24
    t=((f-1)*2080+(1:2080)).';
    ok=t+lag>=1 & t+lag<=numel(h) & t<=numel(bits);
    err=nan(2080,1); err(ok)=h(t(ok)+lag)~=bits(t(ok));
    rows(f,:)=[f,nnz(ok),sum(err(1:32),'omitnan'),sum(err(33:end),'omitnan'), ...
        mean(err,'omitnan'),min(abs(soft(t(ok)+lag)))];
end
T=array2table(rows,'VariableNames',{'TXFrame','ComparedCodedBits','ASMErrors', ...
    'TFErrors','RawBER','MinAbsSoft'});
end
