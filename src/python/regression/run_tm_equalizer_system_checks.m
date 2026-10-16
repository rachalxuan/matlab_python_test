function [T,outputFile] = run_tm_equalizer_system_checks(stage,channelDir,opt)
% One permanent runner: frontend contract, C/D EQ A/B, then fixed-level PSD.
% No receiver algorithm tuning, no large waveforms, no stop on a bad case.
% contract: channelDir is the JSON fixture emitted by parameterContract.test.js.
% cd / psd-cd: channelDir contains 3GPPNTN-CDL_C_1_AntennaGain_1.mat, etc.
% psd: No-H noise-only control (EQ off), channelDir may be ''.
% noh: noiseless No-H. files / psd-files: independent ChannelFiles (not a
% concatenated snapshot sequence). Existing cd/psd defaults are unchanged.
% CodingProfile: conv-3/4 (unchanged default) or ordinary TM ldpc-7/8.
if nargin<2, channelDir=''; end
if nargin<3, opt=struct(); end
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
stage=lower(string(stage));
assert(any(stage==["contract","cd","psd","psd-cd","noh","files","psd-files"]),'Unknown stage.');
outputDir=fullfile(root,'artifacts','ccsds','system-eq');
if ~isfolder(outputDir), mkdir(outputDir); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
outputFile=fullfile(outputDir,['TM_EQ_' char(stage) '_' stamp '.mat']);
if stage=="contract"
    decoded=jsondecode(fileread(channelDir));
    if iscell(decoded), inputs=decoded(:); else, inputs=num2cell(decoded(:)); end
    keep=true(size(inputs));
    for k=1:numel(inputs)
        p=inputs{k};
        if isfield(opt,'Mods'), keep(k)=keep(k)&&any(strcmpi(p.modType,string(opt.Mods))); end
        if isfield(opt,'Pulses'), keep(k)=keep(k)&&any(strcmpi(p.PulseShapingFilter,string(opt.Pulses))); end
        if isfield(opt,'EQStates'), keep(k)=keep(k)&&ismember(p.enableEqualizer,opt.EQStates); end
    end
    inputs=inputs(keep);
    assert(~isempty(inputs),'No contract fixtures match the requested filters.');
    labels=repmat("synthetic-echo",numel(inputs),1);
    % ALSO check the independent MATLAB test configuration against requests
    % made by the real frontend contract; do not merely test a copied JSON.
    for k=1:numel(inputs)
        q=configureEQ(inputs{k},inputs{k}.enableEqualizer);
        fields={'equalizerMode','adaptiveEqualizerSamplingMode','enableKnownHPreEqualizer', ...
            'enableUQPSKPostCarrierAdaptiveEqualizer','enableQAMPostBPSAdaptiveEqualizer', ...
            'enablePilotlessAPSKPostFrontEndAdaptiveEqualizer','adaptiveFractionalPostMode'};
        for f=1:numel(fields)
            assert(isequal(q.(fields{f}),inputs{k}.(fields{f})), ...
                'Frontend/MATLAB request mismatch: %s / %s',q.modType,fields{f});
        end
    end
else
    codingProfile=lower(string(option(opt,'CodingProfile','conv-3/4')));
    assert(isscalar(codingProfile) && any(codingProfile==["conv-3/4","ldpc-7/8"]), ...
        'CodingProfile must be conv-3/4 or ldpc-7/8.');
    mods=string(option(opt,'Mods',["BPSK","QPSK","8PSK","OQPSK","UQPSK","16QAM","32QAM","16APSK","32APSK"]));
    pulses=string(option(opt,'Pulses',["root raised cosine","none"]));
    seeds=option(opt,'Seeds',917);
    profiles=string(option(opt,'Profiles',["C_1","D_1"]));
    endTime=option(opt,'TargetEnd_s',.082); warmTime=option(opt,'WarmupTime_s',.010);
    assert(endTime>warmTime && warmTime>=0,'Invalid measurement time interval.');
    assert(~isempty(mods) && all(ismember(mods,["BPSK","QPSK","8PSK","OQPSK","UQPSK","16QAM","32QAM","16APSK","32APSK"])));
    assert(~isempty(pulses) && all(ismember(pulses,["root raised cosine","none"])));
    assert(~isempty(seeds) && all(isfinite(seeds)) && all(seeds>=0) && all(seeds==floor(seeds)));
    noisePSDs=option(opt,'NoisePSDdBmHz',[-115 -105 -95]);
    assert(all(isfinite(noisePSDs)) && ~isempty(noisePSDs));
    levels=option(opt,'InputLevelDbm',-10); validateattributes(levels,{'numeric'},{'scalar','finite'});
    eqStates=[false true];
    if stage=="psd", eqStates=false; end
    eqStates=option(opt,'EQStates',eqStates);
    assert(~isempty(eqStates) && all(ismember(eqStates,[0 1])),'EQStates must contain 0/1.');
    eqStates=logical(eqStates);
    fileMode=any(stage==["files","psd-files"]);
    noisy=any(stage==["psd","psd-cd","psd-files"]);
    if ~noisy, noisePSDs=NaN; end
    channelPaths=strings(0,1);
    if fileMode
        channelPaths=string(option(opt,'ChannelFiles',strings(0,1)));
        channelPaths=channelPaths(:);
        assert(~isempty(channelPaths),'Supply opt.ChannelFiles: one independent channel per MAT file.');
        profiles=strings(size(channelPaths));
        for j=1:numel(channelPaths)
            assert(isfile(channelPaths(j)),'Missing channel file: %s',channelPaths(j));
            [~,profiles(j)]=fileparts(channelPaths(j));
        end
    elseif any(stage==["psd","noh"])
        profiles="No-H";
    else
        assert(~isempty(profiles) && all(ismember(profiles,["C_1","C_2","C_3","C_4","D_1","D_2","D_3","D_4"])));
        for profile=reshape(profiles,1,[])
            path=fullfile(channelDir,char("3GPPNTN-CDL_"+profile+"_AntennaGain_1.mat"));
            assert(isfile(path),'Missing channel file: %s',path);
        end
    end
    inputs={}; labels=strings(0,1);
    for seed=reshape(seeds,1,[])
     for modType=reshape(mods,1,[])
      for pulse=reshape(pulses,1,[])
       for profileIndex=1:numel(profiles)
        profile=profiles(profileIndex);
        for psd=reshape(noisePSDs,1,[])
         for enabled=eqStates
            p=struct('modType',char(modType),'WaveformMode','ordinaryTM', ...
                'symbolRate',option(opt,'SymbolRateHz',30e6),'sps',8,'channelCoding','convolutional', ...
                'ConvolutionalCodeRate','3/4','ConvolutionalReceiveMode','stream-raw-asm', ...
                'NumBytesInTransferFrame',258,'PulseShapingFilter',char(pulse), ...
                'RolloffFactor',.35,'FilterSpanInSymbols',10,'hasASM',true, ...
                'RandomizerEnabled',false,'PCMFormat','NRZ-L','DataPathMode','single', ...
                'TMDataSource','random','cfo',0,'phaseOffset',0,'delay',0, ...
                'noiseMode','off','noisePlacement','afterChannel','AGCEnabled',false, ...
                'inputLevelDbm',levels,'enableConverterChain',false,'enableADCEquivalent',false, ...
                'randomSeed',seed,'enableReceiverTimeline',true,'enableRuntimeLockTelemetry',true, ...
                'excludeBERWarmUpFrames',true,'captureBaselineData',false,'showFigures',false, ...
                'debugAdaptiveEqualizer',true,'RRatio',2,'ARatio',2,'enableUQPSKFFTCoarseCFO',true);
            if codingProfile=="ldpc-7/8"
                p=rmfield(p,{'ConvolutionalCodeRate','ConvolutionalReceiveMode'});
                p.channelCoding='LDPC'; p.CodeRate='7/8';
                p.NumBitsInInformationBlock=7136;
                p.NumBytesInTransferFrame=7136/8;
                p.IsLDPCOnSMTF=false;
                p.collectPredecoderStats=true; % Offline measurement only, not RX feedback.
                % Ordinary CCSDS LDPC: exact (8160,7136), not 7136/(7/8).
                % The external 32-bit ASM is not LDPC encoded.
                codedFrameBits=8160+32;
            else
                codedFrameBits=(32+8*p.NumBytesInTransferFrame)*(4/3);
            end
            % Continuous 3/4: nominal coded bits per TF may be fractional;
            % NEVER round each frame's puncturing length or reset its phase.
            bps=bitsPerSymbol(modType);
            if isfield(opt,'ModulatorBitRateMbps')
                validateattributes(opt.ModulatorBitRateMbps,{'numeric'},{'scalar','finite','positive'});
                p.modulatorBitRateMbps=opt.ModulatorBitRateMbps;
                p.symbolRate=opt.ModulatorBitRateMbps*1e6/bps;
            end
            frameTime=codedFrameBits/(p.symbolRate*bps);
            p.berWarmUpFrames=ceil(warmTime/frameTime);
            p.berFrames=max(1,ceil(endTime/frameTime)-p.berWarmUpFrames);
            p.enableHChannel=profile~="No-H";
            if p.enableHChannel
                p.HMode='h_matrix_file';
                if fileMode, p.channelFilePath=char(channelPaths(profileIndex));
                else, p.channelFilePath=fullfile(channelDir,char("3GPPNTN-CDL_"+profile+"_AntennaGain_1.mat")); end
                % NaN leaves metadata / historical fallback resolution to
                % the existing loader; no fabricated snapshot resampling.
                p.channelSampleRateHz=option(opt,'ChannelSampleRateHz',1e5);
                p.channelInterpolationMethod='linear';
                p.channelOutOfRangeMode='error'; p.interpolateChannelDelays=true;
                p.normalizeHChannel=logical(option(opt,'NormalizeH',true));
                p.channelPathPowerMode='embedded';
            else
                p.HMode='none';
            end
            if noisy
                p.noiseMode='psd'; p.noisePSDdBmHz=psd;
                % Same integrated bandwidth for RRC and none; do not let
                % pulse-dependent defaults change injected noise power.
                p.noiseBandwidthHz=p.symbolRate*p.sps;
            end
            if contains(modType,'APSK')
                p.APSKReceiverMode='pilotless'; p.HasTMAPSKPilots=false;
            end
            p=configureEQ(p,enabled);
            inputs{end+1,1}=p; labels(end+1,1)=profile; %#ok<AGROW>
         end
        end
       end
      end
     end
    end
end
if option(opt,'BuildOnly',false)
    T=table((1:numel(inputs))',labels,'VariableNames',{'CaseIndex','Channel'});
    save(outputFile,'T','inputs','stage','opt','-v7');
    fprintf('Configuration only, no receiver run: %s\n',outputFile);
    return;
end
n=numel(inputs); rows=cell(n,1); logs=cell(n,1); badFrames=cell(n,1);
diagnostics=cell(n,1);
fprintf('Stage=%s cases=%d; full results: %s\n',stage,n,outputFile);
fprintf('Same seed per case. No TX/H oracle, no bad-frame exclusion. Noise SNR is PRE-filter input SNR.\n');
for k=1:n
    p=inputs{k}; row=emptyRow(k,p,labels(k)); textLog=''; t=tic;
    fprintf('[%d/%d] %s %s %s EQ=%d PSD=%g rate=%g Mbps Rs=%g Msym/s normalizeH=%d\n', ...
        k,n,p.modType,p.PulseShapingFilter,labels(k),p.enableEqualizer,row.NoisePSD_dBmHz, ...
        row.ModulatorBitRate_Mbps,row.SymbolRate_Hz/1e6,row.NormalizeH);
    fprintf('  FEC=%s rate=%s information=%g bit warmup=%d measurement=%d\n', ...
        row.ChannelCoding,row.CodeRate,row.InformationBitsPerTF,p.berWarmUpFrames,p.berFrames);
    try
        rng(p.randomSeed,'twister');
        textLog=evalc('r=run_ccsds_tm_evaluation(p);');
        if ~r.success, error('TMSystem:RunFailed','%s',option(r,'errorMsg',option(r,'error','Unknown receiver failure'))); end
        row.RunCompleted=true; row.BER=r.BER; row.FER=r.FER;
        row.PredecoderBER=option(r,'PredecoderBER',NaN);
        row.PredecoderSteadyBER=option(r,'PredecoderSteadyBER',NaN);
        row.PredecoderASMAligned=double(option(r,'PredecoderASMAligned',NaN));
        row.PredecoderBitsCompared=option(r,'PredecoderBitsCompared',NaN);
        row.ActualSampling=string(r.AdaptiveEqualizerSamplingMode);
        row.ActualEQ=string(r.AdaptiveEqualizerMode);
        row.EQApplied=logical(r.AdaptiveEqualizerEnabled);
        row.EQOutputAccepted=logical(r.AdaptiveEqualizerOutputAccepted);
        row.EQReason=string(r.AdaptiveEqualizerReason);
        row.RouteOK=row.EQApplied==logical(p.enableEqualizer) && ...
            row.ActualSampling==expectedSampling(p.adaptiveEqualizerSamplingMode);
        if contains(p.modType,'APSK')
            row.RouteOK=row.RouteOK && strcmpi(r.APSKReceiverMode,'pilotless') && ~r.HasTMAPSKPilots;
        end
        c=r.MeasurementCoverage;
        row.ComparedFrames=c.ComparedFrames; row.ExpectedFrames=c.ExpectedFrames;
        row.RecoveredNotCompared=c.RecoveredNotComparedFrames;
        row.CoverageComplete=logical(c.Complete);
        row.EquivalentSNR_dB=option(r,'NoiseEquivalentSNR_dB',NaN);
        row.NoiseBandwidthHz=option(r,'NoiseBandwidthHz',NaN);
        row.NoisePower_dBm=option(r,'NoisePower_dBm',NaN);
        row.SymbolRate_Hz=option(r,'SymbolRate_Hz',NaN);
        row.ModulatorBitRate_Mbps=option(r,'ModulatorBitRate_bps',NaN)/1e6;
        row.CarrierLock_pct=100*option(r,'CarrierLockRate',NaN);
        row.FrameLock_pct=100*option(r,'FrameSyncLockRate',NaN);
        row.CarrierReacquisitions=option(r,'CarrierReacquisitions',NaN);
        row.FrameReacquisitions=option(r,'FrameSyncReacquisitions',NaN);
        row.ProjectedUpdates=option(r,'AdaptiveEqualizerProjectedUpdates',NaN);
        row.ActualDuration_s=option(r,'ActualWaveformDuration_s',NaN);
        if ~row.RouteOK
            row.Status="ROUTING_MISMATCH";
        elseif ~row.CoverageComplete || row.RecoveredNotCompared>0
            row.Status="MEASUREMENT_INCOMPLETE";
        elseif row.BER==0 && row.FER==0
            row.Status="ZERO_ERRORS_COMPLETE";
        else
            row.Status="DECODE_ERRORS";
        end
        if isfield(r,'ReceiverTimeline') && r.ReceiverTimeline.Available
            timeline=struct2table(r.ReceiverTimeline.Rows);
            use=timeline.MeasurementEligible & (timeline.ComparedBitsDelta==0 | timeline.ErrorBitsDelta>0);
            names={'TxFrameIndex','TimeStart_s','TimeEnd_s','Coverage','ComparedBitsDelta','ErrorBitsDelta','FrameBER'};
            badFrames{k}=timeline(use,intersect(names,timeline.Properties.VariableNames,'stable'));
            row.ErrorMeasurementFrames=nnz(timeline.MeasurementEligible & timeline.ErrorBitsDelta>0);
            row.UncomparedMeasurementFrames=nnz(timeline.MeasurementEligible & timeline.ComparedBitsDelta==0);
            row.ComparedBits=sum(timeline.ComparedBitsDelta);
            row.ErrorBits=sum(timeline.ErrorBitsDelta);
        end
        diagnostics{k}=compactDiagnostics(r,p);
    catch err
        row.Status="RUN_ERROR"; row.Error=string(err.message);
        fprintf(2,'%s\n',err.message);
    end
    row.Elapsed_s=toc(t); rows{k}=row; logs{k}=textLog;
    T=struct2table(vertcat(rows{1:k}));
    % Compact inputs, logs, bad-frame rows only; never store r / IQ arrays.
    save(outputFile,'T','inputs','logs','badFrames','diagnostics','stage','opt','-v7');
    fprintf('  %s | actual=%s applied=%d accepted=%d | BER=%g FER=%g | coverage=%g/%g | SNR=%g dB | %.1fs\n', ...
        row.Status,row.ActualEQ,row.EQApplied,row.EQOutputAccepted,row.BER,row.FER, ...
        row.ComparedFrames,row.ExpectedFrames,row.EquivalentSNR_dB,row.Elapsed_s);
end
disp(T(:,{'Modulation','Pulse','Channel','EQRequested','ActualSampling','EQApplied', ...
    'RouteOK','NoisePSD_dBmHz','EquivalentSNR_dB','BER','ComparedFrames','ExpectedFrames','Status'}));
fprintf('Saved: %s\n',outputFile);
if stage=="contract", assert(all(T.RouteOK),'Frontend route mismatch; see saved results.'); end
end

function p=configureEQ(p,enabled)
p.enableEqualizer=logical(enabled); p.enableKnownHPreEqualizer=false;
p.equalizerMode='off'; p.adaptiveEqualizerSamplingMode='off'; p.adaptiveFractionalPostMode='off';
p.enableUQPSKPostCarrierAdaptiveEqualizer=false; p.enableQAMPostBPSAdaptiveEqualizer=false;
p.enablePilotlessAPSKPostFrontEndAdaptiveEqualizer=false;
if ~enabled, return; end
p.equalizerMode='blind-cma-lms';
switch upper(string(p.modType))
    case {"BPSK","QPSK","8PSK"}, p.adaptiveEqualizerSamplingMode='2sps';
    case "OQPSK", p.adaptiveEqualizerSamplingMode='oqpsk-staggered';
    otherwise, p.adaptiveEqualizerSamplingMode='1sps';
end
p.enableUQPSKPostCarrierAdaptiveEqualizer=strcmpi(p.modType,'UQPSK');
p.enableQAMPostBPSAdaptiveEqualizer=any(strcmpi(p.modType,{'16QAM','32QAM'}));
p.enablePilotlessAPSKPostFrontEndAdaptiveEqualizer=any(strcmpi(p.modType,{'16APSK','32APSK'}));
end

function mode=expectedSampling(mode)
switch string(mode)
    case "1sps", mode="symbol-spaced-1sps";
    case "2sps", mode="fractionally-spaced-2sps";
    otherwise, mode=string(mode);
end
end

function bps=bitsPerSymbol(modType)
switch string(modType)
    case "BPSK", bps=1;
    case {"QPSK","OQPSK"}, bps=2;
    case "UQPSK", bps=1.5;
    case "8PSK", bps=3;
    case {"16QAM","16APSK"}, bps=4;
    otherwise, bps=5;
end
end

function row=emptyRow(k,p,label)
row=struct('CaseIndex',k,'Modulation',string(p.modType),'Pulse',string(p.PulseShapingFilter), ...
    'Channel',string(label),'Seed',p.randomSeed,'EQRequested',logical(p.enableEqualizer), ...
    'ActualSampling',"",'ActualEQ',"",'EQApplied',false,'EQOutputAccepted',false, ...
    'EQReason',"",'RouteOK',false,'RunCompleted',false,'NoisePSD_dBmHz',option(p,'noisePSDdBmHz',NaN), ...
    'EquivalentSNR_dB',NaN,'NoiseBandwidthHz',NaN,'NoisePower_dBm',NaN,'BER',NaN,'FER',NaN, ...
    'ComparedFrames',0,'ExpectedFrames',p.berFrames,'RecoveredNotCompared',NaN, ...
    'CoverageComplete',false,'CarrierLock_pct',NaN,'FrameLock_pct',NaN, ...
    'CarrierReacquisitions',NaN,'FrameReacquisitions',NaN,'ProjectedUpdates',NaN, ...
    'ActualDuration_s',NaN,'Elapsed_s',NaN,'Status',"NOT_RUN",'Error',"");
row.ModulatorBitRate_Mbps=p.symbolRate*bitsPerSymbol(p.modType)/1e6;
row.SymbolRate_Hz=p.symbolRate;
row.NormalizeH=logical(option(p,'normalizeHChannel',false));
row.ErrorMeasurementFrames=NaN;
row.UncomparedMeasurementFrames=NaN;
row.ComparedBits=NaN;
row.ErrorBits=NaN;
row.ChannelCoding=string(p.channelCoding);
row.CodeRate=string(option(p,'CodeRate',option(p,'ConvolutionalCodeRate','N/A')));
row.InformationBitsPerTF=option(p,'NumBitsInInformationBlock',8*p.NumBytesInTransferFrame);
row.PredecoderBER=NaN;
row.PredecoderSteadyBER=NaN;
row.PredecoderASMAligned=NaN;
row.PredecoderBitsCompared=NaN;
end

function d=compactDiagnostics(r,p)
% Receiver-observable transition times, not inferred from BER or TX truth.
% No IQ arrays. Unknown traces stay unavailable, not "locked".
d=struct('NormalizeH',logical(option(p,'normalizeHChannel',false)), ...
    'MeasurementCoverage',option(r,'MeasurementCoverage',struct()), ...
    'LockEvents',table(),'Locks',struct());
events=struct('Track',{},'LossTime_s',{},'RecoveryTime_s',{},'RecoveryDuration_s',{},'Recovered',{});
telemetry=option(r,'RuntimeLockTelemetry',struct());
for name={'Carrier','Timing','Frame'}
    key=name{1}; tr=option(telemetry,key,struct());
    available=option(tr,'Available',false);
    d.Locks.(key)=struct('Available',available,'Source',option(tr,'Source','unavailable'), ...
        'Reason',option(tr,'Reason',''),'FirstLockTime_s',option(tr,'FirstLockTime_s',NaN), ...
        'LockedAtEnd',NaN,'LossEvents',NaN,'Reacquisitions',NaN);
    if ~available, continue; end
    d.Locks.(key).LockedAtEnd=double(tr.LockedAtEnd);
    d.Locks.(key).LossEvents=tr.LossEvents;
    d.Locks.(key).Reacquisitions=tr.Reacquisitions;
    states=logical(tr.State(:)); times=double(tr.Time_s(:));
    losses=find(diff([false;states])==-1); locks=find(diff([false;states])==1);
    for j=reshape(losses,1,[])
        next=locks(find(locks>j,1));
        recovery=NaN; if ~isempty(next), recovery=times(next); end
        events(end+1)=struct('Track',string(key),'LossTime_s',times(j), ...
            'RecoveryTime_s',recovery,'RecoveryDuration_s',recovery-times(j), ...
            'Recovered',isfinite(recovery)); %#ok<AGROW>
    end
end
if ~isempty(events), d.LockEvents=struct2table(events); end
% Scalar channel metadata only: no per-sample H or noise captures.
meta=option(r,'HChannelMeta',struct());
names={'ChannelSampleRateHz','ChannelSourceDuration_s','PathCount', ...
    'MeanGain_dB','NormalizationGain_dB','DelaySpreadSymbols','FrequencyResponseMin_dB'};
for j=1:numel(names)
    if isfield(meta,names{j}), d.Channel.(names{j})=meta.(names{j}); end
end
end

function v=option(s,name,fallback)
v=fallback;
if isfield(s,name) && ~isempty(s.(name)), v=s.(name); end
end
