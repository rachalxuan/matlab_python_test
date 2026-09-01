function send(i, N_snapshots, socketConfig)
% send  通过 UDP 发送百分比进度或输出 .mat 文件路径。
%
% 本项目对外只发送两类 socket 包：
%   1. 进度包：double 类型的数字 10、20、...、100。
%      接收端收到后可直接作为任务执行进度百分比显示。
%   2. 路径包：string 类型的输出参数 .mat 完整路径。
%      接收端收到后可用该路径继续调用后续 m2/算法程序。
%
% 注意：
%   - 本函数不会在 socket 内容前拼接“已发送进度”或“Output parameter MAT”等文字。
%   - 命令行打印内容也保持和 socket 内容一致：
%       进度打印为 10%、20%、...、100%；
%       路径打印为 D:\UI-lessTest\output\OutputParameter_xxx.mat。
%   - socketConfig.enable = false 时直接返回，不发送也不打印，方便本地调试。
%
% 调用方式：
%   send(progressPercent, socketConfig) 发送纯百分比数值，例如 10、20、...、100。
%   send(filePath, socketConfig)        发送纯输出文件路径字符串。
%   send(i, N_snapshots, socketConfig)  兼容旧写法，内部换算百分比后发送。

    % 兼容没有传 socket 配置的旧调用方式，使用默认 IP/端口。
    if nargin < 2
        socketConfig = defaultSocketConfig();
    elseif nargin == 2 && isstruct(N_snapshots)
        % 两参数写法：
        %   send(10, socketConfig)         -> 发送进度 double 10
        %   send(resultPath, socketConfig) -> 发送路径 string
        socketConfig = N_snapshots;
        if ischar(i) || isstring(i)
            sendPath(i, socketConfig);
        else
            sendProgress(i, socketConfig);
        end
        return;
    elseif nargin < 3 || isempty(socketConfig)
        socketConfig = defaultSocketConfig();
    end

    % 如果第一个参数是字符串，认为它就是输出 .mat 路径。
    if ischar(i) || isstring(i)
        sendPath(i, socketConfig);
        return;
    end

    % 三参数旧写法中，i 是当前循环步数，N_snapshots 是总步数。
    % 这里换算成百分比；实际本项目现在主要在 reportProgress 中
    % 控制只发送 10 次，所以通常不会走每一步都发包的旧逻辑。
    if nargin >= 2 && ~isstruct(N_snapshots) && ~isempty(N_snapshots) && N_snapshots > 0
        progressPercent = min(max(double(i) / double(N_snapshots) * 100, 0), 100);
    else
        progressPercent = double(i);
    end

    sendProgress(progressPercent, socketConfig);
end

function sendProgress(progressPercent, socketConfig)
    % enable=false 时完全跳过 UDP 发送和命令行打印，便于本地无联调测试。
    if isfield(socketConfig, 'enable') && ~socketConfig.enable
        return;
    end

    % 对百分比做保护，保证不会小于 0 或大于 100。
    progressPercent = min(max(double(progressPercent), 0), 100);

    % 进度包使用 double 类型发送。
    % 接收端应按 double 读取，值为 10、20、...、100。
    sender = udpport("datagram", "IPV4");
    write(sender, progressPercent, "double", socketConfig.targetIP, socketConfig.targetPort);
    clear sender;

    % 命令行只打印纯百分比，方便人工确认实际发送内容。
    fprintf('%.0f%%\n', progressPercent);
end

function sendPath(filePath, socketConfig)
    % enable=false 时完全跳过 UDP 发送和命令行打印，避免调试时误发路径。
    if isfield(socketConfig, 'enable') && ~socketConfig.enable
        return;
    end

    filePath = char(filePath);

    % 路径包使用 string 类型发送。
    % 内容就是输出 .mat 的完整路径，不额外拼接任何说明文字。
    sender = udpport("datagram", "IPV4");
    write(sender, filePath, "string", socketConfig.targetIP, socketConfig.targetPort);
    clear sender;

    % 命令行只打印纯路径，和 socket 包内容保持一致。
    fprintf('%s\n', filePath);
end

function socketConfig = defaultSocketConfig()
    % 默认联调地址。若前端/接收端修改了 IP 或端口，应在 main.m
    % 中通过 socketTargetIP/socketTargetPort 传入，不建议改这里。
    socketConfig = struct('targetIP', '127.0.0.1', 'targetPort', 6000, 'enable', true);
end
