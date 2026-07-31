function out = tm_data_path_frame_interleave(bitsI, bitsQ, bitsPerFrame, incompletePolicy)
%TM_DATA_PATH_FRAME_INTERLEAVE Merge decoded rails as I1,Q1,I2,Q2,...
%
%   OUT = TM_DATA_PATH_FRAME_INTERLEAVE(I,Q,N) requires both inputs to
%   contain the same number of complete N-bit frames.
%   OUT = TM_DATA_PATH_FRAME_INTERLEAVE(I,Q,N,'truncate') keeps the common
%   number of complete frames and ignores incomplete/excess frames. The
%   receiver uses this tolerance after synchronization and decoding.

    if nargin < 4 || isempty(incompletePolicy)
        incompletePolicy = 'error';
    end
    validateattributes(bitsPerFrame, {'numeric'}, ...
        {'scalar','real','finite','integer','positive'}, ...
        mfilename, 'bitsPerFrame');

    bitsI = bitsI(:);
    bitsQ = bitsQ(:);
    if ~strcmp(class(bitsI), class(bitsQ))
        error('tm_data_path_frame_interleave:ClassMismatch', ...
            'I/Q decoded streams must have the same class, got %s and %s.', ...
            class(bitsI), class(bitsQ));
    end

    policy = lower(string(incompletePolicy));
    if ~isscalar(policy) || ~any(policy == ["error","truncate"])
        error('tm_data_path_frame_interleave:InvalidIncompletePolicy', ...
            'incompletePolicy must be "error" or "truncate".');
    end

    nI = floor(numel(bitsI)/bitsPerFrame);
    nQ = floor(numel(bitsQ)/bitsPerFrame);
    hasPartialFrame = mod(numel(bitsI),bitsPerFrame) ~= 0 || ...
        mod(numel(bitsQ),bitsPerFrame) ~= 0;
    if policy == "error" && (hasPartialFrame || nI ~= nQ)
        error('tm_data_path_frame_interleave:IncompleteFrames', ...
            ['Strict frame merge requires the same number of complete frames; ', ...
             'got %d I values and %d Q values with %d values per frame.'], ...
            numel(bitsI), numel(bitsQ), bitsPerFrame);
    end

    n = min(nI, nQ);
    out = zeros(2*n*bitsPerFrame, 1, 'like', bitsI);
    for k = 1:n
        idxIn = (k-1)*bitsPerFrame + (1:bitsPerFrame);
        idxOutI = (2*k-2)*bitsPerFrame + (1:bitsPerFrame);
        idxOutQ = (2*k-1)*bitsPerFrame + (1:bitsPerFrame);
        out(idxOutI) = bitsI(idxIn);
        out(idxOutQ) = bitsQ(idxIn);
    end
end
