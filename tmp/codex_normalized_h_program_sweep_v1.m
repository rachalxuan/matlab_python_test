%% Normalized-H, exactly noiseless full-program sweep
% Fixed conditions:
%   enableHChannel      = true
%   normalizeHChannel   = true
%   noiseMode           = 'off'
%   enableConverterChain= false
%   cfo/phaseOffset/delay = 0
%
% The shared engine first holds convolutional 1/2 fixed and sweeps every
% modulation, then holds 8PSK fixed and sweeps coding/rate.  It enables the
% adaptive/modulation-specific receiver, while forcing known-H equalization
% off.  No artifact is written unless SaveCSV is explicitly requested.

NoHSweepRequestedMode = "normalizedh";
run(fullfile(fileparts(mfilename('fullpath')), ...
    'codex_noh_program_sweep_v1.m'));
