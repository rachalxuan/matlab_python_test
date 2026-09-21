% CODEX_TM_GENERATOR_CONV_STREAM_3_4_REGRESSION_V1
% Verify the project's REAL ccsdsTMWaveformGenerator across batch and
% frame-by-frame calls before integrating the continuous receiver into the
% main evaluation path.  The receiver chooses puncture phase from ASM only;
% TX data are used afterwards for regression scoring.

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(fullfile(projectDir,'src','python'));

if ~exist('TMGeneratorConv34Options','var') || ...
        ~isstruct(TMGeneratorConv34Options)
    TMGeneratorConv34Options = struct;
end
tfBytesList = localVector(TMGeneratorConv34Options,'TFBytesList', ...
    [1149 1150 1151]);
warmupFrames = localNumber(TMGeneratorConv34Options,'WarmUpFrames',8);
measurementFrames = localNumber(TMGeneratorConv34Options,'MeasurementFrames',16);
guardReferenceFrames = localNumber(TMGeneratorConv34Options, ...
    'ReferenceGuardFrames',3);
randomSeed = localNumber(TMGeneratorConv34Options,'RandomSeed',7341);
verboseReceiver = localLogical(TMGeneratorConv34Options, ...
    'VerboseReceiver',false);
totalMeasuredFrames = warmupFrames + measurementFrames + guardReferenceFrames;
asm = localASM();
puncturePattern = [1;1;0;1;1;0];
P = numel(puncturePattern)/2;
Q = nnz(puncturePattern);
Fs = 2e6;

results = repmat(localEmptyResult(),numel(tfBytesList),1);
TMGeneratorConv34Details = cell(numel(tfBytesList),1);
fprintf('\n================ REAL TMGENERATOR 3/4 STREAM REGRESSION ================\n');
fprintf('TF cases=%d, measured input frames=%d (%d warmup + %d BER + %d reference guard)\n', ...
    numel(tfBytesList),totalMeasuredFrames,warmupFrames, ...
    measurementFrames,guardReferenceFrames);

for iCase = 1:numel(tfBytesList)
    tfBytes = tfBytesList(iCase);
    payloadBits = tfBytes*8;
    txPayload = localPayloadFixture(payloadBits,totalMeasuredFrames, ...
        randomSeed + 17*tfBytes);
    msg = txPayload(:);

    % Arm A: the exact measured message is supplied in one generator call.
    batchGenerator = localGenerator(tfBytes);
    [batchWaveMeasured,batchCodedMeasured] = batchGenerator(msg);
    [batchWave, batchCompletion, batchCodedGuard] = ...
        HelperTMCompleteBurst(batchGenerator,batchWaveMeasured, ...
        batchCodedMeasured,msg,Fs,struct);
    batchCoded = [int8(batchCodedMeasured(:));int8(batchCodedGuard(:))];

    % Arm B: the same message is supplied one transfer frame per call.  The
    % generator object is retained, so encoder/buffer/filter states persist.
    frameGenerator = localGenerator(tfBytes);
    frameWaveMeasured = complex(zeros(0,1));
    frameCodedMeasured = zeros(0,1,'int8');
    perCallEncodedLengths = zeros(totalMeasuredFrames,1);
    for iFrame = 1:totalMeasuredFrames
        [waveNow,codedNow] = frameGenerator(txPayload(:,iFrame));
        frameWaveMeasured = [frameWaveMeasured;waveNow(:)]; %#ok<AGROW>
        frameCodedMeasured = [frameCodedMeasured;int8(codedNow(:))]; %#ok<AGROW>
        perCallEncodedLengths(iFrame) = numel(codedNow);
    end
    [frameWave, frameCompletion, frameCodedGuard] = ...
        HelperTMCompleteBurst(frameGenerator,frameWaveMeasured, ...
        frameCodedMeasured,msg,Fs,struct);
    frameCoded = [frameCodedMeasured;int8(frameCodedGuard(:))];

    encodedEquivalent = isequal(batchCoded,frameCoded);
    waveformEquivalent = numel(batchWave)==numel(frameWave) && ...
        (isempty(batchWave) || max(abs(batchWave-frameWave)) < 1e-11);
    guardEquivalent = batchCompletion.GuardInputGroups == ...
        frameCompletion.GuardInputGroups && ...
        isequal(batchCodedGuard,frameCodedGuard);

    % Rebuild exactly the raw stream consumed by the real TX.  Completion
    % uses complemented copies of the final input group as unmeasured guard.
    nGuard = batchCompletion.GuardInputGroups;
    guardPayload = repmat(int8(1)-txPayload(:,end),1,nGuard);
    allPayload = [txPayload guardPayload];
    rawFrames = [repmat(asm,1,size(allPayload,2));allPayload];
    rawStream = rawFrames(:);
    assert(mod(numel(batchCoded),Q)==0, ...
        'Real TX emitted a partial 3/4 puncture output period.');
    rawBitsConsumed = numel(batchCoded)/Q*P;
    assert(rawBitsConsumed<=numel(rawStream), ...
        'Real TX emitted more coded bits than the supplied raw stream permits.');
    [trellis,canonicalMode] = ccsdsTMConvolutionalOutputTrellis( ...
        poly2trellis(7,[171 133]),'auto-ccsds','3/4');
    referenceEncoder = comm.ConvolutionalEncoder( ...
        'TrellisStructure',trellis, ...
        'TerminationMethod','Continuous', ...
        'PuncturePatternSource','Property', ...
        'PuncturePattern',puncturePattern);
    referenceCoded = int8(referenceEncoder(rawStream(1:rawBitsConsumed)));
    referenceEquivalent = isequal(referenceCoded,batchCoded);

    measurementRawBits = totalMeasuredFrames*(payloadBits+numel(asm));
    rawConsumedBeforeGuard = numel(batchCodedMeasured)/Q*P;
    measurementTailRawBits = measurementRawBits-rawConsumedBeforeGuard;
    measurementReleasedAfterGuard = rawBitsConsumed>=measurementRawBits;

    receiver = HelperTMContinuousConvReceiver( ...
        'CodeRate','3/4','ASM',asm,'FramePayloadBits',payloadBits, ...
        'TracebackDepth',60,'ASMErrorThreshold',0,'MinASMFrames',4, ...
        'ConvolutionalG1G2Mode',canonicalMode, ...
        'Verbose',verboseReceiver);
    localAppendIrregular(receiver,2*double(batchCoded)-1, ...
        randomSeed+10000+iCase);
    [rxPayload,rxInfo] = receiver.finalize();
    [coverage,comparedBits,errorBits,duplicates] = localScore( ...
        rxPayload,txPayload,warmupFrames,measurementFrames);
    if comparedBits>0
        ber = errorBits/comparedBits;
    else
        ber = NaN;
    end

    pass = encodedEquivalent && waveformEquivalent && guardEquivalent && ...
        referenceEquivalent && measurementReleasedAfterGuard && ...
        rxInfo.Available && rxInfo.SelectedOffset==0 && ...
        coverage==measurementFrames && ...
        comparedBits==measurementFrames*payloadBits && ...
        errorBits==0 && duplicates==0;

    results(iCase).TFBytes = tfBytes;
    results(iCase).RawFrameBits = payloadBits+numel(asm);
    results(iCase).RawFrameRemainderMod3 = ...
        mod(results(iCase).RawFrameBits,P);
    results(iCase).BatchMeasuredEncodedBits = numel(batchCodedMeasured);
    results(iCase).FramewiseMeasuredEncodedBits = numel(frameCodedMeasured);
    results(iCase).AppendedEncodedBits = numel(batchCodedGuard);
    results(iCase).MeasurementTailRawBits = measurementTailRawBits;
    results(iCase).MeasurementReleasedAfterGuard = ...
        measurementReleasedAfterGuard;
    results(iCase).EncodedEquivalent = encodedEquivalent;
    results(iCase).WaveformEquivalent = waveformEquivalent;
    results(iCase).ReferenceEquivalent = referenceEquivalent;
    results(iCase).SelectedDrop = rxInfo.SelectedOffset;
    results(iCase).MeasurementCoverage = coverage;
    results(iCase).ComparedBits = comparedBits;
    results(iCase).ErrorBits = errorBits;
    results(iCase).BER = ber;
    results(iCase).Pass = pass;
    TMGeneratorConv34Details{iCase} = struct( ...
        'BatchCompletion',batchCompletion, ...
        'FrameCompletion',frameCompletion, ...
        'PerCallEncodedLengths',perCallEncodedLengths, ...
        'ReceiverInfo',rxInfo, ...
        'RawBitsConsumedAfterGuard',rawBitsConsumed, ...
        'MeasurementRawBits',measurementRawBits);

    fprintf(['[%d/%d] TF=%d B, raw mod 3=%d | TX batch/frame=%d/%d, ', ...
        'tail=%d raw bit, append=%d coded | eq coded/wave/ref=%d/%d/%d | ', ...
        'drop=%g coverage=%d/%d BER=%g | %s\n'], ...
        iCase,numel(tfBytesList),tfBytes, ...
        results(iCase).RawFrameRemainderMod3, ...
        numel(batchCodedMeasured),numel(frameCodedMeasured), ...
        measurementTailRawBits,numel(batchCodedGuard), ...
        encodedEquivalent,waveformEquivalent,referenceEquivalent, ...
        rxInfo.SelectedOffset,coverage,measurementFrames,ber, ...
        localPassLabel(pass));
end

TMGeneratorConv34Results = struct2table(results);
fprintf('\n================ REAL TMGENERATOR 3/4 SUMMARY ================\n');
disp(TMGeneratorConv34Results);
if all(TMGeneratorConv34Results.Pass)
    fprintf(['PASS: real TMgenerator batch/frame calls are identical, match ', ...
        'the continuous puncture reference, release the measured tail via ', ...
        'real guard transmission, and recover every BER frame.\n']);
else
    bad = TMGeneratorConv34Results(~TMGeneratorConv34Results.Pass,:);
    fprintf(2,'FAIL: %d/%d real-generator cases failed.\n', ...
        height(bad),height(TMGeneratorConv34Results));
    disp(bad);
end

function generator = localGenerator(tfBytes)
    generator = ccsdsTMWaveformGenerator( ...
        'WaveformSource','synchronization and channel coding', ...
        'NumBytesInTransferFrame',tfBytes, ...
        'RandomizerEnabled',false, ...
        'HasASM',true, ...
        'PCMFormat','NRZ-L', ...
        'ChannelCoding','convolutional', ...
        'ConvolutionalCodeRate','3/4', ...
        'ConvolutionalG1G2Mode','auto-ccsds', ...
        'Modulation','QPSK', ...
        'PulseShapingFilter','root raised cosine', ...
        'RolloffFactor',0.35, ...
        'FilterSpanInSymbols',10, ...
        'SamplesPerSymbol',2, ...
        'DataPathMode','single');
end

function localAppendIrregular(receiver,soft,seed)
    stream = RandStream('mt19937ar','Seed',seed);
    receiver.append([]);
    first = 1;
    for chunkLength = [1 2 3]
        last = min(first+chunkLength-1,numel(soft));
        receiver.append(soft(first:last));
        first = last+1;
    end
    while first<=numel(soft)
        chunkLength = randi(stream,[1 8191]);
        last = min(first+chunkLength-1,numel(soft));
        receiver.append(soft(first:last));
        first = last+1;
    end
    receiver.append([]);
end

function [coverage,comparedBits,errorBits,duplicates] = localScore( ...
        rxPayload,txPayload,warmupFrames,measurementFrames)
    recoveredIDs = nan(1,size(rxPayload,2));
    comparedBits = 0;
    errorBits = 0;
    for iFrame = 1:size(rxPayload,2)
        id = localBitsToUint(rxPayload(1:16,iFrame));
        recoveredIDs(iFrame) = id;
        if id>=1 && id<=size(txPayload,2) && ...
                id>warmupFrames && ...
                id<=warmupFrames+measurementFrames
            comparedBits = comparedBits+size(txPayload,1);
            errorBits = errorBits+nnz(rxPayload(:,iFrame)~=txPayload(:,id));
        end
    end
    measurementIDs = warmupFrames+(1:measurementFrames);
    coverage = numel(intersect(measurementIDs,recoveredIDs));
    finiteIDs = recoveredIDs(isfinite(recoveredIDs));
    duplicates = numel(finiteIDs)-numel(unique(finiteIDs));
end

function payload = localPayloadFixture(payloadBits,totalFrames,seed)
    stream = RandStream('mt19937ar','Seed',seed);
    payload = int8(randi(stream,[0 1],payloadBits,totalFrames));
    for iFrame = 1:totalFrames
        payload(1:16,iFrame) = ...
            int8(bitget(uint16(iFrame),16:-1:1)).';
    end
end

function value = localBitsToUint(bits)
    value = 0;
    for bit = double(bits(:)).'
        value = 2*value+bit;
    end
end

function bits = localASM()
    bits = int8(bitget(uint32(hex2dec('1ACFFC1D')),32:-1:1)).';
end

function value = localNumber(s,name,defaultValue)
    value = defaultValue;
    if isfield(s,name) && isnumeric(s.(name)) && isscalar(s.(name)) && ...
            isfinite(s.(name))
        value = double(s.(name));
    end
end

function value = localVector(s,name,defaultValue)
    value = defaultValue;
    if isfield(s,name) && isnumeric(s.(name)) && ~isempty(s.(name)) && ...
            all(isfinite(s.(name)))
        raw = s.(name);
        value = double(raw(:)).';
    end
end

function value = localLogical(s,name,defaultValue)
    value = defaultValue;
    if isfield(s,name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function label = localPassLabel(pass)
    if pass, label='PASS'; else, label='FAIL'; end
end

function s = localEmptyResult()
    s = struct('TFBytes',0,'RawFrameBits',0, ...
        'RawFrameRemainderMod3',0, ...
        'BatchMeasuredEncodedBits',0, ...
        'FramewiseMeasuredEncodedBits',0, ...
        'AppendedEncodedBits',0,'MeasurementTailRawBits',0, ...
        'MeasurementReleasedAfterGuard',false, ...
        'EncodedEquivalent',false,'WaveformEquivalent',false, ...
        'ReferenceEquivalent',false,'SelectedDrop',NaN, ...
        'MeasurementCoverage',0,'ComparedBits',0,'ErrorBits',0, ...
        'BER',NaN,'Pass',false);
end
