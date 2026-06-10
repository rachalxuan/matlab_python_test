classdef HelperCCSDSTMDemodulator < comm.internal.Helper & satcom.internal.ccsds.tmBase
    % HelperCCSDSTMDemodulator [完美版]
    % 1. 逻辑：GMSK 方案2 (Mask=1010..., Prev=1, 反馈差分) -> BER=0
    % 2. 接口：修复了 isInactivePropertyImpl 导致的警告
    
    properties(Nontunable, Access = private)
        pDemod
        pIsGMSK
        pIsOQPSK
        pIs4D8PSKTCM
        pIsQAM
        pQAMOrder
    end
    
    properties(Access = private)
        pDreg % 差分寄存器
        pCount % 计数器
        pLastSymbol % GMSK 差分检测寄存器 (previous complex symbol)
        pTCMConvState
        pTCMDiffState
    end
    
    methods
        function obj = HelperCCSDSTMDemodulator(varargin)
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods(Access = protected)
        function setupImpl(obj)
            setupImpl@satcom.internal.ccsds.tmBase(obj);
            
            % 初始化状态，必须和 Generator 匹配
            obj.pDreg = 1; 
            obj.pCount = 0;
            obj.pLastSymbol = complex(0, 0); % 用于存储上一个复数符号
            obj.pTCMConvState = zeros(6, 1, 'int8');
            obj.pTCMDiffState = zeros(3, 1, 'int8');

            obj.pIsGMSK = contains(string(obj.Modulation), 'GMSK');
            obj.pIsOQPSK = strcmp(obj.Modulation, 'OQPSK');
            obj.pIs4D8PSKTCM = strcmp(obj.Modulation, '4D-8PSK-TCM');

            obj.pIsQAM = contains(string(obj.Modulation), 'QAM');
            if strcmp(obj.Modulation, '16QAM')
                obj.pQAMOrder = 16;
            elseif strcmp(obj.Modulation, '32QAM')
                obj.pQAMOrder = 32;
            else
                obj.pQAMOrder = 0;
            end
            if strcmp(obj.Modulation, 'QPSK')
                obj.pDemod = comm.PSKDemodulator( ...
                    'PhaseOffset',pi/4, ...
                    'ModulationOrder',4, ...
                    'BitOutput',true, ...
                    'DecisionMethod',"Approximate log-likelihood ratio", ...
                    'SymbolMapping','Custom', ...
                    'CustomSymbolMapping',[0;2;3;1]);
            
            elseif strcmp(obj.Modulation, 'OQPSK')
                    % OQPSK 使用 comm.OQPSKDemodulator 处理半符号偏移和匹配滤波。
                    % 它的输出 bit 顺序/LLR 极性和 CCSDS decoder 约定不完全一致，
                    % 因此后面手动做每对 bit 内部交换和 soft bit 极性适配。
                 obj.pDemod = comm.OQPSKDemodulator( ...
                    'PulseShape','Root raised cosine', ...
                    'RolloffFactor', obj.RolloffFactor, ...
                    'SamplesPerSymbol', obj.SamplesPerSymbol, ...
                    'BitOutput', true);
            elseif strcmp(obj.Modulation, '8PSK')
                obj.pDemod = comm.PSKDemodulator('PhaseOffset', pi/8, 'ModulationOrder', 8, ...
                    'BitOutput', true, 'DecisionMethod', "Approximate log-likelihood ratio", ...
                    'SymbolMapping', 'Custom', 'CustomSymbolMapping', [0 4 6 2 3 7 5 1]); 
            elseif obj.pIsQAM
                obj.pDemod = [];
            elseif obj.pIs4D8PSKTCM
                % 4D-8PSK-TCM uses a custom hard-decision 4-symbol mapper below.
            elseif obj.pIsGMSK
                
            end
        end
        
        function y = stepImpl(obj,u)
            if isempty(u), y=zeros(0,1); return; end
            
            if obj.pIs4D8PSKTCM
                hardBits = fourD8PSKTCMViterbiDemod(u, double(obj.ModulationEfficiency));

                % 先保持和原 hard demod 输出约定一致：
                % bit 0 -> -5, bit 1 -> +5
                y = double(hardBits);
                y(y == 0) = -5;
                y(y == 1) = 5;
            elseif obj.pIsGMSK
                  % =========================================================
                  % GMSK 非相干差分 soft metric 检测
                  % 输出约定：
                  %   bit 0 -> positive soft value
                  %   bit 1 -> negative soft value
                  % =========================================================
                  len = length(u);

                  % 1. 构造差分向量：当前点乘以上一点的共轭。
                  % 物理含义是计算相位变化 delta_phi。
                  if obj.pLastSymbol == 0 % 第一帧处理
                      prev_block = [u(1); u(1:end-1)]; % 简单填充
                  else
                      prev_block = [obj.pLastSymbol; u(1:end-1)];
                  end

                  % 保存最后一个符号给下一帧
                  obj.pLastSymbol = u(end);
                  % 2. 差分相位
                  d = u .* conj(prev_block);
                  phase_diff = angle(d);

                  % 3. raw GMSK soft metric
                  % 原硬判决中 phase_diff > 0 判为 1。
                  % 因此这里用 -sin(phase_diff)，保证：
                  %   phase_diff > 0 -> negative -> bit 1
                  %   phase_diff < 0 -> positive -> bit 0
                  ampConf = abs(u) .* abs(prev_block);
                  rawMetric = -sin(phase_diff) .* ampConf;

                  % 4. 归一化，避免幅度太小或太大
                  rmsMetric = sqrt(mean(rawMetric.^2) + eps);
                  rawMetric = rawMetric / rmsMetric;

                  % Turbo 对幅度比较敏感，先用 4~8 之间的尺度
                  softScale = 5;
                  rawMetric = softScale * rawMetric;

                  % 5. 逻辑层 soft 解码
                  % 原硬逻辑：
                  %   temp = rawBit XOR altMask
                  %   decoded = temp XOR lastDecoded
                  %
                  % LLR/soft metric 下，XOR 1 等价于 soft 符号翻转。
                  idx = (obj.pCount + (1:len))';
                  altMask = mod(idx, 2);  % 1,0,1,0,...

                  y = zeros(len, 1);
                  lastDecoded = obj.pDreg;

                  for kk = 1:len
                      m = rawMetric(kk);

                      % 去掉交替反转：XOR altMask
                      if altMask(kk)
                          m = -m;
                      end

                      % 反馈差分解码：XOR lastDecoded
                      if lastDecoded
                          m = -m;
                      end

                      % 当前 decoded bit 的 soft metric
                      y(kk) = m;

                      % 用 soft metric 的硬判决更新反馈状态
                      % 约定：positive -> bit 0，negative -> bit 1
                      lastDecoded = y(kk) < 0;
                  end

                  % 6. 更新状态
                  obj.pDreg = logical(lastDecoded);
                  obj.pCount = obj.pCount + len;

                  % 7. 限幅，避免极端值把 Turbo 迭代推爆
                  llrMax = 20;
                  y = max(min(y, llrMax), -llrMax);
                  y = double(y);
                  % 旧版 GMSK 硬判决/反馈差分逻辑保留过一段时间用于对照，
                  % 现在已经由上面的 soft metric 路径替代，因此这里不再保留整段旧注释。
%                 obj.pDreg = lastDecoded;
%                 obj.pCount = obj.pCount + len;
%                 
%                 % 3. 转为 Soft LLR (0->+5, 1->-5)
%                 y = double(decodedBits);
%                 y(y==0) = 5; 
%                 y(y==1) = -5;

            elseif obj.pIsOQPSK
                % =========================================================
                % OQPSK 官方解调路径
                % 输入 u 是 full-rate waveform，SamplesPerSymbol=sps
                % pDemod 内部完成 RRC 匹配滤波、OQPSK 半符号对齐和 hard bit 输出
                % =========================================================
                y0 = obj.pDemod(u);
                y0 = double(y0(:));
            
                % MATLAB OQPSKDemodulator 默认 Gray 输出。
                % 当前 CCSDS/QPSK 路径等效需要每对 bit 内部交换。
                if mod(length(y0), 2) == 0
                    y0 = reshape(y0, 2, []);
                    y0 = y0([2 1], :);
                    y0 = y0(:);
                end
            
                % 保持与你当前 tryOneRotation 里成功版本完全一致：
                % bit=0 -> -5, bit=1 -> +5
                hardBits = y0 > 0;
                y = -5 * ones(size(hardBits));
                y(hardBits) = 5;
                y = double(y);  
            elseif obj.pIsQAM
                % =========================================================
                % 16QAM / 32QAM soft demod
                % 输入 u 应该已经完成：
                % coarse CFO + RRC + timing sync + carrier sync + 功率归一
                %
                % 输出约定：
                %   bit 0 -> positive soft value
                %   bit 1 -> negative soft value
                % 这个方向和 HelperCCSDSTMDecoder 期望一致
                % =========================================================

                rxQAM = u(:);

                % 再保险：QAM 解调前做一次单位平均功率归一
                if ~isempty(rxQAM)
                    pwr = mean(abs(rxQAM).^2);
                    if pwr > 0
                        rxQAM = rxQAM / sqrt(pwr);
                    end
                end

                M = obj.pQAMOrder;
                bitsPerSym = log2(M);

                % 这里无法直接知道真实 SNR，先给一个温和默认值。
                % 对 Viterbi/CCSDS 解码来说，LLR 尺度不是绝对关键，但不能太离谱。
                noiseVar = 0.01;

                llrRaw = qamdemod(rxQAM, M, ...
                    'OutputType','approxllr', ...
                    'UnitAveragePower',true, ...
                    'NoiseVariance',noiseVar);

                if isvector(llrRaw)
                    y = double(llrRaw(:));
                elseif size(llrRaw,1) == numel(rxQAM) && size(llrRaw,2) == bitsPerSym
                    y = double(reshape(llrRaw.', [], 1));
                else
                    y = double(llrRaw(:));
                end

                % 关键：实测 MATLAB qamdemod 的 LLR 极性和当前 CCSDS decoder 期望相反
                % 你之前 QAM 扩展脚本中显示 Soft polarity = inverted LLR
                y = -y;
            elseif strcmp(obj.Modulation, 'BPSK')
                y = double(real(u));
                if strcmp(obj.PCMFormat,'NRZ-M') && ~any(strcmp(obj.ChannelCoding,{'convolutional','concatenated'}))
                    y(2:end) = y(2:end).*sign(y(1:end-1));
                    y(1) = y(1)*sign(real(obj.pDreg)); 
                    obj.pDreg = y(end);
                end
            else
                y = obj.pDemod(u);
                 if any(strcmp(obj.Modulation, {'QPSK','8PSK'}))
                    y = -1*y;
                elseif strcmp(obj.Modulation,'OQPSK')
%                     y = -1*y;
                    % 不翻号：保留 PSKDemodulator 原生 LLR 极性（>0 表示 bit 0）。
                    % 早期版本 y = -1*y 是排查 BER=0.5 时留下的占位。
                    % 实测 SNR=25 + conv 7/8 场景下，翻号会把 Viterbi 推到全 1 解码鞍点。
                    % 4 重旋转搜索也救不回来（旋转只能 XOR 编码 bit，不改 LLR 整体偏置）。
                end
            end
        end
        
        function resetImpl(obj)
            if ~isempty(obj.pDemod), reset(obj.pDemod); end
            obj.pDreg = 1; 
            obj.pCount = 0;
            obj.pLastSymbol = complex(0, 0);
            obj.pTCMConvState = zeros(6, 1, 'int8');
            obj.pTCMDiffState = zeros(3, 1, 'int8');
        end
        
        % ... Boilerplate ...
        function s = saveObjectImpl(obj), s = saveObjectImpl@matlab.System(obj); end
        function loadObjectImpl(obj,s,wasLocked), loadObjectImpl@matlab.System(obj,s,wasLocked); end
        function flag = isInputSizeMutableImpl(~,~), flag = true; end
        
        function flag = isInactivePropertyImpl(obj,prop)
            % 控制属性可见性（修复警告的关键）
            flag = true; 
            isFACM = false; 
            
            if strcmp(prop,'ChannelCoding')
                flag = false;
            elseif strcmp(prop,'Modulation')
                flag = isFACM;
            elseif strcmp(prop,'PCMFormat')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','BPSK','QPSK','8PSK','OQPSK'})) || isFACM;
            % 允许 GMSK 模式下设置 BandwidthTimeProduct
            elseif strcmp(prop, 'BandwidthTimeProduct')
                flag = ~contains(string(obj.Modulation), 'GMSK');
            elseif strcmp(prop, 'SamplesPerSymbol')
                flag = ~strcmp(obj.Modulation, 'OQPSK');
            
            elseif strcmp(prop, 'RolloffFactor')
                flag = ~strcmp(obj.Modulation, 'OQPSK');
            elseif strcmp(prop, 'ModulationEfficiency')
                flag = ~strcmp(obj.Modulation, '4D-8PSK-TCM');
            end
        end
    end
    
    methods(Access = protected, Static)
        function group = getPropertyGroupsImpl
            genprops = {'Modulation', 'PCMFormat', 'ChannelCoding', 'ModulationEfficiency'};
            group = matlab.system.display.SectionGroup('PropertyList', genprops);
        end
    end
end

function [bitsOut, convState, diffState] = fourD8PSKTCMHardDemod(sym, rEff, convState, diffState)
    sym = sym(:);
    nGroups = floor(length(sym) / 4);
    nBits = round(4 * rEff);
    bitsOut = zeros(nGroups * nBits, 1, 'int8');
    pskmodSymbols = [1+0j; (1+1j)/sqrt(2); 0+1j; (-1+1j)/sqrt(2); -1+0j; ...
        (-1-1j)/sqrt(2); 0-1j; (1-1j)/sqrt(2)];

    for iGroup = 1:nGroups
        rx4 = sym((iGroup-1)*4 + 1:iGroup*4);
        bestMetric = inf;
        bestBits = zeros(nBits, 1, 'int8');
        bestConvState = convState;
        bestDiffState = diffState;

        for word = 0:(2^nBits - 1)
            candBits = int8(de2bi(word, nBits, 'left-msb').');
            [candSym, candConvState, candDiffState] = fourD8PSKTCMMapGroup( ...
                candBits, rEff, convState, diffState, pskmodSymbols);
            metric = sum(abs(rx4 - candSym).^2);
            if metric < bestMetric
                bestMetric = metric;
                bestBits = candBits;
                bestConvState = candConvState;
                bestDiffState = candDiffState;
            end
        end

        bitsOut((iGroup-1)*nBits + 1:iGroup*nBits) = bestBits;
        convState = bestConvState;
        diffState = bestDiffState;
    end
end

function [modSym, convState, diffState] = fourD8PSKTCMMapGroup(bits, rEff, convState, diffState, pskmodSymbols)
    switch rEff
        case 2
            diffInd = [1; 5; 8];
        case 2.25
            diffInd = [2; 6; 9];
        case 2.5
            diffInd = [3; 7; 10];
        case 2.75
            diffInd = [4; 8; 11];
        otherwise
            error('Unsupported 4D-8PSK-TCM modulation efficiency: %g', rEff);
    end

    dataIn = int8(bits(:));
    [diffBits, diffState] = fourD8PSKTCMDifferentialCoder(dataIn(diffInd), diffState);
    dataIn(diffInd) = diffBits;

    [xout, convState] = fourD8PSKTrellisEnc(dataIn(1:3), convState);
    symbols = fourD8PSKConstellationMapper([xout; dataIn], rEff);
    modSym = pskmodSymbols(double(symbols) + 1);
end

function stateId = tcmStateToId(convState, diffState)
    s = [convState(:); diffState(:)];
    s = double(s(:) ~= 0);

    stateId = 0;
    for k = 1:numel(s)
        stateId = stateId * 2 + s(k);
    end

    % MATLAB index
    stateId = stateId + 1;
end
function bitsOut = fourD8PSKTCMViterbiDemod(sym, rEff)
    sym = sym(:);

    supportedEff = [2 2.25 2.5 2.75];
    [minDelta, effIdx] = min(abs(rEff - supportedEff));
    if minDelta > 1e-9
        error('Unsupported 4D-8PSK-TCM modulation efficiency: %g', rEff);
    end
    rEff = supportedEff(effIdx);

    nBits = round(4 * rEff);   % rEff=2 -> 8 bits/group
    nStates = 512;
    nGroups = floor(length(sym) / 4);
    sym = sym(1:4*nGroups);

    [fromStateVec, wordVec, branchSym, branchesByNext] = ...
        fourD8PSKTCMBranchTable(rEff);

    initConv = zeros(6, 1, 'int8');
    initDiff = zeros(3, 1, 'int8');
    initState = tcmStateToId(initConv, initDiff);

    infMetric = 1e30;
    pathMetric = infMetric * ones(nStates, 1);
    pathMetric(initState) = 0;

    survivorPrev = zeros(nGroups, nStates, 'uint16');
    survivorWord = zeros(nGroups, nStates, 'uint16');

    for ig = 1:nGroups
        rx4 = sym((ig-1)*4 + 1:ig*4);

        branchMetric = sum(abs(branchSym - rx4).^2, 1).';
        candMetric = pathMetric(double(fromStateVec)) + branchMetric;

        newMetric = infMetric * ones(nStates, 1);
        newPrev = zeros(nStates, 1, 'uint16');
        newWord = zeros(nStates, 1, 'uint16');

        for nextState = 1:nStates
            idx = branchesByNext{nextState};
            [bestMetric, relIdx] = min(candMetric(idx));
            if isfinite(bestMetric) && bestMetric < infMetric/2
                bestBranch = idx(relIdx);
                newMetric(nextState) = bestMetric;
                newPrev(nextState) = fromStateVec(bestBranch);
                newWord(nextState) = wordVec(bestBranch);
            end
        end

        pathMetric = newMetric;
        survivorPrev(ig, :) = newPrev;
        survivorWord(ig, :) = newWord;
    end

    [~, bestState] = min(pathMetric);

    outWords = zeros(nGroups, 1, 'uint16');
    state = bestState;

    for ig = nGroups:-1:1
        outWords(ig) = survivorWord(ig, state);
        state = double(survivorPrev(ig, state));

        if state == 0
            state = initState;
        end
    end

    bitsOut = zeros(nGroups*nBits, 1, 'int8');
    for ig = 1:nGroups
        w = double(outWords(ig));
        bitsOut((ig-1)*nBits+1:ig*nBits) = int8(de2bi(w, nBits, 'left-msb').');
    end
end

function [fromStateVec, wordVec, branchSym, branchesByNext] = fourD8PSKTCMBranchTable(rEff)
    persistent cache

    supportedEff = [2 2.25 2.5 2.75];
    [minDelta, effIdx] = min(abs(rEff - supportedEff));
    if minDelta > 1e-9
        error('Unsupported 4D-8PSK-TCM modulation efficiency: %g', rEff);
    end
    rEff = supportedEff(effIdx);

    if isempty(cache)
        cache = cell(numel(supportedEff), 1);
    end

    if ~isempty(cache{effIdx})
        entry = cache{effIdx};
        fromStateVec = entry.fromStateVec;
        wordVec = entry.wordVec;
        branchSym = entry.branchSym;
        branchesByNext = entry.branchesByNext;
        return;
    end

    nBits = round(4 * rEff);
    nStates = 512;
    nWords = 2^nBits;
    nBranches = nStates * nWords;

    pskmodSymbols = [ ...
        1+0j; ...
        (1+1j)/sqrt(2); ...
        0+1j; ...
        (-1+1j)/sqrt(2); ...
        -1+0j; ...
        (-1-1j)/sqrt(2); ...
        0-1j; ...
        (1-1j)/sqrt(2)];

    fromStateVec = zeros(nBranches, 1, 'uint16');
    nextStateVec = zeros(nBranches, 1, 'uint16');
    wordVec = zeros(nBranches, 1, 'uint16');
    branchSym = complex(zeros(4, nBranches));

    branchIdx = 1;
    for oldState = 1:nStates
        [oldConv, oldDiff] = tcmIdToState(oldState);
        for w = 0:nWords-1
            candBits = int8(de2bi(w, nBits, 'left-msb').');
            [candSym, nextConv, nextDiff] = fourD8PSKTCMMapGroup( ...
                candBits, rEff, oldConv, oldDiff, pskmodSymbols);

            fromStateVec(branchIdx) = uint16(oldState);
            nextStateVec(branchIdx) = uint16(tcmStateToId(nextConv, nextDiff));
            wordVec(branchIdx) = uint16(w);
            branchSym(:, branchIdx) = candSym;
            branchIdx = branchIdx + 1;
        end
    end

    branchesByNext = cell(nStates, 1);
    for nextState = 1:nStates
        branchesByNext{nextState} = find(nextStateVec == nextState);
    end

    cache{effIdx} = struct( ...
        'fromStateVec',fromStateVec, ...
        'wordVec',wordVec, ...
        'branchSym',branchSym, ...
        'branchesByNext',{branchesByNext});
end
function [convState, diffState] = tcmIdToState(stateId)
    v = stateId - 1;

    bits = zeros(9, 1, 'int8');
    for k = 9:-1:1
        bits(k) = int8(mod(v, 2));
        v = floor(v / 2);
    end

    convState = bits(1:6);
    diffState = bits(7:9);
end

function [diffOut, diffState] = fourD8PSKTCMDifferentialCoder(diffIn, diffState)
    w = logical(diffIn(:));
    states = logical(diffState(:));
    diffOut = zeros(3, 1, 'int8');

    r0 = and(w(1), states(1));
    r1 = (w(2) & states(2)) | (w(2) & r0) | (states(2) & r0);
    diffOut(1) = int8(xor(w(1), states(1)));
    diffOut(2) = int8(xor(xor(w(2), states(2)), r0));
    diffOut(3) = int8(xor(xor(w(3), states(3)), r1));
    diffState = diffOut;
end

function [xout, convState] = fourD8PSKTrellisEnc(inBits, convState)
    xin = logical(inBits(:));
    states = logical(convState(:));

    xout = int8(states(6));
    states(6) = xor(xor(states(5), xin(1)), logical(xout));
    states(5) = xor(xor(xin(1), xin(2)), states(4));
    states(4) = xor(states(3), xin(3));
    states(3) = xor(states(2), xin(2));
    states(2) = xor(states(1), xin(3));
    states(1) = logical(xout);
    convState = int8(states);
end

function z = fourD8PSKConstellationMapper(x, rEff)
    x = double(x(:));
    z = zeros(4, 1);

    switch rEff
        case 2
            z(1) = (4*x(9)) + (2*x(6)) + x(2);
            z(2) = z(1) + ((4*x(8)) + (2*x(4)));
            z(3) = z(1) + ((4*x(7)) + (2*x(3)));
            z(4) = z(1) + ((4*(x(8)+x(7)+x(5))) + (2*(x(4)+x(3)+x(1))));
        case 2.25
            z(1) = (4*x(10)) + (2*x(7)) + x(3);
            z(2) = z(1) + ((4*x(9)) + (2*x(5)) + x(1));
            z(3) = z(1) + ((4*x(8)) + (2*x(4)));
            z(4) = z(1) + ((4*(x(9)+x(8)+x(6))) + (2*(x(5)+x(4)+x(2))) + x(1));
        case 2.5
            z(1) = (4*x(11)) + (2*x(8)) + x(4);
            z(2) = z(1) + ((4*x(10)) + (2*x(6)) + x(2));
            z(3) = z(1) + ((4*x(9)) + (2*x(5))) + x(1);
            z(4) = z(1) + ((4*(x(10)+x(9)+x(7))) + (2*(x(6)+x(5)+x(3))) + (x(2)+x(1)));
        otherwise
            z(1) = (4*x(12)) + (2*x(9)) + x(5);
            z(2) = z(1) + ((4*x(11)) + 2*x(7) + x(3));
            z(3) = z(1) + ((4*x(10)) + 2*x(6) + x(2));
            z(4) = z(1) + ((4*(x(11)+x(10)+x(8))) + (2*(x(7)+x(6)+x(4))) + (x(3)+x(2)+x(1)));
    end
    z = mod(z, 8);
end
