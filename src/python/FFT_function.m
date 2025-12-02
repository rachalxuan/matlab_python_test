function FFT_function(fs, N, freq1, freq2, amp1, amp2)

% fs=100;N=128;   %采样频率和数据点数
n=0:N-1;t=n/fs;   %时间序列
x=amp1*sin(2*pi*freq1*t)+amp2*sin(2*pi*freq2*t); %信号
y=fft(x,N);    %对信号进行快速Fourier变换
mag=abs(y);     %求得Fourier变换后的振幅
f=n*fs/N;    %频率序列

% figure(1)
% 创建第一个子图并保存
    fig1 = figure('Visible', 'off');
    plot(f, mag);
    xlabel('频率/Hz');
    ylabel('振幅'); 
    title(['N=' num2str(N) ', 全频谱']); 
    grid on;
%     fig1_path = fullfile(save_dir, 'fig1_N128_full.png');
    saveas(fig1, "E:\Python_project\Matlab_Py\fig1.png");
    close(fig1);
 
 % 创建第二个子图并保存
    fig2 = figure('Visible', 'off');
    plot(f(1:N/2), mag(1:N/2));
    xlabel('频率/Hz');
    ylabel('振幅'); 
    title(['N=' num2str(N) ', Nyquist前']); 
    grid on;
%     fig2_path = fullfile(save_dir, 'fig2_N128_nyquist.png');
    saveas(fig2, "E:\Python_project\Matlab_Py\fig2.png");
    close(fig2);
% 返回图像路径
%     fig_paths = {fig1_path, fig2_path};
end
