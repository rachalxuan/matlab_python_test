% CODEX_TM_GENERATOR_CONV_STREAM_HIGH_RATE_REGRESSION_V1
% Independent TX conformance check for all five convolutional-code rates.
% The real generator is compared bit-for-bit with a separate continuous
% mother-code + puncture reference, for both batch and one-frame calls.

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(fullfile(projectDir,'src','python'));

if ~exist('TMGeneratorConvHighRateOptions','var') || ...
        ~isstruct(TMGeneratorConvHighRateOptions)
    TMGeneratorConvHighRateOptions = struct;
end
warmupFrames = localNumber(TMGeneratorConvHighRateOptions,'WarmUpFrames',8);
measurementFrames = localNumber(TMGeneratorConvHighRateOptions, ...
    'MeasurementFrames',16);
referenceGuardFrames = localNumber(TMGeneratorConvHighRateOptions, ...
    'ReferenceGuardFrames',3);
seed = localNumber(TMGeneratorConvHighRateOptions,'RandomSeed',9876);
rates = string(localValue(TMGeneratorConvHighRateOptions,'CodeRates', ...
    ["1/2","2/3","3/4","5/6","7/8"]));
tfBytes = 1150;
asm = localASM();
Fs = 2e6;
totalMeasuredFrames = warmupFrames+measurementFrames+referenceGuardFrames;
rows = repmat(localEmptyRow(),numel(rates),1);

fprintf('\n================ REAL TMGENERATOR ALL-RATE CONFORMANCE ================\n');
for iRate = 1:numel(rates)
    rate = rates(iRate);
    cfg = ccsdsTMConvolutionalPunctureConfig(rate);
    knownPattern = localKnownPattern(rate);
    assert(isequal(cfg.Pattern,knownPattern), ...
        'Protocol helper disagrees with independent puncture fixture.');
    payloadBits = 8*tfBytes;
    payload = localPayloadFixture(payloadBits,totalMeasuredFrames, ...
        seed+100*iRate);
    message = payload(:);

    batchGenerator = localGenerator(rate,tfBytes);
    [batchWaveMeasured,batchCodedMeasured] = batchGenerator(message);
    [batchWave,batchCompletion,batchCodedGuard] = ...
        HelperTMCompleteBurst(batchGenerator,batchWaveMeasured, ...
        batchCodedMeasured,message,Fs,struct);
    batchCoded = [int8(batchCodedMeasured(:));int8(batchCodedGuard(:))];

    frameGenerator = localGenerator(rate,tfBytes);
    frameWaveMeasured = complex(zeros(0,1));
    frameCodedMeasured = zeros(0,1,'int8');
    for iFrame = 1:totalMeasuredFrames
        [waveNow,codedNow] = frameGenerator(payload(:,iFrame));
        frameWaveMeasured = [frameWaveMeasured;waveNow(:)]; %#ok<AGROW>
        frameCodedMeasured = [frameCodedMeasured;int8(codedNow(:))]; %#ok<AGROW>
    end
    [frameWave,frameCompletion,frameCodedGuard] = ...
        HelperTMCompleteBurst(frameGenerator,frameWaveMeasured, ...
        frameCodedMeasured,message,Fs,struct);
    frameCoded = [frameCodedMeasured;int8(frameCodedGuard(:))];

    codedEquivalent = isequal(batchCoded,frameCoded);
    waveformEquivalent = numel(batchWave)==numel(frameWave) && ...
        (isempty(batchWave) || max(abs(batchWave-frameWave))<1e-11);
    guardEquivalent = batchCompletion.GuardInputGroups== ...
        frameCompletion.GuardInputGroups && ...
        isequal(batchCodedGuard,frameCodedGuard);

    nGuard = batchCompletion.GuardInputGroups;
    guardPayload = repmat(int8(1)-payload(:,end),1,nGuard);
    allPayload = [payload guardPayload];
    rawFrames = [repmat(asm,1,size(allPayload,2));allPayload];
    rawStream = rawFrames(:);
    p = cfg.InputBitsPerPeriod;
    q = cfg.OutputBitsPerPeriod;
    assert(mod(numel(batchCoded),q)==0, ...
        'Real TX emitted a partial coded puncture period.');
    rawBitsConsumed = numel(batchCoded)/q*p;
    assert(rawBitsConsumed<=numel(rawStream), ...
        'Real TX emitted more bits than the supplied raw stream permits.');
    trellis = ccsdsTMConvolutionalOutputTrellis( ...
        poly2trellis(7,[171 133]),'auto-ccsds',rate);
    referenceEncoder = comm.ConvolutionalEncoder( ...
        'TrellisStructure',trellis,'TerminationMethod','Continuous', ...
        'PuncturePatternSource','Property', ...
        'PuncturePattern',knownPattern);
    referenceCoded = int8(referenceEncoder(rawStream(1:rawBitsConsumed)));
    referenceEquivalent = isequal(referenceCoded,batchCoded);

    measurementRawBits = totalMeasuredFrames*(payloadBits+numel(asm));
    measuredRawConsumed = numel(batchCodedMeasured)/q*p;
    tailRawBits = measurementRawBits-measuredRawConsumed;
    measurementReleased = rawBitsConsumed>=measurementRawBits;

    rx = HelperTMContinuousConvReceiver( ...
        'CodeRate',rate,'ASM',asm,'FramePayloadBits',payloadBits, ...
        'TracebackDepth',60,'ASMErrorThreshold',0,'MinASMFrames',4, ...
        'ConvolutionalG1G2Mode','auto-ccsds','Verbose',false);
    localAppend(rx,2*double(batchCoded)-1,seed+1000*iRate);
    [decoded,info] = rx.finalize();
    [coverage,errors] = localScore(decoded,payload, ...
        warmupFrames,measurementFrames);
    pass = codedEquivalent && waveformEquivalent && guardEquivalent && ...
        referenceEquivalent && measurementReleased && info.Available && ...
        coverage==measurementFrames && errors==0;
    rows(iRate) = struct('CodeRate',rate,'P',p,'Q',q, ...
        'RawFrameRemainder',mod(payloadBits+numel(asm),p), ...
        'BatchFramewiseCodedEqual',codedEquivalent, ...
        'BatchFramewiseWaveEqual',waveformEquivalent, ...
        'GuardEqual',guardEquivalent,'ReferenceEqual',referenceEquivalent, ...
        'MeasurementTailRawBits',tailRawBits, ...
        'MeasurementReleased',measurementReleased, ...
        'ReceiverAvailable',info.Available, ...
        'MeasurementCoverage',coverage,'ErrorBits',errors,'Pass',pass);
    fprintf(['[%s] raw remainder=%d/%d tail=%d | coded/wave/guard/ref=', ...
        '%d/%d/%d/%d | coverage=%d/%d errors=%d -> %s\n'], ...
        rate,rows(iRate).RawFrameRemainder,p,tailRawBits, ...
        codedEquivalent,waveformEquivalent,guardEquivalent, ...
        referenceEquivalent,coverage,measurementFrames,errors, ...
        localPassLabel(pass));
end

TMGeneratorConvHighRateResults = struct2table(rows);
disp(TMGeneratorConvHighRateResults);
assert(all(TMGeneratorConvHighRateResults.Pass), ...
    'Real-generator high-rate conformance regression failed.');
fprintf('PASS: real all-rate TX output matches the independent continuous reference.\n');

function generator = localGenerator(rate,tfBytes)
generator = ccsdsTMWaveformGenerator( ...
    'WaveformSource','synchronization and channel coding', ...
    'NumBytesInTransferFrame',tfBytes,'RandomizerEnabled',false, ...
    'HasASM',true,'PCMFormat','NRZ-L','ChannelCoding','convolutional', ...
    'ConvolutionalCodeRate',char(rate), ...
    'ConvolutionalG1G2Mode','auto-ccsds', ...
    'AllowContinuousPuncturingAcrossFrames',true, ...
    'Modulation','QPSK','PulseShapingFilter','root raised cosine', ...
    'RolloffFactor',0.35,'FilterSpanInSymbols',10, ...
    'SamplesPerSymbol',2,'DataPathMode','single');
end

function pattern = localKnownPattern(rate)
switch char(rate)
    case '1/2'
        pattern=[1;1];
    case '2/3'
        pattern=[1;1;0;1];
    case '3/4'
        pattern=[1;1;0;1;1;0];
    case '5/6'
        pattern=[1;1;0;1;1;0;0;1;1;0];
    case '7/8'
        pattern=[1;1;0;1;0;1;0;1;1;0;0;1;1;0];
    otherwise
        error('Unexpected convolutional fixture "%s".',rate);
end
end

function localAppend(receiver,soft,seed)
stream=RandStream('mt19937ar','Seed',seed);
first=1;
for chunkLength=[1 2 3]
    last=min(first+chunkLength-1,numel(soft));
    receiver.append(soft(first:last)); first=last+1;
end
while first<=numel(soft)
    chunkLength=randi(stream,[1 8191]);
    last=min(first+chunkLength-1,numel(soft));
    receiver.append(soft(first:last)); first=last+1;
end
end

function [coverage,errors] = localScore(decoded,payload,warmup,measured)
ids=nan(1,size(decoded,2)); errors=0;
for k=1:size(decoded,2)
    ids(k)=localBitsToUint(decoded(1:16,k));
    id=ids(k);
    if id>warmup && id<=warmup+measured && id<=size(payload,2)
        errors=errors+nnz(decoded(:,k)~=payload(:,id));
    end
end
coverage=numel(intersect(warmup+(1:measured),ids));
end

function payload=localPayloadFixture(payloadBits,totalFrames,seed)
stream=RandStream('mt19937ar','Seed',seed);
payload=int8(randi(stream,[0 1],payloadBits,totalFrames));
for k=1:totalFrames
    payload(1:16,k)=int8(bitget(uint16(k),16:-1:1)).';
end
end

function value=localBitsToUint(bits)
value=0;
for bit=double(bits(:)).', value=2*value+bit; end
end

function bits=localASM()
bits=int8(bitget(uint32(hex2dec('1ACFFC1D')),32:-1:1)).';
end

function value=localNumber(s,name,defaultValue)
value=defaultValue;
if isfield(s,name) && isnumeric(s.(name)) && isscalar(s.(name)) && ...
        isfinite(s.(name)), value=double(s.(name)); end
end

function value=localValue(s,name,defaultValue)
value=defaultValue;
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); end
end

function label=localPassLabel(pass)
if pass, label='PASS'; else, label='FAIL'; end
end

function row=localEmptyRow()
row=struct('CodeRate',"",'P',NaN,'Q',NaN,'RawFrameRemainder',NaN, ...
    'BatchFramewiseCodedEqual',false,'BatchFramewiseWaveEqual',false, ...
    'GuardEqual',false,'ReferenceEqual',false, ...
    'MeasurementTailRawBits',NaN,'MeasurementReleased',false, ...
    'ReceiverAvailable',false,'MeasurementCoverage',NaN, ...
    'ErrorBits',NaN,'Pass',false);
end
