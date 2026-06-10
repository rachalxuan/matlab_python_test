function out = lineEncode(bits,pcmFormat,varargin)
%satcom.internal.ccsds.lineEncode Line coding 
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   OUT = satcom.internal.ccsds.lineEncode(BITS,PCMFORMAT) returns line
%   coded signal for a specified PCM coding, PCMFORMAT, and information
%   bits, BITS. OUT is a binary column vector. This internal function
%   supports 'NRZ-L', NRZ-M' and 'Biphase-L' encoding.
%
%   OUT = satcom.internal.ccsds.lineEncode(BITS,PCMFORMAT,SPS) returns the
%   line coded signal for a given samples per symbol, SPS. The default
%   value of SPS is 1.

%   Copyright 2020 The MathWorks, Inc.

%#codegen
 
if nargin > 2
    sps = varargin{1};
else
    sps = 1;
end

out = [];
if strcmpi(pcmFormat,'NRZ-L')
    out = zeros(sps*length(bits),1);
    for ii = 1:length(bits)
        out((ii-1)*sps+1:ii*sps) = 2*bits(ii)-1;
    end
    
elseif strcmpi(pcmFormat,'NRZ-M')
    out = -1*ones(sps*length(bits),1);
    if bits(1)== 1
        out(1:sps) = 1;
    end
    
    for ii = 2:length(bits)
        if bits(ii)== 1
            out((ii-1)*sps+1:ii*sps) = -1*out(sps*(ii-1));
        else
            out((ii-1)*sps+1:ii*sps) = out(sps*(ii-1));
        end
    end
    
elseif strcmpi(pcmFormat,'BIPHASE-L')
    out = zeros(2*sps*length(bits),1);
    for ii = 1:length(bits)
        if bits(ii) == 1
            out((ii-1)*2*sps+1:(ii-1+0.5)*2*sps) = 1;
            out((ii-1+0.5)*2*sps+1:ii*2*sps) = -1;
        else
            out((ii-1)*2*sps+1:(ii-1+0.5)*2*sps) = -1;
            out((ii-1+0.5)*2*sps+1:ii*2*sps) = 1;
        end
    end
end
end