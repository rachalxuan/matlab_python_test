function [T,outputFile] = test_tm_ldpc78_link(stage,opt)
% Full-link QPSK 100 Mbps integration checks, no receiver parameter tuning.
% gate: No-H, retained EQ settings with master off / explicit off / on.
% coded / uncoded: saved A2/B1/A4 full intervals, sparse BP / no FEC.
% device: supplied ChannelFile, coded and uncoded (file identity user-owned).
% device-eq: same supplied file and LDPC waveform, EQ off / on.
% device-amplitude: EQ OFF, unchanged / constant RX RMS / RX envelope only.
% Retains failures and small timelines, never IQ. This is the existing main
% evaluator: reference-assisted phase selection may still be used by it.
if nargin<1, stage='gate'; end
if nargin<2, opt=struct(); end
stage=validatestring(stage,{'gate','coded','uncoded','device','device-eq','device-amplitude'});
allowed={'SourceFile','CaseIndices','ChannelFile','OutputDir'};
assert(isstruct(opt) && isscalar(opt) && all(ismember(fieldnames(opt),allowed)));
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
oldPath=path; pathCleanup=onCleanup(@()path(oldPath)); %#ok<NASGU>
oldRng=rng; rngCleanup=onCleanup(@()rng(oldRng)); %#ok<NASGU>
addpath(fullfile(root,'src','python'));
sourceFile=option(opt,'SourceFile',fullfile(root,'artifacts','ccsds', ...
    'system-eq','TM_EQ_files_20261014_101855_691.mat'));
s=load(sourceFile,'inputs','T');
indices=option(opt,'CaseIndices',[2 5 4]);
if strcmp(stage,'gate'), indices=[2 2 2]; end
if any(strcmp(stage,{'device','device-eq','device-amplitude'}))
    assert(isfield(opt,'ChannelFile') && isfile(opt.ChannelFile), ...
        'device requires the exact user-identified CDL-A-CITY ChannelFile.');
    indices=[2 2];
    if strcmp(stage,'device-amplitude'), indices=[2 2 2]; end
end
assert(all(indices>=1 & indices<=numel(s.inputs) & indices==floor(indices)));
outDir=option(opt,'OutputDir',fullfile(root,'artifacts','ccsds','ldpc78','full-link'));
if ~isfolder(outDir), mkdir(outDir); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
outputFile=fullfile(outDir,['LDPC78_Link_' stage '_' stamp '.mat']);
n=numel(indices); inputs=cell(n,1); rows=cell(n,1); badFrames=cell(n,1);
coverage=cell(n,1); telemetry=cell(n,1); T=table();
meta=struct('Stage',stage,'SourceFile',sourceFile, ...
    'ReferenceAssistedPhaseSelectionPossible',true, ...
    'ComparisonMeaning','same modulator rate/channel interval, not identical coded and uncoded IQ');
for k=1:n
    p=s.inputs{indices(k)};
    assert(strcmpi(p.modType,'QPSK') && strcmpi(p.channelCoding,'LDPC') && ...
        strcmp(p.CodeRate,'7/8') && p.NumBitsInInformationBlock==7136);
    assert(p.modulatorBitRateMbps==100,'This regression requires the original 100 Mbps configuration.');
    label=string(s.T.Channel(indices(k)));
    expectedEQ=logical(p.enableEqualizer);
    p.captureLDPC78LLR=false; p.LDPCDecoderMode='standard-sparse-bp';
    p.LDPCMaxIterations=20; p.noiseMode='off';
    p.showFigures=false; p.captureBaselineData=false;
    p.enableReceiverTimeline=true; p.enableRuntimeLockTelemetry=true;
    p.enableKnownHPreEqualizer=false;
    if strcmp(stage,'gate')
        p.enableHChannel=false; p.HMode='none';
        p.enableEqualizer=(k==3); expectedEQ=(k==3);
        label="No-H-gate-"+string(k);
        if k==2
            p.equalizerMode='off'; p.adaptiveEqualizerSamplingMode='off';
            p.adaptiveFractionalPostMode='off';
        end
    elseif any(strcmp(stage,{'device','device-eq','device-amplitude'}))
        p.channelFilePath=char(opt.ChannelFile);
        [~,name]=fileparts(p.channelFilePath); label=string(name);
        if strcmp(stage,'device-eq')
            p.enableEqualizer=(k==2); expectedEQ=(k==2);
        elseif strcmp(stage,'device-amplitude')
            modes={'off','rms','envelope'};
            p.enableEqualizer=false; expectedEQ=false;
            p.debugTimingInputAmplitudeMode=modes{k};
        end
    end
    if strcmp(stage,'uncoded') || (strcmp(stage,'device') && k==2)
        % Removing FEC changes frame duration: retain the SAME physical time
        % interval, with rounding outward by less than one uncoded frame.
        rate=p.modulatorBitRateMbps*1e6;
        warmSeconds=p.berWarmUpFrames*8192/rate;
        endSeconds=(p.berWarmUpFrames+p.berFrames)*8192/rate;
        p.channelCoding='none';
        p=rmfield(p,{'CodeRate','NumBitsInInformationBlock','IsLDPCOnSMTF','LDPCDecoderMode','LDPCMaxIterations'});
        frameSeconds=(32+8*p.NumBytesInTransferFrame)/rate;
        p.berWarmUpFrames=ceil(warmSeconds/frameSeconds);
        p.berFrames=ceil(endSeconds/frameSeconds)-p.berWarmUpFrames;
    end
    inputs{k}=p;
    row=struct('CaseIndex',k,'Channel',label,'Coding',string(p.channelCoding), ...
        'AmplitudeProbe',string(option(p,'debugTimingInputAmplitudeMode','off')), ...
        'ProbeInputPower',NaN,'ProbeOutputPower',NaN, ...
        'Seed',p.randomSeed,'RequestedEQ',expectedEQ,'ActualEQ',false, ...
        'ActualSampling',"",'EQAccepted',false,'Decoder',"", ...
        'BER',NaN,'FER',NaN,'ComparedFrames',0,'ExpectedFrames',p.berFrames, ...
        'RecoveredNotCompared',NaN,'CoverageComplete',false, ...
        'FrameLockRate',NaN,'FrameLockAvailable',false, ...
        'FrameReacquisitions',NaN,'CarrierLockRate',NaN, ...
        'ErrorBits',NaN,'ComparedBits',NaN,'Seconds',NaN,'Status',"NOT_RUN",'Error',"");
    fprintf('\n[LDPC link %s %d/%d] %s coding=%s EQ=%d frames=%d+%d\n', ...
        stage,k,n,label,p.channelCoding,expectedEQ,p.berWarmUpFrames,p.berFrames);
    timer=tic;
    try
        rng(p.randomSeed,'twister');
        r=run_ccsds_tm_evaluation(p);
        assert(r.success,'%s',char(string(option(r,'errorMsg','evaluation failed'))));
        row.ActualEQ=logical(r.AdaptiveEqualizerEnabled);
        row.ActualSampling=string(r.AdaptiveEqualizerSamplingMode);
        row.EQAccepted=logical(r.AdaptiveEqualizerOutputAccepted);
        row.Decoder=string(option(r,'LDPCDecoderMode','none'));
        assert(row.ActualEQ==expectedEQ,'EQ master switch routing mismatch');
        if strcmpi(p.channelCoding,'LDPC')
            assert(row.Decoder=="standard-sparse-bp",'Wrong LDPC decoder');
        end
        row.BER=r.BER; row.FER=r.FER;
        amp=option(r,'TimingInputAmplitudeDiagnostic',struct());
        if row.AmplitudeProbe~="off"
            assert(option(amp,'Applied',false),'Requested amplitude diagnostic did not execute.');
        end
        row.ProbeInputPower=option(amp,'InputPower',NaN);
        row.ProbeOutputPower=option(amp,'OutputPower',NaN);
        c=r.MeasurementCoverage; coverage{k}=c;
        row.ComparedFrames=c.ComparedFrames; row.ExpectedFrames=c.ExpectedFrames;
        row.RecoveredNotCompared=c.RecoveredNotComparedFrames;
        row.CoverageComplete=logical(c.Complete);
        row.FrameLockRate=option(r,'FrameSyncLockRate',NaN);
        row.FrameReacquisitions=option(r,'FrameSyncReacquisitions',NaN);
        row.CarrierLockRate=option(r,'CarrierLockRate',NaN);
        telemetry{k}=option(r,'RuntimeLockTelemetry',struct());
        frameTelemetry=option(telemetry{k},'Frame',struct());
        row.FrameLockAvailable=option(frameTelemetry,'Available',false);
        if isfield(r,'ReceiverTimeline') && r.ReceiverTimeline.Available
            F=struct2table(r.ReceiverTimeline.Rows);
            use=F.MeasurementEligible;
            row.ErrorBits=sum(F.ErrorBitsDelta(use));
            row.ComparedBits=sum(F.ComparedBitsDelta(use));
            names={'TxFrameIndex','TimeStart_s','TimeEnd_s','Coverage', ...
                'ComparedBitsDelta','ErrorBitsDelta','FrameBER'};
            badFrames{k}=F(use & (F.ComparedBitsDelta==0 | F.ErrorBitsDelta>0),names);
        end
        if ~c.Complete || c.RecoveredNotComparedFrames>0
            row.Status="MEASUREMENT_INCOMPLETE";
        elseif ~isfinite(row.BER) || ~isfinite(row.FER)
            row.Status="METRIC_UNAVAILABLE";
        elseif row.BER==0 && row.FER==0
            row.Status="ZERO_ERRORS_COMPLETE";
        else
            row.Status="DECODE_ERRORS";
        end
    catch err
        row.Status="RUN_ERROR"; row.Error=string(err.message);
        fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
    end
    row.Seconds=toc(timer); rows{k}=row;
    T=struct2table(vertcat(rows{1:k}));
    save(outputFile,'T','inputs','badFrames','coverage','telemetry','meta','-v7');
    fprintf('[link result] %s BER=%g FER=%g coverage=%d/%d EQ=%d time=%.1fs\n', ...
        row.Status,row.BER,row.FER,row.ComparedFrames,row.ExpectedFrames,row.ActualEQ,row.Seconds);
    clear r;
end
disp(T); fprintf('Report: %s\n',outputFile);
end

function value=option(s,name,fallback)
value=fallback;
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); end
end
