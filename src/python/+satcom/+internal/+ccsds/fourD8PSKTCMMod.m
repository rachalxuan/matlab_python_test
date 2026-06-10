function [outSymb, stateout, diffencstateout] = fourD8PSKTCMMod(inmsg, rEff, convencstatein, diffencstatein)
%SATCOM.INTERNAL.CCSDS.FOURD8PSKTCMMOD CCSDS TM based 4D 8PSK
%Trellis Coded Modulation
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   OUTSYMB = SATCOM.INTERNAL.CCSDS.FOURD8PSKTCMMOD(INMSG,REFF)
%   modulates INMSG using 4D 8PSK trellis coded modulation (4D 8PSK TCM)
%   based on efficiency of modulation, REFF. The function performs
%   differential encoding, convolutional encoding, constellation mapping,
%   8PSK modulation and pulse shaping as per section 3.3 in CCSDS
%   413.0-G-3 [1]. INMSG is a binary column vector and can be a message or a
%   codeword (in case of concatenated coding). REFF is in terms of
%   bits/channel-symbol and must be one of 2 | 2.25 | 2.5 | 2.75.
%
%   References:
%    [1] Bandwidth-Efficient Modulations. Report concerning Space Data
%    System Standards, CCSDS 413.0-G-3. Green Book, February 2018.
%       - section 3.3.
%
%   Examples:
%   Example 1:
%   % Generate 4D 8PSK trellis coded modulated samples for a modulation 
%   % efficiency of 2 bits/symbol 
%   inmsg = randi([0 1],10072,1); 
%   rEff = 2;
%   out = satcom.internal.ccsds.fourD8PSKTCMMod(inmsg,rEff);

%   Copyright 2020 The MathWorks, Inc.

%#codegen

% Determine the bits(index positions) to differentially encoded
% according to REFF value
switch rEff
    case 2
        ind = [1;5;8];
    case 2.25
        ind = [2;6;9];
    case 2.5
        ind = [3;7;10];
    otherwise % case 2.75
        ind = [4;8;11];
end

% Initialize
diffencstateout = diffencstatein; % Differential encoder states
stateout = convencstatein; % Convolutional encoder states
index = 1;

% 8-PSK Modulator initialization for natural mapping of symbols
pskmodSymbols = [1+0*1j; (1+1j)/sqrt(2); 0+1j; (-1+1j)/sqrt(2); -1+0*1j; ...
    (-1-1j)/sqrt(2); 0-1j; (1-1j)/sqrt(2)];
vecSym = complex(zeros(4*( round((length(inmsg))/(4*rEff)) ),1)); % Initializing memory for Output
numsym = length(inmsg)/(rEff*4);
alldata = zeros((rEff*4+1)*numsym, 1);
cnt = 0;
for iBit = 1:(4 * rEff):length(inmsg)
    
    % Process (4 * REFF) bits in each iteration
    dataIn = inmsg(iBit:(iBit+(4 * rEff)-1));

    % Differentially encode three bits
    [coderOut] = differentialCoder(dataIn(ind),diffencstateout);
    dataIn(ind) = coderOut;
    diffencstateout = coderOut;
    
    % Convolutionally encode first 3 bits of inmsg
    [xout, stateout] = eightPSKTrellisEnc(dataIn(1:3),stateout);
    
    % Constellation Mapper
    constellationMapIn = [xout; dataIn(:)];
    jj = iBit+cnt;
    alldata(jj:jj+4*rEff) = constellationMapIn;
    constellationMapOut = constellationMapper(constellationMapIn, rEff);
    cnt = cnt + 1;
    
    % 8PSK mapping
    outputSym = pskmodSymbols(constellationMapOut+1);
    
    % Save
    vecSym(index:index+3) = outputSym;
    index = index+4;
end
outSymb = vecSym;
end

function x = differentialCoder(w, states)
%DIFFERENTIALCODER Differential encoder
%   [X, STATES] = DIFFERENTIALCODER(W, STATES)Differentially encodes input
%   bits W using modulo-8 addition as per sec 3.3.3.2 in CCSDS 413.0-G-3 [1].

% Initialization
x = zeros(3,1,'int8');

% Modulo-8 adder operation
r0 = and(w(1),states(1));
r1 = (w(2) & states(2)) | (w(2)&r0) | (states(2) & r0);
x(1) = xor(w(1),states(1));
x(2) = xor( xor(w(2),states(2)), r0);
x(3) = xor( xor(w(3),states(3)), r1);

end

function [xout, states] = eightPSKTrellisEnc(xin, states)
%eightPSKTrellisEnc 4D-8PSK trellis encoder
%  [XOUT, STATES] = EIGHTPSKTRELLISENC(XIN, STATES, PREVOUT) performs
%  convolutional encoding on input bits, XIN as per section 3.3.3.3 in
%  CCSDS 413.0-G-3

xout = states(6);
states(6) = xor(xor(states(5), xin(1)), xout);
states(5) = xor(xor(xin(1), xin(2)),states(4));
states(4) = xor(states(3),xin(3));
states(3) = xor(states(2),xin(2));
states(2) = xor(states(1),xin(3));
states(1) = xout;

end

function z = constellationMapper(x,rEff)
% CONSTELLATIONMAPPER constellation mapper
%   Z = CONSTELLATIONMAPPER(X,REFF) maps input bits, X into symbols, Z
%   based on the modulation efficiency, Reff as per section 3.3.3.4 in
%   CCSDS 413.0-G-3. X is a column vector which contains bits whose size
%   should be an integral multiple of (rEff*4)+1.

%Initialization
z = zeros(4,1);

% Map x to z based on REFF Value
switch rEff
    case 2
        z(1) = (4*x(9))+(2*x(6))+x(2);
        z(2) = z(1) + ( (4*x(8)) + (2*x(4)) );
        z(3) = z(1) + ( (4*x(7)) + (2*x(3)) );
        z(4) = z(1) + ( (4* (x(8)+x(7)+x(5))) + (2*(x(4)+x(3)+x(1)))  );    
    case 2.25
        z(1) = (4*x(10))+(2*x(7))+x(3);
        z(2) = z(1) + ( (4*x(9)) + (2*x(5)) + x(1));
        z(3) = z(1) + ( (4*x(8)) + (2*x(4)) );
        z(4) = z(1) + ( (4* (x(9)+x(8)+x(6))) + (2*(x(5)+x(4)+x(2))) + x(1) );  
    case 2.5
        z(1) = (4*x(11))+(2*x(8))+x(4);
        z(2) = z(1) + ( (4*x(10)) + (2*x(6)) + x(2));
        z(3) = z(1) + ( (4*x(9)) + (2*x(5)) ) + x(1);
        z(4) = z(1) + ( (4* (x(10)+x(9)+x(7))) + (2*(x(6)+x(5)+x(3))) + (x(2)+x(1)) ); 
    otherwise % case 2.75
        z(1) = (4*x(12))+(2*x(9))+x(5);
        z(2) = z(1) + ( (4*x(11)) + 2*x(7) + x(3) );
        z(3) = z(1) + ( (4*x(10)) + 2*x(6) + x(2) );
        z(4) = z(1) + ( (4* (x(11)+x(10)+x(8))) + (2*(x(7)+x(6)+x(4))) + (x(3)+ x(2)+ x(1)) );  
end

% Express x modulo-8 format
z = mod(z,8);
end

% LocalWords:  OUTSYMB INMSG REFF inmsg randi Convolutionally DIFFERENTIALCODER XOUT
% LocalWords:  EIGHTPSKTRELLISENC XIN PREVOUT CONSTELLATIONMAPPER Reff
