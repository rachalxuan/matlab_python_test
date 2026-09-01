function AC = cloudLoss(parameter, phi)

    expectationP = 5;
    T_cloud = 271.15;
    p = expectationP;
    f = parameter.fc;
    theta = 300 / T_cloud;                                                         % Define angle
    Epsilon_0 = 77.66 + 103.3 * (theta - 1);                                       % Calculate dielectric constant related parameters
    Epsilon_1 = 0.0671 * Epsilon_0;
    Epsilon_2 = 3.52;
    fp = 20.2 - 146 * (theta - 1) + 316 * (theta - 1)^2;                           % Calculate frequency related parameters
    fs = 39.8 * fp;
    Epsilon_p = (Epsilon_0 - Epsilon_1) / (1 + (f / fp)^2) + ...                   % Calculate Epsilon_p and Epsilon_pp
                (Epsilon_1 - Epsilon_2) / (1 + (f / fs)^2) + Epsilon_2;
    Epsilon_pp = f * (Epsilon_0 - Epsilon_1) / (fp * (1 + (f / fp)^2)) + ...
                 f * (Epsilon_1 - Epsilon_2) / (fs * (1 + (f / fs)^2));
    eta = (2 + Epsilon_p) / Epsilon_pp;                                            % Calculate eta
    Kl = 0.819 * f / (Epsilon_pp * (1 + eta^2));                                   % Calculate Kl
    Lred = computeLred(p, parameter);
    AC = Lred * Kl / sin(phi * pi / 180);
end

function Lred = computeLred(p,parameter)
% Function: According to Section 2 of (ITU-R) P.2145-0, calculate the annual total (atmospheric) surface pressure,
% annual surface water vapor partial pressure, annual dry surface pressure, annual surface temperature,
% annual surface integrated water vapor density, and annual water vapor content corresponding to different exceedance probabilities.
% Inputs:
% p: Desired exceedance frequency
% terminalLatitude: Latitude, terminalLongitude: Longitude
% Returns:
% Lred: The total columnar content of liquid water at probability p when the temperature drops to 273.15 K (kg/m^2 or equivalent millimeters)
terminalLongitude = parameter.terminalLongitude;
terminalLatitude =  parameter.terminalLatitude;
latitudeScope = -90:1.125:90;                                             % Latitude range
longitudeScope = -180:1.125:180;                                          % Longitude range
[Latitude_lowerIndex,Latitude_upperIndex] = dataQueries(terminalLatitude,latitudeScope);      % Using spatial and statistical (CCDF) interpolation method to obtain the range of the target latitude
[Longitude_lowerIndex,Longitude_upperIndex] = dataQueries(terminalLongitude,longitudeScope);   % Using spatial and statistical (CCDF) interpolation method to obtain the range of the target longitude
P_scope_P_filenames = {'external_data/ITU_R_P840_8_data/Lred_01_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_02_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_03_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_05_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_1_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_2_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_3_v4.txt',  'external_data/ITU_R_P840_8_data/Lred_10_v4.txt',... 
                        'external_data/ITU_R_P840_8_data/Lred_20_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_30_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_50_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_60_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_70_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_80_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_90_v4.txt', ...
                        'external_data/ITU_R_P840_8_data/Lred_95_v4.txt', 'external_data/ITU_R_P840_8_data/Lred_99_v4.txt'};

P_scope = [0.1 0.2 0.3 0.5 1 2 3 10 20 30 50 60 70 80 90 95 99];% Different exceedance probabilities of annual surface total pressure in ITU_R_2145
P_index = find( P_scope == p);
if ~isempty(P_index) % If the desired exceedance probability is in the exceedance probability data table

    lredData = readLredData(P_scope_P_filenames, P_index, 161 ,321);
    Lred1 = lredData(Latitude_lowerIndex,Longitude_lowerIndex);
    Lred2 = lredData(Latitude_lowerIndex,Longitude_upperIndex);
    Lred3 = lredData(Latitude_upperIndex,Longitude_lowerIndex);
    Lred4 = lredData(Latitude_upperIndex,Longitude_upperIndex);
    Lred= CCDF(Lred1,Lred2,Lred3,Lred4,Latitude_lowerIndex,Longitude_lowerIndex);
else
    [P_below_index,P_above_index] = dataQueries(p,P_scope); % Using the spatial and statistical (CCDF) interpolation method in ITU_R_1511 to obtain the data corresponding to the desired exceedance probability

    lredData = readLredData(P_scope_P_filenames, P_below_index, 161 ,321);
    Lred1 = lredData(Latitude_lowerIndex,Longitude_lowerIndex);
    Lred2 = lredData(Latitude_lowerIndex,Longitude_upperIndex);
    Lred3 = lredData(Latitude_upperIndex,Longitude_lowerIndex);
    Lred4 = lredData(Latitude_upperIndex,Longitude_upperIndex);
    Lred_below= CCDF(Lred1,Lred2,Lred3,Lred4,Latitude_lowerIndex,Longitude_lowerIndex);
  
    lredData = readLredData(P_scope_P_filenames, P_above_index, 161 ,321);
    Lred1 = lredData(Latitude_lowerIndex,Longitude_lowerIndex);
    Lred2 = lredData(Latitude_lowerIndex,Longitude_upperIndex);
    Lred3 = lredData(Latitude_upperIndex,Longitude_lowerIndex);
    Lred4 = lredData(Latitude_upperIndex,Longitude_upperIndex);
    Lred_above= CCDF(Lred1,Lred2,Lred3,Lred4,Latitude_lowerIndex,Longitude_lowerIndex);
    Lred=Lred_below+((p-P_scope(P_below_index))/(P_scope(P_above_index)-P_scope(P_below_index)))*(Lred_above-Lred_below);
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

function Data = readLredData(P_scope_P_filenames, p ,rows,cols)
    % 使用 switch 映射 p 到对应的文件索引
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
