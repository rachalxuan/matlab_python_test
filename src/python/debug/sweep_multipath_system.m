function results = sweep_multipath_system(profile)
%SWEEP_MULTIPATH_SYSTEM Multipath/equalizer system sweep for CCSDS platform.
%
% Run from MATLAB:
%   addpath('E:\web_code\react\fft_project\react-fft\src\python','-begin')
%   addpath('E:\web_code\react\fft_project\react-fft\src\python\debug','-begin')
%   results = sweep_multipath_system;
%
% Optional:
%   results = sweep_multipath_system("smoke"); % default
%   results = sweep_multipath_system("equalizer");
%   results = sweep_multipath_system("full");
%
% The sweep checks whether representative modulation/coding modes survive
% mild/medium SISO multipath, and compares equalizer off/on.

    if nargin < 1 || isempty(profile)
        profile = "smoke";
    end
    profile = lower(string(profile));

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);
    if exist(fullfile(parentDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(parentDir, '-begin');
    end

    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    outCsv = fullfile(thisDir, sprintf('sweep_multipath_system_%s_%s.csv', profile, stamp));

    cases = localBuildCases(profile);
    hCases = localBuildHScenarios(profile);
    results = localEmptyResults();

    fprintf('\n================ CCSDS MULTIPATH SYSTEM SWEEP ================\n');
    fprintf('Profile : %s\n', profile);
    fprintf('Base cases : %d\n', numel(cases));
    fprintf('H scenarios: %d\n', numel(hCases));
    fprintf('CSV     : %s\n', outCsv);

    totalN = numel(cases) * numel(hCases);
    idx = 0;

    for iCase = 1:numel(cases)
        c = cases{iCase};
        for iH = 1:numel(hCases)
            h = hCases{iH};
            idx = idx + 1;

            p = localApplyHScenario(c.Params, h);

            fprintf('\n[%03d/%03d] %s | %s | %s | SNR %.1f dB\n', ...
                idx, totalN, c.Category, c.Name, h.Name, p.snr);

            t0 = tic;
            try
                out = localDecodeOutput(run_ccsds_tm_evaluation(p));
                elapsed = toc(t0);

                berVal = localField(out, {'BER','ber'}, NaN);
                lockPct = localLockPct(out);
                evmVal = localField(out, {'EVM_post_pct','EVM'}, NaN);
                snrEst = localField(out, {'SNR_est_dB'}, NaN);
                merVal = localField(out, {'MER_dB'}, NaN);
                paprVal = localField(out, {'PAPR_dB'}, NaN);
                success = localSuccess(out);
                errMsg = localError(out);
                verdict = localVerdict(success, berVal, lockPct, c.PassBER, c.PassLock);
            catch ME
                elapsed = toc(t0);
                berVal = NaN;
                lockPct = NaN;
                evmVal = NaN;
                snrEst = NaN;
                merVal = NaN;
                paprVal = NaN;
                success = false;
                errMsg = string(ME.message);
                verdict = "FAIL";
            end

            row = table( ...
                string(c.Category), string(c.Name), string(c.Note), ...
                string(localGetParam(p,'modType',"")), ...
                string(localGetParam(p,'channelCoding',"")), ...
                string(localGetParam(p,'PCMFormat',"")), ...
                string(h.Name), logical(h.EnableH), logical(h.EnableEq), ...
                h.NumTaps, h.EffectiveTaps, h.RelEchoPower_dB, ...
                double(localGetParam(p,'snr',NaN)), ...
                double(localGetParam(p,'cfo',NaN)), ...
                double(localGetParam(p,'phaseOffset',NaN)), ...
                double(localGetParam(p,'delay',NaN)), ...
                berVal, lockPct, evmVal, snrEst, merVal, paprVal, ...
                c.PassBER, c.PassLock, success, verdict, errMsg, elapsed, ...
                'VariableNames', results.Properties.VariableNames);

            results = [results; row]; %#ok<AGROW>
            writetable(results, outCsv);

            fprintf('  BER=%9.3g  Lock=%6.1f%%  EVM=%6.2f%%  SNRest=%6.2f dB  %s\n', ...
                row.BER, row.LockRate_pct, row.EVM_post_pct, row.SNR_est_dB, row.Verdict);
            if row.Verdict == "FAIL"
                fprintf(2, '  Error: %s\n', row.ErrorMsg);
            end
        end
    end

    fprintf('\n================ MULTIPATH SWEEP SUMMARY ================\n');
    disp(groupsummary(results, "Verdict"));
    disp(results);
    fprintf('\nSaved CSV: %s\n', outCsv);
end

function cases = localBuildCases(profile)
    base = struct( ...
        'symbolRate', 20e6, ...
        'sps', 4, ...
        'snr', 18, ...
        'cfo', 20000, ...
        'phaseOffset', 10, ...
        'delay', 0.1, ...
        'channelCoding', 'convolutional', ...
        'ConvolutionalCodeRate', '1/2', ...
        'PCMFormat', 'NRZ-L', ...
        'RolloffFactor', 0.35, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'hasPilots', true, ...
        'showFigures', false, ...
        'berWarmUpFrames', 4, ...
        'berFrames', 16, ...
        'facmWarmupFrames', 10, ...
        'facmBERFrames', 20, ...
        'facmNumIterations', 10, ...
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'enableFACMEqualizer', false);

    cases = {};

    if profile == "equalizer" || profile == "eq"
        modList = {
            "8PSK",  16, "convolutional", "TM conv1/2", 1e-4, 85
            "16QAM", 20, "convolutional", "TM conv1/2", 1e-4, 85
            };
    elseif profile == "full"
        modList = {
            "BPSK",  16, "convolutional", "TM conv1/2", 1e-5, 90
            "QPSK",  16, "convolutional", "TM conv1/2", 1e-5, 90
            "8PSK",  18, "convolutional", "TM conv1/2", 1e-5, 90
            "GMSK",  18, "convolutional", "TM conv1/2", 1e-5, 90
            "16QAM", 22, "convolutional", "TM conv1/2", 1e-5, 85
            "32QAM", 24, "convolutional", "TM conv1/2", 1e-5, 85
            };
    else
        modList = {
            "BPSK",  16, "convolutional", "TM conv1/2", 1e-5, 90
            "8PSK",  18, "convolutional", "TM conv1/2", 1e-5, 90
            "16QAM", 22, "convolutional", "TM conv1/2", 1e-5, 85
            };
    end

    for i = 1:size(modList,1)
        p = base;
        p.modType = char(modList{i,1});
        p.snr = modList{i,2};
        p.channelCoding = char(modList{i,3});
        if strcmpi(p.modType, 'GMSK')
            p.RolloffFactor = 0.5;
        end
        if contains(upper(string(p.modType)), 'QAM')
            p = localRemoveFields(p, {'PCMFormat'});
        end
        cases{end+1} = localCase("TM modulation", ...
            sprintf('%s %s', p.modType, modList{i,4}), p, modList{i,5}, modList{i,6}); %#ok<AGROW>
    end

    if profile == "equalizer" || profile == "eq"
        p = base;
        p.modType = '16APSK';
        p.sps = 8;
        p.snr = 22;
        p.cfo = 20000;
        p.channelCoding = 'none';
        p.ACMFormat = 14;
        p.acmFormat = 14;
        p.hasPilots = true;
        p.debugFACM = false;
        p.facmWarmupFrames = 8;
        p.facmBERFrames = 16;
        p.facmNumIterations = 10;
        p.facmEqualizerMode = 'pilot-ls';
        p.facmEqualizerTaps = 11;
        p.facmEqualizerReg = 1e-2;
        p.pilotLSReg = 1e-2;
        cases{end+1} = localCase("FACM APSK", "16APSK ACM14", p, 1e-4, 80);
        return;
    end

    codingList = {
        "none",          "8PSK none",       20, 1e-4, 90
        "convolutional", "8PSK conv1/2",    18, 1e-5, 90
        "LDPC",          "8PSK LDPC1/2",    20, 1e-4, 80
        };
    if profile == "full"
        codingList = [codingList; {
            "RS",    "8PSK RS",       20, 1e-4, 80
            "Turbo", "8PSK Turbo1/2", 20, 1e-4, 80
            }];
    end

    for i = 1:size(codingList,1)
        p = base;
        p.modType = '8PSK';
        p.snr = codingList{i,3};
        p.channelCoding = char(codingList{i,1});
        p = localApplyCodingDefaults(p);
        cases{end+1} = localCase("Coding", codingList{i,2}, ...
            p, codingList{i,4}, codingList{i,5}); %#ok<AGROW>
    end

    p = base;
    p.modType = 'BPSK';
    p.snr = 18;
    p.channelCoding = 'TPC';
    p.berWarmUpFrames = 0;
    p.berFrames = 6;
    p = localRemoveFields(p, {'ConvolutionalCodeRate','CodeRate','NumBitsInInformationBlock'});
    cases{end+1} = localCase("Coding", "BPSK TPC", p, 1e-4, 80);

    if profile == "full"
        p = base;
        p.modType = 'UQPSK';
        p.symbolRate = 100e6;
        p.sps = 8;
        p.snr = 22;
        p.cfo = 50000;
        p.channelCoding = 'convolutional';
        p.ConvolutionalCodeRate = '1/2';
        p.RRatio = 2;
        p.ARatio = 2;
        p.enableUQPSKFFTCoarseCFO = true;
        cases{end+1} = localCase("Extension modulation", "UQPSK conv1/2", p, 1e-4, 80);

        p = base;
        p.modType = 'FM';
        p.symbolRate = 20e6;
        p.sps = 4;
        p.snr = 10;
        p.cfo = 2e6;
        p.channelCoding = 'convolutional';
        p.ConvolutionalCodeRate = '1/2';
        p.RolloffFactor = 0.5;
        p.TZZS = 0.715;
        cases{end+1} = localCase("Extension modulation", "FM conv1/2", p, 1e-4, 80);
    end

    p = base;
    p.modType = '16APSK';
    p.sps = 8;
    p.snr = 24;
    p.cfo = 20000;
    p.channelCoding = 'none';
    p.ACMFormat = 14;
    p.acmFormat = 14;
    p.hasPilots = true;
    p.debugFACM = false;
    p.facmEqualizerMode = 'pilot-ls';
    p.facmEqualizerTaps = 11;
    p.facmEqualizerReg = 1e-2;
    p.pilotLSReg = 1e-2;
    cases{end+1} = localCase("FACM APSK", "16APSK ACM14", p, 1e-4, 80);

    if profile == "full"
        p = base;
        p.modType = '32APSK';
        p.sps = 8;
        p.snr = 28;
        p.cfo = 20000;
        p.channelCoding = 'none';
        p.ACMFormat = 21;
        p.acmFormat = 21;
        p.hasPilots = true;
        p.debugFACM = false;
        p.facmEqualizerMode = 'pilot-ls';
        p.facmEqualizerTaps = 13;
        p.facmEqualizerReg = 1e-2;
        p.pilotLSReg = 1e-2;
        cases{end+1} = localCase("FACM APSK", "32APSK ACM21", p, 1e-4, 80);
    end
end

function hCases = localBuildHScenarios(profile)
    cleanH = 1;
    mildH = [1, 0, 0.18*exp(1j*pi/4), 0, 0.08*exp(-1j*pi/3)];
    mediumH = [1, 0, 0.35*exp(1j*pi/3), 0, 0.22*exp(-1j*pi/4), 0, 0.12*exp(1j*pi/2)];
    strongH = [1, 0, 0.55*exp(1j*pi/3), 0, 0.35*exp(-1j*pi/4), 0, 0.20*exp(1j*pi/2)];

    if profile == "equalizer" || profile == "eq"
        hCases = {
            localHCase("clean", false, false, cleanH)
            localHCase("mild H, EQ off", true, false, mildH)
            localHCase("mild H, EQ on", true, true, mildH)
            localHCase("medium H, EQ off", true, false, mediumH)
            localHCase("medium H, EQ on", true, true, mediumH)
            localHCase("strong H, EQ off", true, false, strongH)
            localHCase("strong H, EQ on", true, true, strongH)
            };
        return;
    end

    hCases = {
        localHCase("clean", false, false, cleanH)
        localHCase("mild H, EQ off", true, false, mildH)
        localHCase("mild H, EQ on", true, true, mildH)
        localHCase("medium H, EQ on", true, true, mediumH)
        };

    if profile == "full"
        hCases = {
            localHCase("clean", false, false, cleanH)
            localHCase("mild H, EQ off", true, false, mildH)
            localHCase("mild H, EQ on", true, true, mildH)
            localHCase("medium H, EQ off", true, false, mediumH)
            localHCase("medium H, EQ on", true, true, mediumH)
            localHCase("strong H, EQ off", true, false, strongH)
            localHCase("strong H, EQ on", true, true, strongH)
            };
    end
end

function p = localApplyHScenario(p, hCase)
    p.enableHChannel = hCase.EnableH;
    p.enableEqualizer = hCase.EnableEq;
    p.enableFACMEqualizer = hCase.EnableEq;

    if hCase.EnableH
        p.HMode = 'siso_multipath';
        p.H = hCase.H;
        p.normalizeHChannel = true;
    else
        p = localRemoveFields(p, {'HMode','H','normalizeHChannel'});
    end

    if hCase.EnableEq
        p.equalizerMode = 'mmse';
        p.equalizerReg = 1e-2;
        p.normalizeEqualizerOutput = true;

        if isfield(p,'modType') && contains(upper(string(p.modType)), 'APSK')
            p.enableFACMEqualizer = true;
            if ~isfield(p,'facmEqualizerMode') || isempty(p.facmEqualizerMode)
                p.facmEqualizerMode = 'pilot-ls';
            end
        end
    else
        p.enableFACMEqualizer = false;
        p = localRemoveFields(p, {'equalizerMode','equalizerReg','normalizeEqualizerOutput'});
    end
end

function c = localCase(category, name, params, passBER, passLock)
    c = struct();
    c.Category = string(category);
    c.Name = string(name);
    c.Note = "";
    if isfield(params,'channelCoding')
        c.Note = string(params.channelCoding);
    end
    c.Params = params;
    c.PassBER = double(passBER);
    c.PassLock = double(passLock);
end

function h = localHCase(name, enableH, enableEq, taps)
    taps = taps(:).';
    h = struct();
    h.Name = string(name);
    h.EnableH = logical(enableH);
    h.EnableEq = logical(enableEq);
    h.H = taps;
    h.NumTaps = numel(taps);
    h.EffectiveTaps = nnz(abs(taps) > 1e-12);
    if h.EffectiveTaps > 1
        mainPower = abs(taps(1)).^2 + eps;
        echoPower = sum(abs(taps(2:end)).^2);
        h.RelEchoPower_dB = 10*log10(echoPower / mainPower + eps);
    else
        h.RelEchoPower_dB = -Inf;
    end
end

function p = localApplyCodingDefaults(p)
    p = localRemoveFields(p, {'ConvolutionalCodeRate','CodeRate', ...
        'NumBitsInInformationBlock','IsLDPCOnSMTF','LDPCCodeblockSize'});

    coding = lower(string(p.channelCoding));
    switch coding
        case "convolutional"
            p.ConvolutionalCodeRate = '1/2';
        case "ldpc"
            p.CodeRate = '1/2';
            p.NumBitsInInformationBlock = 1024;
            p.IsLDPCOnSMTF = false;
        case "turbo"
            p.CodeRate = '1/2';
            p.NumBitsInInformationBlock = 1784;
        otherwise
            % No extra coding parameters.
    end
end

function results = localEmptyResults()
    results = table( ...
        strings(0,1), strings(0,1), strings(0,1), ...
        strings(0,1), strings(0,1), strings(0,1), ...
        strings(0,1), false(0,1), false(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), false(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
        'VariableNames', {'Category','Name','Note', ...
        'Modulation','Coding','PCMFormat', ...
        'HScenario','EnableHChannel','EnableEqualizer', ...
        'HNumTaps','HEffectiveTaps','HRelEchoPower_dB', ...
        'InputSNR_dB','CFO_Hz','Phase_deg','Delay_symbols', ...
        'BER','LockRate_pct','EVM_post_pct','SNR_est_dB','MER_dB','PAPR_dB', ...
        'PassBER','PassLock_pct','Success','Verdict','ErrorMsg','ElapsedTime_s'});
end

function out = localDecodeOutput(raw)
    if isstruct(raw)
        out = raw;
    elseif ischar(raw) || isstring(raw)
        out = jsondecode(char(raw));
    else
        error('Unsupported evaluation output type: %s', class(raw));
    end
end

function v = localField(s, names, defaultValue)
    v = defaultValue;
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for i = 1:numel(names)
        name = char(names{i});
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if ischar(raw) || isstring(raw)
                raw = str2double(raw);
            end
            if isnumeric(raw) || islogical(raw)
                v = double(raw(1));
                return;
            end
        end
    end
end

function v = localGetParam(s, name, defaultValue)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defaultValue;
    end
end

function lockPct = localLockPct(out)
    lock = localField(out, 'LockRate', NaN);
    if isnan(lock)
        lockPct = NaN;
    elseif lock <= 1.5
        lockPct = 100 * lock;
    else
        lockPct = lock;
    end
end

function tf = localSuccess(out)
    tf = true;
    if isfield(out,'success') && ~isempty(out.success)
        tf = logical(out.success);
    end
end

function msg = localError(out)
    msg = "";
    if isfield(out,'errorMsg') && ~isempty(out.errorMsg)
        msg = string(out.errorMsg);
    end
end

function verdict = localVerdict(success, berVal, lockPct, passBER, passLock)
    if ~success || ~isfinite(berVal) || ~isfinite(lockPct)
        verdict = "FAIL";
    elseif berVal <= passBER && lockPct >= passLock
        verdict = "PASS";
    elseif berVal <= max(1e-2, 10*passBER) && lockPct >= max(50, passLock - 20)
        verdict = "WARN";
    else
        verdict = "FAIL";
    end
end

function s = localRemoveFields(s, names)
    for i = 1:numel(names)
        if isfield(s, names{i})
            s = rmfield(s, names{i});
        end
    end
end
