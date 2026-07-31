function out = tm_data_path_bit_interleave(iStream, qStream)
%TM_DATA_PATH_BIT_INTERLEAVE Pack equal-length I/Q streams as I1,Q1,I2,Q2,...
%
% This is the bit-level contract shared by the ordinary-TM dual-I/Q
% transmitter and its regression tests. It does not perform
% modulation-specific mapper packing.

    iStream = iStream(:);
    qStream = qStream(:);

    if numel(iStream) ~= numel(qStream)
        error('tm_data_path_bit_interleave:LengthMismatch', ...
            'I/Q streams must have equal lengths, got %d and %d.', ...
            numel(iStream), numel(qStream));
    end
    if ~strcmp(class(iStream), class(qStream))
        error('tm_data_path_bit_interleave:ClassMismatch', ...
            'I/Q streams must have the same class, got %s and %s.', ...
            class(iStream), class(qStream));
    end

    out = zeros(2*numel(iStream), 1, 'like', iStream);
    out(1:2:end) = iStream;
    out(2:2:end) = qStream;
end
