% FFT_function.m
function json_str = FFT_function(fs, N, freq1, freq2, amp1, amp2)
% 修改MATLAB函数，直接返回JSON字符串

% 确保所有输入参数都是double类型
fs = double(fs);
N = double(N);
freq1 = double(freq1);
freq2 = double(freq2);
amp1 = double(amp1);
amp2 = double(amp2);

try
    % 原有的计算代码
    n = 0:N-1;
    t = n/fs;
    x = amp1*sin(2*pi*freq1*t)+amp2*sin(2*pi*freq2*t);
    y = fft(x, N);
    mag = abs(y)*2/N;
    f = n*fs/N;
    
    % 生成图像
    fig1 = figure('Visible', 'off');
    plot(f, mag);
    xlabel('频率/Hz'); ylabel('振幅'); 
    title(['N=' num2str(N) ', 全频谱']); grid on;
    saveas(fig1, "E:\web_code\react\fft_project\react-fft\temp\fft_images\fig1.png");
    close(fig1);
    
    fig2 = figure('Visible', 'off');
    plot(f(1:N/2), mag(1:N/2));
    xlabel('频率/Hz'); ylabel('振幅'); 
    title(['N=' num2str(N) ', Nyquist前']); grid on;
    saveas(fig2, "E:\web_code\react\fft_project\react-fft\temp\fft_images\fig2.png");
    close(fig2);
    
    % 准备JSON数据
    result = struct();
    result.success = true;
    result.error = '';
    result.fft_data = struct(...
        'f1', f(1:N/2)', ...
        'mag1', mag(1:N/2)', ...
        'f2', f', ...
        'mag2', mag');
    result.parameters = struct(...
        'fs', fs, 'n', N, 'freq1', freq1, 'freq2', freq2, ...
        'amp1', amp1, 'amp2', amp2);
    
    % 转换为JSON字符串
    json_str = jsonencode(result);
    
catch ME
    % 错误处理
    error_result = struct();
    error_result.success = false;
    error_result.error = ME.message;
    error_result.fft_data = struct();
    json_str = jsonencode(error_result);
end

end