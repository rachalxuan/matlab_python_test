function D=codex_ldpc_a4_boundary_diagnostic_v1(cached)
% Read-only no-H/A4 controls for the reported LDPC K=1024 failure.
rootDiagnostic=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(rootDiagnostic,'src','python'));
if nargin>0
    D=localSoftInputAudit(cached);
    if isfield(D,'Prefix'), D=localPrefixAudit(D); end
    return;
end
NewChannelFECRepresentativeOptions=struct( ...
    'StartFEC',5,'MaxFEC',1,'StartFile',4,'MaxFiles',1, ...
    'ModType','8PSK','SymbolRate',30e6,'SamplesPerSymbol',8, ...
    'BERWarmUpFrames',100,'BERFrames',120,'NoiseMode','off', ...
    'NormalizeHChannel',true,'VerboseReceiverLog',false,'SaveCSV',false, ...
    'ReceiverOverrides',struct('cfo',0, ...
    'enablePSKCoarseFrequencyCompensator',true,'carrierCaptureRangeHz',2e6, ...
    'carrierLoopBandwidth',0.0025,'adaptiveEqualizerSamplingMode','2sps-dual', ...
    'adaptiveFractionalEqualizerTaps',129,'PSKPostFSEPhaseTrackerMode','off', ...
    'collectPredecoderStats',true,'debugCodedBoundary',true, ...
    'debugLDPC',true,'debugASMPhase',true,'debugFrameCheckCount',5, ...
    'FSEDiagnostics',struct('SymbolRange',[80000 120000], ...
        'AnchorRange',[60000 64095],'SwitchRange',[1 12000]))); %#ok<NASGU>
fprintf('LDPC A4, exact reported configuration, with bounded stage captures.\n');
NewChannelPSDSweepLogs=cell(0,1);
logA4=evalc('run(fullfile(rootDiagnostic,''tmp'',''codex_new_channel_psd_fec_representative_sweep_v1.m''));');
D=struct('A4',result,'Parameters',p,'A4Log',NewChannelPSDSweepLogs{1}, ...
    'SweepLog',logA4, ...
    'TXEncodedBits',evalin('base','debugTMEncodedBits'));
D.Prefix=result.FSEDiagnostics.Stages.AfterASM;
q=p; q.enableHChannel=false;
fprintf('LDPC no-H control, all other settings unchanged.\n');
rng(364232726,'twister');
logNoH=evalc('[noH,~]=run_ccsds_tm_evaluation(q);');
D.NoH=noH; D.NoHLog=logNoH;
% This is a decoder-only construction test, not a channel-performance test.
[H,meta]=buildTMLDPC_H_standard(1024,2);
Gc=satcom.internal.ccsds.getTMLDPCGeneratorMatrix(1024,2);
rng(364232726,'twister');
infoBits=randi([0 1],1024,1,'int8');
cw=satcom.internal.ccsds.tmldpcEncode(infoBits,Gc);
llr=[20*(1-2*double(cw));zeros(meta.PuncturedLength,1)];
[decoded,iterations,parity]=ldpcDecode(llr,ldpcDecoderConfig(H),20);
D.DecoderOnlyErrors=nnz(double(decoded)~=double(infoBits));
D.DecoderOnlyIterations=iterations; D.DecoderOnlyParityErrors=nnz(parity);
fprintf('Decoder-only: errors=%d iterations=%d parityErrors=%d\n', ...
    D.DecoderOnlyErrors,iterations,D.DecoderOnlyParityErrors);
for label=["NoH","A4"]
    r=D.(label);
    fprintf('%s: BER=%g preBER=%g preASM=%d\n', ...
        label,r.BER,r.PredecoderSteadyBER,r.PredecoderASMAligned);
    if isfield(r,'MeasurementCoverage'), disp(r.MeasurementCoverage); end
    if isfield(r,'FrameAssociation'), disp(r.FrameAssociation.Reason); end
end
fprintf('No production receiver files or parameters changed.\n');
D=localSoftInputAudit(D);
D=localPrefixAudit(D);
end

function D=localSoftInputAudit(D)
% Offline boundary oracle ONLY: check the same captured symbols with the
% existing LDPC kernel. No result is fed into acquisition or adaptation.
cap=D.A4.FSEDiagnostics.Stages.BeforeASM;
use=cap.SymbolIndex>=80000 & cap.SymbolIndex<=120000;
idx=cap.SymbolIndex(use); y=cap.Samples(use)*1j;
assert(all(diff(idx)==1),'Capture must be contiguous.');
modulator=comm.PSKModulator(8,pi/8,'BitInput',true, ...
    'SymbolMapping','Custom','CustomSymbolMapping',[0 4 6 2 3 7 5 1]);
tx=modulator(double(D.TXEncodedBits));
lags=(-256:256).'; scores=zeros(size(lags));
for i=1:numel(lags)
    scores(i)=abs(sum(y.*conj(tx(idx-lags(i)))));
end
[~,j]=max(scores); lag=lags(j);
demod=HelperCCSDSTMDemodulator('Modulation','8PSK','ChannelCoding','LDPC', ...
    'NoiseVariance',1); % Freeze the historical default for this audit.
soft=demod(y);
firstTXBit=(idx(1)-lag-1)*3+1;
lastTXBit=firstTXBit+numel(soft)-1;
firstFrame=ceil((firstTXBit-1)/2112)+1;
lastFrame=floor(lastTXBit/2112);
frames=firstFrame:lastFrame;
[H,meta]=buildTMLDPC_H_standard(1024,2);
cfg=ldpcDecoderConfig(H);
scales=[1 4 16]; rows=cell(0,1);
for scale=scales
    errors=0; bad=0; raw=0; syndromeBad=0; iterationSum=0;
    for f=frames
        start=(f-1)*2112+65;
        loc=start-firstTXBit+1;
        cw=D.TXEncodedBits(start:start+2047);
        llr=-double(soft(loc:loc+2047));
        raw=raw+nnz((llr<0)~=cw);
        [out,it,parity]=ldpcDecode([scale*llr;zeros(meta.PuncturedLength,1)],cfg,20);
        e=nnz(out~=cw(1:1024));
        errors=errors+e; bad=bad+(e>0);
        syndromeBad=syndromeBad+any(parity);
        iterationSum=iterationSum+it;
    end
    rows{end+1,1}=table(scale,numel(frames),raw/(numel(frames)*2048), ...
        errors/(numel(frames)*1024),errors,bad,syndromeBad, ...
        iterationSum/numel(frames),'VariableNames', ...
        {'LLRScale','Frames','RawCodewordBER','DecodedBER','ErrorBits', ...
        'ErrorFrames','NonzeroSyndromeFrames','MeanIterations'}); %#ok<AGROW>
end
D.OfflineSoftAudit=vertcat(rows{:});
D.OfflineSoftAuditLag=lag; D.OfflineSoftAuditFrames=frames;
fprintf('Captured A4 symbols: +90 deg from ASM evidence, offline true-boundary audit.\n');
fprintf('TX frames=%d:%d, lag=%d, no receiver feedback.\n',firstFrame,lastFrame,lag);
disp(D.OfflineSoftAudit);
end

function D=localPrefixAudit(D)
% Undo the saved final fallback rotation (-90 deg), retaining the upstream
% ASM correction exactly as applied in the original run, including prefix.
s=D.Prefix;
x=s.Samples(s.SymbolIndex<=12000)*1j;
dm=HelperCCSDSTMDemodulator('Modulation','8PSK','ChannelCoding','LDPC', ...
    'NoiseVariance',1); % Freeze the historical default for this audit.
soft=dm(x);
asm=double(D.TXEncodedBits(1:64));
best=[Inf NaN NaN Inf];
for polarity=[1 -1]
    bits=double(polarity*soft>0);
    for pos=1:2112
        indices=pos+(0:7)*2112;
        errors=sum(reshape(bits(reshape(indices+(0:63).',[],1)),64,[])~=asm,1);
        if mean(errors)<best(1) || ...
                (mean(errors)==best(1) && errors(1)<best(4))
            best=[mean(errors) pos polarity errors(1)];
        end
    end
end
decoder=HelperCCSDSTMDecoder('ChannelCoding','LDPC','Modulation','8PSK', ...
    'NumBitsInInformationBlock',1024,'CodeRate','1/2','IsLDPCOnSMTF',false, ...
    'HasASM',true,'RandomizerEnabled',false,'DisablePhaseAmbiguityResolution',true);
out=decoder(soft); positions=decoder.getDecodedFramePositions();
D.PrefixBoundaryAudit=struct('MeanASMErrors',best(1), ...
    'SelectedStartBit',best(2),'SelectedPolarity',best(3), ...
    'ExpectedStartBit',127,'ActualDecoderStartBit',positions.InputStartBit(1), ...
    'DecodedFrames',numel(out)/1024);
assert(positions.InputStartBit(1)==best(2),'Offline search differs from real decoder.');
disp(D.PrefixBoundaryAudit);
end
