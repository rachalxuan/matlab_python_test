function [SF, CL] = shadowFadingClutterLoss(parameter, losEOA, N)
% shadowFadingClutterLoss - 融合 3GPP TR 38.811 与 ITU-R P.2108 的阴影与地物杂波损耗模型
%
% 输入:
%   parameter - 包含 fc, sceneIdx, channelMod, clutterModelType, p_percent 等的结构体
%   losEOA    - 视距仰角 (度)
%   N         - 生成的数据点数
% 输出:
%   SF        - 阴影衰落 (N x 1 向量)
%   CL        - 地物杂波损耗 (N x 1 向量)

    fc = parameter.fc; 
    sceneIdx = parameter.sceneIdx;
    
    if isfield(parameter, 'clutterModelType'), modelType = parameter.clutterModelType; else, modelType = 3; end % 默认Auto
    if isfield(parameter, 'p_percent'), p_percent = parameter.p_percent; else, p_percent = 50; end
    if(fc >= 1e9), fc_GHz = fc / 1e9; else, fc_GHz = fc; end

    % 判定是否为 3GPP 适用频段 (S/Ka)
    is_S_band = (fc_GHz >= 2 && fc_GHz <= 4);
    is_Ka_band = (fc_GHz >= 26.5 && fc_GHz <= 40);
    is_3gpp_supported = is_S_band || is_Ka_band;
    
    % 路由逻辑
    use_ITU_CL = false;
    if modelType == 2 % 强制 ITU
        use_ITU_CL = true;
    elseif modelType == 3 && ~is_3gpp_supported % Auto 模式下不满足频段，走 ITU兜底
        use_ITU_CL = true;
    end
    
    % --- 阴影衰落 SF 生成 (沿用 3GPP) ---
    try
        denseUrbanTable = readData('external_data/3GPP_TR_38_811_data/table6_6_2_1_dense_uburban.txt',9,7);        
        urbanTable = readData('external_data/3GPP_TR_38_811_data/table6_6_2_2_uburban.txt',9,7);         
        subRuralTable = readData('external_data/3GPP_TR_38_811_data/table6_6_2_3_suburban_rural.txt',9,7);  
    catch
        % 兜底：如果文件未找到，返回0
        SF = zeros(N,1); CL = zeros(N,1); return;
    end
    
    if (parameter.channelMod == 'C' || parameter.channelMod == 'D'), channelIdx = 1; else, channelIdx = 2; end
    if is_S_band, bandIdx = 1; else, bandIdx = 2; end % 借用 Ka 方差兜底
    
    diffs = abs(denseUrbanTable(:,1) - losEOA);
    [~, idx] = min(diffs);
    
    switch sceneIdx
        case 1, tableData = denseUrbanTable;
        case 2, tableData = urbanTable;
        case 3, tableData = subRuralTable;
        case 4, tableData = subRuralTable;
        otherwise, tableData = urbanTable;
    end
    
    [SF_3gpp, CL_3gpp] = computeSFCL(bandIdx, channelIdx, tableData, N, idx);
    SF = SF_3gpp; 
    
    % --- 杂波损耗 CL 生成 (ITU vs 3GPP) ---
    if use_ITU_CL
        if channelIdx == 1 % LOS 时无杂波
            CL = zeros(N, 1);
        else
            itu_cl_val = clutterLossEarthSpace(fc_GHz, losEOA, p_percent);
            CL = itu_cl_val * ones(N, 1);
        end
    else
        CL = CL_3gpp .* ones(N, 1); 
    end
end

% ==================== 局部辅助函数 ====================
function [SF1, CL1] = computeSFCL(bandIdx, channelIdx, tableData, N, idx)
% 3GPP 查表提取标准差并生成对数正态随机数
    if(bandIdx == 1) 
         if(channelIdx == 1) 
              sigmaSF = tableData(idx,2); SF1 = sigmaSF.*randn(N,1); CL1 = 0;
          else
              sigmaSF = tableData(idx,3); SF1 = sigmaSF.*randn(N,1); CL1 = tableData(idx,4);
         end
    else
          if(channelIdx == 1)
              sigmaSF = tableData(idx,5); SF1 = sigmaSF.*randn(N,1); CL1 = 0;
          else
              sigmaSF = tableData(idx,6); SF1 = sigmaSF.*randn(N,1); CL1 = tableData(idx,7);
          end
     end
end

function L_ces = clutterLossEarthSpace(fc_GHz, theta_deg, p_percent)
% ITU-R P.2108 模型解析计算
    validateattributes(fc_GHz,   {'numeric'}, {'real','positive'});
    validateattributes(theta_deg, {'numeric'}, {'real','>=',0,'<=',90});
    validateattributes(p_percent, {'numeric'}, {'real','>',0,'<',100});
    A1 = 0.05;
    K1 = 93 .* (fc_GHz .^ 0.175);
    angle_rad = A1 .* (1 - theta_deg ./ 90) + pi .* theta_deg ./ 180;
    Qinv = sqrt(2) .* erfcinv(2 .* (p_percent ./ 100));
    baseTerm = -K1 .* log(1 - p_percent ./ 100) .* cot(angle_rad);
    exponent = 0.5 .* (90 - theta_deg) ./ 90;
    L_ces = baseTerm .^ exponent - 1 - 0.6 .* Qinv;
    L_ces = max(L_ces, 0); % 截断
end