function  parameter = getParameters(channel_params,projectRoot)

channelParams = struct(channel_params);
global Re miu; 
Re = 6371e3;    
miu = 3.9860e14; 
derad = pi/180;

parameter = struct();                              % Construct a structure to save parameter settings

if isfield(channelParams,'channel_standard')
    enable = str2double(channelParams.channel_standard);
    parameter.channel_standard = enable;
else
    enable = 1;
end
channelModel = zeros(1,8);
channelModel(enable) = 1;
enchannelModel = logical(channelModel);

%currentFolder and save oudata Folder
parameter.currentFolder = projectRoot;
parameter.outDataFolder = fullfile(projectRoot,"OutData");

% configurable parameter

parameter.c = 3e8;                                 %m/s
parameter.Re = 6371e3;  
% 3GPP 38.811场景设置参数
if isfield(channelParams,'ntn_scene')
   parameter.sceneIdx = str2double(channelParams.ntn_scene);
else
    parameter.sceneIdx = 1;                            % This parameter is used to select the scenario, 1: dense urban scenario, 2: urban scenario, 3: suburban, 4:rural scenarios
end

if isfield(channelParams,'ntn_model')
   parameter.channelMod =  channelParams.ntn_model;
else
   parameter.channelMod = 'A';                        % channelMod: This parameter is used to select the channel scenario, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model 
end
% 载波频率设
if isfield(channelParams,'sample_rate')
    parameter.Fs = channelParams.sample_rate;   % Carrier frequency (GHz), 
else
    parameter.Fs = 1e5;                            
end
                                                   % 3GPP 38.811: S-band(2-4 GHz band), 2: Ka-band(26.5 to 40GHz band)(CDL)
% 信道采样频率、采样时长设置
% 信道采样频率、采样时长设置

if isfield(channelParams,'carrier_freq')
    parameter.fc = channelParams.carrier_freq;
else
    parameter.fc = 3;                               % Sampling frequency (Hz)
end

parameter.T = 0.2;                                   % Duration represented inside one MAT snapshot, s
if isfield(channelParams,'channel_snapshot_duration_s')
    parameter.T = double(channelParams.channel_snapshot_duration_s);
elseif isfield(channelParams,'snapshot_duration_s')
    parameter.T = double(channelParams.snapshot_duration_s);
end
if ~isscalar(parameter.T) || ~isfinite(parameter.T) || parameter.T <= 0
    error('channel_snapshot_duration_s must be a positive finite scalar.');
end
% parameter.Ttotal = 10;

% 收发天线高度和阵元数目
parameter.ht = 12.5;                               % Transmitting antenna height in metres (m)  
parameter.hr = 10.5;                               % Receiving antenna heights of terminal   

%以下为默认参数
parameter.c = 2.98e8;                              % Speed of light
% 信道采样时间、采样点数计算
parameter.Ts = 1 / parameter.Fs;                   % Sampling interval
parameter.N_Ts = parameter.T * parameter.Fs;       % Number of sampling points during T
%收发天线阵元数目，目前默认都设置为1，若设置为其他，变量维度需要对应修改
parameter.N_t = 1;                                 % Number of transmitter antennas
parameter.N_r = 1;                                 % Number of receiving end antennas

if isfield(channelParams,'antenna_pattern_file')
   antennaPatternFiles = string(channelParams.antenna_pattern_file);
   antennaPatternFiles = antennaPatternFiles(:);
   [~,name,ext] = arrayfun(@fileparts, antennaPatternFiles, ...
       'UniformOutput', false);
   parameter.antennaPatternName = name(:);
   parameter.antennaGainData = cell(numel(antennaPatternFiles),1);
   for j = 1:numel(antennaPatternFiles)
       antennaPattern = antennaPatternFiles(j);
       if strcmpi(ext{j},'.mat')
           antennaData = load(antennaPattern);
           if ~isfield(antennaData,'data')
               error('Antenna pattern MAT must contain variable data: %s', antennaPattern);
           end
           parameter.antennaGainData{j} = antennaData.data;  % 默认选取 phi=90,dB_LHCP
       elseif strcmpi(ext{j},'.csv')
           parameter.antennaGainData{j} = readtable(antennaPattern);
       else
           error('Unsupported antenna pattern file extension: %s', ext{j});
       end
   end

else
    filename = ('external_data\AnnexGain\AntennaGain.csv');
    parameter.antennaPatternName = {'AntennaGain'};
    parameter.antennaGainData = {readtable(filename)};
end

% parameter.antennaData = readtable(parameter.antennaGainData);
% parameter = struct();  
% parameter.terminalVelocity = [21.2132034;21.2132034;0];            % the velocity vector of terminal （m/s） 
% parameter.satelliteVelocity = [-5016.84805477673;-3268.68655794569;-4281.39345663318]; % the velocity vector of satellite （m/s） 

%终端的经纬度
parameter.terminalLatitude = 39;
parameter.terminalLongitude = 116;
parameter.terminalAltitude = 0;
%以下为参数初始化声明（转C需要）
%计算距离和角度
parameter.d2D = 0;                        % Two-dimensional distance between terminal and satellite
parameter.d3D = 0;                        % Three-dimensional distance between terminal and satellite
parameter.losAOA = 0;
parameter.losAOD = 0;
parameter.losZOA = 0;
parameter.losZOD = 0;
parameter.losEOA = 0;

%开普勒六根数模型
parameter.satelliteHeight = 1.507e6;
parameter.satelliteE = 0;
parameter.satelliteI = 40;
parameter.satelliteOmega = 26;
parameter.satelliteOmega1 = 0;
parameter.satelliteTheta = 90;
%
parameter.satelliteData = [Re + parameter.satelliteHeight, parameter.satelliteE, parameter.satelliteI, parameter.satelliteOmega, parameter.satelliteOmega1, parameter.satelliteTheta];
parameter.dT = 1;
if isfield(channelParams,'channel_snapshot_interval_s')
    parameter.dT = double(channelParams.channel_snapshot_interval_s);
elseif isfield(channelParams,'snapshot_interval_s')
    parameter.dT = double(channelParams.snapshot_interval_s);
end
if ~isscalar(parameter.dT) || ~isfinite(parameter.dT) || parameter.dT <= 0
    error('channel_snapshot_interval_s must be a positive finite scalar.');
end


%大尺度enable判断
if isfield(channelParams,'free_space_loss')
  parameter.enFSPL = channelParams.free_space_loss;
else
   parameter.enFSPL = false;
end

if isfield(channelParams,'atmos_absorption')
  parameter.enAtmo = channelParams.atmos_absorption;
else
  parameter.enAtmo = false;
end

if isfield(channelParams,'rain_attenuation')
  parameter.enRain = channelParams.rain_attenuation;
else
   parameter.enRain = false;
end

if isfield(channelParams,'cloud_fog_attenuation')
  parameter.enCloud = channelParams.cloud_fog_attenuation;
else
  parameter.enCloud = false;
end

if isfield(channelParams,'tropospheric_scintillation')
  parameter.enTropo = channelParams.tropospheric_scintillation;
else
    parameter.enTropo = false;
end

if isfield(channelParams,'ionospheric_scintillation')
  parameter.enIono = channelParams.ionospheric_scintillation;
else
   parameter.enIono = false;
end

if isfield(channelParams,'beam_diffusion')
  parameter.enBeam = channelParams.beam_diffusion;
else
    parameter.enBeam = false;
end

if isfield(channelParams,'shadow_fading')
  parameter.enShadow = channelParams.shadow_fading;
else
  parameter.enShadow = false;
end

if isfield(channelParams,'clutter_loss')
  parameter.enClutter = channelParams.clutter_loss;
else
 parameter.enClutter = false;
end

if isfield(channelParams,'clutter_model')
    parameter.clutterModelType  = str2double(channelParams.clutter_model);
else
    parameter.clutterModelType = 3;
end

if isfield(channelParams,'location_probability_p')
    parameter.p_percent  = channelParams.location_probability_p ;
else
    parameter.p_percent = 50;
end

if isfield(channelParams,'polarization_mismatch')
  parameter.enPol = channelParams.polarization_mismatch;
else
 parameter.enPol = false;
end

 
%小尺度enable判断

% parameter.encdl = false;
% parameter.enjake = false;
% parameter.entdl = false;
% parameter.enCLoo = false;
% parameter.enCorazza = true;
% parameter.enLutz = false;
% parameter.ITU_R = false;
% parameter.CustomMultipath = false;

parameter.encdl = enchannelModel(3);
parameter.CustomMultipath = enchannelModel(5);
parameter.entdl = enchannelModel(2);
parameter.enCLoo = enchannelModel(6);
parameter.enCorazza = enchannelModel(7);
parameter.enLutz = enchannelModel(8);
parameter.ITU_R = enchannelModel(4);


 %终端Ecef坐标
% parameter.terminalX = -2.17e+06; 
% parameter.terminalY = 4.45e+06;
% parameter.terminalZ = 4.00e+06;
%  parameter.terminalX = (parameter.terminalAltitude+Re) * cos( parameter.terminalLatitude*derad) * cos( parameter.terminalLongitude*derad); 
%  parameter.terminalY = (parameter.terminalAltitude+Re) * cos( parameter.terminalLatitude*derad) * sin( parameter.terminalLongitude*derad); 
%  parameter.terminalZ = (parameter.terminalAltitude+Re) * sin( parameter.terminalLatitude*derad);
% 
% terminalAzimuth = 45; terminalElevation = 0;
% parameter.terminalVel = 30; % m/s
% parameter.terminalVelocity = parameter.terminalVel * [cos(terminalElevation * derad) * cos(terminalAzimuth * derad); ...
%                                                        cos(terminalElevation * derad) * sin(terminalAzimuth * derad); ...
%                                                                                        sin(terminalElevation * derad)];
% parameter.minElevation = 5; 
%卫星Ecef坐标
% parameter.satelliteX = -2.82e+06;
% parameter.satelliteY = -3.38e+06;
% parameter.satelliteZ = 5.89e+06;

%时间
parameter.month = 1;                   % 一年中的第几月
parameter.day = 1;                       % 一年中的第几天
parameter.time = 1;

if isfield(channelParams,'los_status')
    parameter.IsLos = logical(channelParams.los_status);
else
    parameter.IsLos = false;
end


parameter.fadingType = {'Rican','Rayleigh'};   % Rayleigh、Rican、
parameter.specType = {'Jakes'};  % Jakes、Flat、Gaussian
parameter.Seed = 16464;

if isfield(channelParams,'path_num')
    parameter.nPaths = channelParams.path_num;
else
    parameter.nPaths = 1;
end
parameter.power_dB = 0;
parameter.K = 10;
parameter.tao = 0;

%ITU  1.5e9<fc<5e9  environment{1,2,3,4,5}; 10e9<fc<10e9  environment{1,2,6,7,8} 
if isfield(channelParams,'itu_scene')
    parameter.environment = str2double(channelParams.itu_scene);    
else
    parameter.environment = 1;
end

%CLoo&Corazza&Lutz



if isfield(channelParams,'log_normal_mean')
   parameter.mu_dB = channelParams.log_normal_mean;
else
    parameter.mu_dB = 1;       % 对数正态均值  
end

if isfield(channelParams,'log_normal_std')
   parameter.sigma_dB = channelParams.log_normal_std;
else
   parameter.sigma_dB  = 2;   % 对数正态标准差 
end

if isfield(channelParams,'rayleigh_std')
   parameter.sigma0 = channelParams.rayleigh_std;
else
    parameter.sigma0 = 4;      % 瑞利标准差
end

if isfield(channelParams,'rice_k_factor')
   parameter.K_linear =  channelParams.rice_k_factor;
else
    parameter.K_linear = 10;
end
parameter.K = parameter.K_linear;
if isfield(channelParams,'lutz_state')
   parameter.manual_state =  channelParams.lutz_state;
else
    parameter.manual_state = 0;
end

%轨道场景
if isfield(channelParams,'cloud_fog_attenuation')
    constellationSceneCode = str2double(channelParams.constellation_scene);
else
    constellationSceneCode = 1;
end
parameter.minElevation = 0;  

[sceneTraj, sceneMeta] = ConstellationSceneLoader(projectRoot, constellationSceneCode);

parameter.projectRoot = projectRoot;
parameter.constellationSceneCode = constellationSceneCode;
parameter.constellationSceneName = sceneMeta.SceneName;
parameter.sceneMeta = sceneMeta;
parameter.Ttotal = sceneMeta.AccessDuration;
if isfield(channelParams,'duration_time') && ~isempty(channelParams.duration_time)
    requestedDuration = double(channelParams.duration_time);
    if ~isscalar(requestedDuration) || ~isfinite(requestedDuration) || requestedDuration <= 0
        error('duration_time must be a positive finite scalar in seconds.');
    end
    if requestedDuration > sceneMeta.AccessDuration
        error('duration_time %.3f s exceeds the selected access duration %.3f s.', ...
            requestedDuration, sceneMeta.AccessDuration);
    end
    parameter.Ttotal = requestedDuration;
end

parameter.customTrajectory = sceneTraj;

parameter.selectedTerminal = sceneMeta.TerminalName;
parameter.selectedGateway = sceneMeta.Gateway;
parameter.selectedSatID = sceneMeta.Satellite;
parameter.terminalLatitude = sceneMeta.TerminalLatitude;
parameter.terminalLongitude = sceneMeta.TerminalLongitude;
parameter.terminalAltitude = sceneMeta.TerminalAltitude;
% parameter.terminalVel = 0;
% parameter.terminalVelocity = [0; 0; 0];

parameter.terminalVel = 5;
parameter.terminalVelocity = [3; 4; 0];

R_term = Re + parameter.terminalAltitude;
parameter.terminalX = R_term * cos(parameter.terminalLatitude * derad) * cos(parameter.terminalLongitude * derad);
parameter.terminalY = R_term * cos(parameter.terminalLatitude * derad) * sin(parameter.terminalLongitude * derad);
parameter.terminalZ = R_term * sin(parameter.terminalLatitude * derad);

parameter.satelliteHeight = 1.507e6;
parameter.satelliteE = 0;
parameter.satelliteI = 40;
parameter.satelliteOmega = 26;
parameter.satelliteOmega1 = 0;
parameter.satelliteTheta = 90;
parameter.satelliteData = [Re + parameter.satelliteHeight, parameter.satelliteE, parameter.satelliteI, ...
                            parameter.satelliteOmega, parameter.satelliteOmega1, parameter.satelliteTheta];
parameter.trajectoryMode = 'External';


% socket
parameter.socket = struct( ...
    'targetIP', '127.0.0.1', ...
    'targetPort', 6000, ...
    'enable', true);
if isfield(channelParams,'enable_socket')
    parameter.socket.enable = logical(channelParams.enable_socket);
end


% fields = fieldnames(channel_params);  

% for i = 1:length(fields)
%     field_name = fields{i};       
%     field_data = channel_params.(field_name);   
%     type_str = class(field_data); 
%     fprintf('%s--%s\n', field_name, type_str);
% end



if isfield(channelParams,'is_quick_simulation')
   parameter.is_quick_simulation = channelParams.is_quick_simulation; %
else
    parameter.is_quick_simulation = false;       
end

if  ~ismember(parameter.channel_standard,[1,2,3,5])
 parameter.enShadow = false;
end


parameter.topoData0 = load('external_data/ITU_R_P1511_3_data/ChinaTopo.dat');              % Read the topographic height data from ITU-R P.1511, with a latitude and longitude increment of 1/12 degree
parameter.TOPO = load('external_data\ITU_R_P1511_3_data\ChinaTopo.dat');  

end




