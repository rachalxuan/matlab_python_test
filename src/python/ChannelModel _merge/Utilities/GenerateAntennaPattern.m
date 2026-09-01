% =========================================================
% 脚本：生成供 CDL 模型使用的天线 3D 方向图矩阵
% =========================================================
clear; clc;

% 1. 定义高分辨率的空间角度网格 (单位：度)
% 方位角 Phi: 0 到 360 度
% 俯仰角/天顶角 Theta: 0 到 180 度
phi_grid = linspace(0, 360, 361); 
theta_grid = linspace(0, 180, 181);
[Phi_Mesh, Theta_Mesh] = meshgrid(phi_grid, theta_grid);

% 将角度转为弧度用于公式计算
Phi_rad = Phi_Mesh * pi / 180;
Theta_rad = Theta_Mesh * pi / 180;

%% ---------------------------------------------------------
% 2. 生成终端接收天线 (UE Rx) - 宽波束贴片天线模型
% ----------------------------------------------------------
% 假设终端天线主要向上辐射，Theta > 90 (下半球) 辐射很小
% 极化方向：假设主要为 Theta 极化 (垂直极化主导)
G_rx_max = 5; % 最大增益 5 dBi 左右
Rx_Pattern_Theta = G_rx_max * (cos(Theta_rad) .* (Theta_rad <= pi/2)); % 仅上半球有较强辐射
Rx_Pattern_Phi   = 0.1 * ones(size(Theta_Mesh)); % 交叉极化分量(水平)很小，给个底噪

%% ---------------------------------------------------------
% 3. 生成卫星发射天线 (Sat Tx) - 高定向点波束模型
% ----------------------------------------------------------
% 假设波束极窄，且采用 +/- 45度双线极化发射
beamwidth = 10 * pi / 180; % 3dB 波束宽度 10度
G_tx_max = 30; % 最大增益 30 dBi
% 用高斯包络模拟高定向波束 (聚焦在 Theta = 0 正下方)
SpotBeam = G_tx_max * exp(- (Theta_rad.^2) / (2 * (beamwidth/2.35)^2) );

% 将总增益投影到 Theta 和 Phi 两个极化方向 (模拟 45 度倾斜极化)
Tx_Pattern_Theta = SpotBeam * cos(pi/4);
Tx_Pattern_Phi   = SpotBeam * sin(pi/4);

%% ---------------------------------------------------------
% 4. 保存为标准 .mat 数据文件，供平台调用
% ----------------------------------------------------------
save('Antenna_Data.mat', 'phi_grid', 'theta_grid', ...
     'Rx_Pattern_Theta', 'Rx_Pattern_Phi', ...
     'Tx_Pattern_Theta', 'Tx_Pattern_Phi');

disp('✅ 天线方向图数据已成功生成并保存为 Antenna_Data.mat！');

% 画个图看看我们生成的 UE 天线长什么样
figure;
surf(Phi_Mesh, Theta_Mesh, abs(Rx_Pattern_Theta), 'EdgeColor', 'none');
title('生成的 UE 终端天线方向图 (Theta 极化)');
xlabel('方位角 \phi (deg)'); ylabel('天顶角 \theta (deg)'); zlabel('场强/增益');
colormap('jet'); colorbar;