function [H_t,tao_n,P_n,fd_shift] = TDLModel(parameter,position)

% Function: Compute channel coefficient by section 6.9.2 of 3GPP TR 38.811 V15.4.0 (2020-09) for different TDL channel models:
% 'A': NTN-TDL-A model, 'B': NTN-TDL-B model, 'C': NTN-TDL-C model, 'D': NTN-TDL-D model  
% Input values:
% sceneIdx: This parameter is used to select the scenario,
% 1: Dense urban scenario, 2: Urban scenario, 3: Suburban scenarios，4: Rural scenarios
% channelMod: This parameter is used to select the channel scenario, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model 
% fc: Frequency, S-band(2-4 GHz band), Ka-band(26.5 to 40GHz)，losEOA: Elevation angle of LOS channel
% Return values:
% H_Martix: Channel coefficient of clusters
% H_Martix_t: Channel coefficient clusters to time t
% tao_n: Delay of clusters
  
% default parameter
global Re;
Re = 6371e3;                                         % Earth's radius 
parameter.v_ter = sqrt(sum(position.terminalVelocity.^2));
parameter.v_sat = sqrt(sum(position.satelliteVelocity.^2));
% parameter.R = Re;
% parameter.h = 1e3;
[AOA,AOD,EOA,~,ZOA,ZOD] = computeAzimuthElevation(position);     % Calculate the azimuth ,elevation and Zenith angles between the terminal and the satellite

position.losAOA = AOA;
position.losAOD = AOD;
position.losZOA = ZOA;
position.losZOD = ZOD;

position.losEOA = EOA;
table6_7_2_1a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_1a.txt',51,9);  % Load data of 3GPP_TR_38_811_table6_7_2
derad = pi/180;
sceneIdx = parameter.sceneIdx;
channelMod = parameter.channelMod;
fc = parameter.fc;

losEOA = position.losEOA;
if(fc>=1e9)                                % Ensure that the frequency unit is GHz
    fc = fc / 1e9;
end
if (channelMod == 'A' || channelMod == 'B')
    channelIdx = 2;
else
    channelIdx = 1;
end

diffs = abs(table6_7_2_1a(1,:) - losEOA);  % Calculate the absolute difference between the target elevation angle and each elevation angle in the data table
[~, idx] = min(diffs);                     % Find the index corresponding to the minimum difference, determine the row number taken from the data table, idx

tao_n = [];
P_n = [];
scenariosPara = TDLSceneSwitch(sceneIdx,channelIdx,fc,idx,channelMod);
modeScenariosPara = computeScenariosPara(parameter,scenariosPara,channelIdx,position,channelMod);

tao_n = modeScenariosPara.tao_n;
P_n = modeScenariosPara.P_n;
Pn = kron(sqrt((P_n)/sum(P_n)), ones(1));
modeScenariosPara.Pn = Pn;
P_n = 10*log10(P_n);
[H_t,fd_shift] = generatejakes(parameter,scenariosPara,position,modeScenariosPara,channelMod);
% H_t = sqrt(Pn).*H_jakes;

end

function  scenariosPara = TDLSceneSwitch(sceneIdx,channelIdx,fc,idx,channelMod)
        
        if(fc <=  4 && fc >= 2)
            bandIdx = 1;                           % This parameter is used to select the frequency band scenario, 1: S-band(2-4 GHz band), 2: Ka-band(26.5 to 40GHz band)
        else
            bandIdx = 2;
        end
        % if (channelMod == 'A' || channelMod == 'B')
        %     channelIdx = 2;
        % else
        %     channelIdx = 1;
        % end
switch sceneIdx
    case 1
        if(bandIdx == 1)
            if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_1a.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_2a.txt';
            end
        else
             if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_1b.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_2b.txt';
            end
        end
    case 2
        if(bandIdx == 1)
            if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_3a.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_4a.txt';
            end
        else
             if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_3b.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_4b.txt';
            end
        end
    case 3
        if(bandIdx == 1)
            if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_5a.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_6a.txt';
            end
        else
             if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_5b.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_6b.txt';
            end
        end
    case 4
        if(bandIdx == 1)
            if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_7a.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_8a.txt';
            end
        else
             if(channelIdx == 1)
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_7b.txt';
            else
                Datafile = 'external_data/3GPP_TR_38_811_data/table6_7_2_8b.txt';
            end
        end
end
if channelIdx == 1
    Datas = readCDLData(Datafile,51,9);
else 
    Datas = readCDLData(Datafile,49,9);
end
scenariosPara = fastFadingData(Datas,idx,channelIdx,channelMod);

end


function   [H_Martix_tMode,fd_shift] = generatejakes(parameter,scenariosPara,position,compScenariosPara,channelMod)

    derad = pi/180;
    N = scenariosPara.N;
    EOA = position.losEOA;

    v_sat = parameter.v_sat;
    parameter.power_dB = compScenariosPara.Pn ;
    % R = parameter.R;
    
    K = 10.224;
    % theta = compScenariosPara.theta;

    parameter.nPaths = N;
    if channelMod =="A" || channelMod == "B"
        parameter.IsLos = false;
    elseif channelMod =="C"
        parameter.IsLos = true;
        K = 10.224;
    elseif channelMod == "D"
        parameter.IsLos = true;
        K = 11.707;
    end
    parameter.K = K;

 costheta = 0;
 if channelMod =="C" ||  channelMod == "D"
    vectorLosPath= [sin(position.losZOD * derad) * cos(position.losAOD * derad); ...                 % LoS射线矢量
                    sin(position.losZOD * derad) * sin(position.losAOD * derad); ...
                    cos(position.losZOD* derad)];
     costheta = sum(vectorLosPath .* position.terminalVelocity)/sqrt(sum(position.terminalVelocity.^2)); 
 end

 [H_Martix_tMode,fd_shift,~] = generateJakesSpec(parameter,v_sat,EOA,costheta);


end




function [tau_n,P_n] = clusterDelayPower(scenariosPara,K,DS,channelIdx)

% Function: Calculate Ricean K-factor, Cluster delays, Cluster powers according to different scenario conditions
% Input values:
% scenariosPara: Structure containing parameters related to fast Fading
% K: Ricean K-factor, DS: Delay spread
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% Return values:
% tau_n: Cluster delays
% P_n: Cluster powers

r_tau = scenariosPara.r_tau;             % Get input parameters
N = scenariosPara.N;
zeta = scenariosPara.zeta;
Xn = myrand(N);                          % Draw random variables from a uniform distribution U(0,1)
tau_n1 = -r_tau .* DS .* log(Xn) ;       % Compute cluster delay according to equation (7.5-1) in 3GPP TR 138 901 V16.1.0
if(channelIdx == 1)
    C_tau = 0.7705 - 0.0433 .* K + 0.0002 .* K.^2+0.00001 .* K .^ 3;  % Calculated from equation (7.5-3) in 3GPP TR 138 901 V16.1.0
    tau_n = (sort(tau_n1 - min(tau_n1))) ./ C_tau;                    % Calculation of the additional scaling of the delay according to equation (7.5-4) in 3GPP TR 138 901 V16.1.0
else
    tau_n = sort(tau_n1 - min(tau_n1));     % Normalise the delays
end
Zn = zeta .* randn(1, N);                  % Generates Zn, obeys a normal distribution with N(0, zeta^2)
P_n1 = (exp(-tau_n.*((r_tau-1)./(r_tau*DS)))).*10.^(-Zn/10);
if(channelIdx == 1)
    K_R = 10.^(K / 10);                    % K_R is the Ricean K-factor converted to linear scale
    P_n = (1 ./ (K_R + 1)) .* (P_n1 / sum(P_n1)) ;   % According to 3GPP TR 138 901 V16.1.0 Chinese (7.5-8), compute power of the LOS ray
    P_n(1) = K_R ./ (K_R + 1);            % According to 3GPP TR 138 901 V16.1.0 Chinese (7.5-7), cmpute Power of the single LOS ray  
else
    P_n = P_n1 / sum(P_n1);                % According to 3GPP TR 138 901 V16.1.0 Chinese (7.5-6), compute power of the single LOS ray
end
end


function [scenariosPara] = fastFadingData(dataTable,idx,channelIdx,channelMod)

% Function: Get the data in the data table in 3GPP_TR_38_811 according to different scenario conditions
% Input values:
% dataTable: Parameters of the data table in 3GPP_TR_38_811 corresponding to fastFading
% idx: Location of the data in the data table
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% channelMod: This parameter is used to select the channel scenario, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model
% Return values:
% scenariosPara: Structure containing fastFading related parameters

scenariosPara = struct();                          % Depending on the scenario, get data from 3GPP TR 38.811 V15.4.0中Table 6.7.2
if(channelIdx == 1)
    scenariosPara.mu_lgDS = dataTable(2,idx);        % Row 2
    scenariosPara.sigma_lgDS = dataTable(3,idx);     % Row 3
    scenariosPara.mu_K = dataTable(12,idx);          % Row 12
    scenariosPara.sigma_K  = dataTable(13,idx);      % Row 13
    scenariosPara.r_tau = dataTable(35,idx);         % Row 35
    scenariosPara.zeta = 0;
    scenariosPara.N = 0;
    if (channelMod == 'C')
        scenariosPara.N = 2;
    else
        scenariosPara.N = 3;
    end
    scenariosPara.zeta = dataTable(44,idx);          % Row 44
else
    scenariosPara.mu_lgDS = dataTable(2,idx);        % Row 2
    scenariosPara.sigma_lgDS = dataTable(3,idx);     % Row 3
    scenariosPara.mu_K = 0;
    scenariosPara.sigma_K  = 0;
    scenariosPara.r_tau = dataTable(33,idx);         % Row 33
    scenariosPara.zeta = 0;                          % Row 42
    scenariosPara.N = 0;
    if (channelMod == 'A')
        scenariosPara.N = 3;
    else
        scenariosPara.N = 4;
    end
    scenariosPara.zeta = dataTable(42,idx);          % Row 42
end
end

function modeScenariosPara = computeScenariosPara(parameter,scenariosPara,channelIdx,position,channelMod)

% Function: Compute parameter for different CDL channel models
% Input values:
% parameter: Parameter of channel model
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% compScenariosPara: Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% channelMod: This parameter is used to select the channel scenario, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model
% position: The position and velocity of terminal and satellite
% mu_offestZOD: ZOD offest
% Return values:
% modeScenariosPara: Parameter of different CDL channel models


K = normrnd(scenariosPara.mu_K, scenariosPara.sigma_K, 1);         % Compute K-factor
% DS = 10^scenariosPara.mu_lgDS;
y = scenariosPara.mu_lgDS + scenariosPara.sigma_lgDS*randn;
DS = 10^y;
% DS = lognrnd(scenariosPara.mu_lgDS, scenariosPara.sigma_lgDS, 1);  % Compute DS

[tau_n,P_n] = clusterDelayPower(scenariosPara,K,DS,channelIdx);      %  Generate delay tau_nLos,power P_n

% mu_XPR = scenariosPara.mu_XPR;               % mu_XPR and sigma_XPR from 3GPP TR 38.811 V15.4.0中Table 6.7.2
% sigma_XPR = scenariosPara.sigma_XPR;
% Xnm = mu_XPR  + sigma_XPR * randn(scenariosPara.N, scenariosPara.M); % According to 3GPP TR 138 901 V16.1.0 Chinese (7.5-21), generate the cross polarization power ratios
% Knm = 10.^(Xnm ./ 10);                       % Generate the cross polarization power ratios

compScenariosPara = struct();                % Save data
compScenariosPara.DS = DS;
compScenariosPara.K = K;
compScenariosPara.tao_n = tau_n;
compScenariosPara.P_n = P_n;
% compScenariosPara.Knm = Knm;
modeScenariosPara = TDLModelSwitch(compScenariosPara,position,channelMod);

end

function [modeScenariosPara] = TDLModelSwitch(compScenariosPara,position,channelMod)

% Function: Generate different channel models: 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model
% Input values:
% compScenariosPara: Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters
% position: The position and velocity of terminal and satellite
% channelMod: This parameter is used to select the channel models, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model
% Return values:
% modeScenariosPara: Parameter of different CDL channel models
modeScenariosPara = struct();
modeScenariosPara.EOA_Mod = 0;
modeScenariosPara.K = 0;
modeScenariosPara.Knm = 0;
modeScenariosPara.tao_n = 0;
modeScenariosPara.P_n = 0;
switch channelMod
    case 'A'     % Support NTN-CDL-A
        table6_9_1_1 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_1.txt',4,6);              % Load data of 3GPP_TR_38_811_table6_9_1_1
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,position,table6_9_1_1,channelMod);  % Get Parameter of different CDL channel models
    case 'B'     % Support NTN-CDL-B
        table6_9_1_2 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_2.txt',5,6);              % Load data of 3GPP_TR_38_811_table6_9_1_2
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,position,table6_9_1_2,channelMod);
    case 'C'     % Support NTN-CDL-C
        table6_9_1_3 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_3.txt',4,6);              % Load data of 3GPP_TR_38_811_table6_9_1_3
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,position,table6_9_1_3,channelMod);
    case 'D'     % Support NTN-CDL-D
        table6_9_1_4 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_4.txt',5,6);              % Load data of 3GPP_TR_38_811_table6_9_1_4
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,position,table6_9_1_4,channelMod);
end
end
    function [modeScenariosPara] = CDLModelScenarios(compScenariosPara,position,dataTable,channelMod)
    
    % Function: Compute parameter of different CDL channel models
    % Input values:
    % compScenariosPara: Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters
    % position: The position and velocity of terminal and satellite
    % dataTable: Data of 3GPP_TR_38_811_table6_9_1
    % channelMod: This parameter is used to select the channel scenario, 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model
    % Return values:
    % modeScenariosPara: Parameter of different CDL channel models
    DS_Des = compScenariosPara.DS;
    dataRows = size(dataTable,1);                                                 % Rows of 3GPP_TR_38_811_table6_9_1_1
    TDL_param = struct();
    TDL_param.EOA_Des = position.losEOA;                                          % Desired EOA angle
    TDL_param.EOA_Mod = 50;                                                       % EOA angle of NTN-CDL-A
    tao_nMod = dataTable(1:(dataRows - 1),1);                                     % Delay of model
    TDL_param.P_nMod = dataTable(1:(dataRows - 1),2);                             % Power of model,dB -> linear value
    % XPR_Mod = dataTable(dataRows,5);                                              % XPR of model
    % K_n_mMod = 10^(XPR_Mod/10) .* ones((dataRows - 1),20);                        % Generate the cross polarization power ratios according to equation (7-70b) in 3GPP TR 138 901 V16.1.0
    % tao_nScal = tao_nMod * DS_Des;                                                % Delay of model
    if (channelMod == 'A' || channelMod == 'B')
        K_Mod = 0;
        P_nScal = 10.^((TDL_param.P_nMod) ./ 10);
    else
        K_Des = compScenariosPara.K;                                               % The model's K-factor
        % TDL_param.P_nMod = [sum(TDL_param.P_nMod(1:2)) TDL_param.P_nMod(3:end)];
        K_Mod = TDL_param.P_nMod(1) - 10 * log10(sum(10.^(TDL_param.P_nMod(2:end) ./ 10))); % The model's K-factor according to equation (7.7.6-2) in 3GPP TR 138 901 V16.1.0
        P_nScal = TDL_param.P_nMod;
        P_nScal(2:end) = TDL_param.P_nMod(2:end) - K_Des + K_Mod;
        tau_rms = calculateRMSDelaySpread(TDL_param,tao_nMod);
        tao_nMod = tao_nMod/tau_rms;
        % K1_dB = TDL_param.P_nMod(1)-TDL_param.P_nMod(2);
        P_nScal = [sum(10.^(P_nScal(1:2)/10)); P_nScal(3:end)];
        tao_nMod = tao_nMod([1 3:end]);
        P_nScal = 10 .^ (P_nScal ./ 10);
    end
    tao_nScal = tao_nMod * DS_Des; 
    modeScenariosPara = struct();
    modeScenariosPara.EOA_Mod = TDL_param.EOA_Mod;
    modeScenariosPara.K = K_Mod;
    % modeScenariosPara.Knm = K_n_mMod;
    modeScenariosPara.tao_n = tao_nScal;
    modeScenariosPara.P_n = P_nScal;
    end



function [matrix] = readCDLData(filename, rows, cols)
% Variable declaration and initialization
matrix = zeros(rows, cols);  % Initialize matrix with size rows x cols
currentRow = 1;  % Current row index

% Open the file
fid = fopen(filename, 'r');
% Read the file line by line
    while currentRow <= rows && ~feof(fid)
        line = fgetl(fid);  % Read a line
        if isempty(line)
            break;  % Exit loop if an empty line is encountered
        end
    
        % Manually parse each line of data
        dataRow = parseLine(line, cols);
        % Store data into the matrix
        matrix(currentRow, :) = dataRow;
        currentRow = currentRow + 1;
    end
fclose(fid);  % Close the file
end

% Helper function: Parse a line of data
function dataRow = parseLine(line, cols)
    dataRow = zeros(1, cols);  % Initialize data row
    idx = 1;  % Current character index
    for j = 1:cols
        % Skip all whitespace characters
        while idx <= length(line) && isSpace(line(idx))
            idx = idx + 1;
        end
    
        if idx > length(line)
            dataRow(j) = NaN;  % If exceeding string length, set to NaN
            return;
        end
    
        % Read continuous non-whitespace characters
        numStart = idx;
        while idx <= length(line) && ~isSpace(line(idx))
            idx = idx + 1;
        end
        numEnd = idx - 1;
    
        % Extract numeric string
        numStr = line(numStart:numEnd);
    
        % Convert string to number, ensuring the result is a real number
        dataRow(j) = real(str2double(numStr));
    end

    % Helper function: Check if a character is a whitespace
    function isSpace = isSpace(c)
    % Directly compare ASCII values to avoid escape character issues
    isSpace = (c == ' ') || (c == char(9)) || (c == char(10)) || (c == char(13));
    end
end

function r = myrand(n, seed)
% MYRAND Generate uniformly distributed random numbers in [0, 1]
%   r = myrand(n) returns a vector of n elements with uniform distribution in [0, 1].
%   r = myrand(n, seed) generates random numbers using a specified seed.
%
% Parameters:
%   n: Number of random numbers to generate (scalar)
%   seed: Seed for the random number generator (optional; default uses current time)

% Set default values for N and seed
if nargin < 1
    n = 1; % Default to generating 1 random number
end
if nargin < 2
    % seed = floor(now*1e6); % Use current time as seed if not provided
    seed = sum(clock) * 1e6;
end

% Linear Congruential Generator parameters
M = 2^31 - 1; % Modulus
A = 7^5;      % Multiplier
C = 0;        % Increment

% Initialize the random number sequence
r = zeros(1, n); % Preallocate the result vector
current = seed;  % Current state of the generator

for i = 1:n
    next = mod(A * current + C, M); % Generate next pseudo-random number
    current = next;                 % Update current state
    r(i) = current / M;             % Normalize to [0, 1] interval
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

function tau_rms = calculateRMSDelaySpread(TDL_param,tao_nMod)

    P = 10.^(TDL_param.P_nMod/10);
    m1 = sum(P.*tao_nMod)/sum(P);
    m2 = sum(P.*tao_nMod.^2)/sum(P);
    tau_rms = sqrt(m2 - m1^2);

end




