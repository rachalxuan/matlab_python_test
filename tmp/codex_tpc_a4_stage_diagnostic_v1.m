function D = codex_tpc_a4_stage_diagnostic_v1(cached)
% Read-only frontend diagnosis of the 100+120-frame TPC/A4 record.
% Hard-systematic mode skips iterative TPC decoding, NOT the TPC encoder.
% Its BER is NOT the final decoded BER. TX truth is used only after RX ends.
% Pass a previously captured D to update the offline audit without RX rerun.
if nargin>0
    D=localDecisionAudit(cached);
    return;
end
diagnosticRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(diagnosticRoot,'src','python'));
diagnosticConfig = struct('SymbolRange', ...
    [floor(183*32800/3)-128 ceil(187*32800/3)+256], ...
    'AnchorRange',[1800001 1804096]); % 60 ms, before the reported burst
NewChannelFECRepresentativeOptions = struct( ...
    'StartFEC',7,'MaxFEC',1,'StartFile',4,'MaxFiles',1, ...
    'ModType','8PSK','SymbolRate',30e6,'SamplesPerSymbol',8, ...
    'BERWarmUpFrames',100,'BERFrames',120,'Seed',364232726, ...
    'NoiseMode','off','NormalizeHChannel',true, ...
    'TPCCodeRate','1/2','TPCBlocksPerTF',8,'TPCInterleaver','auto', ...
    'TPCUseKnownZeroConstraint',false,'TPCDecoderMode','hard-systematic-debug', ...
    'VerboseReceiverLog',false,'SaveCSV',false, ...
    'ReceiverOverrides',struct('cfo',0, ...
    'enablePSKCoarseFrequencyCompensator',true,'carrierCaptureRangeHz',2e6, ...
    'carrierLoopBandwidth',0.0025,'adaptiveEqualizerSamplingMode','2sps-dual', ...
    'adaptiveFractionalEqualizerTaps',129,'PSKPostFSEPhaseTrackerMode','off', ...
    'collectPredecoderStats',true,'FSEDiagnostics',diagnosticConfig)); %#ok<NASGU>
fprintf('TPC A4 frontend only: identical encoded record, no iterative TPC sweep.\n');
diagnosticLog = evalc('run(fullfile(diagnosticRoot,''tmp'',''codex_new_channel_psd_fec_representative_sweep_v1.m''));');
assert(result.success && isfield(result,'FSEDiagnostics'), ...
    'Receiver did not produce stage diagnostics.');
D = struct('Parameters',p,'Config',diagnosticConfig,'Log',diagnosticLog, ...
    'PredecoderSteadyBER',result.PredecoderSteadyBER, ...
    'PredecoderFrameBERP95',result.PredecoderFrameBERP95, ...
    'PredecoderFrameBERMax',result.PredecoderFrameBERMax, ...
    'Captured',result.FSEDiagnostics);
% These rounded targets are from the user's iterative-TPC run. A mismatch
% means this is a different record/selected phase branch, not a reproduction.
D.MatchesReportedFrontend = abs(D.PredecoderSteadyBER-0.01036)<5e-6 && ...
    abs(D.PredecoderFrameBERP95-0.049543)<5e-5 && ...
    abs(D.PredecoderFrameBERMax-0.3168)<5e-5;
fprintf('preBER=%.9g p95=%.9g max=%.9g; matches reported frontend=%d\n', ...
    D.PredecoderSteadyBER,D.PredecoderFrameBERP95,D.PredecoderFrameBERMax, ...
    D.MatchesReportedFrontend);
txBits = evalin('base','debugTMEncodedBits');
mapper = comm.PSKModulator(8,pi/4,'SymbolMapping','Custom', ...
    'BitInput',true,'CustomSymbolMapping',[0 4 6 2 3 7 5 1]);
tx = mapper(double(txBits(1:3*floor(numel(txBits)/3))));
cap = D.Captured.Stages.FSEAfterCoarseCFO;
anchor = cap.SymbolIndex>=diagnosticConfig.AnchorRange(1) & ...
    cap.SymbolIndex<=diagnosticConfig.AnchorRange(2);
idx = cap.SymbolIndex(anchor); x = cap.Samples(anchor);
lags = (-256:256).'; scores = zeros(size(lags));
for j=1:numel(lags)
    scores(j)=abs(sum(x.*conj(tx(idx-lags(j)))))/sqrt(sum(abs(x).^2)*numel(x));
end
[best,j]=max(scores); ordered=sort(scores,'descend');
assert(best>0.2 && best>1.3*ordered(2),'Ambiguous TX/RX alignment.');
D.Lag=lags(j); D.AlignmentCorrelation=best;
fprintf('Fixed alignment: lag=%d symbols, correlation=%.6f\n',D.Lag,best);
names={'FSEAfterCoarseCFO','Carrier','AfterASM'};
rows=cell(0,1);
for si=1:numel(names)
    cap=D.Captured.Stages.(names{si});
    stageTX=tx;
    if si>1, stageTX=stageTX*exp(-1j*pi/8); end
    ref=exp(1j*(pi/4+(0:7).'*pi/4));
    if si>1, ref=ref*exp(-1j*pi/8); end
    idx=cap.SymbolIndex; x=cap.Samples;
    anchor=idx>=diagnosticConfig.AnchorRange(1) & idx<=diagnosticConfig.AnchorRange(2);
    anchorPhase=angle(sum(x(anchor).*conj(stageTX(idx(anchor)-D.Lag))));
    fixedRotation=round(anchorPhase/(pi/4))*pi/4;
    bins=unique(floor((idx-1)/256));
    for bi=1:numel(bins)
        selected=floor((idx-1)/256)==bins(bi);
        if nnz(selected)<128, continue; end
        ii=idx(selected); z=x(selected); truth=stageTX(ii-D.Lag);
        [~,near]=min(abs(z-ref.'),[],2); decisions=ref(near);
        fixedSER=mean(abs(decisions*exp(-1j*fixedRotation)-truth)>1e-6);
        branchSER=zeros(8,1);
        for ri=0:7
            branchSER(ri+1)=mean(abs(decisions*exp(-1j*ri*pi/4)-truth)>1e-6);
        end
        [moduloSER,ri]=min(branchSER);
        % Oracle common phase/amplitude fit, not an inverse channel and NOT
        % a deployable receiver or a proof of optimal recoverability.
        g=mean(z.*conj(truth)); aligned=z/g;
        [~,near]=min(abs(aligned-ref.'),[],2);
        shapeSER=mean(abs(ref(near)-truth)>1e-6);
        evm=100*sqrt(mean(abs(aligned-truth).^2));
        lagScores=zeros(9,1);
        for shift=-4:4
            lagScores(shift+5)=abs(sum(z.*conj(stageTX(ii-D.Lag-shift))));
        end
        [~,li]=max(lagScores);
        rows{end+1,1}=table(string(names{si}),min(ii),max(ii), ...
            (mean(ii)-1-D.Lag)/30e3,ceil((mean(ii)-D.Lag)*3/32800), ...
            100*fixedSER,100*moduloSER,100*shapeSER,evm, ...
            mod((ri-1)*45-fixedRotation*180/pi+180,360)-180, ...
            angle(g)*180/pi,li-5, ...
            'VariableNames',{'Stage','SymbolStart','SymbolEnd','Time_ms','TxFrame', ...
            'FixedBranchSER_pct','ModuloBranchSER_pct','OracleShapeSER_pct', ...
            'OracleEVM_pct','RelativeBranch_deg','DataAidedPhase_deg','ResidualLag'}); %#ok<AGROW>
    end
end
D.Windows=vertcat(rows{:});
txIndices=cap.SymbolIndex-D.Lag;
D.TX=struct('SymbolIndex',txIndices,'Symbols',tx(txIndices));
% Test the instrumentation's phase convention against actual demapper bits.
if isfield(D.Captured,'Demapper')
    cap=D.Captured.Stages.AfterASM;
    demod=comm.PSKDemodulator(8,pi/8,'SymbolMapping','Custom', ...
        'CustomSymbolMapping',[0 4 6 2 3 7 5 1],'BitOutput',true);
    bits=demod(cap.Samples);
    indices=reshape((cap.SymbolIndex.'-1)*3+(1:3).',[],1);
    [~,ia,ib]=intersect(indices,D.Captured.Demapper.BitIndex);
    D.DemapperDisagreementBits=nnz(bits(ia)~=D.Captured.Demapper.HardBits(ib));
    D.DemapperComparedBits=numel(ia);
    assert(D.DemapperDisagreementBits==0,'Diagnostic and actual demapper differ.');
end
fprintf('256-symbol window summaries (TX truth offline only):\n');
disp(groupsummary(D.Windows,{'Stage','TxFrame'},'mean', ...
    {'FixedBranchSER_pct','ModuloBranchSER_pct','OracleShapeSER_pct','OracleEVM_pct'}));
fprintf('Nonzero residual lag windows: %d/%d\n', ...
    nnz(D.Windows.ResidualLag~=0),height(D.Windows));
fprintf('No receiver algorithms changed. Hard-systematic BER is not decoded TPC BER.\n');
D=localDecisionAudit(D);
end

function D=localDecisionAudit(D)
% Compare decisions only after execution. The best per-window discrete
% rotation is reported alongside the fixed-anchor score, not fed back.
s=D.Captured.Dual.Samples;
truth=D.TX.Symbols*exp(-1j*pi/8);
[found,j]=ismember(s.SymbolIndex-D.Lag,D.TX.SymbolIndex);
assert(all(found),'Missing offline TX reference for a captured decision.');
truth=truth(j);
anchor=s.SymbolIndex>=D.Config.AnchorRange(1) & s.SymbolIndex<=D.Config.AnchorRange(2);
anchorRotation=round(angle(sum(s.Decision(anchor).*conj(truth(anchor))))/(pi/4))*pi/4;
bins=unique(floor((s.SymbolIndex-1)/256));
rows=cell(0,1);
for bi=1:numel(bins)
    selected=floor((s.SymbolIndex-1)/256)==bins(bi);
    if nnz(selected)<128, continue; end
    used=selected & s.UpdateApplied;
    fixedWrong=NaN; moduloWrong=NaN;
    if any(used)
        d=s.Decision(used); t=truth(used);
        fixedWrong=mean(abs(d*exp(-1j*anchorRotation)-t)>1e-6);
        errors=zeros(8,1);
        for ri=0:7
            errors(ri+1)=mean(abs(d*exp(-1j*ri*pi/4)-t)>1e-6);
        end
        moduloWrong=min(errors);
    end
    ii=s.SymbolIndex(selected);
    rows{end+1,1}=table((mean(ii)-1-D.Lag)/30e3, ...
        ceil((mean(ii)-D.Lag)*3/32800),nnz(selected),nnz(used), ...
        100*nnz(used)/nnz(selected),100*fixedWrong,100*moduloWrong, ...
        'VariableNames',{'Time_ms','TxFrame','CapturedSymbols','UpdatedSymbols', ...
        'Update_pct','FalseAcceptedFixed_pct','FalseAcceptedModulo_pct'}); %#ok<AGROW>
end
D.DecisionAudit=vertcat(rows{:});
fprintf('DD updates: true decision correctness, not merely gate acceptance:\n');
disp(groupsummary(D.DecisionAudit,'TxFrame','mean', ...
    {'Update_pct','FalseAcceptedFixed_pct','FalseAcceptedModulo_pct'}));
end
