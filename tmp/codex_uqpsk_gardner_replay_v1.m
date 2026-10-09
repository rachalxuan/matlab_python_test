% Offline causal A/B: immutable captured 2-sps input, unchanged production
% carrier/demapper/ASM/BER functions. No band/gain tuning or oracle feedback.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
if ~exist('UQReplayOptions','var'), UQReplayOptions=struct(); end
if ~isfield(UQReplayOptions,'CaptureFile')
    UQReplayOptions.CaptureFile='C:/Users/admin/AppData/Local/Temp/UQRC_Debug_20260924_213530.mat';
end
outDir=tempname(fullfile(root,'tmp')); mkdir(outDir);
diary(fullfile(outDir,'console.txt')); diaryGuard=onCleanup(@() diary('off'));
format short g;
s=load(UQReplayOptions.CaptureFile,'UQRC_Debug');
rc=s.UQRC_Debug.Runs{1};
assert(strcmp(rc.Parameters.PulseShapingFilter,'raised cosine'));
fprintf('Captured RC input: %s\nOutput: %s\n',UQReplayOptions.CaptureFile,outDir);
% RRC capture only once if absent; never regenerate RC or change its input.
if numel(s.UQRC_Debug.Runs)>=2 && ~isempty(s.UQRC_Debug.Runs{2})
    rr=s.UQRC_Debug.Runs{2};
else
    p=rc.Parameters; p.PulseShapingFilter='root raised cosine';
    rng(917,'twister'); rrLog=evalc('m=run_ccsds_tm_evaluation(p);');
    assert(m.success,'RRC control capture failed.');
    rr=struct('Parameters',p,'Metrics',m,'DebugLog',rrLog);
end
assert(isequal(rc.Metrics.UQPSKPulseDebug.EncodedBits,rr.Metrics.UQPSKPulseDebug.EncodedBits), ...
    'RRC/RC TX data differ; not a valid control.');
UQReplay=struct('Source',UQReplayOptions.CaptureFile,'OutputDir',outDir,'Runs',{{}});
rows=struct([]);
for ir=1:2
    if ir==1, cap=rc; shape="RC"; else, cap=rr; shape="RRC"; end
    d=cap.Metrics.UQPSKPulseDebug; x=d.Filtered(:);
    assert(cap.Parameters.NumBytesInTransferFrame==256 && ...
        numel(d.EncodedBits)==2080*128 && d.FilterSPS==2, ...
        'This diagnostic is scoped to 256 Byte, 8+120 frames, 2-sps capture.');
    inputPower=mean(abs(x).^2);
    assert(isfinite(inputPower) && inputPower>eps,'Invalid timing input power.');
    fprintf('\n[%s] filter power=%.9g RMS=%.9g; Kp=2.7 BW=.01\n',shape,inputPower,sqrt(inputPower));
    variants=["original","unit-power","gain-equivalent","fixed-phase-1","fixed-phase-2"];
    for v=variants
        appliedScale=1; Kp=2.7;
        if v=="unit-power", appliedScale=1/sqrt(inputPower); end
        if v=="gain-equivalent", Kp=2.7*inputPower; end
        if startsWith(v,"fixed")
            phase=str2double(extractAfter(v,"fixed-phase-"));
            timed=x(phase:2:end); mu=[];
        else
            synchronizer=comm.SymbolSynchronizer('TimingErrorDetector','Gardner (non-data-aided)', ...
                'SamplesPerSymbol',2,'DetectorGain',Kp,'Modulation','PAM/PSK/QAM', ...
                'DampingFactor',1/sqrt(2),'NormalizedLoopBandwidth',.01);
            [timed,mu]=synchronizer(x*appliedScale);
        end
        timingMetrics=measureTiming(timed,d.EncodedBits);
        tailLog=evalc('tail=run_ccsds_tm_evaluation(''diagnostic-uqpsk-tail'',timed,cap);');
        capturedVariant="original";
        if isfield(d,'TimingInputScale') && d.TimingInputScale~=1
            capturedVariant="unit-power";
        end
        if v==capturedVariant
            assert(isequal(tail.Timing,d.Timing) && isequal(tail.Carrier,d.Carrier), ...
                'Original replay is not sample-identical.');
            fprintf('Tail replay BER %.12g/%g frames %d/%d\n',tail.BER,cap.Metrics.BER, ...
                tail.Stats.CountedFrames,cap.Metrics.CountedFrames);
            assert(isequaln(tail.BER,cap.Metrics.BER) && ...
                tail.Stats.CountedFrames==cap.Metrics.CountedFrames && ...
                isequaln(tail.Stats.UQPSKPulseFrameDebug.Gate,d.SelectedFrameDebug.Gate), ...
                'Original downstream replay differs; stop A/B.');
            fprintf('Captured %s replay: EXACT timing/carrier samples and frame gate verified.\n',capturedVariant);
        end
        if v=="unit-power", unitTail=tail; unitMu=mu; end
        if v=="gain-equivalent"
            fprintf('Gain identity: max timing difference=%.3g; max mu difference=%.3g\n', ...
                max(abs(tail.Timing-unitTail.Timing)),max(abs(mu-unitMu)));
        end
        observedFrames=0; observedErrors=NaN;
        if isfield(tail.Stats,'UQPSKPulseFrameDebug') && ...
                isfield(tail.Stats.UQPSKPulseFrameDebug,'Gate')
            gate=tail.Stats.UQPSKPulseFrameDebug.Gate;
            measured=isfinite(gate.TxFrame) & gate.TxFrame>=9 & gate.TxFrame<=128;
            valid=unique(gate.TxFrame(measured));
            assert(nnz(measured)==numel(valid),'Duplicate physical measurement frames');
            observedFrames=numel(valid);
            if observedFrames>0, observedErrors=sum(gate.Errors(measured)); end
        end
        row=struct('Shape',shape,'Variant',v,'InputPower',inputPower, ...
            'AppliedScale',appliedScale,'DetectorGain',Kp,'Symbols',numel(timed), ...
            'TimingAlignmentReliable',timingMetrics.AlignmentReliable, ...
            'TimingErrors',timingMetrics.MeasurementSymbolErrors, ...
            'LastTimingErrorFrame',timingMetrics.LastErrorFrame, ...
            'BER',tail.BER,'FER',tail.Stats.FER,'CountedFrames',tail.Stats.CountedFrames, ...
            'ObservedFrames',observedFrames,'ObservedErrors',observedErrors, ...
            'AcquiredAt',tail.Stats.AcquisitionFrames);
        if isempty(rows), rows=row; else, rows(end+1)=row; end
        fprintf('%s %s: timingErr=%g lastBad=%g | BER=%g FER=%g counted=%d/120 observed=%d/120 errs=%g\n', ...
            shape,v,row.TimingErrors,row.LastTimingErrorFrame,row.BER,row.FER, ...
            row.CountedFrames,row.ObservedFrames,row.ObservedErrors);
        disp(timingMetrics.Frames(9:17,:));
        UQReplay.Runs{end+1}=struct('Shape',shape,'Variant',v,'Timing',timingMetrics, ...
            'Tail',tail,'Mu',mu,'TailLog',tailLog);
        % Independent, new v7 file per case; storage failure never suppresses
        % following controls or claims a saved capture.
        UQReplay.Results=struct2table(rows);
        try
            save(fullfile(outDir,sprintf('checkpoint_%02d.mat',numel(rows))),'UQReplay','-v7');
        catch saveError
            warning('UQReplay:SaveFailed','Result remains in UQReplay workspace: %s',saveError.message);
        end
    end
end
disp(UQReplay.Results);
writetable(UQReplay.Results,fullfile(outDir,'summary.csv'));
fprintf('Fixed phase cases are diagnostic controls, NOT production algorithms.\n%s\n',outDir);
clear diaryGuard;

function m=measureTiming(y,encoded)
ref=uqpskMapBitsLocal(encoded,2,2);
probe=(floor(numel(ref)*.6)+(1:4096)).';
scores=zeros(257,1); gains=complex(zeros(257,1));
for lag=-128:128
    r=ref(probe); z=y(probe+lag);
    gains(lag+129)=(r'*z)/(r'*r);
    scores(lag+129)=abs(r'*z)/sqrt(sum(abs(r).^2)*sum(abs(z).^2));
end
[score,ii]=max(scores); lag=ii-129; gain=gains(ii);
fCount=numel(encoded)/2080;
reliable=score>.9 && abs(lag)<128;
if ~reliable
    % A deliberately wrong fixed sampling phase may not align. Do not turn
    % an unreliable truth comparison into zero errors or abort other cases.
    fTable=array2table([(1:fCount).' nan(fCount,5)], ...
        'VariableNames',{'Frame','Symbols','Errors','SER','EVM','Phase_deg'});
    m=struct('FixedLag',lag,'FixedGain',gain,'AnchorCorrelation',score, ...
        'AlignmentReliable',false,'Frames',fTable, ...
        'MeasurementSymbolErrors',NaN,'LastErrorFrame',NaN);
    fprintf('Offline timing alignment unavailable: correlation=%.6g lag=%d.\n',score,lag);
    return;
end
y=y/gain;
fRows=zeros(fCount,6);
for f=1:fCount
    t=(ceil((f-1)*2080/1.5)+1:floor(f*2080/1.5)).';
    t=t(t+lag>=1 & t+lag<=numel(y) & t<=numel(ref));
    z=y(t+lag); r=ref(t);
    err=(real(z)<0)~=(real(r)<0) | (imag(z)<0)~=(imag(r)<0);
    fRows(f,:)=[f,numel(t),nnz(err),mean(err),sqrt(mean(abs(z-r).^2)), ...
        rad2deg(angle(mean(z.*conj(r))))];
end
fTable=array2table(fRows,'VariableNames',{'Frame','Symbols','Errors','SER','EVM','Phase_deg'});
last=find(fTable.Errors>0,1,'last'); if isempty(last), last=0; end
m=struct('FixedLag',lag,'FixedGain',gain,'AnchorCorrelation',score, ...
    'AlignmentReliable',true, ...
    'Frames',fTable,'MeasurementSymbolErrors',sum(fTable.Errors(9:128)), ...
    'LastErrorFrame',last);
end
