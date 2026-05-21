classdef HelperCCSDSTMDemodulator < comm.internal.Helper & satcom.internal.ccsds.tmBase
    % HelperCCSDSTMDemodulator [完美版]
    % 1. 逻辑：GMSK 方案2 (Mask=1010..., Prev=1, 反馈差分) -> BER=0
    % 2. 接口：修复了 isInactivePropertyImpl 导致的警告
    
    properties(Nontunable, Access = private)
        pDemod
        pIsGMSK
        pIsOQPSK
    end
    
    properties(Access = private)
        pDreg % 差分寄存器
        pCount % 计数器
        pLastSymbol % GMSK差分检测寄存器 (存 complex symbol)
    end
    
    methods
        function obj = HelperCCSDSTMDemodulator(varargin)
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods(Access = protected)
        function setupImpl(obj)
            setupImpl@satcom.internal.ccsds.tmBase(obj);
            
            % 初始化状态 (必须为1以匹配 Generator)
            obj.pDreg = 1; 
            obj.pCount = 0;
            obj.pLastSymbol = complex(0, 0); % 用于存储上一个复数符号

            obj.pIsGMSK = contains(string(obj.Modulation), 'GMSK');
            obj.pIsOQPSK = strcmp(obj.Modulation, 'OQPSK');
            
            if strcmp(obj.Modulation, 'QPSK')
                obj.pDemod = comm.PSKDemodulator( ...
                    'PhaseOffset',pi/4, ...
                    'ModulationOrder',4, ...
                    'BitOutput',true, ...
                    'DecisionMethod',"Approximate log-likelihood ratio", ...
                    'SymbolMapping','Custom', ...
                    'CustomSymbolMapping',[0;2;3;1]);
            
            elseif strcmp(obj.Modulation, 'OQPSK')
                    %  OQPSK 现在用 comm.OQPSKDemodulator 是为了让它处理半符号偏移和匹配滤波，
                    % 但它的输出 bit 顺序/LLR 极性和 CCSDS decoder 约定不完全一致，所以要手动做：
                    % 每对 bit 内部交换 + soft bit 极性适配成 ±5
                 obj.pDemod = comm.OQPSKDemodulator( ...
                    'PulseShape','Root raised cosine', ...
                    'RolloffFactor', obj.RolloffFactor, ...
                    'SamplesPerSymbol', obj.SamplesPerSymbol, ...
                    'BitOutput', true);
            elseif strcmp(obj.Modulation, '8PSK')
                obj.pDemod = comm.PSKDemodulator('PhaseOffset', pi/8, 'ModulationOrder', 8, ...
                    'BitOutput', true, 'DecisionMethod', "Approximate log-likelihood ratio", ...
                    'SymbolMapping', 'Custom', 'CustomSymbolMapping', [0 4 6 2 3 7 5 1]); 
            elseif obj.pIsGMSK
                
            end
        end
        
        function y = stepImpl(obj,u)
            if isempty(u), y=zeros(0,1); return; end
            
            if obj.pIsGMSK
                % =========================================================
                % GMSK 非相干差分检测 (Robust Non-Coherent Detection)
                % =========================================================
                len = length(u);
                
                % 1. 构造差分向量 (当前点 * 上一点的共轭)
                % 这里的物理含义：计算相位变化量 delta_phi
                if obj.pLastSymbol == 0 % 第一帧处理
                    prev_block = [u(1); u(1:end-1)]; % 简单填充
                else
                    prev_block = [obj.pLastSymbol; u(1:end-1)];
                end
                
                % 保存最后一个符号给下一帧
                obj.pLastSymbol = u(end);
                
                % 计算相位差 (核心物理层解调)
                % GMSK中，+Freq (相位增加) -> Bit 1 (或0), -Freq (相位减少) -> Bit 0 (或1)
                % CCSDS 规定: 1 -> +f, 0 -> -f (具体映射需通过逻辑解码还原)
                phase_diff = angle(u .* conj(prev_block));
                
                % 硬判决: 相位增 > 0 判为 1 (暂时假设), 相位减 < 0 判为 0
                % 注意：这里得到的 'hardBits' 其实就是发送端的编码比特 S_k
                hardBits = double(phase_diff > 0); 
                
                % =========================================================
                % 逻辑层解码 (方案2: Feedback Differential)
                % =========================================================
                idx = (obj.pCount + (1:len))';
                altMask = mod(idx, 2); % Mask: 1, 0, 1, 0...
                
                decodedBits = zeros(len, 1);
                lastDecoded = obj.pDreg;
                
                for k = 1:len
                    % 公式: Data[k] = Rx[k] XOR Mask[k] XOR Data[k-1]
                    
                    % 1. 去掉交替反转
                    temp = xor(hardBits(k), altMask(k));
                    
                    % 2. 反馈差分解码
                    decodedBits(k) = xor(temp, lastDecoded);
                    lastDecoded = decodedBits(k);
                end
                
                % 更新状态
                obj.pDreg = lastDecoded;
                obj.pCount = obj.pCount + len;
                
                % 3. 转为 Soft LLR (0->+5, 1->-5)
                y = double(decodedBits);
                y(y==0) = 5; 
                y(y==1) = -5;
            elseif obj.pIsOQPSK
                % =========================================================
                % OQPSK 官方解调路径
                % 输入 u 是 full-rate waveform, 即 SamplesPerSymbol=sps
                % pDemod 内部完成 RRC 匹配滤波 + OQPSK 半符号对齐 + hard bit 输出
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
                    % 不翻号: 用 PSKDemodulator 原生的 LLR 极性 (>0 ⇒ bit 0).
                    % 早期版本写 y = -1*y 是 "先保留, 如 BER=0.5 试去掉" 的占位,
                    % 实测 SNR=25 + conv 7/8 场景下翻号会把 Viterbi 推到全 1 解码鞍点,
                    % 4 重旋转搜索也救不回来 (旋转只能 XOR 编码层 bit, 不改 LLR 整体偏置).
                end
            end
        end
        
        function resetImpl(obj)
            if ~isempty(obj.pDemod), reset(obj.pDemod); end
            obj.pDreg = 1; 
            obj.pCount = 0;
        end
        
        % ... Boilerplate ...
        function s = saveObjectImpl(obj), s = saveObjectImpl@matlab.System(obj); end
        function loadObjectImpl(obj,s,wasLocked), loadObjectImpl@matlab.System(obj,s,wasLocked); end
        function flag = isInputSizeMutableImpl(~,~), flag = true; end
        
        function flag = isInactivePropertyImpl(obj,prop)
            % 控制属性可见性 (修复警告的关键)
            flag = true; 
            isFACM = false; 
            
            if strcmp(prop,'ChannelCoding')
                flag = false;
            elseif strcmp(prop,'Modulation')
                flag = isFACM;
            elseif strcmp(prop,'PCMFormat')
                flag = ~any(strcmp(obj.Modulation,{'PCM/PSK/PM','BPSK','QPSK','8PSK','OQPSK'})) || isFACM;
            % 【新增】允许 GMSK 模式下设置 BandwidthTimeProduct
            elseif strcmp(prop, 'BandwidthTimeProduct')
                flag = ~contains(string(obj.Modulation), 'GMSK');
            elseif strcmp(prop, 'SamplesPerSymbol')
                flag = ~strcmp(obj.Modulation, 'OQPSK');
            
            elseif strcmp(prop, 'RolloffFactor')
                flag = ~strcmp(obj.Modulation, 'OQPSK');
            end
        end
    end
    
    methods(Access = protected, Static)
        function group = getPropertyGroupsImpl
            genprops = {'Modulation', 'PCMFormat', 'ChannelCoding'};
            group = matlab.system.display.SectionGroup('PropertyList', genprops);
        end
    end
end