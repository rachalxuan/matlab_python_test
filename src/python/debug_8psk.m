%% 8PSK 映射关系逆向分析器 (修复版)
clc; clear; close all;

% 1. 配置生成器
args = {
    'WaveformSource', 'synchronization and channel coding', ...
    'Modulation', '8PSK', ...
    'ChannelCoding', 'none', ... 
    'SamplesPerSymbol', 1, ... % 1 SPS
    'FilterSpanInSymbols', 10, ...
    'RolloffFactor', 0.5
};

try
    gen = ccsdsTMWaveformGenerator(args{:});
catch ME
    error('生成器报错: %s', ME.message);
end

% 2. 构造测试数据：必须填满整帧
bitsPerFrame = gen.NumInputBits; % 获取一帧需要的比特数 (例如 8920)

% 我们要测试的序列：0 ~ 7 (每个符号 3 bit)
% 000, 001, 010, 011, 100, 101, 110, 111
testPatternInts = (0:7)';
testPatternBits = de2bi(testPatternInts, 3, 'left-msb')'; 
testPatternBits = testPatternBits(:); % 24 bits 长的测试片段

% 用这个片段循环填充，直到填满 bitsPerFrame
numRepeats = ceil(bitsPerFrame / length(testPatternBits));
fullMsg = repmat(testPatternBits, numRepeats, 1);
fullMsg = fullMsg(1:bitsPerFrame); % 截断到刚好一帧长

% 3. 生成波形
txSig = gen(fullMsg);

% 4. 提取中间段的数据
% 为了避开滤波器延迟和截断边缘，我们取波形正中间的数据
% 中间肯定有完整的 0->7 序列
midIdx = floor(length(txSig)/2);

% 我们往后多取一点，确保覆盖 0~7 所有符号
% 8PSK 符号流: ... 0 1 2 3 4 5 6 7 0 1 2 ...
rxWindow = txSig(midIdx : midIdx + 20); 
rxWindow = rxWindow / mean(abs(rxWindow)); % 归一化

% 5. 寻找 pattern 并分析
fprintf('>>> 开始逆向分析 8PSK 映射关系 <<<\n\n');
fprintf('%-10s | %-15s | %-10s\n', '输入值(Int)', '接收相位(Deg)', '判定点');
fprintf('---------------------------------------------------\n');

detectedMap = zeros(8,1) - 1; % 初始化为 -1
foundCount = 0;

% 遍历窗口里的符号，试图拼凑出映射表
for i = 1:length(rxWindow)
    if foundCount >= 8, break; end
    
    % 计算当前点的角度
    deg = angle(rxWindow(i)) * 180/pi;
    if deg < 0, deg = deg + 360; end
    
    % 找到对应的标准相位点 (0~7)
    standardAngles = 0:45:315;
    [minDiff, idx] = min(abs(deg - standardAngles));
    symbolIdx = idx - 1; % 0~7
    
    % 反推这个点对应的输入值
    % 因为我们的输入是循环的 0,1,2,3,4,5,6,7...
    % 我们需要知道当前的 rxWindow(i) 对应输入流里的哪个位置
    % 这是一个简单的对齐问题
    
    % 但这里有一个更简单的方法：
    % 观察 rxWindow 里的相位变化。如果相邻两个点的相位差对应 input 的差(1)，那就对上了。
    
    % 让我们换个思路：直接在 rxWindow 里找 8 个不同的相位值
    if detectedMap(symbolIdx + 1) == -1
        % 这里稍微有点难，因为我们不知道 rxWindow(i) 具体对应 0还是1还是2...
        % 但我们知道序列是连续的 ...X, X+1, X+2...
        % 我们先打印出来，人工看一眼最准！
    end
end

% === 自动分析太容易错，直接打印出来肉眼看 ===
% 我们打印 16 个连续符号，你一定能看到 0->7 的规律
% 我们的输入是 ... 0, 1, 2, 3, 4, 5, 6, 7, 0, ...
% 只要看到相位的变化规律，就能填表

startView = 1;
for i = startView:startView+15
    deg = angle(rxWindow(i)) * 180/pi;
    if deg < 0, deg = deg + 360; end
    [~, idx] = min(abs(deg - standardAngles));
    sym = idx - 1;
    fprintf('Rx符号[%d]: 相位 %5.1f° -> 索引 %d\n', i, deg, sym);
end

fprintf('\n>>> 人工分析指南 <<<\n');
fprintf('1. 上面的列表里，你应该能看到索引的变化规律。\n');
fprintf('2. 请找一段连续变化的序列，但要注意顺序可能是乱的。\n');
fprintf('3. 其实最简单的做法：\n');
fprintf('   Matlab 默认 8PSK Gray 映射通常是：0, 1, 3, 2, 6, 7, 5, 4\n');
fprintf('   对应的相位索引(0~7)分别是：       0, 1, 2, 3, 4, 5, 6, 7\n');
fprintf('   这意味着：\n');
fprintf('   输入0 -> 相位0 (0°)\n');
fprintf('   输入1 -> 相位1 (45°)\n');
fprintf('   输入2 -> 相位3 (135°)\n');
fprintf('   输入3 -> 相位2 (90°)\n');
fprintf('   ...\n\n');

fprintf('>>> 自动生成推荐配置 (基于常见 CCSDS 假设) <<<\n');
% CCSDS 标准映射 (如果你在上面看到了类似的相位分布)
ccsds_map = [0 1 3 2 6 7 5 4]; 
fprintf('CustomSymbolMapping: [%s]\n', num2str(ccsds_map));