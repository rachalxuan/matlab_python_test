function [decodedBits, info] = ccsdsTPCDecodeSoft(cwSoft, varargin)
%CCSDSTPCDECODESOFT Decode serial soft TPC codeblocks with teacher decoder.
%   Input soft convention follows the existing receiver: bit 1 positive,
%   bit 0 negative.

    p = inputParser;
    addParameter(p, 'Iterations', 6);
    addParameter(p, 'LeastReliableBits', 4);
    addParameter(p, 'Alpha', 0.5);
    addParameter(p, 'Beta', 1);
    addParameter(p, 'TPCCodeRate', 'native');
    addParameter(p, 'TPCInterleaver', 'auto');
    addParameter(p, 'UseKnownZeroConstraint', false);
    % Diagnostic only: extract hard decisions from the transmitted
    % systematic payload coordinates without running the iterative Chase
    % product-code decoder.  This preserves the exact TPC waveform, frame
    % duration and interleaver, so receiver-front-end A/B tests do not spend
    % minutes inside TPC_decoder.  Production behaviour remains iterative.
    addParameter(p, 'DecoderMode', 'iterative');
    parse(p, varargin{:});

    m = 6;
    n = 2^m - 1;
    N = n + 1;
    k = n - m;
    genpoly = [1 0 0 0 0 1 1];
    [H, ~] = hammgen(m, genpoly);
    H = [H(:,m+1:end), H(:,1:m)];

    infoLen = k * k;
    codeLen = N * N;
    [payloadSideLen, rateLabel] = localTPCPayloadSideLength(p.Results.TPCCodeRate, k);
    payloadLen = payloadSideLen * payloadSideLen;
    payloadIdx = localTPCPayloadIndices(rateLabel, payloadSideLen, k);
    knownZeroMask = false(N, N);
    unusedSystematic = true(k, k);
    unusedSystematic(payloadIdx) = false;
    knownZeroMask(1:k, 1:k) = unusedSystematic;
    knownZeroCount = nnz(knownZeroMask);
    useKnownZeroConstraint = logical(p.Results.UseKnownZeroConstraint) && ...
        knownZeroCount > 0;
    interleaverMode = localTPCInterleaverMode(p.Results.TPCInterleaver, rateLabel);
    interleaverIdx = localTPCInterleaverIndices(codeLen, interleaverMode);
    decoderMode = localTPCDecoderMode(p.Results.DecoderMode);
    cwSoft = double(cwSoft(:));
    numBlocks = floor(numel(cwSoft) / codeLen);
    decodedBits = zeros(numBlocks * payloadLen, 1, 'int8');

    oldDir = pwd;
    tpcDir = fileparts(which('TPC_decoder.m'));
    cleanupObj = onCleanup(@() cd(oldDir));
    if ~isempty(tpcDir)
        cd(tpcDir);
    end

    for iBlock = 1:numBlocks
        idx = (iBlock-1)*codeLen+1:iBlock*codeLen;
        deinterleavedSoft = zeros(codeLen, 1);
        deinterleavedSoft(interleaverIdx) = cwSoft(idx);
        rxMat = reshape(deinterleavedSoft, N, N);
        if useKnownZeroConstraint
            % The current 1/2 and 2/3 modes still transmit a complete
            % 64-by-64 product codeword.  Systematic coordinates outside
            % the configured payload square are deterministic zero filler,
            % not unknown received data.  Give those locations a large but
            % finite negative metric (bit 0 in this receiver convention).
            % A finite value avoids Inf*0 -> NaN in the Chase distance
            % calculation while also keeping these known positions out of
            % the least-reliable-bit candidate set.
            knownZeroReliability = localKnownZeroReliability(rxMat);
            rxMat(knownZeroMask) = -knownZeroReliability;
        end
        if strcmp(decoderMode, 'hard-systematic-debug')
            % TPC_encoder is systematic in the top-left k-by-k matrix and
            % payloadIdx is the same mask used by the transmitter.  Positive
            % soft values mean bit 1 in this receiver contract.
            systematicSoft = rxMat(1:k,1:k);
            decPayload = int8(systematicSoft(payloadIdx) > 0);
        else
            [decout, ~] = TPC_decoder(rxMat, n, k, H, ...
                p.Results.LeastReliableBits, p.Results.Alpha, ...
                p.Results.Beta, p.Results.Iterations);
            decPayload = int8(decout(payloadIdx) ~= 0);
        end
        decodedBits((iBlock-1)*payloadLen+1:iBlock*payloadLen) = decPayload(:);
    end

    clear cleanupObj;

    info = struct();
    info.N = N;
    info.K = k;
    info.TPCCodeRate = rateLabel;
    info.NativeInfoBlockBits = infoLen;
    info.PayloadSideBits = payloadSideLen;
    info.PayloadMaskMode = localTPCPayloadMaskMode(rateLabel);
    info.TPCInterleaver = interleaverMode;
    info.InfoBlockBits = payloadLen;
    info.CodeBlockBits = codeLen;
    info.NumBlocks = numBlocks;
    info.CodeRate = payloadLen / codeLen;
    info.NativeCodeRate = infoLen / codeLen;
    info.KnownZeroConstraintEnabled = logical(p.Results.UseKnownZeroConstraint);
    info.KnownZeroConstraintApplied = useKnownZeroConstraint;
    info.KnownZeroBitsPerCodeword = knownZeroCount;
    info.DecoderMode = decoderMode;
end

function mode = localTPCDecoderMode(rawMode)
    if nargin < 1 || isempty(rawMode)
        rawMode = 'iterative';
    end
    mode = lower(strtrim(char(string(rawMode))));
    switch mode
        case {'iterative','normal','production'}
            mode = 'iterative';
        case {'hard-systematic-debug','systematic-debug','bypass'}
            mode = 'hard-systematic-debug';
        otherwise
            error('ccsdsTPCDecodeSoft:InvalidDecoderMode', ...
                ['Unsupported DecoderMode="%s". Use iterative or ', ...
                 'hard-systematic-debug.'], char(string(rawMode)));
    end
end

function reliability = localKnownZeroReliability(rxMat)
    finiteMagnitude = abs(rxMat(isfinite(rxMat)));
    finiteMagnitude = finiteMagnitude(finiteMagnitude > 0);
    if isempty(finiteMagnitude)
        typicalMagnitude = 1;
        peakMagnitude = 1;
    else
        typicalMagnitude = median(finiteMagnitude);
        peakMagnitude = max(finiteMagnitude);
    end
    reliability = max([1, 32*typicalMagnitude, 4*peakMagnitude]);
end

function idx = localTPCPayloadIndices(rateLabel, payloadSideLen, nativeSideLen)
    mask = false(nativeSideLen, nativeSideLen);
    mask(1:payloadSideLen, 1:payloadSideLen) = true;
    idx = find(mask);
end

function mode = localTPCPayloadMaskMode(rateLabel)
    mode = 'top-left-square';
    if strcmp(rateLabel, '1/2')
        mode = 'top-left-square-with-codeword-interleaver';
    end
end

function mode = localTPCInterleaverMode(rawMode, rateLabel)
    if nargin < 1 || isempty(rawMode)
        rawMode = 'auto';
    end
    mode = lower(strtrim(char(rawMode)));
    switch mode
        case {'auto','default'}
            if strcmp(rateLabel, '1/2')
                mode = 'block';
            else
                mode = 'none';
            end
        case {'none','off','bypass'}
            mode = 'none';
        case {'block','codeword','on'}
            mode = 'block';
        otherwise
            error('ccsdsTPCDecodeSoft:InvalidTPCInterleaver', ...
                'Unsupported TPCInterleaver="%s". Use auto, none, or block.', ...
                char(string(rawMode)));
    end
end

function idx = localTPCInterleaverIndices(codeLen, mode)
    idx = (1:codeLen).';
    if strcmp(mode, 'block')
        step = 257;
        idx = mod((0:codeLen-1).' * step, codeLen) + 1;
    end
end

function [payloadSideLen, label] = localTPCPayloadSideLength(rawRate, nativeSideLen)
    if nargin < 1 || isempty(rawRate)
        rawRate = 'native';
    end

    if isnumeric(rawRate)
        payloadSideLen = round(double(rawRate));
        label = sprintf('%dx%d', payloadSideLen, payloadSideLen);
    else
        label = lower(strtrim(char(rawRate)));
        switch label
            case {'native','default','0.7932','57','57x57'}
                payloadSideLen = nativeSideLen;
                label = 'native';
            case {'1/2','half'}
                payloadSideLen = 45;
                label = '1/2';
            case {'2/3'}
                payloadSideLen = 52;
                label = '2/3';
            otherwise
                xPos = strfind(label, 'x');
                if numel(xPos) == 1
                    payloadSideLen = round(str2double(label(1:xPos-1)));
                else
                    payloadSideLen = round(str2double(label));
                end
                label = sprintf('%dx%d', payloadSideLen, payloadSideLen);
        end
    end

    if ~isfinite(payloadSideLen) || payloadSideLen < 1 || payloadSideLen > nativeSideLen
        error('ccsdsTPCDecodeSoft:InvalidTPCCodeRate', ...
            'Unsupported TPCCodeRate="%s". Use native, 1/2, 2/3, or an integer side length <= 57.', ...
            char(string(rawRate)));
    end
end
