function code = rsencCore(msg, n, k, g, gftab1, gftab2)
%RSENCCORE core Reed-Solomon encoder
%   CODE = satcom.internal.ccsds.rsencCore(MSG, N, K, G, GFTAB1, GFTAB2)
%   does the Reed-Solomon encoding on MSG whose length is less than or
%   equal to K. MSG is of length K when there is no shortening. MSG is of
%   double datatype and each element in MSG contains RS symbol which is
%   8-bit word. CODE is the encoded codeword whose length is (N-K+S) where
%   S is the shortened message length. G is the coefficients of the
%   generator polynomial. These coefficients are in the polynomial form.
%   GFTAB1 is a table which converts the exponential form of symbols to
%   polynomial form and GFTAB2 is a table which converts polynomial form of
%   symbols to exponential form.
%
%   Note: This is an internal undocumented function and its API and/or 
%   functionality may change in subsequent releases. 

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen

parity = zeros(n-k, 1, 'int32');
for imsg = 1:length(msg)
    mulres = gfmul(bitxor(msg(imsg), parity(1)), g(2:end), n, gftab1, gftab2);
    parity(1:end-1) = bitxor(parity(2:end), mulres(1:end-1));
    parity(end) = mulres(end);
end
code = [msg(:); parity(:)];
end

function z = gfmul(x, y, n, E2P, P2E)
%GFMUL multiplication of GF elements in gf(2^m)
%   Z = GFMUL(X, Y, N, E2P, P2E) does multiplication of two GF arrays X and
%   Y. X and Y are double datatype. Any one of X or Y can be a scalar. If
%   both are vectors, then they both should be of same length. N =2^m-1.
%   E2P is a table which converts exponential form of Galois elements into
%   polynomial and P2E is a table which converts polynomial form of Galois
%   elements into exponential form.

if isscalar(x) || isscalar(y)
    if isscalar(x)
        x1 = x(ones(size(y)));
        y1 = y;
    else
        y1 = y(ones(size(x)));
        x1 = x;
    end
end
z=zeros(size(y1), 'int32');
nzs = x1~=0 & y1~=0;
r = z;
r(nzs) = mod(P2E(x1(nzs))+P2E(y1(nzs)), n);
z(r==0 & nzs) = 1;
z(r~=0) = E2P(r(r~=0));
end
