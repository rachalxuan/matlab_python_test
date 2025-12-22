function [initsym,tfsym,finalsym] = HelperCCSDSFACMTFSynchronize(sym,asm,tflen)
%HelperCCSDSFACMTFSynchronize Transfer frame synchronization
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   [INITSYM,TFSYM,FINALSYM] = HelperCCSDSFACMTFSynchronize(SYM,ASM,TFLEN)
%   arranges SYM into transfer frames with each transfer frame in a column.
%   INITSYM contains the initial symbols just before the first transfer
%   frame starts. TFSYM contains the transfer frames with each column of
%   length TFLEN and number of columns equal to the number of transfer
%   frames in SYM. FINALSYM contains the symbols from the end of the last
%   transfer frame in SYM to the end of symbols.

%   Copyright 2021 The MathWorks, Inc.

framelen = length(sym);
fullTFLen = tflen + length(asm); % Full TF length including ASM length
[peakpPos, ~, peakDetected] = FrameCorrelate(sym, asm);
initsym = sym(1:peakpPos-1);
numTF = floor((framelen-peakpPos+1)/fullTFLen);
tfsym = zeros(fullTFLen,numTF);
if numTF~=0
    tfsym = reshape(sym(peakpPos - 1 + (1:numTF*fullTFLen)),fullTFLen,numTF);
    finalsym = sym((peakpPos + numTF*fullTFLen):end);
else
    finalsym = sym(peakpPos:end);
end
if ~peakDetected
    finalsym = sym(:);
    tfsym = zeros(0,1);
    initsym = zeros(0,1);
end
end

function [PeakPos, maxcorr, peakDetected] = FrameCorrelate(rxData, syncMarker)

% Correlation for frame synchronization method
numASMThreshold = 27; % If greater than these many ASM bits are matched, then correlation work stops
tflen = length(rxData);
numASMBits = length(syncMarker);
fOfSiYi = zeros(numASMBits, 1);
SMu = -Inf(tflen-numASMBits+1, 1);
peakDetected = false;
for iBit = 1:tflen-numASMBits+1
    yi = rxData(iBit:iBit+numASMBits-1);
    numASMMatched = 0;
    for iCorrelation = 1:numASMBits
        if sign(syncMarker(iCorrelation)) ~= sign(yi(iCorrelation))
            fOfSiYi(iCorrelation) = -1*abs(yi(iCorrelation));
        else
            numASMMatched = numASMMatched + 1;
        end
        if numASMMatched > numASMThreshold
            peakDetected = true;
        end
    end
    SMu(iBit) = sum(fOfSiYi); % See equations in page 9-12 in CCSDS 130.1-G-2
    fOfSiYi = zeros(numASMBits, 1);
    if peakDetected
        break
    end
end
[maxcorr,PeakPos] = max(SMu); % See equations in page 9-12 in CCSDS 130.1-G-2
end

% LocalWords:  INITSYM TFSYM FINALSYM TFLEN
