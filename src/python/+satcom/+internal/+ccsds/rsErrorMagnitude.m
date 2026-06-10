function errmag = rsErrorMagnitude(lambda, syndrome, errloc, n, t, v, h, b, e2p, p2e)
%SATCOM.INTERNAL.CCSDS.RSERRORMAGNITUDE calculate the error magnitude for
%Reed-Solomon codes for a given error location
%
%   ERRMAG = SATCOM.INTERNAL.CCSDS.RSERRORMAGNITUDE(LAMBDA,SYNDROME,...
%   ERRLOC,N,T,V,H,B,E2P,P2E) calculates the error magnitude ERRMAG for
%   each error location specified in the vector ERRLOC. LAMBDA is the error
%   locator polynomial. SYNDROME is the syndrome polynomial. ERRLOC is a
%   vector containing non-zero error locations. N is the length of the codeword. T
%   is the maximum number of errors that the code can correct. V is the
%   number of errors that are detected in the code. H is the exponent of
%   the primitive element of the code using which generator polynomial is
%   constructed. Eg., CCSDS standard [1] has H to be 11. B is the offset of
%   the generator polynomial roots. Roots of the generator polynomial are
%   alpha^(H*(B+j)) where 'j' goes from zero to 2*T-1. E2P is a table which
%   converts exponential form of Galois elements into polynomial and P2E is
%   a table which converts polynomial form of Galois elements into
%   exponential form. ERRMAG is be a vector of length V.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   References:
%    [1] TM Synchronization and Channel Coding. Recommendation
%        for Space Data System Standards, CCSDS 131.0-B-3. Blue Book. Issue
%        3. Washington, D.C.: CCSDS, September 2017.
%
%   See also satcom.internal.ccsds.syndrome,
%   satcom.internal.ccsds.chienSearch

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

% For error magnitude calculation, find error evaluator, omega

OmegaVec = satcom.internal.ccsds.gfconv(lambda, syndrome, n, e2p, p2e);
OmegaActual = OmegaVec(1:2*t-1);
LamDerivTemp = lambda(2:2:end);
lambDeriv = [LamDerivTemp(:)'; zeros(1, length(LamDerivTemp))];
lambDeriv = lambDeriv(:); % This and above line is equivalent to inserting zeros between each element
errmagExp = zeros(v, 1, 'int32');
errmag = errmagExp;
for iErr = 1:v
    ele = mod(-h*errloc(iErr), n);
    if ele == 0
        ele = n;
    end
    omegaval = satcom.internal.ccsds.gfpolyeval(OmegaActual, ele, n, e2p, p2e);
    lamderivval = satcom.internal.ccsds.gfpolyeval(lambDeriv, ele, n, e2p, p2e);
    mulval = mod(ele*(b-1), n);
    if (mulval==0)
        mulval=n;
    end
    errmagExp(iErr) = mod(mulval+omegaval-lamderivval, n);
    if errmagExp(iErr) == 0
        errmagExp(iErr) = n;
    end
    errmag(iErr) = e2p(errmagExp(iErr));
end
end
