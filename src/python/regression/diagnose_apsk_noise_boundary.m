function outputFile = diagnose_apsk_noise_boundary(sourceFile, caseIndex)
% Fixed-waveform, offline-only instruments. No receiver parameter tuning.
% Default: reproduce saved PSD-equivalent 16APSK/RRC/10-dB case.
% No samples are saved; one compact MAT contains tables, checks and logs.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
if nargin<1 || isempty(sourceFile)
    sourceFile=fullfile(root,'tmp','APSK_NoiseModeCompare_20261008_104234_192.mat');
end
if nargin<2, caseIndex=2; end
d=load(sourceFile,'NoiseTestInputs','NoiseTestResults');
p=d.NoiseTestInputs{caseIndex}; expected=d.NoiseTestResults(caseIndex,:);
% This instrument reproduces the HISTORICAL failure, not current defaults.
% Use test_apsk_bps_trajectory for old/new/default acceptance.
p.PilotlessAPSKCarrierRecovery.BlindPhaseSearchTrajectoryMode='legacy';
assert(strcmpi(p.modType,'16APSK') && strcmpi(p.channelCoding,'convolutional'));
assert(strcmp(p.ConvolutionalCodeRate,'3/4') && p.sps==8);
assert(~p.enableHChannel && ~p.enableEqualizer && ~p.AGCEnabled);
assert(p.cfo==0 && p.phaseOffset==0 && p.delay==0);
assert(strcmpi(p.DataPathMode,'single') && ~p.RandomizerEnabled && p.hasASM);
assert(any(strcmp(p.PulseShapingFilter,{'root raised cosine','none'})));
p.captureBaselineData=true;
p.enableReceiverTimeline=true; p.enableRuntimeLockTelemetry=true;
p.debugSynchronizationChain=true;
outputFile=fullfile(root,'tmp',['APSK_NoiseBoundary_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.mat']);
fprintf('OFFLINE DIAGNOSIS: %s, saved case %d\n',p.PulseShapingFilter,caseIndex);
fprintf('Known zero CFO/phase/delay are diagnostic information, NOT production RX inputs.\n');
rng(p.randomSeed,'twister');
logText=evalc('r=run_ccsds_tm_evaluation(p);');
assert(r.success,'Main receiver failed: %s',logText);
checks=struct();
checks.BaselineBER=isequaln(r.BER,expected.BER);
checks.BaselineFER=isequaln(r.FER,expected.FER);
checks.BaselineCoverage=r.MeasurementCoverage.ComparedFrames==expected.Compared;
assert(checks.BaselineBER && checks.BaselineFER && checks.BaselineCoverage, ...
    'Captured run did not reproduce the saved case; do not interpret A/B.');
ActualReceiver=struct('BER',r.BER,'FER',r.FER,'Coverage',r.MeasurementCoverage);
ActualFrames=struct2table(r.ReceiverTimeline.Rows);
c=r.BaselineCapture; pc=c.PulseStageCapture;
txBits=double(pc.TxEncodedBits(:));
txFrames=double(cat(2,pc.TxTransferFrames{:}));
ref=HelperCCSDSFACMReferenceConstellation(14); ref=ref(:);
nTruth=floor(numel(txBits)/4);
labels=reshape(txBits(1:4*nTruth),4,[]).'*[8;4;2;1];
truth=ref(labels+1);
% The same public mapping helper must reproduce all 16 labels and polarity.
checks.ConstellationLabels=isequal( ...
    HelperCCSDSFACMDemodulate(ref,14,1)>0,logical(reshape(int2bit(0:15,4),[],1)));
assert(checks.ConstellationLabels,'Constellation label/polarity mismatch.');

% Full-rate matching filter on the SAME captured noisy waveform.
% Its time grid follows known TX pulse delay, not a BER-minimizing phase scan.
pulse=HelperTMPulseShapeConfig(p.PulseShapingFilter,p.sps, ...
    p.RolloffFactor,p.FilterSpanInSymbols);
if strcmp(p.PulseShapingFilter,'none')
    matched=filter(pulse.ReceiveTaps,1,c.CoarseSynchronizedWaveform);
    cleanMatched=filter(pulse.ReceiveTaps,1,c.TxWaveform);
    reconstructed=matched;
    firstSample=p.sps; % end of the first rectangular hold/integration
else
    f=comm.RaisedCosineReceiveFilter('Shape',pulse.FilterShape, ...
        'RolloffFactor',p.RolloffFactor,'FilterSpanInSymbols',p.FilterSpanInSymbols, ...
        'InputSamplesPerSymbol',p.sps,'DecimationFactor',1);
    matched=f(c.CoarseSynchronizedWaveform); reset(f);
    cleanMatched=f(c.TxWaveform);
    reconstructed=matched(1:p.sps/pc.TimingConfiguration.SamplesPerSymbol:end);
    firstSample=p.FilterSpanInSymbols*p.sps+1; % TX+RX group delay
end
checks.FilterReplayRelativeError=norm(reconstructed-pc.Filtered)/max(norm(pc.Filtered),eps);
assert(checks.FilterReplayRelativeError<1e-12,'Matching-filter replay differs.');
fixed=matched(firstSample:p.sps:end);
cleanFixed=cleanMatched(firstSample:p.sps:end);
assert(numel(cleanFixed)>=nTruth,'Clean fixed-grid control is truncated.');
% A single positive calibration scalar is measured on CLEAN TX only.
% It does not remove noisy phase/amplitude error from any test stream.
cal=512:min(4096,nTruth);
cleanGain=real(truth(cal)'*cleanFixed(cal)/(truth(cal)'*truth(cal)));
checks.CleanGain=cleanGain;
checks.CleanGridSER=mean(nearest(cleanFixed(cal)/cleanGain,ref)~=labels(cal));
assert(cleanGain>0 && checks.CleanGridSER==0,'Known-grid clean control failed.');

[timeReplay,~]=HelperTMSymbolSynchronizerChunked(pc.Filtered,pc.TimingConfiguration);
checks.TimingReplayExact=isequaln(timeReplay,c.TimeSynchronizedSymbols);
assert(checks.TimingReplayExact,'Timing replay not identical.');
[pilot,~,pilotState]=HelperTMAPSKPilotlessFrontEnd(timeReplay,'16APSK',p);
checks.PilotlessReplayExact=isequaln(pilot,pc.PilotlessOutput);
assert(checks.PilotlessReplayExact,'Pilotless replay not identical.');
% ONE integer lag from a prefix wholly inside warmup. Never re-align bad frames.
warmSymbols=floor(p.berWarmUpFrames*(32+8*p.NumBytesInTransferFrame)/3);
[lag,coherence]=prefixLag(timeReplay,truth,min(4096,warmSymbols));
checks.TimingPrefixLag=lag; checks.TimingPrefixCoherence=coherence;
assert(coherence>0.9,'Cannot establish a reliable warmup timing anchor.');
assert(numel(c.FineSynchronizedSymbols)==numel(timeReplay));

% Replay the SAME timing output, with capture only (no algorithm overrides).
traceP=p;
if ~isfield(traceP,'PilotlessAPSKCarrierRecovery')
    traceP.PilotlessAPSKCarrierRecovery=struct();
end
traceP.PilotlessAPSKCarrierRecovery.CapturePhaseStages=true;
[traceOut,traceInfo,traceState]=HelperTMAPSKPilotlessFrontEnd(timeReplay,'16APSK',traceP);
checks.PhaseStageCaptureOutputExact=isequaln(traceOut,pilot);
assert(checks.PhaseStageCaptureOutputExact,'Phase instrumentation changed output.');
[PilotlessStageSummary,PilotlessWindows,BPSFirstEvent,CarrierDiagnostics,BPSBadObservations]= ...
    inspectPilotlessStages(traceState,traceInfo,traceOut,truth,labels,ref,lag,p);
clear traceState traceOut;

% B removes the receiver-applied pointwise phase ONLY. It preserves A's
% amplitudes and the original noisy timing-output phase. No TX symbol phase
% is used here; this control is valid only for known-zero physical CFO/phase.
a=c.FineSynchronizedSymbols;
finalScalar=(pilot'*a)/(pilot'*pilot);
checks.FinalVsPilotlessScalarRelativeError=norm(a-finalScalar*pilot)/max(norm(a),eps);
checks.FinalVsPilotlessConstantAngle_deg=angle(finalScalar)*180/pi;
b=abs(a).*exp(1j*angle(timeReplay));
checks.PhaseControlAmplitudeError=max(abs(abs(a)-abs(b)));
names=["A_actual_final","B_known_phase_keep_gain", ...
    "C_actual_timing_bypass_pilotless","D_known_grid_bypass_pilotless"];
signals={a,b,timeReplay/cleanGain,fixed/cleanGain};
lags=[lag lag lag 0];
rows={}; stageFrames={}; windows={}; infoByStage={};
for j=1:numel(signals)
    z=signals{j};
    demod=HelperCCSDSTMDemodulator('Modulation','16APSK', ...
        'ChannelCoding','convolutional','NoiseVariance',pc.DemodNoiseVariance);
    soft=double(demod(z));
    rx=HelperTMContinuousConvReceiver('CodeRate','3/4', ...
        'FramePayloadBits',8*p.NumBytesInTransferFrame, ...
        'SoftClip',max(abs(soft)),'ConvolutionalG1G2Mode','auto-ccsds','Verbose',false);
    rx.append(soft); [payload,info]=rx.finalize();
    % Physical pairing is an OFFLINE instrument. No VCFC/content-based frame
    % selection and no exclusion of frames because their payload is wrong.
    [fr,summary]=pairByPosition(payload,info,txFrames,lags(j),p,names(j));
    [metrics,w]=symbolMetrics(z,soft,truth,txBits,labels,ref,lags(j),p,names(j));
    summary.PreBER=metrics.PreBER; summary.SER=metrics.SER;
    summary.EVM_pct=metrics.EVM_pct; summary.MaxErrorRunSymbols=metrics.MaxErrorRunSymbols;
    summary.ASMRun=info.Candidates(info.SelectedCandidate).LongestGoodRun;
    summary.PunctureOffset=info.SelectedOffset;
    rows{j}=summary; stageFrames{j}=fr; windows{j}=w; infoByStage{j}=info; %#ok<AGROW>
end
StageSummary=struct2table(vertcat(rows{:}));
FrameComparison=vertcat(stageFrames{:}); Windows=vertcat(windows{:});
PhaseSegments=phaseSegments(Windows(Windows.Stage==names(1),:),p.symbolRate);
% Replay A's payload errors for EVERY frame officially compared. The offline
% instrument may additionally pair frames that production left unpaired;
% that difference is explicitly reported, never called a production pass.
af=stageFrames{1}; measured=ActualFrames.MeasurementEligible & ActualFrames.ComparedBitsDelta>0;
for i=find(measured).'
    q=find(af.TxFrameIndex==ActualFrames.TxFrameIndex(i),1);
    assert(~isempty(q) && af.ComparedBits(q)==ActualFrames.ComparedBitsDelta(i) && ...
        af.ErrorBits(q)==ActualFrames.ErrorBitsDelta(i), ...
        'A replay disagrees with actual compared frame %d.',ActualFrames.TxFrameIndex(i));
end
checks.ActualComparedFramesReproduced=true;
% Only compact receiver-state timelines; no waveforms/LLR/TX payload saved.
BPS=table();
if isfield(pilotState.Carrier,'BlindPhaseSearch')
    s=pilotState.Carrier.BlindPhaseSearch;
    if isfield(s,'Centers') && isfield(s,'Reliable')
        BPS=table(double(s.Centers(:)),logical(s.Reliable(:)), ...
            'VariableNames',{'RxSymbol','Reliable'});
    end
end
save(outputFile,'p','sourceFile','caseIndex','expected','checks','ActualReceiver', ...
    'ActualFrames','StageSummary','FrameComparison','Windows','PhaseSegments', ...
    'BPS','infoByStage','logText','PilotlessStageSummary','PilotlessWindows', ...
    'BPSFirstEvent','CarrierDiagnostics','BPSBadObservations','-v7');
fprintf('\nAll replay/instrument checks passed.\n'); disp(checks);
fprintf('PRODUCTION result (unchanged): BER=%g FER=%g compared=%d/%d\n', ...
    r.BER,r.FER,r.MeasurementCoverage.ComparedFrames,r.MeasurementCoverage.ExpectedFrames);
fprintf('OFFLINE known-position comparisons below are NOT production coverage:\n');
disp(StageSummary);
fprintf('Actual final phase branches (512-symbol windows; transition times are approximate):\n');
disp(PhaseSegments);
fprintf('PILOTLESS stage attribution (fixed warmup phase branch, NOT window-wise correction):\n');
disp(PilotlessStageSummary);
disp(CarrierDiagnostics);
fprintf('BPS centers around first post-anchor branch departure (offline observation only):\n');
if ~isempty(BPSFirstEvent)
    selected=abs(BPSFirstEvent.CenterOffset)<=5 | mod(BPSFirstEvent.CenterOffset,8)==0;
    disp(BPSFirstEvent(selected,:));
end
fprintf('Accepted wrong BPS measurements near that event (truth is diagnostic only):\n');
disp(BPSBadObservations);
uncompared=ActualFrames.MeasurementEligible & ActualFrames.RecoveredCopies>0 & ...
    ActualFrames.ComparedBitsDelta==0;
fprintf('Production recovered-but-uncompared frames (not silently counted as pass):\n');
disp(ActualFrames(uncompared,{'TxFrameIndex','Coverage','RecoveredCopies', ...
    'ComparedBitsDelta','ErrorBitsDelta','ObservedErrorBits'}));
fprintf('Compact report (no samples): %s\n',outputFile);
end

function [summary,windows,event,diagnostics,badObservations]=inspectPilotlessStages(st,inf,y,truth,labels,ref,lag,p)
signals=st.Carrier.PhaseStages;
signals.PostGain=y;
names=fieldnames(signals); sr=cell(numel(names),1); wr=cell(numel(names),1);
for j=1:numel(names)
    z=signals.(names{j}); z=z/sqrt(mean(abs(z).^2));
    ti=(512:min(numel(truth),numel(z)+lag)).'; ri=ti-lag;
    anchor=ti<=1023;
    a=angle(sum(z(ri(anchor)).*conj(truth(ti(anchor)))));
    fixedBranch=round(a/(pi/2));
    err=nearest(z(ri)*exp(-1j*fixedBranch*pi/2),ref)~=labels(ti);
    phase=angle(z(ri).*conj(truth(ti)));
    winRows={};
    for k=1:128:numel(ti)
        ix=k:min(k+127,numel(ti));
        ph=angle(mean(exp(1j*phase(ix))));
        branch=round(angle(exp(1j*(ph-fixedBranch*pi/2)))/(pi/2));
        winRows{end+1}=struct('Stage',string(names{j}), ...
            'TxSymbol',ti(ix(1)),'RxSymbol',ri(ix(1)), ...
            'Time_ms',(ti(ix(1))-1)/p.symbolRate*1e3, ...
            'Phase_deg',ph*180/pi,'RelativeBranch_deg',branch*90, ...
            'SER',mean(err(ix))); %#ok<AGROW>
    end
    w=struct2table(vertcat(winRows{:})); wr{j}=w;
    % Require two consecutive windows in the same non-anchor branch.
    b=w.RelativeBranch_deg;
    q=find(w.TxSymbol(1:end-1)>1023 & b(1:end-1)~=0 & ...
        b(1:end-1)==b(2:end),1);
    firstTime=NaN; firstSymbol=NaN;
    if ~isempty(q), firstTime=w.Time_ms(q); firstSymbol=w.RxSymbol(q); end
    sr{j}=struct('Stage',string(names{j}),'FixedAnchorBranch_deg',fixedBranch*90, ...
        'SER_FixedBranch',mean(err),'FirstPersistentDeparture_ms',firstTime, ...
        'FirstDepartureRxSymbol',firstSymbol, ...
        'NonAnchorWindows',nnz(b~=0));
end
summary=struct2table(vertcat(sr{:})); windows=vertcat(wr{:});
ci=inf.Carrier;
diagnostics=struct('CoarseCFO_Hz',ci.FourthPowerCFO_Hz, ...
    'NDAResidualCFO_Hz',ci.NDAResidualCFO_Hz, ...
    'NDAResidualCFOApplied',ci.NDAResidualCFOApplied, ...
    'AcquisitionPhase_deg',ci.AcquisitionPhase_deg, ...
    'MthApplied',ci.MthPowerPhaseTrackerApplied, ...
    'PreGainApplied',ci.PreDDGainTrackerApplied, ...
    'RingApplied',ci.RingNormalizerApplied, ...
    'BPSApplied',ci.BlindPhaseSearchApplied, ...
    'DDEnabled',ci.DDPhaseTrackerEnabled, ...
    'DDResidualLimit_deg',ci.DDResidualPhaseLimit_deg);
event=table(); badObservations=table();
if ci.BlindPhaseSearchApplied
    bs=st.Carrier.BlindPhaseSearch;
    row=summary(summary.Stage=="BlindPhaseSearch",:);
    if isfinite(row.FirstDepartureRxSymbol)
        % Expected local phase is an offline truth observation, never an
        % estimator input. Locate the actual center-level 45-degree crossing
        % preceding the persistent 128-symbol-window departure.
        input=signals.RingNormalizer;
        ti=(1:numel(input)).'+lag;
        good=ti>=1 & ti<=numel(truth);
        cross=complex(zeros(size(input)));
        cross(good)=input(good).*conj(truth(ti(good)));
        expectedPhase=angle(movsum(cross,[16 16],'Endpoints','shrink'));
        appliedPhase=bs.PhaseAtCentersRad;
        residual=angle(exp(1j*(expectedPhase(bs.Centers)-appliedPhase)));
        branch=round(residual/(pi/2));
        [~,kEnd]=min(abs(bs.Centers-row.FirstDepartureRxSymbol));
        target=branch(kEnd); k=kEnd;
        while k>1 && branch(k-1)==target, k=k-1; end
        diagnostics.FirstBPSDepartureRxSymbol=bs.Centers(k);
        diagnostics.FirstBPSDepartureTime_ms=(bs.Centers(k)+lag-1)/p.symbolRate*1e3;
        diagnostics.FirstBPSDepartureTxFrame=floor( ...
            (bs.Centers(k)+lag-1)*3/(32+8*p.NumBytesInTransferFrame))+1;
        diagnostics.BPSMaxMetric=st.Carrier.PhaseStageInfo.BlindPhaseSearch.MaxMetric;
        ix=(max(2,k-64):min(numel(bs.Centers),k+16)).';
        prediction=bs.PhaseAtCentersRad(ix-1)+bs.FrequencyRadPerSymbol(ix-1).* ...
            (bs.Centers(ix)-bs.Centers(ix-1));
        lifted=bs.MeasuredPhaseModuloRad(ix)+ ...
            round((prediction-bs.MeasuredPhaseModuloRad(ix))/(pi/2))*(pi/2);
        event=table(ix-k,bs.Centers(ix), ...
            (bs.Centers(ix)+lag-1)/p.symbolRate*1e3, ...
            expectedPhase(bs.Centers(ix))*180/pi, ...
            bs.MeasuredPhaseModuloRad(ix)*180/pi,prediction*180/pi, ...
            lifted*180/pi,bs.PhaseAtCentersRad(ix)*180/pi, ...
            bs.FrequencyRadPerSymbol(ix)*p.symbolRate/(2*pi), ...
            bs.BestMetric(ix),bs.Confidence(ix),bs.Reliable(ix), ...
            bs.TrackingAction(ix),bs.FadeHold(ix),'VariableNames', ...
            {'CenterOffset','RxSymbol','Time_ms','InputPhase_deg','MeasuredModulo_deg', ...
            'PredictedPhase_deg','LiftedMeasurement_deg','TrackedPhase_deg', ...
            'Frequency_Hz','Metric','Confidence','Reliable','Action','FadeHold'});
        % Audit the exact BPS nearest-distance objective at bad accepted
        % observations. Inner/outer labels are used AFTER estimation only.
        wrong=abs(angle(exp(4j*(bs.MeasuredPhaseModuloRad(ix)- ...
            expectedPhase(bs.Centers(ix)))))/4)>pi/12 & bs.TrackingAction(ix)==1;
        bi=st.Carrier.PhaseStageInfo.BlindPhaseSearch;
        half=floor(bi.WindowSymbols/2);
        metricInput=input./sqrt(max(movmean(abs(input).^2, ...
            bi.MetricPowerWindowSymbols,'Endpoints','shrink'),eps));
        grid=-pi/4+(0:bi.NumTestPhases-1)*(pi/2)/bi.NumTestPhases;
        badRows={};
        for h=ix(wrong).'
            center=bs.Centers(h); sel=(center-half:center+half).';
            zz=metricInput(sel); costs=zeros(numel(grid),1);
            for g=1:numel(grid)
                costs(g)=mean(min(abs(zz*exp(-1j*grid(g))-ref.').^2,[],2));
            end
            [winCost,win]=min(costs);
            assert(abs(winCost-bs.BestMetric(h))<1e-12,'BPS metric replay differs.');
            [~,right]=min(abs(angle(exp(4j*(grid-expectedPhase(center))))));
            dw=min(abs(zz*exp(-1j*grid(win))-ref.').^2,[],2);
            dr=min(abs(zz*exp(-1j*grid(right))-ref.').^2,[],2);
            inner=abs(truth(sel+lag))<(min(abs(ref))+max(abs(ref)))/2;
            badRows{end+1}=struct('RxSymbol',center, ...
                'Time_ms',(center+lag-1)/p.symbolRate*1e3, ...
                'InputPhase_deg',expectedPhase(center)*180/pi, ...
                'WrongGridPhase_deg',grid(win)*180/pi, ...
                'InnerSymbols',nnz(inner),'OuterSymbols',nnz(~inner), ...
                'WrongCost',winCost,'NearTrueCost',costs(right), ...
                'InnerCostAdvantage',sum(dr(inner)-dw(inner))/numel(sel), ...
                'OuterCostAdvantage',sum(dr(~inner)-dw(~inner))/numel(sel), ...
                'Confidence',bs.Confidence(h)); %#ok<AGROW>
        end
        if ~isempty(badRows), badObservations=struct2table(vertcat(badRows{:})); end
    end
end
end

function label=nearest(z,ref)
[~,label]=min(abs(z(:)-ref(:).').^2,[],2); label=label-1;
end

function [lag,coherence]=prefixLag(y,truth,last)
best=-Inf; lag=0;
for k=-64:64
    ti=(512:last).'; yi=ti-k;
    ok=yi>=1 & yi<=numel(y) & ti<=numel(truth); ti=ti(ok); yi=yi(ok);
    q=abs(truth(ti)'*y(yi))/sqrt(sum(abs(truth(ti)).^2)*sum(abs(y(yi)).^2));
    if q>best, best=q; lag=k; end
end
coherence=best;
end

function [frames,row]=pairByPosition(payload,info,tx,lag,p,name)
nf=p.berFrames; bits=size(tx,1); rawLength=bits+32;
ids=(p.berWarmUpFrames+(1:nf)).';
comp=zeros(nf,1); errs=nan(nf,1); copies=zeros(nf,1);
nonGrid=0;
if info.Available
    ci=info.Candidates(info.SelectedCandidate);
    % Four transmitted bits / three raw bits. One 16APSK symbol is exactly
    % one puncture period; no rounding of nonintegral physical positions.
    rawOffset=(4*lag+info.SelectedOffset)*3/4;
    for k=1:size(payload,2)
        pos=rawOffset+ci.FrameStarts(k);
        index=(pos-1)/rawLength+1;
        if abs(index-round(index))>1e-10, nonGrid=nonGrid+1; continue; end
        index=round(index); q=find(ids==index,1);
        if isempty(q), continue; end
        copies(q)=copies(q)+1;
        assert(copies(q)==1,'Duplicate offline physical frame.');
        comp(q)=bits; errs(q)=nnz(double(payload(:,k))~=tx(:,index));
    end
end
frames=table(repmat(name,nf,1),ids,comp,errs,copies, ...
    'VariableNames',{'Stage','TxFrameIndex','ComparedBits','ErrorBits','RecoveredCopies'});
n=nnz(comp); ber=NaN; fer=NaN;
if n>0, ber=sum(errs(comp>0))/sum(comp); fer=mean(errs(comp>0)>0); end
row=struct('Stage',name,'OfflineCompared',n,'Expected',nf, ...
    'OfflineBER',ber,'OfflineFER',fer,'UnmappedRecovered',nonGrid);
end

function [m,w]=symbolMetrics(z,soft,truth,txBits,labels,ref,lag,p,name)
% Same global power normalization used by the actual APSK demapper; no
% oracle phase/gain fitting on noisy measurement symbols.
z=z/sqrt(mean(abs(z).^2));
first=ceil(p.berWarmUpFrames*(32+8*p.NumBytesInTransferFrame)/3)+1;
last=min(numel(truth),floor((p.berWarmUpFrames+p.berFrames)*(32+8*p.NumBytesInTransferFrame)/3));
ti=(first:last).'; yi=ti-lag;
ok=yi>=1 & yi<=numel(z); ti=ti(ok); yi=yi(ok);
e=nearest(z(yi),ref)~=labels(ti);
phase=angle(z(yi).*conj(truth(ti)))*180/pi;
tb=reshape((ti.'-1)*4+(1:4).',[],1);
rb=reshape((yi.'-1)*4+(1:4).',[],1);
m=struct('PreBER',mean((soft(rb)>0)~=logical(txBits(tb))), ...
    'SER',mean(e),'EVM_pct',100*sqrt(mean(abs(z(yi)-truth(ti)).^2)/mean(abs(truth(ti)).^2)), ...
    'MaxErrorRunSymbols',0);
edges=diff([false;e;false]); runs=find(edges==-1)-find(edges==1);
if ~isempty(runs), m.MaxErrorRunSymbols=max(runs); end
rows={};
for start=1:512:numel(ti)
    ix=start:min(start+511,numel(ti));
    ang=angle(mean(exp(1j*phase(ix)*pi/180)))*180/pi;
    % Lag probes are observations only. NEVER used to realign this stream.
    cc=zeros(5,1);
    for off=-2:2
        ri=yi(ix)+off; valid=ri>=1 & ri<=numel(z); tt=ti(ix); tt=tt(valid); ri=ri(valid);
        cc(off+3)=abs(truth(tt)'*z(ri))/sqrt(sum(abs(truth(tt)).^2)*sum(abs(z(ri)).^2));
    end
    [coh,best]=max(cc);
    rows{end+1}=struct('Stage',name,'TxSymbolStart',ti(ix(1)), ...
        'TxSymbolEnd',ti(ix(end)), ...
        'Time_ms',(ti(ix(1))-1)/p.symbolRate*1e3,'SER',mean(e(ix)), ...
        'MeanPhase_deg',ang,'BestLocalLagDelta',best-3,'Coherence',coh); %#ok<AGROW>
end
w=struct2table(vertcat(rows{:}));
end

function segments=phaseSegments(w,rs)
% Truth is used to LABEL the trajectory only, never to choose RX decisions.
branch=mod(round(w.MeanPhase_deg/90),4);
first=[1;find(diff(branch)~=0)+1]; last=[first(2:end)-1;height(w)];
rows=cell(numel(first),1);
for k=1:numel(first)
    ix=first(k):last(k);
    rows{k}=struct('Start_ms',(w.TxSymbolStart(ix(1))-1)/rs*1e3, ...
        'End_ms',w.TxSymbolEnd(ix(end))/rs*1e3, ...
        'Branch_deg',90*branch(ix(1)),'Windows',numel(ix), ...
        'MeanSER',mean(w.SER(ix)), ...
        'NonzeroLagWindows',nnz(w.BestLocalLagDelta(ix)~=0));
end
segments=struct2table(vertcat(rows{:}));
end
