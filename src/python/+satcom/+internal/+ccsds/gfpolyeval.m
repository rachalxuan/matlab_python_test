function polyeval = gfpolyeval(poly, ele, n, e2p, p2e)
%SATCOM.INTERNAL.CCSDS.GFPOLYEVAL evaluate a polynomial with GF
%coefficients
%
%   POLYEVAL = SATCOM.INTERNAL.CCSDS.GFPOLYEVAL(POLY,ELE,N,E2P,P2E)
%   evaluates the polynomial whose coefficients are GF elements specified
%   in POLY. The function evaluates the polynomial for the element ELE and
%   returns the result in POLYEVAL. Each element of POLY and ELE are
%   GF(2^m) elements, where m is a positive integer. POLY contains
%   coefficients of the polynomial in increasing order of degree. N is
%   2^m-1. E2P is a table which converts exponential form of Galois
%   elements into polynomial form and P2E is a table which converts
%   polynomial form of Galois elements into exponential form.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

% Each coefficient in 'poly' is in ascending powers starting with z^0

polyeval = poly(1);
if ele~=0
    for iEle = 1:length(poly)-1
        if poly(iEle+1) ~= 0
            mulval = mod(poly(iEle+1)+iEle*ele,n);
            if (mulval==0)
                mulval=n;
            end
            if polyeval~=0
                polyeval = bitxor(e2p(polyeval), e2p(mulval));
                if polyeval ~= 0
                    polyeval = p2e(polyeval);
                    if polyeval == 0
                        polyeval = n;
                    end
                end
            else
                polyeval = mulval;
            end
        end
    end
end
end
