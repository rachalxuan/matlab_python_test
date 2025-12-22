function cfoEst = HelperCCSDSFACMFMFrequencyEstimate(rxFM,refFM,fsym)
%HelperCCSDSFACMFMFrequencyEstimate Estimate fine frequency offset
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   CFOEST = HelperCCSDSFACMFMFrequencyEstimate(RXFM,REFFM,FSYM)
%   estimates the residual frequency offset in RXFM by grouping the 256
%   symbols of frame marker (FM) into 16 blocks and estimating the mean of
%   phase difference between each block. The FM symbols are as specified in
%   [1]. CFOEST is the estimated carrier frequency offset. RXFM is the
%   received frame marker of 256 symbols and REFFM are the reference FM
%   symbols of length 256 that are transmitted and can be independently
%   generated at the receiver for correlation purpose.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

% From the frame marker (FM), estimate the residual CFO
% 1. Multiply received FM with reference FM
multipliedFM = rxFM.*conj(refFM);

% 2. Reshape to have groups of 16 symbols
reshapedFM = reshape(multipliedFM,16,16);

% 3. Estimate the phase values in each block by calculating the angle of
% sum of each block
phases = angle(sum(reshapedFM,1));

% 4. Calculate the difference in estimated phases and wrap the angles
% properly to be within -pi to pi.
diffPhases = wrapToPi(phases(2:end)-phases(1:end-1));

% 5. Calculate carrier frequency offset (CFO)
% As there are 16 symbols within each block, phase difference corresponding
% to one symbol will be the calculated phase divided by 16. Phase
% difference between each sample is given by 2*pi*fCFO/fSym. From this CFO
% is estimated as shown here.
cfoEst = mean(diffPhases/16)*fsym/(2*pi);

end

% LocalWords:  CFOEST RXFM REFFM FSYM
