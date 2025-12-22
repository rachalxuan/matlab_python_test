function syncIndex = HelperCCSDSFACMFrameSync(rxSymb,refFM)
%HelperCCSDSFACMFrameSync Frame synchronization
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   SYNCINDEX = HelperCCSDSFACMFrameSync(RXSYM,REFFM) correlates the
%   differential frame marker with the differential input to find the
%   location of frame marker, SYNCINDEX. Differential input is calculated
%   from RXSYM and differential frame marker is calculated from REFFM.
%   REFFM is of length 256 and is defined in CCSDS 131.2-B-1 Section 5.3.2
%   [1].
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

% winLen = 256;
diffRefFM = imag(refFM(1:end-1).*conj(refFM(2:end)));
diffOut = imag(rxSymb(1:end-1).*conj(rxSymb(2:end)));
corrVal = conv(diffOut,flip(diffRefFM)); % Correlation can be found from convolution by flipping one vector
maxVal = max(corrVal);
syncIndex = mod(find(corrVal/maxVal > 0.75, 2)-length(diffRefFM),length(rxSymb))+1; % Convolution operation brings in additional refFM symbols
end

% LocalWords:  SYNCINDEX RXSYM REFFM
