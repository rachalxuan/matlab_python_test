function outputDir=test_apsk_none_timing_contract(suite)
% Full-chain regression, no oracle corrections. All failures are retained.
% suite: all (default), baseline, extended, telemetry.
if nargin<1, suite='all'; end
assert(any(strcmp(suite,{'all','baseline','extended','telemetry'})));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
baselineDir=fullfile(root,'tmp','baselines','rrc_pre_apsk_migration_20260925_224040');
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
fprintf('APSK timing contract (%s): %s\n',suite,outputDir);
rows={};
if any(strcmp(suite,{'all','telemetry'}))
    for sps=[2 8]
        % Compare telemetry-on/off outputs and the native input-sample trace.
        rng(917); x=repelem(exp(1j*pi/2*randi([0 3],2000,1)),sps);
        cfg=struct('SamplesPerSymbol',sps,'ChunkSizeSamples',4096,'CollectTimingError',false);
        y=HelperTMSymbolSynchronizerChunked(x,cfg);
        cfg.CollectTimingError=true; [z,info]=HelperTMSymbolSynchronizerChunked(x,cfg);
        assert(isequaln(y,z)); assert(numel(info.TimingErrorTrace)==numel(x));
        lockCfg=struct('SymbolRateHz',1e6,'TimingErrorTrace',zeros(128*sps,1), ...
            'TimingErrorSamplesPerSymbol',sps,'Options',struct('runtimeTimingWindowSymbols',64));
        locks=HelperTMRuntimeLockTelemetry(lockCfg);
        expected=([mean(1:64*sps),mean(64*sps+1:128*sps)]'-1)/(1e6*sps);
        assert(max(abs(locks.Timing.Time_s-expected))<1e-12);
    end
    fprintf('PASS telemetry: complete input-sample trace, correct time axis, unchanged signal output.\n');
end
if any(strcmp(suite,{'all','baseline'}))
    mods={'BPSK','QPSK','8PSK','OQPSK','UQPSK','16QAM','32QAM','16APSK','32APSK'};
    for k=1:numel(mods)
        s=load(fullfile(baselineDir,sprintf('%02d_%s_RRC_NoH.mat',k,mods{k})));
        p=s.caseData.Parameters; rng(p.randomSeed,'twister');
        logText=evalc('r=run_ccsds_tm_evaluation(p);');
        assert(r.success,'%s',r.errorMsg);
        identical=true;
        for f={'TxWaveform','ReferenceConstellation','CoarseSynchronizedWaveform', ...
                'TimeSynchronizedSymbols'}
            identical=identical && isequaln(r.BaselineCapture.(f{1}),s.caseData.Result.BaselineCapture.(f{1}));
        end
        finalIdentical=isequaln(r.BaselineCapture.FineSynchronizedSymbols, ...
            s.caseData.Result.BaselineCapture.FineSynchronizedSymbols);
        row=summaryRow(p,r,sprintf('%s_frozen_RRC',mods{k}));
        row.UpstreamIdentical=identical; row.LegacyFinalIdentical=finalIdentical;
        % APSK scalar gain is intentionally corrected. Keep its TX/timing
        % baseline exact; other modulations must retain the final array too.
        row.Pass=row.Pass && identical && (contains(mods{k},'APSK') || finalIdentical);
        rows{end+1}=row; %#ok<AGROW>
        fprintf('%s upstreamIdentical=%d legacyFinalIdentical=%d BER=%g coverage=%d/%d pass=%d\n', ...
            mods{k},identical,finalIdentical,row.BER,row.ComparedFrames,p.berFrames,row.Pass);
        save(fullfile(outputDir,[mods{k} '_baseline.mat']),'p','logText','row');
        writeSummary(rows,outputDir);
    end
end
if any(strcmp(suite,{'all','extended'}))
    for modIndex=1:2
        mods={'16APSK','32APSK'};
        s=load(fullfile(baselineDir,sprintf('%02d_%s_RRC_NoH.mat',7+modIndex,mods{modIndex})));
        base=s.caseData.Parameters; base.PulseShapingFilter='none';
        base.berFrames=120; base.captureBaselineData=false; base.includeRawData=false;
        base.debugSynchronizationChain=true;
        cases={};
        for seed=[917 20260925]
            for delay=[0.25 0.5 2 3.5]
                p=base; p.randomSeed=seed; p.delay=delay; cases{end+1}=p; %#ok<AGROW>
            end
        end
        for cfo=[-50e3 -1e3 1e3 50e3]
            p=base; p.randomSeed=917; p.delay=1; p.cfo=cfo; p.phaseOffset=30;
            cases{end+1}=p; %#ok<AGROW>
        end
        % Representative full-chain FEC and alternate-SPS checks.
        p=base; p.randomSeed=917; p.delay=1; p.channelCoding='convolutional';
        p.ConvolutionalCodeRate='1/2'; cases{end+1}=p;
        for sps=[4 16]
            p=base; p.randomSeed=917; p.delay=sps/8; p.sps=sps;
            cases{end+1}=p; %#ok<AGROW>
        end
        for k=1:numel(cases)
            p=cases{k}; rng(p.randomSeed,'twister');
            logText=evalc('r=run_ccsds_tm_evaluation(p);');
            name=sprintf('%s_%02d',mods{modIndex},k);
            row=summaryRow(p,r,name);
            if r.success
                row.Pass=row.Pass && r.SyncDiagnostics.TimingInputSamplesPerSymbol==p.sps;
            end
            rows{end+1}=row; %#ok<AGROW>
            save(fullfile(outputDir,[name '.mat']),'p','r','logText','row','-v7');
            writeSummary(rows,outputDir);
            fprintf('%s seed=%d delay=%g sps=%g CFO=%g FEC=%s BER=%g FER=%g coverage=%d/%d pass=%d\n', ...
                name,p.randomSeed,p.delay,p.sps,p.cfo,p.channelCoding,row.BER,row.FER,row.ComparedFrames,p.berFrames,row.Pass);
        end
        p=base; p.equalizerMode='blind-cma-lms'; p.enableEqualizer=true;
        p.adaptiveEqualizerSamplingMode='2sps';
        logText=evalc('r=run_ccsds_tm_evaluation(p);');
        assert(~r.success && contains(r.errorMsg,'APSK none with a 2-sps FSE'), ...
            'Expected an explicit APSK none/FSE rejection.');
        save(fullfile(outputDir,[mods{modIndex} '_fse_rejection.mat']),'p','r','logText');
        fprintf('PASS %s: none + 2-sps FSE explicitly rejected.\n',mods{modIndex});
    end
end
if ~isempty(rows)
    Summary=writeSummary(rows,outputDir); disp(Summary);
    assert(all(Summary.Pass),'APSKTiming:AcceptanceFailed', ...
        'Some cases failed. All results retained in %s',outputDir);
end
fprintf('PASS (%s). Results: %s\n',suite,outputDir);
end

function row=summaryRow(p,r,name)
row=struct('Case',string(name),'ModType',string(p.modType), ...
    'SPS',p.sps,'Seed',p.randomSeed,'Delay',p.delay,'CFO',p.cfo, ...
    'FEC',string(p.channelCoding),'BER',NaN,'FER',NaN,'ComparedFrames',0, ...
    'UpstreamIdentical',NaN,'LegacyFinalIdentical',NaN,'Pass',false,'Error',string(r.errorMsg));
if r.success
    row.BER=r.BER; row.FER=r.FER; row.ComparedFrames=r.CountedFrames;
    row.Pass=r.BER==0 && r.FER==0 && r.CountedFrames==p.berFrames && ...
        r.MeasurementCoverage.Complete && r.MeasurementCoverage.ComparedFrames==p.berFrames;
end
end

function Summary=writeSummary(rows,outputDir)
Summary=struct2table(vertcat(rows{:}));
writetable(Summary,fullfile(outputDir,'summary.csv'));
save(fullfile(outputDir,'summary.mat'),'Summary');
end
