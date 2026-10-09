function outputDir = test_apsk_pulse_shaping(baselineDir)
% APSK ordinary TM pulse/rate regression: frozen upstream plus BER acceptance.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
if nargin<1
    baselineDir=fullfile(root,'tmp','baselines','rrc_pre_apsk_migration_20260925_224040');
end
outputDir=tempname(fullfile(root,'tmp'));
mkdir(outputDir);
fprintf('APSK pulse regression: %s\n',outputDir);
rows={};
for im=1:2
    mods={'16APSK','32APSK'};
    saved=load(fullfile(baselineDir,sprintf('%02d_%s_RRC_NoH.mat',7+im,mods{im})));
    p=saved.caseData.Parameters;
    rng(p.randomSeed,'twister');
    logText=evalc('r=run_ccsds_tm_evaluation(p);');
    assert(r.success,'%s',r.errorMsg);
    reference=saved.caseData.Result.BaselineCapture;
    for f={'TxWaveform','ReferenceConstellation','CoarseSynchronizedWaveform', ...
            'TimeSynchronizedSymbols'}
        assert(isequaln(reference.(f{1}),r.BaselineCapture.(f{1})), ...
            '%s RRC baseline changed at %s.',mods{im},f{1});
    end
    row=checkResult(r,p);
    assert(row.ZeroErrorComplete,'Frozen RRC baseline no longer passes.');
    row.FrozenRRCUpstreamIdentical=true;
    row.LegacyFinalIdentical=isequaln(reference.FineSynchronizedSymbols,r.BaselineCapture.FineSynchronizedSymbols);
    rows{end+1}=row; %#ok<AGROW>
    save(fullfile(outputDir,[mods{im} '_rrc.mat']),'p','r','logText','-v7');
    fprintf('%s RRC: TX/filter/timing baseline identical (post-carrier gain intentionally changed); BER=%g, coverage=%d/%d\n', ...
        mods{im},r.BER,r.CountedFrames,p.berFrames);
    for seed=[917 20260925]
        for delay=[0 1]
            p=saved.caseData.Parameters;
            p.PulseShapingFilter='none';
            p.berFrames=120;
            p.randomSeed=seed;
            p.delay=delay;
            p.debugSynchronizationChain=true;
            rng(seed,'twister');
            logText=evalc('r=run_ccsds_tm_evaluation(p);');
            name=sprintf('%s_none_seed%d_delay%g',mods{im},seed,delay);
            % Save before acceptance checks so any failure remains inspectable.
            save(fullfile(outputDir,[name '.mat']),'p','r','logText','-v7');
            assert(r.success,'%s',r.errorMsg);
            row=checkResult(r,p);
            assert(strcmp(r.ReceivePulseFilterActual,'rectangular matched filter'));
            assert(strcmp(r.TransmitPulseShapeActual,'rectangular symbol hold (no shaping filter)'));
            burst=r.BurstCompletion;
            assert(burst.RectangularSymbolHoldApplied);
            assert(burst.OriginalWaveformSamples== ...
                burst.GeneratorOutputSamplesBeforeHold*p.sps);
            tx=r.BaselineCapture.TxWaveform;
            assert(numel(tx)==burst.OriginalWaveformSamples+burst.AppendedSamples);
            body=tx(1:burst.OriginalWaveformSamples);
            tail=tx(burst.OriginalWaveformSamples+1:end);
            assert(~isempty(body) && ~isempty(tail));
            % Every symbol in BOTH segments must occupy SPS identical samples.
            for segment={body,tail}
                groups=reshape(segment{1},p.sps,[]);
                assert(all(all(groups==groups(1,:))), ...
                    'Body/continuation does not use identical rectangular holds.');
            end
            sync=r.SyncDiagnostics;
            assert(sync.TimingInputSamplesPerSymbol==p.sps);
            assert(sync.TimingInputSamples==floor( ...
                numel(r.BaselineCapture.CoarseSynchronizedWaveform)));
            row.BodyAndTailHoldVerified=true;
            row.TimingInputSPS=sync.TimingInputSamplesPerSymbol;
            rows{end+1}=row; %#ok<AGROW>
            fprintf('%s: BER=%g FER=%g coverage=%d/%d, body/tail SPS=%d, timing SPS=%g\n', ...
                name,r.BER,r.FER,r.CountedFrames,p.berFrames,p.sps,row.TimingInputSPS);
        end
    end
end
Summary=struct2table(vertcat(rows{:}));
writetable(Summary,fullfile(outputDir,'summary.csv'));
save(fullfile(outputDir,'summary.mat'),'Summary');
disp(Summary);
fprintf('Results: %s\n',outputDir);
assert(all(Summary.ZeroErrorComplete), ...
    'APSKPulse:AcceptanceFailed', ...
    'Integration checks completed, but some No-H cases have errors or incomplete coverage. See summary.csv and saved case MAT files.');
fprintf('PASS: APSK RRC upstream unchanged and none body/tail/full-rate timing verified.\n');
end

function row=checkResult(r,p)
assert(strcmp(r.WaveformMode,'ordinaryTM') && ...
    strcmp(r.APSKReceiverMode,'pilotless') && ~r.HasTMAPSKPilots && r.PilotlessAPSKApplied);
assert(r.Fs==p.symbolRate*p.sps);
zeroErrorComplete=r.BER==0 && r.FER==0 && r.CountedFrames==p.berFrames && ...
    r.MeasurementCoverage.Complete && r.MeasurementCoverage.ComparedFrames==p.berFrames;
assert(r.BurstCompletion.Applied && r.BurstCompletion.AppendedSamples>0);
row=struct('ModType',string(p.modType),'Pulse',string(p.PulseShapingFilter), ...
    'Seed',p.randomSeed,'DelaySamples',p.delay,'BER',r.BER,'FER',r.FER, ...
    'ComparedFrames',r.CountedFrames,'CoverageComplete',r.MeasurementCoverage.Complete, ...
    'SampleRateHz',r.Fs,'ZeroErrorComplete',zeroErrorComplete,'FrozenRRCUpstreamIdentical',false, ...
    'LegacyFinalIdentical',NaN, ...
    'BodyAndTailHoldVerified',false,'TimingInputSPS',NaN);
end
