function [T, reportFile] = test_tm_ldpc78_decoder(stage, opt)
%TEST_TM_LDPC78_DECODER Isolated 7/8 graph regression, NEVER changes RX/cache.
%   test_tm_ldpc78_decoder('core')    : structure/TX/clean/error contracts
%   [T,F] = test_tm_ldpc78_decoder('compare') : core + fixed synthetic LLR A/B
%   [T,F] = test_tm_ldpc78_decoder('replay',struct('BatchFile',file))
%   Replay MAT must contain Batch.LLR (8160xN, positive=0, no ASM, already
%   derandomized), optionally Batch.Message (7136xN, evaluation ONLY).
%   A Batch without reference reports NaN errors, never a fabricated BER=0.
%   Optional Batch.Labels and Batch.FrameIndex preserve original identifiers.
%   Options: Seed=917, FramesPerCondition=2, MaxIterations=20,
%   SaveResults=true, OutputDir=artifacts/ccsds/ldpc78, BatchFile or Batch.
%   This tests the decoder, not end-to-end synchronization/coverage/CDL.

if nargin<1, stage='compare'; end
if nargin<2, opt=struct(); end
stage=validatestring(stage,{'core','compare','replay'});
allowed={'Seed','FramesPerCondition','MaxIterations','SaveResults', ...
    'OutputDir','BatchFile','Batch'};
assert(isstruct(opt) && isscalar(opt) && all(ismember(fieldnames(opt),allowed)), ...
    'Unknown option or nonscalar options struct.');
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
sourceDir=fullfile(root,'src','python');
oldPath=path; pathCleanup=onCleanup(@()path(oldPath));
addpath(sourceDir);
oldRng=rng; rngCleanup=onCleanup(@()rng(oldRng));
seed=option(opt,'Seed',917); rng(seed,'twister');
maxIterations=option(opt,'MaxIterations',20);
validateattributes(maxIterations,{'numeric'},{'scalar','integer','positive','finite'});
frames=option(opt,'FramesPerCondition',2);
validateattributes(frames,{'numeric'},{'scalar','integer','positive','finite'});
T=table(); reportFile='';
[~,~,model]=HelperTMLDPC78Decode();
generator=satcom.internal.ccsds.getTMLDPCGeneratorMatrix(7136,8/7);
fprintf('[7/8] BP graph and explicit receiver-mode regression; default mode/cache unchanged.\n');
fprintf('[graph] mother=%dx%d nnz=%d; shortened=%dx%d nnz=%d; known-zero=18; fill=2; punctured=0\n', ...
    size(model.MotherH),nnz(model.MotherH),size(model.H),nnz(model.H));
localCore(model,generator,maxIterations);
if strcmp(stage,'core'), return; end

if strcmp(stage,'replay')
    assert(xor(isfield(opt,'Batch'),isfield(opt,'BatchFile')), ...
        'Replay requires exactly one of Batch or BatchFile.');
    if isfield(opt,'Batch')
        Batch=opt.Batch;
    else
        stored=load(opt.BatchFile,'Batch');
        assert(isfield(stored,'Batch'),'MAT file must contain Batch.');
        Batch=stored.Batch;
    end
else
    Batch=localBatch(generator,frames,seed);
end
Batch=validateBatch(Batch);
count=size(Batch.LLR,2);
legacyPath=fullfile(sourceDir,'tm_ldpc_H_k7136_n8160.mat');
% Read-only: do NOT call legacy cache builders or the old noiseless script.
old=load(legacyPath,'H','k','n');
assert(old.k==7136 && old.n==8160 && isequal(size(old.H),[1024 8160]));
legacyCfg=ldpcDecoderConfig(sparse(logical(old.H)),'bp');
fprintf('[legacy] nnz=%d; graph edge reduction=%.1fx; maxIter=%d; termination=early\n', ...
    nnz(old.H),nnz(old.H)/nnz(model.H),maxIterations);

% Warm both code paths, exclude setup/warm-up from per-codeword timing.
warm=int8(satcom.internal.ccsds.tmldpcEncode(zeros(7136,1,'int8'),generator));
warmLLR=20*(1-2*double(warm));
ldpcDecode(warmLLR,legacyCfg,maxIterations,'OutputFormat','whole', ...
    'Termination','early','Multithreaded',true);
HelperTMLDPC78Decode(warmLLR,maxIterations);

saveResults=option(opt,'SaveResults',true);
validateattributes(saveResults,{'logical'},{'scalar'});
batchFile='';
if saveResults
    outDir=option(opt,'OutputDir',fullfile(root,'artifacts','ccsds','ldpc78'));
    if ~isfolder(outDir), mkdir(outDir); end
    stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
    reportFile=fullfile(outDir,['LDPC78_BP_' stamp '.mat']);
    batchFile=fullfile(outDir,['LDPC78_LLR_' stamp '.mat']);
    save(batchFile,'Batch','-v7');
end
meta=struct('Stage',stage,'SetupSeed',seed,'BatchSeed',option(Batch,'Seed',NaN), ...
    'MaxIterations',maxIterations, ...
    'Algorithm','bp','Termination','early','LLRPolarity','positive-zero', ...
    'LegacyPath',legacyPath,'LegacyNNZ',nnz(old.H),'StandardNNZ',nnz(model.H), ...
    'BatchFile',batchFile,'MatrixMode',model.MatrixMode, ...
    'ModelVersion',model.Version,'MotherGraphSize',size(model.MotherH), ...
    'ShortenedMotherIndices',model.ShortenedMotherIndices, ...
    'FillWireIndices',model.FillWireIndices, ...
    'MATLABVersion',version,'CompletedCodewords',0,'TotalCodewords',count, ...
    'MainReceiverModified',false,'TimingScope','decode only, after warm-up');
rows=struct([]);
for frame=1:count
    llr=double(Batch.LLR(:,frame));
    referenceCodeword=[];
    if isfield(Batch,'Message')
        referenceCodeword=int8(satcom.internal.ccsds.tmldpcEncode( ...
            Batch.Message(:,frame),generator));
    end
    % Alternate order to reduce systematic first/second timing bias.
    if mod(frame,2), order=[1 2]; else, order=[2 1]; end
    for which=order
        if which==1
            timer=tic;
            [whole,iterations,checks]=ldpcDecode(llr,legacyCfg,maxIterations, ...
                'OutputFormat','whole','Termination','early','Multithreaded',true);
            seconds=toc(timer);
            message=int8(whole(1:7136)); core=int8(whole(1:8158));
            name="legacy-dense-bp";
        else
            [message,diag]=HelperTMLDPC78Decode(llr,maxIterations);
            iterations=diag.ActualIterations; seconds=diag.DecodeSeconds;
            checks=diag.ParityCheckWeight; core=diag.DecodedCoreBits;
            name="standard-sparse-bp";
        end
        reencoded=int8(satcom.internal.ccsds.tmldpcEncode(message,generator));
        row=struct('BatchIndex',frame,'FrameIndex',Batch.FrameIndex(frame), ...
            'Condition',string(Batch.Labels(frame)),'Decoder',name, ...
            'InputInfoErrors',NaN,'InputCoreErrors',NaN, ...
            'DecodedInfoErrors',NaN,'ComparedInfoBits',0, ...
            'Iterations',double(iterations),'OwnParityWeight',sum(checks(:)~=0), ...
            'StandardParityWeight',nnz(mod(model.H*double(core),2)), ...
            'SubcodeMismatchBits',nnz(core~=reencoded(1:8158)), ...
            'ReceivedFillHardErrors',nnz(llr(8159:8160)<0), ...
            'Seconds',seconds);
        if which==2, row.OwnParityWeight=double(checks); end
        if isfield(Batch,'Message')
            reference=Batch.Message(:,frame);
            row.InputInfoErrors=nnz((llr(1:7136)<0)~=reference);
            row.InputCoreErrors=nnz((llr(1:8158)<0)~=referenceCodeword(1:8158));
            row.DecodedInfoErrors=nnz(message~=reference);
            row.ComparedInfoBits=7136;
        end
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        fprintf('[%d/%d %s] %s inputInfo=%g inputCore=%g decodedInfo=%g iter=%d parity=%d standardParity=%d subcode=%d time=%.4fs\n', ...
            frame,count,row.Condition,name,row.InputInfoErrors,row.InputCoreErrors,row.DecodedInfoErrors, ...
            row.Iterations,row.OwnParityWeight,row.StandardParityWeight, ...
            row.SubcodeMismatchBits,seconds);
    end
    T=struct2table(rows); meta.CompletedCodewords=frame;
    if saveResults, save(reportFile,'T','meta','-v7'); end
end
T=sortrows(T,{'BatchIndex','Decoder'});
if saveResults, save(reportFile,'T','meta','-v7'); end
fprintf('[done] %d/%d codewords compared; all failures retained. Not a link coverage test.\n',count,count);
if saveResults, fprintf('Report: %s\nLLR replay: %s\n',reportFile,batchFile); end
end

function localCore(model,generator,maxIterations)
% Structural-test additions must not change the generated comparison fixture.
coreRng=rng; coreCleanup=onCleanup(@()rng(coreRng));
% Impulses near shortening, circulant and information/parity boundaries.
locations=unique([1 2 493 494 510 511 512 1004 1005 1022 1023 6625 7135 7136 ...
    (511*(1:13)-18) (511*(1:13)-17)]);
messages=zeros(7136,2+numel(locations)+4,'int8');
messages(:,2)=1;
for n=1:numel(locations), messages(locations(n),n+2)=1; end
messages(:,end-3:end)=int8(randi([0 1],7136,4));
for n=1:size(messages,2)
    cw=int8(satcom.internal.ccsds.tmldpcEncode(messages(:,n),generator));
    assert(numel(cw)==8160 && ~any(cw(8159:8160)));
    assert(isequal(cw(1:7136),messages(:,n)));
    mother=[zeros(18,1);double(cw(1:8158))];
    assert(~any(mod(model.MotherH*mother,2)), ...
        'TX does not satisfy standard mother graph (circulant direction/order).');
    assert(~any(mod(model.H*double(cw(1:8158)),2)));
    [decoded,d]=HelperTMLDPC78Decode(20*(1-2*double(cw)),maxIterations);
    assert(isequal(decoded,messages(:,n)) && d.GraphParityPassed);
end
% Match the public waveform generator's bit output, not only an encoder copy.
g=ccsdsTMWaveformGenerator('Modulation','QPSK','ChannelCoding','LDPC', ...
    'CodeRate','7/8','NumBitsInInformationBlock',7136, ...
    'IsLDPCOnSMTF',false,'HasASM',true,'RandomizerEnabled',false);
[~,bits]=g(messages(:,end));
release(g);
assert(numel(bits)==8192 && isequal(int8(bits(33:end)),cw));
fprintf('[rate] nominal=7/8; information=7136; wire=8160; actual=%.9f; inverse=%.9f (not 8/7)\n', ...
    7136/8160,8160/7136);

% Exercise the explicit main-receiver switch on the same perfect codeword.
% Generic QPSK demodulator soft values use positive=bit1; the Decoder owns
% the one polarity conversion to the positive=bit0 BP convention.
decoderArgs={'ChannelCoding','LDPC','Modulation','QPSK', ...
    'CodeRate','7/8','NumBitsInInformationBlock',7136, ...
    'IsLDPCOnSMTF',false,'HasASM',true,'RandomizerEnabled',false, ...
    'DisableFrameSynchronization',true};
softGeneric=20*(2*double(bits(:))-1);
sparseReceiver=HelperCCSDSTMDecoder(decoderArgs{:}, ...
    'LDPCDecoderMode','standard-sparse-bp', ...
    'LDPCMaxIterations',maxIterations);
sparseOutput=sparseReceiver(softGeneric);
assert(isequal(sparseOutput,messages(:,end)), ...
    'Main receiver sparse 7/8 switch changed a perfect message.');
release(sparseReceiver);
captureReceiver=HelperCCSDSTMDecoder(decoderArgs{:}, ...
    'LDPCDecoderMode','capture-only');
captureOutput=captureReceiver(softGeneric);
capture=captureReceiver.getLDPCCapture();
assert(isequal(captureOutput,messages(:,end)) && capture.Available && ...
    isequal(size(capture.LLR),[8160 1]) && ...
    isequal(double(capture.LLR(:,1)),20*(1-2*double(cw))) && ...
    strcmp(capture.LLRPolarity,'positive-zero') && ...
    capture.ASMRemoved && capture.Derandomized, ...
    'Main receiver capture boundary/polarity contract changed.');
release(captureReceiver);
fprintf('[receiver PASS] standard-sparse-bp and capture-only: exact message, boundary and LLR polarity.\n');
% Complement-tolerant boundary acquisition must not pick an arbitrary phase.
% These fixtures contain only known ASM bits, never TX payload references.
marker=int8(bits(1:32)); windows=repmat(marker,1,8);
phase=HelperTMLDPC78CapturePhase({1-windows,windows},marker,[0 180]);
assert(phase.Accepted && phase.SelectedIndex==2 && ...
    isequal(phase.NormalMeanErrors,[32;0]) && isequal(phase.InverseMeanErrors,[0;32]));
phase=HelperTMLDPC78CapturePhase({windows,1-windows},marker,[0 180]);
assert(phase.Accepted && phase.SelectedIndex==1);
phase=HelperTMLDPC78CapturePhase({windows,windows},marker,[0 180]);
assert(~phase.Accepted && isnan(phase.SelectedIndex),'Tied ASM evidence must not pick the first candidate.');
phase=HelperTMLDPC78CapturePhase({windows(:,1:2),1-windows(:,1:2)},marker,[0 180]);
assert(~phase.Accepted,'Insufficient periodic evidence must be rejected.');
fprintf('[capture phase PASS] signed ASM, inverse ASM, ambiguous and insufficient evidence.\n');

% Fill corruption must be reported, not interpreted as LDPC parity evidence.
clean=20*(1-2*double(cw)); fillBad=clean; fillBad(8159:8160)=-20;
[a,da]=HelperTMLDPC78Decode(clean,maxIterations);
[b,db]=HelperTMLDPC78Decode(fillBad,maxIterations);
assert(isequal(a,b) && db.ReceivedFillHardErrors==2 && ...
    isequal(da.ActualIterations,db.ActualIterations));
% Input purity, batch independence and exact output size.
pair=[clean fillBad]; before=pair;
[both,dd]=HelperTMLDPC78Decode(pair,maxIterations);
assert(isequal(pair,before) && isequal(both,[a b]) && ...
    isequal(dd.ReceivedFillHardErrors,[0 2]));
% Correct a few weak wrong decisions: deterministic check, not a BER curve.
weak=clean; weak([1 493 494 7136 7137 8158])=-0.2*sign(weak([1 493 494 7136 7137 8158]));
[recovered,dw]=HelperTMLDPC78Decode(weak,maxIterations);
assert(isequal(recovered,messages(:,end)) && dw.GraphParityPassed, ...
    'Sparse BP failed the bounded weak-error contract.');
% Standard base-graph parity is not the encoder-subcode membership test.
% A constant 511-bit parity block is in the base-graph nullspace, but is
% not the parity word emitted for this message by the systematic encoder.
outside=cw; outside(7137:7647)=1-outside(7137:7647);
[sameInfo,extra]=HelperTMLDPC78Decode(20*(1-2*double(outside)),maxIterations);
assert(extra.GraphParityPassed && isequal(sameInfo,messages(:,end)) && ...
    nnz(extra.DecodedCoreBits~=cw(1:8158))==511, ...
    'Base-code/subcode distinction or explicit output positions changed.');
localMustFail(@()HelperTMLDPC78Decode(zeros(8192,1)), ...
    'ASM-inclusive input must be rejected.');
localMustFail(@()HelperTMLDPC78Decode(nan(8160,1)), 'NaN must be rejected.');
localMustFail(@()HelperTMLDPC78Decode(zeros(8160,1),0), 'Zero iterations must be rejected.');
fprintf('[core PASS] %d TX vectors, mother/shortened syndrome, public generator, clean BP, fill isolation, batch, weak errors, subcode distinction, input validation.\n',size(messages,2));
end

function Batch=localBatch(generator,frames,seed)
% BPSK channel LLR fixture, not a claimed device QPSK/channel measurement.
conditions=["clean","weak-6-errors","awgn-sigma-0.45","awgn-sigma-0.65"];
N=frames*numel(conditions);
Batch=struct('LLR',zeros(8160,N),'Message',zeros(7136,N,'int8'), ...
    'Labels',strings(1,N),'FrameIndex',1:N, ...
    'Provenance','synthetic BPSK real-noise codeword LLR; no frontend', ...
    'Seed',seed,'LLRPolarity','positive-zero','ASMRemoved',true,'Derandomized',true);
for f=1:frames
    message=int8(randi([0 1],7136,1));
    cw=int8(satcom.internal.ccsds.tmldpcEncode(message,generator));
    symbols=1-2*double(cw);
    noise=randn(8160,1); % same realization for both specified noise levels
    for c=1:numel(conditions)
        k=(c-1)*frames+f;
        if c==1
            llr=20*symbols;
        elseif c==2
            llr=20*symbols; pos=[1 493 494 7136 7137 8158];
            llr(pos)=-0.2*symbols(pos);
        else
            sigma=[0.45 0.65]; sigma=sigma(c-2);
            llr=2*(symbols+sigma*noise)/(sigma^2);
        end
        Batch.LLR(:,k)=llr; Batch.Message(:,k)=message; Batch.Labels(k)=conditions(c);
    end
end
end

function b=validateBatch(b)
assert(isstruct(b) && isscalar(b) && isfield(b,'LLR'));
validateattributes(b.LLR,{'double','single'},{'real','finite','2d','nonempty','nrows',8160});
assert(isfield(b,'LLRPolarity') && strcmp(b.LLRPolarity,'positive-zero') && ...
    isfield(b,'ASMRemoved') && isequal(b.ASMRemoved,true) && ...
    isfield(b,'Derandomized') && isequal(b.Derandomized,true), ...
    'Explicit LLRPolarity=positive-zero, ASMRemoved=true, Derandomized=true required.');
n=size(b.LLR,2);
if isfield(b,'Message')
    assert(isequal(size(b.Message),[7136 n]) && all(ismember(b.Message(:),[0 1])), ...
        'Message must be 7136-by-N binary evaluation reference.');
    b.Message=int8(b.Message);
end
if ~isfield(b,'Labels'), b.Labels=repmat("external-LLR",1,n); end
b.Labels=reshape(string(b.Labels),1,[]); assert(numel(b.Labels)==n);
if ~isfield(b,'FrameIndex'), b.FrameIndex=1:n; end
validateattributes(b.FrameIndex,{'numeric'},{'real','finite','vector','numel',n});
end

function localMustFail(f,description)
failed=false;
try
    f();
catch
    failed=true;
end
assert(failed,description);
end

function v=option(s,name,fallback)
if isfield(s,name), v=s.(name); else, v=fallback; end
end
