function sym = HelperCCSDSFACMFrameMarker(~)
%HelperCCSDSFACMFrameMarker Frame marker generation
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   SYM = HelperCCSDSFACMFrameMarker() generates the pi/2-BPSK modulated
%   256 symbol frame marker, SYM as defined in CCSDS 131.2-B-1 section
%   5.3.2 [1].
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

% Following FrameMarker can be generated using comm.GoldSequence as
% shown in following code:
% H = comm.GoldSequence('FirstPolynomial','z^8+z^6+z^5+z^4+1',...
%     'FirstInitialConditions',[1 0 0 1 0 1 1 0],'SecondPolynomial',...
%     'z^8 + z^6 + z^5 + z^4 + z^3 + z + 1','SecondInitialConditions',...
%     [0 1 0 0 1 0 0 1],'SamplesPerFrame',256);
% FrameMarker = H();
FrameMarker = [1;1;1;1;1;0;1;1;0;1;0;0;0;1;0;0;0;0;0;1;1;1;1;1;...
    0;0;0;1;1;1;0;1;1;0;1;1;1;1;0;1;1;1;0;1;0;1;1;1;0;1;1;1;0;1;...
    1;0;1;1;1;1;0;0;1;0;0;0;1;1;0;1;0;0;0;1;1;1;1;0;0;1;1;1;0;1;...
    1;0;1;0;0;0;0;1;0;0;0;0;1;0;1;1;0;1;0;0;1;0;1;1;0;0;1;1;1;0;...
    1;0;1;0;1;1;1;0;0;1;1;1;0;1;0;1;1;1;1;1;0;1;0;1;1;1;0;1;0;1;...
    1;0;1;1;1;1;1;1;0;0;0;1;1;1;1;0;0;1;1;1;0;0;0;0;1;1;0;0;1;0;...
    1;0;1;1;1;0;1;1;1;0;1;1;0;0;1;1;1;1;1;0;0;1;0;1;0;0;1;0;0;0;...
    0;1;0;1;1;1;0;0;1;1;0;1;1;1;1;0;1;1;0;0;1;1;1;0;0;1;0;1;0;0;...
    0;1;1;0;1;0;1;1;1;1;0;0;0;1;0;1;0;0;0;0;0;1];

% pi/2 - BPSK modulation
sym = complex(zeros(256,1));
modSymb = (1-2*FrameMarker)/sqrt(2);
sym(1:2:end) = modSymb(1:2:end)+1j*modSymb(1:2:end);
sym(2:2:end) = -modSymb(2:2:end)+1j*modSymb(2:2:end);
end