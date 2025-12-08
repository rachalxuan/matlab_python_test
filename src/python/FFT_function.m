function json_str = FFT_function(fs, N, freq1, freq2, amp1, amp2)
    % 强制转换类型
    fs = double(fs); N = double(N);
    freq1 = double(freq1); freq2 = double(freq2);
    amp1 = double(amp1); amp2 = double(amp2);

    try
        % 1. FFT 计算核心逻辑
        n = 0:N-1;
        t = n/fs;
        x = amp1*sin(2*pi*freq1*t) + amp2*sin(2*pi*freq2*t);
        y = fft(x, N);
        mag = abs(y)*2/N;
        f = n*fs/N;
        
        % 2. === 关键修复：构建绝对路径 ===
        % 获取当前 m 文件的路径
        currentFile = mfilename('fullpath');
        [pathstr, ~, ~] = fileparts(currentFile);
        
        % 向上两级找到项目根目录 (假设结构是 src/python/FFT_function.m)
        % pathstr 是 .../src/python
        % fileparts(pathstr) 是 .../src
        % fileparts(fileparts(pathstr)) 是 项目根目录 (例如 E:\web_code\react\fft_project\react-fft)
        projectRoot = fileparts(fileparts(pathstr)); 
        
        % 构建图片保存目录: 项目根目录/temp/fft_images
        saveDir = fullfile(projectRoot, 'temp', 'fft_images');
        
        % 如果目录不存在则创建
        if ~exist(saveDir, 'dir')
           mkdir(saveDir);
        end
        
        % 3. 生成并保存图片 (关闭可见性以提速)
        fig1 = figure('Visible', 'off');
        plot(f, mag);
        xlabel('Hz'); ylabel('Amp'); title(['N=' num2str(N) ' Full Spectrum']); grid on;
        % 保存全路径
        saveas(fig1, fullfile(saveDir, 'fig1.png'));
        close(fig1);
        
        fig2 = figure('Visible', 'off');
        plot(f(1:N/2), mag(1:N/2));
        xlabel('Hz'); ylabel('Amp'); title(['N=' num2str(N) ' Nyquist']); grid on;
        saveas(fig2, fullfile(saveDir, 'fig2.png'));
        close(fig2);
        
        % 4. 准备返回数据 (转置为行向量防止前端格式错误)
        f_half = f(1:N/2); mag_half = mag(1:N/2);
        if iscolumn(f_half), f_half = f_half'; end
        if iscolumn(mag_half), mag_half = mag_half'; end
        if iscolumn(f), f = f'; end
        if iscolumn(mag), mag = mag'; end

        result = struct();
        result.success = true;
        % 将路径返回给 Python，方便调试
        result.save_dir = char(saveDir); 
        result.fft_data = struct('f1', f_half, 'mag1', mag_half, 'f2', f, 'mag2', mag);
        result.parameters = struct('fs', fs, 'n', N, 'freq1', freq1, 'freq2', freq2, 'amp1', amp1, 'amp2', amp2);
        
        json_str = jsonencode(result);
        
    catch ME
        error_result = struct();
        error_result.success = false;
        error_result.error = ME.message;
        % 捕获错误栈信息
        error_result.stack = ME.stack(1).name;
        json_str = jsonencode(error_result);
    end
end