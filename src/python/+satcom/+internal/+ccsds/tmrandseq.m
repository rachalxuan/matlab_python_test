function seq = tmrandseq(seqlen)
%SATCOM.INTERNAL.CCSDS.TMRANDSEQ PN randomizer sequence specified in TM synchronization and
%channel coding.
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   SEQ = SATCOM.INTERNAL.CCSDS.TMRANDSEQ(SEQLEN) generates the random
%   sequence specified in section 10 of CCSDS 131.0-B-3 TM Synchronization
%   and channel coding standard of length SEQLEN. SEQ is a logical column
%   vector containing the random sequence of length SEQLEN.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

% Following 255 length PN sequence is generated from following code
% poly = 'z^8 + z^7 + z^5 + z^3 + 1';
% initcond = ones(8, 1);
% pnobj = comm.PNSequence('Polynomial', poly, 'InitialConditions', ...
%     initcond, 'SamplesPerFrame', 255);
% seq = pnobj();

%   Copyright 2020 The MathWorks, Inc.

%#codegen

seq255 = int8([1;1;1;1;1;1;1;1;0;1;0;0;1;0;0;0;0;0;0;0;1;1;1;0;1;1;0;0;0;0;0;0;...
          1;0;0;1;1;0;1;0;0;0;0;0;1;1;0;1;0;1;1;1;0;0;0;0;1;0;1;1;1;1;0;0;...
          1;0;0;0;1;1;1;0;0;0;1;0;1;1;0;0;1;0;0;1;0;0;1;1;1;0;1;0;1;1;0;1;...
          1;0;1;0;0;1;1;1;1;0;1;1;0;1;1;1;0;1;0;0;0;1;1;0;1;1;0;0;1;1;1;0;...
          0;1;0;1;1;0;1;0;1;0;0;1;0;1;1;1;0;1;1;1;1;1;0;1;1;1;0;0;1;1;0;0;...
          0;0;1;1;0;0;1;0;1;0;1;0;0;0;1;0;1;0;1;1;1;1;1;1;0;0;1;1;1;1;1;0;...
          0;0;0;0;1;0;1;0;0;0;0;1;0;0;0;0;1;1;1;1;0;0;0;1;1;0;0;0;1;0;0;0;...
          1;0;0;1;0;1;0;0;1;1;0;0;1;1;0;1;1;1;1;0;1;0;1;0;1;0;1;1;0;0;0]);
   
numseq255 = floor(seqlen/255);
seq = zeros(seqlen, 1, 'int8');
seq(1:255*numseq255) = repmat(seq255, numseq255, 1);

remianingseqlen = mod(seqlen, 255);
seq(255*numseq255+1:end) = seq255(1:remianingseqlen);
end
