function [AGCRecovered,G] = HelperDigitalAutomaticGainControl(signal,snr,G)
%HelperDigitalAutomaticGainControl Digital automatic gain control
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   [AGCRECOVERED,G] = HelperDigitalAutomaticGainControl(SIGNAL,SNR,G)
%   adjusts gain of the signal, SIGNAL such that the power is unity. SNR is
%   the signal to noise power ratio that is detected in the received
%   signal. The input G is the gain calculated in previous iteration. Output
%   G is the gain calculated with the current input signal, SIGNAL.
%   AGCRECOVERED is the signal with is multiplied by appropriate gain
%   factor so that the power in the signal is unity. The algorithm for
%   digital automatic gain control is adopted from CCSDS 130.11-G-1 Section
%   5.5 [1].
%
%   References:
%   [1] SCCC—Summary of Definition and Performance. Informational report,
%       CCSDS 130.11-G-1. Green Book. Issue 1. Washington, D.C.: CCSDS,
%       April 2019.

%   Copyright 2021 The MathWorks, Inc.

gammaDAGC = 1/160;
nVar = 1/snr;
Pref = 1+nVar;
AGCRecovered = zeros(length(signal),1);
GVector = zeros(length(signal)+1,1);
GVector(1) = G;
for isym = 1:length(signal)
    AGCRecovered(isym) = G*signal(isym);
    e = -1*((abs(AGCRecovered(isym)).^2) - Pref);
    G = G + e*gammaDAGC;
    if abs(G)>1e10
        G = sign(G)*1e10; % Limiting the maximum value to avoid Inf
    end
    GVector(isym+1) = G;
end
end

% LocalWords:  AGCRECOVERED
