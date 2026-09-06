%% No-H full-program impairment sweep wrapper
% Runs the same case matrix as codex_noh_program_sweep_v1.m, but expands it
% into controlled one-variable-at-a-time profiles:
%   measured-SNR AWGN, CFO, fixed phase, fractional-sample delay, and one
%   combined point.  H and the channel equalizer remain forced OFF.
%
% Full run:
%   run('E:/web_code/react/fft_project/react-fft/tmp/codex_noh_impairment_program_sweep_v1.m');
%
% Example chunk (jobs 1..20 only):
%   NoHSweepUserOptions = struct('StartJob',1,'MaxJobs',20);
%   run('E:/web_code/react/fft_project/react-fft/tmp/codex_noh_impairment_program_sweep_v1.m');
%
% Example: noise-only profiles, modulation section only:
%   NoHSweepUserOptions = struct( ...
%       'RunModulationSweep',true,'RunCodingSweep',false, ...
%       'ImpairmentGroups',["baseline","noise"], ...
%       'NoiseSNRdB',[30 20 15 10]);
%   run('E:/web_code/react/fft_project/react-fft/tmp/codex_noh_impairment_program_sweep_v1.m');

NoHSweepRequestedMode = "impairment";
noHSweepWrapperDir = fileparts(mfilename('fullpath'));
run(fullfile(noHSweepWrapperDir,'codex_noh_program_sweep_v1.m'));
