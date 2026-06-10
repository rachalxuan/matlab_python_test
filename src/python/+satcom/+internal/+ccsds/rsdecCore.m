function [ccode, errmag, v] = rsdecCore(code, n, k, s, h, b, e2p, p2e)
%SATCOM.INTERNAL.CCSDS.RSDECCORE core Reed-Solomon decoder
%   [CCODE, ERRMAG, V] =
%   SATCOM.INTERNAL.CCSDS.RSDECCORE(CODE,N,K,S,H,B,E2P,P2E) does the core
%   RS decoding on the received code CODE. N is the length of the code in
%   the form of 2^M-1 where M is a positive integer. K is the number of RS
%   symbols in the message. S is the shortened message length which is
%   greater than zero and less than or equal to K. H is the exponent of the
%   primitive element of the code using which generator polynomial is
%   constructed. Eg., CCSDS standard [1] has H to be 11. B is the offset of
%   the generator polynomial roots. Roots of the generator polynomial are
%   alpha^(H*(B+j)) where 'j' goes from zero to 2*t-1 where 't' is the
%   maximum number of errors that the code can correct. E2P is a table
%   which converts exponential form of Galois elements into polynomial form
%   and P2E is a table which converts polynomial form of Galois elements
%   into exponential form. V is the number of detected errors in the CODE.
%   If V is -1, then CODE has uncorrectable errors. CCODE is the corrected
%   code. CCODE has the same length as that of CODE. If V is -1, then CCODE
%   is same as that of CODE.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   References:
%    [1] TM Synchronization and Channel Coding. Recommendation
%        for Space Data System Standards, CCSDS 131.0-B-3. Blue Book. Issue
%        3. Washington, D.C.: CCSDS, September 2017.

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

% Note that most of the processing is in power form representation of
% elements.

t2 = n-k;
t = floor(t2/2); % When n-k is odd then floor value is taken.
codeFlipped = [fliplr(code(:)') zeros(1, k-s, 'int32')];
genpolyroots = mod(h*(b:b+t2-1), n);
syn = satcom.internal.ccsds.syndrome(codeFlipped, n, genpolyroots, e2p, p2e);
synflipped = fliplr(syn(:)');
[lambda, L] = comm.internal.bch.coreBerlekamp(synflipped,n,t,e2p,p2e); % 'lambda' is in power form
[errLocations, v] = satcom.internal.ccsds.chienSearch(lambda, n, double(L), t, h, e2p);
if (any(errLocations>(n-k+s)) && v>0)
    v = int32(-1);
end
errmag = int32(0);
if v>0 % Only when errors can be calculated, calculate error magnitude
    errmag = satcom.internal.ccsds.rsErrorMagnitude(lambda, synflipped, errLocations, n, t, v, h, b, e2p, p2e);
    codeFlipped(errLocations) = bitxor(codeFlipped(errLocations)', errmag);
end
ccode = fliplr(codeFlipped(1:n-k+s))';
end
