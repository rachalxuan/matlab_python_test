function cfg = ccsdsTMConvolutionalPunctureConfig(codeRate)
%CCSDSTMCONVOLUTIONALPUNCTURECONFIG Canonical TM puncturing definition.
%   CFG contains the puncture pattern used after the rate-1/2 mother code,
%   the number P of decoded input bits per puncture period, and the number
%   Q of transmitted coded bits per period.  The definition is protocol
%   configuration only; it contains no transmitted data or receiver truth.

rate = char(strtrim(string(codeRate)));
switch rate
    case '1/2'
        pattern = [1;1];
    case '2/3'
        pattern = [1;1;0;1];
    case '3/4'
        pattern = [1;1;0;1;1;0];
    case '5/6'
        pattern = [1;1;0;1;1;0;0;1;1;0];
    case '7/8'
        pattern = [1;1;0;1;0;1;0;1;1;0;0;1;1;0];
    otherwise
        error('ccsdsTMConvolutionalPunctureConfig:UnsupportedRate', ...
            'Unsupported convolutional code rate "%s".',rate);
end

cfg = struct( ...
    'CodeRate',rate, ...
    'Pattern',pattern, ...
    'InputBitsPerPeriod',numel(pattern)/2, ...
    'OutputBitsPerPeriod',nnz(pattern));
end
