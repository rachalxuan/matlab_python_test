function seq = facmPLScramblingSequence(codenum,len)
%satcom.internal.ccsds.facmPLScramblingSequence PL scrambling
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   SEQ = satcom.internal.ccsds.facmPLScramblingSequence(CODENUM, LEN)
%   generates integer valued physical layer (PL) scrambling sequence as
%   specified in Annex C of CCSDS "Flexible advanced coding and modulation
%   scheme for high rate telemetry applications" standard [1]. CODENUM is
%   the scrambling code number. LEN is the length of the sequence that is
%   needed. SEQ is the generated random integer values in the range of [0,
%   3] of length LEN. This integer valued sequence, SEQ can be mapped to
%   QPSK constellation as specified by the standard.
%
%   References:
%   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
%       Telemetry Applications. Recommendation for Space Data System
%       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington,
%       D.C.: CCSDS, March 2012.

%   Copyright 2020-2021 The MathWorks, Inc.

%#codegen

x1 = comm.PNSequence(...
    'Polynomial','z^18+z^7+1',...
    'InitialConditions',[zeros(17,1);1],...
    'Mask',codenum,...
    'SamplesPerFrame',len);
y1 = comm.PNSequence(...
    'Polynomial','z^18 + z^10 + z^7 + z^5 + 1',...
    'InitialConditions',ones(18,1),...
    'Mask',0,...
    'SamplesPerFrame',len);

x2 = comm.PNSequence(...
    'Polynomial','z^18+z^7+1',...
    'InitialConditions',[zeros(17,1);1],...
    'Mask',codenum+131072,...
    'SamplesPerFrame',len);
y2 = comm.PNSequence(...
    'Polynomial','z^18 + z^10 + z^7 + z^5 + 1',...
    'InitialConditions',ones(18,1),...
    'Mask',131072,...
    'SamplesPerFrame',len);

z1t = mod(x1()+y1(),2);
z2t = mod(x2()+y2(),2);
seq = 2*z2t+z1t;

end

% LocalWords:  CODENUM
