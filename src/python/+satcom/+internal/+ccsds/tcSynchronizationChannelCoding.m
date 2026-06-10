function encData = tcSynchronizationChannelCoding(bits,cfg)
%SATCOM.INTERNAL.CCSDS.TCSYNCHRONIZATIONCHANNELCODING CCSDS TC
%synchronization and channel coding sublayer operations
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   ENCDATA = SATCOM.INTERNAL.CCSDS.TCSYNCHRONIZATIONCHANNELCODING(BITS,CFG)
%   returns the bits after randomization (optional), channel coding, and
%   CLTU generation for a given configuration, CFG, and information bits,
%   BITS.

%   Copyright 2020 The MathWorks, Inc.

% References
% [1] TC Synchronization and Channel Coding. Recommendation for Space Data
% System Standards, CCSDS 231.0-B-3. Blue Book. Issue 3. Washington, D.C.:
% CCSDS, September 2017.

%#codegen

% Fill data and randomization
if strcmpi(cfg.ChannelCoding,'BCH')
    % Adding fill data
    inbitsTemp = addFillData(cfg.ChannelCoding,bits);
    % Optional randomization of the TC transfer frame(s)
    if cfg.HasRandomizer
        data = satcom.internal.ccsds.randomizer(inbitsTemp);
    else
        data = inbitsTemp;
    end
else
    % Adding fill data
    inbitsTemp = addFillData(cfg.ChannelCoding,bits,cfg.LDPCCodewordLength);
    % Randomize the TC transfer frame(s)
    data = satcom.internal.ccsds.randomizer(inbitsTemp);
end

% BCH or LDPC channel coding
if strcmpi(cfg.ChannelCoding,'BCH')
    numCodewords = ceil(length(data)/56);
    codewords = zeros(64*numCodewords,1);
    for ii = 1 : numCodewords
        u = data((ii-1)*56+1:ii*56);
        % BCH encoding
        cw = ccsdsBCHEncode(u);
        % Adding filler bit in the BCH codewords
        codewords((ii-1)*64+1:ii*64) = [cw; 0];
    end
    % CLTU generation
    encData = generateCLTU(cfg.ChannelCoding,codewords);
    
else
    
    cwLength = cfg.LDPCCodewordLength;
    messageLength = 0.5*cwLength; % since code rate is 1/2
    numCodewords = length(data)/messageLength;
    codewords = zeros(cwLength*numCodewords,1);
    
    % Load LDPC parity check matrix
    parityMatrix = coder.load('+satcom/+internal/+ccsds/tcParityCheckMatrix.mat');
    if cwLength == 128
        H = coder.const(parityMatrix.I1);
    else
        H = coder.const(parityMatrix.I2);
    end
    
    % Create a binary LDPC encoder System object, ldpcEncoder
    ldpcEncoder = comm.LDPCEncoder(H);
    u = zeros(messageLength,1);
    for ii = 1 :numCodewords
        u(1:end) = data((ii-1)*messageLength+1:ii*messageLength);
        % LDPC encoding
        cw = ldpcEncoder(u);
        % LDPC Codewords
        codewords((ii-1)*cwLength+1:ii*cwLength) = cw;
    end
    % CLTU generation
    if cwLength == 128
        encData = generateCLTU(cfg.ChannelCoding,codewords,cfg.HasTailSequence);
    else
        encData = generateCLTU(cfg.ChannelCoding,codewords);
    end
end

end

function cltu = generateCLTU(channelCoding,codewords,varargin)
% CLTU generation based on the channel coding 

if strcmpi(channelCoding,'BCH')
    
    % 16 bit start sequence
    startSeq = [1 1 1 0 1 0 1 1 1 0 0 1 0 0 0 0]';
    % 64 bit tail sequence
    tailSeq = [1 1 0 0 0 1 0 1 1 1 0 0 0 1 0 1 1 1 0 0 0 1 0 1 ...
        1 1 0 0 0 1 0 1 1 1 0 0 0 1 0 1 1 1 0 0 0 1 0 1 ...
        1 1 0 0 0 1 0 1 0 1 1 1 1 0 0 1]';
    
    % CLTU generation
    cltu = [startSeq; codewords; tailSeq];
    
else
    
    % 64 bit start sequence
    startSeq = [0 0 0 0 0 0 1 1 0 1 0 0 0 1 1 1 0 1 1 1 0 1 1 0 ...
        1 1 0 0 0 1 1 1 0 0 1 0 0 1 1 1 0 0 1 0 1 0 0 0 ...
        1 0 0 1 0 1 0 1 1 0 1 1 0 0 0 0]';
    % 128 bit tail sequence
    tailSeq = [0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 ...
        0 1 0 1 0 1 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 ...
        1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 0 1 0 1 0 1 0 1 ...
        0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 ...
        0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 ...
        0 1 0 1 0 1 0 1]';
    
    % CLTU generation 
    hasTailSequence = false;
    if nargin > 2
        hasTailSequence = varargin{1};
    end

    if hasTailSequence
        cltu = [startSeq; codewords; tailSeq];
    else
        cltu = [startSeq; codewords];
    end
end
end

function out = addFillData(channelCoding, inbits, varargin)
% Appending fill bits on transfer frame(s) to create integral number of
% codewords
if nargin > 2
    cwLength = varargin{1};
else
    cwLength = 128;
end

if strcmpi(channelCoding, 'BCH')
    % Number of octets in BCH input message 
    codewordOctets = 7;
elseif strcmpi(channelCoding, 'LDPC') && (cwLength == 128)
    % Number of octets in LDPC input message with a codeword length of 128
    codewordOctets = 8;
else
    % Number of octets in LDPC input message with a codeword length of 512
    codewordOctets = 32;
end

% Number of octets in the data
msgOctets = ceil(length(inbits)/8);
if mod(msgOctets, codewordOctets) ~= 0
    fillOctets = codewordOctets - mod(msgOctets, codewordOctets);
else
    fillOctets = 0;
end

if fillOctets ~= 0
    fillData = repmat([0 1 0 1 0 1 0 1], 1, fillOctets);
    out = [double(inbits); fillData'];
else
    out = double(inbits);
end

end

function codeword = ccsdsBCHEncode(inbits)
% BCH encoding compliant to CCSDS TC recommendation

inbitsClass = class(inbits);
% Generator polynomial for the (63,56) modified BCH code
genpoly = logical([1 0 1 0 0 0 1 1]);
parity = satcom.internal.dvbs.bchParity(inbits, genpoly);
% Rearrange parity
parity = flip(parity);
% Form the BCH encoder output codeword and cast the type same as input
codeword = cast([inbits; ~parity], inbitsClass);

end