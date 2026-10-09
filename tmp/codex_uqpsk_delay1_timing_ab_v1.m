% Bounded diagnosis for the first failing nonzero-delay acceptance case.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src','python'));
f=load(fullfile(root,'tmp','tpfad6ce0a_9cad_4377_acd2_90b34cf7d9b7','failure_017.mat'));
p=f.p; p.delay=1; p.debugUQPSKPulseStages=true;
p.debugUQPSKTimingInputNormalization=true;
rng(917,'twister'); captureLog=evalc('m=run_ccsds_tm_evaluation(p);');
assert(m.success); d=m.UQPSKPulseDebug;
cap=struct('Parameters',p,'Metrics',m);
outDir=tempname(fullfile(root,'tmp')); mkdir(outDir);
fprintf('OUTPUT: %s\n',outDir);
rows=struct([]); runs=cell(2,1);
for k=1:2
    x=d.Filtered; scale=1;
    if k==2, scale=1/sqrt(mean(abs(x).^2)); end
    timing=comm.SymbolSynchronizer('TimingErrorDetector','Gardner (non-data-aided)', ...
        'SamplesPerSymbol',2,'DetectorGain',2.7,'Modulation','PAM/PSK/QAM', ...
        'DampingFactor',1/sqrt(2),'NormalizedLoopBandwidth',.01);
    timingLog=evalc('[y,mu]=timing(x*scale);');
    tailLog=evalc('tail=run_ccsds_tm_evaluation(''diagnostic-uqpsk-tail'',y,cap);');
    r=struct('InputNormalized',k==2,'Power',mean(abs(x).^2), ...
        'InputSamples',numel(x),'ExpectedSymbols',numel(x)/2, ...
        'OutputSymbols',numel(y),'BER',tail.BER,'CountedFrames',tail.Stats.CountedFrames);
    if isempty(rows), rows=r; else, rows(end+1)=r; end
    runs{k}=struct('Timing',y,'Mu',mu,'TimingLog',timingLog,'Tail',tail,'TailLog',tailLog);
    disp(r); disp(timingLog);
    if k==2
        assert(isequal(tail.Timing,d.Timing) && isequal(tail.Carrier,d.Carrier));
        assert(isequaln(tail.BER,m.BER));
    end
end
results=struct2table(rows); disp(results);
save(fullfile(outDir,'diagnosis.mat'),'results','runs','cap','captureLog','-v7');
writetable(results,fullfile(outDir,'diagnosis.csv'));
