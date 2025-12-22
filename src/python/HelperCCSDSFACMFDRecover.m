function [ACMFormat,hasPilots,decFail] = HelperCCSDSFACMFDRecover(fd)
%HelperCCSDSFACMFDRecover Recovers PL signaling information from CCSDS FACM
%frame descriptor field
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
% 
%   [ACMFORMAT,HASPILOTS,DECFAIL] = HelperCCSDSFACMFDRecover(FD) recovers
%   the ACMFORMAT and presence of pilots indicator, HASPILOTS from the
%   frame descriptor, FD. DECFAIL indicates if decoding the FD is failed.
%   If DECFAIL is zero means the decoding is successful.
%
%   Demodulation is performed according to the constellation given in CCSDS
%   131.2-B-1 Section 5.4 [1].
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington, D.C.:
%       CCSDS, March 2012.

%   Copyright 2021 The MathWorks, Inc.

% pi/2 - BPSK soft demodulation (+ve -> 0, -ve -> 1)
softBits = zeros(64, 1); % Header frame descriptor length is 64
softBits(1:2:end) = real(fd(1:2:end))+imag(fd(1:2:end));
softBits(2:2:end) = imag(fd(2:2:end))-real(fd(2:2:end));

% de-scrambling
scramSeq = logical([0 1 1 1 0 0 0 1 1 0 0 1 1 1 0 1 1 0 0 0 0 0 1 1 1 1 ...
    0 0 1 0 0 1 0 1 0 1 0 0 1 1 0 1 0 0 0 0 1 0 0 0 1 0 1 1 0 1 1 1 1 1 1 0 1 0]');
softBits(scramSeq) = -softBits(scramSeq);

% Maximum-likelihood decoding
m = 64;
allMsgs = de2bi(0:m-1, 6); % one per row
genMat = [0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1; ...
          0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1; ...
          0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1; ...
          0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1; ...
          0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1; ...
          1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1];
% Codeword length is 32
softEncMsgs = zeros(32, m);
for i = 1:m
    encMsg = mod(allMsgs(i,:)*genMat,2);
    softEncMsgs(:,i) = 1-2*encMsg;
end
possMsg = zeros(64, 128);
possMsg(1:2:end,:) = repmat(softEncMsgs,1,2);
possMsg(2:2:end,1:64) = softEncMsgs;
possMsg(2:2:end,65:end) = -softEncMsgs;
%   Euclidean distance metric
distMet = sum(abs(repmat(softBits,1,2*m) - possMsg).^2,1)./sum(abs(possMsg).^2,1);
%   Select the msg bits corresponding to the minimum
index = find(distMet==min(distMet),1);
if index > 64
    decFail = 1;
    index = index-64;
else
    decFail = 0;
end
decBits = allMsgs(index,:);
ACMFormat = comm.internal.utilities.convertBit2Int(decBits(1:5)',5);
hasPilots = false;
if decBits(6)
    hasPilots = true;
end
end

% LocalWords:  ACMFORMAT HASPILOTS ve de
