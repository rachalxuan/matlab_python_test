function test_web_monitor
% A small genuine receive run: enabling monitoring must be observational.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
artifactRoot=fullfile(root,'artifacts','ccsds','monitor-regression');
if ~isfolder(artifactRoot), mkdir(artifactRoot); end
folder=tempname(artifactRoot); mkdir(folder);
p=struct('modType','QPSK','channelCoding','none','symbolRate',30e6, ...
    'sps',8,'snr',100,'noiseMode','off','cfo',0,'phaseOffset',0,'delay',0, ...
    'NumBytesInTransferFrame',1115,'berWarmUpFrames',4,'berFrames',8, ...
    'excludeBERWarmUpFrames',true, ...
    'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
    'showFigures',false,'enableRuntimeLockTelemetry',true,'enableReceiverTimeline',true, ...
    'outputDir',folder);
rng(8401,'twister'); a=run_ccsds_tm_evaluation(p);
p.enableWebMonitor=true;
rng(8401,'twister'); b=run_ccsds_tm_evaluation(p);
assert(a.success && b.success);
assert(isequaln(a.ReceiverTimeline,b.ReceiverTimeline),'Monitoring altered receiver results.');
assert(a.BER==b.BER && b.BER==0);
assert(b.ReceiverTimeline.MeasurementCoverage.Complete);
assert(b.ReceiverTimeline.MeasurementCoverage.ComparedFrames==8);
assert(b.RuntimeLockTelemetry.Frame.Available, ...
    'Aligned uncoded ASM evidence must be exported, not inferred from BER.');
snapshot=jsondecode(fileread(fullfile(folder,'receiver-monitor.json')));
assert(snapshot.metricsReady && strcmp(snapshot.processingMode,'batch'));
assert(strcmp(snapshot.stage,'results-ready'));
assert(~isfield(snapshot.timeline,'Observations'));
assert(snapshot.timeline.Summary.ComparedBits==b.ReceiverTimeline.Summary.ComparedBits);
assert(numel(snapshot.constellation.i)<=2048 && ~snapshot.constellation.timeResolved);
fprintf('PASS: web monitoring leaves receiver results unchanged; snapshot: %s\n',folder);
testAlignedASMObservation;
end

function testAlignedASMObservation
% A damaged marker must change the monitor, not the already aligned payload.
asm=int8(reshape(dec2bin(hex2dec('1ACFFC1D'),32).'-'0',[],1));
payload=zeros(16*8,1,'int8');
hard=repmat([asm;payload],6,1);
frameLength=numel(asm)+numel(payload);
hard(2*frameLength+(1:32))=1-asm;
% Complementary ASM can represent a separate phase hypothesis: use a mixed
% corruption instead, whose correlation cannot pass the fixed-slot gate.
hard(2*frameLength+(1:16))=asm(1:16);
decoder=HelperCCSDSTMDecoder('ChannelCoding','none','Modulation','QPSK', ...
    'NumBytesInTransferFrame',16,'HasASM',true,'RandomizerEnabled',false, ...
    'DisableFrameSynchronization',true,'DisablePhaseAmbiguityResolution',true, ...
    'FrameSyncLockThreshold',2,'FrameSyncUnlockThreshold',1);
bits=decoder(2*double(hard)-1);
trace=decoder.getFrameSyncTelemetry();
assert(isequal(bits,repmat(payload,6,1)), ...
    'Side-band ASM observation must not gate or mutate decoded payload.');
assert(trace.Available && numel(trace.Locked)==6);
assert(isequal(trace.ASMObservationAccepted(:),logical([1;1;0;1;1;1])));
assert(isequal(trace.Locked(:),logical([0;1;0;0;1;1])));
fprintf('PASS: fixed-slot ASM observation detects loss/reacquisition without changing payload.\n');
end
