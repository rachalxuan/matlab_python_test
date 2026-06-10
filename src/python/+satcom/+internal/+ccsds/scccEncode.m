function encoded = scccEncode(bits,ACMFormat,m,I,InterleavingIndices,SCCCPuncturePattern2)
%satcom.internal.ccsds.scccEncode Serial concatenated convolutional encoder
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   ENCODED = satcom.internal.ccsds.scccEncode(BITS, ACMFORMAT, M, I,
%   INTERLEAVINGINDICES, SCCCPUNCTUREPATTERN2) does the serial concatenated
%   convolutional coding operation on input bits, BITS. ACMFORMAT is the
%   ACM format of the waveform that is defined in [1]. M is the number of
%   bits per modulation symbol. I is the interleaver length.
%   INTERLEAVINGINDICES is the required interleaving indices for
%   interleaving the output bits from the outer convolutional encoder.
%   SCCCPUNCTUREPATTERN2 is the second puncturing pattern that is applied
%   to the inner convolutional encoder that is applied to the systematic
%   bits. ENCODED is a column vector of bits after encoding.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington,
%       D.C.: CCSDS, March 2012.

%   Copyright 2020-2021 The MathWorks, Inc.

%#codegen

% Following values are taken from table 4-3 from CCSDS flexible advanced
% coding and modulation scheme for high rate telemetry applications
% standard [1].
P_Values = [7558;5758;4690;3849;3000;1810;7830;8458;5698;...
    4361;3082;1443;7918;6659;5349;3885;2520;8745;7363;5823;4303;...
    2698;9234;7558;6093;4685;3171];
Delta_Values = [1084;4684;7912;10913;13922;17992;9092;11344;...
    16624;21201;25720;30599;20884;25383;29933;34997;39962;30137;...
    35119;40619;45739;51304;40808;46444;51869;56877;62351];
PVal =  P_Values(ACMFormat);
Delta = Delta_Values(ACMFormat);
SCCCPuncturePattern1 = [1;1;1;0];
SCCCTrellisStructure = poly2trellis(3,[7,5],7);

% Outer convolutional code
[p,s] = convenc(bits,SCCCTrellisStructure,SCCCPuncturePattern1);

% Terminate the outer convolutional code properly
fstate = int2bit(s,2);
b1 = xor(fstate(1),fstate(2));
p = [p;b1;fstate(2);fstate(1)]; % As the puncture pattern is [1;1;1;0], only three bits are appended for terminating 2 stage register

% Interleaving
u1 = p(InterleavingIndices);

% Inner convolutional encoder
[c1,s1]  = convenc(u1,SCCCTrellisStructure);

% Terminate the inner convolutional code properly
fstate = int2bit(s1,2);
b1 = xor(fstate(1),fstate(2));
c1 = [c1;b1;fstate(2);fstate(1);fstate(1)]; % 4 bits are appended to terminate the trellis

tc1 = reshape(c1,2,I+2)';
c1s = tc1(1:end-2,1); % Systematic part of the encoder output
c1p = tc1(1:end-2,2); % Parity part of the encoder output
p1s = c1s(SCCCPuncturePattern2); % Puncture the systematic part

% Puncture the parity part
e = 1;
p1p = zeros(PVal-2,1);
cnt = 1;
for idx = 1:I
    if e>0
        p1p(cnt) = c1p(idx);
        cnt = cnt + 1;
    else
        e = e + I;
    end
    e = e - Delta;
end

% Merge the systematic part and parity part
allBitsVec = [p1s;tc1(end-1:end,1);p1p;tc1(end-1:end,2)];

% Row column interleaver
reg = reshape(allBitsVec,8100,m);
interleaveRegister = reg.';
encoded = interleaveRegister(:);
end

% LocalWords:  ACMFORMAT INTERLEAVINGINDICES SCCCPUNCTUREPATTERN ACM
