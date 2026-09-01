function [H_t,tao_n,P_n,dopplerFreqCenter] = CDLModel(parameter,position)

% Function: Compute channel coefficient by section 6.9.1 of 3GPP TR 38.811 V15.4.0 (2020-09) for different CDL channel models:
% 'A': NTN-CDL-A model, 'B': NTN-CDL-B model, 'C': NTN-CDL-C model, 'D': NTN-CDL-D model  
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
derad = pi/180;
Re = 6371e3;                                         % Earth's radius 

[d2D, d3D] = computeDistances(position);
position.d2D = d2D;                       
position.d3D = d3D;

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
hr = parameter.hr;
losEOA = position.losEOA;
if(fc>=1e9)                                % Ensure that the frequency unit is GHz
    fc = fc / 1e9;
else
    fc = fc;
end
if(fc <=  4 && fc >= 2)
    bandIdx = 1;                           % This parameter is used to select the frequency band scenario, 1: S-band(2-4 GHz band), 2: Ka-band(26.5 to 40GHz band)
else
    bandIdx = 2;
end
diffs = abs(table6_7_2_1a(1,:) - losEOA);  % Calculate the absolute difference between the target elevation angle and each elevation angle in the data table
[~, idx] = min(diffs);                     % Find the index corresponding to the minimum difference, determine the row number taken from the data table, idx
H_Martix = complex([]);
H_Martix_t = complex([]);
tao_n = [];
P_n = [];
dopplerFreqCenter = 0;
tLength = 0;
clussterNum = 0;
switch sceneIdx
    case 1                                 % Support scenario 1:  Dense urban scenario
        if (channelMod == 'A' || channelMod == 'B')
            channelIdx = 2;
        else
            channelIdx = 1;
        end
        if(bandIdx == 1)                   % Support S-band
            if(channelIdx == 1)            % Support LOS channel
                mu_offestZOD = 0;          % Based table 7.5-7 of 3GPP TR 138 901 V16.1.0, get ZOD offest in  LOS channel
                [scenariosPara] = fastFadingData(table6_7_2_1a,idx,channelIdx,channelMod);                                        % Get table data of 3GPP_TR_38_811 Section 6.7.2 in LOS channel
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);  % Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters in LOS channel
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute channel coefficient in LOS channel
            else                                                                                                                  % Support NLOS channel
                mu_offestZOD = -10^(-1.5 * log10(max(10,position.d2D)) + 3.3);                                                             % Based table 7.5-7 of 3GPP TR 138 901 V16.1.0, get ZOD offest in NLOS channel
                table6_7_2_2a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_2a.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_2a,idx,channelIdx,channelMod);                                        % Get table data of 3GPP_TR_38_811 Section 6.7.2 in NLOS channel
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);  % Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters in NLOS channel
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute channel coefficient in NLOS channel
            end
        else                                                                                                                      % Support Ka-band
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_1b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_1b.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_1b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute  channel coefficient
            else
                mu_offestZOD = -10^(-1.5 * log10(max(10,position.d2D)) + 3.3);
                table6_7_2_2b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_2b.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_2b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute  channel coefficient
            end
        end
    case 2       % Support scenario 2: Urban scenario
        if (channelMod == 'A' || channelMod == 'B')
            channelIdx = 2;
        else
            channelIdx = 1;
        end
        if(bandIdx == 1)
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_3a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_3a.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_3a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute  channel coefficient
            else
                mu_offestZOD = (7.66 * log10(fc) - 5.96) - (10^((0.208 * log10(fc) - 0.782) * log10(max(25,position.d2D)) + (-0.13 * log10(fc) + 2.03) - 0.07 * (hr - 1.5)));
                table6_7_2_4a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_4a.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_4a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);  % Compute sum of Sub-cluster channel coefficient
            end
        else
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_3b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_3b.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_3b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);   % Compute sum of Sub-cluster channel coefficient
            else
                mu_offestZOD = (7.66 * log10(fc) - 5.96) - (10^((0.208 * log10(fc) - 0.782) * log10(max(25,position.d2D)) + (-0.13 * log10(fc) + 2.03) - 0.07 * (hr - 1.5)));
                table6_7_2_4b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_4b.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_4b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);   % Compute sum of Sub-cluster channel coefficient
            end
        end
    case 3      % Support scenario 3: Suburban scenarios
        if (channelMod == 'A' || channelMod == 'B')
            channelIdx = 2;
        else
            channelIdx = 1;
        end
        if(bandIdx == 1)
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_5a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_5a.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_5a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            else
                mu_offestZOD = (atan((35 - 3.5) / position.d2D) / derad) - (atan((35 - 1.5) / position.d2D) / derad);
                table6_7_2_6a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_6a.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_6a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            end
        else
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_5b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_5b.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_5b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            else
                mu_offestZOD = (atan((35 - 3.5) / position.d2D) / derad) - (atan((35 - 1.5) / position.d2D) / derad);
                table6_7_2_6b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_6b.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_6b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            end
        end
    case 4      % Support scenario 4: Rural scenarios
        if (channelMod == 'A' || channelMod == 'B')
            channelIdx = 2;
        else
            channelIdx = 1;
        end
        if(bandIdx == 1)
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_7a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_7a.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_7a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            else
                mu_offestZOD = (atan((35 - 3.5) / position.d2D) / derad) - (atan((35 - 1.5) / position.d2D) / derad);
                table6_7_2_8a = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_8a.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_8a,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute  channel coefficient
            end
        else
            if(channelIdx == 1)
                mu_offestZOD = 0;
                table6_7_2_7b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_7b.txt',51,9);
                [scenariosPara] = fastFadingData(table6_7_2_7b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            else
                mu_offestZOD = (atan((35 - 3.5) / position.d2D) / derad) - (atan((35 - 1.5) / position.d2D) / derad);
                table6_7_2_8b = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_8b.txt',49,9);
                [scenariosPara] = fastFadingData(table6_7_2_8b,idx,channelIdx,channelMod);
                [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD);
                tLength = parameter.N_Ts;
                clussterNum = scenariosPara.N;
                H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
                H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,tLength));
                [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction (scenariosPara,modeScenariosPara,parameter,position,channelIdx);    % Compute channel coefficient
            end
        end
end
% H = complex(zeros(clussterNum,1));
% H_t = complex(zeros(clussterNum,tLength));
% 
% for i1 = 1:1:clussterNum
%     H(i1,1) = H_Martix(:,:,i1);              % Each row represents a different cluster
% end
% 
% 
% for i2 = 1:1:clussterNum
%     for i3 = 1:1:tLength
%         H_t(i2,i3) = H_Martix_t(:,:,i2,i3);    % Each row represents a different cluster, each column represents a different time
%     end
% end

% H_t(:,:) = H_Martix_t(1,1,:,1,:);    % Each row represents a different cluster, each column represents a different time  2026-7-7
H_t = H_Martix_t;  %26-7-13

%% 下面程序是为了去除固定的多普勒频率值，达到降低信道采样率的目的
% t = linspace(0,parameter.T,parameter.N_Ts);  % Sampling Time series
% numPath = size(H_t,1); %径数
% tscale = ones(numPath,1)*t; % 将采样时间序列对应扩充到每径的所有采样点
% H_t = H_t.*exp(-sqrt(-1)*2*pi*dopplerFreqCenter*tscale);
% H_t = H_t.*exp(-sqrt(-1)*2*pi*dopplerFreqCenter*(1/parameter.Fs)*tscale);
end


function [H_Martix,H_Martix_t,tao_n,P_n, dopplerFreqCenter] = scenariosFunction(scenariosPara,modeScenariosPara,parameter,position,channelIdx)

% Function:In different scenarios, compute channel coefficients of clusters
% Input values:
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% modeScenariosPara: Parameter of different CDL channel models
% parameter: Parameter of channel model
% position: The position and velocity of terminal and satellite
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% Return values:
% H_Martix: Channel coefficient of clusters, H_Martix_t: Channel coefficient clusters to time t
% tao_n: Delay of clusters
% H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
% length_t = parameter.N_Ts;
% H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,length_t));
dopplerFreqCenter = 0;
if(channelIdx == 1)
    [H_Los,HLos_t] = LosCoefficient(modeScenariosPara,parameter,1,1,position);
    tao_n = (modeScenariosPara.tao_n);           % Delay of clusters
    P_n = (modeScenariosPara.P_n);               % Power of clusters
    losClusters = [1];                           % LOS clusters index
    lenLos = length(losClusters) + 1;            % End index of LOS clusters
    if(scenariosPara.N == (lenLos - 1))           % Only have one LOS clusters
        H_Martix = H_Los;
        H_Martix_t =  HLos_t;
    else
        [H_Martix,H_Martix_t, dopplerFreqCenter] = computeLosCoefficient(H_Los,HLos_t,lenLos,scenariosPara,modeScenariosPara,parameter,position); % Compute channel coefficient based equation(6.8-1a) of 3GPP TR 38.811 V15.4.0 (2020-09)
    end
else
    [H_Martix,H_Martix_t, dopplerFreqCenter] = computeNLosCoefficient(scenariosPara,modeScenariosPara,parameter,position); % Compute channel coefficient based equation(6.8-1a) of 3GPP TR 38.811 V15.4.0 (2020-09)
    tao_n = [modeScenariosPara.tao_n];            % Delay of clusters
    P_n = (modeScenariosPara.P_n);                % Power of clusters
end
end



function [H_Martix,H_Martix_t, dopplerFreqCenter] = computeLosCoefficient(H_Martix1,H_Martix_t1,len,scenariosPara,modeScenariosPara,parameter,position)

% Function: Compute channel coefficient based equation(7.5-22) of 3GPP TR 38.901  V16.1.0 (2020-11)
% Input values:
% H_Martix1: Channel coefficient of clusters (1)/(1~2) in LOS/NLOS channel
% H_Martix_t1:Channel coefficient of clusters (1)/(1~2) in LOS/NLOS channel to time t
% len: The number of los clusters/strongest clusters
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% modeScenariosPara: Parameter of different CDL channel models
% parameter: Parameter of channel model
% position: The position and velocity of terminal and satellite
% Return values:
% H_Martix: Channel coefficient of clusters, H_Martix_t: Channel coefficient of clusters to time t
% H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
length_t = parameter.N_Ts;
% H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,length_t));
% H_Martix(:,:,1) = H_Martix1(:,:,1);
% H_Martix_t(:,:,1,:) = H_Martix_t1(:,:,1,:);     % Channel coefficient of clusters 1 in LOS channel to time t

%2026-7-14
H_Martix = complex(zeros(scenariosPara.N,parameter.NumAntennaPattern));    
H_Martix_t = complex(zeros(scenariosPara.N,length_t,parameter.NumAntennaPattern));

H_Martix1 = permute(H_Martix1,[3,5,2,4,1]);
H_Martix(1,:,:) = H_Martix1;
% H_Martix
H_Martix_t1 = permute(H_Martix_t1,[3,2,5,4,1]);
H_Martix_t(1,:,:) = H_Martix_t1;
comPara = struct();                             % Get N-len parameters
comPara.N = scenariosPara.N - len + 1;
comPara.M = scenariosPara.M;
comPara.K = modeScenariosPara.K(len:end);
comPara.P_n = modeScenariosPara.P_n(len:end);
comPara.tao_n = modeScenariosPara.tao_n(len:end);
comPara.phi_n_m_AOA = modeScenariosPara.phi_n_m_AOA(len:end,:);
comPara.phi_n_m_AOD = modeScenariosPara.phi_n_m_AOD(len:end,:);
comPara.theta_n_m_ZOA = modeScenariosPara.theta_n_m_ZOA(len:end,:);
comPara.theta_n_m_ZOD = modeScenariosPara.theta_n_m_ZOD(len:end,:);
comPara.Knm = modeScenariosPara.Knm(len:end,:);

% 计算 NLOS 部分的信道系数（这里 NlosCoefficient 返回的 H_usnmNlos 尺寸为 [N_r, N_t, comPara.N, scenariosPara.M]，
% H_usnmNlos_t 尺寸为 [N_r, N_t, comPara.N, scenariosPara.M, length_t]）
[H_usnmNlos, H_usnmNlos_t, dopplerFreqCenter] = NlosCoefficient(parameter, comPara, position);

% 对 NLOS 信道系数沿第4维求和，避免内层 for 循环
% 得到的尺寸为 [N_r, N_t, comPara.N]，然后赋值到 H_Martix 对应位置（索引为 len 到 scenariosPara.N）
H_Martix2 = sum(H_usnmNlos, 4);
H_Martix(len:end,:,:) = permute(H_Martix2,[3,5,2,4,1]);    %26-7-13

% 同样，对时变信道系数进行向量化求和
% H_usnmNlos_t 尺寸为 [N_r, N_t, comPara.N, scenariosPara.M, length_t]
% 沿第4维求和后得到 [N_r, N_t, comPara.N, length_t]，赋值到 H_Martix_t 对应位置
H_Martix_t3 = sum(H_usnmNlos_t, 4);
H_Martix_t (len:end,:,:)= permute(H_Martix_t3,[3,2,5,4,1]);  %26-7-13

end


function [H_Martix,H_Martix_t, dopplerFreqCenter] = computeNLosCoefficient(scenariosPara,modeScenariosPara,parameter,position)

% Function: Compute channel coefficient based equation(7.5-22) of 3GPP TR 38.901 V16.1.0 (2020-11)
% Input values:
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% modeScenariosPara: Parameter of different CDL channel models
% parameter: Parameter of channel model
% position: The position and velocity of terminal and satellite
% Return values:
% H_Martix: Channel coefficient of clusters, H_Martix_t: Channel coefficient of clusters to time t
% length_t = parameter.N_Ts;
% H_Martix = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N));
% H_Martix_t = complex(zeros(parameter.N_r,parameter.N_t,scenariosPara.N,length_t));
comPara = struct();                               %  Get parameters
comPara.N = scenariosPara.N;
comPara.M = scenariosPara.M;
comPara.K = modeScenariosPara.K;
comPara.P_n = modeScenariosPara.P_n;
comPara.tao_n = modeScenariosPara.tao_n;
comPara.phi_n_m_AOA = modeScenariosPara.phi_n_m_AOA;
comPara.phi_n_m_AOD = modeScenariosPara.phi_n_m_AOD;
comPara.theta_n_m_ZOA = modeScenariosPara.theta_n_m_ZOA;
comPara.theta_n_m_ZOD = modeScenariosPara.theta_n_m_ZOD;
comPara.Knm = modeScenariosPara.Knm;

% 调用 NlosCoefficient 得到的通道系数
[H_usnmNlos, H_usnmNlos_t, dopplerFreqCenter] = NlosCoefficient(parameter, comPara, position);

% 对于 H_Martix：沿第4维（M）求和，尺寸从 [N_r, N_t, N, M] 变为 [N_r, N_t, N]
H_Martix = sum(H_usnmNlos, 4);
% H_Martix = reshape(H_Martix,scenariosPara.N,[],parameter.NumAntennaPattern);
H_Martix = permute(H_Martix,[3,2,5,1,4]);    %26-7-13
% 对于 H_Martix_t：沿第4维求和，尺寸从 [N_r, N_t, N, M, length_t] 变为 [N_r, N_t, N, length_t]
H_Martix_t = sum(H_usnmNlos_t, 4);
% H_Martix_t = reshape(H_Martix_t,scenariosPara.N,parameter.Fs,parameter.NumAntennaPattern);

H_Martix_t = permute(H_Martix_t,[3,2,5,4,1]);  %26-7-13
end


function [modeScenariosPara,AS,mu,sigma] = computeScenariosPara(parameter,scenariosPara,channelIdx,channelMod,position,mu_offestZOD)

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

table6_7_2_1aa = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_1aa.txt',2,13);     % Get data of channel model
table6_7_2_1ab = readCDLData('external_data/3GPP_TR_38_811_data/table6_7_2_1ab.txt',2,10);
losAOA = position.losAOA;
losAOD = position.losAOD;
losZOA = position.losZOA;
losZOD = position.losZOD;
K = normrnd(scenariosPara.mu_K, scenariosPara.sigma_K, 1);         % Compute K-factor
% DS = 10^scenariosPara.mu_lgDS;
y = scenariosPara.mu_lgDS + scenariosPara.sigma_lgDS*randn;
DS = 10^y;
% DS = lognrnd(scenariosPara.mu_lgDS, scenariosPara.sigma_lgDS, 1);  % Compute DS

mu_lgDS = scenariosPara.mu_lgDS;
sigma_lgDS = scenariosPara.sigma_lgDS;


ASD = lognrnd(scenariosPara.mu_lgASD, scenariosPara.sigma_lgASD, 1);% Compute ASD
ASD_mu = scenariosPara.mu_lgASD;
ASD_sigma = scenariosPara.sigma_lgASD;

ASA = lognrnd(scenariosPara.mu_lgASA, scenariosPara.sigma_lgASA, 1);% Compute ASA
ASA_mu = scenariosPara.mu_lgASA;
ASA_sigma = scenariosPara.sigma_lgASA;

ZSD = lognrnd(scenariosPara.mu_lgZSD, scenariosPara.sigma_lgZSD, 1);% Compute ZSD
ZSD_mu = scenariosPara.mu_lgZSD;
ZSD_sigma = scenariosPara.sigma_lgZSD;

ZSA = lognrnd(scenariosPara.mu_lgZSA, scenariosPara.sigma_lgZSA, 1);% Compute ZSA
ZSA_mu = scenariosPara.mu_lgZSA;
ZSA_sigma = scenariosPara.sigma_lgZSA;

AS = [ASD,ASA,ZSD,ZSA,DS];
mu = [ASD_mu,ASA_mu,ZSD_mu,ZSA_mu,mu_lgDS];
sigma = [ASD_sigma,ASA_sigma,ZSD_sigma,ZSA_sigma,sigma_lgDS];

[tau_n,P_n] = clusterDelayPower(scenariosPara,K,DS,channelIdx);      %  Generate delay tau_nLos,power P_n
idxFai= find(table6_7_2_1aa(1,:) == scenariosPara.N);                % According to Table 6.7.2-1aa in 3GPP TR 38.811 V15.4.0, generate Scaling factors for AOA, AOD
idxTheta = find(table6_7_2_1ab(1,:) == scenariosPara.N);             % According to Table 6.7.2-1ab in 3GPP TR 38.811 V15.4.0, generate Scaling factors for ZOA, ZOD
if(channelIdx == 1)
    C_phi_NLOS = table6_7_2_1aa(2,idxFai);
    C_phi = C_phi_NLOS.*(1.1035-0.028*K-0.002*K.^2+0.0001*K.^3);
    C_thetaNlos = table6_7_2_1ab(2,idxTheta);
    C_theta = C_thetaNlos.*(1.3086+0.0339*K-0.0077*K.^2+0.0002*K.^3);
else
    C_phi = table6_7_2_1aa(2,idxFai);
    C_theta = table6_7_2_1ab(2,idxTheta);
end
c_ASA = scenariosPara.c_ASA;
[phi_n_m_AOA] = azimuthAngleofClusters(scenariosPara,ASA,c_ASA,P_n,C_phi,losAOA,channelIdx);                   %  Generate AOA
c_ASD = scenariosPara.c_ASD;
[phi_n_m_AOD] = azimuthAngleofClusters(scenariosPara,ASD,c_ASD,P_n,C_phi,losAOD,channelIdx);                   %  Generate AOD
c_ZSA = scenariosPara.c_ZSA;
[theta_n_m_ZOA] = zenithAngleofClusters(scenariosPara,ZSA,c_ZSA,P_n,C_theta,mu_offestZOD,losZOA,1,channelIdx); %  Generate ZOA
c_ZSD = 0;
[theta_n_m_ZOD] = zenithAngleofClusters(scenariosPara,ZSD,c_ZSD,P_n,C_theta,mu_offestZOD,losZOD,2,channelIdx); %  Generate ZOD
phi_n_m_AOA = shuffleMatrix(phi_n_m_AOA);    % Coupling of rays within a cluster for both azimuth and elevation
phi_n_m_AOD = shuffleMatrix(phi_n_m_AOD);
theta_n_m_ZOA = shuffleMatrix(theta_n_m_ZOA);
theta_n_m_ZOD = shuffleMatrix(theta_n_m_ZOD);
mu_XPR = scenariosPara.mu_XPR;               % mu_XPR and sigma_XPR from 3GPP TR 38.811 V15.4.0中Table 6.7.2
sigma_XPR = scenariosPara.sigma_XPR;
Xnm = mu_XPR  + sigma_XPR * randn(scenariosPara.N, scenariosPara.M); % According to 3GPP TR 138 901 V16.1.0 Chinese (7.5-21), generate the cross polarization power ratios
Knm = 10.^(Xnm ./ 10);                       % Generate the cross polarization power ratios
compScenariosPara = struct();                % Save data
compScenariosPara.DS = DS;
compScenariosPara.K = K;
compScenariosPara.tao_n = tau_n;
compScenariosPara.P_n = P_n;
compScenariosPara.phi_n_m_AOA = phi_n_m_AOA;
compScenariosPara.phi_n_m_AOD = phi_n_m_AOD;
compScenariosPara.theta_n_m_ZOA = theta_n_m_ZOA;
compScenariosPara.theta_n_m_ZOD = theta_n_m_ZOD;
compScenariosPara.Knm = Knm;

compScenariosPara.ASA = ASA;
modeScenariosPara = struct();
[modeScenariosPara] = CDLModelSwitch(compScenariosPara,scenariosPara,position,channelMod); % Compute parameter of NTN-CDL-A/B/C/D
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
    scenariosPara.mu_lgASD = dataTable(4,idx);       % Row 4
    scenariosPara.sigma_lgASD = dataTable(5,idx);    % Row 5
    scenariosPara.mu_lgASA= dataTable(6,idx);        % Row 6
    scenariosPara.sigma_lgASA = dataTable(7,idx);    % Row 7
    scenariosPara.mu_lgZSA= dataTable(8,idx);        % Row 8
    scenariosPara.sigma_lgZSA = dataTable(9,idx);    % Row 9
    scenariosPara.mu_lgZSD = dataTable(10,idx);      % Row 10
    scenariosPara.sigma_lgZSD = dataTable(11,idx);   % Row 11
    scenariosPara.mu_K = dataTable(12,idx);          % Row 12
    scenariosPara.sigma_K  = dataTable(13,idx);      % Row 13
    scenariosPara.KtoK = 1;
    scenariosPara.KtoSF = dataTable(23,idx);         % Row 23
    scenariosPara.KtoDS = dataTable(22,idx);         % Row 22
    scenariosPara.KtoASD = dataTable(20,idx);        % Row 20
    scenariosPara.KtoASA = dataTable(21,idx);        % Row 21
    scenariosPara.KtoZSD = dataTable(26,idx);        % Row 26
    scenariosPara.KtoZSA = dataTable(27,idx);        % Row 27
    scenariosPara.SFtoK = dataTable(23,idx);         % Row 23
    scenariosPara.SFtoSF = 1;
    scenariosPara.SFtoDS = dataTable(18,idx);        % Row 18
    scenariosPara.SFtoASD = dataTable(17,idx);       % Row 17
    scenariosPara.SFtoASA = dataTable(16,idx);       % Row 16
    scenariosPara.SFtoZSD = dataTable(24,idx);       % Row 24
    scenariosPara.SFtoZSA = dataTable(25,idx);       % Row 25
    scenariosPara.DStoK = dataTable(22,idx);         % Row 22
    scenariosPara.DStoSF = dataTable(18,idx);        % Row 18
    scenariosPara.DStoDS = 1;
    scenariosPara.DStoASD = dataTable(14,idx);       % Row 14
    scenariosPara.DStoASA = dataTable(15,idx);       % Row 15
    scenariosPara.DStoZSD = dataTable(28,idx);       % Row 28
    scenariosPara.DStoZSA = dataTable(29,idx);       % Row 29
    scenariosPara.ASDtoK = dataTable(20,idx);        % Row 20
    scenariosPara.ASDtoSF = dataTable(17,idx);       % Row 17
    scenariosPara.ASDtoDS =  dataTable(14,idx);      % Row 14
    scenariosPara.ASDtoASD = 1;
    scenariosPara.ASDtoASA = dataTable(19,idx);      % Row 19
    scenariosPara.ASDtoZSD = dataTable(30,idx);      % Row 30
    scenariosPara.ASDtoZSA = dataTable(31,idx);      % Row 31
    scenariosPara.ASAtoK = dataTable(21,idx);        % Row 21
    scenariosPara.ASAtoSF = dataTable(16,idx);       % Row 16
    scenariosPara.ASAtoDS =  dataTable(15,idx);      % Row 15
    scenariosPara.ASAtoASD = dataTable(19,idx);      % Row 19
    scenariosPara.ASAtoASA = 1;
    scenariosPara.ASAtoZSD = dataTable(32,idx);      % Row 32
    scenariosPara.ASAtoZSA = dataTable(33,idx);      % Row 33
    scenariosPara.ZSDtoK = dataTable(26,idx);        % Row 26
    scenariosPara.ZSDtoSF = dataTable(24,idx);       % Row 24
    scenariosPara.ZSDtoDS =  dataTable(28,idx);      % Row 28
    scenariosPara.ZSDtoASD = dataTable(30,idx);      % Row 30
    scenariosPara.ZSDtoASA = dataTable(32,idx);      % Row 32
    scenariosPara.ZSDtoZSD = 1;
    scenariosPara.ZSDtoZSA = dataTable(34,idx);      % Row 34
    scenariosPara.ZSAtoK = dataTable(27,idx);        % Row 27
    scenariosPara.ZSAtoSF = dataTable(25,idx);       % Row 25
    scenariosPara.ZSAtoDS =  dataTable(29,idx);      % Row 29
    scenariosPara.ZSAtoASD = dataTable(31,idx);      % Row 31
    scenariosPara.ZSAtoASA = dataTable(33,idx);      % Row 33
    scenariosPara.ZSAtoZSD = dataTable(34,idx);      % Row 34
    scenariosPara.ZSAtoZSA = 1;
    scenariosPara.r_tau = dataTable(35,idx);         % Row 35
    scenariosPara.mu_XPR =dataTable(36,idx);         % Row 36
    scenariosPara.sigma_XPR = dataTable(37,idx);     % Row 37
    scenariosPara.c_ASD = 0;                         % Row 39
    scenariosPara.c_ASA = 0;                         % Row 40
    scenariosPara.c_ZSA = 0;                         % Row 41
    scenariosPara.zeta = 0;
    scenariosPara.N = 0;
    if (channelMod == 'C')
        scenariosPara.N = 3;
    else
        scenariosPara.N = 4;
    end
    scenariosPara.M = dataTable(39,idx);             % Row 39
    scenariosPara.c_DS = dataTable(40,idx);          % Row 40
    if isnan(scenariosPara.c_DS)
        scenariosPara.c_DS = 3.91;
    end
    scenariosPara.c_ASD = dataTable(41,idx);         % Row 41
    scenariosPara.c_ASA = dataTable(42,idx);         % Row 42
    scenariosPara.c_ZSA = dataTable(43,idx);         % Row 43
    scenariosPara.zeta = dataTable(44,idx);          % Row 44
else
    scenariosPara.mu_lgDS = dataTable(2,idx);        % Row 2
    scenariosPara.sigma_lgDS = dataTable(3,idx);     % Row 3
    scenariosPara.mu_lgASD = dataTable(4,idx);       % Row 4
    scenariosPara.sigma_lgASD = dataTable(5,idx);    % Row 5
    scenariosPara.mu_lgASA= dataTable(6,idx);        % Row 6
    scenariosPara.sigma_lgASA = dataTable(7,idx);    % Row 7
    scenariosPara.mu_lgZSA= dataTable(8,idx);        % Row 8
    scenariosPara.sigma_lgZSA = dataTable(9,idx);    % Row 9
    scenariosPara.mu_lgZSD = dataTable(10,idx);      % Row 10
    scenariosPara.sigma_lgZSD = dataTable(11,idx);   % Row 11
    scenariosPara.mu_K = 0;
    scenariosPara.sigma_K  = 0;
    scenariosPara.KtoK = 1;
    scenariosPara.KtoSF = dataTable(21,idx);         % Row 21
    scenariosPara.KtoDS = dataTable(20,idx);         % Row 20
    scenariosPara.KtoASD = dataTable(18,idx);        % Row 18
    scenariosPara.KtoASA = dataTable(19,idx);        % Row 19
    scenariosPara.KtoZSD = dataTable(24,idx);        % Row 24
    scenariosPara.KtoZSA = dataTable(25,idx);        % Row 25
    scenariosPara.SFtoK = dataTable(21,idx);         % Row 21
    scenariosPara.SFtoSF = 1;
    scenariosPara.SFtoDS = dataTable(16,idx);        % Row 16
    scenariosPara.SFtoASD = dataTable(15,idx);       % Row 15
    scenariosPara.SFtoASA = dataTable(14,idx);       % Row 14
    scenariosPara.SFtoZSD = dataTable(22,idx);       % Row 22
    scenariosPara.SFtoZSA = dataTable(23,idx);       % Row 23
    scenariosPara.DStoK = dataTable(20,idx);         % Row 20
    scenariosPara.DStoSF = dataTable(16,idx);        % Row 16
    scenariosPara.DStoDS = 1;
    scenariosPara.DStoASD = dataTable(12,idx);       % Row 12
    scenariosPara.DStoASA = dataTable(13,idx);       % Row 13
    scenariosPara.DStoZSD = dataTable(26,idx);       % Row 26
    scenariosPara.DStoZSA = dataTable(27,idx);       % Row 27
    scenariosPara.ASDtoK = dataTable(18,idx);        % Row 18
    scenariosPara.ASDtoSF = dataTable(15,idx);       % Row 15
    scenariosPara.ASDtoDS =  dataTable(12,idx);      % Row 12
    scenariosPara.ASDtoASD = 1;
    scenariosPara.ASDtoASA = dataTable(17,idx);      % Row 17
    scenariosPara.ASDtoZSD = dataTable(28,idx);      % Row 28
    scenariosPara.ASDtoZSA = dataTable(29,idx);      % Row 29
    scenariosPara.ASAtoK = dataTable(19,idx);        % Row 19
    scenariosPara.ASAtoSF = dataTable(14,idx);       % Row 14
    scenariosPara.ASAtoDS =  dataTable(13,idx);      % Row 13
    scenariosPara.ASAtoASD = dataTable(17,idx);      % Row 17
    scenariosPara.ASAtoASA = 1;
    scenariosPara.ASAtoZSD = dataTable(30,idx);      % Row 30
    scenariosPara.ASAtoZSA = dataTable(31,idx);      % Row 31
    scenariosPara.ZSDtoK = dataTable(24,idx);        % Row 24
    scenariosPara.ZSDtoSF = dataTable(22,idx);       % Row 22
    scenariosPara.ZSDtoDS =  dataTable(26,idx);      % Row 26
    scenariosPara.ZSDtoASD = dataTable(28,idx);      % Row 28
    scenariosPara.ZSDtoASA = dataTable(30,idx);      % Row 30
    scenariosPara.ZSDtoZSD = 1;
    scenariosPara.ZSDtoZSA = dataTable(32,idx);      % Row 32
    scenariosPara.ZSAtoK = dataTable(25,idx);        % Row 25
    scenariosPara.ZSAtoSF = dataTable(23,idx);       % Row 23
    scenariosPara.ZSAtoDS =  dataTable(27,idx);      % Row 27
    scenariosPara.ZSAtoASD = dataTable(29,idx);      % Row 29
    scenariosPara.ZSAtoASA = dataTable(31,idx);      % Row 31
    scenariosPara.ZSAtoZSD = dataTable(32,idx);      % Row 32
    scenariosPara.ZSAtoZSA = 1;
    scenariosPara.r_tau = dataTable(33,idx);         % Row 33
    scenariosPara.mu_XPR =dataTable(34,idx);         % Row 34
    scenariosPara.sigma_XPR = dataTable(35,idx);     % Row 35
    scenariosPara.c_ASD = 0;                         % Row 39
    scenariosPara.c_ASA = 0;                         % Row 40
    scenariosPara.c_ZSA = 0;                         % Row 41
    scenariosPara.zeta = 0;                          % Row 42
    scenariosPara.N = 0;
    if (channelMod == 'A')
        scenariosPara.N = 3;
    else
        scenariosPara.N = 4;
    end
    scenariosPara.M = dataTable(37,idx);             % Row 37
    scenariosPara.c_DS = dataTable(38,idx);          % Row 38
    if isnan(scenariosPara.c_DS)
        scenariosPara.c_DS = 3.91;
    end
    scenariosPara.c_ASD = dataTable(39,idx);         % Row 39
    scenariosPara.c_ASA = dataTable(40,idx);         % Row 40
    scenariosPara.c_ZSA = dataTable(41,idx);         % Row 41
    scenariosPara.zeta = dataTable(42,idx);          % Row 42
end
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
if(channelIdx == 2)
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


function [phi_n_m_Azimuth] = azimuthAngleofClusters(scenariosPara,AS,c_AS,P_n,C_phi,losAzimuth,channelIdx)

% Function: Compute the AOD/AOA of a cluster
% Input values:
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% AS: ASD/ASA distribution
% C_AS: C_ASA/C_ASD is the cluster root mean square difference of AOD/AOA
% P_n: Cluster ray power
% C_phi: Scaling factor generated by ZOA, ZOD
% losAzimuth: Szimuth of the LOS
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% Return values:
% phi_n_m_Azimuth: AOD/AOA of clusters

N = scenariosPara.N;                 % Get input parameters
M = scenariosPara.M;
phi_n_Azimuth1 = (2*(AS ./ 1.4).*sqrt(-log(P_n ./ max(P_n)))) ./ C_phi;  % Compute AOD/AOA according to equation (7.5-9) in 3GPP TR 138 901 V16.1.0
Xn1 = 2 * (rand(N) >= 0.5) - 1;   % Maps each element to {1, -1}
Yn = ((AS ./ 7).^2) .* randn(1, N);  % Generate a random number matrix of N(0, (ASA./7). ^2) the matrix of random numbers
if(channelIdx == 1)
    phi_n_Azimuth = (Xn1 .* phi_n_Azimuth1 + Yn) - (Xn1(1) .* phi_n_Azimuth1(1) + Yn(1) - losAzimuth);  % Compute AOD/AOA for loscase according to equation (7.5-12) in 3GPP TR 138 901 V16.1.0
else
    phi_n_Azimuth = Xn1 .* phi_n_Azimuth1 + Yn + losAzimuth;              % Compute AOD/AOA according to equation (7.5-11) in 3GPP TR 138 901 V16.1.0
end
phi_n_m_Azimuth = zeros(N,M);
for nIndex = 1:N
    alpha0 = [0.0447 -0.0447 0.1413 -0.1413 0.2492 -0.2492 0.3715 -0.3715 0.5129 -0.5129 0.6797 -0.6797 0.8844 -0.8844 1.1481 -1.1481 1.5195 -1.5195 2.1551 -2.1551];
    alpha = alpha0(1:M);
    phi_n_m_Azimuth(nIndex,:) = phi_n_Azimuth(nIndex) .* ones(1,M) + c_AS * alpha;  % Compute AOD/AOA according to equation (7.5-13) in 3GPP TR 138 901 V16.1.0 add offset angles
end
end


function [theta_n_m_Zenith] = zenithAngleofClusters(scenariosPara,ZS,c_ZS,P_n,C_theta,mu_offestZOD,losZenith,zenithAngleKind,channelIdx)

% Function: Calculate the ZOA/ZOD of the cluster
% Input values:
% scenariosPara: Table data from section 6.7.2 of 3GPP TR 38.811 V15.4.0 (2020-09)
% ZS: ZSD/ZSA distribution
% C_ZS: C_ZSA/C_ZSD is the cluster rms diffusion value for ZOA/ZOD
% P_n: Cluster ray power
% C_theta: Scaling factor for ZOA, ZOD generation
% zenithAngleKind: Indicates the type of zenith angle to distinguish between different calculations , 1:ZOA,2:ZOD
% channelIdx: This parameter is used to select the channel scenario, 1: LOS channel, 2: NLOS channel
% Return values：
% theta_n_m_Zenith: ZOA/ZOD of the cluster

N = scenariosPara.N;  % Get input parameters
M = scenariosPara.M;
theta_n_Zenith1 = (ZS .* log(P_n ./ max(P_n))) ./ C_theta;          % Compute ZOD/ZOA according to equation (7.5-15) in 3GPP TR 138 901 V16.1.0
Xn1 = 2 * (myrand(N) >= 0.5) - 1;                                   % Maps each element to {1, -1}
Yn = ((ZS ./7 ).^2) .* randn(1, N);                                 % Generate a matrix of random numbers N(0, (ZSA./7). ^2) of the random number matrix
theta_n_m_Zenith = zeros(N,M);
if (zenithAngleKind == 1)
    if (channelIdx == 1)
        theta_n_Zenith = (Xn1 .* theta_n_Zenith1 + Yn) - (Xn1(1) .* theta_n_Zenith1(1) + Yn(1) - losZenith); % Compute ZOD/ZOA of the loscase according to equation (7.5-17) in 3GPP TR 138 901 V16.1.0
    else
        theta_n_Zenith = Xn1 .* theta_n_Zenith1 + Yn + losZenith;   % Compute  ZOD/ZOA according to equation (7.5-16) in 3GPP TR 138 901 V16.1.0
    end
    for nIndex = 1:N
        alpha0 = [0.0447 -0.0447 0.1413 -0.1413 0.2492 -0.2492 0.3715 -0.3715 0.5129 -0.5129 0.6797 -0.6797 0.8844 -0.8844 1.1481 -1.1481 1.5195 -1.5195 2.1551 -2.1551];
        alpha = alpha0(1:M);
        theta_n_m_Zenith(nIndex,:) = theta_n_Zenith(nIndex) .* ones(1,M) + c_ZS * alpha;    % Compute ZOD/ZOA  according to equation (7.5-18) add offset angles in 3GPP TR 138 901 V16.1.0
    end
else
    mu_lgZSD = scenariosPara.mu_lgZSD;
    if (channelIdx == 1)
        theta_n_Zenith = (Xn1 .* theta_n_Zenith1 + Yn) - (Xn1(1) .* theta_n_Zenith1(1) + Yn(1) - losZenith); % Compute ZOD/ZOA for loscase according to equation (7.5-17) in 3GPP TR 138 901 V16.1.0
    else
        theta_n_Zenith = Xn1 .* theta_n_Zenith1 + Yn + losZenith + mu_offestZOD;                             % Compute ZOD/ZOA according to equation (7.5-19) in 3GPP TR 138 901 V16.1.0
    end
    for nIndex = 1:N
        alpha0 = [0.0447 -0.0447 0.1413 -0.1413 0.2492 -0.2492 0.3715 -0.3715 0.5129 -0.5129 0.6797 -0.6797 0.8844 -0.8844 1.1481 -1.1481 1.5195 -1.5195 2.1551 -2.1551];
        alpha = alpha0(1:M);
        theta_n_m_Zenith(nIndex,:) = theta_n_Zenith(nIndex) .* ones(1,M) + (3/8) * (10^(mu_lgZSD)) * alpha;   % Compute  ZOD/ZOA according to 3GPP TR 138 901 V16.1.0, equation (7.5-20) add offset angles
    end
end
end

function [shuffledMatrix] = shuffleMatrix(anglesMatric)

% Function: Stochastic coupling of the input matrix
% Input values:
% anglesMatric: Initial matrix to be processed
% Return values:
% shuffledMatrix: Initial matrix to be processed

numRows = size(anglesMatric,1);           % Get the number of rows in the matrix
numCols = size(anglesMatric,2);           % Get the number of columns in the matrix
shuffledMatrix = zeros(numRows,numCols);  % Initialise the disrupted matrix with the same size as the original matrix
for i = 1:numRows
    shuffledIndices = randperm(numCols);  % randperm(n), generates a random permutation from 1 to n
    shuffledMatrix(i, :) = anglesMatric(i, shuffledIndices);
end
end


function [H_usnm,H_usnm_t,dopplerFreqCenter] = NlosCoefficient(parameter,modePara,position)

% Function: Compute channel coefficient of Sub-cluster based equation(6.8-1a) of 3GPP TR 38.811 V15.4.0 (2020-09)
% Input values:
% parameter: Parameter of channel model
% modePara: Parameter of different CDL channel models
% position: The position and velocity of terminal and satellite
% Return values:
% H_usnm: Channel coefficient of Sub-cluster
% H_usnm_t: Channel coefficient of Sub-cluster to time t
% dopplerFreqCenter：存储多普勒中心频率用于频率搬移，降低采样率
derad = pi/180;
global Re;
t = linspace(0,parameter.T,parameter.N_Ts);  % Time series
% if parameter.T >= 1
%     t = linspace(parameter.T-1,parameter.T,parameter.N_Ts);  % Time series
% else
%     t = linspace(0,parameter.T,parameter.N_Ts);
% end
c = parameter.c;
fc = parameter.fc;
N_r = parameter.N_r;
N_t = parameter.N_t;
N = modePara.N;
M = modePara.M;
K = modePara.K;
P_n = modePara.P_n;
tao_n = modePara.tao_n;
phi_n_m_AOA = modePara.phi_n_m_AOA;
phi_n_m_AOD = modePara.phi_n_m_AOD;
theta_n_m_ZOA = modePara.theta_n_m_ZOA;
theta_n_m_ZOD = modePara.theta_n_m_ZOD;
phi = phi_n_m_AOD(:).';                                         % 2026_6_6
theta = theta_n_m_ZOD(:).';                                     % 2026_6_6
F_txfield = parameter.F_tx;
% data = parameter.antennaGain;
% F_txfield = fiedldpattern([phi(1),theta(1)-90,0],theta,phi,data);    % 2026_6_6
% [F_txfield,~] = GenerateAntennaPattern_Gain([phi(1),theta(1)-90,0],theta,phi,data);
F_txfield = repmat(F_txfield,1,N*M);
F_txfield = permute(F_txfield,[1,3,2,4]);
F_txfield = reshape(F_txfield,[2,1,N,M,parameter.NumAntennaPattern]);                         % 2026_6_6
Knm = modePara.Knm;
terminalVelocity = position.terminalVelocity;
satelliteVelocity = position.satelliteVelocity;
dopplerFreq = zeros(N,M);                                         % 存储各子径多普勒频率
numPolarizations = 4;                                          % The number of polarisation combinations
initialPhases = (2 * pi) * rand(N, M, numPolarizations) - pi;  % Draw initial random phases
k = (2 * pi * fc * (1e9)) / c;                                 % The wave number
a = 10 * c / (fc * (1e9));                                     % The radius of the antenna's circular aperture
psi = 108 / fc^2;                                              % ψ is the faraday rotation in degree ,f is the central carrier frequency in GHz,Calculated from equation (6.8-2) in 3GPP TR 38.811 V15.4.0
lambda0 = c / (fc * (1e9));
d = lambda0 / 2;                                               % The distance of transmit antenna element
d_rx = zeros(3, N_r);
for u = 1:N_r
    d_rx(:, u) = [(u - 1) * d; 0; 0];                          % The location vector of receive antenna element
end
d_tx = zeros(3, N_t);
radius = a;
for s = 1:N_t
    angle = 2 * pi * (s - 1) / N_t;                            %  Angle of each element relative to the first element
    d_tx(:, s) = [radius * cos(angle); radius * sin(angle); 0];% The location vector of transmit antenna element
end

% H_usnm = complex(zeros(N_r, N_t, N, M));
% t_length = length(t);
% H_usnm_t = complex(zeros(N_r, N_t, N, M,t_length));
% dopplerFreqCenter = 0;
% 
% for u = 1:N_r
%     for s = 1:N_t
%         for n = 1:N
%             for m = 1:M
%                 Fr = [cos(psi*derad) -sin(psi*derad); sin(psi*derad) cos(psi*derad)];% Faraday rotation,Calculated from equation (6.8-2) in 3GPP TR 38.811 V15.4.0
%                 % G_max = 1.5 * (0.5)^2;                                               % Calculate the maximum gain value, for a half-wave dipole antenna, the maximum gain occurs at theta = 90 degrees
%                 % F_rx = [cos(pi*cos(theta_n_m_ZOA(n,m)*derad) / 2).^2  ./ sin(theta_n_m_ZOA(n,m) * derad).^2; G_max];  % The field patterns of receive antenna element
%                 gain = 1;                                              %2026_6_24 Isotropic Gain_max = 1; polarization angle = [45 -45], 
%                 F_rx = [sind(45);cosd(45)]*gain;                
%                 % if(theta_n_m_ZOD == 0)
%                 %     G_tx = 1;
%                 % else
%                 %     G_tx = 4 * (abs(besselj(1,k * a * sin(theta_n_m_ZOD(n,m) * derad))/(k * a * sin(theta_n_m_ZOD(n,m) * derad))))^2;
%                 % end
%                 G_tx = 1;
%                 F_tx = [ G_tx * cos(45*derad); G_tx * sin(45 * derad)];                % The field patterns of transmit antenna element
%                 % F_tx = F_txfield(:,n,m);                                        % The field patterns of transmit antenna element,2026_6_6
%                 randomPhases = [exp(1i * initialPhases(n,m,1)), sqrt(Knm(n,m)^(-1)) * exp(1i * initialPhases(n,m,3));...
%                     sqrt(Knm(n,m)^(-1)) * exp(1i * initialPhases(n,m,2)), exp(1i*initialPhases(n,m,4))]; % Draw initial random phases
%                 r_rx = [sin(theta_n_m_ZOA(n,m) * derad) * cos(phi_n_m_AOA(n,m) * derad); ...                        % The spherical unit vector of receive antenna
%                     sin(theta_n_m_ZOA(n,m) * derad) * sin(phi_n_m_AOA(n,m) * derad); ...
%                     cos(theta_n_m_ZOA(n,m))];
%                 r_tx = [sin(theta_n_m_ZOD(n,m) * derad) * cos(phi_n_m_AOD(n,m) * derad); ...                        % The spherical unit vector of transmit antenna
%                     sin(theta_n_m_ZOD(n,m) * derad) * sin(phi_n_m_AOD(n,m) * derad); ...
%                     cos(theta_n_m_ZOD(n,m))];
%                 H_usnm(u,s,n,m) = sqrt(P_n(n) / M) * F_rx.' * randomPhases * Fr * F_tx * exp(1i * 2 * pi * ((r_rx.' * d_rx(:,u)) / lambda0)) *...             % Compute channel coefficient of Sub-cluster based equation(6.8-1a)
%                     exp(1i*2*pi * ((r_tx.' * d_tx(:,s)) / lambda0));
%                 % for t_idx = 1:t_length
%                 %     H_usnm_t(u,s,n,m,t_idx) = (P_n(n) / M) * F_rx.' * randomPhases * Fr * F_tx * exp(1i * 2 * pi * ((r_rx.' * d_rx(:,u)) / lambda0)) *... % Compute channel coefficient of Sub-cluster based equation(6.8-1a) to time t
%                 %     exp(1i * 2 * pi * ((r_tx.' * d_tx(:,s)) / lambda0)) * exp(1i * 2 * pi * ((r_rx.' * terminalVelocity * t(t_idx)) / lambda0)) * exp(1i * 2 * pi *((r_tx.' * satelliteVelocity * t(t_idx)) / lambda0));
%                 % end
%                 % 直接计算整个时间序列
%                 timeFactor = exp(1i * 2 * pi * ((r_rx.' * terminalVelocity + r_tx.' * satelliteVelocity) / lambda0) * t);
%                 H_usnm_t(u,s,n,m,:) = H_usnm(u,s,n,m) * timeFactor;
%                 % 统计各子径多普勒频率 20250807修改
%                 dopplerFreq(n,m) = ((r_rx.' * terminalVelocity + r_tx.' * satelliteVelocity) / lambda0);
%             end
%         end
%         dopplerFreqCenter = mean(mean(dopplerFreq));% 计算多普勒频率中心值
%         % for n = 1:N
%         %     for m = 1:M
%         %         timeFactor = exp(1i * 2 * pi * (dopplerFreq(n,m)-dopplerFreqCenter) * t);
%         %         H_usnm_t(u,s,n,m,:) = H_usnm(u,s,n,m) * timeFactor;
%         %     end
%         % end
%     end
% end

% 
% 26-7-13
Fr = [cos(psi*derad) -sin(psi*derad); sin(psi*derad) cos(psi*derad)];

theta_n_m_ZOA = theta_n_m_ZOA(:);
phi_n_m_AOA = phi_n_m_AOA(:);
theta_n_m_ZOD = theta_n_m_ZOD(:);
phi_n_m_AOD = phi_n_m_AOD(:);


r_rx = [sin(theta_n_m_ZOA * derad) .* cos(phi_n_m_AOA * derad); ...                        % The spherical unit vector of receive antenna
    sin(theta_n_m_ZOA * derad) .* sin(phi_n_m_AOA * derad); ...
    cos(theta_n_m_ZOA)];

r_tx = [sin(theta_n_m_ZOD * derad) .* cos(phi_n_m_AOD * derad); ...                        % The spherical unit vector of transmit antenna
    sin(theta_n_m_ZOD * derad) .* sin(phi_n_m_AOD * derad); ...
    cos(theta_n_m_ZOD)];

r_tx =  reshape(r_tx,N*M,3,1); 
r_rx =  reshape(r_rx,N*M,3,1); 

r_tx = permute(r_tx,[2,3,1]);
r_tx = reshape(r_tx,3,1,N,M);

r_rx = permute(r_rx,[2,3,1]);
r_rx = reshape(r_rx,3,1,N,M);

initialPhases = reshape(initialPhases,N*M,4);
Knm = Knm(:);
randomPhases = [exp(1i * initialPhases(:,1)), sqrt(Knm.^(-1)) .* exp(1i * initialPhases(:,3));...
    sqrt(Knm.^(-1)) .* exp(1i * initialPhases(:,2)), exp(1i.*initialPhases(:,4))]; % Draw initial random phases
randomPhases = reshape(reshape(randomPhases,N*M,4),N,M,2,2);
randomPhases = permute(randomPhases,[3,4,1,2]);

gain = ones(2,1,N,M);                                           
F_rx = [sind(45);cosd(45)].*gain;  
F_rx = pagectranspose(F_rx);

A = pagemtimes(pagemtimes(pagemtimes(F_rx,randomPhases),Fr),F_txfield);
F = A(:);
% A = permute(A,[3,4,5,1,2]);
D = repmat(sqrt(P_n / M),1,M*parameter.NumAntennaPattern);
E = F.*D(:);
A = reshape(E,1,1,N,M,parameter.NumAntennaPattern);
r_rx = pagectranspose(r_rx);
r_tx = pagectranspose(r_tx);

B  =exp(1i * 2 * pi * (pagemtimes(r_rx,d_rx) / lambda0)) .* exp(1i*2*pi * (pagemtimes(r_tx,d_tx) / lambda0));

% C =  exp(1i * 2 * pi * ((pagemtimes(r_rx,terminalVelocity) + pagemtimes(r_tx,satelliteVelocity)) / lambda0) .* t);

H_usnm = pagemtimes(A,B);

H_usnm_t = pagemtimes(pagemtimes(A,B), exp(1i * 2 * pi * ((pagemtimes(r_rx,terminalVelocity) + pagemtimes(r_tx,satelliteVelocity)) / lambda0) .* t));

% H_usnm_t1 = permute(H_usnm_t1,[1,5,3,4,2]);

dopplerFreqCenter = mean(mean((pagemtimes(r_rx,terminalVelocity) + pagemtimes(r_tx,satelliteVelocity)) / lambda0));

end

function [H_us,H_us_t] = LosCoefficient(modeScenariosPara,parameter,N,M,position)

% Function: Compute channel coefficient of Sub-cluster based equation(6.8-1b) of 3GPP TR 38.811 V15.4.0 (2020-09)
% Input values:
% parameter: Parameter of channel model
% N: The number of clusters, M: The number of sub-clusters
% position: The position and velocity of terminal and satellite
% modeScenariosPara: Parameter of different CDL channel models
% Return values:
% H_us: Channel coefficient of cluster
% H_us_t: Channel coefficient of cluster to time t

derad = pi/180;
global Re;
t = linspace(0,parameter.T,parameter.N_Ts);  % Time series
c = parameter.c;
fc = parameter.fc;
N_r = parameter.N_r;
N_t= parameter.N_t;
% 根据收发端位置计算的LoS角度，注意这个是不对的，还存在天线朝向，应根据模型参数来计算
losAOA = position.losAOA;
losAOD = position.losAOD;
losZOA = position.losZOA;
losZOD = position.losZOD;
% 下面为根据模型参数来计算LoS角度
% losAOA = modeScenariosPara.phi_n_m_AOA(1,1);
% losAOD = modeScenariosPara.phi_n_m_AOD(1,1);
% losZOA = modeScenariosPara.theta_n_m_ZOA(1,1);
% losZOD = modeScenariosPara.theta_n_m_ZOD(1,1);

% F_txfield = fiedldpattern([losAOD,losZOD-90,0],losZOD,losAOD,data);    % 2026_6_6
% data = parameter.antennaGain;
% [F_txfield,~] = GenerateAntennaPattern_Gain([losAOD,losZOD-90,0],losZOD,losAOD,data);%2026-6-11
F_txfield = parameter.F_tx;
F_txfield = reshape(F_txfield,[2,1,N,M,parameter.NumAntennaPattern]); 
terminalVelocity = position.terminalVelocity;
satelliteVelocity = position.satelliteVelocity;
d3D = position.d3D;                                            % Three-dimensional distance between terminal and satellite
k = (2 * pi * fc * (1e9)) / c;                                 % The wave number
a = 10 * c / (fc * (1e9));                                     % The radius of the antenna's circular aperture
psi = 108 / fc^2;                                              % ψ is the faraday rotation in degree ,f is the central carrier frequency in GHz,Calculated from equation (6.8-2) in 3GPP TR 38.811 V15.4.0
lambda0 = c / (fc * (1e9));
d = lambda0 / 2;                                               % The distance of transmit antenna element
d_rx = zeros(3,N_r);
for u = 1:N_r
    d_rx(:, u) = [(u - 1) * d; 0; 0];                          % The location vector of receive antenna element
end
d_tx = zeros(3, N_t);
radius = a;
for s = 1:N_t
    angle = 2 * pi * (s - 1) / N_t;                             % Angle of each element relative to the first element
    d_tx(:, s) = [radius * cos(angle); radius * sin(angle); 0]; % The location vector of transmit antenna element
end

% H_us = complex(zeros(N_r,N_t,N,M));
% t_length = length(t);
% H_us_t = complex(zeros(N_r,N_t,N,M,t_length));
% for u = 1:N_r
%     for s = 1:N_t
%         for n = 1:N
%             for m = 1:M
%                 Fr = [cos(psi * derad), -sin(psi * derad); sin(psi * derad), cos(psi * derad)];           % Faraday rotation,Calculated from equation (6.8-2) in 3GPP TR 38.811 V15.4.0
%                 % G_max = 1.5 * (0.5)^2;                                                                    % Calculate the maximum gain value, for a half-wave dipole antenna, the maximum gain occurs at theta = 90 degrees
%                 % F_rx = [cos(pi * cos(losZOA(n,m) * derad) / 2).^2 ./ sin(losZOA(n,m) * derad).^2; G_max]; % The field patterns of receive antenna element
%                 gain = 1;                                              %2026_6_24 Isotropic Gain_max = 1; polarization angle = [45 -45], 
%                 F_rx = [sind(45);cosd(45)]*gain; 
%                 % if(losZOD == 0)
%                     G_tx = 1;
%                 % else
%                 %     G_tx = 4*(abs(besselj(1,k * a * sin(losZOD(n,m) * derad)) / (k * a * sin(losZOD(n,m) * derad))))^2;
%                 % end
%                 F_tx = [ G_tx * cos(45 * derad); G_tx * sin(45 * derad)];                         % The field patterns of transmit antenna element
%                 % F_tx = F_txfield;       %2026-6-6
%                 randomPhases = [1 0; 0 -1];                                                       % Draw initial random phases
%                 r_rx = [sin(losZOA(n,m) * derad) * cos(losAOA(n,m) * derad); ...                 % The spherical unit vector of receive antenna
%                     sin(losZOA(n,m) * derad) * sin(losAOA(n,m) * derad); ...
%                     cos(losZOA(n,m))];
%                 r_tx = [sin(losZOD(n,m) * derad) * cos(losAOD(n,m) * derad); ...                 % The spherical unit vector of transmit antenna
%                     sin(losZOD(n,m) * derad) * sin(losAOD(n,m) * derad); ...
%                     cos(losZOD(n,m))];
%                 H_us(u,s,n,m) = F_rx.' * randomPhases * Fr * F_tx * exp(-1i * 2 * pi * (d3D / lambda0)) * exp(1i * 2 * pi * ((r_rx.' * d_rx(:,u)) / lambda0)) *...             % Compute channel coefficient of Sub-cluster based equation(6.8-1b)
%                     exp(1i * 2 * pi * ((r_tx.' * d_tx(:,s)) / lambda0));
%                 for t_idx = 1:t_length
%                     H_us_t(u,s,n,m,t_idx) =  F_rx.' * randomPhases * Fr * F_tx * exp(-1i * 2 * pi * (d3D / lambda0)) * exp(1i * 2 * pi *((r_rx.' * d_rx(:,u)) / lambda0)) *... % Compute channel coefficient of Sub-cluster based equation(6.8-1b) to time t
%                         exp(1i * 2 * pi * ((r_tx.' * d_tx(:,s)) / lambda0)) * exp(1i * 2 * pi * ((r_rx.' * terminalVelocity * t(t_idx)) / lambda0)) * exp(1i * 2 * pi * ((r_tx.' * satelliteVelocity * t(t_idx)) / lambda0));
%                 end
%             end
%         end
%     end
% end

Fr = [cos(psi*derad) -sin(psi*derad); sin(psi*derad) cos(psi*derad)];

r_rx = [sin(losAOA * derad) .* cos(losAOA * derad); ...                        % The spherical unit vector of receive antenna
    sin(losZOA * derad) .* sin(losAOA * derad); ...
    cos(losZOA)];

r_tx = [sin(losZOD * derad) .* cos(losAOD * derad); ...                        % The spherical unit vector of transmit antenna
    sin(losZOD * derad) .* sin(losAOD * derad); ...
    cos(losZOD)];

% r_tx =  reshape(r_tx,N*M,3,1); 
% r_rx =  reshape(r_rx,N*M,3,1); 
% 
% r_tx = permute(r_tx,[2,3,1]);
% r_tx = reshape(r_tx,3,1,N,M);
% 
% r_rx = permute(r_rx,[2,3,1]);
% r_rx = reshape(r_rx,3,1,N,M);

% initialPhases = reshape(initialPhases,N*M,4);
% Knm = Knm(:);
% randomPhases = [exp(1i * initialPhases(:,1)), sqrt(Knm.^(-1)) .* exp(1i * initialPhases(:,3));...
%     sqrt(Knm.^(-1)) .* exp(1i * initialPhases(:,2)), exp(1i.*initialPhases(:,4))]; % Draw initial random phases
% randomPhases = reshape(reshape(randomPhases,N*M,4),N,M,2,2);
% randomPhases = permute(randomPhases,[3,4,1,2]);
randomPhases = [1 0; 0 -1];
gain = ones(2,1,N,M);                                           
F_rx = [sind(45);cosd(45)].*gain;  
F_rx = pagectranspose(F_rx);

A = pagemtimes(pagemtimes(pagemtimes(F_rx,randomPhases),Fr),F_txfield);
% F = A(:);
% % A = permute(A,[3,4,5,1,2]);
% D = repmat(sqrt(P_n / M),1,M*parameter.NumAntennaPattern);
% E = F.*D(:);
% A = reshape(E,1,1,N,M,parameter.NumAntennaPattern);
r_rx = pagectranspose(r_rx);
r_tx = pagectranspose(r_tx);

B  =exp(-1i * 2 * pi * (d3D / lambda0))*exp(1i * 2 * pi * (pagemtimes(r_rx,d_rx) / lambda0)) .* exp(1i*2*pi * (pagemtimes(r_tx,d_tx) / lambda0));

% C =  exp(1i * 2 * pi * ((pagemtimes(r_rx,terminalVelocity) + pagemtimes(r_tx,satelliteVelocity)) / lambda0) .* t);

H_us = pagemtimes(A,B);

H_us_t = pagemtimes(pagemtimes(A,B), exp(1i * 2 * pi * ((pagemtimes(r_rx,terminalVelocity) + pagemtimes(r_tx,satelliteVelocity)) / lambda0) .* t));

% H_usnm_t1 = permute(H_usnm_t1,[1,5,3,4,2]);


end


function [modeScenariosPara] = CDLModelSwitch(compScenariosPara,scenariosPara,position,channelMod)

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
modeScenariosPara.phi_n_m_AOD = 0;
modeScenariosPara.phi_n_m_AOA = 0;
modeScenariosPara.theta_n_m_ZOD = 0;
modeScenariosPara.theta_n_m_ZOA = 0;
switch channelMod
    case 'A'     % Support NTN-CDL-A
        table6_9_1_1 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_1.txt',4,6);              % Load data of 3GPP_TR_38_811_table6_9_1_1
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,scenariosPara,position,table6_9_1_1,channelMod);  % Get Parameter of different CDL channel models
    case 'B'     % Support NTN-CDL-B
        table6_9_1_2 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_2.txt',5,6);              % Load data of 3GPP_TR_38_811_table6_9_1_2
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,scenariosPara,position,table6_9_1_2,channelMod);
    case 'C'     % Support NTN-CDL-C
        table6_9_1_3 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_3.txt',4,6);              % Load data of 3GPP_TR_38_811_table6_9_1_3
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,scenariosPara,position,table6_9_1_3,channelMod);
    case 'D'     % Support NTN-CDL-D
        table6_9_1_4 = readCDLData('external_data/3GPP_TR_38_811_data/table6_9_1_4.txt',5,6);              % Load data of 3GPP_TR_38_811_table6_9_1_4
        [modeScenariosPara] = CDLModelScenarios(compScenariosPara,scenariosPara,position,table6_9_1_4,channelMod);
end
end



function [modeScenariosPara] = CDLModelScenarios(compScenariosPara,scenariosPara,position,dataTable,channelMod)

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
CDL_param = struct();
CDL_param.EOA_Des = position.losEOA;                                          % Desired EOA angle
CDL_param.EOA_Mod = 50;                                                       % EOA angle of NTN-CDL-A
CDL_param.P_nMod = dataTable(1:(dataRows - 1),2);                             % Power of model,dB -> linear value
CDL_param.phi_n_AODMod = dataTable(1:(dataRows - 1),3);                       % AOD of model
CDL_param.phi_n_AOAMod = dataTable(1:(dataRows - 1),4);                       % AOA of model

CDL_param.theta_n_ZODMod = (90 + position.losEOA) * ones((dataRows - 1),1); % ZOD of model
CDL_param.theta_n_ZOAMod = dataTable(1:(dataRows - 1),6);                     % ZOA of model
CDL_param.C_ASAMod = dataTable(dataRows,2);                                   % C_ASA of model
CDL_param.C_ZSAMod = dataTable(dataRows,4);                                   % C_ZSA of model
tao_nMod = dataTable(1:(dataRows - 1),1);                                     % Delay of model
XPR_Mod = dataTable(dataRows,5);                                              % XPR of model
K_n_mMod = 10^(XPR_Mod/10) .* ones((dataRows - 1),20);                        % Generate the cross polarization power ratios according to equation (7-70b) in 3GPP TR 138 901 V16.1.0
tao_nScal = tao_nMod * DS_Des;                                                % Delay of model
[phi_n_mAODScal,phi_n_mAOAScal] = scaledAzimuthAngle(CDL_param,compScenariosPara,scenariosPara);
[theta_n_mZODScal,theta_n_mZOAScal] = scaledzenithAngle(CDL_param,compScenariosPara,scenariosPara);
if (channelMod == 'A' || channelMod == 'B')
    K_Mod = 0;
    P_nScal = 10.^((CDL_param.P_nMod) ./ 10);
else
    K_Des = compScenariosPara.K;                                               % The model's K-factor
    K_Mod = CDL_param.P_nMod(1) - 10 * log10(sum(10.^(CDL_param.P_nMod(2:end) ./ 10))); % The model's K-factor according to equation (7.7.6-2) in 3GPP TR 138 901 V16.1.0
    P_nScal = CDL_param.P_nMod;
    P_nScal(1) = CDL_param.P_nMod(1) - K_Des + K_Mod;
    P_nScal = 10 .^ (P_nScal ./ 10);
end
modeScenariosPara = struct();
modeScenariosPara.EOA_Mod = CDL_param.EOA_Mod;
modeScenariosPara.K = K_Mod;
modeScenariosPara.Knm = K_n_mMod;
modeScenariosPara.tao_n = tao_nScal;
modeScenariosPara.P_n = P_nScal;
modeScenariosPara.phi_n_m_AOD = phi_n_mAODScal;
modeScenariosPara.phi_n_m_AOA = phi_n_mAOAScal;
modeScenariosPara.theta_n_m_ZOD = theta_n_mZODScal;
modeScenariosPara.theta_n_m_ZOA = theta_n_mZOAScal;
end


function [phi_n_mAODScal,phi_n_mAOAScal] = scaledAzimuthAngle(CDL_param,compScenariosPara,scenariosPara)

% Function: Compute AOA/AOD angle according to equation (7.7-0a) in 3GPP TR 138 901 V16.1.0
% Input values:
% CDL_param: Parameter of different CDL channel models
% compScenariosPara: Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters
% Return values:
% phi_n_mAODScal: Scaled AOD angle of CDL channel models for clusters and sub-clusters
% phi_n_mAOAScal: Scaled AOA angle of CDL channel models for clusters and sub-clusters
% phi_n_AOAScal:  Scaled AOA of CDL channel models for clusters

P_nDes = compScenariosPara.P_n.';
phi_n_mAOADes = compScenariosPara.phi_n_m_AOA;
phi_n_AOAMod = CDL_param.phi_n_AOAMod;
phi_n_AODMod = CDL_param.phi_n_AODMod;
numberCluster= length(phi_n_AOAMod);
C_ASAMod = CDL_param.C_ASAMod;
P_nMod = CDL_param.P_nMod;
alpha = [0.0447 -0.0447 0.1413 -0.1413 0.2492 -0.2492 0.3715 -0.3715 0.5129...  % The ray offset angles within a cluster given by Table 7.5-3 in 3GPP TR 138 901 V16.1.0
    -0.5129 0.6797 -0.6797 0.8844 -0.8844 1.1481 -1.1481 1.5195 -1.5195 2.1551 -2.1551];
phi_n_mAOAMod = phi_n_AOAMod + C_ASAMod * alpha;       % Compute ZOA according to equation (7.7-0a) in 3GPP TR 138 901 V16.1.0
phi_n_mAOAMod = shuffleMatrix(phi_n_mAOAMod);          % Coupling of rays within a cluster for both azimuth and elevation
[ASA_Mod,miu_AOAMod] = modeParam(phi_n_mAOAMod,P_nMod);
[ASA_Des,miu_AOADes] = modeParam(phi_n_mAOADes,P_nDes);
phi_n_AOAScal = (ASA_Des / ASA_Mod) * (phi_n_AOAMod - miu_AOAMod) + miu_AOADes; % Scaled ray angles can be obtained according to the equation(7.7-5) in 3GPP TR 138 901 V16.1.0
phi_n_mAOAScal = phi_n_AOAScal + C_ASAMod * alpha;
phi_n_mAODScal = phi_n_AODMod(1) * ones(numberCluster,20);
end


function [theta_n_mZODScal,theta_n_mZOAScal] = scaledzenithAngle(CDL_param,compScenariosPara,scenariosPara)

% Function: Compute ZOA/ZOD angle according to equation(6.9-2) in 3GPP_TR_38_811 V15.4.0
% Input values:
% CDL_param: Parameter of different CDL channel models
% compScenariosPara: Based table 6.7.2 in 3GPP TR 38.811 V15.4.0，generate large scale parameters
% Return values:
% theta_n_mZODScal: Scaled ZOD angle of CDL channel models for clusters and sub-clusters
% theta_n_mZOAScal: Scaled ZOA angle of CDL channel models for clusters and sub-clusters
% theta_n_ZOAScal:  Scaled ZOA of CDL channel models for clusters

P_nDes = compScenariosPara.P_n.';
theta_n_mZOADes = compScenariosPara.theta_n_m_ZOA ;
theta_n_ZOAMod = CDL_param.theta_n_ZOAMod;
theta_n_ZODMod = CDL_param.theta_n_ZODMod;
numberCluster = length(theta_n_ZOAMod);
C_ZSAMod = CDL_param.C_ZSAMod;
P_nMod = CDL_param.P_nMod;
EOA_Des = CDL_param.EOA_Des;
EOA_Mod = CDL_param.EOA_Mod;
alpha = [0.0447 -0.0447 0.1413 -0.1413 0.2492 -0.2492 0.3715 -0.3715 0.5129...  % The ray offset angles within a cluster given by Table 7.5-3 in 3GPP TR 138 901 V16.1.0
    -0.5129 0.6797 -0.6797 0.8844 -0.8844 1.1481 -1.1481 1.5195 -1.5195 2.1551 -2.1551];
theta_n_mZOAMod = theta_n_ZOAMod + C_ZSAMod * alpha;     % Compute ZOA according to equation (7.7-0a) in 3GPP TR 138 901 V16.1.0
theta_n_mZOAMod = shuffleMatrix(theta_n_mZOAMod);        % Coupling of rays within a cluster for both azimuth and elevation
[ZSA_Mod,miu_ZOAMod] = modeParam(theta_n_mZOAMod,P_nMod);
[ZSA_Des,miu_ZOADes] = modeParam(theta_n_mZOADes,P_nDes);
% [~,miu_ZOADes] = modeParam(theta_n_mZOADes,P_nDes);
% y = scenariosPara.mu_lgZSA + scenariosPara.sigma_lgZSA*randn;
% ZSA_Des = 10^y;
theta_n_ZOAScal = (ZSA_Des / ZSA_Mod) * (theta_n_ZOAMod - miu_ZOAMod) + miu_ZOADes - (EOA_Des - EOA_Mod); % Scaled ray angles can be obtained according to the equation(6.9-2) in 3GPP_TR_38_811 V15.4.0
theta_n_mZOAScal = theta_n_ZOAScal + C_ZSAMod * alpha;
theta_n_mZODScal = theta_n_ZODMod(1) * ones(numberCluster,20);
end


function [AS_mod,miu_Mod] = modeParam(angle_n_mMod,P_nMod)

% Function: Compute angle spread and mean angle according to  Annex A in 3GPP TR 138 901 V16.1.0
% Input values:
% angle_n_mMod: The clusters and sub-clusters angle of CDL channel models
% P_nMod: The power of CDL channel models
% Return values:
% AS_mod: Angle spread of CDL channel models
% miu_Mod: Mean angle of CDL channel models

derad = pi/180;
[~,lenCol] = size(angle_n_mMod);
P_n_mMod = repmat(P_nMod,1,lenCol);
sum_angle = (sum(sum(exp(1i .* angle_n_mMod) .* P_n_mMod,2)));
AS_mod = sqrt(-2*log(abs((sum_angle) / sum(sum(P_n_mMod,2))))); % Compute angular spread according to equation (A-1) by Annex A in 3GPP TR 138 901 V16.1.0
miu_Mod = (atan(imag(sum_angle) / real(sum_angle))) / derad;    % Compute mean angle according to equation (A-2) by Annex A in 3GPP TR 138 901 V16.1.0
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
end

% Helper function: Check if a character is a whitespace
function isSpace = isSpace(c)
% Directly compare ASCII values to avoid escape character issues
isSpace = (c == ' ') || (c == char(9)) || (c == char(10)) || (c == char(13));
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
% AOA  = (atan2(deltaY, deltaX)) ./ derad;                                 % Azimuth angle of arrival (-180,180)度
% AOD = ((atan2(-deltaY, -deltaX))) ./ derad;                              % Azimuth angle of departure
AOA = -180;                 %2026_6_6
AOD = 0;                    %2026_6_6
EOA = (asin(deltaZ / sqrt(deltaX^2 + deltaY^2 + deltaZ^2))) ./ derad;    % Elevation angle of arrival (-90,90)度
if EOA < 0
    EOA = 90 + EOA;
end
EOD = -(asin(deltaZ / sqrt(deltaX^2 + deltaY^2 + deltaZ^2))) ./ derad;   % Elevation angle of departure
ZOA = 90 - EOA;                                                          % Zenith angle of arrival
ZOD = 90 - EOD;                                                          % Zenith angle of departure (0,180)度
end

function [d2D, d3D] = computeDistances(position)
% Function: Compute the 2D and 3D distance between terminal and satellite
% Input values:
% terminalX, terminalY, terminalZ: 3D coordinates of the terminal
% satelliteX, satelliteY, satelliteZ: 3D coordinates of the satellite
% Return values:
% d2D: 2D distance between the terminal and the satellite
% d3D: 3D distance between the terminal and the satellite

terminalX = position.terminalX;    % Get the 3D coordinates of the terminal and satellite
terminalY = position.terminalY;
terminalZ = position.terminalZ;
satelliteX = position.satelliteX;
satelliteY = position.satelliteY;
satelliteZ = position.satelliteZ;
d2D = sqrt((satelliteX - terminalX)^2 + (satelliteY - terminalY)^2);                               % Compute 2D distances
d3D = sqrt((satelliteX - terminalX)^2 + (satelliteY - terminalY)^2 + (satelliteZ - terminalZ)^2);  % Compute 3D distances
end
