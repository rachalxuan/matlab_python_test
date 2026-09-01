function A_p = troposphericScintillationLoss(parameter, theta) 
% Function:Tropospheric scintillation cumulative probability distribution prediction function
% Input parameters:
% f - Frequency (GHz), range 4 GHz to 55 GHz
% theta - Free space elevation angle (°), at least 5°
% D - Physical diameter of the ground station antenna (m)
% eta - Antenna efficiency, if unknown, use the conservative estimate value of 0.5
D = 1;
eta = 0.5;
expectationP = 5; 
p = expectationP;
f = parameter.fc;
Nwet = computeNwet(p, parameter);                                                       % Calculate the unprocessed radio refractivity Nwet, which corresponds to the es, t, and H given in ITU-R Recommendation P.453
sigma_ref = 3.6e-3 + 1e-4 * Nwet;                                                       % Calculate the standard deviation of the reference signal amplitude σ_ref
h_L = 1000;                                                                             % Height of the near-ground disturbance layer, 1000 m
L = (2 * h_L) / (sqrt((sin(theta * pi / 180))^2 + 2.35e-4 )+ sin(theta * pi / 180));      % Calculate the effective path length L
D_eff = sqrt(eta) * D;                                                                  % Estimate the effective antenna diameter D_eff based on geometric diameter D and antenna efficiency η
x = 1.22 * D_eff^2 * (f / L);                                                           % Calculate the antenna average coefficient
if x >= 7.0
    A_p = 0;
    return;
else
    g_x = sqrt(3.86 * (x^2 + 1)^(11/12) * sin(11/6 * atan(1/x)) - 7.08 * x^(5/6));
    sigma = sigma_ref * f^(7/12) * (g_x / (sin(theta * pi / 180))^1.2);
end
a_p = -0.061 * (log10(p)).^3 + 0.072 * (log10(p)).^2 - 1.71 * log10(p) + 3.0;            % Calculate the time percentage coefficient a(p) for p in the range 0.01 < p <= 50
A_p = a_p .* sigma;                                                                      % Calculate the attenuation depth A(p) exceeding the time percentage p%
end

function Nwet = computeNwet(p, parameter)
% Function: Calculate the unprocessed radio refractivity Nwet, which corresponds to the es, t, and H given in ITU-R Recommendation P.453
% Input values:
% P: Desired exceedance frequency
% terminalLatitude: Latitude, terminalLongitude: Longitude
% Return value:
% Nwet
terminalLongitude = parameter.terminalLongitude;
terminalLatitude = parameter.terminalLatitude;
latitudeScope = -90:0.75:90; % Latitude range
longitudeScope = -180:0.75:180; % Longitude range
[Latitude_lowerIndex, Latitude_upperIndex] = dataQueries(terminalLatitude, latitudeScope); % Use spatial and statistical (CCDF) interpolation methods to get the range of the target latitude
[Longitude_lowerIndex, Longitude_upperIndex] = dataQueries(terminalLongitude, longitudeScope); % Use spatial and statistical (CCDF) interpolation methods to get the range of the target longitude
P_scope_P_filenames = {'external_data/ITU_R_P453_14_data/NWET_Annual_01.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_02.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_03.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_05.txt', ...
'external_data/ITU_R_P453_14_data/NWET_Annual_1.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_2.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_3.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_5.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_10.txt', ...
'external_data/ITU_R_P453_14_data/NWET_Annual_20.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_30.txt',  'external_data/ITU_R_P453_14_data/NWET_Annual_50.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_60.txt', ...
'external_data/ITU_R_P453_14_data/NWET_Annual_70.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_80.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_90.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_95.txt', 'external_data/ITU_R_P453_14_data/NWET_Annual_99.txt'};
P_scope = [0.1 0.2 0.3 0.5 1 2 3 5 10 20 30 50 60 70 80 90 95 99]; % Different exceedance probability values for annual surface total pressure in ITU_R_2145
P_index = find(P_scope == p);
if ~isempty(P_index) % Desired exceedance probability is in the exceedance probability data table
    nwetData = readNwetData(P_scope_P_filenames,P_index,241,481); 
    Nwet1 = nwetData(Latitude_lowerIndex, Longitude_lowerIndex);
    Nwet2 = nwetData(Latitude_lowerIndex, Longitude_upperIndex);
    Nwet3 = nwetData(Latitude_upperIndex, Longitude_lowerIndex);
    Nwet4 = nwetData(Latitude_upperIndex, Longitude_upperIndex);
    Nwet = CCDF(Nwet1, Nwet2, Nwet3, Nwet4, Latitude_lowerIndex, Longitude_lowerIndex);
else 
    [P_below_index, P_above_index] = dataQueries(p, P_scope); % Use spatial and statistical (CCDF) interpolation methods to get the data corresponding to the desired exceedance probability
    nwetData = readNwetData(P_scope_P_filenames,P_below_index,241,481);
    Nwet1 = nwetData(Latitude_lowerIndex, Longitude_lowerIndex);
    Nwet2 = nwetData(Latitude_lowerIndex, Longitude_upperIndex);
    Nwet3 = nwetData(Latitude_upperIndex, Longitude_lowerIndex);
    Nwet4 = nwetData(Latitude_upperIndex, Longitude_upperIndex);
    Nwet_below = CCDF(Nwet1, Nwet2, Nwet3, Nwet4, Latitude_lowerIndex, Longitude_lowerIndex);
    nwetData = readNwetData(P_scope_P_filenames,P_above_index,241,481);
    Nwet1 = nwetData(Latitude_lowerIndex, Longitude_lowerIndex);
    Nwet2 = nwetData(Latitude_lowerIndex, Longitude_upperIndex);
    Nwet3 = nwetData(Latitude_upperIndex, Longitude_lowerIndex);
    Nwet4 = nwetData(Latitude_upperIndex, Longitude_upperIndex);
    Nwet_above = CCDF(Nwet1, Nwet2, Nwet3, Nwet4, Latitude_lowerIndex, Longitude_lowerIndex);
    Nwet = Nwet_below + ((p - P_scope(P_below_index)) / (P_scope(P_above_index) - P_scope(P_below_index))) * (Nwet_above - Nwet_below);
end 
end
function expectationValue = CCDF(d1,d2,d3,d4,Latitude_lowerIndex,Longitude_lowerIndex)
% Function: According to Annex 1 of ITU_R_P1144_12, calculate the expected value of the data parameter using bilinear interpolation method on a square grid
% Inputs:
% d1,d2,d3,d4: Four different data parameter values
% latitudeLowerIndex,longitudeLowerIndex: Row index and column index corresponding to latitude and longitude
% Returns:
% expectationValue: The expected value obtained after interpolation

r = Latitude_lowerIndex+(0.5);
c = Longitude_lowerIndex+(0.5);
R = Latitude_lowerIndex;
C = Longitude_lowerIndex;
expectationValue = d1*((R+1-r)*(C+1-c))+d3*((r-R)*(C+1-c))+d2*((R+1-r)*(c-C))+d4*((r-R)*(c-C));
end
function Data = readNwetData(P_scope_P_filenames,p,rows,cols)
    % Use a switch statement to map p to the corresponding file index
    switch p
        case 1
            filename = P_scope_P_filenames{1};
        case 2
            filename = P_scope_P_filenames{2};
        case 3
            filename = P_scope_P_filenames{3};
        case 4
            filename = P_scope_P_filenames{4};
        case 5
            filename = P_scope_P_filenames{5};
        case 6
            filename = P_scope_P_filenames{6};
        case 7
            filename = P_scope_P_filenames{7};
        case 8
            filename = P_scope_P_filenames{8};
        case 9
            filename = P_scope_P_filenames{9};
        case 10
            filename = P_scope_P_filenames{10};
        case 11
            filename = P_scope_P_filenames{11};
        case 12
            filename = P_scope_P_filenames{12};
        case 13
            filename = P_scope_P_filenames{13};
        case 14
            filename = P_scope_P_filenames{14};
        case 15
            filename = P_scope_P_filenames{15};
        case 16
            filename = P_scope_P_filenames{16};
        case 17
            filename = P_scope_P_filenames{17};
        case 18
            filename = P_scope_P_filenames{18};
        otherwise
            error('Unknown exceedance probability: %f', p);
    end     
    fileID = fopen(filename, 'r');      % Open the file
    if fileID == -1
        error('Unable to open file: %s', filename);
    end
    % Assume the file contains floating-point numbers, read the data into a matrix
    Data = fscanf(fileID, '%f', [cols,rows])'; 
    fclose(fileID);                     % Close the file
end

