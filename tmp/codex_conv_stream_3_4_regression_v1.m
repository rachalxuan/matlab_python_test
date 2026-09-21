% CODEX_CONV_STREAM_3_4_REGRESSION_V1
% Isolated bit-level proof for non-frame-aligned continuous 3/4 puncturing.
% It does not change the legacy receiver path and does not use channel/FEC
% truth to select a receiver candidate.

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(fullfile(projectDir,'src','python'));

if ~exist('ConvStream34Options','var') || ~isstruct(ConvStream34Options)
    ConvStream34Options = struct;
end
fullMatrix = localLogical(ConvStream34Options,'FullMatrix',false);
verboseReceiver = localLogical(ConvStream34Options,'VerboseReceiver',true);
randomSeed = localNumber(ConvStream34Options,'RandomSeed',3401);
selectedTestIndex = localNumber(ConvStream34Options,'TestIndex',NaN);

rng(randomSeed,'twister');
asm = localASM();
warmupFrames = 8;
measurementFrames = 16;
guardFrames = 3;
totalFrames = warmupFrames + measurementFrames + guardFrames;
tfBytesList = [1149 1150 1151];

tests = struct('TFBytes',{},'CropBits',{},'ChunkMode',{});
for tfBytes = tfBytesList
    tests(end+1) = struct('TFBytes',tfBytes,'CropBits',0, ...
        'ChunkMode','random'); %#ok<SAGROW>
end
for cropBits = 0:3
    tests(end+1) = struct('TFBytes',1150,'CropBits',cropBits, ...
        'ChunkMode','single'); %#ok<SAGROW>
    tests(end+1) = struct('TFBytes',1150,'CropBits',cropBits, ...
        'ChunkMode','random'); %#ok<SAGROW>
end
if fullMatrix
    tests = struct('TFBytes',{},'CropBits',{},'ChunkMode',{});
    for tfBytes = tfBytesList
        for cropBits = 0:3
            for chunkMode = ["single","fixed","random"]
                tests(end+1) = struct('TFBytes',tfBytes, ...
                    'CropBits',cropBits,'ChunkMode',char(chunkMode)); %#ok<SAGROW>
            end
        end
    end
end
if isfinite(selectedTestIndex)
    selectedTestIndex = round(selectedTestIndex);
    if selectedTestIndex < 1 || selectedTestIndex > numel(tests)
        error('ConvStream34Options.TestIndex must be in the range 1:%d.', ...
            numel(tests));
    end
    tests = tests(selectedTestIndex);
end

results = repmat(localEmptyResult(),numel(tests),1);
fprintf('\n================ 3/4 CONTINUOUS PUNCTURE REGRESSION ================\n');
fprintf('Tests=%d, warmup=%d, measurement=%d, guard=%d, seed=%d\n', ...
    numel(tests),warmupFrames,measurementFrames,guardFrames,randomSeed);

for iTest = 1:numel(tests)
    test = tests(iTest);
    payloadBits = test.TFBytes*8;
    frameBits = payloadBits + numel(asm);
    txPayload = zeros(payloadBits,totalFrames,'int8');
    for iFrame = 1:totalFrames
        payload = int8(randi([0 1],payloadBits,1));
        idBits = int8(bitget(uint16(iFrame),16:-1:1)).';
        payload(1:16) = idBits;
        txPayload(:,iFrame) = payload;
    end
    rawFrames = [repmat(asm,1,totalFrames);txPayload];
    rawStream = rawFrames(:);
    assert(mod(numel(rawStream),3) == 0, ...
        'The unmeasured guard must close the 3-bit TX puncture period.');

    [trellis,canonicalMode] = ccsdsTMConvolutionalOutputTrellis( ...
        poly2trellis(7,[171 133]),'auto-ccsds','3/4');
    encoder = comm.ConvolutionalEncoder( ...
        'TrellisStructure',trellis, ...
        'TerminationMethod','Continuous', ...
        'PuncturePatternSource','Property', ...
        'PuncturePattern',[1;1;0;1;1;0]);
    coded = int8(encoder(rawStream));
    coded = coded(test.CropBits+1:end);
    soft = 2*double(coded)-1;

    receiver = HelperTMContinuousConvReceiver( ...
        'CodeRate','3/4', ...
        'ASM',asm, ...
        'FramePayloadBits',payloadBits, ...
        'TracebackDepth',60, ...
        'ASMErrorThreshold',0, ...
        'MinASMFrames',4, ...
        'ConvolutionalG1G2Mode',canonicalMode, ...
        'Verbose',verboseReceiver);
    localAppendChunks(receiver,soft,test.ChunkMode,randomSeed+iTest);
    [rxPayload,info] = receiver.finalize();

    recoveredIDs = zeros(1,size(rxPayload,2));
    frameErrors = zeros(1,size(rxPayload,2));
    comparedBits = 0;
    errorBits = 0;
    for iFrame = 1:size(rxPayload,2)
        recoveredIDs(iFrame) = localBitsToUint(rxPayload(1:16,iFrame));
        id = recoveredIDs(iFrame);
        if id >= 1 && id <= totalFrames
            err = nnz(rxPayload(:,iFrame) ~= txPayload(:,id));
            frameErrors(iFrame) = err;
            if id > warmupFrames && id <= warmupFrames+measurementFrames
                comparedBits = comparedBits + payloadBits;
                errorBits = errorBits + err;
            end
        else
            frameErrors(iFrame) = payloadBits;
        end
    end
    measurementIDs = warmupFrames + (1:measurementFrames);
    recoveredMeasurementIDs = intersect(measurementIDs,recoveredIDs);
    coverage = numel(recoveredMeasurementIDs);
    duplicateIDs = numel(recoveredIDs)-numel(unique(recoveredIDs));
    if comparedBits > 0
        ber = errorBits/comparedBits;
    else
        ber = NaN;
    end
    pass = info.Available && coverage == measurementFrames && ...
        comparedBits == measurementFrames*payloadBits && ...
        errorBits == 0 && duplicateIDs == 0;

    results(iTest).TFBytes = test.TFBytes;
    results(iTest).RawFrameBits = frameBits;
    results(iTest).RawFrameRemainderMod3 = mod(frameBits,3);
    results(iTest).CropBits = test.CropBits;
    results(iTest).ExpectedDrop = mod(4-mod(test.CropBits,4),4);
    results(iTest).SelectedDrop = info.SelectedOffset;
    results(iTest).ChunkMode = string(test.ChunkMode);
    results(iTest).Locked = info.Available;
    results(iTest).RecoveredFrames = info.RecoveredFrames;
    results(iTest).MeasurementCoverage = coverage;
    results(iTest).ComparedBits = comparedBits;
    results(iTest).ErrorBits = errorBits;
    results(iTest).BER = ber;
    results(iTest).DuplicateFrameIDs = duplicateIDs;
    results(iTest).Pass = pass;

    fprintf(['[%02d/%02d] TF=%d B, (ASM+TF) mod 3=%d, crop=%d, ', ...
        'chunks=%-6s | drop=%d expected=%d | measurement=%d/%d, ', ...
        'BER=%g | %s\n'], ...
        iTest,numel(tests),test.TFBytes,mod(frameBits,3),test.CropBits, ...
        test.ChunkMode,info.SelectedOffset,results(iTest).ExpectedDrop, ...
        coverage,measurementFrames,ber,localPassLabel(pass));
end

ConvStream34Results = struct2table(results);
fprintf('\n================ 3/4 CONTINUOUS STREAM SUMMARY ================\n');
disp(ConvStream34Results(:,{'TFBytes','RawFrameRemainderMod3', ...
    'CropBits','ExpectedDrop','SelectedDrop','ChunkMode','Locked', ...
    'MeasurementCoverage','ComparedBits','ErrorBits','BER','Pass'}));

if all(ConvStream34Results.Pass)
    fprintf(['PASS: non-divisible 3/4 frames, four coded-bit start offsets, ', ...
        'and selected chunking modes all passed without TX-aided candidate selection.\n']);
else
    bad = ConvStream34Results(~ConvStream34Results.Pass,:);
    fprintf(2,'FAIL: %d/%d cases failed. Inspect ConvStream34Results below.\n', ...
        height(bad),height(ConvStream34Results));
    disp(bad);
end

% Negative control: receiver-side ASM evidence must be mandatory.  Random
% soft bits are not associated with any TX reference and must not lock.
negativePayloadBits = 1150*8;
negativeLength = round((negativePayloadBits+numel(asm))*4/3*12);
negativeSoft = 2*double(randi([0 1],negativeLength,1))-1;
negativeReceiver = HelperTMContinuousConvReceiver( ...
    'CodeRate','3/4','ASM',asm,'FramePayloadBits',negativePayloadBits, ...
    'ASMErrorThreshold',0,'MinASMFrames',4,'Verbose',false);
localAppendChunks(negativeReceiver,negativeSoft,'random',randomSeed+9000);
[negativePayload,negativeInfo] = negativeReceiver.finalize();
ConvStream34NegativeControl = struct( ...
    'Locked',negativeInfo.Available, ...
    'RecoveredFrames',size(negativePayload,2), ...
    'Pass',~negativeInfo.Available && isempty(negativePayload));
fprintf('[Negative control] random stream: lock=%d, recovered=%d | %s\n', ...
    ConvStream34NegativeControl.Locked, ...
    ConvStream34NegativeControl.RecoveredFrames, ...
    localPassLabel(ConvStream34NegativeControl.Pass));
assert(ConvStream34NegativeControl.Pass, ...
    'Random input falsely satisfied the multi-frame ASM lock rule.');

function localAppendChunks(receiver,soft,mode,seed)
    switch lower(string(mode))
        case "single"
            receiver.append(soft);
        case "fixed"
            chunkLength = 4093;
            for first = 1:chunkLength:numel(soft)
                receiver.append(soft(first:min(first+chunkLength-1,end)));
            end
        case "random"
            state = rng;
            cleaner = onCleanup(@() rng(state));
            rng(seed,'twister');
            first = 1;
            while first <= numel(soft)
                chunkLength = randi([1 8191]);
                last = min(first+chunkLength-1,numel(soft));
                receiver.append(soft(first:last));
                first = last+1;
            end
        otherwise
            error('Unknown ChunkMode="%s".',mode);
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

function value = localLogical(s,name,defaultValue)
    value = defaultValue;
    if isfield(s,name) && ~isempty(s.(name))
        value = logical(s.(name));
    end
end

function value = localNumber(s,name,defaultValue)
    value = defaultValue;
    if isfield(s,name) && isnumeric(s.(name)) && isscalar(s.(name)) && ...
            isfinite(s.(name))
        value = double(s.(name));
    end
end

function label = localPassLabel(pass)
    if pass
        label = 'PASS';
    else
        label = 'FAIL';
    end
end

function s = localEmptyResult()
    s = struct('TFBytes',0,'RawFrameBits',0,'RawFrameRemainderMod3',0, ...
        'CropBits',0,'ExpectedDrop',0,'SelectedDrop',NaN, ...
        'ChunkMode',"",'Locked',false,'RecoveredFrames',0, ...
        'MeasurementCoverage',0,'ComparedBits',0,'ErrorBits',0, ...
        'BER',NaN,'DuplicateFrameIDs',0,'Pass',false);
end
