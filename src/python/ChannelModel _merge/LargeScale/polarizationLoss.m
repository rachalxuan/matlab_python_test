function [loss_dB, faradayAngle_deg] = polarizationLoss(fc_GHz, elevation, polTx, polRx, TEC)
% polarizationLoss - 计算星地链路极化失配与法拉第旋转损耗 (面向过程版)
%
% 输入参数:
%   fc_GHz    - 载波频率 [GHz] (注意是 GHz)
%   elevation - 终端可视仰角 [deg]
%   polTx     - 发射天线极化 ('Linear-H', 'Linear-V', 'RHCP', 'LHCP', 'Matched')
%   polRx     - 接收天线极化 ('Linear-H', 'Linear-V', 'RHCP', 'LHCP', 'Matched')
%   TEC       - 电离层总电子含量 [TECU] (可选参数, 默认 20)
%
% 输出参数:
%   loss_dB          - 极化失配引发的额外损耗 [dB] (正值代表损耗)
%   faradayAngle_deg - 电磁波穿透电离层发生的法拉第旋转角 [deg]

    % 如果未输入 TEC，赋默认值 20
    if nargin < 5 || isempty(TEC)
        TEC = 20; 
    end
    
    % 如果设置为“匹配”，代表理想接收，损耗直接为 0 dB
    if strcmp(polTx, 'Matched') || strcmp(polRx, 'Matched')
        loss_dB = 0;
        faradayAngle_deg = 0;
        return;
    end
    
    % =============================================================
    % 1. 计算法拉第旋转角 (Faraday Rotation Angle)
    % =============================================================
    % 倾斜因子 (Slant Factor): 仰角越低，穿过电离层的物理路径越长
    if elevation < 10
         slantFactor = 1 / sind(10); % 保护机制：低于 10 度时按 10 度算，防除零
    else
         slantFactor = 1 / sind(elevation);
    end
    
    % 核心物理公式: 旋转角 [度] = 108 * TEC / f_GHz^2 * 倾斜因子
    faradayAngle_deg = (108 * TEC / (fc_GHz^2)) * slantFactor;
    
    % =============================================================
    % 2. 构造琼斯矢量 (Jones Vectors)
    % =============================================================
    vecTx = getJonesVector(polTx);
    vecRx = getJonesVector(polRx);
    
    % =============================================================
    % 3. 应用电离层法拉第旋转 (仅对入射波矢量进行坐标旋转)
    % =============================================================
    theta_rad = deg2rad(faradayAngle_deg);
    % 2D 旋转矩阵
    R = [cos(theta_rad), -sin(theta_rad); 
         sin(theta_rad),  cos(theta_rad)];
         
    vecInc = R * vecTx; % 到达地面的实际信号极化状态
    
    % =============================================================
    % 4. 计算极化损耗因子 (PLF) 与 最终损耗 dB
    % =============================================================
    % PLF 定义为接收天线与入射波矢量内积的平方 (注意共轭转置 ')
    plf = abs(vecRx' * vecInc)^2;
    
    % 物理保护：限制最小 PLF，防止计算 log10(0) 导致 -Inf 崩溃画图引擎
    plf = max(plf, 1e-6); 
    
    loss_dB = -10 * log10(plf);
end

function vec = getJonesVector(type)
% 内部辅助函数：获取各种极化方式的标准归一化琼斯矢量
    switch type
        case 'Linear-H'  % 水平线极化
            vec = [1; 0];
        case 'Linear-V'  % 垂直线极化
            vec = [0; 1];
        case 'Linear-45' % 45度极化
            vec = [1; 1] / sqrt(2);
        case 'RHCP'      % 右旋圆极化
            vec = [1; -1j] / sqrt(2);
        case 'LHCP'      % 左旋圆极化
            vec = [1; 1j] / sqrt(2);
        otherwise
            vec = [1; 0]; % 兜底处理
    end
end