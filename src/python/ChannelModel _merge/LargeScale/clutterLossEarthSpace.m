function L_ces = clutterLossEarthSpace(fc_GHz, theta_deg, p_percent)
% clutterLossEarthSpace
% 地-空/地-卫星地物损耗统计模型（结果固定截断到不小于0 dB）

    validateattributes(fc_GHz,   {'numeric'}, {'real','positive'});
    validateattributes(theta_deg, {'numeric'}, {'real','>=',0,'<=',90});
    validateattributes(p_percent, {'numeric'}, {'real','>',0,'<',100});

    A1 = 0.05;
    K1 = 93 .* (fc_GHz .^ 0.175);

    angle_rad = A1 .* (1 - theta_deg ./ 90) + pi .* theta_deg ./ 180;

    % 逆补正态分布函数
    Qinv = sqrt(2) .* erfcinv(2 .* (p_percent ./ 100));

    baseTerm = -K1 .* log(1 - p_percent ./ 100) .* cot(angle_rad);
    exponent = 0.5 .* (90 - theta_deg) ./ 90;

    L_ces = baseTerm .^ exponent - 1 - 0.6 .* Qinv;

    % 固定截断
    L_ces = max(L_ces, 0);
end