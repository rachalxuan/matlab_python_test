function Abs = beamSpreadingLoss(theta0)
% beamSpreadingLoss - 计算波束扩散损耗
%
% 输入:
%   theta0 - 偏离波束中心的角度
% 输出:
%   Abs    - 波束扩散损耗 (dB)

    h = 1; 
    if theta0 >= 10 || h >= 3
        Abs = 0; 
        return; 
    end
    
    num = 0.5411 + 0.074466 * theta0 + h * (0.06272 + 0.0276 * theta0) + h^2 * 0.008288;
    den = 1.728 + 0.5411 * theta0 + 0.03723 * theta0^2 + h * (0.1815 + 0.06272 * theta0 + 0.01386 * theta0^2) + h^2 * (0.01727 + 0.008288 * theta0);
    B = 1 - num / (den)^2; 
    Abs = -10 * log10(B);
end