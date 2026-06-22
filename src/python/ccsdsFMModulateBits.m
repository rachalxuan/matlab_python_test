function [fmWaveform, fmInfo] = ccsdsFMModulateBits(bits, params)
%CCSDSFMMODULATEBITS FM extension modulator for CCSDS encoded bits.
%   This follows the teacher FM/SOQPSK example structure:
%   warm-up bits + training + payload, then +/-1 mapping, upsampling,
%   square-root raised-cosine shaping, phase integration, and exp(j*phase).
%
%   CFO, phase offset, fractional delay, and AWGN are intentionally not
%   added here. The main evaluation channel should add impairments once.

    if nargin < 2 || isempty(params)
        params = struct();
    end

    fmInfo = ccsdsFMBuildInfo(bits, params);
    symbolRate = fmInfo.SymbolRate;
    fs = fmInfo.Fs;
    rolloff = fmInfo.RolloffFactor;
    tzzs = fmInfo.TZZS;
    interN = fmInfo.interN;

    database = double(fmInfo.dataSend)*2 - 1;
    database = upsample(database, interN);
    shapingFilter = rcosine(symbolRate, fs, 'sqrt', rolloff);
    shapingFilter = shapingFilter / sum(shapingFilter);
    dataLPF = conv(database, shapingFilter);

    phaseState = cumsum([0, dataLPF(2:end)]);
    fmWaveform = exp(1j * phaseState(:) * pi * tzzs);
end
