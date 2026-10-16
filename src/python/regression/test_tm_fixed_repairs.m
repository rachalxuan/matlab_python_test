function T = test_tm_fixed_repairs(whichCase,overrides)
% Fixed failure/regression inputs; truth is used ONLY by the BER evaluator.
% No signal captures. One result file per group is replaced on rerun.
if nargin<2, overrides=struct(); end
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
if strcmpi(whichCase,'unit'), T=localUnit(); return; end
if strcmpi(whichCase,'qpsk-logic-unit'), T=localQPSKLogicUnit(); return; end
if strcmpi(whichCase,'phase-unit'), T=localPhaseUnit(); return; end
folder=fullfile(root,'artifacts','ccsds','system-eq');
switch lower(string(whichCase))
    case 'qpsk-phase', file='TM_EQ_files_20261013_103200_321.mat'; indices=[29 2 3];
    case 'qpsk-phase-ab', file='TM_EQ_files_20261013_103200_321.mat'; indices=[29 29];
    case 'qpsk-phase-noh', file='TM_EQ_files_20261013_103200_321.mat'; indices=repmat(2,1,8);
    case 'qpsk-stage2', file='TM_EQ_files_20261013_103200_321.mat'; indices=[34 35 2 3 29];
    case 'qpsk-itu', file='TM_EQ_files_20261013_103200_321.mat'; indices=[34 35];
    case 'bpsk', file='TM_EQ_cd_20261011_184320_360.mat'; indices=6;
    case 'bpsk-seed', file='TM_EQ_cd_20261011_184320_360.mat'; indices=6;
    case 'bpsk-regression', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[2 4 8];
    case 'qam', file='TM_EQ_psd_20261011_201140_162.mat'; indices=41;
    case 'qam-regression', file='TM_EQ_psd_20261011_201140_162.mat'; indices=[32 35 38 40];
    case 'qam-rrc', file='TM_EQ_psd_20261011_201140_162.mat'; indices=38;
    case 'qam-16none', file='TM_EQ_psd_20261011_201140_162.mat'; indices=35;
    case 'qam-lownoise', file='TM_EQ_psd_20261011_201140_162.mat'; indices=40;
    case 'qam-integration', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[46 54 42 50];
    case 'qam-fir-noh', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[42 46 50 54];
    case 'apsk', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[67 68];
    case 'apsk-on', file='TM_EQ_cd_20261011_184320_360.mat'; indices=68;
    case 'apsk16-fixed', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[60 60];
    case 'apsk-d1-pulse', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[64 68 72];
    case 'apsk-noh', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[59 60 63 64 67 68 71 72];
    case 'apsk-regression', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[60 64 72];
    case 'smoke', file='TM_EQ_cd_20261011_184320_360.mat'; indices=[2 6 10 14 18 22 26 30 34 38 42 46 50 54 58 62 66 70];
    otherwise, error('Unknown case group. See tm_system_failure_diagnosis.md.');
end
s=load(fullfile(folder,file),'inputs','T'); rows=cell(numel(indices),1);
logs=cell(size(rows)); inputs=cell(size(rows));
diagnostics=repmat({struct()},size(rows));
runInfo=struct('Created',char(datetime('now')),'MATLAB',version, ...
    'Group',char(whichCase),'Overrides',overrides);
for n=1:numel(indices)
    k=indices(n); p=s.inputs{k};
    if strcmpi(whichCase,'qpsk-phase-ab'), p.enableContinuousConvPhaseReacquisition=n==2; end
    if any(strcmpi(whichCase,{'smoke','qam-integration','qam-fir-noh','apsk-noh','qpsk-phase-noh'}))
        p.enableHChannel=false; p.HMode='none'; p.noiseMode='off';
        p.berWarmUpFrames=30; p.berFrames=120;
    end
    if strcmpi(whichCase,'qpsk-phase-noh')
        rates={'1/2','2/3','3/4','5/6','7/8','3/4','5/6','3/4'};
        p.ConvolutionalCodeRate=rates{n};
        if n==6 || n==7
            p.channelCoding='concatenated'; p.RSInterleavingDepth=1;
            p.RSMessageLength=223+16*(n==7); p.NumBytesInTransferFrame=p.RSMessageLength;
            p.IsRSMessageShortened=false;
        end
        if n==8, p.PulseShapingFilter='none'; end
    end
    if strcmpi(whichCase,'bpsk-seed'), p.randomSeed=20260927; end
    if strcmpi(whichCase,'apsk16-fixed'), p.randomSeed=916+n; end
    if strcmpi(whichCase,'qam-integration')
        p.ConvolutionalReceiveMode='legacy-coded-asm';
        if n<=2
            p.channelCoding='TPC'; p.TPCCodeRate='1/2'; p.TPCBlocksPerTF=8;
            p.NumBytesInTransferFrame=2025;
        else
            p.DataPathMode='dualIQ'; p.ConvolutionalCodeRate='1/2';
        end
    end
    fields=fieldnames(overrides);
    for j=1:numel(fields), p.(fields{j})=overrides.(fields{j}); end
    inputs{n}=p; rng(p.randomSeed,'twister'); tic;
    logs{n}=evalc('r=run_ccsds_tm_evaluation(p);');
    row=struct('Case',k,'Seed',p.randomSeed,'Modulation',string(p.modType), ...
        'Pulse',string(p.PulseShapingFilter),'RunCompleted',r.success,'BER',NaN,'FER',NaN, ...
        'Compared',0,'Expected',p.berFrames,'Complete',false, ...
        'RecoveredNotCompared',NaN,'ZeroErrorFullCoverage',false,'Seconds',toc,'Reason',"");
    if r.success
        row.BER=r.BER; row.FER=r.FER; c=r.MeasurementCoverage;
        row.Compared=c.ComparedFrames; row.Expected=c.ExpectedFrames;
        row.Complete=c.Complete; row.RecoveredNotCompared=c.RecoveredNotComparedFrames;
        row.ZeroErrorFullCoverage=row.BER==0 && row.FER==0 && ...
            row.Complete && row.RecoveredNotCompared==0;
        if isfield(r,'QAMCarrierRecovery'), diagnostics{n}.QAM=r.QAMCarrierRecovery; end
        if isfield(r,'APSKAcquisitionEqualizer'), diagnostics{n}.APSK=r.APSKAcquisitionEqualizer; end
        diagnostics{n}.EqualizerStructure=r.AdaptiveEqualizerStructure;
        diagnostics{n}.EqualizerPosition=r.AdaptiveEqualizerPosition;
        diagnostics{n}.DDPasses=r.AdaptiveEqualizerDDPasses;
        diagnostics{n}.BPSReliableFraction=r.PilotlessAPSKBlindPhaseSearchReliableRate;
        diagnostics{n}.FractionalDualApplied=r.AdaptiveFractionalDualModeApplied;
        diagnostics{n}.FractionalDualDDMSE=r.AdaptiveFractionalDualDDMSE;
        diagnostics{n}.PSKPostFSEPhaseTrackerMode=r.PSKPostFSEPhaseTrackerMode;
        if isfield(r,'RuntimeLockTelemetry'), diagnostics{n}.RuntimeLockTelemetry=r.RuntimeLockTelemetry; end
        if isfield(r,'ReceiverTimeline'), diagnostics{n}.ReceiverTimeline=r.ReceiverTimeline; end
        if isfield(r,'HChannelMeta'), diagnostics{n}.HChannelMeta=r.HChannelMeta; end
        if isfield(r,'HEffectiveTaps'), diagnostics{n}.HEffectiveTaps=r.HEffectiveTaps; end
        if isfield(r,'ContinuousConvPhaseRecovery'), diagnostics{n}.PhaseRecovery=r.ContinuousConvPhaseRecovery; end
        if contains(upper(string(p.modType)),'APSK') && p.enableEqualizer && ...
                strcmpi(p.equalizerMode,'blind-cma-lms')
            eq=r.APSKAcquisitionEqualizer;
            assert(eq.Applied && strcmp(eq.Position,'pre-carrier') && ...
                eq.PostBlindStartupSkipped && eq.InputSymbols==eq.OutputSymbols, ...
                'APSK FIR placement, ownership or sample count regression.');
            assert(strcmp(r.AdaptiveEqualizerStructure,'fir') && ...
                r.AdaptiveEqualizerDDPasses==0, ...
                'APSK unexpectedly collapsed to scalar or restarted post-carrier DD.');
        end
    else
        row.Reason=string(r.errorMsg);
    end
    rows{n}=row; disp(struct2table(row));
    if strcmpi(whichCase,'qpsk-phase-noh')
        fprintf('No-H profile: %s %s %s\n',p.channelCoding,p.ConvolutionalCodeRate,p.PulseShapingFilter);
        assert(row.ZeroErrorFullCoverage,'No-H phase-recovery integration regressed.');
    end
    % Checkpoint compact rows, not waveforms. A MATLAB/MEX process failure
    % must not erase the evidence from preceding completed cases.
    T=struct2table(vertcat(rows{1:n})); baseline=s.T(indices(1:n),:);
    save(fullfile(folder,['Repair_' char(whichCase) '.mat']), ...
        'T','baseline','inputs','logs','diagnostics','runInfo','-v7');
end
end

function T=localQPSKLogicUnit()
% Inject errors BEFORE convolutional encoding: the receiver must preserve
% real payload errors and bad ASM observations, not hide them by clipping.
rng(917,'twister'); asm=int8(bitget(uint32(hex2dec('1ACFFC1D')),32:-1:1)).';
payload=int8(randi([0 1],256,20)); rows={};
for rate=["1/2","2/3","3/4","5/6","7/8"]
    pc=ccsdsTMConvolutionalPunctureConfig(char(rate));
    trellis=ccsdsTMConvolutionalOutputTrellis(poly2trellis(7,[171 133]),'auto-ccsds',char(rate));
    for fixture=["clean","bad-asm","bad-payload","startup","no-lock"]
        raw=[repmat(asm,1,20);payload]; firstFrame=1;
        if fixture=="bad-asm" || fixture=="bad-payload"
            raw(1:5,8)=1-raw(1:5,8);
        end
        if fixture=="bad-payload", raw(40,8)=1-raw(40,8); end
        if fixture=="startup"
            raw(1:5,2:4)=1-raw(1:5,2:4); firstFrame=5;
        end
        if fixture=="no-lock", raw(1:5,:)=1-raw(1:5,:); end
        input=double(raw(:)); padding=120+mod(-numel(input)-120,pc.InputBitsPerPeriod);
        encoder=comm.ConvolutionalEncoder('TrellisStructure',trellis, ...
            'TerminationMethod','Continuous','PuncturePatternSource','Property', ...
            'PuncturePattern',pc.Pattern);
        soft=2*double(encoder([input;zeros(padding,1)]))-1;
        for chunk=[Inf 137]
            rx=HelperTMContinuousConvReceiver('CodeRate',char(rate), ...
                'FramePayloadBits',256,'Verbose',false);
            if isinf(chunk), rx.append(soft);
            else
                for k=1:chunk:numel(soft), rx.append(soft(k:min(k+chunk-1,end))); end
            end
            [decoded,info]=rx.finalize(); c=info.Candidates(info.SelectedCandidate);
            if fixture=="no-lock"
                assert(~info.Available && isempty(decoded)); errors=NaN;
            else
                assert(info.Available && size(decoded,2)==21-firstFrame);
                assert(c.FirstFrameStart==1+(firstFrame-1)*288);
                assert(isequal(decoded,raw(33:end,firstFrame:end)));
                errors=nnz(decoded~=payload(:,firstFrame:end));
                assert(errors==double(fixture=="bad-payload"));
                if fixture=="bad-asm" || fixture=="bad-payload"
                    assert(c.ASMErrors(8)==5 && c.LongestGoodRun==12);
                end
            end
            rows{end+1}=struct('Rate',rate,'Fixture',fixture,'Chunk',chunk, ...
                'Frames',size(decoded,2),'PayloadErrors',errors,'Passed',true); %#ok<AGROW>
        end
    end
end
T=struct2table(vertcat(rows{:})); disp(T);
% A recovered list beginning 723 physical frames late must not reset time.
frame=struct('Available',true,'Source','continuous-viterbi-raw-asm', ...
    'ObservationIndex',(1:8)','ASMObservationAccepted',true(8,1), ...
    'Locked',[false(3,1);true(5,1)],'PositionDomain','decoded-raw-bit', ...
    'InputFrameLength',2096,'NominalRawBitOffset',0, ...
    'PeakPosition',1+(0:7)'*2096);
cfg=struct('FrameSyncTelemetry',frame,'FrameDuration_s',2096*4/3/100e6);
a=HelperTMRuntimeLockTelemetry(cfg);
cfg.FrameSyncTelemetry.PeakPosition=frame.PeakPosition+723*2096;
b=HelperTMRuntimeLockTelemetry(cfg);
assert(max(abs(b.Frame.Time_s-a.Frame.Time_s-723*cfg.FrameDuration_s))<1e-12);
assert(abs(b.Frame.FirstLockTime_s-a.Frame.FirstLockTime_s-723*cfg.FrameDuration_s)<1e-12);
cfg.FrameSyncTelemetry.PeakPosition(2)=NaN;
b=HelperTMRuntimeLockTelemetry(cfg); assert(~b.Frame.Available);
fprintf('All 50 continuous-receiver fixtures and frame-clock checks passed.\n');
end

function T=localPhaseUnit()
rng(917,'twister'); asm=int8(bitget(uint32(hex2dec('1ACFFC1D')),32:-1:1)).';
payload=int8(randi([0 1],264,40)); L=296; angles=[0 90 180 270]; rows={};
for rate=["1/2","2/3","3/4","5/6","7/8"]
    pc=ccsdsTMConvolutionalPunctureConfig(char(rate));
    trellis=ccsdsTMConvolutionalOutputTrellis(poly2trellis(7,[171 133]),'auto-ccsds',char(rate));
    args={'CodeRate',char(rate),'FramePayloadBits',264,'Verbose',false};
    for fixture=["clean","constant90","bad-asm","bad-payload","plus90","minus90-mid","two-slips"]
        raw=[repmat(asm,1,40);payload];
        if fixture=="bad-asm", raw(1:5,8:10)=1-raw(1:5,8:10); end
        if fixture=="bad-payload", raw(45,8)=1-raw(45,8); end
        bits=double(raw(:)); pad=120+mod(-numel(bits)-120,pc.InputBitsPerPeriod);
        if mod((numel(bits)+pad)/pc.InputBitsPerPeriod*pc.OutputBitsPerPeriod,2)
            pad=pad+pc.InputBitsPerPeriod;
        end
        enc=comm.ConvolutionalEncoder('TrellisStructure',trellis,'TerminationMethod','Continuous', ...
            'PuncturePatternSource','Property','PuncturePattern',pc.Pattern);
        coded=enc([bits;zeros(pad,1)]);
        modulator=comm.PSKModulator('ModulationOrder',4,'PhaseOffset',pi/4, ...
            'BitInput',true,'SymbolMapping','Custom','CustomSymbolMapping',[0;2;3;1]);
        x=modulator(coded); expectedSwitches=0;
        if fixture=="constant90", x=x*1j; end
        if any(fixture==["plus90","minus90-mid","two-slips"])
            rawPos=16*L;
            if fixture=="minus90-mid", rawPos=rawPos+floor(L/2); end
            codedPos=floor(rawPos/pc.InputBitsPerPeriod)*pc.OutputBitsPerPeriod+ ...
                nnz(pc.Pattern(1:2*mod(rawPos,pc.InputBitsPerPeriod)));
            at=floor(codedPos/2)+1; angle=90;
            if fixture=="minus90-mid", angle=-90; end
            x(at:end)=x(at:end)*exp(1j*deg2rad(angle)); expectedSwitches=1;
            if fixture=="two-slips"
                rawPos=28*L;
                codedPos=floor(rawPos/pc.InputBitsPerPeriod)*pc.OutputBitsPerPeriod+ ...
                    nnz(pc.Pattern(1:2*mod(rawPos,pc.InputBitsPerPeriod)));
                at=floor(codedPos/2)+1; x(at:end)=x(at:end)*(-1j); expectedSwitches=2;
            end
        end
        soft=cell(4,1);
        for b=1:4
            demod=HelperCCSDSTMDemodulator('Modulation','QPSK','ChannelCoding','convolutional');
            soft{b}=demod(x*exp(1j*deg2rad(angles(b))));
        end
        referenceDecoded=[]; referenceStarts=[];
        for chunk=[Inf 137]
            streams=soft;
            if isfinite(chunk)
                for b=1:4
                    ix=1:chunk:numel(soft{b}); streams{b}=cell(numel(ix),1);
                    for j=1:numel(ix), streams{b}{j}=soft{b}(ix(j):min(ix(j)+chunk-1,end)); end
                end
            end
            [decoded,info]=HelperTMConvPhaseReacquirer(@(b)streams{b},angles,args,3);
            assert(info.Available && info.PhaseRecovery.SwitchCount==expectedSwitches, ...
                'Phase recovery mismatch: %s, %s',rate,fixture);
            c=info.Candidates(1); ids=1+(c.FrameStarts-1)/L;
            assert(all(ids==round(ids)) && all(diff(ids)>0) && all(ids<=40));
            errors=sum(decoded~=payload(:,ids),1);
            if expectedSwitches==0
                assert(numel(ids)==40 && sum(errors)==double(fixture=="bad-payload"));
            else
                safe=ids<=14 | ids>=35;
                assert(nnz(ids<=14)==14 && nnz(ids>=35)==6 && all(errors(safe)==0));
                assert(any(errors>0),'Already committed transition errors were hidden.');
            end
            if isinf(chunk), referenceDecoded=decoded; referenceStarts=c.FrameStarts;
            else, assert(isequal(decoded,referenceDecoded) && isequal(c.FrameStarts,referenceStarts)); end
            rows{end+1}=struct('Rate',rate,'Fixture',fixture,'Chunk',chunk, ... %#ok<AGROW>
                'Switches',expectedSwitches,'Frames',numel(ids),'Errors',sum(errors),'Passed',true);
        end
    end
    % Equally credible phase hypotheses cannot be arbitrarily selected.
    [d,info]=HelperTMConvPhaseReacquirer(@(~)soft{1},angles,args,3);
    assert(~info.Available && info.Ambiguous && isempty(d) && ...
        ~info.PhaseRecovery.FrameSyncTelemetry.Available);
    [d,info]=HelperTMConvPhaseReacquirer(@(~)zeros(1000,1),angles,args,3);
    assert(~info.Available && isempty(d) && ~info.PhaseRecovery.FrameSyncTelemetry.Available);
end
T=struct2table(vertcat(rows{:})); disp(T);
fprintf('70 phase/continuous-state tests, 5 ambiguity and 5 no-evidence rejections passed.\n');
end

function T=localUnit()
rows={};
for M=[16 32]
    ref=qammod((0:M-1)',M,'UnitAveragePower',true);
    for seed=[917 20260927]
        rng(seed,'twister'); tx=ref(randi(M,20000,1));
        for cfo=[-500 500]
            n=(0:numel(tx)-1)'; rx=tx.*exp(1j*(.71+2*pi*cfo*n/30e6));
            [y,~,info]=HelperTMQAMCarrierSynchronizer(rx,ref,.005,30e6);
            ix=(4097:numel(tx))';
            phase=angle(tx(ix)'*y(ix)); branch=round(phase/(pi/2))*(pi/2);
            evm=norm(y(ix)*exp(-1j*branch)-tx(ix))/norm(tx(ix));
            assert(evm<1e-6,'QAM carrier noiseless unit regression failed.');
            rows{end+1}=struct('M',M,'Seed',seed,'CFO',cfo, ...
                'EVM',evm,'FinalFrequencyHz',info.FinalFrequencyHz); %#ok<AGROW>
        end
    end
end
T=struct2table(vertcat(rows{:})); disp(T);
% Structural FIR checks, separate from full-link BER tests. No training
% truth: rotation equivariance, count preservation and frozen-prefix scope.
rng(917,'twister'); x=randn(2500,1)+1j*randn(2500,1);
ref=[.4;.8;1.2]; opt=struct('AcquisitionSymbols',512);
[a,info]=HelperTMBlindAcquisitionEqualizer(x,ref,opt);
b=HelperTMBlindAcquisitionEqualizer(x*exp(.7j),ref,opt);
assert(numel(a)==numel(x) && info.TapNorm<=4+1e-12);
assert(norm(b-a*exp(.7j))/norm(a)<1e-10);
x(1100:end)=2*x(1100:end);
b=HelperTMBlindAcquisitionEqualizer(x,ref,opt);
assert(isequal(a(1:1024),b(1:1024)), ...
    'Later samples changed the frozen acquisition/validation prefix.');
fprintf('Blind RDE length, phase-equivariance and frozen-prefix checks passed.\n');
% Short/unqualified blind startup cannot turn a requested FIR into scalar.
for modName=["16APSK","16QAM"]
    if modName=="16APSK", ref=HelperCCSDSFACMReferenceConstellation(14);
    else, ref=qammod((0:15)',16,'UnitAveragePower',true); end
    ref=ref(:); x=ref(randi(numel(ref),2048,1));
    opt=struct('modType',char(modName),'adaptiveEqualizerTaps',11, ...
        'adaptiveEqualizerCMAWarmupSymbols',1,'adaptiveEqualizerDDPasses',0, ...
        'adaptiveEqualizerAutoScalarForQAM',true,'adaptiveEqualizerScalarSideTapOnRatio',1);
    [~,state,eq]=HelperTMBlindCMAEqualizer(x,ref,opt);
    assert(eq.NumTaps==11 && strcmp(eq.EqualizerStructure,'fir') && numel(state.Weights)==11);
    opt.adaptiveEqualizerTaps=1;
    [~,~,eq]=HelperTMBlindCMAEqualizer(x,ref,opt);
    assert(eq.NumTaps==1 && strcmp(eq.EqualizerStructure,'scalar'));
end
fprintf('Explicit FIR/scalar structure checks passed (APSK and QAM legacy auto-scalar request).\n');
end
