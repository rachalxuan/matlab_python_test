function summary = test_oqpsk_equalizer(stage,savedRunFile,caseIndices)
% Compact permanent regression; no files or waveforms are saved.
% baseline: RRC/none, uncoded/continuous 3/4, EQ off/on, 120 frames each.
% multipath: same cases, fixed complex echo; retains the production front end.
% multipath-isolated: diagnostic ONLY, additionally disables H-only envelope
% tracking. Production OQPSK no longer uses fourth-power phase pre-tracking.
% The fixed multipath case preserves the original false-phase regression.
% ordinary: representative other receivers, No-H smoke checks, no files.
% offsets: fixed multipath, EQ enabled, each impairment separately (no FEC).
% saved: replay specified SystemTestInputs from a compact sweep MAT file.
%   test_oqpsk_equalizer('saved',file,[13]) preserves every case option.
%   Report errors/coverage honestly; a completed run is NOT a zero-BER pass.
if nargin<1, stage='baseline'; end
addpath(fileparts(fileparts(mfilename('fullpath'))));
assert(any(strcmp(stage,{'baseline','unit','multipath','multipath-isolated','ordinary','offsets','saved'})));
if strcmp(stage,'saved')
    assert(nargin==3,'Supply the saved sweep file and explicit case indices.');
    data=load(savedRunFile,'SystemTestInputs'); rows=cell(numel(caseIndices),1);
    for j=1:numel(caseIndices)
        k=caseIndices(j); q=data.SystemTestInputs{k};
        assert(strcmpi(q.modType,'OQPSK'),'Only select OQPSK cases.');
        q.captureBaselineData=false; q.debugAdaptiveEqualizer=true;
        rng(q.randomSeed,'twister');
        logText=evalc('r=run_ccsds_tm_evaluation(q);');
        if ~r.success, fprintf('%s\n',logText); error('%s',r.errorMsg); end
        logLines=splitlines(string(logText));
        disp(logLines(contains(logLines,'OQPSK adaptive EQ')));
        coverage=r.MeasurementCoverage;
        passed=r.BER==0 && r.FER==0 && coverage.Complete && ...
            coverage.RecoveredNotComparedFrames==0;
        rows{j}=struct('CaseIndex',k,'Pulse',string(q.PulseShapingFilter), ...
            'BER',r.BER,'FER',r.FER,'ComparedFrames',coverage.ComparedFrames, ...
            'ExpectedFrames',coverage.ExpectedFrames, ...
            'RecoveredNotCompared',coverage.RecoveredNotComparedFrames, ...
            'FinalTapNorm',r.AdaptiveEqualizerFinalTapNorm, ...
            'ProjectedUpdates',r.AdaptiveEqualizerProjectedUpdates, ...
            'RejectedUpdates',r.AdaptiveEqualizerRejectedUpdates, ...
            'ZeroErrorComplete',passed);
        fprintf('SAVED case=%d BER=%g FER=%g coverage=%d/%d zeroErrorComplete=%d\n', ...
            k,r.BER,r.FER,coverage.ComparedFrames,coverage.ExpectedFrames,passed);
    end
    summary=struct2table(vertcat(rows{:})); disp(summary);
    return;
end
rng(917,'twister');
% Shared DD arithmetic/reject policy must remain exactly equivalent.
for k=1:1000
    w=randn(11,1)+1j*randn(11,1);
    u=randn(11,1)+1j*randn(11,1); e=randn+1j*randn;
    power=real(u'*u)+1e-8; step=.001; bound=4;
    expected=w+(step/power)*u*conj(e);
    allowed=all(isfinite(expected)) && norm(expected)<=bound;
    if ~allowed, expected=w; end
    [actual,accepted]=HelperTMNormalizedTapUpdate(w,u,e,step,power,bound);
    assert(isequal(actual,expected) && accepted==allowed);
end
w=[1;0]; u=[1;1];
[projected,accepted,limited]=HelperTMNormalizedTapUpdate(w,u,100,.1,2,1,true);
assert(accepted && limited && abs(norm(projected)-1)<1e-14);
[held,accepted]=HelperTMNormalizedTapUpdate(w,u,Inf,.1,2,1,true);
assert(~accepted && isequal(held,w));
fprintf('UNIT shared normalized update: DD equivalence / projection / nonfinite hold passed\n');
for pulse=["root raised cosine","none"]
    cfg=HelperTMPulseShapeConfig(pulse,8,.35,10);
    if pulse=="none"
        tx=comm.OQPSKModulator('BitInput',true,'SamplesPerSymbol',8, ...
            'SymbolMapping',[0 2 3 1],'PulseShape','Custom', ...
            'FilterNumerator',ones(1,8));
    else
        tx=comm.OQPSKModulator('BitInput',true,'SamplesPerSymbol',8, ...
            'SymbolMapping',[0 2 3 1],'PulseShape','Root raised cosine', ...
            'RolloffFactor',.35,'FilterSpanInSymbols',10);
    end
    x=tx(randi([0 1],80000,1));
    for echo=[0 .45]
        h=[1 zeros(1,7) echo];
        mf=filter(cfg.ReceiveTaps,1,filter(h,1,x));
        [y,d]=HelperTMOQPSKAdaptiveEqualizer(mf,8,10,struct());
        assert(numel(y)==numel(mf) && d.CMASymbols>0);
        assert(d.PeakTapNorm<=d.MaxTapNorm*(1+1e-12) && d.RejectedUpdates==0);
        fprintf('UNIT %s echo=%g rail MSE %.6g -> %.6g tap norm %.4g\n', ...
            pulse,echo,d.InputStructureMSE,d.OutputStructureMSE,d.FinalTapNorm);
        args={'Modulation','OQPSK','SamplesPerSymbol',8,'PulseShapingFilter',char(pulse)};
        a=HelperCCSDSTMDemodulator(args{:});
        b=HelperCCSDSTMDemodulator(args{:},'OQPSKInputMatchedFiltered',true);
        assert(isequal(a(filter(h,1,x)),b(mf)),'Matched-filter bypass changed soft bits.');
        if echo>0, assert(d.OutputStructureMSE<d.InputStructureMSE); end
    end
end
summary=table();
if strcmp(stage,'unit'), return; end
p=struct('modType','OQPSK','symbolRate',10e6,'sps',8, ...
    'NumBytesInTransferFrame',258,'ConvolutionalCodeRate','3/4', ...
    'ConvolutionalReceiveMode','stream-raw-asm','hasASM',true, ...
    'PCMFormat','NRZ-L','RandomizerEnabled',false,'DataPathMode','single', ...
    'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableKnownHPreEqualizer',false, ...
    'enableReceiverTimeline',true,'showFigures',false,'randomSeed',917, ...
    'debugAdaptiveEqualizer',true);
if strcmp(stage,'offsets')
    impairments={struct('cfo',3000),struct('cfo',-3000), ...
        struct('phaseOffset',30),struct('delay',.5)};
    rows={};
    for pulse=["root raised cosine","none"]
        for k=1:numel(impairments)
            q=p; q.channelCoding='none'; q.ConvolutionalReceiveMode='legacy-coded-asm';
            q.PulseShapingFilter=char(pulse); q.enableHChannel=true;
            q.HMode='siso_multipath'; q.H=[1 zeros(1,7) .45+.15j];
            q.enableEqualizer=true; q.equalizerMode='blind-cma-lms';
            q.adaptiveEqualizerSamplingMode='oqpsk-staggered';
            q.randomSeed=20260927;
            name=fieldnames(impairments{k}); name=name{1};
            q.(name)=impairments{k}.(name);
            rng(q.randomSeed,'twister');
            logText=evalc('r=run_ccsds_tm_evaluation(q);');
            if ~r.success, fprintf('%s\n',logText); error('%s',r.errorMsg); end
            passed=r.BER==0 && r.FER==0 && r.CountedFrames==120 && ...
                r.MeasurementCoverage.Complete && ...
                r.MeasurementCoverage.RecoveredNotComparedFrames==0;
            assert(r.FastEnvelopeApplied && ~r.HighRatePhaseTrackingApplied && ...
                r.AdaptiveEqualizerEnabled);
            fprintf('OFFSET %s %s=%g BER=%g FER=%g coverage=%d/120\n', ...
                pulse,name,q.(name),r.BER,r.FER,r.CountedFrames);
            rows{end+1}=struct('Pulse',pulse,'Impairment',string(name), ...
                'Value',q.(name),'BER',r.BER,'FER',r.FER, ...
                'ComparedFrames',r.CountedFrames,'Pass',passed); %#ok<AGROW>
        end
    end
    summary=struct2table(vertcat(rows{:})); disp(summary);
    assert(all(summary.Pass),'OQPSK offset regression failed.');
    return;
end
if strcmp(stage,'ordinary')
    for modType=["BPSK","QPSK","8PSK","UQPSK","16QAM","32QAM","16APSK","32APSK"]
        q=p; q.modType=char(modType); q.channelCoding='convolutional';
        q.enableEqualizer=false; q.PulseShapingFilter='root raised cosine';
        rng(q.randomSeed,'twister');
        evalc('r=run_ccsds_tm_evaluation(q);');
        assert(r.success,'%s',r.errorMsg);
        fprintf('OTHER %s BER=%g FER=%g coverage=%d/120\n', ...
            modType,r.BER,r.FER,r.CountedFrames);
        assert(r.BER==0 && r.FER==0 && r.CountedFrames==120 && ...
            r.MeasurementCoverage.Complete && ...
            r.MeasurementCoverage.RecoveredNotComparedFrames==0);
    end
    return;
end
rows={};
for pulse=["root raised cosine","none"]
 for coding=["none","convolutional"]
  for enabled=[false true]
    q=p; q.PulseShapingFilter=char(pulse); q.channelCoding=char(coding);
    if coding=="none", q.ConvolutionalReceiveMode='legacy-coded-asm'; end
    if startsWith(stage,'multipath')
        q.enableHChannel=true; q.HMode='siso_multipath';
        q.H=[1 zeros(1,7) .45+.15j];
        % Diagnostic only: additionally bypass the retained envelope stage.
        if strcmp(stage,'multipath-isolated'), q.enableOQPSKHighRateTracking=false; end
    end
    q.enableEqualizer=enabled; q.equalizerMode='blind-cma-lms';
    q.adaptiveEqualizerSamplingMode='auto';
    rng(q.randomSeed,'twister');
    logText=evalc('r=run_ccsds_tm_evaluation(q);');
    if ~r.success, fprintf('%s\n',logText); error('%s',r.errorMsg); end
    fprintf('%s %s %s EQ=%d BER=%g FER=%g coverage=%d/120 mode=%s\n', ...
        stage,pulse,coding,enabled,r.BER,r.FER,r.CountedFrames,r.AdaptiveEqualizerMode);
    if enabled
        fprintf('  actual rail MSE %.6g -> %.6g; updates=%d\n', ...
            r.AdaptiveEqualizerInputStructureMSE,r.AdaptiveEqualizerOutputStructureMSE, ...
            r.AdaptiveEqualizerCMASymbols);
    end
    assert(r.Fs==q.symbolRate*q.sps);
    assert(r.AdaptiveEqualizerEnabled==enabled);
    assert(~r.HighRatePhaseTrackingApplied, ...
        'OQPSK must not use the QPSK fourth-power phase pre-tracker.');
    assert(r.FastEnvelopeApplied == ...
        (q.enableHChannel && ~strcmp(stage,'multipath-isolated')), ...
        'Retained envelope routing changed.');
    fprintf('  envelope=%d fourthPowerPhase=%d\n', ...
        r.FastEnvelopeApplied,r.HighRatePhaseTrackingApplied);
    passed=r.BER==0 && r.FER==0 && r.CountedFrames==120 && ...
        r.MeasurementCoverage.Complete && ...
        r.MeasurementCoverage.RecoveredNotComparedFrames==0;
    if ~passed
        lines=splitlines(string(logText));
        disp(lines(contains(lines,'OQPSK coarse CFO') | contains(lines,'Phase ambiguity')));
    end
    rows{end+1}=struct('Pulse',pulse,'Coding',coding,'Enabled',enabled, ...
        'BER',r.BER,'FER',r.FER,'ComparedFrames',r.CountedFrames, ...
        'ZeroErrorComplete',passed); %#ok<AGROW>
  end
 end
end
summary=struct2table(vertcat(rows{:})); disp(summary);
required=true(height(summary),1);
if startsWith(stage,'multipath'), required=summary.Enabled; end
assert(all(summary.ZeroErrorComplete(required)), ...
    'OQPSK EQ regression failed; no bad frames may be excluded.');
end
