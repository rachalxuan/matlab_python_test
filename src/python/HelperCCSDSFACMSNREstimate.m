function SNREst = HelperCCSDSFACMSNREstimate(rxFM,refFM)
%HelperCCSDSFACMSNREstimate Estimate SNR
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   SNREST = HelperCCSDSFACMSNREstimate(RXFM,REFFM) estimates the signal
%   power to noise power ratio (SNR) of the received signal, RXFM. SNREST is the
%   estimated SNR. REFFM is the reference frame marker that is given in
%   CCSDS 131.2-B-1 Section 5.3.2. For detailed algorithm of SNR
%   estimation, refer CCSDS 130.11-G-1 Section 5.5 [2].
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.
%   [2] SCCC—Summary of Definition and Performance. Informational report,
%       CCSDS 130.11-G-1. Green Book. Issue 1. Washington, D.C.: CCSDS,
%       April 2019.

%   Copyright 2021 The MathWorks, Inc.

% 1. Estimate and compensate for residual phase offset in the frame marker
Tm0 = angle(sum(rxFM(1:16).*conj(refFM(1:16)))); % Consider first 16 symbols for phase estimation
Tm1 = angle(sum(rxFM(256-15:256).*conj(refFM(end-15:end)))); % Consider last 16 symbols for phase estimation
phasesInBlk = wrapToPi(Tm0 + (wrapToPi(Tm1-Tm0)/(257))*(1:256)); % Interpolate the phases for in-between symbols
phaseCompensated = rxFM(:).*exp(-1j*phasesInBlk.'); % Compensate for phases for the symbols

% 2. Estimate SNR on the phase compensated symbols
RVal = real(phaseCompensated(:).*conj(refFM(:)));
RSquare = abs(RVal).^2;
a = mean(RSquare);
b = mean(RVal);
SNREst = b^2/(2*(a-(b^2))); % See Section 5.5 in [2]
end

% LocalWords:  SNREST RXFM REFFM
