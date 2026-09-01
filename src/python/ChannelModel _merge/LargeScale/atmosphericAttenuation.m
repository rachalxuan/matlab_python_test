
function [Atotal] = atmosphericAttenuation(parameter,losEOA)
 
% Function: Compute atmospheric attenuation, calculate oxygen gas attenuation according to (ITU-R) P.676-13 Annex 2 Equation (32), and calculate water vapor gas attenuation according to (ITU-R) P.676 Annex 2 Equation (40), summing the oxygen gas and water vapor gas attenuation to get atmospheric attenuation
% Input values:
% terminalLatitude: Latitude, terminalLongitude: Longitude
% fc: Frequency, losEOA: Elevation angle, expectationP: Expected exceedance probability
% Return values:
% Atotal: Atmospheric attenuation value
    derad = pi/180;
    expectationP = 5;
    terminalLatitude = parameter.terminalLatitude;
    terminalLongitude = parameter.terminalLongitude;
    fc = parameter.fc;
    %% Data import        
   table1 = readData('external_data/ITU_R_P676_13_data/table1.txt', 44, 7);
   data1= readData('external_data/ITU_R_P676_13_data/data1.txt', 700, 5);
   data2= readData('external_data/ITU_R_P676_13_data/data2.txt', 699, 5);
   Pmean = readData('external_data/ITU_R_2145_0_data/P_Annual/P_mean.txt', 73, 137);
   RHOmean = readData('external_data/ITU_R_2145_0_data/RHO_Annual/RHO_mean.txt', 73, 137);
   Tmean= readData('external_data/ITU_R_2145_0_data/T_Annual/T_mean.txt', 73, 137);
   Vsmean= readData('external_data/ITU_R_2145_0_data/V_Annual/V_mean.txt', 73, 137);
    
    %% Calculate oxygen attenuation
    % Obtain the parameters needed in Equation (32) of Annex 1 of ITU-R P.676 from the data table
    f0 = table1(:,1); 
    a1 = table1(:,2);
    a2 = table1(:,3);
    a3 = table1(:,4);
    a4 = table1(:,5);
    a5 = table1(:,6);
    a6 = table1(:,7);
    % Obtain annual average data using the explanation in Table 2 of ITU-R P.2145-0
    
    [averageP,averageEs,averagePs,averageTs,average_RHO,averageVs] = atmosphericAttenuationParameter(terminalLatitude,terminalLongitude,Pmean,RHOmean,Tmean,Vsmean);
    theta = (300 /(averageTs)) + 0 * 1i;
    [pP,pTs,pRHO,pVs] =...                                                                          % Interpolate the expected parameters at the desired location through p interpolation
    computeExpectationPData(expectationP,terminalLatitude,terminalLongitude);
    lengthIndex = length(f0);
    tempData = zeros(1,lengthIndex);
    for iIndex = 1:1:lengthIndex
         Si = a1(iIndex) * (1e-7) * averagePs * (theta)^3 * exp(a2(iIndex) * (1 - (theta)));        % Calculate the oxygen spectral line strength Si, using Equation (3) in Annex 1 of ITU-R P.676-13
         fi = f0(iIndex);                                                                           % fi is the oxygen spectral line frequency, given by Equation (5) in Annex 1 of ITU-R P.676-13
         deltaf = a3(iIndex) * (1e-4) * (averagePs * ((theta)^(0.8-a4(iIndex))) + 1.1 * averageEs * (theta)); % Calculate the oxygen spectral line width, using Equation (6a) in Annex 1 of ITU-R P.676-13
         deltaf = sqrt(deltaf^2 + 2.25 * (1e-6));                                                   % Modify the spectral line width delta_f, taking into account the Zeeman splitting of the oxygen spectral line, using Equation (6b) in Annex 1 of ITU-R P.676-13
         delta = (a5(iIndex) + a6(iIndex) * (theta)) * (1e-4) * (averagePs + averageEs) * (theta)^(0.8);      % Due to interference in the oxygen line, delta is a correction factor, using Equation (7) in Annex 1 of ITU-R P.676-13
         Fi = (fc/fi) * (((deltaf - delta * (fi - fc)) / ((fi-fc)^2 + deltaf^2)) + ((deltaf - delta*(fi + fc)) / ((fi + fc)^2 + deltaf^2)));  % Calculate the spectral line shape factor Fi, given by Equation (5) in Annex 1 of ITU-R P.676-13
         tempData(iIndex) = real(Fi * Si);
    end
    sumSiFi = sum(tempData);
    d = 5.6 * (1e-4) * (averagePs + averageEs) * (theta^(0.8));       % d is the width parameter in the Debye spectrum, calculated using Equation (9) in Annex 1 of ITU-R P.676-13
    ND = fc * averagePs * theta^2 * (((6.14 * (1e-5)) / (d * (1 + (fc / d)^2))) + ((1.4 * (1e-12) * averagePs * (theta^1.5)) / (1 + (1.9 * (1e-5) * (fc^1.5))))); % The dry air continuum from the non-resonant Debye spectrum of oxygen below 10 GHz and the nitrogen attenuation caused by air pressure above 100 GHz, using Equation (8) in Annex 1 of ITU-R P.676-13
    nOxygey = sumSiFi + ND;                                           % The imaginary part of the complex refractive index at this frequency, using Equation (2a) in Annex 1 of ITU-R P.676-13
    rOxygen = 0.1820 * fc * nOxygey;                                  % The gas attenuation caused by oxygen, unit is dB/km
    [a0,b0,c0,d0] = computeParameter(data1,fc);
    hOxygen = a0 + b0 * pTs + c0 * pP + d0 * pRHO;                    % Using Equation (33) in Annex 2 of ITU-R P.676-13
    Ao = (rOxygen * hOxygen) / sin(losEOA * derad);                   % Predicted statistical gas attenuation caused by oxygen on the inclined path A0, using Equation (32) in Annex 2 of ITU-R P.676-13    
    %% Calculate water vapor gas attenuation
    % The coefficients av, bv, cv, and dv for the relevant frequency should be linearly interpolated between the frequencies in the first data file
    [av,bv,cv,dv] = computeParameter(data2,fc);
    Kv = av + bv * average_RHO + cv * averageTs + dv * averageP;     % Calculate the parameter of water vapor fading using Equation (41) in Annex 2 of ITU-R P.676-13
    Aw = (Kv * pVs) / (sin(losEOA * derad));                         % The statistical gas attenuation caused by water vapor on the inclined path Aw, calculated using Equation (40) in Annex 2 of ITU-R P.676-13
    Atotal = Ao + Aw;                                                % Net inclined path gas attenuation, which is the sum of the inclined path gas attenuation caused by oxygen Ao and the inclined path gas attenuation caused by water vapor Aw
end


function [a,b,c,d] = computeParameter(data,fc)

% Function: Calculate the coefficients in Equations (32) and (40) based on the data files Part 1 and Part 2 from Section 1.2 of Annex 2 in ITU-R P.676-13
% Input values:
% data: Data file Part 1 or Part 2 from Section 1.2 of Annex 2 in ITU-R P.676-13
% fc: Frequency
% Return values:
% a,b,c,d: Coefficient values in Equations (32) and (40)
 
       if(fc >= 1e9)                      % Ensure the frequency in different units meets the code numerical judgment requirements
           fc = fc/1e9;
        else
           fc = fc;
        end
        % Use interpolation to obtain the coefficient values at the corresponding frequency
        a = interp1(data(:,1),data(:,2), fc, 'linear');
        b = interp1(data(:,1),data(:,3), fc, 'linear');
        c = interp1(data(:,1),data(:,4), fc, 'linear');
        d = interp1(data(:,1),data(:,5), fc, 'linear');
end


function [expectationPP,expectationPTs,expectationPRHO,expectationPVs] = computeExpectationPData(expectationP,terminalLatitude,terminalLongitude)
  
% Function: According to Section 2 of (ITU-R) P.2145-0, calculate the annual total (atmospheric) surface pressure corresponding to different exceedance probabilities,
% annual surface water vapor partial pressure, annual dry surface pressure, annual surface temperature, annual surface integrated water vapor density, and annual water vapor content
% Input values:
% expectationP: Expected exceedance probability
% terminalLatitude: Latitude, terminalLongitude: Longitude
% Return values:
% expectationPP: Annual total (atmospheric) surface pressure corresponding to exceedance probability P, unit is hPa
% expectationPTs: Annual surface temperature corresponding to exceedance probability P, unit is K
% expectationPRHO: Annual surface integrated water vapor density corresponding to exceedance probability P, unit is g/m^3
% expectationPVs: Annual water vapor content corresponding to exceedance probability P, unit is kg/m^2 or mm
                                                              
   % Different data file names corresponding to different exceedance probabilities for annual surface total pressure in ITU_R_2145                                          
    pScopePFilenames = {'external_data/ITU_R_2145_0_data/P_Annual/P_001.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_002.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_003.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_005.txt',...
                    'external_data/ITU_R_2145_0_data/P_Annual/P_01.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_02.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_03.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_05.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_1.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_2.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_3.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_5.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_10.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_20.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_30.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_50.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_60.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_70.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_80.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_90.txt',... 
                    'external_data/ITU_R_2145_0_data/P_Annual/P_95.txt', 'external_data/ITU_R_2145_0_data/P_Annual/P_99.txt'};                                    
    % Different data file names corresponding to different exceedance probabilities for annual surface water vapor density in ITU_R_2145  
pScopeRHOFilenames = {'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_001.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_002.txt',... 
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_003.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_005.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_01.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_02.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_03.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_05.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_1.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_2.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_3.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_5.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_10.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_20.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_30.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_50.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_60.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_70.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_80.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_90.txt',...
                     'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_95.txt', 'external_data/ITU_R_2145_0_data/RHO_Annual/RHO_99.txt'};

     % Different data file names corresponding to different exceedance probabilities for annual surface temperature in ITU_R_2145
   pScopeTsFilenames = {'external_data/ITU_R_2145_0_data/T_Annual/T_001.txt','external_data/ITU_R_2145_0_data/T_Annual/T_002.txt',...  
                     'external_data/ITU_R_2145_0_data/T_Annual/T_003.txt','external_data/ITU_R_2145_0_data/T_Annual/T_005.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_01.txt','external_data/ITU_R_2145_0_data/T_Annual/T_02.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_03.txt','external_data/ITU_R_2145_0_data/T_Annual/T_05.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_1.txt','external_data/ITU_R_2145_0_data/T_Annual/T_2.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_3.txt','external_data/ITU_R_2145_0_data/T_Annual/T_5.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_10.txt','external_data/ITU_R_2145_0_data/T_Annual/T_20.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_30.txt','external_data/ITU_R_2145_0_data/T_Annual/T_50.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_60.txt','external_data/ITU_R_2145_0_data/T_Annual/T_70.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_80.txt','external_data/ITU_R_2145_0_data/T_Annual/T_90.txt',... 
                     'external_data/ITU_R_2145_0_data/T_Annual/T_95.txt','external_data/ITU_R_2145_0_data/T_Annual/T_99.txt'};

     % ITU_R_2145中年度地表综合水蒸气含量不同超越概率对应的不同数据文件名称
   pScopeVsFilenames = {'external_data/ITU_R_2145_0_data/V_Annual/V_001.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_002.txt',...  
                     'external_data/ITU_R_2145_0_data/V_Annual/V_003.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_005.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_01.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_02.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_03.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_05.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_1.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_2.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_3.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_5.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_10.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_20.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_30.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_50.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_60.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_70.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_80.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_90.txt',... 
                     'external_data/ITU_R_2145_0_data/V_Annual/V_95.txt', 'external_data/ITU_R_2145_0_data/V_Annual/V_99.txt'};


    pScope = [0.01 0.02 0.03 0.05 0.1 0.2 0.3 0.5 1 2 3 5 10 20 30 50 60 70 80 90 95 99]; % Different exceedance probability values for annual surface total pressure in ITU_R_2145     
    pIndex = find( pScope == expectationP);
    if ~isempty(pIndex)                                          % If the expected exceedance probability is in the exceedance probability data table
       pPData = readFileData(pScopePFilenames,pIndex,73, 137);            % Obtain the annual total (atmospheric) surface pressure at the corresponding exceedance probability P using ITU-R P.2145-0 Table 2
       pRHOData = readFileData(pScopeRHOFilenames,pIndex,73, 137);        % Obtain the annual surface water vapor density at the corresponding exceedance probability P using ITU-R P.2145-0 Table 2
       pTsData = readFileData(pScopeTsFilenames,pIndex,73, 137);          % Obtain the annual surface temperature at the corresponding exceedance probability P using ITU-R P.2145-0 Table 2
       pVsdata = readFileData(pScopeVsFilenames,pIndex,73, 137);          % Obtain the annual surface integrated water vapor content at the corresponding exceedance probability P using ITU-R P.2145-0 Table 2 
       
       [pP,pEs,pPs,pTs,pRHO,pVs] = atmosphericAttenuationParameter(terminalLatitude,terminalLongitude,pPData,pRHOData,pTsData,pVsdata);
       expectationPP = pP;                                        % The annual total (atmospheric) surface pressure at the expected exceedance probability
       expectationPRHO = pRHO;                                    % The annual surface water vapor density at the expected exceedance probability
       expectationPTs = pTs;                                      % The annual surface temperature at the expected exceedance probability
       expectationPVs = pVs;                                      % The annual surface integrated water vapor content at the expected exceedance probability 
       expectationPEs = (expectationPRHO*expectationPTs) / 216.7; % The surface water vapor partial pressure at the expected exceedance probability, unit is hPa, calculated using the content of ITU-R P.676-13 Annex 2 Equation (32)
       expectationPPs = expectationPP-expectationPEs;             % The dry surface pressure at the expected exceedance probability, unit is hPa, calculated using the content of ITU-R P.676-13 Annex 2 Equation (32)
    else                                                                
       [pBelowIndex,pAboveIndex] = dataQueries(expectationP,pScope); % Using the spatial and statistical (CCDF) interpolation method from ITU_R_1511, obtain the data corresponding to the expected exceedance probability
       pBelowPData = readFileData(pScopePFilenames,pBelowIndex,73, 137);        
       pAbovePsData = readFileData(pScopePFilenames,pAboveIndex,73, 137);
       pBelowRHOData = readFileData(pScopeRHOFilenames,pBelowIndex,73, 137);
       pAboveRHOData = readFileData(pScopeRHOFilenames,pAboveIndex,73, 137);
       pBelowTsData = readFileData(pScopeTsFilenames,pBelowIndex,73, 137);
       pAboveTsData = readFileData(pScopeTsFilenames,pAboveIndex,73, 137);
       pBelowVsData = readFileData(pScopeVsFilenames,pBelowIndex,73, 137);
       pAboveVsData = readFileData(pScopeVsFilenames,pAboveIndex,73, 137);
       % Calculate the parameters below and above the expected exceedance probability using the spatial and statistical (mean and standard deviation) method from ITU_R_P2145  
       [pBelowP,pBelowEs,pBelowPs,pBelowTs,pBelowRHO,pBelowVs] = atmosphericAttenuationParameter(terminalLatitude,terminalLongitude,pBelowPData,pBelowRHOData,pBelowTsData,pBelowVsData);
       [pAboveP,pAboveEs,pAbovePs,pAboveTs,pAboveRHO,pAboveVs] = atmosphericAttenuationParameter(terminalLatitude,terminalLongitude,pAbovePsData,pAboveRHOData,pAboveTsData,pAboveVsData);
       % Use the spatial and statistical (mean and standard deviation) interpolation method from ITU_R_P2145 to calculate the parameters at the expected exceedance probability   
       expectationPP = pBelowP+((expectationP-pScope(pBelowIndex))/(pScope(pAboveIndex)-pScope(pBelowIndex)))*(pAboveP-pBelowP);                          
       expectationPRHO = pBelowRHO+((expectationP-pScope(pBelowIndex))/(pScope(pAboveIndex)-pScope(pBelowIndex)))*(pAboveRHO-pBelowRHO);
       expectationPTs = pBelowTs+((expectationP-pScope(pBelowIndex))/(pScope(pAboveIndex)-pScope(pBelowIndex)))*(pAboveTs-pBelowTs);
       expectationPVs = pBelowVs+((expectationP-pScope(pBelowIndex))/(pScope(pAboveIndex)-pScope(pBelowIndex)))*(pAboveVs-pBelowVs);
       expectationPEs = (expectationPRHO*expectationPTs)/216.7;             
       expectationPPs = expectationPP-expectationPEs;                          
    end  
end



function [computeP,computeEs,computePs,computeTs,computeRHO,computeVs] = atmosphericAttenuationParameter(terminalLatitude,terminalLongitude,dataP,dataRHO,dataTs,dataVs)
    
% Function: According to Section 2 of (ITU-R) P.2145-0, calculate the annual average total (atmospheric) surface pressure,
% annual average surface water vapor partial pressure, annual average dry surface pressure, annual average surface temperature, annual average surface integrated water vapor density, and annual average water vapor content.
% Input values:
% terminalLatitude: Latitude, terminalLongitude: Longitude
% dataP: Annual total (atmospheric) surface pressure data from ITU-R P.2145
% dataRHO: Annual surface water vapor density from ITU-R P.2145
% dataTs: Annual total (atmospheric) surface temperature data from ITU-R P.2145
% dataVs: Annual surface water vapor content data from ITU-R P.2145
% Return values:
% computeP: Total (atmospheric) surface pressure, unit is hPa
% computeEs: Surface water vapor partial pressure, unit is hPa
% computePs: Dry surface pressure, unit is hPa
% computeTs: Surface temperature, unit is K
% computeRHO: Surface water vapor density, unit is g/m^3
% computeVs: Water vapor content, unit is kg/m^2 or mm

    
    dataZGround = readData('external_data/ITU_R_2145_0_data/P_Annual/P_Z_ground.txt', 73, 137); % The height above sea level for the location with an exceedance probability of 5%, unit is m, data obtained using the explanation in ITU-R P.2145-0 Table 2       
    dataPSCH = readData('external_data/ITU_R_2145_0_data/P_Annual/PSCH.txt',73, 137);           % The surface pressure ratio height for the location with an exceedance probability of 5%, obtained using the explanation in ITU-R P.2145-0 Table 2 
    dataRHOVSCH = readData('external_data/ITU_R_2145_0_data/RHO_Annual/RHO_VSCH.txt',73, 137);  % The water vapor density ratio height for the location with an exceedance probability of 5%, obtained using the explanation in ITU-R P.2145-0 Table 2 
    dataTSCH = readData('external_data/ITU_R_2145_0_data/T_Annual/TSCH.txt', 73, 137);          % The temperature ratio height for the location with an exceedance probability of 5%, obtained using the explanation in ITU-R P.2145-0 Table 2 
    dataVSCH = readData('external_data/ITU_R_2145_0_data/V_Annual/Vs_VSCH.txt', 73, 137);       % The water vapor content ratio height for the location, obtained using the explanation in ITU-R P.2145-0 Table 4


    latitudeScope = linspace(18, 54, 73);                                                                  % Set the latitude range according to the data in the ITU-R P.2145-0 file
    longitudeScope = linspace(73, 135, 137);                                                               % Set the longitude range according to the data in the ITU-R P.2145-0 file
    latitudeLowerIndex = 0;
    latitudeUpperIndex = 0;
    longitudeLowerIndex = 0;
    longitudeUpperIndex = 0;
    [latitudeLowerIndex,latitudeUpperIndex] = dataQueries(terminalLatitude,latitudeScope);     % Obtain the range where the target latitude is located
    [longitudeLowerIndex,longitudeUpperIndex] = dataQueries(terminalLongitude,longitudeScope); % Obtain the range where the target longitude is located  
    
    topoData0 = readData('external_data/ITU_R_P1511_3_data/ChinaTopo.dat',432,744);              % Read the topographic height data from ITU-R P.1511, with a latitude and longitude increment of 1/12 degree
    topoData = flipud(topoData0)./1000;                                         % Use the flipud function to flip the matrix
    lat = linspace(18, 54, 432);                                                % Latitude from -90 degrees to 90 degrees, increment of 1/12 degree
    lon = linspace(73, 135, 744);                                              % Longitude from -180 degrees to 180 degrees, increment of 1/12 degree
    topoDataTrimmed = topoData;                             
    [longitudeTrim, latitudeTrim] = meshgrid(lon(1:end), lat(1:end));           % Ensure the grid size matches topoDataTrimmed
    hs = interp2(longitudeTrim, latitudeTrim, topoDataTrimmed, terminalLongitude, terminalLatitude, 'cubic');   % Perform interpolation, note that LON and LAT here should be complete grids for interpolation queries
    alt = hs;    
    if all(latitudeLowerIndex == latitudeUpperIndex) && all(longitudeLowerIndex == longitudeUpperIndex)
         computeP = dataP(latitudeLowerIndex,longitudeUpperIndex);      % Global annual average reference average total (atmospheric) surface pressure at the desired location, unit is hPa, data read directly from the data table
         computeRHO = dataRHO(latitudeLowerIndex,longitudeUpperIndex);  % Global annual average reference average surface water vapor density at the desired location, unit is g/m^3, data read directly from the data table
         computeTs = dataTs(latitudeLowerIndex,longitudeUpperIndex);    % Global annual average reference average surface temperature at the desired location, unit is K, data read directly from the data table
         computeVs = dataVs(latitudeLowerIndex,longitudeUpperIndex);  
    else                                                                % If there is no information for the target location's latitude and longitude, calculate the four coordinate points through linear interpolation according to ITU-R P.2145-0 Section 2.1
         [gridP1] = computePsGrid(dataP,alt,dataZGround,dataPSCH,latitudeLowerIndex,longitudeLowerIndex); 
         [gridP2] = computePsGrid(dataP,alt,dataZGround,dataPSCH,latitudeLowerIndex,longitudeUpperIndex);
         [gridP3] = computePsGrid(dataP,alt,dataZGround,dataPSCH,latitudeUpperIndex,longitudeLowerIndex);
         [gridP4] = computePsGrid(dataP,alt,dataZGround,dataPSCH,latitudeUpperIndex,longitudeUpperIndex);
         [computeP] = CCDF(gridP1,gridP2,gridP3,gridP4,latitudeLowerIndex,longitudeLowerIndex);   
         [gridRHO1] = computeRHOGrid(dataRHO,alt,dataZGround,dataRHOVSCH,latitudeLowerIndex,longitudeLowerIndex);
         [gridRHO2] = computeRHOGrid(dataRHO,alt,dataZGround,dataRHOVSCH,latitudeLowerIndex,longitudeUpperIndex);
         [gridRHO3] = computeRHOGrid(dataRHO,alt,dataZGround,dataRHOVSCH,latitudeUpperIndex,longitudeLowerIndex);
         [gridRHO4] = computeRHOGrid(dataRHO,alt,dataZGround,dataRHOVSCH,latitudeUpperIndex,longitudeUpperIndex);
         [computeRHO] = CCDF(gridRHO1,gridRHO2,gridRHO3,gridRHO4,latitudeLowerIndex,longitudeLowerIndex);
         [gridTs1] = computeTsGrid(dataTs,alt,dataZGround,dataTSCH,latitudeLowerIndex,longitudeLowerIndex);
         [gridTs2] = computeTsGrid(dataTs,alt,dataZGround,dataTSCH,latitudeLowerIndex,longitudeUpperIndex);
         [gridTs3] = computeTsGrid(dataTs,alt,dataZGround,dataTSCH,latitudeUpperIndex,longitudeLowerIndex);
         [gridTs4] = computeTsGrid(dataTs,alt,dataZGround,dataTSCH,latitudeUpperIndex,longitudeUpperIndex);
         [computeTs] = CCDF(gridTs1,gridTs2,gridTs3,gridTs4,latitudeLowerIndex,longitudeLowerIndex); 
         [gridVs1] = computeVsGrid(dataVs,alt,dataZGround,dataVSCH,latitudeLowerIndex,longitudeLowerIndex);
         [gridVs2] = computeVsGrid(dataVs,alt,dataZGround,dataVSCH,latitudeLowerIndex,longitudeUpperIndex);
         [gridVs3] = computeVsGrid(dataVs,alt,dataZGround,dataVSCH,latitudeUpperIndex,longitudeLowerIndex);
         [gridVs4] = computeVsGrid(dataVs,alt,dataZGround,dataVSCH,latitudeUpperIndex,longitudeUpperIndex);
         [computeVs] = CCDF(gridVs1,gridVs2,gridVs3,gridVs4,latitudeLowerIndex,longitudeLowerIndex);    
    end   
         computeEs = (computeRHO*computeTs)/216.7;                % Global annual average reference average surface water vapor partial pressure, unit is hPa, calculated using the content of ITU-R P.676-13 Annex 2 Equation (32)
         computePs = computeP-computeEs;                          % Global annual average reference average dry surface pressure, unit is hPa, calculated using the content of ITU-R P.676-13 Annex 2 Equation (32)
end


function [gridP] = computePsGrid(dataP,alt,dataZGround,dataPSCH,terminalLatitude,terminalLongitude)

% Function: According to Section 2 of ITU_R_P2145_0, obtain the annual total (atmospheric) surface pressure data parameters at different latitudes and longitudes
% Input values:
% dataP: Annual total (atmospheric) surface pressure data from ITU_R_P2145_0
% alt: Topographic height data at different latitudes and longitudes from ITU-R P.1511
% dataZGround: Height above sea level from ITU_R_P2145_0
% dataPSCH: Surface pressure ratio height for different exceedance probabilities from ITU_R_P2145_0
% terminalLatitude, terminalLongitude: Latitude and longitude values of the terminal
% Return values:
% gridP: Total (atmospheric) surface pressure data at different latitudes and longitudes

         gridP = dataP(terminalLatitude,terminalLongitude)...
               * exp(-((alt - dataZGround(terminalLatitude,terminalLongitude)) / (dataPSCH(terminalLatitude,terminalLongitude))));
end

function [gridRHO] = computeRHOGrid(dataRHO,alt,dataZGround,dataVSCH,terminalLatitude,terminalLongitude)
 
% Function: According to Section 2 of ITU_R_P2145_0, obtain the annual water vapor density data parameters at different latitudes and longitudes
% Input values:
% dataRHO: Annual water vapor density data from ITU_R_P2145_0
% alt: Topographic height data at different latitudes and longitudes from ITU-R P.1511
% dataZGround: Height above sea level from ITU_R_P2145_0
% dataVSCH: Water vapor density ratio height for different exceedance probabilities from ITU_R_P2145_0
% terminalLatitude, terminalLongitude: Latitude and longitude values of the terminal
% Return values:
% gridRHO: Water vapor density data at different latitudes and longitudes

         gridRHO = dataRHO(terminalLatitude,terminalLongitude)...
               * exp(-((alt - dataZGround(terminalLatitude,terminalLongitude)) / (dataVSCH(terminalLatitude,terminalLongitude))));
end

function [gridTs] = computeTsGrid(dataTs,alt,dataZGround,dataTSCH,terminalLatitude,terminalLongitude)
        
% Function: According to Section 2 of ITU_R_P2145_0, obtain the annual surface temperature data parameters at different latitudes and longitudes
% Input values:
% dataTs: Annual surface temperature data from ITU_R_P2145_0
% alt: Topographic height data at different latitudes and longitudes from ITU-R P.1511
% dataZGround: Height above sea level from ITU_R_P2145_0
% dataTSCH: Surface temperature ratio height for different exceedance probabilities from ITU_R_P2145_0
% terminalLatitude, terminalLongitude: Latitude and longitude values of the terminal
% Return values:
% gridTs: Surface temperature data at different latitudes and longitudes

         gridTs = dataTs(terminalLatitude,terminalLongitude)...
               + ((dataTSCH(terminalLatitude,terminalLongitude)) * (alt-dataZGround(terminalLatitude,terminalLongitude)));
end


function [gridVs] = computeVsGrid(dataVs,alt,dataZGround,dataVSCH,terminalLatitude,terminalLongitude)
      
% Function: According to Section 2 of ITU_R_P2145_0, obtain the annual water vapor content data parameters at different latitudes and longitudes
% Input values:
% dataVs: Annual water vapor content data from ITU_R_P2145_0
% alt: Topographic height data at different latitudes and longitudes from ITU-R P.1511
% dataZGround: Height above sea level from ITU_R_P2145_0
% dataVSCH: Water vapor content ratio height for different exceedance probabilities from ITU_R_P2145_0
% terminalLatitude, terminalLongitude: Latitude and longitude values of the terminal
% Return values:
% gridVs: Surface temperature data at different latitudes and longitudes

     gridVs = dataVs(terminalLatitude,terminalLongitude)...
           * exp(-((alt - dataZGround(terminalLatitude,terminalLongitude)) / (dataVSCH(terminalLatitude,terminalLongitude))));
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




