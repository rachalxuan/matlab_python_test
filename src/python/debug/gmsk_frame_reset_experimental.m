function [softBits, info, rawMetric] = gmsk_frame_reset_experimental(inputData, cfg)
%GMSK_FRAME_RESET_EXPERIMENTAL Compatibility wrapper for the isolated test.
%
% The implementation is shared with the opt-in receiver helper so the short
% experiment and the later main-chain integration exercise identical logic.

    [softBits, info, rawMetric] = ...
        gmsk_frame_reset_demodulate(inputData, cfg);
end
