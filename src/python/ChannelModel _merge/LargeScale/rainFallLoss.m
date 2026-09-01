function Ar= rainFallLoss(parameter,theta)

% Function: Calculates long-term rainfall data based on single-point rainfall
% Input parameters:
% hR: Rainfall (km)
% R_0_01: Annual average single-point rainfall with 0.01% probability (mm/h)
% hs: Height of the Earth station above mean sea level (km)
% theta: Elevation angle (degrees)
% phi: Latitude of the Earth station (degrees)
% f: Frequency (GHz)
% Re: Effective radius of the Earth (8500 km)
% p: Percentage of annual exceedance probability (0.01~5%)
expectationP = 5; 
p = expectationP;
terminalLongitude=parameter.terminalLongitude;
terminalLatitude=parameter.terminalLatitude;
f=parameter.fc;
phi=parameter.terminalLatitude;
Re=8500;



TOPO = readData('external_data\ITU_R_P1511_3_data\ChinaTopo.dat',432,744);                                      % Assume the TOPO.dat file has been loaded into MATLAB with the variable name topoData
topoData = flipud(TOPO);
latitude1 = linspace(18, 54, 432);                                                                   % Latitude from -90 degrees to 90 degrees, increment by 1/12 degrees
longitude1 = linspace(73, 135, 744);                                                                % Longitude from -180 degrees to 180 degrees, increment by 1/12 degrees
[LON_trim, LAT_trim] = meshgrid(longitude1(1:end), latitude1(1:end));                                % Correction: Ensure grid size matches topoDataTrimmed
hs = interp2(LON_trim, LAT_trim, topoData, terminalLongitude, terminalLatitude, 'cubic') / 1000;     % Interpolate, note that LON and LAT here should be the complete grid for interpolation query

% hR: Rainfall (km)
latitude2 = readData('external_data\ITU_R_P839_4_data\Lat.txt',121,241);
v = linspace(-180, 180, 241);                                                                        % Generate a vector from -180 to 180
longitude2 = repmat(v, 121, 1);  
height = readData('external_data\ITU_R_P839_4_data\h0.txt',121,241);                                                   % Read the 0-degree isotherm height data

aaa=latitude2(:,1)'*(-1);
[latitudeLowerIndex,latitudeUpperIndex] = dataQueries(terminalLatitude,aaa);     % Obtain the range where the target latitude is located
aaa1=121-latitudeUpperIndex;
aaa2=121-latitudeLowerIndex;
[longitudeLowerIndex,longitudeUpperIndex] = dataQueries(terminalLongitude,longitude2(1,:)); % Obtain the range where the target longitude is located  
d1 = height(aaa1,longitudeLowerIndex);
d2 = height(aaa1,longitudeUpperIndex);
d3 = height(aaa2,longitudeLowerIndex);
d4 = height(aaa2,longitudeUpperIndex);
h_0 = CCDF(d1,d2,d3,d4,aaa1,longitudeLowerIndex);
hR = h_0 + 0.36;                                                                                      % Rainfall h_R

% R_001:The annual average rainfall amount R0.01 that exceeds a probability of 0.01%
% latitude3 = readData('external_data\ITU_R_P837_7_data\LAT_R001.TXT',1441,2881);                              % Read latitude and longitude data
% longitude3 = readData('external_data\ITU_R_P837_7_data\LON_R001.TXT',1441,2881);
rainfallData = readData('external_data\ITU_R_P837_7_data\ChinaRainfall.dat',289,497);                 % Read rainfall rate data
latitude3 = linspace(18, 54, 289);                                                                   % Latitude from -90 degrees to 90 degrees, increment by 1/12 degrees
longitude3 = linspace(73, 135, 497);                                                                % Longitude from -180 degrees to 180 degrees, increment by 1/12 degrees
[LON_trim, LAT_trim] = meshgrid(longitude3(1:end), latitude3(1:end)); 
R_0_01 = interp2(LON_trim, LAT_trim, rainfallData, terminalLongitude, terminalLatitude, 'linear');

theta_rad = deg2rad(theta);                                                                          % Calculate the slant path length Ls
if theta >= 5
    Ls = (hR - hs) / sin(theta_rad); 
else
    Ls = 2 * (hR - hs) / (sqrt(sin(theta_rad)^2 + (2 * (hR - hs)) / Re) + sin(theta_rad));
end
if hR - hs <= 0                                                                                      % If hR - hs is less than or equal to 0, the expected rain attenuation at any time percentage is 0
    A_0_01 = 0;
    Ar = 0;
    return;
end
LG = Ls * cos(theta_rad);                                                                            % Calculate the horizontal projection of the slant path LG
if R_0_01 == 0                                                                                       % If R_0.01 equals 0, the expected rain attenuation at any time percentage is 0
    A_0_01 = 0;
    Ar = 0;
    return;
end
gamma_R =rainAttenuatianl(f, R_0_01, theta);                                                         % Obtain the specific attenuation gamma_R
r_0_01 = 1 / (1 + 0.78 * sqrt((LG * gamma_R) / f) - 0.38 * (1 - exp(-2 * LG)));                      % Calculate the horizontal scaling factor r_0.01 for the 0.01% time period
zeta = atan((hR - hs) / (LG * r_0_01)) * (180 / pi);                                                 % Calculate the vertical adjustment factor nu_0.01 for the 0.01% time period
if zeta > 0
    LR = (LG * r_0_01) / cos(theta_rad); 
else
    LR = (hR - hs) / sin(theta_rad); 
end
if abs(phi) < 36
    chi = 36 - abs(phi); 
else
    chi = 0; 
end
v_0_01 = 1 / (1 + sqrt(sin(theta_rad)) * (31 * (1 - exp(-theta / (1 + chi)))) * sqrt(LR * gamma_R) / f^2 - 0.45);
LE = LG * v_0_01;                                                                                    %Effective path length LE
A_0_01 = gamma_R * LE;                                                                               %Expected attenuation exceeding the annual average 0.01% time
if p >= 1 || abs(phi) >= 36                                                                          %Expected attenuation exceeding the annual average for other percentages
    beta = 0;
elseif p < 1 && abs(phi) < 36 && theta >= 25
    beta = -0.005 * (abs(phi) - 36);
else
    beta = -0.005 * (abs(phi) - 36) + 1.8 - 4.25 * sin(theta_rad);
end
Ar = A_0_01 * (p / 0.01) ^(-(0.655 + 0.033 * log(p) - 0.045 * log(A_0_01) - beta * (1 - p) * sin(theta_rad)));

% Function to calculate rainfall attenuation rate
% Input parameters:
% f - Frequency (Hz)
% R - Rainfall rate (mm/h)
% theta: Elevation angle (degrees)

function gamma_R = rainAttenuatianl(f, R, theta)
tao_degree = 90;                                                                                     % Unit is degrees
theta_degree = theta;                                                                                % Unit is degrees
tao = deg2rad(tao_degree);                                                                           % Convert angle to radians
theta = deg2rad(theta_degree);                                                                       % Convert angle to radians
% Import k_H and other required parameters
m_kH = -0.18961;
m_kV = -0.16398;
m_aH = 0.67849;
m_aV = -0.053739;
c_kH = 0.71147;
c_kV = 0.63297;
c_aH = -1.95537;
c_aV = 0.83433;
% Define coefficients
aj_k = [-5.3398, -0.35351, -0.23789, -0.94158; ...
    -3.80595, -3.44965, -0.39902, 0.50167];
bj_k = [-0.10008, 1.26970, 0.86036, 0.64552; ...
    0.56934, -0.22911, 0.73042, 1.07319];
cj_k = [1.13098, 0.45400, 0.15354, 0.16817; ...
    0.81061, 0.51059, 0.11899, 0.27195];
aj_a = [-0.14318, 0.29591, 0.32177, -5.37610, 16.1721; ...
    -0.07771, 0.56727, -0.20238, -48.2991, 48.5833];
bj_a = [1.82442, 0.77564, 0.63773, -0.96230, -3.29980; ...
    2.33840, 0.95545, 1.14520, 0.791669, 0.791459];
cj_a = [-0.55187, 0.19822, 0.13164, 1.47828, 3.43990; ...
    -0.76284, 0.54039, 0.26809, 0.116226, 0.116479];
% Calculate k_H
sum_kH = 0;
for i = 1:4
    y = (log10(f) - bj_k(1, i)) / cj_k(1, i);
    x = aj_k(1, i) * exp(-y^2);
    sum_kH = sum_kH + x;
end
log_kH = sum_kH + m_kH * log10(f) + c_kH;
k_H = 10^(log_kH);
% Calculate k_V
sum_kV = 0;
for i = 1:4
    y = (log10(f) - bj_k(2, i)) / cj_k(2, i);
    x = aj_k(2, i) * exp(-y^2);
    sum_kV = sum_kV + x;
end
log_kV = sum_kV + m_kV * log10(f) + c_kV;
k_V = 10^(log_kV);
sum_aH = 0;
for i = 1:5
    y = (log10(f) - bj_a(1, i)) / cj_a(1, i);
    x = aj_a(1, i) * exp(-y^2);
    sum_aH = sum_aH + x;
end
a_H = sum_aH + m_aH * log10(f) + c_aH;
% Calculate a_V
sum_aV = 0;
for i = 1:5
    y = (log10(f) - bj_a(2, i)) / cj_a(2, i);
    x = aj_a(2, i) * exp(-y^2);
    sum_aV = sum_aV + x;
end
a_V = sum_aV + m_aV * log10(f) + c_aV;
% Calculate k and alpha
k = (k_H + k_V + (k_H - k_V) * cos(2 * tao) * cos(theta)^2) / 2;
alpha = (k_H * a_H + k_V * a_V + (k_H * a_H - k_V * a_V) * cos(2 * tao) * cos(theta)^2) / (2 * k);
% Return the rainfall attenuation rate (dB/km)
gamma_R = k * (R^alpha);
end
end
function [expectationValue] = CCDF(d1,d2,d3,d4,latitudeLowerIndex,longitudeLowerIndex)
      
% Function: According to the bilinear interpolation method for square grids in Annex 1 of ITU_R_P1144_12, calculate data parameters
% Input values:
% d1,d2,d3,d4: Four different data parameter values
% latitudeLowerIndex, longitudeLowerIndex: Row index and column index corresponding to latitude and longitude
% Return values:
% expectationValue: The expected value obtained after interpolation

     r = latitudeLowerIndex + (0.5);
     c = longitudeLowerIndex + (0.5);
     R = latitudeLowerIndex;
     C = longitudeLowerIndex;
     expectationValue = d1 * ((R + 1 - r) * (C + 1 -c)) + d3 * ((r - R) * (C + 1 - c)) + d2 * ((R + 1 - r) * (c - C)) + d4 * ((r - R) * (c - C));
end