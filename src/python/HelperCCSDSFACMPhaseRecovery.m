function [sym,frameDescriptor] = HelperCCSDSFACMPhaseRecovery(framesym,pilots,refFM)
%HelperCCSDSFACMPhaseRecovery Phase recovery
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   [SYM,FRAMEDESCRIPTOR] = ...
%   HelperCCSDSFACMPhaseRecovery(FRAMESYM,PILOTS,REFFM) calculates and
%   compensates for the phase offset that is left in FRAMESYM using the
%   reference pilots, PILOTS to generate the phase compensated symbols,
%   SYM. FRAMESYM is one complete physical layer (PL) frame which includes
%   frame header, data payload and pilots. REFFM is the reference frame
%   marker of length 256 that is defined in CCSDS 131.2-B-1 Section 5.3.2
%   [1]. SYM is the phase compensated payload part of the frame of length
%   8100*16 = 129600. FRAMEDESCRIPTOR is the phase compensated frame
%   descriptor (See CCSDS 131.2-B-1 Section 5.3.3 [1]).
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

numSymPerBlk = 540; % 540 is the number of symbols per sub section
numFD= 64; % Number of frame descriptors in a frame
% From pilots, estimate the residual phase offset
codeBlks = reshape(framesym(321:end),556,[]); % 556 is the number of symbols including pilots in a sub-section
pilotBlks = reshape(pilots,16,[]);
Tm = angle(sum(codeBlks(end-15:end,:).*conj(pilotBlks))); % Section 5.6 in green book of FACM

pilotsRemovedTemp = zeros(numSymPerBlk,240); % 240 is the number of sub-sections in a frame

% Recover frame descriptor and the first sub-section by using phase
% estimates from the last 16 symbols of the frame marker.
Tm0 = angle(sum(framesym(256-15:256).*conj(refFM(end-15:end))));
phasesInBlk = wrapToPi(Tm0 + (wrapToPi(Tm(1)-Tm0)/(numSymPerBlk+numFD+1))*(1:(numSymPerBlk+numFD)));
phaseCompensated = framesym(257:256+numFD+numSymPerBlk).*exp(-1j*phasesInBlk.'); % Contains the frame descriptor and the first sub-section in the payload
frameDescriptor = phaseCompensated(1:numFD);
pilotsRemovedTemp(:,1) = phaseCompensated(numFD+1:end);

% Compensate for the phase offset on the symbols using the information
% provided in section 5.6
for iSubSection = 2:240 % 240 is the number of subsections in a frame
    phasesInBlk = wrapToPi(Tm(iSubSection-1) + (wrapToPi(Tm(iSubSection)-Tm(iSubSection))/(numSymPerBlk+1))*(1:numSymPerBlk));
    pilotsRemovedTemp(:,iSubSection) = codeBlks(1:numSymPerBlk,iSubSection).*exp(-1j*phasesInBlk.');
end
sym = pilotsRemovedTemp(:);
end

% LocalWords:  FRAMEDESCRIPTOR FRAMESYM REFFM
