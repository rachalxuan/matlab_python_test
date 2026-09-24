% CODEX_CONV_STREAM_HIGH_RATE_REGRESSION_V1
% Bit-layer proof for all five continuous convolutional-code rates. Receiver offset
% selection uses decoded ASM evidence only.  TX bits are consulted only
% after finalize() to score coverage and BER.

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
addpath(fullfile(projectDir,'src','python'));

if ~exist('ConvStreamHighRateOptions','var') || ...
        ~isstruct(ConvStreamHighRateOptions)
    ConvStreamHighRateOptions = struct;
end
rates = string(localField(ConvStreamHighRateOptions,'CodeRates', ...
    ["1/2","2/3","3/4","5/6","7/8"]));
tfBytes = localNumber(ConvStreamHighRateOptions,'TFBytes',1150);
verbose = localLogical(ConvStreamHighRateOptions,'VerboseReceiver',false);
seed = localNumber(ConvStreamHighRateOptions,'RandomSeed',5678);
warmupFrames = 8;
measurementFrames = 16;
guardFrames = 2;
asm = localASM();
payloadBits = 8*tfBytes;
frameBits = numel(asm)+payloadBits;

nRows = 0;
for rateForCount = rates
    cfgForCount = ccsdsTMConvolutionalPunctureConfig(rateForCount);
    nRows = nRows+2*cfgForCount.OutputBitsPerPeriod;
end
rows = repmat(localEmptyRow(),nRows,1);
rowIndex = 0;
fprintf('\n================ ALL-RATE CONV BIT-STREAM REGRESSION ================\n');
for iRate = 1:numel(rates)
    rate = char(rates(iRate));
    knownPattern = localKnownPattern(rate);
    cfg = ccsdsTMConvolutionalPunctureConfig(rate);
    assert(isequal(cfg.Pattern,knownPattern), ...
        'Shared puncture configuration disagrees with the independent fixture.');
    p = cfg.InputBitsPerPeriod;
    q = cfg.OutputBitsPerPeriod;
    % Continuous Viterbi output is delayed by traceback.  Append explicit
    % non-measurement frames so the last requested measurement frame is
    % released for every rate; do not rely on incidental puncture closure.
    totalFrames = warmupFrames+measurementFrames+guardFrames;
    while mod(totalFrames*frameBits,p) ~= 0
        totalFrames = totalFrames+1;
    end
    txPayload = localPayloadFixture(payloadBits,totalFrames,seed+100*iRate);
    raw = [repmat(asm,1,totalFrames);txPayload];
    raw = raw(:);
    assert(mod(numel(raw),p)==0,'TX fixture did not close its puncture period.');
    trellis = ccsdsTMConvolutionalOutputTrellis( ...
        poly2trellis(7,[171 133]),'auto-ccsds',rate);
    enc = comm.ConvolutionalEncoder( ...
        'TrellisStructure',trellis,'TerminationMethod','Continuous', ...
        'PuncturePatternSource','Property', ...
        'PuncturePattern',knownPattern);
    coded = int8(enc(raw));

    for crop = 0:q-1
        fixtureOutputs = cell(2,1);
        fixtureStarts = cell(2,1);
        for iMode = 1:2
            chunkMode = ["single","random"];
            soft = 2*double(coded(crop+1:end))-1;
            rx = HelperTMContinuousConvReceiver( ...
                'CodeRate',rate,'ASM',asm, ...
                'FramePayloadBits',payloadBits,'TracebackDepth',60, ...
                'ASMErrorThreshold',0,'MinASMFrames',4, ...
                'ConvolutionalG1G2Mode','auto-ccsds', ...
                'Verbose',verbose);
            localAppend(rx,soft,chunkMode(iMode),seed+1000*iRate+crop);
            [decoded,info] = rx.finalize();
            fixtureOutputs{iMode} = decoded;
            if info.Available
                fixtureStarts{iMode} = info.Candidates( ...
                    info.SelectedCandidate).FrameStarts;
            else
                fixtureStarts{iMode} = zeros(0,1);
            end
            [coverage,errorBits,duplicateIDs] = localScore( ...
                decoded,txPayload,warmupFrames,measurementFrames);
            accounting = all(arrayfun(@(c) ...
                c.InputBitsDiscarded+c.InputBitsConsumed+ ...
                c.PendingInputBits==info.InputBitsSeen,info.Candidates));
            expectedDrop = mod(q-mod(crop,q),q);
            pass = info.Available && info.SelectedOffset==expectedDrop && ...
                coverage==measurementFrames && errorBits==0 && ...
                duplicateIDs==0 && accounting;
            rowIndex = rowIndex+1;
            rows(rowIndex) = struct( ...
                'CodeRate',string(rate),'P',p,'Q',q, ...
                'TFBytes',tfBytes,'RawFrameRemainder',mod(frameBits,p), ...
                'CropBits',crop,'ChunkMode',chunkMode(iMode), ...
                'ExpectedDrop',expectedDrop, ...
                'SelectedDrop',info.SelectedOffset, ...
                'Locked',info.Available,'RecoveredFrames',info.RecoveredFrames, ...
                'MeasurementCoverage',coverage,'ErrorBits',errorBits, ...
                'DuplicateFrameIDs',duplicateIDs, ...
                'CandidateAccountingValid',accounting, ...
                'ChunkEquivalent',false,'Pass',pass); %#ok<SAGROW>
        end
        equivalent = isequal(fixtureOutputs{1},fixtureOutputs{2}) && ...
            isequal(fixtureStarts{1},fixtureStarts{2});
        rows(rowIndex-1).ChunkEquivalent = equivalent;
        rows(rowIndex).ChunkEquivalent = equivalent;
        rows(rowIndex-1).Pass = rows(rowIndex-1).Pass && equivalent;
        rows(rowIndex).Pass = rows(rowIndex).Pass && equivalent;
    end

    % A random stream has no associated TX reference and must not satisfy
    % the receiver's multi-frame ASM acquisition rule.
    negativeSoft = 2*double(randi([0 1],q*ceil(12*frameBits/p),1))-1;
    negativeRX = HelperTMContinuousConvReceiver( ...
        'CodeRate',rate,'ASM',asm,'FramePayloadBits',payloadBits, ...
        'ASMErrorThreshold',0,'MinASMFrames',4,'Verbose',false);
    localAppend(negativeRX,negativeSoft,"random",seed+9000+iRate);
    [negativePayload,negativeInfo] = negativeRX.finalize();
    assert(~negativeInfo.Available && isempty(negativePayload), ...
        '%s random negative control falsely locked.',rate);
end

ConvStreamHighRateResults = struct2table(rows);
disp(ConvStreamHighRateResults(:,{ ...
    'CodeRate','P','Q','RawFrameRemainder','CropBits','ChunkMode', ...
    'ExpectedDrop','SelectedDrop','Locked','MeasurementCoverage', ...
    'ErrorBits','ChunkEquivalent','CandidateAccountingValid','Pass'}));
assert(all(ConvStreamHighRateResults.Pass), ...
    'High-rate bit-stream regression failed.');
fprintf('PASS: %d/%d all-rate bit-stream cases passed without TX-aided acquisition.\n', ...
    nnz(ConvStreamHighRateResults.Pass),height(ConvStreamHighRateResults));

function pattern = localKnownPattern(rate)
switch char(rate)
    case '1/2'
        pattern = [1;1];
    case '2/3'
        pattern = [1;1;0;1];
    case '3/4'
        pattern = [1;1;0;1;1;0];
    case '5/6'
        pattern = [1;1;0;1;1;0;0;1;1;0];
    case '7/8'
        pattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];
    otherwise
        error('Unexpected high-rate fixture "%s".',rate);
end
end

function localAppend(receiver,soft,mode,seed)
if mode=="single"
    receiver.append(soft);
    return;
end
stream = RandStream('mt19937ar','Seed',seed);
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
end

function [coverage,errorBits,duplicates] = localScore( ...
        decoded,txPayload,warmupFrames,measurementFrames)
ids = zeros(1,size(decoded,2));
errorBits = 0;
for iFrame = 1:size(decoded,2)
    ids(iFrame) = localBitsToUint(decoded(1:16,iFrame));
    id = ids(iFrame);
    if id>warmupFrames && id<=warmupFrames+measurementFrames && ...
            id<=size(txPayload,2)
        errorBits = errorBits+nnz(decoded(:,iFrame)~=txPayload(:,id));
    end
end
wanted = warmupFrames+(1:measurementFrames);
coverage = numel(intersect(wanted,ids));
duplicates = numel(ids)-numel(unique(ids));
end

function payload = localPayloadFixture(payloadBits,totalFrames,seed)
stream = RandStream('mt19937ar','Seed',seed);
payload = int8(randi(stream,[0 1],payloadBits,totalFrames));
for iFrame = 1:totalFrames
    payload(1:16,iFrame) = int8(bitget(uint16(iFrame),16:-1:1)).';
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

function value = localField(s,name,defaultValue)
value = defaultValue;
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); end
end

function value = localNumber(s,name,defaultValue)
value = double(localField(s,name,defaultValue));
end

function value = localLogical(s,name,defaultValue)
value = logical(localField(s,name,defaultValue));
end

function row = localEmptyRow()
row = struct('CodeRate',"",'P',NaN,'Q',NaN,'TFBytes',NaN, ...
    'RawFrameRemainder',NaN,'CropBits',NaN,'ChunkMode',"", ...
    'ExpectedDrop',NaN,'SelectedDrop',NaN,'Locked',false, ...
    'RecoveredFrames',NaN,'MeasurementCoverage',NaN,'ErrorBits',NaN, ...
    'DuplicateFrameIDs',NaN,'CandidateAccountingValid',false, ...
    'ChunkEquivalent',false,'Pass',false);
end
