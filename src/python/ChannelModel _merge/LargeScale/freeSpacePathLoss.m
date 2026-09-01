function [FSPL] = freeSpacePathLoss(parameter,losEOA)
% Function: Calculate the free space path loss (FSPL) according to Equation (6.6-2) in 3GPP TR 38.811 V15.4.0 (2020-09)
% Input values:
% satelliteHeight: Satellite height
% fc: Frequency, EOA: Elevation angle 
% Output values:
% FSPL: Free space path loss value

    % 🌟 修复：直接定义地球半径常数，彻底抛弃不稳定的 global
    Re = 6371e3; 
    
    satelliteHeight = parameter.satelliteHeight;
    fc = parameter.fc;
    derad = pi / 180;                                        % Convert degrees to radians
    
    % Calculate the slant range between the satellite and the ground terminal
    slantRange = sqrt((Re)^2 * (sin(losEOA * derad))^2 + (satelliteHeight)^2 + 2 * satelliteHeight * Re)...     
                  - (Re * sin(losEOA * derad));              
                  
    % Calculate the free space path loss value
    FSPL = 32.45 + 20 * log10(fc) + 20 * log10(slantRange);  
end