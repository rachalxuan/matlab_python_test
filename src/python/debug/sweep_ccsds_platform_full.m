function results = sweep_ccsds_platform_full(profile)
%SWEEP_CCSDS_PLATFORM_FULL Full-platform regression sweep for CCSDS simulation.
%
% Run from MATLAB:
%   addpath('E:\web_code\react\fft_project\react-fft\src\python','-begin')
%   addpath('E:\web_code\react\fft_project\react-fft\src\python\debug','-begin')
%   results = sweep_ccsds_platform_full;
%
% Optional:
%   results = sweep_ccsds_platform_full("smoke"); % default, faster
%   results = sweep_ccsds_platform_full("full");  % more SNR points
%
% This script checks:
%   1) TM modulation/demodulation modes
%   2) PCM formats NRZ-L / NRZ-M / NRZ-S
%   3) channel coding/decoding modes
%   4) extension modes: QAM, UQPSK, FM, TPC, FACM APSK

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
    outCsv = fullfile(thisDir, sprintf('sweep_ccsds_platform_full_%s_%s.csv', profile, stamp));

    cases = localBuildCases(profile);
    results = localEmptyResults();

    fprintf('\n================ CCSDS PLATFORM FULL SWEEP ================\n');
    fprintf('Profile: %s\n', profile);
    fprintf('Cases  : %d\n', numel(cases));
    fprintf('CSV    : %s\n', outCsv);

    for k = 1:numel(cases)
        c = cases{k};
        fprintf('\n[%03d/%03d] %s | %s | SNR %.1f dB\n', ...
            k, numel(cases), c.Category, c.Name, c.Params.snr);

        t0 = tic;
        try
            out = localDecodeOutput(run_ccsds_tm_evaluation(c.Params));
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
            string(c.Category), string(c.Name), ...
            string(localGetParam(c.Params,'modType',"")), ...
            string(localGetParam(c.Params,'channelCoding',"")), ...
            string(localGetParam(c.Params,'PCMFormat',"")), ...
            double(localGetParam(c.Params,'snr',NaN)), ...
            double(localGetParam(c.Params,'cfo',NaN)), ...
            double(localGetParam(c.Params,'phaseOffset',NaN)), ...
            double(localGetParam(c.Params,'delay',NaN)), ...
            berVal, lockPct, evmVal, snrEst, merVal, paprVal, ...
            c.PassBER, c.PassLock, success, verdict, errMsg, elapsed, ...
            'VariableNames', results.Properties.VariableNames);

        results = [results; row]; %#ok<AGROW>
        writetable(results, outCsv);

        fprintf('  BER=%8.3g  Lock=%6.1f%%  EVM=%6.2f%%  SNRest=%6.2f dB  %s\n', ...
            row.BER, row.LockRate_pct, row.EVM_post_pct, row.SNR_est_dB, row.Verdict);
        if row.Verdict == "FAIL"
            fprintf(2, '  Error: %s\n', row.ErrorMsg);
        end
    end

    fprintf('\n================ PLATFORM SWEEP SUMMARY ================\n');
    disp(groupsummary(results, "Verdict"));
    disp(results);
    fprintf('\nSaved CSV: %s\n', outCsv);
end

function cases = localBuildCases(profile)
    cases = {};

    base = struct( ...
        'symbolRate', 20e6, ...
        'sps', 4, ...
        'snr', 12, ...
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
        'berFrames', 20, ...
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false);

    % 1. TM modulation/demodulation smoke cases.
    modCases = {
        'BPSK',  8,  1e-5, 90
        'QPSK', 10,  1e-5, 90
        '8PSK', 12,  1e-5, 90
        'GMSK', 12,  1e-5, 90
        '16QAM',18,  1e-5, 85
        '32QAM',20,  1e-5, 85
        };
    for i = 1:size(modCases,1)
        p = base;
        p.modType = modCases{i,1};
        p.snr = modCases{i,2};
        p.symbolRate = 20e6;
        if strcmpi(p.modType, 'GMSK')
            p.RolloffFactor = 0.5;
        end
        cases{end+1} = localCase("TM modulation", ...
            sprintf('%s conv1/2', p.modType), p, modCases{i,3}, modCases{i,4}); %#ok<AGROW>
    end

    % 2. PCM format regression with uncoded and convolutional paths.
    for modName = ["BPSK","QPSK","8PSK"]
        for coding = ["none","convolutional"]
            for pcm = ["NRZ-L","NRZ-M","NRZ-S"]
                p = base;
                p.modType = char(modName);
                p.channelCoding = char(coding);
                p.PCMFormat = char(pcm);
                p.snr = 20;
                p.RolloffFactor = 0.35;
                if coding == "none" && isfield(p,'ConvolutionalCodeRate')
                    p = rmfield(p,'ConvolutionalCodeRate');
                end
                cases{end+1} = localCase("PCM format", ...
                    sprintf('%s %s %s', modName, coding, pcm), p, 5e-3, 80); %#ok<AGROW>
            end
        end
    end

    % 3. Coding/decoding regression.
    codingCases = {
        'none',          '8PSK uncoded',       16, 1e-4, 90
        'convolutional', '8PSK conv1/2',       10, 1e-5, 90
        'RS',            '8PSK RS',            14, 1e-4, 80
        'LDPC',          '8PSK LDPC1/2',        8, 1e-4, 80
        'Turbo',         '8PSK Turbo1/2',      12, 1e-4, 80
        };
    for i = 1:size(codingCases,1)
        p = base;
        p.modType = '8PSK';
        p.snr = codingCases{i,3};
        p.channelCoding = codingCases{i,1};
        p.PCMFormat = 'NRZ-L';
        p.RolloffFactor = 0.35;
        p = localApplyCodingDefaults(p);
        cases{end+1} = localCase("Coding", codingCases{i,2}, ...
            p, codingCases{i,4}, codingCases{i,5}); %#ok<AGROW>
    end

    % 4. TPC extension.
    p = base;
    p.modType = 'BPSK';
    p.snr = 12;
    p.channelCoding = 'TPC';
    p.berWarmUpFrames = 0;
    p.berFrames = 6;
    p.debugTPC = false;
    p = localRemoveFields(p, {'ConvolutionalCodeRate','CodeRate','NumBitsInInformationBlock'});
    cases{end+1} = localCase("Coding", "BPSK TPC", p, 1e-4, 80);

    % 5. UQPSK extension.
    p = base;
    p.modType = 'UQPSK';
    p.symbolRate = 100e6;
    p.sps = 8;
    p.snr = 18;
    p.cfo = 50000;
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '1/2';
    p.RRatio = 2;
    p.ARatio = 2;
    p.enableUQPSKFFTCoarseCFO = true;
    p.debugUQPSK = false;
    cases{end+1} = localCase("Extension modulation", "UQPSK conv1/2", p, 1e-4, 80);

    % 6. FM extension. EVM/MER may be NaN for FM; judge by BER/lock.
    p = base;
    p.modType = 'FM';
    p.symbolRate = 20e6;
    p.sps = 4;
    p.snr = 8;
    p.cfo = 2e6;
    p.channelCoding = 'convolutional';
    p.ConvolutionalCodeRate = '1/2';
    p.RolloffFactor = 0.5;
    p.TZZS = 0.715;
    p.debugFM = false;
    cases{end+1} = localCase("Extension modulation", "FM conv1/2", p, 1e-4, 80);

    % 7. FACM/APSK smoke cases.
    p = base;
    p.modType = '16APSK';
    p.symbolRate = 1e6;
    p.sps = 8;
    p.snr = 22;
    p.cfo = 20000;
    p.phaseOffset = 10;
    p.delay = 0.1;
    p.channelCoding = 'none';
    p.ACMFormat = 14;
    p.hasPilots = true;
    p.facmWarmupFrames = 7;
    p.facmBERFrames = 20;
    p.debugFACM = false;
    p = localRemoveFields(p, {'ConvolutionalCodeRate'});
    cases{end+1} = localCase("FACM APSK", "16APSK ACM14", p, 1e-4, 80);

    p = base;
    p.modType = '32APSK';
    p.symbolRate = 1e6;
    p.sps = 8;
    p.snr = 26;
    p.cfo = 20000;
    p.phaseOffset = 10;
    p.delay = 0.1;
    p.channelCoding = 'none';
    p.ACMFormat = 21;
    p.hasPilots = true;
    p.facmWarmupFrames = 7;
    p.facmBERFrames = 20;
    p.debugFACM = false;
    p = localRemoveFields(p, {'ConvolutionalCodeRate'});
    cases{end+1} = localCase("FACM APSK", "32APSK ACM21", p, 1e-3, 70);

    if profile == "full"
        cases = localExpandFullSNR(cases);
    end
end

function cases = localExpandFullSNR(cases)
    expanded = {};
    for k = 1:numel(cases)
        c = cases{k};
        if c.Category == "FACM APSK"
            snrs = [c.Params.snr-2 c.Params.snr c.Params.snr+2];
        elseif c.Category == "Extension modulation" && strcmpi(c.Params.modType,'FM')
            snrs = [4 6 8 10];
        else
            snrs = [max(0,c.Params.snr-4) c.Params.snr c.Params.snr+4];
        end
        for s = snrs
            c2 = c;
            c2.Params.snr = s;
            c2.Name = sprintf('%s @ %.0fdB', c.Name, s);
            expanded{end+1} = c2; %#ok<AGROW>
        end
    end
    cases = expanded;
end

function c = localCase(category, name, params, passBER, passLock)
    c = struct();
    c.Category = string(category);
    c.Name = string(name);
    c.Params = params;
    c.PassBER = passBER;
    c.PassLock = passLock;
end

function p = localApplyCodingDefaults(p)
    p = localRemoveFields(p, {'ConvolutionalCodeRate','CodeRate', ...
        'NumBitsInInformationBlock','IsLDPCOnSMTF','LDPCCodeblockSize'});
    switch lower(string(p.channelCoding))
        case "convolutional"
            p.ConvolutionalCodeRate = '1/2';
        case "ldpc"
            p.CodeRate = '1/2';
            p.NumBitsInInformationBlock = 1024;
            p.IsLDPCOnSMTF = false;
        case "turbo"
            p.CodeRate = '1/2';
            p.NumBitsInInformationBlock = 1784;
    end
end

function p = localRemoveFields(p, fields)
    for i = 1:numel(fields)
        if isfield(p, fields{i})
            p = rmfield(p, fields{i});
        end
    end
end

function results = localEmptyResults()
    results = table( ...
        strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), false(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
        'VariableNames', {'Category','CaseName','Modulation','Coding','PCMFormat', ...
        'InputSNR_dB','CFO_Hz','Phase_deg','Delay_symbols', ...
        'BER','LockRate_pct','EVM_post_pct','SNR_est_dB','MER_dB','PAPR_dB', ...
        'PassBER','PassLock_pct','Success','Verdict','ErrorMsg','ElapsedTime_s'});
end

function out = localDecodeOutput(x)
    if isstruct(x)
        out = x;
    elseif ischar(x) || isstring(x)
        out = jsondecode(char(x));
    else
        error('Unsupported run_ccsds_tm_evaluation output type: %s', class(x));
    end
end

function v = localField(s, names, defv)
    v = defv;
    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    for i = 1:numel(names)
        name = names{i};
        if isfield(s, name) && ~isempty(s.(name))
            v = double(s.(name));
            return;
        end
    end
end

function lockPct = localLockPct(out)
    lockPct = localField(out, {'FrameLock_pct','LockRate_pct','FrameLock'}, NaN);
    if isnan(lockPct)
        lockVal = localField(out, {'LockRate','lockRate'}, NaN);
        if ~isnan(lockVal)
            if lockVal <= 1
                lockPct = 100 * lockVal;
            else
                lockPct = lockVal;
            end
        end
    end
end

function tf = localSuccess(out)
    if isfield(out,'success')
        tf = logical(out.success);
    else
        tf = isfield(out,'BER') || isfield(out,'ber');
    end
end

function msg = localError(out)
    msg = "";
    if isfield(out,'errorMsg') && ~isempty(out.errorMsg)
        msg = string(out.errorMsg);
    elseif isfield(out,'error') && ~isempty(out.error)
        msg = string(out.error);
    end
end

function verdict = localVerdict(success, berVal, lockPct, passBER, passLock)
    if ~success || isnan(berVal)
        verdict = "FAIL";
    elseif berVal <= passBER && (isnan(lockPct) || lockPct >= passLock)
        verdict = "PASS";
    elseif berVal <= max(1e-2, 10*passBER)
        verdict = "WARN";
    else
        verdict = "FAIL";
    end
end

function v = localGetParam(p, name, defv)
    if isfield(p, name) && ~isempty(p.(name))
        v = p.(name);
    else
        v = defv;
    end
end
