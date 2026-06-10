function codeword = bchEncode(inbits)
%SATCOM.INTERNAL.CCSDS.BCHENCODE BCH encoding compliant to CCSDS TC
%recommendation
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   CODEWORD = SATCOM.INTERNAL.CCSDS.BCHENCODE(INBITS) returns the (63,56)
%   BCH encoded output for the input bits, INBITS.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

inbitsClass = class(inbits);
% Generator polynomial for the (63,56) modified BCH code
genpoly = logical([1 0 1 0 0 0 1 1]);
parity = satcom.internal.dvbs.bchParity(inbits, genpoly);
% Rearrange parity
parity = flip(parity);
% Form the BCH encoder output code word and cast the type same as input
codeword = cast([inbits; ~parity], inbitsClass);

end