function out = tcmodulate(bits,cfg)
%SATCOM.INTERNAL.CCSDS.TCMODULATE Signal modulation as per the specified
%scheme in CCSDS telecommmand
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   OUT = SATCOM.INTERNAL.CCSDS.TCMODULATE(BITS,CFG) returns the IQ
%   samples after performing modulation of the encoded bits, BITS based on
%   the modulation scheme in the configuration, CFG. OUT is a complex
%   column vector containing the complex envelope of the modulated signal.
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
        % Line coded signal
        sig = satcom.internal.ccsds.lineEncode(bits,cfg.PCMFormat,sps);
        % Subcarrier modulation
        Fc = cfg.SubcarrierFrequency;
        R = cfg.SymbolRate;
        Fs = sps*R;
        T = length(bits)/R;
        t = (0:(1/Fs):T-(1/Fs)).';
        x = sin(2*pi*Fc*t);
        y = sig.*x;
        
        % Waveform generation
        I = sin(cfg.ModulationIndex*y);
        Q = -1*cos(cfg.ModulationIndex*y);
        out = I+1j*Q;
        
    case 'PCM/PM/biphase-L'
        % Line coded signal
        sig = satcom.internal.ccsds.lineEncode(bits,'BIPHASE-L',sps);
        % Waveform generation
        I = sig*sin(cfg.ModulationIndex);
        Q = -1*cos(cfg.ModulationIndex);
        out = I+1j*Q;
        
    case 'BPSK'
        out = complex(2*bits-1);
end

end