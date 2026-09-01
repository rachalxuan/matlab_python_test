function H_matrix = Lutz(fs,T,fc,v,mu_dB,sigma_dB,K_linear,manual_state,costheta)
% =========================================================================
% CLoo信道系数生成
% 输入：
% mu_dB       % 对数正态均值 
% sigma_dB    % 对数正态标准差 
% K_linear    % 莱斯 K 因子 (线性值)，控制直射径与多径的功率比
% manual_state % 手动状态开关：1 为全“好状态”，0 为全“坏状态”  
% fs = 1000;  %采样频率 单位Hz
% T = 1;      %采样时间 单位s
% fc = 2e9;   %载波频率 单位Hz
% 输出：H_matrix %复数信道矩阵
% ========================================================================= 
        c = 3e8;%光速 单位（m/s)
        %计算多普勒频率
        fd = (v*fc)/c;
        %计算FFT和IFFT的点数
        N = T*fs;
        %生成多普勒滤波器
        f = (-N/2:N/2-1)*(fs/N); %生成-N/2到N/2-1的对称频率轴
        H_Jakes = zeros(1,N);%生成1行，N列的全0向量
        idx = abs(f) < fd;%定义索引
        H_Jakes(idx) = 1./(pi*fd*sqrt(1 - (f(idx)/fd).^2));
        H_Jakes = ifftshift(H_Jakes);
        %生成两路高斯白噪声
        I = randn(1, N); 
        Q = randn(1, N);
        
        %生成多径瑞利散射分量
        filtered_I = ifft(fft(I, N) .* H_Jakes, N);
        filtered_Q = ifft(fft(Q, N) .* H_Jakes, N);
        
        % 归一化、叠加
        filtered_I = (filtered_I / sqrt(mean(filtered_I.^2))) * sqrt(0.5);
        filtered_Q = (filtered_Q / sqrt(mean(filtered_Q.^2))) * sqrt(0.5);
        rayleigh_comp = filtered_I + 1j * filtered_Q;
        
        %根据参数选择信道状态
        if manual_state == 1
            % 好信道   纯莱斯分布：直射径加上多径杂波
            A_rice = sqrt(K_linear); 
            %为直射分量设置相位
            phi = 2 * pi * rand(1, 1); % 均匀分布的随机相位 给直射分量设置随机的起点相位
            t = (0:N-1)/fs;
            fd_LOS = fd; 
            los_comp = A_rice .* exp(1j * phi) .* exp(1j * 2 * pi *costheta* fd_LOS * t);%固定阴影衰落*随机初相*多普勒频移相位旋转 
            h_raw = los_comp + rayleigh_comp; 
            
        elseif manual_state == 0
            %坏信道 瑞利与对数正态的乘积 (Suzuki分布)：直射径丢失，多径被阴影遮挡
            shadowing_dB = mu_dB + sigma_dB * randn(1, 1);
            z = 10.^(shadowing_dB / 20);
            %输出信道系数
            h_raw = z .* rayleigh_comp; 
        end
        
        %归一化
        H_matrix = h_raw / sqrt(mean(abs(h_raw).^2));
end