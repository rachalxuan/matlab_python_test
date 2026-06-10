function [n, fullmsglen, i, s] = validateRSPrms(k, inputs, fname)
%   [N, FULLMSGLEN, I, S] = satcom.internal.ccsds.validateRSPrms(K, INPUTS,
%   FNAME) validates the input parameters of ccsdsRSEncode() and
%   ccsdsRSDecode() functions. INPUTS is cell input which is taken from
%   varargin of encoder or decoder. FNAME is the function name in character
%   vector which is calling this function. N is the codeword length and is
%   always fixed to 255 in case of CCSDS RS codes. FULLMSGLEN value is
%   equal to K and is of int32 datatype irrespective of datatype of K. I is
%   the interleaving depth which is taken from INPUTS. S is the shortened
%   message length which is taken from INPUTS.
%
%   Note: This is an internal undocumented function and its API and/or 
%   functionality may change in subsequent releases. 

%   Copyright 2019-2020 The MathWorks, Inc.

%#codegen
validateattributes(k, {'numeric'}, {'nonnan', 'finite', 'nonempty', 'scalar'}, fname, 'K');
coder.internal.errorIf(~any(k==[223;239]), 'satcom:ccsdsrs:InvalidRSCodeConfig', k);
if numel(inputs)==1
    Kshort = k; % Shortened message length
    validateattributes(inputs{1}, {'numeric'}, {'nonempty', 'nonnan', 'finite', 'integer', 'scalar'}, fname, 'I');
    coder.internal.errorIf(~any(inputs{1}==[1,2,3,4,5,8]), 'satcom:ccsdsrs:InvalidRSInterleavingDepth', inputs{1});
    i = int32(inputs{1}); % Interleaving depth
elseif numel(inputs)==2
    Kshort = inputs{2};
    validateattributes(inputs{1}, {'numeric'}, {'nonempty', 'nonnan', 'finite', 'integer', 'scalar'}, fname, 'I');
    coder.internal.errorIf(~any(inputs{1}==[1,2,3,4,5,8]), 'satcom:ccsdsrs:InvalidRSInterleavingDepth', inputs{1});
    validateattributes(Kshort, {'numeric'}, {'nonempty','nonnan','finite','integer',...
    'positive','scalar','>',0,'<=',k}, fname , 'S');
    i = int32(inputs{1});
else
    i = int32(1); % Default value of Interleaving depth is 1
    Kshort = k;
end

n = int32(255); % Codeword length is always 255

% Convert the input parameters to int32 datatypes
fullmsglen = int32(k);
s = int32(Kshort);

end
