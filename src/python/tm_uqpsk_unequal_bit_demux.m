function [iStream, qStream, droppedTail] = ...
        tm_uqpsk_unequal_bit_demux(x, rRatio, tailPolicy)
%TM_UQPSK_UNEQUAL_BIT_DEMUX Unpack grouped UQPSK values into I/Q rails.
%
%   [I,Q] = TM_UQPSK_UNEQUAL_BIT_DEMUX(X) reverses the default RRatio=2
%   layout [I1;I2;Q1;I3;I4;Q2;...].
%
%   [I,Q,DROPPED] = TM_UQPSK_UNEQUAL_BIT_DEMUX(X,RRATIO,'drop') removes
%   an incomplete final group and returns its length in DROPPED. The
%   strict default rejects incomplete groups.

    if nargin < 2 || isempty(rRatio)
        rRatio = 2;
    end
    if nargin < 3 || isempty(tailPolicy)
        tailPolicy = 'error';
    end

    rRatio = localValidateRatio(rRatio);
    policy = lower(string(tailPolicy));
    if ~isscalar(policy) || ~any(policy == ["error","drop"])
        error('tm_uqpsk_unequal_bit_demux:InvalidTailPolicy', ...
            'tailPolicy must be "error" or "drop".');
    end

    x = x(:);
    groupLength = rRatio + 1;
    droppedTail = mod(numel(x), groupLength);
    if droppedTail ~= 0
        if policy == "error"
            error('tm_uqpsk_unequal_bit_demux:IncompleteGroup', ...
                ['Grouped UQPSK input must contain complete %d-value ', ...
                 'groups; got %d values.'], groupLength, numel(x));
        end
        x = x(1:end-droppedTail);
    end

    if isempty(x)
        iStream = zeros(0, 1, 'like', x);
        qStream = zeros(0, 1, 'like', x);
        return;
    end

    groups = reshape(x, groupLength, []);
    iStream = reshape(groups(1:rRatio, :), [], 1);
    qStream = reshape(groups(end, :), [], 1);
end

function rRatio = localValidateRatio(value)
    rRatio = double(value);
    if ~isscalar(rRatio) || ~isfinite(rRatio) || ...
            rRatio < 1 || rRatio ~= round(rRatio)
        error('tm_uqpsk_unequal_bit_demux:InvalidRRatio', ...
            'RRatio must be a positive integer scalar.');
    end
end
