function enabled = HelperTMUsesCalibratedPSKLLR(modulation, coding)
% One contract shared by the receiver, ASM demapper and payload demapper.
% APP/BP decoders require LLR magnitude, not merely a signed decision metric.
% RS uses signs; Viterbi normalizes its quantizer range. The current Chase
% TPC implementation has its own fixed-beta metric convention. Preserve
% those paths, and do not apply memoryless PSK formulas to CPM/UQPSK/FM.
enabled = any(strcmpi(modulation,{'BPSK','QPSK','8PSK'})) && ...
    any(strcmpi(coding,{'LDPC','turbo'}));
end
