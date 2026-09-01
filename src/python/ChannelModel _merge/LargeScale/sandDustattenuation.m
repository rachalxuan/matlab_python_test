function [A_sd] = sandDustattenuation(parameter)

% Function: Compute the sand and dust attenuation
% Input values:
% parameter: Parameter settings
% Return values:
% A_sd: The sand and dust attenuation

    fc = parameter.fc;
    c = parameter.c;
    lamda = c / (fc * (1e9));
    rho = 2.65e6;         % Sand and dust density, g/m3
    L = 10;               % The length of the path through sand and dust
    otherPara = 0.01;     % Dry sand and dust, visibility 100m: 0.01,Damp sand and dust, water vapor content 20%: 0.14
    A_sd = (2.456e5 * otherPara * L ) / (lamda * rho);  % Sand and dust attenuation, equation (308) of GJB/Z 87-97
end


