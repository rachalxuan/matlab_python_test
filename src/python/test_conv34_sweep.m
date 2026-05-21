%% cfo gmsk speep
clc;
clear;

snrList = 8:1:22;
rateList = {'1/2','7/8'};

BER  = nan(length(rateList), length(snrList));
LOCK = nan(length(rateList), length(snrList));

for ir = 1:length(rateList)
    rateNow = rateList{ir};

    for k = 1:length(snrList)
        snrNow = snrList(k);

        fprintf('\nRate=%s, SNR=%.1f dB\n', rateNow, snrNow);

        p = struct('modType','GMSK','symbolRate',1e6,'sps',8, ...
                   'snr',snrNow,'cfo',20000,'phaseOffset',0,'delay',0, ...
                   'channelCoding','convolutional', ...
                   'ConvolutionalCodeRate',rateNow, ...
                   'NumBytesInTransferFrame',1046, ...
                   'BandwidthTimeProduct',0.5, ...
                   'hasASM',true, ...
                   'hasRandomizer',false, ...
                   'showFigures',false);

        out = run_ccsds_tm_evaluation(p);
        r = jsondecode(out);

        BER(ir,k)  = r.BER;
        LOCK(ir,k) = r.LockRate;

        fprintf('BER=%.3g, Lock=%.1f%%\n', r.BER, r.LockRate*100);
    end
end

figure;
hold on;
grid on;
for ir = 1:length(rateList)
    b = BER(ir,:);
    b(b == 0) = 1e-6;
    semilogy(snrList, b, '-o', 'LineWidth', 2, 'DisplayName', rateList{ir});
end
xlabel('SNR (dB)');
ylabel('BER');
title('GMSK: BER vs SNR for different convolutional rates');
legend('Location','best');
ylim([1e-6 1]);

figure;
hold on;
grid on;
for ir = 1:length(rateList)
    plot(snrList, LOCK(ir,:)*100, '-o', 'LineWidth', 2, 'DisplayName', rateList{ir});
end
xlabel('SNR (dB)');
ylabel('Frame Lock (%)');
title('GMSK: Lock vs SNR for different convolutional rates');
legend('Location','best');
ylim([0 100]);




%% oqpsk debug
% clc;
% clear;
% 
% caseList = {
%     'clean',      0,     0, 0;
%     'phaseOnly',  0,    15, 0;
%     'cfo2k',   2000,     0, 0;
%     'cfo5k',   5000,     0, 0;
%     'cfo20k', 20000,     0, 0;
%     'delay01',    0,     0, 0.1;
%     'delay035',   0,     0, 0.35;
%     'allLight',20000,   15, 0.35;
% };
% 
% for k = 1:size(caseList,1)
%     name = caseList{k,1};
%     cfoNow = caseList{k,2};
%     phaseNow = caseList{k,3};
%     delayNow = caseList{k,4};
% 
%     fprintf('\n==============================\n');
%     fprintf('OQPSK case: %s, CFO=%g, phase=%g, delay=%g\n', ...
%         name, cfoNow, phaseNow, delayNow);
%     fprintf('==============================\n');
% 
%     p = struct('modType','OQPSK','symbolRate',5e6,'sps',8, ...
%                'snr',10,'cfo',cfoNow,'phaseOffset',phaseNow,'delay',delayNow, ...
%                'channelCoding','RS', ...
%                'RolloffFactor',0.35, ...
%                'hasASM',true, ...
%                'hasRandomizer',false, ...
%                'showFigures',false);
% 
%     out = run_ccsds_tm_evaluation(p);
%     r = jsondecode(out);
% 
%     fprintf('BER=%.3g, Lock=%.1f%%, EVM=%.2f%%, MER=%.2f dB\n', ...
%         r.BER, r.LockRate*100, r.EVM_post_pct, r.MER_dB);
% end

%% 高码率
% clc;
% clear;
% 
% modList  = {'QPSK','8PSK'};
% rateList = {'3/4','5/6','7/8'};
% 
% numBytesTF = 1046;
% 
% snrList = 10:2:30;
% 
% symbolRate = 1e6;
% sps = 8;
% 
% % 固定损伤
% cfoNow = 20000;
% phaseNow = 15;
% delayNow = 0.35;
% 
% BER  = nan(length(modList), length(rateList), length(snrList));
% LOCK = nan(length(modList), length(rateList), length(snrList));
% EVM  = nan(length(modList), length(rateList), length(snrList));
% MER  = nan(length(modList), length(rateList), length(snrList));
% 
% for im = 1:length(modList)
%     for ir = 1:length(rateList)
% 
%         modNow = modList{im};
%         rateNow = rateList{ir};
% 
%         fprintf('\n========================================\n');
%         fprintf('SNR sweep: %s rate %s\n', modNow, rateNow);
%         fprintf('========================================\n');
% 
%         for is = 1:length(snrList)
% 
%             snrNow = snrList(is);
% 
%             fprintf('\n------------------------------\n');
%             fprintf('Running %s rate %s, SNR = %.1f dB\n', ...
%                 modNow, rateNow, snrNow);
%             fprintf('------------------------------\n');
% 
%             p = struct( ...
%                 'modType',modNow, ...
%                 'symbolRate',symbolRate, ...
%                 'sps',sps, ...
%                 'snr',snrNow, ...
%                 'cfo',cfoNow, ...
%                 'phaseOffset',phaseNow, ...
%                 'delay',delayNow, ...
%                 'channelCoding','convolutional', ...
%                 'ConvolutionalCodeRate',rateNow, ...
%                 'NumBytesInTransferFrame',numBytesTF, ...
%                 'RolloffFactor',0.35, ...
%                 'hasASM',true, ...
%                 'hasRandomizer',false, ...
%                 'showFigures',false);
% 
%             out = run_ccsds_tm_evaluation(p);
%             r = jsondecode(out);
% 
%             BER(im,ir,is)  = r.BER;
%             LOCK(im,ir,is) = r.LockRate;
%             EVM(im,ir,is)  = r.EVM_post_pct;
%             MER(im,ir,is)  = r.MER_dB;
% 
%             fprintf('[SNR SUMMARY] %s %s SNR=%.1f: BER=%.3g, Lock=%.1f%%, EVM=%.2f%%, MER=%.2f dB\n', ...
%                 modNow, rateNow, snrNow, r.BER, r.LockRate*100, r.EVM_post_pct, r.MER_dB);
%         end
%     end
% end
% 
% save('sweep_snr_highrate.mat', ...
%     'modList','rateList','snrList','BER','LOCK','EVM','MER');
% 
% % =========================
% % Plot BER
% % =========================
% for im = 1:length(modList)
% 
%     figure;
%     hold on;
% 
%     for ir = 1:length(rateList)
%         berPlot = squeeze(BER(im,ir,:));
%         berPlot(berPlot == 0) = 1e-6;
% 
%         semilogy(snrList, berPlot, '-o', 'LineWidth', 2);
%     end
% 
%     grid on;
%     xlabel('SNR (dB)');
%     ylabel('BER');
%     title([modList{im} ' BER vs SNR']);
%     legend(rateList, 'Location','southwest');
%     ylim([1e-6 1]);
% end
% 
% % =========================
% % Plot Lock
% % =========================
% for im = 1:length(modList)
% 
%     figure;
%     hold on;
% 
%     for ir = 1:length(rateList)
%         plot(snrList, squeeze(LOCK(im,ir,:))*100, '-o', 'LineWidth', 2);
%     end
% 
%     grid on;
%     xlabel('SNR (dB)');
%     ylabel('Frame Lock (%)');
%     title([modList{im} ' Frame Lock vs SNR']);
%     legend(rateList, 'Location','southeast');
%     ylim([0 100]);
% end
% 
% % =========================
% % Plot EVM
% % =========================
% for im = 1:length(modList)
% 
%     figure;
%     hold on;
% 
%     for ir = 1:length(rateList)
%         plot(snrList, squeeze(EVM(im,ir,:)), '-o', 'LineWidth', 2);
%     end
% 
%     grid on;
%     xlabel('SNR (dB)');
%     ylabel('EVM (%)');
%     title([modList{im} ' EVM vs SNR']);
%     legend(rateList, 'Location','northeast');
% end

%% ------SNR
% clc;
% clear;
% 
% modList = {'QPSK', '8PSK'};
% 
% symbolRate = 1e6;
% sps = 8;
% 
% snrList = 0:2:24;
% 
% % 固定损伤
% cfoVal = 50000;
% phaseVal = 30;
% delayVal = 0.35;
% 
% BER  = zeros(length(modList), length(snrList));
% EVM  = zeros(length(modList), length(snrList));
% MER  = zeros(length(modList), length(snrList));
% LOCK = zeros(length(modList), length(snrList));
% 
% for m = 1:length(modList)
% 
%     modNow = modList{m};
% 
%     fprintf('\n============================================\n');
%     fprintf('Testing modulation = %s, convolutional 3/4\n', modNow);
%     fprintf('============================================\n');
% 
%     for k = 1:length(snrList)
% 
%         snrNow = snrList(k);
% 
%         fprintf('\n------------------------------\n');
%         fprintf('running %s, SNR = %.1f dB\n', modNow, snrNow);
%         fprintf('------------------------------\n');
% 
%         p = struct( ...
%             'modType', modNow, ...
%             'symbolRate', symbolRate, ...
%             'sps', sps, ...
%             'snr', snrNow, ...
%             'cfo', cfoVal, ...
%             'phaseOffset', phaseVal, ...
%             'delay', delayVal, ...
%             'channelCoding', 'convolutional', ...
%             'ConvolutionalCodeRate', '3/4', ...
%             'RolloffFactor', 0.35, ...
%             'hasASM', true, ...
%             'hasRandomizer', false, ...
%             'showFigures', false);
% 
%         out = run_ccsds_tm_evaluation(p);
%         r = jsondecode(out);
% 
%         BER(m,k)  = r.BER;
%         EVM(m,k)  = r.EVM_post_pct;
%         MER(m,k)  = r.MER_dB;
%         LOCK(m,k) = r.LockRate;
% 
%         fprintf('%s | SNR=%5.1f dB, BER=%.3g, Lock=%.1f%%, EVM=%.2f%%, MER=%.2f dB\n', ...
%             modNow, snrNow, r.BER, r.LockRate*100, r.EVM_post_pct, r.MER_dB);
% 
%     end
% end
% 
% berPlot = BER;
% berPlot(berPlot == 0) = 1e-6;
% 
% figure;
% semilogy(snrList, berPlot(1,:), '-o', 'LineWidth', 2);
% hold on;
% semilogy(snrList, berPlot(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('SNR (dB)');
% ylabel('BER');
% title('TM convolutional 3/4: BER vs SNR');
% legend(modList, 'Location', 'best');
% ylim([1e-6 1]);
% 
% figure;
% plot(snrList, LOCK(1,:)*100, '-o', 'LineWidth', 2);
% hold on;
% plot(snrList, LOCK(2,:)*100, '-s', 'LineWidth', 2);
% grid on;
% xlabel('SNR (dB)');
% ylabel('Frame Lock (%)');
% title('TM convolutional 3/4: Frame Lock vs SNR');
% legend(modList, 'Location', 'best');
% ylim([0 100]);
% 
% figure;
% plot(snrList, EVM(1,:), '-o', 'LineWidth', 2);
% hold on;
% plot(snrList, EVM(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('SNR (dB)');
% ylabel('EVM (%)');
% title('TM convolutional 3/4: EVM vs SNR');
% legend(modList, 'Location', 'best');
% 
% figure;
% plot(snrList, MER(1,:), '-o', 'LineWidth', 2);
% hold on;
% plot(snrList, MER(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('SNR (dB)');
% ylabel('MER (dB)');
% title('TM convolutional 3/4: MER vs SNR');
% legend(modList, 'Location', 'best');
%% CFO

% clc;
% clear;
% 
% % =========================================================
% % TM convolutional 3/4 CFO sweep
% % 测试普通 TM 链路，不是 FACM
% % =========================================================
% 
% modList = {'QPSK', '8PSK'};
% 
% % 符号率和采样率
% symbolRate = 1e6;
% sps = 8;
% 
% % CFO 扫描范围
% cfoList = [0 10000 20000 50000 80000 100000 150000 200000];
% 
% % 固定信道参数
% snrVal = 20;
% phaseVal = 30;
% delayVal = 0.35;
% 
% % 结果矩阵：行 = 调制方式，列 = CFO 点
% BER  = zeros(length(modList), length(cfoList));
% EVM  = zeros(length(modList), length(cfoList));
% MER  = zeros(length(modList), length(cfoList));
% LOCK = zeros(length(modList), length(cfoList));
% 
% for m = 1:length(modList)
% 
%     modNow = modList{m};
% 
%     fprintf('\n============================================\n');
%     fprintf('Testing modulation = %s, convolutional 3/4\n', modNow);
%     fprintf('============================================\n');
% 
%     for k = 1:length(cfoList)
% 
%         cfoNow = cfoList(k);
% 
%         fprintf('\n------------------------------\n');
%         fprintf('running %s, CFO = %7.0f Hz\n', modNow, cfoNow);
%         fprintf('------------------------------\n');
% 
%         p = struct( ...
%             'modType', modNow, ...
%             'symbolRate', symbolRate, ...
%             'sps', sps, ...
%             'snr', snrVal, ...
%             'cfo', cfoNow, ...
%             'phaseOffset', phaseVal, ...
%             'delay', delayVal, ...
%             'channelCoding', 'convolutional', ...
%             'ConvolutionalCodeRate', '3/4', ...
%             'RolloffFactor', 0.35, ...
%             'hasASM', true, ...
%             'hasRandomizer', false, ...
%             'showFigures', false);
% 
%         out = run_ccsds_tm_evaluation(p);
%         r = jsondecode(out);
% 
%         BER(m,k)  = r.BER;
%         EVM(m,k)  = r.EVM_post_pct;
%         MER(m,k)  = r.MER_dB;
%         LOCK(m,k) = r.LockRate;
% 
%         fprintf('%s | CFO=%7.0f Hz, BER=%.3g, Lock=%.1f%%, EVM=%.2f%%, MER=%.2f dB\n', ...
%             modNow, cfoNow, r.BER, r.LockRate*100, r.EVM_post_pct, r.MER_dB);
% 
%     end
% end
% 
% % =========================================================
% % 画图
% % =========================================================
% 
% % BER 图，0 BER 用显示下限替代
% berPlot = BER;
% berPlot(berPlot == 0) = 1e-6;
% 
% figure;
% semilogy(cfoList/1000, berPlot(1,:), '-o', 'LineWidth', 2);
% hold on;
% semilogy(cfoList/1000, berPlot(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('CFO (kHz)');
% ylabel('BER');
% title('TM convolutional 3/4: BER vs CFO');
% legend(modList, 'Location', 'best');
% ylim([1e-6 1]);
% 
% figure;
% plot(cfoList/1000, LOCK(1,:)*100, '-o', 'LineWidth', 2);
% hold on;
% plot(cfoList/1000, LOCK(2,:)*100, '-s', 'LineWidth', 2);
% grid on;
% xlabel('CFO (kHz)');
% ylabel('Frame Lock (%)');
% title('TM convolutional 3/4: Frame Lock vs CFO');
% legend(modList, 'Location', 'best');
% ylim([0 100]);
% 
% figure;
% plot(cfoList/1000, EVM(1,:), '-o', 'LineWidth', 2);
% hold on;
% plot(cfoList/1000, EVM(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('CFO (kHz)');
% ylabel('EVM (%)');
% title('TM convolutional 3/4: EVM vs CFO');
% legend(modList, 'Location', 'best');
% 
% figure;
% plot(cfoList/1000, MER(1,:), '-o', 'LineWidth', 2);
% hold on;
% plot(cfoList/1000, MER(2,:), '-s', 'LineWidth', 2);
% grid on;
% xlabel('CFO (kHz)');
% ylabel('MER (dB)');
% title('TM convolutional 3/4: MER vs CFO');
% legend(modList, 'Location', 'best');