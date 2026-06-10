function c = gfconv(a, b, n, e2p, p2e)
%SATCOM.INTERNAL.CCSDS.GFCONV polynomial multiplication of two GF arrays
%   C = SATCOM.INTERNAL.CCSDS.GFCONV(A,B,N,E2P,P2E) does the polynomial
%   multiplication of 2 polynomials whose coefficients are GF arrays A and
%   B. This operation is equivalent to convolution of the GF arrays A and
%   B. Each element of A and/or B is from GF(2^m) where m is a positive
%   integer. N is 2^m-1. E2P is a table which converts exponential form of
%   Galois elements into polynomial form and P2E is a table which converts
%   polynomial form of Galois elements into exponential form. C is the
%   result of the convolution of A and B. C is be a vector of length
%   length(A)+length(B)-1.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

alength = length(a);
blength = length(b);
clength = alength+blength-1;
c = zeros(clength,1, 'int32');
afull = [zeros(clength-alength,1, 'int32'); a(:)];
bfull = flipud([zeros(clength-blength,1, 'int32'); b(:)]); % b is flipped and shifted in each iteration for convolution

convEle = int32(0);
for iconv = 1:clength
    for iEle = 1:clength
        if (afull(iEle)~=0 && bfull(iEle)~=0)
            mulEle = mod(afull(iEle)+bfull(iEle), n);
            if (mulEle==0)
                mulEle=n;
            end
            convEle = comm.internal.bch.gfAdd(convEle, mulEle, n, e2p, p2e);
        end
    end
    c(iconv) = convEle;
    bfull = circshift(bfull, 1);
    convEle = int32(0);
end
end
