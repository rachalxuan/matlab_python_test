function out = reg_decode_output(outRaw)
%REG_DECODE_OUTPUT Normalize run_ccsds_tm_evaluation output to a struct.

    if ischar(outRaw) || isstring(outRaw)
        out = jsondecode(char(outRaw));
    else
        out = outRaw;
    end
end
