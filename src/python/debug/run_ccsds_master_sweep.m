function results = run_ccsds_master_sweep()
clc;

snrList = [0 2 4 6 8 10 12];

fprintf('\n================ MASTER CCSDS SWEEP ================\n');

results = table();

%% =========================================================
% 1. TM 基础体制（BPSK/QPSK/8PSK）
% =========================================================
modList = ["BPSK","QPSK","8PSK"];
codeList = ["none","convolutional"];
pcmList  = ["NRZ-L","NRZ-M","NRZ-S"];

for m = modList
    for c = codeList
        for p = pcmList

            for snr = snrList

                cfg = struct( ...
                    'modType', m, ...
                    'symbolRate', 20e6, ...
                    'sps', 4, ...
                    'snr', snr, ...
                    'cfo', 2e4, ...
                    'phaseOffset', 10, ...
                    'delay', 0.1, ...
                    'channelCoding', c, ...
                    'PCMFormat', p, ...
                    'hasASM', true, ...
                    'hasRandomizer', false, ...
                    'berWarmUpFrames', 4, ...
                    'berFrames', 20, ...
                    'showFigures', false);

                out = run_ccsds_tm_evaluation(cfg);

                results = addRow(results, m, c, p, snr, out);
                printRow(m,c,p,snr,out);

            end
        end
    end
end


% %% =========================================================
% % 2. 高阶调制（QAM）
% % =========================================================
% qamList = ["16QAM","32QAM"];
% 
% for m = qamList
%     for c = ["convolutional","LDPC"]
% 
%         for snr = snrList
% 
%             cfg = struct( ...
%                 'modType', m, ...
%                 'symbolRate', 20e6, ...
%                 'sps', 4, ...
%                 'snr', snr, ...
%                 'cfo', 2e4, ...
%                 'channelCoding', c, ...
%                 'PCMFormat', "NRZ-L", ...
%                 'hasASM', true, ...
%                 'hasRandomizer', false, ...
%                 'berWarmUpFrames', 4, ...
%                 'berFrames', 20, ...
%                 'showFigures', false);
% 
%             out = run_ccsds_tm_evaluation(cfg);
%             results = addRow(results, m, c, "NRZ-L", snr, out);
%             printRow(m,c,"NRZ-L",snr,out);
% 
%         end
%     end
% end
% 
% 
% %% =========================================================
% % 3. UQPSK（单独体制）
% % =========================================================
% for snr = [0 4 8 12]
% 
%     cfg = struct( ...
%         'modType', "UQPSK", ...
%         'symbolRate', 100e6, ...
%         'sps', 8, ...
%         'snr', snr, ...
%         'cfo', 5e4, ...
%         'phaseOffset', 10, ...
%         'delay', 0.1, ...
%         'channelCoding', "convolutional", ...
%         'ConvolutionalCodeRate', "1/2", ...
%         'RRatio', 2, ...
%         'ARatio', 2, ...
%         'enableUQPSKFFTCoarseCFO', true, ...
%         'showFigures', false, ...
%         'debugUQPSK', false);
% 
%     out = run_ccsds_tm_evaluation(cfg);
% 
%     results = addRow(results, "UQPSK", "conv", "N/A", snr, out);
%     printRow("UQPSK","conv","N/A",snr,out);
% 
% end
% 
% 
% %% =========================================================
% % 4. FM（只扫 SNR + CFO）
% % =========================================================
% for snr = [0 4 8 12]
%     for cfo = [0 2e6 5e6]
% 
%         cfg = struct( ...
%             'modType', "FM", ...
%             'symbolRate', 20e6, ...
%             'sps', 4, ...
%             'snr', snr, ...
%             'cfo', cfo, ...
%             'phaseOffset', 10, ...
%             'delay', 0.1, ...
%             'channelCoding', "convolutional", ...
%             'hasASM', true, ...
%             'hasRandomizer', false, ...
%             'showFigures', false, ...
%             'debugFM', false);
% 
%         out = run_ccsds_tm_evaluation(cfg);
% 
%         results = addRow(results, "FM","conv","N/A",snr,out);
%         printRow("FM","conv","N/A",snr,out);
% 
%     end
% end
% 
% 
% %% =========================================================
% % 5. TPC（独立测试）
% % =========================================================
% for snr = [0 4 8 12]
% 
%     cfg = struct( ...
%         'modType', "BPSK", ...
%         'symbolRate', 20e6, ...
%         'sps', 4, ...
%         'snr', snr, ...
%         'cfo', 2e4, ...
%         'channelCoding', "TPC", ...
%         'hasASM', true, ...
%         'hasRandomizer', false, ...
%         'showFigures', false, ...
%         'tpcIterations', 6);
% 
%     out = run_ccsds_tm_evaluation(cfg);
% 
%     results = addRow(results, "BPSK","TPC","NRZ-L",snr,out);
%     printRow("BPSK","TPC","NRZ-L",snr,out);
% 
% end


%% =========================================================
disp(' ');
disp('================ FINAL SUMMARY ================');
disp(results);

end

%% =========================================================
function results = addRow(results, m, c, p, snr, out)

out = localDecodeOutput(out);

results = [results; table( ...
    string(m), string(c), string(p), snr, ...
    getf(out, {'BER','ber'}), ...
    getLockPct(out), ...
    getf(out, {'EVM_post_pct','EVM'}), ...
    'VariableNames', {'Mod','Coding','PCM','SNR','BER','Lock','EVM'})];

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

function v = getf(s, names)
v = NaN;
if ischar(names) || isstring(names)
    names = cellstr(names);
end
for k = 1:numel(names)
    f = names{k};
    if isfield(s, f) && ~isempty(s.(f))
        v = double(s.(f));
        return;
    end
end
end

function lockPct = getLockPct(out)
lockPct = getf(out, {'FrameLock_pct','LockRate_pct','FrameLock'});
if isnan(lockPct)
    lockVal = getf(out, {'LockRate','lockRate'});
    if ~isnan(lockVal)
        if lockVal <= 1
            lockPct = 100 * lockVal;
        else
            lockPct = lockVal;
        end
    end
end
end

function printRow(m,c,p,snr,out)
out = localDecodeOutput(out);
fprintf('[%s | %s | %s | SNR=%d] BER=%.3g  LOCK=%.1f%%\n', ...
    m,c,p,snr, getf(out, {'BER','ber'}), getLockPct(out));
end
