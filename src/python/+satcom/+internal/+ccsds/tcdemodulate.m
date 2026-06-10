function out = tcdemodulate(rxFrame,cfg)
%SATCOM.INTERNAL.CCSDS.TCDEMODULATE Demodulation as per the specified
%scheme in CCSDS telecommand
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   OUT = SATCOM.INTERNAL.CCSDS.TCDEMODULATE(RXFRAME,CFG) returns the soft
%   symbols after performing demodulation of the received waveform,
%   RXFRAME, based on the modulation scheme in the configuration, CFG. OUT
%   is a column vector containing the soft symbols.
%
%   CFG is a configuration object of type <a href="matlab:help('ccsdsTCConfig')">ccsdsTCConfig</a>.
%   The properties of CFG are used to define the parameters required for
%   the CCSDS TC waveform generation.
%
% References:
%   [1] Radio Frequency and Modulation Systems - Part 1: Earth Stations and
%   Spacecraft. Recommendation for Space Data System Standards, CCSDS
%   401.0-B-29. Blue Book. Issue 29. Washington, D.C.: CCSDS, March 2019.

%   Copyright 2020 The MathWorks, Inc.

%#codegen

out = [];
sps = cfg.SamplesPerSymbol;
switch cfg.Modulation    
    case 'PCM/PSK/PM' 
        % Subcarrier demodulation
        Fc = cfg.SubcarrierFrequency;
        R = cfg.SymbolRate;
        Fs = sps*R;
        T = length(rxFrame)/(sps*R);
        t = (0:(1/Fs):T-(1/Fs)).';
        x = sin(2*pi*Fc*t);
        
        I = sin(cfg.ModulationIndex*x);
        idx = find(abs(I)>=0.1);
        temp2 = I(1:sps);
        dd = find(abs(temp2)>=0.1);
        len = length(dd);
        sig = real(rxFrame(idx))./I(idx);
        demodSig = zeros(length(sig)/len,1);
        for kk = 1:length(sig)/len
            sample = mean(sig((kk-1)*len+1:kk*len));
            demodSig(kk) = sample;
        end
        % Line decoding
        out = satcom.internal.ccsds.lineDecode(demodSig,cfg.PCMFormat);
    case 'PCM/PM/biphase-L'   
        I = sin(cfg.ModulationIndex);
        demodSamples = real(rxFrame)./I;
        demodSig = zeros(length(demodSamples)/sps,1);
        for kk = 1:length(demodSig)
            temp = sum(demodSamples((kk-1)*sps+1:kk*sps,1));
            demodSig(kk) = temp;
        end
        % Line decoding
        out = satcom.internal.ccsds.lineDecode(demodSig,'BIPHASE-L');
    case 'BPSK'
        out = double(real(rxFrame));
end
end