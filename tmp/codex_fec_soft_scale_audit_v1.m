function A=codex_fec_soft_scale_audit_v1(turboCapture,tpcCapture)
% Small offline audits; never changes a received sample or receiver state.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src','python'));
u=turboCapture.RawSoft(:); scaled=u/turboCapture.ResidualVariance;
A=struct();
A.RSHardDecisionChanges=nnz((u>0)~=(scaled>0));
% The exact peak-normalized 8-bit quantizer used by both convolutional
% and concatenated routes. Do NOT introduce clipping before this test.
a=uencode(u,8,max(abs(u)),'unsigned');
b=uencode(scaled,8,max(abs(scaled)),'unsigned');
A.ViterbiQuantizerChanges=nnz(a~=b);
assert(A.RSHardDecisionChanges==0 && A.ViterbiQuantizerChanges==0);
fprintf('RS hard-decision changes=0; conv/concatenated Viterbi input changes=0.\n');
if nargin<2, return; end

cap=tpcCapture.Captured.Stages.AfterASM;
take=cap.SymbolIndex>=tpcCapture.Config.SymbolRange(1) & ...
    cap.SymbolIndex<=tpcCapture.Config.SymbolRange(2);
idx=cap.SymbolIndex(take); z=cap.Samples(take);
[found,j]=ismember(idx-tpcCapture.Lag,tpcCapture.TX.SymbolIndex);
assert(all(found) && all(diff(idx)==1));
truth=tpcCapture.TX.Symbols(j)*exp(-1j*pi/8);
dm=comm.PSKDemodulator(8,pi/8,'BitOutput',true, ...
    'DecisionMethod','Approximate log-likelihood ratio','Variance',1, ...
    'SymbolMapping','Custom','CustomSymbolMapping',[0 4 6 2 3 7 5 1]);
soft=-dm(z); bits=int8(-dm(truth)>0);
firstBit=(idx(1)-tpcCapture.Lag-1)*3+1;
variance=HelperTMPSKResidualVariance(z,exp(1j*(pi/8+(0:7).'*pi/4)));
% Four fixed codewords around the recorded burst, not selected by outcome.
frames=[184 184 185 186]; words=[1 4 1 1]; rows=cell(4,1);
for k=1:4
    start=(frames(k)-1)*32800+32+(words(k)-1)*4096+1;
    loc=start-firstBit+1; assert(loc>=1 && loc+4095<=numel(soft));
    cw=soft(loc:loc+4095); tx=bits(loc:loc+4095);
    args={'TPCCodeRate','1/2','TPCInterleaver','block','UseKnownZeroConstraint',false};
    reference=ccsdsTPCDecodeSoft(2*double(tx)-1,args{:},'DecoderMode','hard-systematic-debug');
    raw=ccsdsTPCDecodeSoft(cw,args{:});
    calibrated=ccsdsTPCDecodeSoft(max(-50,min(50,cw/variance)),args{:});
    rows{k}=table(frames(k),words(k),variance,nnz((cw>0)~=tx), ...
        nnz(raw~=reference),nnz(calibrated~=reference), ...
        'VariableNames',{'TxFrame','Codeword','ResidualVariance','RawCodedErrors', ...
        'OriginalDecodedErrors','LLRScaledDecodedErrors'});
end
A.TPC=vertcat(rows{:}); disp(A.TPC);
fprintf('TPC keeps six Chase iterations and beta=1 in BOTH arms. Not a full-link BER estimate.\n');
end
