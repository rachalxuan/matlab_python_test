function encoded = tmldpcEncode(msg, g)
%SATCOM.INTERNAL.CCSDS.TMLDPCENCODE Encode with LDPC codes as per CCSDS TM
%synchronization and channel coding standard
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   ENCODED = SATCOM.INTERNAL.CCSDS.TMLDPCENCODE(MSG, G) does the LDPC
%   encoding operation on MSG and gives out ENCODED as specified in section
%   7 of CCSDS 131.0-B-3 TM Synchronization and channel coding standard.
%   Generator matrix is given by G. G contains only non-systematic columns
%   and only those rows which is the first row of block circulant matrices.
%   For more information on block circulant matrices in LDPC encoder see
%   [1].
%
%   References:
%
%   [1] TM Synchronization and Channel Coding - Summary of Concept and
%       rationale. Information report, CCSDS 130.1-G-3. Green Book. Issue
%       3. Washington, D.C.: CCSDS, June 2020.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

if coder.target('MATLAB')
    encoded = logical(satcom.internal.ccsds.cg_tmldpcEncodeCore_logical(logical(msg),logical(g)));
else
    encoded = logical(satcom.internal.ccsds.tmldpcEncodeCore(logical(msg),logical(g)));
end
end
