function outputDir = test_apsk_ordinary_entry(fixtureFile,baselineDir)
% Compare direct defaults, real frontend requests, and the frozen RRC data.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
if nargin<1, fixtureFile=fullfile(root,'tmp','apsk_entry_fixture.json'); end
if nargin<2
    baselineDir=fullfile(root,'tmp','baselines','rrc_pre_apsk_migration_20260925_224040');
end
outputDir=tempname(fullfile(root,'tmp'));
mkdir(outputDir);
requests=jsondecode(fileread(fixtureFile));
rows=cell(numel(requests),1);
for k=1:numel(requests)
    p=requests(k).Direct;
    assert(~isfield(p,'HasTMAPSKPilots') && ~isfield(p,'APSKReceiverMode') && ...
        ~isfield(p,'WaveformMode'),'Direct call must exercise omitted defaults.');
    p.captureBaselineData=true;
    rng(p.randomSeed,'twister');
    directLog=evalc('direct=run_ccsds_tm_evaluation(p);');
    w=requests(k).Web; w.captureBaselineData=true;
    rng(p.randomSeed,'twister');
    webLog=evalc('web=run_ccsds_tm_evaluation(w);');
    j=requests(k).Web;
    rng(p.randomSeed,'twister');
    jsonLog=evalc('jsonResult=jsondecode(run_ccsds_tm_evaluation(jsonencode(j)));');
    assert(direct.success && web.success && jsonResult.success, ...
        'APSK entry failed; inspect saved test output.');
    for r={direct,web,jsonResult}
        r=r{1};
        assert(strcmp(r.WaveformMode,'ordinaryTM') && ...
            strcmp(r.APSKReceiverMode,'pilotless') && ~r.HasTMAPSKPilots);
        assert(r.PilotlessAPSKApplied && r.BER==0 && r.FER==0 && ...
            r.CountedFrames==16 && r.MeasurementCoverage.Complete);
    end
    old=load(fullfile(baselineDir,sprintf('%02d_%s_RRC_NoH.mat',7+k,p.modType)));
    a=direct.BaselineCapture; b=web.BaselineCapture;
    frozen=old.caseData.Result.BaselineCapture;
    fields={'TxWaveform','ReferenceConstellation','CoarseSynchronizedWaveform', ...
        'TimeSynchronizedSymbols','FineSynchronizedSymbols'};
    for f=fields
        assert(isequaln(a.(f{1}),b.(f{1})), ...
            'MATLAB/frontend mismatch: %s %s.',p.modType,f{1});
        assert(isequaln(a.(f{1}),frozen.(f{1})), ...
            'Frozen RRC baseline changed: %s %s.',p.modType,f{1});
    end
    assert(isequaln(direct.MeasurementCoverage,web.MeasurementCoverage) && ...
        isequaln(direct.BurstCompletion,web.BurstCompletion));
    save(fullfile(outputDir,[p.modType '.mat']), ...
        'p','w','direct','web','jsonResult','directLog','webLog','jsonLog','-v7');
    rows{k}=struct('ModType',string(p.modType),'BER',direct.BER, ...
        'FER',direct.FER,'ComparedFrames',direct.CountedFrames, ...
        'DirectWebAndFrozenSamplesIdentical',true);
end
% Every alias is checked even when a canonical value is already present.
bad={struct('WaveformMode','FACM'),struct('ACMFormat',21), ...
    struct('HasTMAPSKPilots',true),struct('hasTMAPSKPilots',true), ...
    struct('HasPilots',true),struct('hasPilots',true), ...
    struct('useTMAPSKPilots',true),struct('enableFACMEqualizer',true), ...
    struct('APSKReceiverMode','legacy'),struct('APSKReceiverMode','pilot-aided'), ...
    struct('HasTMAPSKPilots',false,'hasTMAPSKPilots',true), ...
    struct('APSKReceiverMode','pilotless','apskReceiverMode','legacy')};
for k=1:numel(bad)
    p=requests(1).Direct;
    names=fieldnames(bad{k});
    for n=1:numel(names), p.(names{n})=bad{k}.(names{n}); end
    evalc('rejected=run_ccsds_tm_evaluation(p);');
    assert(~rejected.success && contains(rejected.errorIdentifier,'Unsupported'), ...
        'Retired mode must be rejected before waveform generation.');
end
Summary=struct2table(vertcat(rows{:}));
writetable(Summary,fullfile(outputDir,'summary.csv'));
save(fullfile(outputDir,'summary.mat'),'Summary','bad');
disp(Summary);
fprintf('PASS: direct, frontend struct and JSON agree; frozen arrays unchanged; %d invalid requests rejected.\nResults: %s\n',numel(bad),outputDir);
end
