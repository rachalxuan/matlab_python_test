function R = codex_conv_a4_carrier_replay_v1()
% Fixed-input carrier replay and OFFLINE DD angular-margin audit.
% One original Conv/A4 run; three carrier-only replays from symbol one.
% No receiver parameter changes, no alternate FEC runs, no automatic files.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
cacheFile = fullfile(root,'tmp','conv_a4_dual_local_diagnostic_result.mat');
assert(isfile(cacheFile),'Run the original local diagnostic before this audit.');
loaded = load(cacheFile,'D'); D = loaded.D;
old = D.Runs{2}; lag = old.Lag; rate = 30e6;
assert(old.Mode=="2sps-dual" && lag==42, ...
    'This controlled replay expects the existing Conv/A4 dual record.');
region = [14.8 15.3]; % TX time in milliseconds, after the measured 42-symbol lag.
replayEnd = ceil(region(2)*rate/1000)+lag+1;
captureCfg = D.Config;
captureCfg.CarrierReplayEndSymbol = replayEnd;
fprintf('Capture original Conv/A4 once; replay prefix 1:%d (%.3f ms).\n', ...
    replayEnd,replayEnd/rate*1000);
[M,receiverLog,parameters] = localCapture(root,captureCfg);
assert(M.success && isfield(M,'FSEDiagnostics'), ...
    'Original receiver did not return diagnostic capture.');
cap = M.FSEDiagnostics.Stages.CarrierReplay;
assert(numel(cap.Input)==replayEnd,'Replay prefix is incomplete.');
assert(abs(M.BER-old.BER)<1e-14,'Original Conv BER changed; stop comparison.');
% Before studying widths, prove that this is the same FSE waveform as D.
oldInput = old.Captured.Stages.FSEAfterCoarseCFO;
use = oldInput.SymbolIndex<=replayEnd;
inputDifference = max(abs(cap.Input(oldInput.SymbolIndex(use))-oldInput.Samples(use)));
oldOutput = old.Captured.Stages.Carrier;
use = oldOutput.SymbolIndex<=replayEnd;
outputDifference = max(abs(cap.OriginalOutput(oldOutput.SymbolIndex(use))-oldOutput.Samples(use)));
assert(inputDifference<1e-12 && outputDifference<1e-12, ...
    'Saved baseline and new captured samples disagree. Do not interpret replays.');
fprintf('Saved record reproduced: input max diff=%.3g, output=%.3g, BER=%.10g.\n', ...
    inputDifference,outputDifference,M.BER);
indices = (ceil(region(1)*rate/1000)+lag+1:replayEnd).';
timeMs = (indices-1-lag)/rate*1000;
[present,where] = ismember(indices-lag,old.TX.SymbolIndex);
assert(all(present),'Local TX truth is missing from the saved diagnostic.');
truth = old.TX.Symbols(where)*exp(-1j*pi/8); % TX pi/4 -> RX pi/8 convention.
anchor = timeMs>=14.8 & timeMs<14.9;
bandwidths = [0.005 0.0025 0.00125];
R = struct('Parameters',parameters,'InputDifference',inputDifference, ...
    'OriginalOutputDifference',outputDifference,'OriginalBER',M.BER, ...
    'OriginalFER',M.FER,'PrefixSymbols',replayEnd,'SymbolRate',rate, ...
    'LocalSymbolIndex',indices,'Time_ms',timeMs,'Input',cap.Input(indices), ...
    'Truth',truth,'ReceiverLog',receiverLog);
R.Replays = cell(3,1); summaryRows = cell(3,1); allWindows = cell(3,1);
for replayIndex=1:numel(bandwidths)
    bw = bandwidths(replayIndex);
    sync = comm.CarrierSynchronizer('Modulation',cap.Modulation, ...
        'SamplesPerSymbol',cap.SamplesPerSymbol,'DampingFactor',cap.DampingFactor, ...
        'ModulationPhaseOffset',cap.ModulationPhaseOffset, ...
        'NormalizedLoopBandwidth',bw);
    if strcmpi(cap.ModulationPhaseOffset,'Custom')
        sync.CustomPhaseOffset = cap.CustomPhaseOffset;
    end
    [output,phEst] = sync(cap.Input); % ALWAYS starts at the first input symbol.
    if replayIndex==1
        R.BaselineReplayOutputMaxDifference = max(abs(output-cap.OriginalOutput));
        R.BaselineReplayPhaseMaxDifference = max(abs(phEst-cap.OriginalPhaseEstimate));
        assert(R.BaselineReplayOutputMaxDifference<1e-12 && ...
            R.BaselineReplayPhaseMaxDifference<1e-12, ...
            'BW=0.005 did not reproduce the original PLL history.');
    end
    localOutput = output(indices);
    anchorPhase = angle(sum(localOutput(anchor).*conj(truth(anchor))));
    rotation = round(anchorPhase/(pi/4))*pi/4;
    aligned = localOutput*exp(-1j*rotation); % ONE fixed pre-event branch only.
    symbolErrors = localDecisions(aligned)~=localDecisions(truth);
    bits = localBits(aligned); truthBits = localBits(truth);
    bitErrors = bits~=truthBits;
    correction = unwrap(angle(localOutput.*conj(cap.Input(indices))));
    correction = (correction-mean(correction(anchor)))*180/pi;
    W = localPhaseWindows(bw,indices,aligned,truth,lag,rate);
    branch = W.Branch_deg;
    branchRun = 0; firstSlip = NaN; slipBranch = NaN;
    for windowIndex=1:height(W)
        if branch(windowIndex)~=0 && isfinite(branch(windowIndex))
            if windowIndex>1 && branch(windowIndex)==branch(windowIndex-1)
                branchRun = branchRun+1;
            else
                branchRun = 1;
            end
            if branchRun>=3
                firstSlip = W.Start_ms(windowIndex-2);
                slipBranch = branch(windowIndex);
                break;
            end
        else
            branchRun = 0;
        end
    end
    onset = timeMs>=14.95 & timeMs<15.04;
    late = timeMs>=15.12 & timeMs<=15.3;
    summaryRows{replayIndex} = table(bw,rotation*180/pi, ...
        mean(symbolErrors),mean(bitErrors),mean(symbolErrors(anchor)), ...
        mean(symbolErrors(onset)),mean(symbolErrors(late)), ...
        localMaxRun(symbolErrors),localMaxRun(bitErrors), ...
        isfinite(firstSlip),firstSlip,slipBranch, ...
        'VariableNames',{'Bandwidth','AnchorRotation_deg','LocalSER','LocalBER', ...
        'BeforeEventSER','EventSER','AfterEventSER','MaxErrorSymbolRun', ...
        'MaxErrorBitRun','SustainedBranchChange','FirstBranchWindow_ms','Branch_deg'});
    R.Replays{replayIndex} = struct('Bandwidth',bw,'Output',localOutput, ...
        'PhaseEstimate_rad',phEst(indices),'CorrectionChange_deg',correction, ...
        'SymbolErrors',symbolErrors,'BitErrors',bitErrors,'Windows',W);
    allWindows{replayIndex} = W;
end
R.Summary = vertcat(summaryRows{:}); R.PhaseWindows = vertcat(allWindows{:});
[R.GateAudit,R.GateDistributions,R.GateWindowBranches,R.GateSamples] = localGateAudit(D);
R.Meaning = ['All three carrier replays use identical post-CFO FSE input and ', ...
    'independent history from symbol one. Local BER is hard coded-bit BER BEFORE ', ...
    'ASM and FEC, NOT final payload BER. A single pre-event phase branch is removed. ', ...
    'Branch event means three 256-symbol windows in the same nonzero branch; ', ...
    'the window start is approximate, not exact PLL loss-of-lock time. Gate ', ...
    'labels are offline only; no threshold is fed back into the receiver.'];
fprintf('\n=== FIXED INPUT: CARRIER-ONLY REPLAY ===\n'); disp(R.Summary);
fprintf('Baseline replay max differences: samples %.3g; native phEst %.3g.\n', ...
    R.BaselineReplayOutputMaxDifference,R.BaselineReplayPhaseMaxDifference);
fprintf('\n=== OFFLINE ANGULAR-MARGIN AUDIT ===\n'); disp(R.GateDistributions);
disp(R.GateAudit(ismember(R.GateAudit.MinimumMargin_deg,[0 5 10 15 20]),:));
fprintf('%s\nNo receiver defaults changed. No files written by this function.\n',R.Meaning);
end

function [M,receiverLog,parameters] = localCapture(root,captureCfg)
% Run the same original case, not a new scout or an entire coding sweep.
NewChannelPSDSweepOptions = struct( ...
    'StartFile',4,'MaxFiles',1,'ModType','8PSK', ...
    'ChannelCoding','convolutional','NumBytesInTransferFrame',1115, ...
    'SymbolRate',30e6,'SamplesPerSymbol',8, ...
    'BERWarmUpFrames',30,'BERFrames',120,'Seed',364232726, ...
    'NoiseMode','off','NormalizeHChannel',true,'VerboseReceiverLog',false, ...
    'SaveCSV',false,'ReceiverOverrides',struct( ...
    'ConvolutionalCodeRate','1/2','channelPathPowerMode','embedded', ...
    'adaptiveEqualizerSamplingMode','2sps-dual', ...
    'adaptiveFractionalEqualizerTaps',129, ...
    'adaptiveFractionalEqualizerStep',2e-4, ...
    'adaptiveFractionalEqualizerWeightUpdatePeriod',1, ...
    'adaptiveFractionalPostMode','off','PSKPostFSEPhaseTrackerMode','off', ...
    'collectPredecoderStats',true,'debugPredecoderBurst',true, ...
    'debugPredecoderMaxBurstFrames',3,'FSEDiagnostics',captureCfg)); %#ok<NASGU>
sweepPath = fullfile(root,'tmp','codex_new_channel_psd_sync_sweep_v1.m'); %#ok<NASGU>
receiverLog = evalc('run(sweepPath);');
M = result; parameters = p;
end

function W = localPhaseWindows(bw,indices,output,truth,lag,rate)
rows = cell(0,1);
for start=indices(1):256:indices(end)-255
    take=indices>=start & indices<start+256;
    z=output(take); target=truth(take);
    gain=mean(z.*conj(target));
    phase=angle(gain)*180/pi;
    branch=mod(round(phase/45)+4,8)*45-180;
    if abs(gain)<0.2, branch=NaN; end
    rows{end+1,1}=table(bw,start,(start-1-lag)/rate*1000,phase,branch, ...
        mean(localDecisions(z)~=localDecisions(target)),abs(gain), ...
        'VariableNames',{'Bandwidth','SymbolStart','Start_ms','TruthRelativePhase_deg', ...
        'Branch_deg','FixedBranchSER','CoherentMagnitude'}); %#ok<AGROW>
end
W=vertcat(rows{:});
end

function d = localDecisions(x)
d=mod(round((angle(x)-pi/8)/(pi/4)),8);
end

function b = localBits(x)
demod=comm.PSKDemodulator(8,pi/8,'SymbolMapping','Custom', ...
    'CustomSymbolMapping',[0 4 6 2 3 7 5 1],'BitOutput',true);
b=demod(x);
end

function count = localMaxRun(errors)
edges=diff([false;errors(:);false]);
count=max([0;find(edges==-1)-find(edges==1)]);
end

function [T,Q,B,S] = localGateAudit(D)
runData=D.Runs{2}; s=runData.Captured.Dual.Samples; lag=runData.Lag;
idx=s.SymbolIndex;
[known,position]=ismember(idx-lag,runData.TX.SymbolIndex);
valid=known & isfinite(s.Decision) & isfinite(s.CorrectedForDecision);
idx=idx(valid); position=position(valid);
decision=s.Decision(valid); z=s.CorrectedForDecision(valid);
original=s.UpdateApplied(valid);
truth=runData.TX.Symbols(position)*exp(-1j*pi/8);
margin=22.5-abs(angle(z.*conj(decision)))*180/pi;
time=(idx-1-lag)/30e3;
before=time>=14.8 & time<14.9;
fixedRotation=localBestRotation(decision(before),truth(before));
fixedWrong=abs(decision*exp(-1j*fixedRotation)-truth)>1e-6;
% Label shape errors using ONE rotation per 256-symbol window, chosen using
% ALL decisions, never re-fit the rotation for each candidate gate threshold.
localWrong=false(size(idx)); branches=cell(0,1);
bins=unique(floor((idx-1)/256));
for bi=1:numel(bins)
    take=floor((idx-1)/256)==bins(bi);
    rotation=localBestRotation(decision(take),truth(take));
    localWrong(take)=abs(decision(take)*exp(-1j*rotation)-truth(take))>1e-6;
    branches{end+1,1}=table(min(idx(take)),mean(time(take)),rotation*180/pi, ...
        mean(localWrong(take)),mean(fixedWrong(take)), ...
        'VariableNames',{'SymbolStart','Midpoint_ms','BestBranch_deg', ...
        'ModuloBranchError','FixedBranchError'}); %#ok<AGROW>
end
B=vertcat(branches{:});
fine=D.FineWindows(D.FineWindows.Mode=="2sps-dual",:);
[~,worst]=min(abs(fine.Time_ms-14.966));
badStart=fine.SymbolStart(worst); badEnd=fine.SymbolEnd(worst);
regions={time>=14.8 & time<14.9,idx>=badStart & idx<=badEnd, ...
    time>=14.95 & time<15.04,time>=15.12 & time<=15.3};
labels=["before-event","bad-256-symbols","event-wide","later-window"];
rows=cell(0,1); distributions=cell(0,1);
for ri=1:numel(regions)
    take=regions{ri}; base=take & original;
    good=base & ~localWrong; bad=base & localWrong;
    distributions{end+1,1}=table(labels(ri),nnz(base), ...
        100*mean(localWrong(base)),localAUC(margin(base),~localWrong(base)), ...
        localQuantile(margin(good),0.1),localQuantile(margin(good),0.5), ...
        localQuantile(margin(good),0.9),localQuantile(margin(bad),0.1), ...
        localQuantile(margin(bad),0.5),localQuantile(margin(bad),0.9), ...
        'VariableNames',{'Region','OriginalUpdates','OriginalWrong_pct','MarginAUC', ...
        'CorrectP10_deg','CorrectP50_deg','CorrectP90_deg', ...
        'WrongP10_deg','WrongP50_deg','WrongP90_deg'}); %#ok<AGROW>
    for threshold=0:2.5:20
        keep=base & margin>=threshold;
        rows{end+1,1}=table(labels(ri),threshold,nnz(keep), ...
            100*nnz(keep)/max(1,nnz(take)),100*mean(localWrong(keep)), ...
            100*mean(fixedWrong(keep)),100*nnz(keep & ~localWrong)/max(1,nnz(good)), ...
            100*nnz(keep & localWrong)/max(1,nnz(bad)), ...
            'VariableNames',{'Region','MinimumMargin_deg','KeptUpdates', ...
            'Update_pct','FalseAcceptedModulo_pct','FalseAcceptedFixed_pct', ...
            'CorrectUpdateRetention_pct','WrongUpdateRetention_pct'}); %#ok<AGROW>
    end
end
T=vertcat(rows{:}); Q=vertcat(distributions{:});
S=table(idx,time,margin,original,fixedWrong,localWrong, ...
    'VariableNames',{'SymbolIndex','Time_ms','AngularMargin_deg','OriginalUpdate', ...
    'WrongFixedBranch','WrongModulo256'});
end

function rotation = localBestRotation(decision,truth)
errors=zeros(8,1);
for ri=0:7
    errors(ri+1)=mean(abs(decision*exp(-1j*ri*pi/4)-truth)>1e-6);
end
[~,best]=min(errors); rotation=(best-1)*pi/4;
end

function q = localQuantile(x,p)
if isempty(x), q=NaN; else, q=quantile(x,p); end
end

function auc = localAUC(score,correct)
positive=nnz(correct); negative=nnz(~correct);
if positive==0 || negative==0, auc=NaN; return; end
[~,~,groups]=unique(score);
counts=accumarray(groups,1);
meanRank=cumsum(counts)-(counts-1)/2;
auc=(sum(meanRank(groups(correct)))-positive*(positive+1)/2)/(positive*negative);
end
