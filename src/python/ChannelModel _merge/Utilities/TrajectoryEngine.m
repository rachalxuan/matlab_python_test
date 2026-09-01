function [t_vec, termPos, satPos, satVel, Angles, fd_record,traj] = TrajectoryEngine(param)
% TrajectoryEngine  生成终端与卫星的时间对齐轨迹。
%
% 作用：
%   根据 parameter 中的终端位置、卫星轨迹和仿真步长，输出每个快照
%   对应的终端位置、卫星位置/速度、空间角度和多普勒记录。
%
% 输入：
%   param     - getParameters 生成的完整仿真参数结构体。
%
% 输出：
%   t_vec     - 仿真时间序列。
%   termPos   - 终端 ECEF 位置，维度为 3 x N。
%   satPos    - 卫星 ECEF 位置，维度为 3 x N。
%   satVel    - 卫星 ECEF 速度，维度为 3 x N。
%   Angles    - AOA/AOD/EOA/EOD 等角度结构体。
%   fd_record - 每个快照对应的多普勒频移记录。
    % =====================================================================
    % 卫星轨迹与运动学核心引擎 (Trajectory Engine)
    % ---------------------------------------------------------------------
    % 功能：统一输出按时间步长对齐的星地相对位置、速度、多普勒与空间夹角
    % 模式支持：内置六根数开普勒推演 (Internal) / 第三方数据导入 (External)
    % =====================================================================
    
    % 物理常数
    derad = pi / 180; 
    mu = 3.9860e14; % 地球引力常数
    c = 2.9979e8;   % 光速 (m/s)
    
     % 1. 生成宏观时间轴 (控制仿真分辨率)
    if ~isfield(param, 'dT'), param.dT = 1; end % 默认步长 1s
    % 旧逻辑从 dT 开始：Ttotal=100, dT=1 时得到 1,2,...,100。
    % t_vec = param.dT : param.dT : param.Ttotal;
    %
    % 新逻辑统一从 0 秒开始：Ttotal=100, dT=1 时得到 0,1,...,99，
    % 共 100 个快照。这样外部全天 1Hz 经纬高文件的“第 1 行 = 0s”
    % 可以和仿真快照一一对应，避免整体错开 1 秒。
    %
    % 这里的 Ttotal 已经不是 GUI 手动输入值，而是 getParameters.m
    % 根据所选星座场景默认卫星的过境持续时间自动写入。
    % dT 固定为 1 秒，因此快照数基本等于该次过境持续秒数。
    t_vec = 0 : param.dT : param.Ttotal - param.dT;
    N_snapshots = length(t_vec); 
    
    % 2. 计算终端 (UE) 的运动轨迹。
    % param.terminalVelocity 是 ECEF 三维速度向量。
    % 本项目的信关站/终端默认静止，getParameters.m 中固定为 [0;0;0]，
    % 所以 termPos(:,i) 每个快照都等于初始 ECEF 坐标。
    % 保留这一行公式，是为了后续若需要移动终端，只需给 terminalVelocity 赋值。
    termPosInit = [param.terminalX; param.terminalY; param.terminalZ];
    termPos = zeros(3, N_snapshots);
    for i = 1:N_snapshots
        termPos(:, i) = termPosInit + param.terminalVelocity * t_vec(i);
    end
    
    satPos = zeros(3, N_snapshots); 
    satVel = zeros(3, N_snapshots); 
    
    % =================================================================
    % 3. 核心路由：根据模式生成卫星轨迹已经全部打开
    % =================================================================
     if isfield(param, 'trajectoryMode') && strcmp(param.trajectoryMode, 'External')
         % -------------------------------------------------------------
         % 模式 A：导入外界数据 (如 STK, WI 等)
         % -------------------------------------------------------------
         % --- 在 TrajectoryEngine 内部的 External 处理区 ---
         traj = param.customTrajectory; 
        % 对 .txt 经纬高 + 过境表导入的数据，导入阶段只保存全天 1Hz
        % 原始经纬高和过境窗口。每次真正运行时，都用当前 t_vec 重新
        % 截取轨迹点，确保 Ttotal/dT 改变后轨迹点数同步改变。
        %
        % 当前 Ttotal 来自场景默认过境持续时间，因此这里实际含义是：
        % 从默认卫星对默认终端的过境开始时刻起，按 1 秒步长取出整段过境轨迹。
        % 如果后续改默认卫星或默认终端，只要 ConstellationSceneLoader 给出
        % 新的过境窗口，这里会自动截取对应轨迹。
        if isfield(traj, 'SourceType') && strcmp(traj.SourceType, 'LLH_Day1Hz_AccessWindow') ...
                && isfield(traj, 'RawLon') && isfield(traj, 'RawLat') && isfield(traj, 'RawAlt')
            traj = buildLLHDay1HzTrajForEngine(traj, t_vec);
        end
     
         % 兼容旧轨迹结构：如果文件里存的是 satPos 矩阵，自动拆解给 X/Y/Z。
         if isfield(traj, 'satPos') && ~isfield(traj, 'X')
             traj.X = traj.satPos(1, :);
             traj.Y = traj.satPos(2, :);
             traj.Z = traj.satPos(3, :);
         end
     
         % 同样兼容旧速度结构：如果文件里存的是 satVel 矩阵，自动拆解给 Vx/Vy/Vz。
         if isfield(traj, 'satVel') && ~isfield(traj, 'Vx')
              traj.Vx = traj.satVel(1, :);
              traj.Vy = traj.satVel(2, :);
              traj.Vz = traj.satVel(3, :);
         end
         % 将读取到的外部轨迹正式赋值给引擎输出变量。
         % 对 LLH_Day1Hz_AccessWindow 类型，上面的函数已经按当前 t_vec
         % 重新截取并检查过境窗口；这里使用线性插值兜底，避免 spline 过冲。
         %
         % satPos 是卫星在 ECEF 坐标系下的位置，satVel 是同一坐标系下的速度。
         % 后面的星地距离、仰角和多普勒都在这个统一坐标系里计算。
         satPos(1, :) = interp1(traj.Time, traj.X, t_vec, 'linear', 'extrap');
         satPos(2, :) = interp1(traj.Time, traj.Y, t_vec, 'linear', 'extrap');
         satPos(3, :) = interp1(traj.Time, traj.Z, t_vec, 'linear', 'extrap');
    
         satVel(1, :) = interp1(traj.Time, traj.Vx, t_vec, 'linear', 'extrap');
         satVel(2, :) = interp1(traj.Time, traj.Vy, t_vec, 'linear', 'extrap');
         satVel(3, :) = interp1(traj.Time, traj.Vz, t_vec, 'linear', 'extrap');
     else
        % -------------------------------------------------------------
        % 模式 B：独立生成 (基于内置开普勒六根数模型)
        % -------------------------------------------------------------
        satData = param.satelliteData; % [高度, 偏心率, 倾角, 升交点赤经, 近地点幅角, 真近点角]
        
        % 轨道角速度
        orbitalAngularVel = ((sqrt(mu) / ((abs(satData(1) * (1 - satData(2)^2)))^(3 / 2)))) * ...
                            ((1 + satData(2) * cos(satData(6) * derad))^2) / derad;
        
        % 计算每个仿真时刻的真近点角
        satelliteThetaRange = satData(6) + orbitalAngularVel * t_vec; 
        
        for i = 1:N_snapshots
            satData(6) = satelliteThetaRange(i); 
            [pos, vel] = satelliteCoordinate(satData, mu); % 调用内部坐标转换函数
            satPos(:, i) = pos; 
            satVel(:, i) = vel;
        end
     end
    
    % =================================================================
    % 4. 计算星地空间拓扑与信道核心参数 (角度、多普勒)
    % =================================================================
    montionAOD = zeros(1, N_snapshots); montionEOA = zeros(1, N_snapshots); montionZOD = zeros(1, N_snapshots);
    montionPos = struct();
    
    for i = 1:N_snapshots
        montionPos.terminalX = termPos(1, i); montionPos.terminalY = termPos(2, i); montionPos.terminalZ = termPos(3, i);
        montionPos.satelliteX = satPos(1, i); montionPos.satelliteY = satPos(2, i); montionPos.satelliteZ = satPos(3, i);
        if i == 488
            a= 1;
        end
        % 计算空间仰角、方位角
        [~, AOD, EOA, ~, ~, ZOD] = computeAzimuthElevation(montionPos); 
        montionAOD(i) = AOD; montionEOA(i) = EOA; montionZOD(i) = ZOD;
    end
    Angles = struct('AOD', montionAOD, 'EOA', montionEOA, 'ZOD', montionZOD);
    
    % 解算动态多普勒频移 (基于相对径向速度投影)
    %
    % 多普勒不是用卫星速度大小直接算，而是用“星地相对速度在视距方向上的投影”。
    % 具体逻辑如下：
    %   deltaPos = satPos - termPos
    %       表示从终端指向卫星的视距 LOS 向量。
    %
    %   dist3D = norm(deltaPos)
    %       表示当前星地三维距离，也用于把 LOS 向量归一化。
    %
    %   deltaVel = satVel - terminalVelocity
    %       表示卫星相对终端的速度。
    %       本项目终端速度固定为 [0;0;0]，所以这里实际就是卫星速度；
    %       如果后续终端移动，这个公式仍然成立。
    %
    %   v_rel = dot(deltaVel, deltaPos) / dist3D
    %       表示相对速度沿 LOS 方向的径向分量。
    %       只有径向分量会引起多普勒，切向速度不会直接改变传播距离。
    %
    %   fd = -(v_rel / c) * fc
    %       c 为光速，fc 为载频。负号是本代码采用的符号约定：
    %       当投影速度导致星地距离增大/减小时，多普勒正负号随投影方向变化。
    deltaPos = satPos - termPos; 
    dist3D = sqrt(sum(deltaPos.^2, 1)); 
    termVelMatrix = repmat(param.terminalVelocity, 1, N_snapshots); 
    deltaVel = satVel - termVelMatrix; 
    
    v_rel = sum(deltaVel .* deltaPos, 1) ./ dist3D; % 速度在视距(LOS)方向的投影
    % fd_record = -(v_rel / c) * (param.fc * 1e9);    % fd = -(v/c)*fc
    fd_record = v_rel;


end

% =========================================================================
% 以下为引擎内部私有函数 (与外部完全隔离，保持环境干净)
% =========================================================================
function [Coordinate,V] = satelliteCoordinate(data,miu)
   derad = pi/180;
   a = data(1); e = data(2); i= data(3)*derad; w = data(4)*derad; W = data(5)*derad; fai = data(6)*derad; 
   p = abs(a * (1 - e^2)); u = w + fai;
   Coordinate = p / (1 + e * cos(fai)) * [cos(W) * cos(u)-sin(W) * sin(u) * cos(i),  sin(W) * cos(u) + cos(W) * sin(u) * cos(i), sin(i) * sin(u)]';
   V = (miu/p)^(0.5)*[-cos(W) * (sin(u) + e * sin(w)) - sin(W) * (cos(u) +e * cos(w)) * cos(i), -sin(W) * (sin(u) + e * sin(w)) + cos(W) * (cos(u) + e * cos(w)) * cos(i), sin(i) * (cos(u)+e * cos(w))].';   
end

function [AOA,AOD,EOA,EOD,ZOA,ZOD] = computeAzimuthElevation(position)
    % derad = pi/180; 
    % tX = position.terminalX; tY = position.terminalY; tZ = position.terminalZ; R_term = sqrt(tX^2 + tY^2 + tZ^2);
    % deltaX = position.satelliteX - tX; deltaY = position.satelliteY - tY; deltaZ = position.satelliteZ - tZ; 
    % dist3D = sqrt(deltaX^2 + deltaY^2 + deltaZ^2);
    % dot_product = deltaX*tX + deltaY*tY + deltaZ*tZ; 
    % sin_el = dot_product / (dist3D * R_term); 
    % EOA = asin(sin_el) / derad; 
    % AOA = (atan2(deltaY, deltaX)) ./ derad; 
    % AOD = ((atan2(-deltaY, -deltaX))) ./ derad; 
    % EOD = -EOA; ZOA = 90 - EOA; ZOD = 90 - EOD;  

terminalX = position.terminalX;
terminalY = position.terminalY;
terminalZ = position.terminalZ;
satelliteX = position.satelliteX;
satelliteY = position.satelliteY;
satelliteZ = position.satelliteZ;
derad = pi/180;                                                          % Convert degrees to radians
deltaX = satelliteX - terminalX;
deltaY = satelliteY - terminalY;
deltaZ = satelliteZ - terminalZ;
AOA  = (atan2(deltaY, deltaX)) ./ derad;                                 % Azimuth angle of arrival (-180,180)度
AOD = ((atan2(-deltaY, -deltaX))) ./ derad;                              % Azimuth angle of departure
EOA = (asin(deltaZ / sqrt(deltaX^2 + deltaY^2 + deltaZ^2))) ./ derad;    % Elevation angle of arrival (-90,90)度
if EOA < 0
    EOA = 90 + EOA;
end
EOD = -(asin(deltaZ / sqrt(deltaX^2 + deltaY^2 + deltaZ^2))) ./ derad;   % Elevation angle of departure
ZOA = 90 - EOA;                                                          % Zenith angle of arrival
ZOD = 90 - EOD;                                                          % Zenith angle of departure (0,180)度


end

function Traj = buildLLHDay1HzTrajForEngine(rawTraj, t_vec)
    % 根据当前仿真时间轴，从全天 1Hz 经纬高文件中截取本次需要的轨迹。
    % 这样即使在 getParameters 中修改 Ttotal/dT，也会在运行时得到新的点数。
    startTime = rawTraj.AccessStartTime;
    endTime = rawTraj.AccessEndTime;

    if isfield(rawTraj, 'RawDt') && ~isempty(rawTraj.RawDt)
        rawDt = rawTraj.RawDt;
    else
        rawDt = 1;
    end

    lonData = rawTraj.RawLon(:);
    latData = rawTraj.RawLat(:);
    altData = rawTraj.RawAlt(:);
    N_raw = min([length(lonData), length(latData), length(altData)]);

    if N_raw < 2
        error('外部经纬高原始数据点太少，至少需要 2 个采样点。');
    end

    lonData = lonData(1:N_raw);
    latData = latData(1:N_raw);
    altData = altData(1:N_raw);

    simTime = t_vec(:);
    N_sim = length(simTime);
    lonSel = zeros(N_sim, 1);
    latSel = zeros(N_sim, 1);
    altSel = zeros(N_sim, 1);
    nearestIdxRecord = zeros(N_sim, 1);
    absoluteTimeRecord = zeros(N_sim, 1);

    for k = 1:N_sim
        absoluteTime = startTime + simTime(k);

        % 当前导入轨迹只代表选中卫星的一次过境。
        % 如果仿真总时长超过过境结束时间，继续外推会产生不真实的位置、
        % 仰角和多普勒，因此无界面测试中直接在命令行报错并停止。
        if absoluteTime > endTime
            error(['仿真时间超过该卫星过境结束时间。', newline, ...
                   '卫星 %s 对终端 %s 的过境窗口为 %.3f s 到 %.3f s，', newline, ...
                   '当前仿真需要取到 %.3f s。请缩短 Ttotal、增大 dT，或选择下一颗卫星。'], ...
                   getStructField(rawTraj, 'SatID', '未知卫星'), ...
                   getStructField(rawTraj, 'TerminalID', '未知终端'), ...
                   startTime, endTime, absoluteTime);
        end

        nearestIdx = round(absoluteTime / rawDt) + 1;
        nearestIdx = max(1, min(N_raw, nearestIdx));

        lonSel(k) = lonData(nearestIdx);
        latSel(k) = latData(nearestIdx);
        altSel(k) = altData(nearestIdx);

        nearestIdxRecord(k) = nearestIdx;
        absoluteTimeRecord(k) = absoluteTime;
    end

    Traj = llh2TrajStructForEngine(simTime, latSel, lonSel, altSel);
    Traj.SourceType = rawTraj.SourceType;
    Traj.SatID = getStructField(rawTraj, 'SatID', '');
    Traj.TerminalID = getStructField(rawTraj, 'TerminalID', '');
    Traj.AccessStartTime = startTime;
    Traj.AccessEndTime = endTime;
    Traj.AccessDuration = rawTraj.AccessDuration;
    Traj.RawSampleCount = N_raw;
    Traj.SimSampleCount = N_sim;
    Traj.NearestIndex = nearestIdxRecord;
    Traj.AbsoluteTime = absoluteTimeRecord;
    Traj.SelectedLon = lonSel;
    Traj.SelectedLat = latSel;
    Traj.SelectedAlt = altSel;
end

function Traj = llh2TrajStructForEngine(time, latDeg, lonDeg, altVal)
    % 将纬度、经度、高度转换为 ECEF 坐标，并根据时间轴计算速度。
    % 输入高度通常为 km，例如 IridiumNext 的 1150；若已经是 m，则不再放大。
    Re = 6371e3;

    time = time(:);
    latDeg = latDeg(:);
    lonDeg = lonDeg(:);
    altVal = altVal(:);

    N = min([length(time), length(latDeg), length(lonDeg), length(altVal)]);
    time = time(1:N);
    latDeg = latDeg(1:N);
    lonDeg = lonDeg(1:N);
    altVal = altVal(1:N);

    if max(abs(altVal)) < 1e5
        alt_m = altVal * 1000;
    else
        alt_m = altVal;
    end
    
    % lat = deg2rad(latDeg);
    % lon = unwrap(deg2rad(lonDeg));
    % r = Re + alt_m;
    % 
    % X = r .* cos(lat) .* cos(lon);
    % Y = r .* cos(lat) .* sin(lon);
    % Z = r .* sin(lat);

f=1/298.257223563;
hg =  alt_m;
a = 6378.137e3;
phi = latDeg;
lamd = lonDeg;
Ns = (a./sqrt(1-(2*f-f^2)*(sind(phi).^2)));

X = (Ns+hg).*cosd(phi).*cosd(lamd);
Y = (Ns+hg).*cosd(phi).*sind(lamd);
Z = (Ns*(1-f)^2+hg).*sind(phi);


    if N < 2
        Vx = zeros(N, 1);
        Vy = zeros(N, 1);
        Vz = zeros(N, 1);
    else
        Vx = gradient(X, time);
        Vy = gradient(Y, time);
        Vz = gradient(Z, time);
    end
    Traj.Time = time;
    Traj.X = X;
    Traj.Y = Y;
    Traj.Z = Z;
    Traj.Vx = Vx;
    Traj.Vy = Vy;
    Traj.Vz = Vz;

end

function value = getStructField(s, fieldName, defaultValue)
    % 小工具：有些旧轨迹结构体可能没有 TerminalID 等字段，用默认值兜底。
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = s.(fieldName);
    else
        value = defaultValue;
    end
end
