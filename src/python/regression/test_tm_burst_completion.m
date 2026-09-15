function test_tm_burst_completion(runReceiver)
% Short, deterministic boundary tests; no long A4/TPC iterative sweep.
if nargin<1, runReceiver=false; end
addpath(fileparts(fileparts(mfilename('fullpath'))));
g=ccsdsTMWaveformGenerator('Modulation','8PSK','ChannelCoding','TPC', ...
    'TPCCodeRate','1/2','TPCBlocksPerTF',8,'HasASM',true, ...
    'RandomizerEnabled',false,'NumBytesInTransferFrame',2025, ...
    'SamplesPerSymbol',8);
rng(364232726,'twister');
u=int8(randi([0 1],g.NumInputBits*150,1));
[x,b]=g(u); prefix=x; randomState=rng;
[completed,tail]=HelperTMCompleteBurst(g,x,b,u,240e6,struct());
fprintf('TX proof: encoded=%d modulated=%d pending=%d applied=%d\n', ...
    numel(b),tail.OriginalModulatedBits,tail.BufferedModulationBits,tail.Applied);
assert(tail.Applied && numel(b)==4920000 && tail.BufferedModulationBits==3552);
assert(isequal(completed(1:numel(prefix)),prefix) && isequal(randomState,rng));
assert(numel(completed)/8*3>numel(b));
assert(abs(tail.MeasurementDuration_s-4920000/3/30e6)<1e-12);
fprintf('TX boundary: pending=%d bits released; original prefix/RNG unchanged; guards=%d.\n', ...
    tail.BufferedModulationBits,tail.GuardInputGroups);
clear completed prefix x b u g;
o=struct('ExpectedFrames',150,'FirstMeasurementFrame',31, ...
    'PayloadBitsPerFrame',16200,'TxFrameIndex',(1:149).', ...
    'Counted',[(false(30,1));true(119,1)]);
c=HelperTMMeasurementCoverage({o});
assert(~c.Complete && c.UnrecoveredFrames==1 && c.ComparedFrames==119);
assert(strcmp(c.Status,'MEASUREMENT_INCOMPLETE'));
o.TxFrameIndex=(1:150).'; o.Counted=[false(30,1);true(120,1)];
c=HelperTMMeasurementCoverage({o});
assert(c.Complete && c.ComparedBits==1944000 && c.ComparedFrames==120);
% Appended RX guard observations cannot satisfy a missing measured TX slot.
o.TxFrameIndex=[(1:149).';NaN;NaN]; o.Counted=[false(30,1);true(119,1);false;false];
c=HelperTMMeasurementCoverage({o});
assert(~c.Complete && c.ComparedFrames==119);
% Receiving a frame but excluding its comparison is a distinct failure.
o.TxFrameIndex=(1:150).'; o.Counted=[false(30,1);true(119,1);false];
c=HelperTMMeasurementCoverage({o});
assert(~c.Complete && c.UnrecoveredFrames==0 && c.RecoveredNotComparedFrames==1);
o.TxFrameIndex=[(1:149).';149]; o.Counted=[false(30,1);true(120,1)];
c=HelperTMMeasurementCoverage({o});
assert(~c.Complete && c.DuplicateComparisons==1 && c.ComparedFrames==119);
fprintf('Coverage: tail missing, full coverage, guard exclusion, uncounted recovered frame passed.\n');
% Lock in the guard interval must not repair an unlocked measured endpoint.
f=struct('Available',true,'ObservationIndex',(1:6).', ...
    'ASMObservationAccepted',[true;true;false;false;true;true], ...
    'Locked',[true;true;false;false;true;true]);
cfg=struct('FrameSyncTelemetry',f,'FrameDuration_s',.1,'ObservationEndTime_s',.4);
lock=HelperTMRuntimeLockTelemetry(cfg);
assert(lock.Frame.Available && ~lock.Frame.LockedAtEnd && ...
    all(lock.Frame.Time_s<=.4) && lock.Frame.Reacquisitions==0);
if runReceiver, test_tm_frame_association(true); end
end
