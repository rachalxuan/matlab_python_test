function results = sweep_tpc_modulations(snrList, modList, tpcCodeRateList, tpcBlocksPerTFList)
%SWEEP_TPC_MODULATIONS Sweep modulation modes with fixed TPC coding.
%
% Run from MATLAB:
%   addpath('E:\web_code\react\fft_project\react-fft\src\python','-begin')
%   addpath('E:\web_code\react\fft_project\react-fft\src\python\debug','-begin')
%   results = sweep_tpc_modulations;
%
% Optional:
%   results = sweep_tpc_modulations(0:2:12);
%   results = sweep_tpc_modulations(0:2:12, ["BPSK","QPSK","8PSK","16QAM","32QAM"]);
%   results = sweep_tpc_modulations(0:2:12, ["QPSK","8PSK"], ["1/2","2/3"], [1 3]);
%
% Default sweep plan:
%   Modulation      : BPSK, QPSK, 8PSK, GMSK, 16QAM, 32QAM
%   TPCCodeRate     : 1/2, 2/3
%   TPCBlocksPerTF  : 1, 2, 3, 4, 5, 6, 8
%   Non-byte-aligned TF combinations are skipped automatically.
%
% Notes:
%   TPC uses the teacher (64,57)^2 product-code encoder/decoder.
%   Default TPCCodeRate is 2/3, implemented as a shortened 52x52 payload.
%   Default TPCBlocksPerTF is 3, so one coded TF is ASM + 3 TPC codewords.
%   This is a TM extension path, not FACM APSK.

    thisDir = fileparts(mfilename('fullpath'));
    parentDir = fileparts(thisDir);
    if exist(fullfile(parentDir, 'run_ccsds_tm_evaluation.m'), 'file')
        addpath(parentDir, '-begin');
    end

    if nargin < 1 || isempty(snrList)
        snrList = 0:2:20;
    end
    if nargin < 2 || isempty(modList)
%         modList = ["BPSK","QPSK","8PSK","GMSK","16QAM","32QAM"];
        modList = ["32QAM"];
    end
    modList = localStringList(modList);
    if nargin < 3 || isempty(tpcCodeRateList)
        tpcCodeRateList = ["1/2","2/3"];
    end
    tpcCodeRateList = localStringList(tpcCodeRateList);
    if nargin < 4 || isempty(tpcBlocksPerTFList)
        tpcBlocksPerTFList = [1 2 3 4 5 6 8];
    end
    tpcBlocksPerTFList = localNumericList(tpcBlocksPerTFList);

    cfg = localDefaultConfig(snrList, modList, tpcCodeRateList, tpcBlocksPerTFList);
    stamp = datestr(now,'yyyymmdd_HHMMSS');
    cfg.outputFile = fullfile(thisDir, sprintf('sweep_tpc_modulations_%s.csv', stamp));
    cfg.plotFile = fullfile(thisDir, sprintf('sweep_tpc_modulations_%s.png', stamp));

    fprintf('\n[TPC sweep config] modulations=%s\n', strjoin(string(modList), ", "));
    fprintf('[TPC sweep config] codeRates=%s, blocksPerTF=%s\n', ...
        strjoin(string(tpcCodeRateList), ", "), mat2str(tpcBlocksPerTFList));
    fprintf('[TPC sweep config] valid cases=%d, SNR points=%d, total runs=%d\n', ...
        numel(cfg.cases), numel(cfg.snrList), numel(cfg.cases)*numel(cfg.snrList));

    results = localRunSweep(cfg);
    localPlotResults(results, cfg);

    fprintf('\n================ TPC MODULATION SWEEP SUMMARY ================\n');
    disp(results);
    fprintf('\nSaved CSV : %s\n', cfg.outputFile);
    fprintf('Saved Plot: %s\n', cfg.plotFile);
end

function cfg = localDefaultConfig(snrList, modList, tpcCodeRateList, tpcBlocksPerTFList)
    infoRate = 300e6;
    cfg = struct();
    cfg.snrList = double(snrList(:).');
    cfg.tpcCodeRateList = string(tpcCodeRateList(:).');
    cfg.tpcBlocksPerTFList = double(tpcBlocksPerTFList(:).');

    common = struct( ...
        'sps', 8, ...
        'snr', 10, ...
        'cfo', 20000, ...
        'phaseOffset', 10, ...
        'delay', 0.2, ...
        'channelCoding', 'TPC', ...
        'RolloffFactor', 0.35, ...
        'hasASM', true, ...
        'hasRandomizer', false, ...
        'TPCCodeRate','2/3', ...
        'TPCBlocksPerTF',3, ...
        'hasPilots', true, ...
        'showFigures', false, ...
        'berWarmUpFrames', 2, ...
        'berFrames', 10, ...
        'IFHz', 1000e6, ...
        'carrierFreqHz', 1000e6, ...
        'enableHChannel', false, ...
        'enableEqualizer', false, ...
        'debugTPC', false);

%     validTPC = localValidTPCCases(cfg.tpcCodeRateList, cfg.tpcBlocksPerTFList);
    % =========================
    % FIXED VALID TPC DESIGN SPACE
    % =========================
   validTPC = [
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',1)
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',2)
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',3)
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',4)
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',5)
       struct('TPCCodeRate',"2/3",'TPCBlocksPerTF',6)

       struct('TPCCodeRate',"1/2",'TPCBlocksPerTF',8)
       ];
    cfg.cases = repmat(struct('Name',"", 'TPCCodeRate',"", 'TPCBlocksPerTF',0, ...
    'Params',common, 'Note',""), 0, 1);

    for iMod = 1:numel(modList)

        name = upper(string(modList(iMod)));

        for iTPC = 1:numel(validTPC)

            rateName = validTPC(iTPC).TPCCodeRate;
            blocksPerTF = validTPC(iTPC).TPCBlocksPerTF;

            p = common;
            p.modType = char(name);
            p.TPCCodeRate = char(rateName);
            p.TPCBlocksPerTF = blocksPerTF;

            p.symbolRate = infoRate / localBitsPerSymbol(name);

            if name == "GMSK"
                p.BandwidthTimeProduct = 0.5;
                p.symbolRate = infoRate;
            end

            cfg.cases(end+1,1) = struct( ...
                'Name', name, ...
                'TPCCodeRate', rateName, ...
                'TPCBlocksPerTF', blocksPerTF, ...
                'Params', p, ...
                'Note', "VALID TPC: " + rateName + ", N=" + string(blocksPerTF));
        end
    end
end

function results = localRunSweep(cfg)
    results = table( ...
        strings(0,1), strings(0,1), zeros(0,1), strings(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), false(0,1), strings(0,1), ...
        'VariableNames', {'Modulation','TPCCodeRate','TPCBlocksPerTF','Note', ...
        'InputSNR_dB','BER','FER','EVM_post_pct','SNR_est_dB', ...
        'LockRate_pct','AcquisitionFrames','NumBytesInTransferFrame', ...
        'Success','ErrorMsg'});

    fprintf('\n================ TPC MODULATION SWEEP ================\n');
    fprintf('SNR points: %s\n', mat2str(cfg.snrList));

    for iCase = 1:numel(cfg.cases)
        c = cfg.cases(iCase);
        for snrVal = cfg.snrList
            p = c.Params;
            p.snr = snrVal;

            fprintf('\n[%s | TPC %s | blocks/TF %d | SNR %.1f dB]\n', ...
                char(c.Name), char(c.TPCCodeRate), c.TPCBlocksPerTF, snrVal);
            try
                out = localDecodeOutput(run_ccsds_tm_evaluation(p));
                row = table( ...
                    string(c.Name), string(c.TPCCodeRate), double(c.TPCBlocksPerTF), ...
                    string(c.Note), snrVal, ...
                    localField(out,'BER',NaN), ...
                    localField(out,'FER',NaN), ...
                    localField(out,'EVM_post_pct',NaN), ...
                    localField(out,'SNR_est_dB',NaN), ...
                    100*localField(out,'LockRate',NaN), ...
                    localField(out,'AcquisitionFrames',NaN), ...
                    localTPCTransferFrameBytes(c.TPCCodeRate, c.TPCBlocksPerTF), ...
                    localSuccess(out), localError(out), ...
                    'VariableNames', results.Properties.VariableNames);
            catch ME
                row = table( ...
                    string(c.Name), string(c.TPCCodeRate), double(c.TPCBlocksPerTF), ...
                    string(c.Note), snrVal, ...
                    NaN, NaN, NaN, NaN, 0, NaN, NaN, false, string(ME.message), ...
                    'VariableNames', results.Properties.VariableNames);
            end

            results = [results; row]; %#ok<AGROW>
            writetable(results, cfg.outputFile);

            if row.Success
                fprintf('  BER=%8.3g  FER=%8.3g  EVM=%6.2f%%  SNRest=%6.2fdB  Lock=%6.1f%%\n', ...
                    row.BER, row.FER, row.EVM_post_pct, row.SNR_est_dB, row.LockRate_pct);
            else
                fprintf(2, '  FAILED: %s\n', row.ErrorMsg);
            end
        end
    end
end

function localPlotResults(results, cfg)
    valid = isfinite(results.InputSNR_dB) & isfinite(results.BER) & results.BER >= 0;
    if ~any(valid)
        return;
    end

    results.CurveName = results.Modulation + " R" + results.TPCCodeRate + " N" + string(results.TPCBlocksPerTF);
    curves = unique(results.CurveName, 'stable');
    colors = lines(numel(curves));
    markers = {'o','s','^','d','v','>','<'};

    fig = figure('Name','TPC Modulation Sweep', ...
        'NumberTitle','off', 'Color',[0.94 0.94 0.94], ...
        'Position',[100 100 1500 470]);
    tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    for k = 1:numel(curves)
        sub = results(results.CurveName == curves(k) & valid, :);
        semilogy(sub.InputSNR_dB, max(sub.BER, 1e-6), '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('BER');
    title('BER vs SNR'); ylim([1e-6 1]);
    legend(cellstr(curves), 'Location','southwest');

    nexttile; hold on;
    for k = 1:numel(curves)
        sub = results(results.CurveName == curves(k) & valid, :);
        plot(sub.InputSNR_dB, sub.EVM_post_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('EVM (%)');
    title('EVM vs SNR');
    legend(cellstr(curves), 'Location','northeast');

    nexttile; hold on;
    for k = 1:numel(curves)
        sub = results(results.CurveName == curves(k) & valid, :);
        plot(sub.InputSNR_dB, sub.LockRate_pct, '-', ...
            'Color', colors(k,:), 'LineWidth', 2.0, ...
            'Marker', markers{1+mod(k-1,numel(markers))}, ...
            'MarkerSize', 6, 'MarkerFaceColor','w');
    end
    grid on; box on;
    xlabel('Input SNR (dB)'); ylabel('Frame Lock (%)');
    title('Frame Lock vs SNR'); ylim([0 105]);
    legend(cellstr(curves), 'Location','southeast');

    sgtitle('TPC modulation/rate/blocks sweep');
    exportgraphics(fig, cfg.plotFile, 'Resolution', 220);
end

function bps = localBitsPerSymbol(modName)
    switch upper(string(modName))
        case "BPSK"
            bps = 1;
        case {"QPSK","OQPSK"}
            bps = 2;
        case "8PSK"
            bps = 3;
        case "16QAM"
            bps = 4;
        case "32QAM"
            bps = 5;
        otherwise
            bps = 1;
    end
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

function tf = localSuccess(out)
    tf = isfield(out,'success') && logical(out.success);
end

function msg = localError(out)
    msg = "";
    if isfield(out,'errorMsg') && ~isempty(out.errorMsg)
        msg = string(out.errorMsg);
    elseif isfield(out,'error') && ~isempty(out.error)
        msg = string(out.error);
    end
end

function v = localField(s, name, defv)
    if isfield(s, name) && ~isempty(s.(name))
        v = double(s.(name));
    else
        v = defv;
    end
end

function out = localStringList(raw)
    if ischar(raw)
        out = string({raw});
    elseif iscellstr(raw)
        out = string(raw);
        out = out(:).';
    else
        out = string(raw);
        out = out(:).';
    end
end

function out = localNumericList(raw)
    if ischar(raw) || isstring(raw)
        out = str2double(cellstr(string(raw(:))));
    else
        out = double(raw(:));
    end
    out = out(:).';
    out = out(isfinite(out));
    if isempty(out)
        out = 3;
    end
end

function cases = localValidTPCCases(rateList, blocksList)
    maxTFBytes = 2048;
    cases = repmat(struct('TPCCodeRate',"", 'TPCBlocksPerTF',0, ...
        'NumBytesInTransferFrame',0), 0, 1);

    for iRate = 1:numel(rateList)
        rateName = string(rateList(iRate));
        for iBlk = 1:numel(blocksList)
            blocksPerTF = max(1, round(double(blocksList(iBlk))));
            tfBits = localTPCPayloadBits(rateName) * blocksPerTF;

            if mod(tfBits, 8) ~= 0
                fprintf(2, '[skip] TPC rate %s, blocks/TF %d gives %d info bits, not byte aligned.\n', ...
                    char(rateName), blocksPerTF, tfBits);
                continue;
            end

            tfBytes = tfBits / 8;
            if tfBytes > maxTFBytes
                fprintf(2, '[skip] TPC rate %s, blocks/TF %d gives %.0f bytes, exceeds NumBytesInTransferFrame limit %d.\n', ...
                    char(rateName), blocksPerTF, tfBytes, maxTFBytes);
                continue;
            end

            cases(end+1,1) = struct( ...
                'TPCCodeRate', rateName, ...
                'TPCBlocksPerTF', blocksPerTF, ...
                'NumBytesInTransferFrame', tfBytes); %#ok<AGROW>
        end
    end
end

function bits = localTPCPayloadBits(rateName)
    switch lower(strtrim(char(rateName)))
        case {'1/2','half'}
            side = 45;
        case {'2/3','twothirds','two-thirds'}
            side = 52;
        case {'native','57/64','57x57'}
            side = 57;
        otherwise
            error('sweep_tpc_modulations:InvalidTPCCodeRate', ...
                'Unsupported TPCCodeRate="%s".', char(rateName));
    end
    bits = side * side;
end

function nBytes = localTPCTransferFrameBytes(rateName, blocksPerTF)
    bits = localTPCPayloadBits(rateName) * max(1, round(double(blocksPerTF)));
    if mod(bits, 8) == 0
        nBytes = bits / 8;
    else
        nBytes = NaN;
    end
end
