function report = test_receiver_timeline(runIntegration)
% Fast accounting tests, plus an optional short receiver on/off comparison.
if nargin<1, runIntegration=false; end
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
locks=struct('Carrier',struct('Available',true, ...
    'Time_s',[.01;.11;.21;.31;.41;.51], ...
    'State',[false;true;false;true;true;true], ...
    'Quality',[1;.1;1;.1;.1;.1]), ...
    'Timing',struct('Available',false),'Frame',struct('Available',false));
obs=struct('Lane','single','ExpectedFrames',6,'PayloadBitsPerFrame',100, ...
    'FirstMeasurementFrame',2,'RxFrameIndex',(1:5).', ...
    'TxFrameIndex',[1;2;4;5;NaN],'ErrorBits',[0;0;7;0;NaN], ...
    'Counted',[false;true;true;true;false]);
M=HelperTMReceiverTimeline({obs},locks,.6,3,1,7/300);
T=struct2table(M.Rows);
assert(M.Available && M.Summary.ComparedBits==300 && M.Summary.ErrorBits==7);
assert(M.Summary.MissingWithinObservedSpan==1 && ...
    M.Summary.BoundaryOrUnlocalizedMissing==1 && M.Summary.UnmatchedRxFrames==1);
assert(isnan(T.FrameBER(3)) && T.CumulativeComparedBits(3)==T.CumulativeComparedBits(2));
assert(T.Coverage(6)=="unobserved-trailing" && isnan(T.FrameBER(6)));
assert(all(isnan(T.TimingLastObservedState)) && T.CarrierLastObservedState(3)==0);
assert(T.CarrierEvidenceAge_s(end)>0 && M.Summary.LegacyBERMatchesCounters);
% Null output is an outage/unobserved record, NOT BER=0.
empty=obs; empty.RxFrameIndex=zeros(0,1); empty.TxFrameIndex=zeros(0,1);
empty.ErrorBits=zeros(0,1); empty.Counted=false(0,1);
outage=HelperTMReceiverTimeline({empty},locks,.6,0,0,NaN);
assert(outage.Summary.UnrecoveredMeasurementFrames==5 && ...
    isnan(outage.Summary.MeasuredBER));
assert(all(isnan([outage.Rows.FrameBER])));
% Duplicate decoder output preserves legacy bit counters without hiding
% duplicate delivery, or inflating unique recovered-frame coverage.
dup=obs; dup.RxFrameIndex=(1:6).'; dup.TxFrameIndex=[1;2;4;5;NaN;4];
dup.ErrorBits=[0;0;7;0;NaN;1]; dup.Counted=[false;true;true;true;false;true];
duplicate=HelperTMReceiverTimeline({dup},locks,.6,4,2,8/400);
assert(duplicate.Summary.DuplicateRecoveredFrames==1 && duplicate.Summary.ErrorBits==8);
assert(duplicate.Summary.NonForwardRxMatches==1 && duplicate.Summary.FrameAssociationSuspect);
assert(~M.Summary.FrameAssociationSuspect);
% Two rails stay separate while sharing the physical waveform time span.
i=obs; i.Lane='I'; q=obs; q.Lane='Q';
split=HelperTMReceiverTimeline({i,q},locks,.6,6,2,14/600);
assert(numel(split.Rows)==12 && split.Summary.ErrorBits==14 && ...
    max([split.Rows.TimeEnd_s])==.6);
json=jsonencode(M); roundTrip=jsondecode(json);
assert(roundTrip.Summary.ErrorBits==7 && isempty(roundTrip.Rows(3).FrameBER));
unavailable=HelperTMReceiverTimeline({},locks,.6,0,0,NaN);
assert(~unavailable.Available);
rejected=false;
try
    HelperTMReceiverTimeline({obs},locks,.6,4,1,7/300);
catch ex
    rejected=strcmp(ex.identifier,'ReceiverTimeline:CounterMismatch');
end
assert(rejected,'Counter mismatch must be detected.');
fprintf('Receiver timeline: 7 accounting/serialization checks passed.\n');
report=struct('UnitChecks',7,'Integration',struct([]));
if ~runIntegration, return; end
p=struct('modType','QPSK','channelCoding','none','symbolRate',10e6,'sps',8, ...
    'snr',100,'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'WaveformMode','ordinaryTM','NumBytesInTransferFrame',223, ...
    'hasASM',true,'RandomizerEnabled',false,'RandomizerFECPosition','afterEncoding', ...
    'DataPathMode','single','TMDataSource','random','RolloffFactor',.35, ...
    'berWarmUpFrames',4,'berFrames',12,'excludeBERWarmUpFrames',true, ...
    'enableHChannel',false,'enableEqualizer',false,'showFigures',false, ...
    'showPipelineFigure',false,'showPowerFigure',false, ...
    'enableRuntimeLockTelemetry',true,'enableReceiverTimeline',false);
configs={p,p,p}; configs{2}.channelCoding='RS'; configs{2}.RSMessageLength=223;
configs{2}.RSInterleavingDepth=1; configs{2}.IsRSMessageShortened=false;
configs{3}.DataPathMode='dualIQ';
report.Integration=repmat(struct('Coding','','LaneMode','','BER',NaN, ...
    'Summary',struct()),numel(configs),1);
for ci=1:numel(configs)
    test=configs{ci};
    rng(1234,'twister'); baselineLog=evalc('[baseline,~]=run_ccsds_tm_evaluation(test);');
    test.enableReceiverTimeline=true;
    rng(1234,'twister'); observedLog=evalc('[observed,~]=run_ccsds_tm_evaluation(test);');
    if ~baseline.success || ~observed.success
        disp(baseline); disp(observed); fprintf('%s\n%s\n',baselineLog,observedLog);
    end
    assert(baseline.success && observed.success,'Short receiver run failed.');
    assert(isequaln(baseline.BER,observed.BER) && ...
        isequaln(baseline.FER,observed.FER) && ...
        baseline.CountedFrames==observed.CountedFrames, ...
        'Instrumentation changed BER/FER or counted frames.');
    timeline=observed.ReceiverTimeline;
    assert(timeline.Available && timeline.Summary.ComparedFrames==observed.CountedFrames);
    assert(timeline.Summary.LegacyBERMatchesCounters && timeline.Summary.ComparedBits>0);
    assert(timeline.Summary.PhysicalAssociationLanes==numel(timeline.Observations));
    assert(abs(timeline.Summary.Duration_s-observed.MeasurementDuration_s)<1e-12);
    assert(observed.MeasurementCoverage.Complete && ...
        observed.MeasurementCoverage.UnrecoveredFrames==0);
    fprintf('QPSK %s %s: timeline on/off identical, BER=%g, compared=%d, missing=%d.\n', ...
        test.channelCoding,test.DataPathMode,observed.BER, ...
        timeline.Summary.ComparedFrames,timeline.Summary.UnrecoveredMeasurementFrames);
    report.Integration(ci)=struct('Coding',test.channelCoding,'LaneMode',test.DataPathMode, ...
        'BER',observed.BER,'Summary',timeline.Summary);
end
end
