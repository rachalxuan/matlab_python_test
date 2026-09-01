% a = Corazza(1000,1,2e9,30,-0.5,2,10);
% 
% % 1. PDF部分
% subplot(1, 2, 1);
% histogram(abs(a), 50, 'Normalization', 'pdf', 'FaceColor', [0.7 0.8 1]);
% title('PDF');
% ylabel('概率密度 (PDF)');
% grid on;
% 
% % 2. PSD部分
% subplot(1, 2, 2);
% [x, f] = periodogram(a, rectwin(length(a)), length(a), 1000, 'centered');
% plot(f, 10*log10(x), 'LineWidth', 1);
% title('PSD');
% ylabel('功率谱密度 (PSD) [dB/Hz]');
% xlabel('频率 (Hz)');
% grid on;

function H_matrix = Corazza(fs,T,fc,v,mu_dB,sigma_dB,K_linear,costheta)
% =========================================================================
% CLoo信道系数生成
% 输入：
% mu_dB       % 对数正态均值 
% sigma_dB    % 对数正态标准差 
% K_linear    % 莱斯 K 因子 (线性值)，控制直射径与多径的功率比
  
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
        
        % 将 I/Q 两路归一化，使其方差各为 0.5，确保总散射功率为 1
        filtered_I = (filtered_I / sqrt(mean(filtered_I.^2))) * sqrt(0.5);
        filtered_Q = (filtered_Q / sqrt(mean(filtered_Q.^2))) * sqrt(0.5);
        rayleigh_comp = filtered_I + 1j * filtered_Q;
        
        %构建莱斯衰落分量
        A = sqrt(K_linear);
        %为直射分量设置相位
        phi = 2 * pi * rand(1, 1); % 均匀分布的随机相位 给直射分量设置随机的起点相位
        t = (0:N-1)/fs;
        fd_LOS = fd; 
        los_comp = A .* exp(1j * phi) .* exp(1j * 2 * pi * costheta *fd_LOS * t);%固定阴影衰落*随机初相*多普勒频移相位旋转 
        
        w = los_comp + rayleigh_comp; % 这就是图片公式中的 w（服从莱斯分布）
        
        %生成对数正态阴影衰落分量
        shadowing_dB = mu_dB + sigma_dB * randn(1, 1);%固定阴影衰落值
        z = 10.^(shadowing_dB / 20); % 将 dB 转换为幅值
        
        %叠加
        h_raw = z .* w; 
        
        %归一化
        H_matrix = h_raw / sqrt(mean(abs(h_raw).^2));
end