function idx = tmTurboInterleavingIndices(k)
%SATCOM.INTERNAL.CCSDS.TMTURBOINTERLEAVINGINDICES Interleaving indices for
%Turbo codes of CCSDS TM synchronization and channel coding standard
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   IDX = SATCOM.INTERNAL.CCSDS.TMTURBOINTERLEAVINGINDICES(K) computes the
%   interleaving indices, IDX that are needed for the turbo codes specified
%   in CCSDS 131-0.B-3 TM synchronization and channel coding standard [1].
%   K is the number of bits in one information block.
%
%   References: 
%
%   [1] TM Synchronization and Channel Coding. Recommendation
%       for Space Data System Standards, CCSDS 131.0-B-3. Blue Book. Issue
%       3. Washington, D.C.: CCSDS, September 2017.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

k1 = 8;
k2 = k/k1;
p = [31;37;43;47;53;59;61;67];
% Following algorithm is defined in section 6.3.g.2 of CCSDS TM
% synchronization and channel coding standard (Page 6-4 of 131.0-B-3 [1])
s = (1:k)';
m = mod(s-1,2);
i = floor((s-1)/(2*k2));
j = floor((s-1)/2) - i*k2;
t = mod(19*i+1,k1/2);
q = mod(t, 8)+1;
c = mod(p(q).*j + 21*m,k2);
idx = 2*(t + (c*k1/2) + 1) - m;
end
