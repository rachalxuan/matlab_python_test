function [iStream, qStream, droppedTail] = tm_data_path_bit_deinterleave(x, oddTailPolicy)
%TM_DATA_PATH_BIT_DEINTERLEAVE Unpack I1,Q1,I2,Q2,... into two streams.
%
%   [I,Q] = TM_DATA_PATH_BIT_DEINTERLEAVE(X) rejects an odd-length input.
%   [I,Q,DROPPED] = TM_DATA_PATH_BIT_DEINTERLEAVE(X,'drop') drops one
%   unpaired tail value. The receiver uses 'drop' only as a synchronization
%   tolerance; contract tests use the strict default.

    if nargin < 2 || isempty(oddTailPolicy)
        oddTailPolicy = 'error';
    end

    x = x(:);
    policy = lower(string(oddTailPolicy));
    if ~isscalar(policy) || ~any(policy == ["error","drop"])
        error('tm_data_path_bit_deinterleave:InvalidOddTailPolicy', ...
            'oddTailPolicy must be "error" or "drop".');
    end

    droppedTail = false;
    if mod(numel(x), 2) ~= 0
        if policy == "error"
            error('tm_data_path_bit_deinterleave:OddLength', ...
                'Interleaved I/Q input must contain complete pairs; got %d values.', ...
                numel(x));
        end
        x = x(1:end-1);
        droppedTail = true;
    end

    iStream = x(1:2:end);
    qStream = x(2:2:end);
end
