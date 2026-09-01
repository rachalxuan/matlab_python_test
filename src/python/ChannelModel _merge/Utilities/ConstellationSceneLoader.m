function [traj, meta] = ConstellationSceneLoader(projectRoot, sceneCode)
% ConstellationSceneLoader  按数字编号加载星座场景数据。
%
% 作用：
%   根据 sceneCode 进入对应场景分支，确定默认信关站/终端、默认卫星，
%   读取该卫星的 LLA 轨迹，并整理过境时间信息。
%
% 输入：
%   projectRoot - 项目根目录。
%   sceneCode   - 星座场景数字编号：
%                 1 Iridium Next场景
%                 2 Inmarsat场景
%                 3 Globalstar场景
%                 4 Leogeo场景
%                 5 Meteosat场景
%                 6 Orbcomm场景
%
% 输出：
%   traj        - 轨迹结构体，供 TrajectoryEngine 使用。
%   meta        - 场景元信息，包括场景名、终端、卫星和过境时长。

    meta = struct();
    traj = [];

    %% 1. 根据数字编号选择场景、默认终端和默认卫星
    % 前端下拉框传入的是数字编号 sceneCode，而不是中文场景名。
    % 这里用 switch 把编号固定映射到：
    %   场景文件夹 cfg.folder
    %   默认信关站 cfg.gateway
    %   默认终端 cfg.terminalName
    %   默认过境卫星 cfg.satellite
    %
    % 后续如果要把某个场景从 DVB1 换成 DVB2，或者换另一颗默认卫星，
    % 只需要改 getSceneConfig 中对应 case，不需要改 GUI 或主流程。
    cfg = getSceneConfig(sceneCode);

    % 根据默认终端名称查表得到经纬高。
    % 终端速度不在这里设置，统一在 getParameters.m 中固定为 0。
    terminalPos = getTerminalPosition(cfg.terminalName);

    %% 2. 读取默认卫星的 LLA 轨迹文件
    % LLA 文件位于：
    %   external_data\星座场景\<场景文件夹>\LLA\<卫星名>.txt
    %
    % 文件列顺序为：高度、纬度、经度。
    % readSceneLLAFile 会整理成 lon/lat/alt 三个数组，后续由
    % TrajectoryEngine 转成 ECEF 坐标和速度。
    sceneRoot = fullfile(projectRoot, 'external_data', '星座场景', cfg.folder);
    llaFile = fullfile(sceneRoot, 'LLA', [cfg.satellite, '.txt']);
    if ~isfile(llaFile)
        error('未找到场景 LLA 文件: %s', llaFile);
    end
    [lonData, latData, altData] = readSceneLLAFile(llaFile);

    %% 3. 整理过境时间窗口
    % LEO 场景：
    %   通常有 Single_GW_Connection\<信关站>_10h_to_14h.txt 过境表。
    %   表中每一行记录某颗卫星对该信关站的可见窗口：
    %       SatID, StartTime, EndTime, Duration
    %   本项目选择默认卫星后，用该卫星第一条过境记录作为仿真时间。
    %
    % GEO/近 GEO 场景：
    %   Inmarsat、Meteosat 这类场景 cfg.useAccessTable=false，
    %   没有过境表时直接使用 LLA 文件整段轨迹作为仿真时长。
    %
    % 最终输出的 duration 会写入 sceneMeta.AccessDuration，
    % getParameters.m 会把它作为 parameter.Ttotal，
    % 因此用户选择星座场景后，仿真总时长自动确定。
    startTime = 0;
    endTime = numel(lonData) - 1;
    duration = endTime - startTime;
    accessFile = '';
    rawSampleCount = numel(lonData);

    if cfg.useAccessTable
        accessFile = fullfile(sceneRoot, 'Single_GW_Connection', [cfg.gateway, '_10h_to_14h.txt']);
        if ~isfile(accessFile)
            error('未找到信关站连接表: %s', accessFile);
        end

        accessTable = readAccessTable(accessFile);
        rowIdx = find(strcmp({accessTable.SatID}, cfg.satellite), 1, 'first');
        if isempty(rowIdx)
            error('连接表 %s 中未找到默认卫星 %s。', accessFile, cfg.satellite);
        end

        startTime = accessTable(rowIdx).StartTime;
        endTime = accessTable(rowIdx).EndTime;
        duration = accessTable(rowIdx).Duration;

        % 部分 LEO 轨迹文件只保存 10h-14h 窗口，而过境表中的
        % StartTime/EndTime 可能仍然是“全天秒数”。
        % 例如 10:00:00 对应全天秒 36000，但文件第一行是窗口内 0 秒。
        % 此时要减去 cfg.rawWindowStart，把全天秒转换为文件内索引。
        if endTime > rawSampleCount - 1 && startTime >= cfg.rawWindowStart
            startTime = startTime - cfg.rawWindowStart;
            endTime = endTime - cfg.rawWindowStart;
        end
    end

    %% 4. 组装轨迹结构体
    % 这里不直接生成最终 ECEF 轨迹，而是把原始 1Hz LLA 数据、
    % 过境开始时间和过境持续时间一起交给 TrajectoryEngine。
    %
    % 原因：
    %   - getParameters.m 会统一设置 dT=1 秒。
    %   - TrajectoryEngine 知道当前 t_vec，可按 t_vec 从 RawLon/RawLat/RawAlt
    %     中截取本次仿真需要的点。
    %   - 这样星座场景选择、过境时长、轨迹刷新率三者能保持一致。
    traj.SourceType = 'LLH_Day1Hz_AccessWindow';
    traj.SatID = cfg.satellite;
    traj.AccessStartTime = startTime;
    traj.AccessEndTime = endTime;
    traj.AccessDuration = duration;
    traj.RawDt = 1;
    traj.RawLon = lonData(:);
    traj.RawLat = latData(:);
    traj.RawAlt = altData(:);

    %% 5. 组装场景元信息
    % meta 主要供 getParameters.m 使用：
    %   - SceneName/SceneFolder 用于记录当前场景；
    %   - Gateway/Satellite/TerminalName 记录默认链路选择；
    %   - AccessDuration 用于设置仿真总时长；
    %   - TerminalLongitude/Latitude/Altitude 用于设置静止终端位置。
    meta.SceneCode = sceneCode;
    meta.SceneName = cfg.sceneName;
    meta.SceneFolder = cfg.folder;
    meta.Gateway = cfg.gateway;
    meta.Satellite = cfg.satellite;
    meta.AccessFile = accessFile;
    meta.AccessStartTime = startTime;
    meta.AccessEndTime = endTime;
    meta.AccessDuration = duration;
    meta.TerminalName = cfg.terminalName;
    meta.TerminalLongitude = terminalPos.longitude;
    meta.TerminalLatitude = terminalPos.latitude;
    meta.TerminalAltitude = terminalPos.altitude;
    meta.TerminalVelocity = 0;
end

function cfg = getSceneConfig(sceneCode)
% getSceneConfig  数字编号到场景默认配置的映射。
% 修改某个场景默认终端或卫星时，只改这里对应 case 即可。
    switch sceneCode
        case 1
            cfg = struct('sceneName', 'Iridium Next场景', 'folder', 'IridiumNext', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'S0301', ...
                'useAccessTable', true, 'rawWindowStart', 36000);
        case 2
            cfg = struct('sceneName', 'Inmarsat场景', 'folder', 'Inmarsat', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'F11', ...
                'useAccessTable', false, 'rawWindowStart', 0);
        case 3
            cfg = struct('sceneName', 'Globalstar场景', 'folder', 'Globalstar', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'S45', ...
                'useAccessTable', true, 'rawWindowStart', 36000);
        case 4
            cfg = struct('sceneName', 'Leogeo场景', 'folder', 'leogeo', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'S022', ...
                'useAccessTable', true, 'rawWindowStart', 36000);
        case 5
            cfg = struct('sceneName', 'Meteosat场景', 'folder', 'Meteosat', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'M1-1', ...
                'useAccessTable', false, 'rawWindowStart', 0);
        case 6
            cfg = struct('sceneName', 'Orbcomm场景', 'folder', 'ORBCOMM', ...
                'gateway', 'DVB1', 'terminalName', 'DVB1', 'satellite', 'S028', ...
                'useAccessTable', true, 'rawWindowStart', 36000);
        otherwise
            error('未知星座场景编号: %g。', sceneCode);
    end
end

function pos = getTerminalPosition(terminalName)
% getTerminalPosition  默认终端名称到经纬高的映射。
% 后续需要换终端时，可直接改场景 case 中的 terminalName。
    switch terminalName
        case 'F1'
            pos = struct('latitude', 34.2583, 'longitude', 108.929, 'altitude', 0);
        case 'DVB1'
            pos = struct('latitude', 23.2092, 'longitude', 120.187, 'altitude', 0);
        case 'DVB2'
            pos = struct('latitude', 38.8951, 'longitude', 77.0364, 'altitude', 0);
        otherwise
            error('未知终端: %s', terminalName);
    end
end

function accessTable = readAccessTable(filename)
% readAccessTable  读取信关站与卫星过境连接表。
% 输出字段包括 SatID、StartTime、EndTime、Duration。
    txt = fileread(filename);
    pattern = '\S+\s+([A-Za-z0-9_\-]+)\s+([-+]?\d*\.?\d+)\s+([-+]?\d*\.?\d+)\s+([-+]?\d*\.?\d+)';
    tokens = regexp(txt, pattern, 'tokens');
    if isempty(tokens)
        error('未能从连接表中解析出过境记录。');
    end

    accessTable = struct('SatID', {}, 'StartTime', {}, 'EndTime', {}, 'Duration', {});
    for i = 1:numel(tokens)
        accessTable(i).SatID = tokens{i}{1};
        accessTable(i).StartTime = str2double(tokens{i}{2});
        accessTable(i).EndTime = str2double(tokens{i}{3});
        accessTable(i).Duration = str2double(tokens{i}{4});
    end
end

function [lonData, latData, altData] = readSceneLLAFile(filename)
% readSceneLLAFile  读取星座场景 LLA 文本文件。
% 文件列顺序为：高度、纬度、经度。
    data = readmatrix(filename, 'FileType', 'text');
    if isempty(data) || size(data, 2) < 3
        error('LLA 文件至少需要三列: 高度、纬度、经度。');
    end

    data = data(:, 1:3);
    data = data(all(isfinite(data), 2), :);
    if size(data, 1) < 2
        error('LLA 文件有效数据点太少，至少需要 2 行。');
    end

    altData = data(:, 1);
    latData = data(:, 2);
    lonData = data(:, 3);
end
