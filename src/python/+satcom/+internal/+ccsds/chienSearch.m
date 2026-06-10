function [errLocations, numErr] = chienSearch(lambda, n, v, t, h, e2p)
%SATCOM.INTERNAL.CCSDS.CHIENSEARCH search for error locations
%   [ERRLOCATIONS, NUMERR] = SATCOM.INTERNAL.CCSDS.CHIENSEARCH(LAMBDA, ...
%   N, V, T, H, E2P,) performs Chien search operation. LAMBDA is the error
%   locator polynomial typically found using Berlekamp algorithm. N is the
%   length of the code in the form of 2^M-1 where M is a positive integer.
%   V is the number of errors detected in previous steps of decoding. T is
%   the maximum number of errors that the code can correct. H is the
%   exponent of the primitive element of the code using which generator
%   polynomial is constructed. Eg., CCSDS standard [1] has H to be 11. E2P
%   is a table which converts exponential form of Galois elements into
%   polynomial form. ERRLOCATIONS is the actual error locations that are
%   found during Chien search. NUMERR is the actual number of errors that
%   are detected. If NUMERR is -1, then the code for which LAMBDA has been
%   calculated has uncorrectable errors.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

t2 = 2*t;
% Modified Chien search
polyval = int32(1); % gf(1,m,primpoly);
alphaReg = (h:h:h*v)'; %gf(GF_Table1(11:11:11*v), m, primpoly)';
errLocations=zeros(v, 1, 'int32');
deglambda = int32(0);
for ii = t2:-1:2
    if lambda(ii) > 0
        deglambda = ii-1;
        break;
    end
end
if (deglambda ~= v)
    numErr = int32(-1); % Decoding failure
    return;
end

newLambda = lambda(1:v+1);
numErr = int32(0);
for ii = n:-1:1
    for jj=2:v+1
        if newLambda(jj)~=0
            polyval = bitxor(polyval, e2p(newLambda(jj)));
        end
    end
    if polyval==0
        numErr = numErr + 1;
        errLocations(numErr) = int32(ii);
    end
    for jj = 2:v+1
        if newLambda(jj)~=0
            newLambda(jj) = mod(newLambda(jj) + alphaReg(jj-1), n);
            if newLambda(jj)==0
                newLambda(jj)=n;
            end
        end
    end
    polyval = int32(1);
end

% Decoding failure if one of the following conditions is met:
% (1) lambda(Z) has no roots in this field
% (2) Number of roots not equal to degree of lambda(Z)
if numErr ~= deglambda
    numErr = int32(-1);
end
if nnz(errLocations) ~= v
    numErr = int32(-1);
end
end
