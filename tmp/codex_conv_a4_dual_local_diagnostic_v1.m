function D = codex_conv_a4_dual_local_diagnostic_v1(cached)
% Conv/A4 only. One scout locates the bad frame, then two identical-record
% receiver runs capture bounded diagnostics. No adaptation parameters change.
% TX symbols are reconstructed and compared only AFTER each receiver returns.
% Pass an existing D to refine its bounded captures without any new RX run.
if nargin>0
    D = localFineReport(cached);
    return;
end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
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
    'adaptiveFractionalPostMode','off', ...
    'PSKPostFSEPhaseTrackerMode','off','collectPredecoderStats',true, ...
    'debugPredecoderBurst',true,'debugPredecoderMaxBurstFrames',3)); %#ok<NASGU>
fprintf('Conv A4: scout dual, 30 warm-up + 120 BER frames (no TPC sweep).\n');
scoutLog = evalc('run(fullfile(root,''tmp'',''codex_new_channel_psd_sync_sweep_v1.m''));'); %#ok<NASGU>
assert(result.success,'Conv diagnostic scout did not complete successfully.');
scout = result;
baseParameters = p; % The sweep leaves its actual receiver input in p.
frameSymbols = scout.PredecoderCodedBitsPerFrame/3;
txFrame = scout.PredecoderTxFrameOffset+scout.PredecoderWorstFrameIndex;
firstSymbol = floor((txFrame-1)*frameSymbols)+1;
cfg = struct('SymbolRange', ...
    [max(1,floor(firstSymbol-2*frameSymbols)-256), ...
    ceil(firstSymbol+3*frameSymbols)+256], 'AnchorRange',[50000 54095], ...
    'SwitchRange',[30977 35072]);
D = struct('Config',cfg,'ScoutWorstRxFrame',scout.PredecoderWorstFrameIndex, ...
    'ScoutWorstTxFrame',txFrame,'CodedSymbolsPerFrame',frameSymbols, ...
    'ScoutBER',scout.BER,'ScoutWorstPredecoderBER',scout.PredecoderFrameBERMax);
fprintf('Scout: BER=%.9g, worst RX frame=%d TX frame=%d pre-BER=%.9g.\n', ...
    D.ScoutBER,D.ScoutWorstRxFrame,txFrame,D.ScoutWorstPredecoderBER);
fprintf('Capture symbol range %d:%d, fixed alignment probe %d:%d.\n', ...
    cfg.SymbolRange,cfg.AnchorRange);
modeNames = ["2sps","2sps-dual"];
D.Runs = cell(2,1);
for diagnosticModeIndex = 1:2
    q = baseParameters;
    q.adaptiveEqualizerSamplingMode = char(modeNames(diagnosticModeIndex));
    q.FSEDiagnostics = cfg;
    rng(364232726,'twister');
    receiverLog = evalc('[M,~] = run_ccsds_tm_evaluation(q);');
    assert(M.success && isfield(M,'FSEDiagnostics'), ...
        'The receiver did not return the bounded diagnostics.');
    txBits = evalin('base','debugTMEncodedBits');
    modulator = comm.PSKModulator(8,pi/4,'SymbolMapping','Custom', ...
        'BitInput',true,'CustomSymbolMapping',[0 4 6 2 3 7 5 1]);
    txSymbols = modulator(double(txBits(1:3*floor(numel(txBits)/3))));
    observed = M.FSEDiagnostics;
    lag = localFindLag(observed.Stages.FSEAfterCoarseCFO,txSymbols,cfg);
    reference = exp(1j*(pi/4+(0:7).'*pi/4));
    % TX uses pi/4, while the actual helper and post-carrier demapper use
    % pi/8. This is a known coordinate convention, not a fitted slip repair.
    receiverReference = reference*exp(-1j*pi/8);
    receiverTruth = txSymbols*exp(-1j*pi/8);
    stageNames = {'FSEAfterCoarseCFO','Carrier','BeforeASM','AfterASM'};
    tables = cell(numel(stageNames),1);
    for stageIndex = 1:numel(stageNames)
        stageName = stageNames{stageIndex};
        if strcmp(stageName,'FSEAfterCoarseCFO')
            stageTruth = txSymbols;
            stageReference = reference;
        else
            stageTruth = receiverTruth;
            stageReference = receiverReference;
        end
        tables{stageIndex} = localScoreStage(observed.Stages.(stageName), ...
            stageTruth,stageReference,lag,cfg,stageName);
    end
    windowResults = vertcat(tables{:});
    runResult = struct('Mode',modeNames(diagnosticModeIndex), ...
        'BER',M.BER,'FER',M.FER, ...
        'PredecoderBER',M.PredecoderSteadyBER, ...
        'WorstPredecoderBER',M.PredecoderFrameBERMax, ...
        'Lag',lag,'Windows',windowResults,'Captured',observed,'Log',receiverLog);
    if isfield(observed,'Dual')
        internal = observed.Dual.Samples;
        decisionWindows = localScoreStage(struct( ...
            'SymbolIndex',internal.SymbolIndex, ...
            'Samples',internal.CorrectedForDecision), ...
            receiverTruth,receiverReference,lag,cfg,'DDInternal');
        internal.DecisionRotation = localAnchorRotation( ...
            internal.Decision,internal.SymbolIndex,receiverTruth,lag,cfg);
        trace = observed.Dual.Trace;
        trace.CapturedDecisions = zeros(height(trace),1);
        trace.TrueDecisionErrorPct = NaN(height(trace),1);
        trace.FalseAcceptedDecisionPct = NaN(height(trace),1);
        trace.FalseAcceptedModuloBranchPct = NaN(height(trace),1);
        maxIdentityResidual = 0;
        for wi = 1:height(trace)
            selected = internal.SymbolIndex>=trace.SymbolStart(wi) & ...
                internal.SymbolIndex<=trace.SymbolEnd(wi) & ...
                isfinite(internal.Decision) & internal.SymbolIndex-lag>=1 & ...
                internal.SymbolIndex-lag<=numel(txSymbols);
            if ~any(selected), continue; end
            truth = receiverTruth(internal.SymbolIndex(selected)-lag);
            decisions = internal.Decision(selected);
            errors = abs(decisions*exp(-1j*internal.DecisionRotation)-truth)>1e-6;
            acceptedUpdates = internal.UpdateApplied(selected);
            trace.CapturedDecisions(wi) = nnz(selected);
            trace.TrueDecisionErrorPct(wi) = 100*mean(errors);
            if any(acceptedUpdates)
                trace.FalseAcceptedDecisionPct(wi) = 100*mean(errors(acceptedUpdates));
                rotationErrors = zeros(8,1);
                for ri = 0:7
                    rotationErrors(ri+1) = mean(abs( ...
                        decisions(acceptedUpdates)*exp(-1j*ri*pi/4)- ...
                        truth(acceptedUpdates))>1e-6);
                end
                trace.FalseAcceptedModuloBranchPct(wi) = 100*min(rotationErrors);
            end
            identity = internal.FeedbackIdentityResidual(selected);
            maxIdentityResidual = max(maxIdentityResidual,max(identity,[],'omitnan'));
        end
        runResult.DecisionWindows = decisionWindows;
        runResult.DualTrace = trace;
        runResult.FeedbackIdentityMaxResidual = maxIdentityResidual;
        fprintf('Same-symbol NLMS identity max residual: %.3g\n',maxIdentityResidual);
    end
    % Compare the ACTUAL demapper hard bits with the captured post-ASM
    % nearest decisions (same custom mapping), not a re-aligned BER proxy.
    if isfield(observed,'Demapper')
        post = observed.Stages.AfterASM;
        hardDemod = comm.PSKDemodulator(8,pi/8,'SymbolMapping','Custom', ...
            'CustomSymbolMapping',[0 4 6 2 3 7 5 1],'BitOutput',true);
        expectedBits = hardDemod(post.Samples);
        expectedIndices = reshape((post.SymbolIndex.'-1)*3+(1:3).',[],1);
        [~,ia,ib] = intersect(expectedIndices,observed.Demapper.BitIndex);
        runResult.DemapperDisagreementBits = nnz( ...
            expectedBits(ia)~=observed.Demapper.HardBits(ib));
        runResult.DemapperComparedBits = numel(ia);
        assert(runResult.DemapperDisagreementBits==0, ...
            'Diagnostic demapper does not match the actual receiver. Do not interpret stage BER.');
    end
    txIndex = unique([observed.Stages.AfterASM.SymbolIndex-lag; ...
        observed.Stages.FSEAfterCoarseCFO.SymbolIndex-lag]);
    txIndex = txIndex(txIndex>=1 & txIndex<=numel(txSymbols));
    runResult.TX = struct('SymbolIndex',txIndex,'Symbols',txSymbols(txIndex), ...
        'Meaning','Offline instrumentation only; never fed into receiver adaptation.');
    D.Runs{diagnosticModeIndex} = runResult;
    fprintf('\n%s: BER=%.9g FER=%.9g pre-BER=%.9g max=%.9g lag=%d symbols\n', ...
        runResult.Mode,runResult.BER,runResult.FER,runResult.PredecoderBER, ...
        runResult.WorstPredecoderBER,lag);
    inBadFrame = windowResults.SymbolEnd>=firstSymbol & ...
        windowResults.SymbolStart<=firstSymbol+frameSymbols;
    disp(windowResults(inBadFrame,:));
    if isfield(runResult,'DualTrace')
        trace = runResult.DualTrace;
        selected = trace.SymbolEnd>=firstSymbol & ...
            trace.SymbolStart<=firstSymbol+frameSymbols;
        disp(trace(selected,:));
    end
    if isfield(runResult,'DemapperDisagreementBits')
        fprintf('Actual demapper vs post-ASM hard slicing: %d/%d bit disagreements.\n', ...
            runResult.DemapperDisagreementBits,runResult.DemapperComparedBits);
    end
end
assert(abs(D.Runs{2}.BER-D.ScoutBER)<1e-14, ...
    'Diagnostics changed the dual receiver BER. Inspect instrumentation before interpretation.');
fprintf('\nDiagnostics-on dual reproduces scout BER exactly. No files written by this function.\n');
D = localFineReport(D);
end

function lag = localFindLag(capture,tx,cfg)
selected = capture.SymbolIndex>=cfg.AnchorRange(1) & ...
    capture.SymbolIndex<=cfg.AnchorRange(2);
indices = capture.SymbolIndex(selected);
x = capture.Samples(selected);
assert(numel(x)>=1024,'Insufficient fixed alignment probe.');
lags = (-256:256).';
scores = zeros(size(lags));
for li=1:numel(lags)
    ti=indices-lags(li);
    ok=ti>=1 & ti<=numel(tx);
    scores(li)=abs(sum(x(ok).*conj(tx(ti(ok)))))/ ...
        sqrt(sum(abs(x(ok)).^2)*nnz(ok));
end
[best,index]=max(scores);
ordered=sort(scores,'descend');
assert(best>0.2 && best>1.3*ordered(2), ...
    'TX/RX alignment is ambiguous; do not interpret true-decision metrics.');
lag=lags(index);
fprintf('Alignment: RX index = TX index + %d; correlation %.4f, runner-up %.4f.\n', ...
    lag,best,ordered(2));
end

function rotation = localAnchorRotation(x,indices,tx,lag,cfg)
selected=indices>=cfg.AnchorRange(1) & indices<=cfg.AnchorRange(2) & ...
    indices-lag>=1 & indices-lag<=numel(tx) & isfinite(x);
phase=angle(sum(x(selected).*conj(tx(indices(selected)-lag))));
rotation=round(phase/(pi/4))*pi/4;
end

function T = localScoreStage(capture,tx,reference,lag,cfg,name)
indices=capture.SymbolIndex;
x=capture.Samples;
anchorRotation=localAnchorRotation(x,indices,tx,lag,cfg);
bins=unique(floor((indices-1)/2048));
out=cell(numel(bins),1);
for bi=1:numel(bins)
    start=bins(bi)*2048+1; stop=start+2047;
    selected=indices>=start & indices<=stop & indices-lag>=1 & ...
        indices-lag<=numel(tx) & isfinite(x);
    if nnz(selected)<128, continue; end
    idx=indices(selected); z=x(selected); truth=tx(idx-lag);
    [~,nearest]=min(abs(z-reference.'),[],2);
    decisions=reference(nearest);
    fixedSER=mean(abs(decisions*exp(-1j*anchorRotation)-truth)>1e-6);
    localRotationSER=zeros(8,1);
    for ri=0:7
        localRotationSER(ri+1)=mean(abs(decisions*exp(-1j*ri*pi/4)-truth)>1e-6);
    end
    [moduloSER,ri]=min(localRotationSER);
    % Data-aided scalar fit is a DIAGNOSTIC shape metric only. Always retain
    % fixed-branch SER and phase alongside it so a slip cannot be hidden.
    gain=sum(z.*conj(truth))/numel(truth);
    aligned=z/gain;
    [~,nearestAligned]=min(abs(aligned-reference.'),[],2);
    shapeSER=mean(abs(reference(nearestAligned)-truth)>1e-6);
    evm=100*sqrt(mean(abs(aligned-truth).^2));
    lagScores=zeros(9,1);
    for shift=-4:4
        ti=idx-lag-shift;
        ok=ti>=1 & ti<=numel(tx);
        lagScores(shift+5)=abs(sum(z(ok).*conj(tx(ti(ok)))));
    end
    [~,lagIndex]=max(lagScores);
    out{bi}=table(string(name),start,stop,nnz(selected), ...
        100*fixedSER,100*moduloSER,100*shapeSER,evm, ...
        mod(ri-1,8)*45,angle(gain)*180/pi,lagIndex-5, ...
        'VariableNames',{'Stage','SymbolStart','SymbolEnd','CapturedSymbols', ...
        'FixedBranchSER_pct','ModuloBranchSER_pct','OracleShapeSER_pct', ...
        'OracleEVM_pct','BestBranch_deg','DataAidedPhase_deg','ResidualLag'});
end
out=out(~cellfun(@isempty,out));
T=vertcat(out{:});
end

function D = localFineReport(D)
% 256-symbol subwindows only inside the already captured bad-frame region.
% A best local rotation is REPORTED, not silently used to erase a cycle slip.
rows = cell(0,1);
events = cell(0,1);
first = round((D.ScoutWorstTxFrame-1)*D.CodedSymbolsPerFrame)+1;
refTx = exp(1j*(pi/4+(0:7).'*pi/4));
refRx = refTx*exp(-1j*pi/8);
for mi=1:numel(D.Runs)
    runData=D.Runs{mi}; cap=runData.Captured;
    tx=complex(NaN(max(runData.TX.SymbolIndex)+4,1));
    tx(runData.TX.SymbolIndex)=runData.TX.Symbols;
    txRx=tx*exp(-1j*pi/8);
    lag=runData.Lag;
    carrierRotation=localAnchorRotation(cap.Stages.Carrier.Samples, ...
        cap.Stages.Carrier.SymbolIndex,txRx,lag,D.Config);
    idx=cap.Stages.Carrier.SymbolIndex;
    assert(isequal(idx,cap.Stages.FSEAfterCoarseCFO.SymbolIndex) && ...
        isequal(idx,cap.Stages.AfterASM.SymbolIndex));
    carrierRatio=cap.Stages.Carrier.Samples./cap.Stages.FSEAfterCoarseCFO.Samples;
    carrierRatio=carrierRatio./abs(carrierRatio);
    beforeSlip=idx>=first+lag & idx<first+lag+1024;
    initial=angle(mean(carrierRatio(beforeSlip)));
    carrierRelative=angle(carrierRatio*exp(-1j*initial))*180/pi;
    crossing=find(idx>=first+lag & carrierRelative<=-22.5,1);
    if ~isempty(crossing)
        events{end+1,1}=table(runData.Mode,"Carrier correction crosses -22.5 deg", ...
            idx(crossing),(idx(crossing)-1-lag)/30e3,carrierRelative(crossing), ...
            'VariableNames',{'Mode','Event','SymbolIndex','Time_ms','Change_deg'}); %#ok<AGROW>
    end
    asmState=round(angle(cap.Stages.AfterASM.Samples./ ...
        cap.Stages.BeforeASM.Samples)/(pi/4));
    changes=mod(diff(asmState)+4,8)-4;
    positions=find(diff(idx)==1 & changes~=0 & idx(2:end)>=first+lag);
    for ei=positions(:).'
        events{end+1,1}=table(runData.Mode,"ASM correction branch changes", ...
            idx(ei+1),(idx(ei+1)-1-lag)/30e3,changes(ei)*45, ...
            'VariableNames',{'Mode','Event','SymbolIndex','Time_ms','Change_deg'}); %#ok<AGROW>
    end
    for start=(floor(first/256)-2)*256+1:256:first+D.CodedSymbolsPerFrame+512
        stop=start+255;
        names={'FSEAfterCoarseCFO','Carrier','AfterASM'};
        phase=NaN(1,3); ser=NaN(1,3); shape=NaN(1,3);
        for si=1:3
            s=cap.Stages.(names{si});
            selected=s.SymbolIndex>=start & s.SymbolIndex<=stop;
            idx=s.SymbolIndex(selected); z=s.Samples(selected);
            if numel(z)<128, continue; end
            if si==1, truth=tx(idx-lag); ref=refTx;
            else, truth=txRx(idx-lag); ref=refRx; end
            gain=mean(z.*conj(truth)); phase(si)=angle(gain)*180/pi;
            [~,near]=min(abs(z-ref.'),[],2);
            decisions=ref(near);
            ser(si)=100*mean(abs(decisions*exp(-1j*carrierRotation)-truth)>1e-6);
            [~,near]=min(abs(z/gain-ref.'),[],2);
            shape(si)=100*mean(abs(ref(near)-truth)>1e-6);
        end
        pass=NaN; falseAccepted=NaN; ddBranch=NaN;
        if isfield(cap,'Dual')
            s=cap.Dual.Samples;
            selected=s.SymbolIndex>=start & s.SymbolIndex<=stop & ...
                isfinite(s.Decision);
            idx=s.SymbolIndex(selected); decisions=s.Decision(selected);
            accepted=s.UpdateApplied(selected);
            if ~isempty(idx)
                pass=100*mean(accepted);
                if any(accepted)
                    errors=zeros(8,1);
                    for ri=0:7
                        errors(ri+1)=mean(abs(decisions(accepted)*exp(-1j*ri*pi/4)- ...
                            txRx(idx(accepted)-lag))>1e-6);
                    end
                    [falseAccepted,best]=min(errors);
                    falseAccepted=100*falseAccepted;
                    ddBranch=(best-1)*45;
                end
            end
        end
        rows{end+1,1}=table(runData.Mode,start,stop,(start-1-lag)/30e3, ...
            shape(1),phase(1),ser(2),phase(2),ser(3),phase(3), ...
            pass,falseAccepted,ddBranch,'VariableNames', ...
            {'Mode','SymbolStart','SymbolEnd','Time_ms','FSEShapeSER_pct', ...
            'FSEPhase_deg','CarrierFixedSER_pct','CarrierPhase_deg', ...
            'ASMFixedSER_pct','ASMPhase_deg','DDUpdate_pct', ...
            'FalseAcceptedModuloBranch_pct','DDBestBranch_deg'}); %#ok<AGROW>
    end
end
D.FineWindows=vertcat(rows{:});
D.Events=vertcat(events{:});
D.Meaning = ['Truth and scalar/rotation fits are OFFLINE only. Raw FSE ', ...
    'retains carrier drift; use its shape error plus phase, not its fixed ', ...
    'branch SER alone. DD fixed-branch error includes slips since the anchor; ', ...
    'modulo-branch error removes one constant rotation per window but the ', ...
    'selected branch is also reported. Fractional windows can span a slip.'];
fprintf('\nFine diagnostic (256 symbols), carrier-slip neighborhood:\n');
disp(D.Events);
disp(D.FineWindows(D.FineWindows.Time_ms>=14.95 & ...
    D.FineWindows.Time_ms<=15.035,:));
for mi=1:numel(D.Runs)
    S=D.Runs{mi}.Windows;
    fprintf('Switch neighborhood: %s\n',D.Runs{mi}.Mode);
    disp(S(S.Stage=="FSEAfterCoarseCFO" & S.SymbolStart>=30721 & ...
        S.SymbolEnd<=36864,{'SymbolStart','SymbolEnd','OracleShapeSER_pct', ...
        'OracleEVM_pct','ResidualLag'}));
    if isfield(D.Runs{mi}.Captured,'DecodedFrames')
        decoded=D.Runs{mi}.Captured.DecodedFrames;
        worst=find(decoded.BER>0.05);
        fprintf('Decoded RX frames with BER>0.05 (includes acquisition frames):\n');
        disp(table(decoded.RxFrameIndex(worst),decoded.BER(worst), ...
            'VariableNames',{'RxFrameIndex','BER'}));
    end
end
end
