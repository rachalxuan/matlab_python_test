function [H_Martix_tMode,fd_shift,tao] = generateJakesSpec(parameter,satVelRange,EOA,costheta)
% =========================================================================
% 多径信道核心计算引擎 (后端处理 - 严谨物理修正版)
% 输入：configData (包含全局物理参数与多径表格)
% 输出：H_matrix (复数信道矩阵，维度：径数 x 每秒点数N x 仿真秒数Tsim)
% =========================================================================
    
    % 1. 解析全局参数
    rng(parameter.Seed); 
    fs = parameter.Fs;
    
    % 2. 物理层公式：将速度与载频转化为最大多普勒频移
    fc_Hz = parameter.fc * 1e9; 
    v_ms = parameter.terminalVel; 
    c = 3e8;                     
    fd = (v_ms / c) * fc_Hz;     
    dT = parameter.T;
    % 3. 初始化时频轴与内存
    N = fs * dT; 
    f_axis = (-N/2 : N/2-1) * (fs/N); 
    nPaths = parameter.nPaths;
    h = parameter.satelliteHeight;
    R = 6371e3;
    fd_shift = (satVelRange/c) * (R/(R+h)) * cosd(EOA) * fc_Hz;
    % 预分配 3D 内存矩阵
    H_Martix_tMode = complex(zeros(nPaths, N,size(parameter.GainTx,1)));
    H_Martix_t = complex(zeros(nPaths, N));
    % data = parameter.antennaGainData;
    % [~,Gain] = GenerateAntennaPattern_Gain([0,EOA,0],EOA+90,0,data);
    tao = zeros(nPaths,1);
        for i = 1:nPaths
            power_dB   = parameter.power_dB(1);
            if i == 1 && parameter.IsLos
                fadingType = parameter.fadingType{1};
                parameter.dopplerPhaselos = 2*pi*(1/parameter.Fs)*(fd_shift + fc_Hz)* (v_ms / c)*costheta* (0:N)';
            else
                fadingType = parameter.fadingType{2};
            end 
            specType   = parameter.specType{1}; 
            % extraParam = parameter.K; % K / m / sigma_dB
            
            % [核心 1]：生成多普勒功率谱密度 (PSD)
            S = generateDopplerFilter(specType, f_axis, fd);
            
            % [核心 2]：生成绝对单位功率归一化的衰落系数 (E|h|^2 = 1)
            h_normalized = generateFadingCoeffs(fadingType, S, N, parameter);
            
            % [核心 3]：精准赋予指定的多径相对功率
            linear_power = 10^(power_dB / 10);
            H_Martix = h_normalized * sqrt(linear_power);    
            dopplerPhase = 2*pi*(1/fs)*(fd_shift) * (0:N)';
            H_Martix_t(i,:) = H_Martix.*exp(-1j*dopplerPhase(1:(end-1),1))';

            tao(i) = parameter.tao + (i-1)*30e-9;
        end
        
        if ~isfield(parameter,'GainTx')
            parameter.GainTx = 1;
        end

        for j = 1:size(parameter.GainTx,2)
            H_Martix_tMode(:,:,j) = parameter.GainTx(j) * H_Martix_t * parameter.GainRx;
        end


end 


% =========================================================================
% 子函数 1：多普勒成型滤波器 (生成 PSD 形状)
% =========================================================================
function S = generateDopplerFilter(specType, f_axis, fd)
    N = length(f_axis);
    S = zeros(1, N);
    idx = abs(f_axis) < fd;
    
    if strcmp(specType, 'Jakes')
        S(idx) = 1 ./ (pi * fd * sqrt(1 - (f_axis(idx)/fd).^2 + realmin));  
    % elseif strcmp(specType, 'Flat')
    %     S(idx) = 1 ./ (2 * fd);
    % elseif strcmp(specType, 'Gaussian')
    %     sigma_gauss = 1; 
    %     S(idx) = (1/sqrt(2*pi*sigma_gauss^2)) * exp(-f_axis(idx).^2 / (2*sigma_gauss^2));
    else
        S(idx) = 1; 
    end
    
    % 归一化 PSD (确保积分总能量为1，提升后续数值稳定性)
    df = f_axis(2) - f_axis(1);
    S = S / (sum(S)*df);
    
    % 转换为 MATLAB 的逻辑频域 
    S = ifftshift(S); 
end

% =========================================================================
% 子函数 2：单径衰落系数生成器 (完全修正数学推导版)
% =========================================================================
function h_coeff = generateFadingCoeffs(fadingType, S, N, parameter)
    % 1. 基础复高斯白噪声
    I = randn(1, N); 
    Q = randn(1, N); 
    
    %  频谱成型必须乘以 sqrt(S)，而不是 S
    H_filter = sqrt(S);
    
    filtered_I = ifft(fft(I, N) .* H_filter, N);
    filtered_Q = ifft(fft(Q, N) .* H_filter, N);
    
    % 无论生成什么，必须先获取单位功率的纯散射径
    h_scatter = filtered_I + 1j * filtered_Q;
    h_scatter = h_scatter / sqrt(mean(abs(h_scatter).^2)); % 强制归一化 E|h|^2=1

    % 2. 注入特定衰落的统计特性
    if strcmp(fadingType, 'Rayleigh')
        h_coeff = h_scatter; % 纯散射，已经是单位功率
        
    elseif strcmp(fadingType, 'Rican')
        K = parameter.K; % 莱斯因子 (线性)
        % 严谨的莱斯功率分配：总功率 = P_los + P_scatter = 1
        P_scatter = 1 / (K + 1);
        P_los = K / (K + 1);
        % 添加直射径 (由于仿真秒数切割，这里用简化版直流0Hz作为LOS，保证能量正确)
        A = sqrt(P_los); 
        h_coeff = sqrt(P_scatter) * h_scatter + A*exp(-1j*parameter.dopplerPhaselos(1:(end-1),1))'; % 时域直接加直流分量
    else
        h_coeff = ones(1, N); % 容错
    end
end
