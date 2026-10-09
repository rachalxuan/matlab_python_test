% Candidate No-H regression through the real receiver. The candidate remains
% diagnostic-only because delay=1, seed917, RC regresses. No warmup changes.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
if ~exist('UQTimingOptions','var'), UQTimingOptions=struct(); end
if ~isfield(UQTimingOptions,'Seeds'), UQTimingOptions.Seeds=[917 42 2026]; end
if ~isfield(UQTimingOptions,'Delays'), UQTimingOptions.Delays=[0 1 1.25 2.5 5.75 7.75]; end
assert(all(UQTimingOptions.Delays>=0),'Channel delay is causal and nonnegative (input samples).');
% The production Farrow object's default centered kernel clips delays < 1.
% Keep 0 as the explicit bypass; never claim a clipped .25 as a true .25.
assert(all(UQTimingOptions.Delays==0 | UQTimingOptions.Delays>=1), ...
    'Nonzero delay must be >=1 sample for the current centered Farrow kernel.');
shapes=["root raised cosine","raised cosine","none"];
outDir=tempname(fullfile(root,'tmp')); mkdir(outDir);
diary(fullfile(outDir,'console.txt')); diaryGuard=onCleanup(@() diary('off'));
fprintf('OUTPUT: %s\nDelays in 80-MHz INPUT SAMPLES; unchanged warmup=8, measurement=120.\n',outDir);
cases=struct([]);
for shape=shapes
for seed=UQTimingOptions.Seeds(:).'
for delay=UQTimingOptions.Delays(:).'
    c=struct('Modulation',"UQPSK",'Shape',shape,'Seed',seed,'Delay',delay,'TFBytes',256);
    if isempty(cases), cases=c; else, cases(end+1)=c; end
end
end
end
% Previously good frame grouping, and unchanged receiver branches.
for seed=UQTimingOptions.Seeds(:).'
    cases(end+1)=struct('Modulation',"UQPSK",'Shape',"raised cosine", ...
        'Seed',seed,'Delay',0,'TFBytes',254);
end
for modType=["QPSK","OQPSK"]
    cases(end+1)=struct('Modulation',modType,'Shape',"root raised cosine", ...
        'Seed',917,'Delay',0,'TFBytes',256);
end
rows=struct([]); UQTimingDetails=cell(numel(cases),1);
for ic=1:numel(cases)
    c=cases(ic);
    p=struct('modType',char(c.Modulation),'symbolRate',10e6,'sps',8, ...
        'channelCoding','none','NumBytesInTransferFrame',c.TFBytes, ...
        'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
        'PCMFormat','NRZ-L','PulseShapingFilter',char(c.Shape), ...
        'RolloffFactor',.35,'FilterSpanInSymbols',10,'noiseMode','off', ...
        'cfo',0,'phaseOffset',0,'delay',c.Delay,'berWarmUpFrames',8, ...
        'berFrames',120,'excludeBERWarmUpFrames',true,'enableHChannel',false, ...
        'enableEqualizer',false,'showFigures',false,'enableReceiverTimeline',true);
    p.debugUQPSKTimingInputNormalization=true;
    r=c; r.Success=false; r.BER=NaN; r.FER=NaN; r.ComparedFrames=0;
    r.UnrecoveredFrames=NaN; r.RecoveredNotComparedFrames=NaN;
    r.ComparedBits=NaN; r.ErrorBits=NaN; r.ObservedErrorBits=NaN;
    r.SampleRateConsistent=false; r.NormalizedPower=NaN; r.Pass=false; r.Error="";
    fprintf('[%d/%d] %s %s TF=%d seed=%d delay=%g ...\n', ...
        ic,numel(cases),c.Modulation,c.Shape,c.TFBytes,c.Seed,c.Delay);
    rng(c.Seed,'twister'); tic;
    m=struct(); logText='';
    try
        logText=evalc('m=run_ccsds_tm_evaluation(p);');
        r.Success=m.success;
        if ~m.success, error('UQTiming:ReceiverFailed','%s',m.errorMsg); end
        cov=m.MeasurementCoverage;
        T=struct2table(m.ReceiverTimeline.Rows);
        T=T(T.MeasurementEligible,:);
        r.BER=m.BER; r.FER=m.FER; r.ComparedFrames=cov.ComparedFrames;
        r.UnrecoveredFrames=cov.UnrecoveredFrames;
        r.RecoveredNotComparedFrames=cov.RecoveredNotComparedFrames;
        r.ComparedBits=sum(T.ComparedBitsDelta); r.ErrorBits=sum(T.ErrorBitsDelta);
        r.ObservedErrorBits=sum(T.ObservedErrorBits);
        r.SampleRateConsistent=abs(m.ActualWaveformDuration_s*80e6- ...
            (m.BurstCompletion.OriginalWaveformSamples+m.BurstCompletion.AppendedSamples))<1e-6;
        tok=regexp(logText,'\[UQPSK timing input\][^\r\n]*normalizedPower=([^\s]+)','tokens','once');
        if ~isempty(tok), r.NormalizedPower=str2double(tok{1}); end
        normalized=c.Modulation~="UQPSK" || abs(r.NormalizedPower-1)<1e-7;
        r.Pass=r.BER==0 && r.FER==0 && cov.Complete && ...
            cov.ExpectedFrames==120 && cov.ComparedFrames==120 && ...
            cov.UnrecoveredFrames==0 && cov.RecoveredNotComparedFrames==0 && ...
            cov.DuplicateComparisons==0 && height(T)==120 && ...
            all(T.ComparedBitsDelta==c.TFBytes*8) && ...
            r.ComparedBits==120*c.TFBytes*8 && r.ErrorBits==0 && ...
            r.ObservedErrorBits==0 && r.SampleRateConsistent && ...
            strcmp(m.PulseShapingFilter,c.Shape) && m.delay_in==c.Delay && normalized;
        if ~r.Pass
            r.Error=sprintf('Acceptance failed: compared %d/120, BER=%g; inspect saved log/timeline.', ...
                r.ComparedFrames,r.BER);
        end
        UQTimingDetails{ic}=struct('Parameters',p,'Coverage',cov,'Timeline',T, ...
            'BurstCompletion',m.BurstCompletion,'Log',logText);
    catch problem
        r.Error=string(problem.message);
        UQTimingDetails{ic}=struct('Parameters',p,'Log',logText,'Error',r.Error);
    end
    r.Elapsed_s=toc;
    if isempty(rows), rows=r; else, rows(end+1)=r; end
    UQTimingResults=struct2table(rows);
    fprintf('  PASS=%d BER=%g FER=%g coverage=%d/120 uncounted=%g errors=%g | %.1fs %s\n', ...
        r.Pass,r.BER,r.FER,r.ComparedFrames,r.RecoveredNotComparedFrames,r.ErrorBits,r.Elapsed_s,r.Error);
    save(fullfile(outDir,'results.mat'),'UQTimingResults','UQTimingDetails','UQTimingOptions','-v7');
    writetable(UQTimingResults,fullfile(outDir,'results.csv'));
    if ~r.Pass
        save(fullfile(outDir,sprintf('failure_%03d.mat',ic)),'m','p','logText','-v7');
    end
end
disp(UQTimingResults);
fprintf('PASS %d/%d. Evidence: %s\n',nnz(UQTimingResults.Pass),height(UQTimingResults),outDir);
clear diaryGuard;
assert(all(UQTimingResults.Pass),'Regression incomplete: failed cases preserved, no acceptance claim.');
