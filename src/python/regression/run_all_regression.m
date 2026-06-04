%% sweep_ccsds_regression_suite.m
% 系统回归测试脚本：支持多调制、多编码、多信道H多径

clc;
clear;

%% 基础参数
base = struct('modType','8PSK', ...
    'symbolRate',1e6, ...
    'sps',8, ...
    'snr',12, ...
    'cfo',50000, ...
    'phaseOffset',10, ...
    'delay',0.3, ...
    'channelCoding','none', ...
    'NumBytesInTransferFrame',1115, ...
    'RolloffFactor',0.35, ...
    'hasASM',true, ...
    'hasRandomizer',false, ...
    'showFigures',false, ...
    'berWarmUpFrames',5, ...
    'berFrames',20, ...
    'enableHChannel',true, ...
    'HMode','siso_multipath', ...
    'normalizeHChannel',true);

%% 测试调制方式
modulations = {'8PSK','QPSK','OQPSK','GMSK','PCM/PM/biphase-L'};

%% 测试编码方式
codings = {'none','RS','convolutional','LDPC'};

%% 信道H多径配置（可调强度）
Hcases = {
    struct('name','mild', 'H',[1,0,0.25*exp(1j*pi/3),0,0.10*exp(-1j*pi/4)]), ...
    struct('name','strong', 'H',[1,0,0.85*exp(1j*pi/3),0,0.60*exp(-1j*pi/4),0,0.40*exp(1j*pi/2)]) ...
};

%% 初始化结果表
results = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Modulation','Coding','Channel','BER','LockRate_pct'});

%% 主循环
for m = 1:numel(modulations)
    modType = modulations{m};
    for c = 1:numel(codings)
        coding = codings{c};

        for hIdx = 1:numel(Hcases)
            Hcase = Hcases{hIdx};

            p = base;
            p.modType = modType;
            p.channelCoding = coding;
            p.H = Hcase.H;  % 多径
            p.enableHChannel = true;
            p.debugGMSK = strcmp(modType, 'GMSK');

            % 设置编码特有字段
            switch coding
                case 'RS'
                    p.RSMessageLength = 223;
                    p.RSInterleavingDepth = 1;
                    p.IsRSMessageShortened = false;
                case 'convolutional'
                    p.ConvolutionalCodeRate = '2/3';
                case 'LDPC'
                    p.LDPCCodeRate = '1/2';
            end

            fprintf('\n========== Test: %s + %s + H=%s ==========\n', modType, coding, Hcase.name);
            outRaw = run_ccsds_tm_evaluation(p);

            % JSON字符串解析
            if ischar(outRaw) || isstring(outRaw)
                out = jsondecode(char(outRaw));
            else
                out = outRaw;
            end

            fprintf('BER=%g, Lock=%.2f%%\n', out.BER, out.LockRate*100);

            results = [results; {modType, coding, Hcase.name, out.BER, out.LockRate*100}]; %#ok<AGROW>
        end
    end
end

%% 显示汇总结果
disp(results);
