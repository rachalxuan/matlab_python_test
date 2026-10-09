function outputDir = debug_apsk_none_stages(inputDir)
% Offline diagnostic only: TX truth NEVER feeds receiver decisions.
% No arguments: capture 16/32APSK, none, seed917, delay0/1 from main chain.
% With inputDir: replay saved *_none_seed917_delay*.mat from pulse regression.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root,'src','python'));
outputDir=tempname(fullfile(root,'tmp')); mkdir(outputDir);
diary(fullfile(outputDir,'console.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('APSK NONE STAGE DEBUG: %s\n',outputDir);
fprintf('Oracle alignment/gain/grid below are OFFLINE diagnostics, not receiver BER.\n');
for modType=["16APSK","32APSK"]
    for delay=[0 1]
        name=sprintf('%s_none_seed917_delay%d',modType,delay);
        if nargin>0 && ~isempty(inputDir)
            s=load(fullfile(inputDir,[name '.mat'])); p=s.p; r=s.r;
            logText=s.logText;
        else
            p=struct('modType',char(modType),'symbolRate',10e6,'sps',8, ...
                'channelCoding','none','NumBytesInTransferFrame',256, ...
                'hasASM',true,'RandomizerEnabled',false,'DataPathMode','single', ...
                'PulseShapingFilter','none','RolloffFactor',0.35, ...
                'noiseMode','off','cfo',0,'phaseOffset',0,'delay',delay, ...
                'berWarmUpFrames',8,'berFrames',120,'excludeBERWarmUpFrames',true, ...
                'enableHChannel',false,'enableEqualizer',false, ...
                'APSKReceiverMode','pilotless','HasTMAPSKPilots',false, ...
                'enableReceiverTimeline',true,'debugSynchronizationChain',true, ...
                'captureBaselineData',true,'showFigures',false,'randomSeed',917);
            rng(917,'twister'); logText=evalc('r=run_ccsds_tm_evaluation(p);');
            save(fullfile(outputDir,[name '_capture.mat']),'p','r','logText','-v7');
        end
        assert(r.success,'%s',r.errorMsg);
        assert(strcmpi(p.PulseShapingFilter,'none') && strcmpi(p.channelCoding,'none'));
        assert(~p.enableHChannel && ~p.enableEqualizer && p.cfo==0 && p.phaseOffset==0);
        c=r.BaselineCapture; sps=p.sps; bitsPerSymbol=log2(str2double(erase(modType,'APSK')));
        symbolsPerFrame=(32+8*p.NumBytesInTransferFrame)/bitsPerSymbol;
        assert(symbolsPerFrame==floor(symbolsPerFrame),'This debug requires whole symbols per uncoded frame.');
        held=reshape(c.TxWaveform,sps,[]);
        assert(all(all(held==held(1,:))),'TX is not an SPS-wide hold.');
        truth=held(1,:).'; constellation=c.ReferenceConstellation(:);
        % Reconstruct only the stateless receive FIR on the SAME saved signal.
        fullMatched=filter(ones(1,sps)/sps,1,c.CoarseSynchronizedWaveform);
        filtered=fullMatched(sps/2:sps/2:end);
        if isfield(c,'PulseStageCapture')
            cfg=c.PulseStageCapture.TimingConfiguration;
            filtered=fullMatched(sps/cfg.SamplesPerSymbol:sps/cfg.SamplesPerSymbol:end);
            assert(isequaln(filtered,c.PulseStageCapture.Filtered), ...
                'Offline reconstruction differs from actual timing input.');
        else
            cfg=struct('SamplesPerSymbol',2,'DetectorGain', ...
                cos(pi*p.RolloffFactor/2)/(pi*(1-p.RolloffFactor^2/4)), ...
                'Modulation','PAM/PSK/QAM','NormalizedLoopBandwidth',0.005, ...
                'ChunkSizeSamples',50000);
            if isfield(p,'timingLoopBandwidth'), cfg.NormalizedLoopBandwidth=p.timingLoopBandwidth; end
        end
        cfg.CollectTimingError=true;
        [replayed,timingInfo]=HelperTMSymbolSynchronizerChunked(filtered,cfg);
        replayIdentical=isequaln(replayed,c.TimeSynchronizedSymbols);
        assert(replayIdentical,'Timing replay differs from saved output; do not interpret this run.');
        [pilotReplay,pilotInfo]=HelperTMAPSKPilotlessFrontEnd(replayed,char(modType),p);
        if isfield(c,'PulseStageCapture') && isfield(c.PulseStageCapture,'PilotlessOutput')
            assert(isequaln(pilotReplay,c.PulseStageCapture.PilotlessOutput), ...
                'Pilotless replay differs from actual captured stage.');
        end
        % Final plotting capture also includes ASM correction, normalization
        % and a global rotation. Compare separately; do not call it raw PLL.
        finalScale=(pilotReplay'*c.FineSynchronizedSymbols)/(pilotReplay'*pilotReplay);
        finalDifference=sqrt(mean(abs(c.FineSynchronizedSymbols-finalScale*pilotReplay).^2));
        fprintf('\n=== %s ===\n',name);
        fprintf('Receiver BER=%g FER=%g coverage=%d/%d | timing replay identical=%d\n', ...
            r.BER,r.FER,r.CountedFrames,p.berFrames,replayIdentical);
        fprintf('Timing gain=%.8g BW=%.8g | input=%d output=%d phaseEstimateRMS=%.6g (not a lock metric)\n', ...
            cfg.DetectorGain,cfg.NormalizedLoopBandwidth,numel(filtered),numel(replayed),timingInfo.TimingErrorRMS);
        fprintf('Pilotless x^M CFO=%+.6g Hz (true=0), order=%g, confidence=%.3g dB; residual=%+.6g Hz\n', ...
            pilotInfo.FourthPowerCFO_Hz,pilotInfo.CoarsePowerOrder, ...
            pilotInfo.FourthPowerConfidence_dB,pilotInfo.FinalResidualFrequency_Hz);
        fprintf('Post-ASM/final vs pilotless, after constant scale: RMS difference=%.6g\n',finalDifference);
        fprintf('Pilotless submodules: preDDGain=%d ringNormalizer=%d mthPhase=%d BPS=%d finalGain=%d\n', ...
            pilotInfo.PreDDGainTrackerApplied,pilotInfo.RingNormalizerApplied, ...
            pilotInfo.MthPowerPhaseTrackerApplied,pilotInfo.BlindPhaseSearchApplied,pilotInfo.ComplexGainEnabled);
        grids=cell(sps,1);
        for phase=1:sps
            grids{phase}=measure(fullMatched(phase:sps:end),truth,constellation,p,symbolsPerFrame, ...
                sprintf('fullRateGrid%d',phase));
        end
        gridSummary=struct2table(vertcat(grids{:}));
        disp(gridSummary(:,{'Stage','Lag','ErrorSymbols','SER','EVM_pct'}));
        beforeGainOptions=p; beforeGainOptions.enablePilotlessAPSKComplexGainTracker=false;
        carrierOnly=HelperTMAPSKPilotlessFrontEnd(replayed,char(modType),beforeGainOptions);
        % These two fixed-grid controls remain the ORIGINAL 2-sps grid,
        % even when production Gardner now receives full-rate input.
        grid2=fullMatched(sps/2:sps/2:end);
        stages={grid2(1:2:end),grid2(2:2:end),replayed,carrierOnly,pilotReplay,c.FineSynchronizedSymbols};
        names={'filteredOdd','filteredEven','postGardner','pilotlessBeforeFinalGain','postPilotless','postASMAndFinal'};
        metrics=cell(6,1); frameRows=cell(6,1); details=cell(6,1);
        for k=1:6
            if k>=4
                % This adapter preserves symbol indexing; never search a new
                % lag on a possibly rotating carrier output.
                [metrics{k},frameRows{k},details{k}]=measure(stages{k},truth,constellation,p,symbolsPerFrame,names{k},metrics{3}.Lag);
            else
                [metrics{k},frameRows{k},details{k}]=measure(stages{k},truth,constellation,p,symbolsPerFrame,names{k});
            end
        end
        StageSummary=struct2table(vertcat(metrics{:})); Frames=vertcat(frameRows{:});
        disp(StageSummary);
        bad=Frames.ErrorSymbols>0 & ismember(Frames.Stage,["postGardner","postPilotless","postASMAndFinal"]);
        fprintf('First 16 bad stage/frame rows (all rows saved in CSV):\n');
        indices=find(bad); disp(Frames(indices(1:min(16,numel(indices))),:));
        if isfield(r,'ReceiverTimeline') && r.ReceiverTimeline.Available
            timeline=struct2table(r.ReceiverTimeline.Rows);
            affected=timeline.MeasurementEligible & ...
                (timeline.ErrorBitsDelta>0 | timeline.ComparedBitsDelta==0);
            fprintf('Actual receiver errors/uncompared frames (first 16):\n');
            ix=find(affected); disp(timeline(ix(1:min(16,numel(ix))), ...
                {'TxFrameIndex','ComparedBitsDelta','ErrorBitsDelta','Coverage'}));
        end
        save(fullfile(outputDir,[name '_debug.mat']),'StageSummary','Frames','details', ...
            'gridSummary','timingInfo','pilotInfo','cfg','replayIdentical','-v7');
        writetable(StageSummary,fullfile(outputDir,[name '_stages.csv']));
        writetable(Frames,fullfile(outputDir,[name '_frames.csv']));
    end
end
fprintf('\nDiagnostic complete (NOT a zero-error acceptance): %s\n',outputDir);
end

function [row,frames,detail]=measure(y,truth,points,p,spf,name,fixedLag)
% Fit ONE lag and ONE constant complex gain on an early measured prefix.
% Never realign per frame: phase slips/timing drift remain visible.
y=y(:); truth=truth(:);
first=p.berWarmUpFrames*spf+1; last=(p.berWarmUpFrames+p.berFrames)*spf;
best=Inf; lagBest=0; gain=1;
lags=-32:32;
if nargin>=7, lags=fixedLag; end
for lag=lags
    ti=(first:min(first+4095,last)).'; yi=ti-lag;
    ok=yi>=1 & yi<=numel(y) & ti<=numel(truth); ti=ti(ok); yi=yi(ok);
    t=truth(ti); v=y(yi); g=(t'*v)/(t'*t);
    cost=mean(abs(v-g*t).^2)/max(mean(abs(v).^2),eps);
    if cost<best
        best=cost; lagBest=lag; gain=g;
        powerGain=sqrt(mean(abs(v).^2)/mean(abs(t).^2));
    end
end
coherence=sqrt(max(0,1-best));
% A rotating/unrelated stream has near-zero correlation: never divide by
% that near-zero LS gain and manufacture huge EVM. Flag calibration invalid.
if coherence<0.9, gain=powerGain*exp(1j*angle(gain)); end
ti=(first:last).'; yi=ti-lagBest;
ok=yi>=1 & yi<=numel(y) & ti>1 & ti<numel(truth); ti=ti(ok); yi=yi(ok);
assert(abs(gain)>eps,'Cannot fit stage gain.');
z=y(yi)/gain; t=truth(ti);
[~,expected]=min(abs(t-points.').^2,[],2);
[~,decided]=min(abs(z-points.').^2,[],2);
wrong=decided~=expected;
relativePhase=angle(z.*conj(t))*180/pi;
% Descriptive 3-tap ISI fit, NOT an equalizer or a correction used for SER.
X=[truth(ti-1),t,truth(ti+1)]; a=X\z;
residual=z-X*a;
row=struct('Stage',string(name),'Lag',lagBest,'Coherence',coherence, ...
    'ConstantGainReliable',coherence>=0.9,'GainAbs',abs(gain), ...
    'GainPhase_deg',angle(gain)*180/pi,'ComparedSymbols',numel(ti), ...
    'ErrorSymbols',nnz(wrong),'SER',mean(wrong), ...
    'EVM_pct',100*sqrt(mean(abs(z-t).^2)/mean(abs(t).^2)), ...
    'PrevMixAbs',abs(a(1)),'MainMixAbs',abs(a(2)),'NextMixAbs',abs(a(3)), ...
    'ThreeTapResidual_pct',100*sqrt(mean(abs(residual).^2)/mean(abs(t).^2)));
frameIndex=ceil(ti/spf); fr=(p.berWarmUpFrames+1:p.berWarmUpFrames+p.berFrames).';
count=zeros(size(fr)); errors=count; evm=nan(size(fr)); phase=evm;
for k=1:numel(fr)
    mask=frameIndex==fr(k); count(k)=nnz(mask); errors(k)=nnz(wrong(mask));
    if count(k)>0
        evm(k)=100*sqrt(mean(abs(z(mask)-t(mask)).^2)/mean(abs(t(mask)).^2));
        phase(k)=angle(sum(z(mask).*conj(t(mask))))*180/pi;
    end
end
frames=table(repmat(string(name),numel(fr),1),fr,count,errors,evm,phase, ...
    'VariableNames',{'Stage','TxFrameIndex','ComparedSymbols','ErrorSymbols','EVM_pct','Phase_deg'});
detail=struct('TruthSymbolIndex',ti,'Wrong',wrong,'ErrorMagnitude',abs(z-t), ...
    'PhaseError_deg',relativePhase,'ThreeTapCoefficients',a, ...
    'Note','Global oracle alignment/gain only; SER includes ASM, excludes warmup and guards. Not receiver payload BER.');
end
