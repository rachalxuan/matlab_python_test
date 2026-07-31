function out = tm_uqpsk_unequal_bit_mux(iStream, qStream, rRatio)
%TM_UQPSK_UNEQUAL_BIT_MUX Pack unequal-rate UQPSK I/Q rails.
%
%   OUT = TM_UQPSK_UNEQUAL_BIT_MUX(I,Q) uses RRatio=2 and returns
%   [I1;I2;Q1;I3;I4;Q2;...].
%
%   OUT = TM_UQPSK_UNEQUAL_BIT_MUX(I,Q,RRATIO) packs RRATIO consecutive
%   I-rail values followed by one Q-rail value. I and Q must have the same
%   class and NUMEL(I) must equal RRATIO*NUMEL(Q).

    if nargin < 3 || isempty(rRatio)
        rRatio = 2;
    end
    rRatio = localValidateRatio(rRatio);

    iStream = iStream(:);
    qStream = qStream(:);
    if ~strcmp(class(iStream), class(qStream))
        error('tm_uqpsk_unequal_bit_mux:ClassMismatch', ...
            'I/Q streams must have the same class, got %s and %s.', ...
            class(iStream), class(qStream));
    end
    expectedILength = rRatio * numel(qStream);
    if numel(iStream) ~= expectedILength
        error('tm_uqpsk_unequal_bit_mux:RateMismatch', ...
            ['UQPSK unequal rails require numel(I)=RRatio*numel(Q); ', ...
             'got I=%d, Q=%d, RRatio=%d.'], ...
            numel(iStream), numel(qStream), rRatio);
    end

    if isempty(qStream)
        out = zeros(0, 1, 'like', iStream);
        return;
    end

    iGroups = reshape(iStream, rRatio, []);
    groups = [iGroups; reshape(qStream, 1, [])];
    out = groups(:);
end

function rRatio = localValidateRatio(value)
    rRatio = double(value);
    if ~isscalar(rRatio) || ~isfinite(rRatio) || ...
            rRatio < 1 || rRatio ~= round(rRatio)
        error('tm_uqpsk_unequal_bit_mux:InvalidRRatio', ...
            'RRatio must be a positive integer scalar.');
    end
end
