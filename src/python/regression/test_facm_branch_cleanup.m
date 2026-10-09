function outputDir=test_facm_branch_cleanup(mode,baselineDir)
% Freeze the CURRENT ordinary-TM chain, then verify a framing-only cleanup.
% No TX truth is supplied to synchronization, demapping, or decoding.
if nargin<1, mode='check'; end
assert(any(strcmp(mode,{'capture','check'})));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('FACM branch cleanup %s: %s\n',mode,outputDir);
shared={'ccsdsTMWaveformGenerator.m','HelperCCSDSTMDemodulator.m', ...
    'HelperTMAPSKPilotlessFrontEnd.m','HelperCCSDSFACMDemodulate.m', ...
    'HelperCCSDSFACMReferenceConstellation.m','HelperTMCompleteBurst.m', ...
    'HelperTMComplexGainTracker.m'};
sharedSource=cellfun(@(f)fileread(which(f)),shared,'UniformOutput',false);
if strcmp(mode,'capture')
    source=fileread(which('run_ccsds_tm_evaluation'));
    cases=buildCases();
    save(fullfile(outputDir,'manifest.mat'),'cases','shared','sharedSource','source','-v7');
else
    assert(nargin>=2 && isfolder(baselineDir),'Supply a pre-cleanup baseline directory.');
    before=load(fullfile(baselineDir,'manifest.mat'));
    assert(isequal(shared,before.shared) && isequal(sharedSource,before.sharedSource), ...
        'Shared TX/RX/math source changed during a framing-only cleanup.');
    cases=before.cases;
end
rows=cell(numel(cases),1);
for k=1:numel(cases)
    p=cases{k}; rng(p.randomSeed,'twister');
    logText=evalc('r=run_ccsds_tm_evaluation(p);');
    save(fullfile(outputDir,sprintf('case_%02d.mat',k)),'p','r','logText','-v7');
    assert(r.success,'%s',r.errorMsg);
    assert(r.BER==0 && r.FER==0 && r.CountedFrames==p.berFrames && ...
        r.MeasurementCoverage.Complete,'Case %d failed acceptance.',k);
    assert(strcmp(r.WaveformMode,'ordinaryTM'));
    c=r.BaselineCapture;
    if contains(p.modType,'APSK')
        assert(strcmp(r.APSKReceiverMode,'pilotless') && r.PilotlessAPSKApplied && ~r.HasTMAPSKPilots);
        if strcmp(p.modType,'16APSK'), format=14; else, format=21; end
        % Freeze all labels plus soft output on the actual received sequence.
        ref=HelperCCSDSFACMReferenceConstellation(format);
        labelSoft=HelperCCSDSFACMDemodulate(ref,format,0.07);
        rxSoft=HelperCCSDSFACMDemodulate(c.FineSynchronizedSymbols,format,0.07);
    else
        labelSoft=[]; rxSoft=[];
    end
    save(fullfile(outputDir,sprintf('case_%02d.mat',k)),'labelSoft','rxSoft','-append');
    if strcmp(mode,'check')
        b=load(fullfile(baselineDir,sprintf('case_%02d.mat',k)));
        for f={'TxWaveform','ReferenceConstellation','RawReceiverSymbols', ...
                'CoarseSynchronizedWaveform','TimeSynchronizedSymbols', ...
                'FineSynchronizedSymbols','BestRotation_deg','ActualConfiguration'}
            assert(isequaln(c.(f{1}),b.r.BaselineCapture.(f{1})), ...
                'Case %d changed at %s.',k,f{1});
        end
        assert(isequaln(labelSoft,b.labelSoft) && isequaln(rxSoft,b.rxSoft), ...
            'APSK labels or soft values changed.');
        for f={'BER','FER','CountedFrames','MeasurementCoverage','BurstCompletion', ...
                'ResidualCFO_Hz','ResidualPhase_deg'}
            assert(isequaln(r.(f{1}),b.r.(f{1})),'Result changed: %s.',f{1});
        end
    end
    rows{k}=struct('ModType',string(p.modType),'Pulse',string(p.PulseShapingFilter), ...
        'Coding',string(p.channelCoding),'BER',r.BER,'FER',r.FER, ...
        'ComparedFrames',r.CountedFrames,'Complete',r.MeasurementCoverage.Complete, ...
        'EquivalentToBaseline',strcmp(mode,'check'));
    fprintf('%02d %s / %s / %s: BER=%g FER=%g coverage=%d/%d equivalent=%d\n', ...
        k,p.modType,p.PulseShapingFilter,p.channelCoding,r.BER,r.FER, ...
        r.CountedFrames,p.berFrames,strcmp(mode,'check'));
end
% Requests for retired framing must fail, not silently produce ordinary TM.
bad={struct('WaveformMode','FACM'),struct('ACMFormat',21), ...
    struct('HasTMAPSKPilots',true),struct('hasTMAPSKPilots',true), ...
    struct('HasPilots',true),struct('hasPilots',true), ...
    struct('useTMAPSKPilots',true),struct('enableFACMEqualizer',true), ...
    struct('APSKReceiverMode','legacy'),struct('APSKReceiverMode','pilot-aided'), ...
    struct('HasTMAPSKPilots',false,'hasTMAPSKPilots',true), ...
    struct('APSKReceiverMode','pilotless','apskReceiverMode','legacy')};
for k=1:numel(bad)
    p=cases{1}; names=fieldnames(bad{k});
    for j=1:numel(names), p.(names{j})=bad{k}.(names{j}); end
    evalc('r=run_ccsds_tm_evaluation(p);');
    assert(~r.success && contains(r.errorIdentifier,'Unsupported'));
end
Summary=struct2table(vertcat(rows{:}));
writetable(Summary,fullfile(outputDir,'summary.csv'));
save(fullfile(outputDir,'summary.mat'),'Summary','bad');
fprintf('PASS %s: %d cases, %d retired requests rejected.\n',mode,height(Summary),numel(bad));
end

function cases=buildCases()
p=struct('symbolRate',10e6,'sps',8,'NumBytesInTransferFrame',256, ...
    'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
    'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableEqualizer',false,'enableReceiverTimeline',true, ...
    'captureBaselineData',true,'showFigures',false,'randomSeed',20260927);
cases={};
for modType={'16APSK','32APSK'}
    for pulse={'root raised cosine','none'}
        for code={'none','RS','LDPC'}
            q=p; q.modType=modType{1}; q.PulseShapingFilter=pulse{1}; q.channelCoding=code{1};
            if strcmp(code{1},'RS')
                q.NumBytesInTransferFrame=223; q.RSMessageLength=223;
                q.RSInterleavingDepth=1; q.IsRSMessageShortened=false;
            elseif strcmp(code{1},'LDPC')
                q.CodeRate='1/2'; q.NumBitsInInformationBlock=1024; q.IsLDPCOnSMTF=false;
            end
            cases{end+1}=q; %#ok<AGROW>
        end
    end
end
for modType={'BPSK','QPSK','8PSK','16QAM','32QAM','OQPSK','UQPSK'}
    q=p; q.modType=modType{1}; q.PulseShapingFilter='root raised cosine';
    q.channelCoding='none'; q.berFrames=16; q.randomSeed=917;
    cases{end+1}=q; %#ok<AGROW>
end
end
