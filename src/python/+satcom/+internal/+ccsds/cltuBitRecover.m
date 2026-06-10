function bits = cltuBitRecover(rxData,cfg,DecodingMode,threshold,nVar)
%satcom.internal.ccsds.cltuBitRecover Search for start sequence and bit
%recovery from CLTUs
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   BITS = satcom.internal.ccsds.cltuBitRecover(RXDATA,CFG,DECODINGMODE,
%   THRESHOLD,NVAR) returns the recovered bits, BITS, from the demodulated
%   soft symbols, RXDATA, for a given configuration, CFG. BITS is a
%   cell array of one or more column vectors based on the number of CLTUs
%   present in RXDATA. 
%
%   DECODINGMODE specifies the decoding mode used in the decoding of BCH
%   codewords. THRESHOLD specifies the threshold value of normalized
%   correlation metric required for the detection of start sequence. NVAR
%   specifies the noise variance used to scale the soft bits. THRESHOLD and
%   NVAR is used when the channel coding is LDPC.
%
%   This internal function performs the search for start sequence and bit
%   recovery from CLTUs. Bit recovery from CLTUs includes channel decoding
%   and derandomization (optional). Codeword rejection and tail sequence
%   detection is also done as part of this internal function. If the
%   decoder has any decoding failure or any uncorrected errors in the
%   decoded output, codeword will be rejected and the search for the start
%   sequence will be started again at the beginning of the uncorrected
%   codeword. For LDPC, If tail sequence is present, then the search for
%   tail sequence is used to detect the end of CLTU.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

rxSymb = rxData;
coder.varsize('rxSymb',[inf inf]);
bits = {};
while (length(rxSymb)>80)
    % Start sequence detection
    [cws,isCLTU,index] = sequenceDetector(rxSymb,cfg,DecodingMode,threshold);
    rxSymb = rxSymb(index+1:end,1);
    if isCLTU
        % Decode CLTUs and recover the transfer frames
        [decbits,startSeqIdx] = cltuDecode(cws,cfg,DecodingMode,...
            threshold,nVar);
        rxSymb = rxSymb(startSeqIdx+1:end,1);
        bits{end+1} = int8(decbits);
    else
        rxSymb = [];
    end
end

end

function [codewords,isCLTU,index] = sequenceDetector(rxSymb,cfg,DecodingMode,...
    threshold)
% Start sequence detection in the received symbols 

codewords = [];
index = 0;
if strcmpi(cfg.ChannelCoding,'BCH')
    
    startSeq1 = [1 1 1 0 1 0 1 1 1 0 0 1 0 0 0 0]';
    startSeq2 = double(~startSeq1);
    isCLTU = false;
    % Search for start sequence
    for m = 0:length(rxSymb)-16
        if strcmpi(cfg.Modulation,'PCM/PSK/PM')&& strcmpi(cfg.PCMFormat,'NRZ-M')
            llr = satcom.internal.ccsds.lineDecode(rxSymb(m+1:end,1),...
                cfg.PCMFormat);
            data = double(llr > 0);
        else
            data = double(rxSymb(m+1:end,1)>0);
        end
        % Detect start sequence by comparing the bits with known start
        % sequence and resolve the data ambiguity (sense of '1' and '0')
        % by comparing the bits with inverse of start sequence
        temp = data(1:16);
        diff1 = sum(abs(temp-startSeq1));
        diff2 = sum(abs(temp-startSeq2));
        n = length(DecodingMode);
        index = m+16;
        if (diff1 < 2 && strncmpi(DecodingMode,'Error Correcting',n))||...
                (diff1 == 0 && strncmpi(DecodingMode,'Error Detecting',n))
            codewords = data(17:end,1);
            isCLTU = true;
            break;
        elseif (diff2 < 2 && strncmpi(DecodingMode,'Error Correcting',n))||...
                (diff2 == 0 && strncmpi(DecodingMode,'Error Detecting',n))
            codewords = double(~data(17:end,1));
            isCLTU = true;
            break;
        end
    end
else
    
    isCLTU = false;
    startSeq = [0 0 0 0 0 0 1 1 0 1 0 0 0 1 1 1 0 1 1 1 0 1 1 0 1 1 0 0 0 1 1....
        1 0 0 1 0 0 1 1 1 0 0 1 0 1 0 0 0 1 0 0 1 0 1 0 1 1 0 1 1 0 0 0 0]';
    prb = 2*startSeq-1;
    temp = complex(zeros(64,1));
    
    % Search for start sequence
    for m = 0:length(rxSymb)-64    
        if strcmpi(cfg.Modulation,'PCM/PSK/PM')&& strcmpi(cfg.PCMFormat,'NRZ-M')
            rxData = satcom.internal.ccsds.lineDecode(rxSymb(m+1:end,1),...
                cfg.PCMFormat);
        else 
            rxData = rxSymb(m+1:end,1);
        end
        % Detect start sequence by checking the correlation with known
        % start sequence and resolve the data ambiguity (sense of '1' and
        % '0') by analyzing the correlation metric
        temp(1:end) = rxData(1:64,1);
        metric = xcorr(temp,prb,'normalized',0);
        detmet = round(metric*1000)/1000;
        index = m+64;
        if detmet >= threshold
            codewords = rxData(65:end,1);
            isCLTU = true;
            break;
        elseif (-1*detmet) >= threshold
            codewords = -1*rxData(65:end,1);
            isCLTU = true;
            break;
        end
    end
end

end

function [bits,startSeqIdx] = cltuDecode(codewords,cfg,...
    DecodingMode,threshold,nVar)
% Decodes the CLTU from the codewords and returns the index for the
% remaining symbols. Search for the next CLTU is started using the symbols
% from this index point. Decoding CLTU includes channel decoding,
% derandomization, codeword rejection and tail sequence detection.

output = [];
startSeqIdx = 0;
if strcmpi(cfg.ChannelCoding,'BCH')
    % BCH decoding
    cwLength = 64;
    msgLength = 56;
    numCodewords = floor(length(codewords)/cwLength);
    out = zeros(msgLength*numCodewords,1);
    for iCodeword = 1 : numCodewords
        cw = double(codewords((iCodeword-1)*cwLength+1:iCodeword*cwLength,1));
        code = [cw(1:msgLength); ~cw(msgLength+1:end-1)];
        if strncmpi(DecodingMode,'Error Correcting',length(DecodingMode))
            % BCH Error Correction Mode
            [u,cnumerr] = ccsdsBCHDecode(code);
            % Decoded bits in each codeword
            out((iCodeword-1)*msgLength+1:iCodeword*msgLength) = u;
            if cnumerr < 0
                output = out(1:(iCodeword-1)*msgLength);
                startSeqIdx = (iCodeword-1)*cwLength;
                break;
            else
                output = out;
                startSeqIdx = (iCodeword)*cwLength;
            end
        else
            % BCH Error Detection Mode
            u = cw(1:msgLength);
            out((iCodeword-1)*msgLength+1:iCodeword*msgLength) = u;
            parityActual = ~cw(msgLength+1:end-1);
            codeword = satcom.internal.ccsds.bchEncode(u);
            parityExpected = ~codeword(msgLength+1:end);
            % Compare the received parity bits with calculated parity bits
            if ~isequal(parityExpected,parityActual)
                output = out(1:(iCodeword-1)*msgLength);
                startSeqIdx = (iCodeword-1)*cwLength;
                break;
            else
                output = out;
                startSeqIdx = (iCodeword)*cwLength;
            end
        end
    end
    % Optional derandomization of the TC transfer frame
    if cfg.HasRandomizer
        bits = satcom.internal.ccsds.randomizer(output);
    else
        bits = output;
    end   
else
    
    % LDPC decoding
    cwLength = cfg.LDPCCodewordLength;
    messageLength = 0.5*cwLength; % since code rate is 1/2
    numCodewords = floor(length(codewords)/cwLength);
    out = zeros(messageLength*numCodewords,1);
    % Load LDPC parity check matrix and tail sequence
    matData = coder.load('+satcom/+internal/+ccsds/tcParityCheckMatrix.mat');
    if cwLength == 128
        H = coder.const(matData.I1);
    else
        H = coder.const(matData.I2);
    end
    % Parity check matrix from the row and column indices of the 1s
    H1 = zeros(cwLength-messageLength,cwLength);
    for kk = 1:length(H)
        H1(H(kk,1),H(kk,2))= 1;
    end
    % Create a binary LDPC encoder System object, ldpcEncoder
    ldpcDecoder = comm.LDPCDecoder(H,'DecisionMethod',...
        'Hard decision','IterationTerminationCondition',...
        'Parity check satisfied','OutputValue','Whole codeword');
    % Tail sequence 
    prb = 2*(matData.TailSeq)-1;
    
    cw = zeros(cwLength,1);
    for iCodeword = 1 :numCodewords
        cw(1:end) = (1/nVar)*codewords((iCodeword-1)*cwLength+1:iCodeword*cwLength,1);
        % LDPC decoder
        u = ldpcDecoder(cw);
        % Decoded bits in each codeword
        out((iCodeword-1)*messageLength+1:iCodeword*messageLength) = double(~(u(1:messageLength)));
        % If a tail sequence is transmitted, detecting its presence by
        % using a correlator
        temp = complex(zeros(cwLength,1));
        if (cfg.HasTailSequence) && (cfg.LDPCCodewordLength == 128)
            temp(1:end) = (1/nVar)*codewords((iCodeword-1)*cwLength+1:iCodeword*cwLength,1);
            % Detect tail sequence by checking the correlation with known
            % tail sequence and resolve the data ambiguity by analyzing
            % the correlation metric
            metric = xcorr(temp,prb,'normalized',0);
            detmet = round(metric*1000)/1000;
            if abs(detmet) >= threshold
                output = out(1:(iCodeword-1)*messageLength);
                startSeqIdx = (iCodeword)*cwLength;
                break;
            else
                output = out;
                startSeqIdx = (iCodeword)*cwLength;
            end
        else
            % Check for any decoder failure and codeword rejection
            u1 = u> 0;
            W = mod(H1*u1,2);
            if any(W)
                output = out(1:(iCodeword-1)*messageLength);
                startSeqIdx = (iCodeword-1)*cwLength;
                break;
            else
                output = out;
                startSeqIdx = (iCodeword)*cwLength;
            end
        end
    end
    % Derandomization of the TC transfer frame
    if isempty(output)
        bits = [];
    else
        bits = satcom.internal.ccsds.randomizer(output(:,1));  
    end
end    
end

function [decmsg,cnumerr] = ccsdsBCHDecode(inBits)
% BCH decoding 

e2p = int32([2 4 8 16 32 3 6 12 24 48 35 5 10 20 40 19 38 15 ...
    30 60 59 53 41 17 34 7 14 28 56 51 37 9 18 36 11 22 44 27 54 47 29 ...
    58 55 45 25 50 39 13 26 52 43 21 42 23 46 31 62 63 61 57 49 33 1]);
p2e = int32([0 1 6 2 12 7 26 3 32 13 35 8 48 27 18 4 24 33 16 ...
    14 52 36 54 9 45 49 38 28 41 19 56 5 62 25 11 34 31 17 47 15 23 53 ...
    51 37 44 55 40 10 61 46 30 50 22 39 43 29 60 42 21 20 59 57 58]);

% Calculate syndrome
t = int32(1);
b = int32(63);
n = int32(63);
syn = bchSyndrome(inBits, n, t,b, e2p, p2e);

% BCH decoding
decoded = inBits;
cnumerr = int32(0);
if nnz(syn) ~= 0
    % BCH Berlekamp algorithm.
    [errLocatorPoly, L] = comm.internal.bch.coreBerlekamp(syn, n, t, e2p, p2e);   
    % Error location search from the error locator polynomial.
    [errPos, cnumerr] = comm.internal.bch.bchErrSearch(errLocatorPoly, n, t, L, e2p, p2e);
    if cnumerr > 0
        decoded(errPos(1:L)) = xor(1, decoded(errPos(1:L)));
    end
end
decmsg = double(decoded(1:56));

end

function syn = bchSyndrome(inBits, n, t,b, e2p, p2e)
% calculates the syndrome for inBits.

t2 = 2*t;
syn = zeros(t2, 1, 'int32');
syntemp = syn;
for jj = (n-1):-1:0 %jj would be the power of each bit.
    if jj == 0
        eleidx = n; % rotating for proper usage of power notation.
    else
        eleidx = jj;
    end
    if inBits(n-jj)
        for ii = b:b+t2-1
            eleVal = mod(ii*eleidx,n);
            if eleVal==0
                eleVal = int32(n);
            end
            syntemp(ii-b+1) = bitxor(syntemp(ii-b+1), e2p(eleVal));
        end
    end
end

for ii = b:b+t2-1
    if syntemp(ii-b+1)== 1
        syn(ii-b+1) = int32(n);
    elseif syntemp(ii-b+1)~=0
        syn(ii-b+1) = p2e(syntemp(ii-b+1));
    end
end
end