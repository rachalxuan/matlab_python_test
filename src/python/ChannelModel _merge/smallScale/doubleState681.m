function [all_cumulative_distances,H_Martix_tMode,numsend] = doubleState681(parameter,position,numsend)
%numEvents add 2026-7-9
[AOA,AOD,EOA,~,ZOA,ZOD] = computeAzimuthElevation(position);     % Calculate the azimuth ,elevation and Zenith angles between the terminal and the satellite    
position.losAOA = AOA;
position.losAOD = AOD;
position.losZOA = ZOA;
position.losZOD = ZOD;
position.losEOA = EOA;



% H_Martix_tMode = NaN;
% Ts = parameter.Ttotal;          % 采样时间，单位为秒
Ts = parameter.Tt;                 %2026-7-7
% Ts = parameter.T;
% fs = 1/Ts;
fs = parameter.Fs;
fc  = parameter.fc * 1e9;
c = 3e8;
derad = pi/180;
theta = position.losEOA;
losAOD = position.losAOD;
losZOD = position.losZOD;
vm = norm(position.terminalVelocity);
environment = parameter.environment;

[goodTable,badTable] = getLMSParamsP681(fc,theta,environment);
muG = goodTable.MeanVar(1);    % 好状态的平均值
sigmaG = goodTable.MeanVar(2);  % 好状态的标准差
muB = badTable.MeanVar(1);    % 差状态的平均值
sigmaB = badTable.MeanVar(2);  % 差状态的标准差
durminG =goodTable.MinDur;   % 好状态的最小事件持续时间
durminB =badTable.MinDur;   % 差状态的最小事件持续时间
mu_MAG=goodTable.MeanMA(1);
sigma_MAG=goodTable.MeanMA(2);
mu_MAB=badTable.MeanMA(1);
sigma_MAB=badTable.MeanMA(2);

% Loo参数
g1G = goodTable.G1G2(1); % ΣA的系数
g2G = goodTable.G1G2(2); % ΣA的系数
h1G = goodTable.H1H2(1); % MP的系数
h2G = goodTable.H1H2(2); % MP的系数
g1B = badTable.G1G2(1); % ΣA的系数
g2B = badTable.G1G2(2); % ΣA的系数
h1B = badTable.H1H2(1); % MP的系数
h2B = badTable.H1H2(2); % MP的系数

% 转换长度系数
% f1 = goodTable.F1F2(1);
% f2 = goodTable.F1F2(2);

pB_min = badTable.ProbRange(1);
pB_max = badTable.ProbRange(2);

Lcorr = goodTable.Lcorr;

% % 初始化状态序列和持续时间数组
% state_sequence = zeros(1, N);
% duration_sequence = zeros(1, N);
% loo_params = zeros(3, N);  % 初始化Loo参数数组

all_fastFading= []; %用于存储快衰系数
all_cumulative_distances = []; % 用于存储对应的累积距离
all_slowFading = [];%用于存储直射径系数
% current_global_distance = 0;
current_global_distance = parameter.current_global_distance;   %2026-7-7
initialState = "G";
% timeTotal = parameter.Ttotal;  % 总行驶距离 (m)
timeTotal = parameter.Tt;
stateList = {};    % 存储事件序列：交替的 "Good"/"Bad"
durationList= [];  % 存储每个事件的持续距离 (m)
currentState = initialState;
timeCovered = 0;
while timeCovered < timeTotal
    if currentState == "G"
        mu = muG; 
        sig = sigmaG; 
        durmin = durminG;
    else
        mu = muB; 
        sig = sigmaB; 
        durmin = durminB;
    end
    % 随机抽取对数正态距离，直到 ≥ durmin
    eventDur = 0;
    while eventDur < durmin
        tmp = lognrnd(mu, sig);
        eventDur = round(tmp);
    end
    timeCovered = timeCovered + eventDur;
    stateList{end+1} = currentState;
    durationList(end+1) = eventDur;
    % 状态交替
    if currentState == "G"   % 若你用的是 string 类型
        currentState = "B";
    else
        currentState = "G";
    end

end
% If we overshot the required distance, truncate the last event duration
if timeCovered > timeTotal
    excess = timeCovered - timeTotal;
    durationList(end) = durationList(end) - excess;
    if durationList(end) <= 0
        durationList(end) = []; 
        stateList(end) = [];  % drop last event if its duration became zero or negative
    end
end
numEvents = length(durationList);

% if numEvents ==1 && numsend < 50
% 
%    send([num2str(numsend)], parameter.socket);
%    numsend = numsend+5;
% end
% 生成状态序列
for i = 1:numEvents
    % 生成MA值并检查范围
    if stateList{i} == "G"
        mu_MA=mu_MAG;
        sigma_MA=sigma_MAG;
        MA = normrnd(mu_MA, sigma_MA);
        while MA < (mu_MA - 1.645 * sigma_MA) || MA > (mu_MA + 1.645 * sigma_MA)
            MA = normrnd(mu_MA, sigma_MA);
        end
        % 计算Loo参数
        SigmaA = g1G * MA + g2G;
        MP = h1G * MA + h2G;
        % loo_params(:, i) = [MA, SigmaA, MP];
    else
        mu_MA=mu_MAB;
        sigma_MA=sigma_MAB;
        MA = normrnd(mu_MA, sigma_MA);
        while MA < (mu_MA + sqrt(2) * sigma_MA * erfinv(2 * pB_min - 1)) || ...
                MA > (mu_MA + sqrt(2) * sigma_MA * erfinv(2 * pB_max - 1))
            MA = normrnd(mu_MA, sigma_MA);
        end
        % 计算Loo参数
        SigmaA = g1B * MA + g2B;
        MP = h1B * MA + h2B;
        % loo_params(:, i) = [MA, SigmaA, MP];
    end

    duration = durationList(i);
    [x_t,t] = generate_complex_time_series(duration, fs);% 示例输入信号
    % 应用Jakes滤波器
    fm = vm * fc / c; % 最大多普勒频移
    [fastFading,cumulative_distances]= jakes_filter(x_t, t, fm , current_global_distance , vm);
    current_global_distance = cumulative_distances(end);
    Sigma = sqrt(0.5*10^(MP/10));
    fastFading = fastFading*Sigma;
    all_fastFading = [all_fastFading,fastFading];
    all_cumulative_distances = [all_cumulative_distances,cumulative_distances];
    %直射径低通滤波器系数
    rho_s = exp(-vm * Ts / Lcorr);
    b = [sqrt(1 - rho_s^2)];
    a = [1, -rho_s];
    slowFading_dB = MA + SigmaA * randn(1,length(t)); % 低通滤波前信号
    amplitude_filtered = filter(b, a, slowFading_dB);% 低通滤波后信号
    slowFading_linear = 10.^(amplitude_filtered / 20);
    vectorLosPath= [sin(losZOD * derad) * cos(losAOD * derad); ...                 % LoS射线矢量
        sin(losZOD * derad) * sin(losAOD * derad); ...
        cos(losZOD* derad)];
    fd = fc/c * sum(vectorLosPath .* position.terminalVelocity);  % LoS径多普勒频率
    slowFading_linear = slowFading_linear*exp(1j*2*pi*fd);
    all_slowFading = [all_slowFading , slowFading_linear];
    H_Martix_tMode = all_slowFading + all_fastFading;

    if i ==1 || mod(i,3) == 0 || durationList(i) > 45
    if numsend <= 65
       
        send([num2str(numsend)], parameter.socket);
        numsend = numsend+5;
       
    end
    end

end
% 计算累积距离
cumulative_distance = cumsum([0, durationList * vm]); % 乘以速度
end

function [x_t,t] = generate_complex_time_series(T, fs)
    % T: 时间长度（秒）
    % fs: 采样频率（Hz）
    % 创建时间向量
    t = 0:1/fs:T-1/fs;
    % 生成复数时间序列
    x_real = randn(size(t));
    x_imag = randn(size(t));
    x_t = x_real + 1i*x_imag;
end

function  [y_t,cumulative_distances]= jakes_filter(x_t, t, fm, distance, vm)  
% x_t: 输入的时间序列
    % t: 时间向量，对应于x_t的每个采样点
    % fm: 最大多普勒频移
    % 从输入时间序列获取采样间隔
    dt = mean(diff(t)); % 计算时间向量中连续点之间的平均时间差
    fs = 1 / dt; % 采样频率
    % 创建频率向量
    N = length(x_t); % 信号长度
    f = (-N/2:N/2-1) * (fs/N); % 频率向量
    % % 计算Jakes滤波器的频域表达式
    S_f = zeros(size(f));
    mask = abs(f) < fm;
    S_f(mask) = 1 ./ (pi * fm * sqrt(1 - (f(mask) / fm).^2+ realmin));
    % S_f = zeros(size(f));
    % for i = 1:length(f)
    %     if abs(f(i)) < fm
    %         S_f(i) = 1 / (pi * fm * sqrt(1 - (f(i) / fm)^2));
    %     else
    %         S_f(i) = 0;
    %     end
    % end
    K = 1/norm(S_f)*sqrt(length(S_f));
    S_f = K*S_f;
    % 对输入信号进行傅里叶变换
    X_f = fft(x_t);
    % 应用Jakes滤波器
    Y_f = X_f .* S_f;
    % 傅里叶逆变换，得到滤波后的时域信号
    y_t = ifft(Y_f);
    % 确保y_t与x_t具有相同的时间向量
    y_t = y_t(1:length(x_t));
    m = length(t);
    cumulative_distances = zeros(1, m);
    % for j = 1:m
    %     cumulative_distances(j)= distance + vm * t(j); % 更新累积距离
    % end
    distance = repmat(distance,1,m);
    cumulative_distances= distance + vm .* t; % 更新累积距离

end

function [goodTable,badTable] = getLMSParamsP681(fc,theta,environment)
    % [GOODTABLE,BADTABLE] = getLMSParamsP681v11(FC,THETA,ENVIRONMENT) 
    % returns the LMS environment parameters according to ITU-R
    % P681-11, depending on the carrier frequency FC, elevation
    % angle THETA, and environment type ENVIRONMENT. GOODTABLE and
    % BADTABLE are structures with information about the good state
    % and bad state respectively.
    roundedElevation = NaN; % 预先定义，防止未赋值错误
    % Check the elevation angle
    coder.internal.errorIf((theta < 0) || (theta > 90), ...
        'satcom:p681LMSChannel:InvalidElevationAngle', ...
        sprintf("%g",theta));

    % Get the closest available elevation angle based on the values
    % of environment and carrier frequency
    if fc >= 1.5e9 && fc <= 5e9
        switch environment
            case {1,2,3,4}
                if theta < 25
                    roundedElevation = 20;
                elseif theta < 37.5
                    roundedElevation = 30;
                elseif theta < 52.5
                    roundedElevation = 45;
                elseif theta < 65
                    roundedElevation = 60;
                else
                    roundedElevation = 70;
                end
            case 5
                if theta < 25
                    roundedElevation = 20;
                elseif theta < 45
                    roundedElevation = 30;
                elseif theta < 65
                    roundedElevation = 60;
                else
                    roundedElevation = 70;
                end
            otherwise
                %  这里的错误检查在之前的 if 条件内，不会执行
                if (fc >= 1.5e9 && fc <= 5e9)
                    error("Invalid Carrier Frequency: fc should > 5 GHz");
                end
        end

    elseif fc >= 10e9 && fc <= 20e9
        switch environment
            case {6,1,7}
                roundedElevation = 30;
            case 8
                roundedElevation = 34;
            case 2
                if fc < 15.85e9
                    roundedElevation = 34;
                else
                    roundedElevation = 30;
                end
            otherwise
                if (fc >= 10e9 && fc <= 20e9)
                    error("Invalid Carrier Frequency: fc should < 10 GHz");
                end
        end
    else
        if (fc < 1.5e9) || (fc > 20e9) % 假设合法范围是 1.5GHz - 20GHz
            error("Invalid Carrier Frequency: fc must be between 1.5 and 20 GHz.");
        end
    end


    % For each frequency range and environment, generate parameter
    % tables of good and bad states
    if fc < 3e9
        switch environment
            case 1
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.0042 1.2049];
                    goodTable.MinDur = 3.9889;
                    goodTable.MeanMA = [-3.3681 3.3226];
                    goodTable.H1H2 = [0.1739 -11.5966];
                    goodTable.G1G2 = [0.0036 1.3230];
                    goodTable.Lcorr = 0.9680;
                    goodTable.F1F2 = [0.0870 2.8469];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [3.689 0.9796];
                    badTable.MinDur = 10.3114;
                    badTable.MeanMA = [-18.1771 3.2672];
                    badTable.H1H2 = [1.1411 4.0581];
                    badTable.G1G2 = [-0.2502 -1.2528];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.7332 1.1030];
                    goodTable.MinDur = 7.3174;
                    goodTable.MeanMA = [-2.3773 2.1222];
                    goodTable.H1H2 = [0.0941 -13.1679];
                    goodTable.G1G2 = [-0.2811 0.9323];
                    goodTable.Lcorr = 1.4731;
                    goodTable.F1F2 = [0.1378 3.3733];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.7582 1.2210];
                    badTable.MinDur = 5.7276;
                    badTable.MeanMA = [-17.4276 3.9532];
                    badTable.H1H2 = [0.9175 -0.8009];
                    badTable.G1G2 = [-0.1484 0.5910];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [3.0639 1.6980];
                    goodTable.MinDur = 10;
                    goodTable.MeanMA = [-1.8225 1.1317];
                    goodTable.H1H2 = [-0.0481 -14.7450];
                    goodTable.G1G2 = [-0.4643 0.3334];
                    goodTable.Lcorr = 1.7910;
                    goodTable.F1F2 = [0.0744 2.1423];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.9108 1.2602];
                    badTable.MinDur = 6;
                    badTable.MeanMA = [-15.4844 3.3245];
                    badTable.H1H2 = [0.9434 -1.7555];
                    badTable.G1G2 = [-0.0798 2.8101];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [2.8135 1.5962];
                    goodTable.MinDur = 10;
                    goodTable.MeanMA = [-1.5872 1.2446];
                    goodTable.H1H2 = [-0.5168 -17.4060];
                    goodTable.G1G2 = [-0.1953 0.5353];
                    goodTable.Lcorr = 1.7977;
                    goodTable.F1F2 = [-0.1285 5.4991];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.0211 0.6568];
                    badTable.MinDur = 1.9126;
                    badTable.MeanMA = [-14.1435 3.2706];
                    badTable.H1H2 = [0.6975 -7.5383];
                    badTable.G1G2 = [0.0422 3.2030];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [4.2919 2.4703];
                    goodTable.MinDur = 118.3312;
                    goodTable.MeanMA = [-1.8434 0.5370];
                    goodTable.H1H2 = [-4.7301 -26.5687];
                    goodTable.G1G2 = [0.5192 1.9583];
                    goodTable.Lcorr = 2.0963;
                    goodTable.F1F2 = [-0.0826 2.8824];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.1012 1.0341];
                    badTable.MinDur = 4.8569;
                    badTable.MeanMA = [-12.9383 1.7588];
                    badTable.H1H2 = [2.5318 16.8468];
                    badTable.G1G2 = [0.3768 8.4377];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 2
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.2201 1.2767];
                    goodTable.MinDur = 2.2914;
                    goodTable.MeanMA = [-2.7191 1.3840];
                    goodTable.H1H2 = [-0.3037 -13.0719];
                    goodTable.G1G2 = [-0.1254 0.7894];
                    goodTable.Lcorr = 0.9290;
                    goodTable.F1F2 = [0.2904 1.0324];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2657 1.3812];
                    badTable.MinDur = 2.5585;
                    badTable.MeanMA = [-13.8808 2.5830];
                    badTable.H1H2 = [1.0136 0.5158];
                    badTable.G1G2 = [-0.1441 0.7757];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [3.0138 1.4161];
                    goodTable.MinDur = 8.3214;
                    goodTable.MeanMA = [-0.7018 1.2107];
                    goodTable.H1H2 = [-0.6543 -14.6457];
                    goodTable.G1G2 = [-0.1333 0.8992];
                    goodTable.Lcorr = 1.7135;
                    goodTable.F1F2 = [0.1091 3.3];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.4521 0.7637];
                    badTable.MinDur = 5.9087;
                    badTable.MeanMA = [-11.9823 3.4728];
                    badTable.H1H2 = [0.62 -7.5485];
                    badTable.G1G2 = [-0.1644 0.2762];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [4.5857 1.3918];
                    goodTable.MinDur = 126.8375;
                    goodTable.MeanMA = [-1.1496 1.0369];
                    goodTable.H1H2 = [0.2148 -17.8462];
                    goodTable.G1G2 = [0.0729 1.0303];
                    goodTable.Lcorr = 3.2293;
                    goodTable.F1F2 = [0.5766 0.7163];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2414 0.7884];
                    badTable.MinDur = 4.3132;
                    badTable.MeanMA = [-10.3806 2.3543];
                    badTable.H1H2 = [0.0344 -14.2087];
                    badTable.G1G2 = [0.0662 3.5043];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [3.4124 1.4331];
                    goodTable.MinDur = 19.5431;
                    goodTable.MeanMA = [-0.7811 0.7979];
                    goodTable.H1H2 = [-2.1102 -19.7954];
                    goodTable.G1G2 = [-0.2284 0.2796];
                    goodTable.Lcorr = 2.0215;
                    goodTable.F1F2 = [-0.4097 8.7440];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.9922 0.7132];
                    badTable.MinDur = 3.1213;
                    badTable.MeanMA = [-12.1436 3.1798];
                    badTable.H1H2 = [0.4372 -8.3651];
                    badTable.G1G2 = [-0.2903 -0.6001];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [4.2919 2.4703];
                    goodTable.MinDur = 118.3312;
                    goodTable.MeanMA = [-1.8434 0.5370];
                    goodTable.H1H2 = [-4.7301 -26.5687];
                    goodTable.G1G2 = [0.5192 1.9583];
                    goodTable.Lcorr = 2.0963;
                    goodTable.F1F2 = [-0.0826 2.8824];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.1012 1.0341];
                    badTable.MinDur = 4.8569;
                    badTable.MeanMA = [-12.9383 1.7588];
                    badTable.H1H2 = [2.5318 16.8468];
                    badTable.G1G2 = [0.3768 8.4377];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 3
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.7663 1.1211];
                    goodTable.MinDur = 6.5373;
                    goodTable.MeanMA = [-2.5017 2.3059];
                    goodTable.H1H2 = [0.0238 -11.4824];
                    goodTable.G1G2 = [-0.2735 1.3898];
                    goodTable.Lcorr = 0.8574;
                    goodTable.F1F2 = [0.0644 2.6740];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2328 1.3788];
                    badTable.MinDur = 2.8174;
                    badTable.MeanMA = [-15.2300 5.0919];
                    badTable.H1H2 = [0.9971 0.8970];
                    badTable.G1G2 = [-0.0568 1.9253];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.4246 1.3025];
                    goodTable.MinDur = 5.4326;
                    goodTable.MeanMA = [-2.2284 1.4984];
                    goodTable.H1H2 = [-0.3431 -14.0798];
                    goodTable.G1G2 = [-0.2215 1.0077];
                    goodTable.Lcorr = 0.8264;
                    goodTable.F1F2 = [-0.0576 3.3977];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8980 1.0505];
                    badTable.MinDur = 2.4696;
                    badTable.MeanMA = [-15.1583 4.0987];
                    badTable.H1H2 = [0.9614 0.3719];
                    badTable.G1G2 = [-0.0961 1.3123];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [2.8402 1.4563];
                    goodTable.MinDur = 10.4906;
                    goodTable.MeanMA = [-1.2871 0.6346];
                    goodTable.H1H2 = [-0.0222 -16.7316];
                    goodTable.G1G2 = [-0.3905 0.4880];
                    goodTable.Lcorr = 1.4256;
                    goodTable.F1F2 = [-0.0493 5.3952];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8509 0.8736];
                    badTable.MinDur = 2.6515;
                    badTable.MeanMA = [-12.6718 3.1722];
                    badTable.H1H2 = [0.8329 -3.9947];
                    badTable.G1G2 = [-0.0980 1.3381];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [3.7630 1.2854];
                    goodTable.MinDur = 17.6726;
                    goodTable.MeanMA = [-0.5364 0.6115];
                    goodTable.H1H2 = [-0.1418 -17.8032];
                    goodTable.G1G2 = [-0.2120 0.7819];
                    goodTable.Lcorr = 0.8830;
                    goodTable.F1F2 = [-0.8818 10.1610];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.7192 1.1420];
                    badTable.MinDur = 2.5981;
                    badTable.MeanMA = [-9.5399 2.0732];
                    badTable.H1H2 = [-0.4454 -16.8201];
                    badTable.G1G2 = [0.0609 2.5925];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [4.0717 1.2475];
                    goodTable.MinDur = 30.8829;
                    goodTable.MeanMA = [-0.3340 0.6279];
                    goodTable.H1H2 = [-1.6253 -19.7558];
                    goodTable.G1G2 = [-0.4438 0.6355];
                    goodTable.Lcorr = 1.5633;
                    goodTable.F1F2 = [-0.3483 5.1244];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.5673 0.5948];
                    badTable.MinDur = 2.1609;
                    badTable.MeanMA = [-8.3686 2.5603];
                    badTable.H1H2 = [0.1788 -9.5153];
                    badTable.G1G2 = [-0.0779 1.1209];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 4
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.1597 1.3766];
                    goodTable.MinDur = 2.0744;
                    goodTable.MeanMA = [-0.8065 1.5635];
                    goodTable.H1H2 = [-0.9170 -12.1228];
                    goodTable.G1G2 = [-0.0348 0.9571];
                    goodTable.Lcorr = 0.8845;
                    goodTable.F1F2 = [0.0550 2.6383];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.9587 1.5465];
                    badTable.MinDur = 1.3934;
                    badTable.MeanMA = [-10.6615 2.6170];
                    badTable.H1H2 = [0.8440 -1.4804];
                    badTable.G1G2 = [-0.1069 1.6141];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.5579 1.2444];
                    goodTable.MinDur = 3.5947;
                    goodTable.MeanMA = [-1.3214 1.6645];
                    goodTable.H1H2 = [-1.0445 -14.3176];
                    goodTable.G1G2 = [-0.1656 0.7180];
                    goodTable.Lcorr = 1.0942;
                    goodTable.F1F2 = [0.0256 3.8527];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.3791 1.1778];
                    badTable.MinDur = 2.2800;
                    badTable.MeanMA = [-10.4240 2.4446];
                    badTable.H1H2 = [0.6278 -4.8146];
                    badTable.G1G2 = [-0.0451 2.2327];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [3.1803 1.3427];
                    goodTable.MinDur = 6.7673;
                    goodTable.MeanMA = [-0.9902 1.0348];
                    goodTable.H1H2 = [-0.4235 -16.8380];
                    goodTable.G1G2 = [-0.1095 0.6893];
                    goodTable.Lcorr = 2.3956;
                    goodTable.F1F2 = [0.2803 4.0004];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.5382 1.1291];
                    badTable.MinDur = 3.3683;
                    badTable.MeanMA = [-10.2891 2.3090];
                    badTable.H1H2 = [0.3386 -9.7118];
                    badTable.G1G2 = [-0.046 2.1310];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [2.9322 1.3234];
                    goodTable.MinDur = 5.7209;
                    goodTable.MeanMA = [-0.6153 1.1723];
                    goodTable.H1H2 = [-1.4024 -16.9664];
                    goodTable.G1G2 = [-0.2516 0.5353];
                    goodTable.Lcorr = 1.7586;
                    goodTable.F1F2 = [0.1099 4.2183];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.1955 1.1115];
                    badTable.MinDur = 1.6512;
                    badTable.MeanMA = [-9.9595 2.2188];
                    badTable.H1H2 = [0.2666 -9.0046];
                    badTable.G1G2 = [-0.0907 1.4730];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [3.8768 1.4738];
                    goodTable.MinDur = 16.0855;
                    goodTable.MeanMA = [-0.7818 0.7044];
                    goodTable.H1H2 = [-2.9566 -20.0326];
                    goodTable.G1G2 = [-0.2874 0.4050];
                    goodTable.Lcorr = 1.6546;
                    goodTable.F1F2 = [-0.3914 6.6931];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8445 0.8874];
                    badTable.MinDur = 2.9629;
                    badTable.MeanMA = [-6.7769 2.1339];
                    badTable.H1H2 = [-0.3723 -14.9638];
                    badTable.G1G2 = [-0.1822 0.1163];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            otherwise % 5
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.5818 1.7310];
                    goodTable.MinDur = 9.2291;
                    goodTable.MeanMA = [-0.8449 1.3050];
                    goodTable.H1H2 = [-0.3977 -12.3714];
                    goodTable.G1G2 = [0.0984 1.3138];
                    goodTable.Lcorr = 1.1578;
                    goodTable.F1F2 = [0.0994 2.4200];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.7136 1.1421];
                    badTable.MinDur = 1.6385;
                    badTable.MeanMA = [-10.8315 2.2642];
                    badTable.H1H2 = [0.8589 -2.4054];
                    badTable.G1G2 = [-0.1804 0.8553];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [3.2810 1.4200];
                    goodTable.MinDur = 14.4825;
                    goodTable.MeanMA = [-1.3799 1.0010];
                    goodTable.H1H2 = [-0.8893 -16.4615];
                    goodTable.G1G2 = [-0.2432 0.6519];
                    goodTable.Lcorr = 1.9053;
                    goodTable.F1F2 = [0.0196 3.9374];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8414 0.9697];
                    badTable.MinDur = 2.7681;
                    badTable.MeanMA = [-11.1669 2.4724];
                    badTable.H1H2 = [-0.1030 -13.7102];
                    badTable.G1G2 = [-0.1025 1.7671];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [3.255 1.287];
                    goodTable.MinDur = 6.47;
                    goodTable.MeanMA = [0 0.3];
                    goodTable.H1H2 = [-2.024 -19.454];
                    goodTable.G1G2 = [0.273 0.403];
                    goodTable.Lcorr = 3.84;
                    goodTable.F1F2 = [-1.591 12.274];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [3.277 1.260];
                    badTable.MinDur = 7.81;
                    badTable.MeanMA = [-2.32 2.06];
                    badTable.H1H2 = [-1.496 -22.894];
                    badTable.G1G2 = [-0.361 -0.119];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [4.3291 0.7249];
                    goodTable.MinDur = 27.3637;
                    goodTable.MeanMA = [-0.1625 0.3249];
                    goodTable.H1H2 = [0.6321 -21.5594];
                    goodTable.G1G2 = [0.1764 0.4135];
                    goodTable.Lcorr = 1.6854;
                    goodTable.F1F2 = [3.0127 6.2345];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [3.4534 0.9763];
                    badTable.MinDur = 8.9481;
                    badTable.MeanMA = [-1.6084 0.5817];
                    badTable.H1H2 = [-0.3976 -22.7905];
                    badTable.G1G2 = [-0.0796 0.1939];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
        end
    elseif fc < 5e9
        % Frequencies between 3 GHz and 5 GHz
        switch environment
            case 1
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.5467 1.0431];
                    goodTable.MinDur = 5.2610;
                    goodTable.MeanMA = [-2.7844 2.6841];
                    goodTable.H1H2 = [0.1757 -12.9417];
                    goodTable.G1G2 = [-0.2044 1.5866];
                    goodTable.Lcorr = 1.4243;
                    goodTable.F1F2 = [0.1073 1.9199];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [3.6890 0.9796];
                    badTable.MinDur = 10.3114;
                    badTable.MeanMA = [-19.4022 3.2428];
                    badTable.H1H2 = [0.9638 -0.9382];
                    badTable.G1G2 = [0.0537 4.5670];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.0158 1.2348];
                    goodTable.MinDur = 4.5491;
                    goodTable.MeanMA = [-3.7749 2.2381];
                    goodTable.H1H2 = [-0.1564 -15.1531];
                    goodTable.G1G2 = [-0.0343 1.0602];
                    goodTable.Lcorr = 0.8999;
                    goodTable.F1F2 = [0.2707 -0.0287];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2627 1.4901];
                    badTable.MinDur = 2.0749;
                    badTable.MeanMA = [-17.9098 2.9828];
                    badTable.H1H2 = [0.8250 -2.5833];
                    badTable.G1G2 = [-0.0741 2.1406];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [2.3005 1.6960];
                    goodTable.MinDur = 10;
                    goodTable.MeanMA = [-1.4466 1.1472];
                    goodTable.H1H2 = [0.1550 -13.6861];
                    goodTable.G1G2 = [0.1666 1.2558];
                    goodTable.Lcorr = 1.6424;
                    goodTable.F1F2 = [0.2517 -0.3512];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.6314 1.1210];
                    badTable.MinDur = 6;
                    badTable.MeanMA = [-15.3926 3.2527];
                    badTable.H1H2 = [0.9509 -1.2462];
                    badTable.G1G2 = [0.0363 4.4356];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [2.4546 1.9595];
                    goodTable.MinDur = 10;
                    goodTable.MeanMA = [-1.6655 0.8244];
                    goodTable.H1H2 = [-0.4887 -17.2505];
                    goodTable.G1G2 = [-0.3373 0.3285];
                    goodTable.Lcorr = 2.3036;
                    goodTable.F1F2 = [0.0025 1.4949];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8892 0.8982];
                    badTable.MinDur = 1.9126;
                    badTable.MeanMA = [-14.4922 3.4941];
                    badTable.H1H2 = [0.4501 -9.6935];
                    badTable.G1G2 = [0.1202 4.8329];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [2.8354 2.4631];
                    goodTable.MinDur = 67.5721;
                    goodTable.MeanMA = [-1.0455 0.2934];
                    goodTable.H1H2 = [-3.0973 -20.7862];
                    goodTable.G1G2 = [0.0808 0.8952];
                    goodTable.Lcorr = 2.2062;
                    goodTable.F1F2 = [0.0755 2.1426];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.5170 1.1057];
                    badTable.MinDur = 3.6673;
                    badTable.MeanMA = [-14.2294 5.4444];
                    badTable.H1H2 = [0.0908 -15.8022];
                    badTable.G1G2 = [0.0065 3.1520];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 2
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.8194 1.6507];
                    goodTable.MinDur = 11.1083;
                    goodTable.MeanMA = [-4.8136 1.9133];
                    goodTable.H1H2 = [-0.4500 -17.9227];
                    goodTable.G1G2 = [-0.1763 0.8244];
                    goodTable.Lcorr = 1.2571;
                    goodTable.F1F2 = [0.0727 2.8177];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.5873 1.3919];
                    badTable.MinDur = 4.4393;
                    badTable.MeanMA = [-17.0970 2.9350];
                    badTable.H1H2 = [0.8991 -2.4082];
                    badTable.G1G2 = [0.0582 4.0347];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.9226 1.3840];
                    goodTable.MinDur = 6.7899;
                    goodTable.MeanMA = [-1.9611 1.8460];
                    goodTable.H1H2 = [0.2329 -15.0063];
                    goodTable.G1G2 = [0.0334 1.3323];
                    goodTable.Lcorr = 1.6156;
                    goodTable.F1F2 = [0.1281 2.3949];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.7375 0.6890];
                    badTable.MinDur = 7.7356;
                    badTable.MeanMA = [-15.3022 2.9379];
                    badTable.H1H2 = [0.5146 -8.9987];
                    badTable.G1G2 = [0.0880 4.4692];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [4.3019 0.8530];
                    goodTable.MinDur = 36.1277;
                    goodTable.MeanMA = [-1.2730 0.9286];
                    goodTable.H1H2 = [0.2050 -17.5670];
                    goodTable.G1G2 = [0.0074 0.7490];
                    goodTable.Lcorr = 1.1191;
                    goodTable.F1F2 = [-0.9586 10.8084];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.3715 1.3435];
                    badTable.MinDur = 9.5511;
                    badTable.MeanMA = [-5.6373 2.9302];
                    badTable.H1H2 = [-0.7188 -21.0513];
                    badTable.G1G2 = [-0.2896 -0.3951];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [2.8958 1.7061];
                    goodTable.MinDur = 13.9133;
                    goodTable.MeanMA = [-1.1987 1.0492];
                    goodTable.H1H2 = [-1.6501 -18.9375];
                    goodTable.G1G2 = [-0.1369 0.4477];
                    goodTable.Lcorr = 3.0619;
                    goodTable.F1F2 = [-0.0419 5.8920];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.9128 0.6869];
                    badTable.MinDur = 2.9398;
                    badTable.MeanMA = [-13.1811 2.6228];
                    badTable.H1H2 = [0.6911 -6.0721];
                    badTable.G1G2 = [0.0598 3.7220];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [4.1684 1.0766];
                    goodTable.MinDur = 42.0185;
                    goodTable.MeanMA = [0.1600 0.5082];
                    goodTable.H1H2 = [-3.4369 -18.1632];
                    goodTable.G1G2 = [-1.1144 0.9703];
                    goodTable.Lcorr = 2.5817;
                    goodTable.F1F2 = [-0.1129 4.0555];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.4778 0.7033];
                    badTable.MinDur = 1.8473;
                    badTable.MeanMA = [-10.2225 1.8417];
                    badTable.H1H2 = [0.3934 -9.6284];
                    badTable.G1G2 = [-0.1331 0.7223];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 3
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.0262 1.2355];
                    goodTable.MinDur = 2.2401;
                    goodTable.MeanMA = [-3.1324 1.8929];
                    goodTable.H1H2 = [-0.4368 -15.1009];
                    goodTable.G1G2 = [-0.0423 1.2532];
                    goodTable.Lcorr = 0.8380;
                    goodTable.F1F2 = [0.0590 1.5623];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.9451 1.4293];
                    badTable.MinDur = 1.9624;
                    badTable.MeanMA = [-16.5697 4.0368];
                    badTable.H1H2 = [1.0921 1.6440];
                    badTable.G1G2 = [-0.0325 2.4452];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.4504 1.1061];
                    goodTable.MinDur = 2.3941;
                    goodTable.MeanMA = [-1.8384 1.7960];
                    goodTable.H1H2 = [-0.5582 -14.4416];
                    goodTable.G1G2 = [-0.4545 0.8188];
                    goodTable.Lcorr = 0.9268;
                    goodTable.F1F2 = [-0.0330 2.7056];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.7813 1.2802];
                    badTable.MinDur = 2.1484;
                    badTable.MeanMA = [-15.4143 4.5579];
                    badTable.H1H2 = [0.8549 -2.2415];
                    badTable.G1G2 = [-0.0761 1.6768];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [2.2910 1.4229];
                    goodTable.MinDur = 2.8605;
                    goodTable.MeanMA = [-0.0018 1.1193];
                    goodTable.H1H2 = [-1.2023 -14.0732];
                    goodTable.G1G2 = [-0.1033 0.9299];
                    goodTable.Lcorr = 0.9288;
                    goodTable.F1F2 = [0.0002 1.9694];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.2738 1.1539];
                    badTable.MinDur = 0.7797;
                    badTable.MeanMA = [-12.1063 2.9814];
                    badTable.H1H2 = [0.6537 -4.5948];
                    badTable.G1G2 = [-0.0815 1.6693];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [3.0956 1.3725];
                    goodTable.MinDur = 8.1516;
                    goodTable.MeanMA = [-0.5220 1.0950];
                    goodTable.H1H2 = [0.0831 -16.8546];
                    goodTable.G1G2 = [0.0411 1.1482];
                    goodTable.Lcorr = 1.2251;
                    goodTable.F1F2 = [-0.0530 2.7165];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.0920 1.2080];
                    badTable.MinDur = 0.7934;
                    badTable.MeanMA = [-12.1817 3.3604];
                    badTable.H1H2 = [1.1006 0.5381];
                    badTable.G1G2 = [-0.0098 2.4287];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [3.9982 1.3320];
                    goodTable.MinDur = 28.3220;
                    goodTable.MeanMA = [-1.3403 0.7793];
                    goodTable.H1H2 = [-0.4861 -19.5316];
                    goodTable.G1G2 = [-0.2356 0.7178];
                    goodTable.Lcorr = 1.4378;
                    goodTable.F1F2 = [-0.0983 3.9005];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.4165 0.4685];
                    badTable.MinDur = 2.5168;
                    badTable.MeanMA = [-11.9560 1.5654];
                    badTable.H1H2 = [0.5663 -6.8615];
                    badTable.G1G2 = [-0.2903 -1.2715];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            case 4
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.0294 1.4280];
                    goodTable.MinDur = 1.7836;
                    goodTable.MeanMA = [-3.2536 1.6159];
                    goodTable.H1H2 = [-0.5718 -16.1382];
                    goodTable.G1G2 = [-0.0805 0.9430];
                    goodTable.Lcorr = 1.0863;
                    goodTable.F1F2 = [0.1263 1.4478];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.0290 1.5493];
                    badTable.MinDur = 1.5269;
                    badTable.MeanMA = [-14.3363 2.7753];
                    badTable.H1H2 = [0.8186 -2.9963];
                    badTable.G1G2 = [-0.0822 1.7660];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.1218 1.4895];
                    goodTable.MinDur = 2.4539;
                    goodTable.MeanMA = [-1.5431 1.8811];
                    goodTable.H1H2 = [-0.7288 -14.1626];
                    goodTable.G1G2 = [-0.1241 0.9482];
                    goodTable.Lcorr = 1.3253;
                    goodTable.F1F2 = [0.0849 1.6324];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2051 1.5741];
                    badTable.MinDur = 2.1289;
                    badTable.MeanMA = [-12.8884 3.0097];
                    badTable.H1H2 = [0.6635 -4.6034];
                    badTable.G1G2 = [-0.0634 2.3898];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 45
                    goodTable = struct;
                    goodTable.MeanVar = [3.1803 1.3427];
                    goodTable.MinDur = 6.7673;
                    goodTable.MeanMA = [0.0428 1.6768];
                    goodTable.H1H2 = [-0.9948 -14.4265];
                    goodTable.G1G2 = [-0.1377 1.0077];
                    goodTable.Lcorr = 2.0419;
                    goodTable.F1F2 = [0.1894 2.1378];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.4017 1.1315];
                    badTable.MinDur = 3.5668;
                    badTable.MeanMA = [-11.3173 2.7467];
                    badTable.H1H2 = [0.2929 -9.7910];
                    badTable.G1G2 = [-0.0387 2.6194];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [2.4961 1.4379];
                    goodTable.MinDur = 3.7229;
                    goodTable.MeanMA = [-1.0828 1.0022];
                    goodTable.H1H2 = [-1.2973 -16.6791];
                    goodTable.G1G2 = [-0.1187 0.6254];
                    goodTable.Lcorr = 1.9038;
                    goodTable.F1F2 = [0.1624 1.8417];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.2113 1.1254];
                    badTable.MinDur = 1.9001;
                    badTable.MeanMA = [-12.3044 2.3641];
                    badTable.H1H2 = [0.5456 -6.4660];
                    badTable.G1G2 = [-0.0443 2.3029];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [2.8382 1.3804];
                    goodTable.MinDur = 6.8051;
                    goodTable.MeanMA = [-0.8923 0.9455];
                    goodTable.H1H2 = [-1.3425 -17.5636];
                    goodTable.G1G2 = [-0.1210 0.6444];
                    goodTable.Lcorr = 2.1466;
                    goodTable.F1F2 = [0.0593 2.8854];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.1470 1.0038];
                    badTable.MinDur = 1.9195;
                    badTable.MeanMA = [-11.5722 2.3437];
                    badTable.H1H2 = [0.3459 -9.5399];
                    badTable.G1G2 = [-0.0275 2.6238];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
            otherwise %5
                if roundedElevation == 20
                    goodTable = struct;
                    goodTable.MeanVar = [2.9050 1.7236];
                    goodTable.MinDur = 10.7373;
                    goodTable.MeanMA = [-1.4426 1.2989];
                    goodTable.H1H2 = [0.4875 -13.5981];
                    goodTable.G1G2 = [0.1343 1.8247];
                    goodTable.Lcorr = 1.2788;
                    goodTable.F1F2 = [0.2334 0.7612];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.1969 0.9865];
                    badTable.MinDur = 2.2901;
                    badTable.MeanMA = [-14.4036 3.0396];
                    badTable.H1H2 = [0.5813 -6.9790];
                    badTable.G1G2 = [-0.0911 2.1475];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [2.7334 1.6971];
                    goodTable.MinDur = 10.2996;
                    goodTable.MeanMA = [-0.9996 1.0752];
                    goodTable.H1H2 = [0.3407 -14.8465];
                    goodTable.G1G2 = [-0.0413 1.2006];
                    goodTable.Lcorr = 1.7072;
                    goodTable.F1F2 = [0.0443 2.2591];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [1.8403 0.9268];
                    badTable.MinDur = 1.8073;
                    badTable.MeanMA = [-12.9855 2.8149];
                    badTable.H1H2 = [0.3553 -9.9284];
                    badTable.G1G2 = [0.0501 3.8667];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                elseif roundedElevation == 60
                    goodTable = struct;
                    goodTable.MeanVar = [3.4044 1.3980];
                    goodTable.MinDur = 10.4862;
                    goodTable.MeanMA = [0.4640 0.7060];
                    goodTable.H1H2 = [0.3710 -19.6032];
                    goodTable.G1G2 = [0.0332 0.5053];
                    goodTable.Lcorr = 1.8017;
                    goodTable.F1F2 = [3.1149 3.5721];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.5534 1.7143];
                    badTable.MinDur = 4.7289;
                    badTable.MeanMA = [-2.3787 0.8123];
                    badTable.H1H2 = [-2.3834 -24.6987];
                    badTable.G1G2 = [0.0172 0.7237];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                else % roundedElevation equals 70
                    goodTable = struct;
                    goodTable.MeanVar = [2.9223 1.0267];
                    goodTable.MinDur = 7.3764;
                    goodTable.MeanMA = [-0.1628 0.5104];
                    goodTable.H1H2 = [0.1590 -20.4767];
                    goodTable.G1G2 = [0.1137 0.4579];
                    goodTable.Lcorr = 1.3531;
                    goodTable.F1F2 = [-0.0538 5.1204];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [2.5188 1.3166];
                    badTable.MinDur = 7.2801;
                    badTable.MeanMA = [-2.3703 1.5998];
                    badTable.H1H2 = [-1.0228 -22.4769];
                    badTable.G1G2 = [-0.0986 0.2879];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.9];
                end
        end
    else
        % Frequencies between 10 GHz and 20 GHz
        switch environment
            case 1
                goodTable = struct;
                goodTable.MeanVar = [1.95 1.82];
                goodTable.MinDur = 0.01;
                goodTable.MeanMA = [-0.21 0.44];
                goodTable.H1H2 = [0 -32.62];
                goodTable.G1G2 = [0 0.44];
                goodTable.Lcorr = 5.67;
                goodTable.F1F2 = [0.10 1.49];
                goodTable.ProbRange = [0.05 0.95];
                badTable = struct;
                badTable.MeanVar = [0.05 1.40];
                badTable.MinDur = 1;
                badTable.MeanMA = [-13.96 8.93];
                badTable.H1H2 = [0.68 -10.06];
                badTable.G1G2 = [-0.37 0];
                badTable.Lcorr = goodTable.Lcorr;
                badTable.F1F2 = goodTable.F1F2;
                badTable.ProbRange = [0.03 0.97];
            case 2
                if roundedElevation == 30
                    goodTable = struct;
                    goodTable.MeanVar = [1.66 1.64];
                    goodTable.MinDur = 0.01;
                    goodTable.MeanMA = [-0.23 0.49];
                    goodTable.H1H2 = [0 -30.99];
                    goodTable.G1G2 = [0 0.49];
                    goodTable.Lcorr = 7.9;
                    goodTable.F1F2 = [0.08 1.67];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [0.10 1.70];
                    badTable.MinDur = 0.5;
                    badTable.MeanMA = [-8.93 8.41];
                    badTable.H1H2 = [0.48 -11.37];
                    badTable.G1G2 = [-0.45 0];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.006 0.921];
                else % roundedElevation equals 34
                    goodTable = struct;
                    goodTable.MeanVar = [1.0125 1.6944];
                    goodTable.MinDur = 1.5;
                    goodTable.MeanMA = [-0.02 0];
                    goodTable.H1H2 = [0 -38.17];
                    goodTable.G1G2 = [0 0.39];
                    goodTable.Lcorr = 0.5;
                    goodTable.F1F2 = [0.036 0.8];
                    goodTable.ProbRange = [0.05 0.95];
                    badTable = struct;
                    badTable.MeanVar = [-0.8026 1.288];
                    badTable.MinDur = 1.1;
                    badTable.MeanMA = [-5.4 7.3];
                    badTable.H1H2 = [0.69 -15.97];
                    badTable.G1G2 = [-0.21 0];
                    badTable.Lcorr = goodTable.Lcorr;
                    badTable.F1F2 = goodTable.F1F2;
                    badTable.ProbRange = [0.1 0.6];
                end
            case 8
                goodTable = struct;
                goodTable.MeanVar = [1.7663 1.9350];
                goodTable.MinDur = 0.9;
                goodTable.MeanMA = [0.05 0];
                goodTable.H1H2 = [0 -40.25];
                goodTable.G1G2 = [0 0.39];
                goodTable.Lcorr = 0.5;
                goodTable.F1F2 = [0.088 1.21];
                goodTable.ProbRange = [0.05 0.95];
                badTable = struct;
                badTable.MeanVar = [-0.4722 1.7232];
                badTable.MinDur = 0.8;
                badTable.MeanMA = [-16 10.4];
                badTable.H1H2 = [0.87 -14.26];
                badTable.G1G2 = [-0.21 0];
                badTable.Lcorr = goodTable.Lcorr;
                badTable.F1F2 = goodTable.F1F2;
                badTable.ProbRange = [0.1 0.9];
            case 6
                goodTable = struct;
                goodTable.MeanVar = [1.27 1.86];
                goodTable.MinDur = 0.01;
                goodTable.MeanMA = [-0.16 0.39];
                goodTable.H1H2 = [0 -29.61];
                goodTable.G1G2 = [0 0.39];
                goodTable.Lcorr = 31.7;
                goodTable.F1F2 = [0.15 1.28];
                goodTable.ProbRange = [0.05 0.95];
                badTable = struct;
                badTable.MeanVar = [-0.31 1.35];
                badTable.MinDur = 0.5;
                badTable.MeanMA = [-5.92 8.20];
                badTable.H1H2 = [0.34 -14.39];
                badTable.G1G2 = [-0.41 0];
                badTable.Lcorr = goodTable.Lcorr;
                badTable.F1F2 = goodTable.F1F2;
                badTable.ProbRange = [0.001 0.861];
            otherwise % 7
                goodTable = struct;
                goodTable.MeanVar = [1.37 1.94];
                goodTable.MinDur = 0.01;
                goodTable.MeanMA = [-0.19 0.47];
                goodTable.H1H2 = [0 -26.07];
                goodTable.G1G2 = [0 0.47];
                goodTable.Lcorr = 19.52;
                goodTable.F1F2 = [0.12 1.78];
                goodTable.ProbRange = [0.05 0.95];
                badTable = struct;
                badTable.MeanVar = [-0.02 1.92];
                badTable.MinDur = 0.5;
                badTable.MeanMA = [-5.84 7.47];
                badTable.H1H2 = [0.47 -12.78];
                badTable.G1G2 = [-0.41 0];
                badTable.Lcorr = goodTable.Lcorr;
                badTable.F1F2 = goodTable.F1F2;
                badTable.ProbRange = [0.0006 0.88];
        end
    end
end

function [AOA,AOD,EOA,EOD,ZOA,ZOD] = computeAzimuthElevation(position)

% Function: Calculate the azimuth and elevation angles between the terminal and the satellite
% Input values:
% terminalX: The X coordinate of the terminal
% terminalY: The Y coordinate of the terminal
% terminalZ: The Z coordinate of the terminal
% satelliteX: The X coordinate of the satellite
% satelliteY: The Y coordinate of the satellite
% satelliteZ: The Z coordinate of the satellite
% Return values:
% AOA: Azimuth angle of arrival
% AOD: Azimuth angle of departure
% EOA: Elevation angle of arrival
% EOD: Elevation angle of departure
% ZOA: Zenith angle of arrival
% ZOD: Zenith angle of departure

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