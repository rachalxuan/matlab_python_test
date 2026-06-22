function out = lineDecode(data,pcmFormat)
%satcom.internal.ccsds.lineDecode Decoding of line coded data
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   OUT = satcom.internal.ccsds.lineDecode(DATA,PCMFORMAT) returns the
%   decoded soft decision values, OUT, for a specified PCM coding,
%   PCMFORMAT, and line coded signal, DATA. This internal function supports
%   'NRZ-L', 'NRZ-M', 'NRZ-S' and 'Biphase-L' schemes.

%   Copyright 2020 The MathWorks, Inc.

%#codegen
 
llr = real(data);
out = [];
coder.varsize('out',[inf 1]);
if strcmpi(pcmFormat,'NRZ-L')
    out = double(llr);
elseif strcmpi(pcmFormat,'NRZ-M')
    out = zeros(length(llr),1);
    out(1) = double(llr(1));
    for ii = 2:length(out)
        out(ii) = double(-1*llr(ii)*llr(ii-1));
    end
elseif strcmpi(pcmFormat,'NRZ-S')
    out = zeros(length(llr),1);
    out(1) = double(-1*llr(1));
    for ii = 2:length(out)
        out(ii) = double(llr(ii)*llr(ii-1));
    end
elseif strcmpi(pcmFormat,'BIPHASE-L')
    llr1 = llr(1:2:end,1);
    llr2 = -1*llr(2:2:end,1);
    out = double(0.5*(llr1+llr2));
end
end
