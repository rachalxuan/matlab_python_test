function [A_infinity] = ionosphericScintillation(parameter,EOA)
    month = parameter.month;                   % 一年中的第几月
    day = parameter.day;                       % 一年中的第几天
    t = parameter.time;
    latitude = parameter.terminalLatitude;     % 观测地纬度
    f = parameter.fc * 1e6;                          % 信号频率，单位为 MHz
    % 计算太阳赤纬角 δ
    delta = -23.44 * cosd(360 * (day + 10) / 365);  % 使用cosd以度为单位

    % 计算时角 τ
    tau = 15 * abs(t - 12); % 时角

    % 计算太阳天顶角 χ
    chi = acosd(sind(delta) * sind(latitude) + cosd(delta) * cosd(latitude) * cosd(tau));  % 使用acosd以度为单位

    % 太阳黑子数数据（2022年6月到2024年6月）
    R = [144.97, 154.5, 159.45, 111.0, 143.0, 171.0  ... % 2022年7月到12月
        143.0, 110.0, 143.0, 171.0, 164.0, 196.0, ... % 2023年1月到6月
        215.0, 148.0,159.0, 145.0, 155.0, 160.0, ... % 2023年7月到12月
        160.0, 155.0, 160.0, 170.0, 175.0, 160.0]; % 2024年1月到6月
    
    % 计算2023年1月到12月的12个月流动平均值
    R12 = zeros(1, 12);  % 用于存储12个月流动平均值
    for n = 1:12
        % 计算当前月的流动平均值，取前后6个月
        start_idx = n;  % 确保开始索引不小于1
        end_idx = min(24, n+11);   % 确保结束索引不大于24
        R12(n) = mean(R(start_idx:end_idx));  % 计算该月的流动平均
    end

    r12 = R12(month);  % 获取选定月份的流动平均值

    % 计算磁旋频率 fH
    if latitude >= 22 && latitude < 35
        fH = 1.3;  % 北纬22°~35°之间
    elseif latitude >= 35 && latitude < 45
        fH = 1.4;  % 北纬35°~45°之间
    elseif latitude >= 45 && latitude <= 55
        fH = 1.5;  % 北纬45°~55°之间
    else
        fH = NaN;  % 设置为NaN表示无效值
    end

    % 计算电离层的吸收
    i100 = asin(0.985 * cosd(EOA));  % i100以弧度计算

    % 吸收指数计算
    I = (1 + 0.0037 * r12) * (abs(cosd(0.881 * chi)))^1.3;

    % 电离层吸收计算
    A_infinity = 677.2 * I * sec(i100) / ((f + fH)^1.98 + 10.2) + 7.3;  % sec()需要i100是弧度
end

