function encoded = tmldpcEncodeCore(msg, g)
%SATCOM.INTERNAL.CCSDS.TMLDPCENCODECORE Encode with LDPC codes as per CCSDS
%TM synchronization and channel coding standard
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   ENCODED = SATCOM.INTERNAL.CCSDS.TMLDPCENCODECORE(MSG, G) does the LDPC
%   encoding operation on MSG and gives out ENCODED as specified in section
%   8 of CCSDS green book [1]. Generator matrix is given by G. G contains
%   only non-systematic columns and only those rows which is the first row
%   of block circulant matrices. For more information on block circulant
%   matrices in LDPC encoder see [1].
%
%   References: 
%
%   [1] TM Synchronization and Channel Coding - Summary of Concept and
%       rationale. Information report, CCSDS 130.1-G-3. Green Book. Issue
%       3. Washington, D.C.: CCSDS, June 2020.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

s = size(g);
if s(1) == 14 % k = 7154
    k = 7154;
    tbits = [zeros(18,1,'logical');msg(:)];
else
    k = s(1)*s(2)/8;
    tbits = logical(msg);
end

numElements = round(k/s(1)); % Function round is used to deal with approximations done by MATLAB. Else, this value should always be an integer
numColumns = round(s(2)/numElements);
numRows = s(1);
parityBits = zeros(s(2),1,'logical');
for iRow = 1:numRows
    for iCol = 1:numColumns
        currentColumnIdx = (iCol-1)*numElements+1:iCol*numElements;
        currentParity = parityBits(currentColumnIdx);
        currentG = g(iRow, currentColumnIdx)';
        for iEle = 1:numElements
            currentBit = tbits(iEle+(iRow-1)*numElements);
            if currentBit
                currentParity = xor(currentG,currentParity);
            end
            currentG = circshift(currentG,1);
        end
        parityBits(currentColumnIdx) = currentParity;
    end
end

if s(1) == 14
    encoded = [msg;parityBits;false;false];
else
    encoded = [msg;parityBits];
end
end