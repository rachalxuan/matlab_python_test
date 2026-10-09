function outputDir=test_apsk_gain_fix(mode,referenceDir)
% Local gain-estimator regression; no true symbols supplied to receivers.
% capture: freeze existing H behavior BEFORE changing production defaults.
% check: mechanism tests, fixed failure replay, H comparison after change.
if nargin<1, mode='check'; end
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Gain fix %s: %s\n',mode,outputDir);
assert(any(strcmp(mode,{'capture','check'})));
if strcmp(mode,'capture')
    mods={'16APSK','32APSK','16QAM','32QAM'};
    for k=1:numel(mods)
        p=struct('modType',mods{k},'symbolRate',10e6,'sps',8, ...
            'channelCoding','none','NumBytesInTransferFrame',256, ...
            'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
            'PulseShapingFilter','root raised cosine','noiseMode','off', ...
            'cfo',0,'phaseOffset',0,'delay',0,'berWarmUpFrames',8,'berFrames',32, ...
            'excludeBERWarmUpFrames',true,'enableHChannel',true, ...
            'HMode','h_matrix_file','channelFilePath','E:/matlab_project/v3.0/v3.0/channel/4-ChannelData.mat', ...
            'normalizeHChannel',true,'channelInterpolationMethod','linear','channelOutOfRangeMode','wrap', ...
            'enableEqualizer',false,'APSKReceiverMode','pilotless','HasTMAPSKPilots',false, ...
            'enableReceiverTimeline',true,'captureBaselineData',true,'showFigures',false,'randomSeed',917);
        rng(p.randomSeed,'twister'); logText=evalc('r=run_ccsds_tm_evaluation(p);');
        save(fullfile(outputDir,[mods{k} '_H.mat']),'p','r','logText','-v7');
        assert(r.success,'%s',r.errorMsg);
        fprintf('H BEFORE %s BER=%g FER=%g coverage=%d/%d\n',mods{k},r.BER,r.FER,r.CountedFrames,p.berFrames);
    end
    return;
end
assert(nargin>=2 && isfolder(referenceDir),'Supply the frozen pre-change H directory.');
mechanismTests();
source=fullfile(root,'tmp','tp63073790_9ecf_426c_af05_892069c58600');
s=load(fullfile(source,'32APSK_none_seed20260927.mat'));
truth=s.r.BaselineCapture.TxWaveform(1:8:end);
ref=HelperCCSDSFACMReferenceConstellation(21); ref=ref(:);
rows={};
for pulse=["root_raised_cosine","none"]
    s=load(fullfile(source,['32APSK_' char(pulse) '_seed20260927.mat']));
    p=s.p; c=s.r.BaselineCapture;
    legacy=p; legacy.PilotlessAPSKComplexGainTracker=struct('MagnitudeEstimationMode','power');
    old=HelperTMAPSKPilotlessFrontEnd(c.TimeSynchronizedSymbols,'32APSK',legacy);
    assert(isequaln(old,c.PulseStageCapture.PilotlessOutput),'Legacy replay changed.');
    [fixed,gainInfo]=HelperTMAPSKPilotlessFrontEnd(c.TimeSynchronizedSymbols,'32APSK',p);
    assert(strcmp(gainInfo.ComplexGain.MagnitudeEstimationMode,'decision'));
    % Fit delay ONLY on an early prefix; use actual unity-power demap later.
    ti=(8*416+1:8*416+4096).'; best=-Inf; lag=0;
    for q=-32:32
        score=abs(truth(ti)'*c.TimeSynchronizedSymbols(ti-q));
        if score>best, best=score; lag=q; end
    end
    txi=(8*416+1:128*416).'; rxi=txi-lag;
    expected=HelperCCSDSFACMDemodulate(truth(txi),21,1)>0;
    oldFinal=c.FineSynchronizedSymbols/sqrt(mean(abs(c.FineSynchronizedSymbols).^2));
    fixedFinal=fixed/sqrt(mean(abs(fixed).^2));
    oldBits=HelperCCSDSFACMDemodulate(oldFinal(rxi),21,1)>0;
    newBits=HelperCCSDSFACMDemodulate(fixedFinal(rxi),21,1)>0;
    oldErrors=nnz(oldBits~=expected); newErrors=nnz(newBits~=expected);
    assert(oldErrors==2 && newErrors==0);
    bad=[24628;24629]-lag;
    row=struct('Pulse',pulse,'OldErrors',oldErrors,'NewErrors',newErrors, ...
        'FirstRadiusBefore',abs(oldFinal(bad(1))),'FirstRadiusAfter',abs(fixedFinal(bad(1))), ...
        'SecondRadiusBefore',abs(oldFinal(bad(2))),'SecondRadiusAfter',abs(fixedFinal(bad(2))));
    rows{end+1}=row; %#ok<AGROW>
    save(fullfile(outputDir,[char(pulse) '_replay.mat']),'p','row','fixed','gainInfo','lag','-v7');
    disp(row);
end
Replay=struct2table(vertcat(rows{:})); writetable(Replay,fullfile(outputDir,'replay.csv'));
rows={};
for modType=["16APSK","32APSK","16QAM","32QAM"]
    s=load(fullfile(referenceDir,[char(modType) '_H.mat'])); p=s.p;
    rng(p.randomSeed,'twister'); logText=evalc('r=run_ccsds_tm_evaluation(p);');
    assert(r.success,'%s',r.errorMsg);
    identical=true;
    for f={'TxWaveform','CoarseSynchronizedWaveform','TimeSynchronizedSymbols','FineSynchronizedSymbols'}
        identical=identical && isequaln(r.BaselineCapture.(f{1}),s.r.BaselineCapture.(f{1}));
    end
    row=struct('ModType',modType,'Identical',identical,'BER',r.BER,'FER',r.FER,'ComparedFrames',r.CountedFrames);
    rows{end+1}=row; %#ok<AGROW>
    save(fullfile(outputDir,[char(modType) '_H.mat']),'p','r','logText','row','-v7');
    fprintf('H AFTER %s identical=%d BER=%g FER=%g coverage=%d/%d\n',modType,identical,r.BER,r.FER,r.CountedFrames,p.berFrames);
    assert(identical && isequaln(r.MeasurementCoverage,s.r.MeasurementCoverage));
end
HComparison=struct2table(vertcat(rows{:})); writetable(HComparison,fullfile(outputDir,'H_comparison.csv'));
fprintf('PASS gain fix mechanism / fixed replay / H preservation.\n');
end

function mechanismTests()
refs={HelperCCSDSFACMReferenceConstellation(14),HelperCCSDSFACMReferenceConstellation(21), ...
    qammod((0:15).',16,'UnitAveragePower',true),qammod((0:31).',32,'UnitAveragePower',true)};
mods={'16APSK','32APSK','16QAM','32QAM'};
opt=struct('MagnitudeEstimationMode','decision','TrackPhase',false,'Regularization',0, ...
    'UpdatePowerReference',false,'PowerReference',1,'InitialGainMagnitude',1, ...
    'FadePowerTauSymbols',16,'DecisionGate',0.35,'DecisionMarginMin',0, ...
    'HoldEnterBadSymbols',16,'RecoverGoodSymbols',1,'FadeEnterDB',-10,'FadeExitDB',-6);
for k=1:numel(refs)
    ref=refs{k}(:); [~,order]=sort(abs(ref));
    % Long occupancy-biased runs exercise power fade entry/exit without H.
    truth=[repmat(ref,32,1);repelem(ref(order),256);repmat(ref,32,1)];
    [y,~,info]=HelperTMComplexGainTracker(truth,ref,opt);
    assert(max(abs(y-truth))<1e-12,'Data-only power variation changed true gain.');
    % A changing physical amplitude must still be tracked (not just frozen).
    truth=repmat(ref,ceil(32000/numel(ref)),1); n=numel(truth);
    amplitude=1+0.12*sin(2*pi*(0:n-1)'/n);
    [y,~,rampInfo]=HelperTMComplexGainTracker(amplitude.*truth,ref,opt);
    [~,dec]=min(abs(y-ref.').^2,[],2); [~,expected]=min(abs(truth-ref.').^2,[],2);
    assert(all(dec==expected) && max(abs(abs(y./truth)-1))<0.01);
    % External HOLD -> recovery must retain the valid pre-fade gain rather
    % than seed it from arbitrary data occupancy at the exit symbol.
    q=opt; q.ExternalHoldMask=false(size(truth)); q.ExternalHoldMask(400:900)=true;
    y=HelperTMComplexGainTracker(truth,ref,q);
    assert(max(abs(y-truth))<1e-12);
    fprintf('MECHANISM %s occupancy=unchanged rampSER=0 HOLD-exit=unchanged (occupancy fade=%g, ramp acceptance=%g)\n', ...
        mods{k},info.FadeFraction,rampInfo.AcceptanceRate);
end
end
