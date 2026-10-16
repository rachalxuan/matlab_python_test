# LDPC 7/8：独立标准校验图实验

默认路径仍**不接管主接收机**。标准稀疏译码器、固定 LLR 对照和 Stage2 实际
LLR 抓取分别复用现有链路；没有复制整套收发链，没有改 TX、同步、均衡、LLR
可靠度或已有 `tm_ldpc_H_*.mat`。`LDPCDecoderMode='legacy-dense-bp'` 是默认和
回退路径；只有显式选择实验模式才会改变 7/8 译码或绕过 BP。

## 图和位置约定

来源：[CCSDS 131.0-B-3 §7.3、Table 7-1](https://ccsds.org/Pubs/131x0b3s.pdf)。
标准母图为 1022×8176，32704 条边；每个循环子矩阵为 511×511，每行右循环移位。
其秩为 1020，不把 MATLAB 配置对象的 `N-M` 当作真实的信息位置定义。

现有发送码字（不含 ASM）：

```text
7136 个信息 bit | 1022 个校验 bit | 2 个发送填充零 = 8160 bit
```

- 母码第 1:18 位是未发送的已知零。直接删除 H 的这 18 列，精确消去零变量；
  **不追加 LLR=0，不使用可调的“大 LLR”代替已知零**。
- 母码 19:8176 对应线上 1:8158，信息位为母码 19:7154。
- 线上 8159:8160 是填充位，不进入母码校验图；报告收到的填充位硬判错误。
- 有效 H 为 1022×8158，32632 条边。没有打孔未知位。
- 官方 `ldpcDecoderConfig(H,'bp')` + `ldpcDecode`，默认上限 20 次，early 停止，
  whole 输出再按明确信息位置提取。既不重写 BP，也不偷偷切到最小和。
- 输入必须是已对齐、去 ASM、完成必要解扰的 8160×N LLR，**正值代表 bit 0**。
  当前普通 TM 软解调入口符号相反；不能把其未转换的 soft bits 直接塞进来。

母图描述的码比 TX 采用的子码大：`GraphParityPassed=true` 不单独证明子码成员资格，
更不证明消息正确。测试另外用**译码结果**重新编码，检查 `SubcodeMismatchBits`；
该检查不使用 TX truth，也不反馈选择输出。`DecodedInfoErrors` 才使用 TX truth 做离线评估。
特意添加了“母图校验通过但子码不匹配”的反例测试，防止今后混淆两者。

## 直接运行

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python'));
addpath(fullfile(root,'src','python','regression'));

% 结构、现有 TX 一致性、无噪声、填充隔离、输入检查。
test_tm_ldpc78_decoder('core');

% 两种图共用同一批 LLR；不会运行 CDL，也不会改主接收机。
opt = struct('Seed',20261012,'FramesPerCondition',3,'MaxIterations',20);
[T, reportFile] = test_tm_ldpc78_decoder('compare',opt);
disp(T(:,{'FrameIndex','Condition','Decoder','InputInfoErrors', ...
    'DecodedInfoErrors','Iterations','OwnParityWeight', ...
    'SubcodeMismatchBits','Seconds'}));
disp(reportFile);
```

默认 `FramesPerCondition=2`，总共 8 个码字；上例为 12 个码字。
四组条件：无噪声、6 个弱错误、实 BPSK 噪声 sigma=0.45、sigma=0.65。
合成 LLR 为 `2*(symbol + sigma*noise)/sigma^2`。
**sigma 不是主脚本 SNR/PSD 参数；这些也不是设备或 CDL 性能点。**
弱错误组的 6 个码位中有 4 个信息位，因此 `InputCoreErrors=6`、`InputInfoErrors=4`。
高噪声允许失败，失败逐码字保留，不能解释成所有输入都应当 BER=0。

两边相同最大迭代次数、相同 early 规则、相同 MATLAB 多线程开关。预热两条路径，
计时不含构图/预热，交替先后顺序；耗时是当前机器实测值，不是 FPGA 吞吐率。
旧、新图校验方程不同，`OwnParityWeight` 不能直接当作跨图距离比较；
同时给出在标准图下重新计算的 `StandardParityWeight`。

结果保存在 `artifacts/ccsds/ldpc78/`：一份小报告、一份压缩的 LLR/参考 bit 数据。
每完成一对码字就保存报告；不保存整段 IQ，不生成缓存校验矩阵。
`SaveResults=false` 可完全关闭结果写盘。

## 固定同一批数据重放

```matlab
S = load(reportFile,'meta');
[R,~] = test_tm_ldpc78_decoder('replay',struct( ...
    'BatchFile',S.meta.BatchFile,'SaveResults',false));
```

也可把真实接收端抓取的码字 LLR 传入同一入口，不重新经过 TX/信道：

```matlab
Batch = struct();
Batch.LLR = llr8160ByN;        % 已对齐，已解扰，正值=0，确实包含两个填充位
Batch.LLRPolarity = 'positive-zero';
Batch.ASMRemoved = true;
Batch.Derandomized = true;
Batch.FrameIndex = originalFrameIndices;
% 可选，仅用于离线错误统计；禁止用它来对齐、调尺度或筛选成功帧。
Batch.Message = reference7136ByN;
[R,~] = test_tm_ldpc78_decoder('replay',struct('Batch',Batch,'SaveResults',false));
```

不要将声明设为 true 来绕过检查；应在确认实际数据处理位置后再传入。
缺少 `Message` 时错误计数为 NaN、比较 bit 为 0，校验/迭代/耗时仍可观察，
不会伪报 BER=0。接口无法自动证明外部码字已对齐，真实抓取时仍须审计边界。

## Stage2 实际 LLR 对照

`capture_tm_ldpc78_stage2_llr` 固定重放三类完整 Stage2 信道区间：

- `CDL_A_2`：正常基线，检查新图不能破坏正确结果；
- `CDL_B_1`：残余误码，判断旧图是否留下本可纠正的错误；
- `CDL_A_4`：严重失败，判断前端软信息是否已经不可恢复。

抓取时由接收端周期 ASM 固定一个相位候选，在已对齐、去 ASM、极性归一并完成
必要解扰后记录 8160 点 LLR；旧稠密 BP 不运行，也不根据 BER/发送真值挑相位。
程序只保存少量起点/中段/末段、原失败帧邻域及高原始错误码字，不保存整段 IQ。
发送消息只在波形、边界、相位和 LLR 全部冻结后用于标注窗口及计算译码错误。

2026-10-15 抓取入口修正：旧周期评分允许 ASM 及其反码，不能单独消除
180 度歧义。仅在 capture 模式，对每个候选的既有周期边界分别计算正常/反相
ASM 错误均值；至少 3 个观测、正常 ASM 均值不超过原 MaxErr，且领先次优
候选至少原 MinGap，才选择该相位。没有 TX BER 参与选择，普通接收路径不变。
证据不充分或离线参考关联失败时，保存 `LDPC78_CAPTURE_FAILED_*.mat`，
记录候选 ASM 窗口、边界以及至多 MaxCodewordsPerCase 个均匀分布的 LLR
（若已抓到），不保存整段 IQ，不创建虚假参考消息，继续下一个用例。
报告的 FailedCaseLabels/DiagnosticFiles 明确保留失败，不将跳过视为通过。
core 增加正相、反相、同分和观测不足的抓取相位单元测试。
抓取脚本同时恢复原 Stage2 每个用例的 `rng(p.randomSeed,'twister')`，
退出时恢复调用者 RNG。仅传 randomSeed 字段不会让评估函数自行设置 RNG。

本机修复后验证（2026-10-15）：core 和 B1/A4 的实际抓取/对照已运行通过。
以恢复 seed=917 的报告 `LDPC78_Stage2_AB_20261015_003633_303.mat` 为准；
较早的 `003307_055` 是尚未显式恢复 RNG 的试运行，不作原 Stage2 随机序列复现依据。
B1 的正常 ASM 在 180 度，0 度命中反码；A4 的正常 ASM 在 90 度。
各保存 12 个码字，B1 新旧译码错误总数为 0/101，A4 为 372/698。
A4 的新图残余 372 bit 全在第 1 帧（预热区）；本次选中的测量区码字新图零误码。
这些汇总包含预热控制码字，不是整段 BER/FER；878/878 是抓取模式的原始
信息位参考覆盖，不是整段 LDPC 译码验收。所有失败码字都保留在报告中。

```matlab
o = struct('SourceFile',fullfile(root,'artifacts','ccsds','system-eq', ...
    'TM_EQ_files_20261014_101855_691.mat'));
[T, reportFile, batchFiles] = capture_tm_ldpc78_stage2_llr(o);
```

同一列实际 LLR 随后进入旧稠密 BP 和新标准稀疏 BP，记录信息错误、实际迭代数、
校验是否通过、子码一致性和纯译码耗时。主接收机的显式模式为：

- `legacy-dense-bp`：默认/回退；
- `standard-sparse-bp`：目前只允许普通 TM CCSDS `(8160,7136)` 7/8；
- `capture-only`：仅诊断，其“raw systematic hard”结果不是 LDPC 后 BER。

## 本阶段边界与回退

### 2026-10-14 本机验证

- MATLAB R2022a，最终实现通过 41 组 TX 结构/无噪声测试（含各 511-bit 块边界）。
- 同一批 LLR 重放时，错误、迭代次数及各类校验结果逐项一致；无参考数据时错误为 NaN。
- 原有 `test_ldpc_boundary_soft_metrics` 通过（LDPC 1/2 边界、PSK LDPC/Turbo 软信息、其他编码指标不变）。
- TX、主译码器、旧 7/8 MAT 和原 AR4JA 1/2 图构造文件 SHA256 前后相同。
- 最终固定样本报告：`artifacts/ccsds/ldpc78/LDPC78_BP_20261014_142207_203.mat`。
  对应 LLR：同目录 `LDPC78_LLR_20261014_142207_203.mat`。

最终样本 `Seed=20261012, FramesPerCondition=3, MaxIterations=20`：

| 条件 | 旧图译码后信息错误（三个码字） | 新图译码后信息错误 | 旧图迭代 | 新图迭代 |
|---|---|---|---|---|
| 无噪声 | 0 / 0 / 0 | 0 / 0 / 0 | 1 / 1 / 1 | 1 / 1 / 1 |
| 6 个弱码位错误 | 0 / 0 / 0 | 0 / 0 / 0 | 2 / 2 / 2 | 1 / 1 / 1 |
| sigma=0.45 | 85 / 97 / 102 | 0 / 0 / 0 | 20 / 20 / 20 | 3 / 4 / 4 |
| sigma=0.65 | 416 / 430 / 429 | 416 / 431 / 432 | 20 / 20 / 20 | 20 / 20 / 20 |

sigma=0.45 三个码字旧图约 0.445–0.527 秒/字，新图约 0.0011–0.0012 秒/字。
这是小样本本机计时；不是普遍加速保证，也不是整条接收链的时间。
sigma=0.65 下新图也未收敛，且部分错误数增加；这些失败没有筛除或替换成输入硬判决。

### 2026-10-15 完整链路与均衡总开关验证

新增一个长期保留的入口 `test_tm_ldpc78_link`，复用原 Stage2 的 inputs 和
`run_ccsds_tm_evaluation`，不另建 TX/RX，不保存整段 IQ。
修复显式 `enableEqualizer=false` 仍可能因残留 `2sps` 设置运行 FSE 的问题：
显式关闭优先于均衡模式、采样模式和专用后级开关；未提供总开关时保留旧行为。
本轮没有修改同步算法、均衡步长、预热长度或 BER 计数门限。

实际运行 QPSK、100 Mbps 调制比特率（50 Msym/s）、RRC、seed=917，
无额外噪声、无已知 H 补偿、开启原盲均衡，稀疏 BP 最大 20 次迭代。
保留原先约 82 ms 的信道时间区间，不只测试开头。

| 信道文件简称 | LDPC 7/8 BER / FER | LDPC 比较帧 | 关闭编码错误 bit | 关闭编码 BER / FER | 关闭编码比较帧 |
|---|---|---|---|---|---|
| CDL_A_2 | 0 / 0 | 878/878 | 0 | 0 / 0 | 1003/1003 |
| CDL_B_1 | 0 / 0 | 878/878 | 603 | 8.42484e-5 / 0.0588235 | 1003/1003 |
| CDL_A_4 | 0 / 0 | 878/878 | 38675 | 0.00540349 / 0.913260 | 1003/1003 |

全部无已恢复未比较帧；关闭编码后的帧同步遥测可用，锁定比例约 99.913%，
计入启动获取过程。A4 均衡已执行，但输出质量接受标志仍为 false，不能因为
LDPC 译码正确就把均衡质量标志改成通过。
关闭编码保持 892 Byte TF，按帧长重新计算帧数以对齐信道时间区间（端点相差
不到一个无编码帧），不是相同 IQ 波形，也不是相同净信息速率。
每例整链耗时：编码约 33–46 秒，无编码约 26–32 秒，本机计时仅供参考。

No-H 总开关对照三例（关闭但保留 2sps / 全显式关闭 / 开启 2sps）均
BER=FER=0、878/878，实际均衡开关分别为 false/false/true。

报告目录 `artifacts/ccsds/ldpc78/full-link`：

- `LDPC78_Link_gate_20261015_154757_728.mat`
- `LDPC78_Link_coded_20261015_154915_839.mat`
- `LDPC78_Link_uncoded_20261015_155108_605.mat`

```matlab
addpath(fullfile(root,'src','python','regression'));
test_tm_ldpc78_link('gate');
test_tm_ldpc78_link('coded');
test_tm_ldpc78_link('uncoded');
% 待确认设备 CDL-A-CITY 对应的确切 MAT 文件后：
% o = struct('ChannelFile','完整的实际 MAT 文件路径');
% test_tm_ldpc78_link('device',o);
```

稀疏 BP 已可通过显式 `p.LDPCDecoderMode='standard-sparse-bp'` 进入主链，
但未更改项目默认 `legacy-dense-bp`，其它码率不变。
以上使用现有评估主链，其普通相位候选选择仍可能依赖发送参考的误码比较；
因此不是独立于发送参考的设备式盲捕获验收。capture-only 的相位选择则仅用
接收 ASM 证据。不能将 A2/A4 直接改名为 CITY，或为了模拟设备而强迫
无编码测试产生错误。

### 2026-10-15 用户指定 CITY 文件对照

用户确认文件为
`E:/matlab_project/link_simulation final_03/link_simulation/mat文件/model/cdl-a-city.mat`。
本机 `whos -file` 确认仅有复数 double `H(3,100000)`，没有路径时延或时间采样率。
按当前加载器，缺失时延按零处理，三行系数在相同延迟相加；沿用测试输入的
100 kHz 信道采样率，文件解释为 1 秒。此读法不包含不同路径间的时延失真，
不等价于已经确认了设备的信道回放配置。

未调整参数，运行 `test_tm_ldpc78_link('device',struct('ChannelFile',...))`：

- 稀疏 BP LDPC 7/8：878/878、BER=FER=0，0 错误 bit，43.8 秒。
- 无编码：1003/1003、BER=FER=0，0 错误 bit，27.4 秒。
- 两组均开启盲均衡、无额外噪声、seed=917、约 82 ms 区间；不是全 1 秒验收。
- 报告 `LDPC78_Link_device_20261015_162208_861.mat`。

关闭编码仍零误码这一结果原样保留。下一步须核对设备是否另行配置路径时延、
H 回放更新率、噪声/电平及均衡开关，不能凭空添加时延或噪声使其失败。

同日新增 `device-eq`：同一 CITY 文件、同一 seed、LDPC 始终开启，仅比较
均衡总开关关闭/开启，约 82 ms。关闭：0/878，BER/FER=NaN，未能建立
有效测量；开启：878/878，BER=FER=0，比较 6265408 bit，耗时分别 25.1/41.2 秒。
报告 `LDPC78_Link_device-eq_20261015_191158_725.mat`。
这是现有接收分支开关对照，不是仅隔离 FIR 抽头的对照；关闭分支也没有执行
该分支的快速包络跟踪。未据此认定 LDPC 失效或多径不可恢复。

```matlab
o=struct('ChannelFile', ...
 'E:/matlab_project/link_simulation final_03/link_simulation/mat文件/model/cdl-a-city.mat');
test_tm_ldpc78_link('device-eq',o);
```

全 1 秒连续测试尚未运行：400 MHz 下有 4 亿复采样，仅三路插值 H 约
19.2 GB，另有收发波形及多个中间数组；当前主机总内存约 32 GB、检查时
可用约 12 GB。未将分段重启接收器的结果冒充连续接收结果。

### CITY 均衡关闭后的幅度隔离诊断

`test_tm_ldpc78_link('device-amplitude',o)` 始终关闭均衡、使用原 Gardner
及载波链，seed=917 重放相同配置产生的波形，不改变信道、带宽、FEC 或统计门限。
诊断选项 `debugTimingInputAmplitudeMode` 默认 off，仅允许 QPSK EQ-off 路径：
`rms` 用匹配滤波后接收样本的整段均方功率作固定缩放；`envelope` 复用已有
16-symbol IIR 包络跟踪。两者不使用 TX/H、ASM 或 BER 确定增益；整段 RMS
是离线诊断，不是已经验证的因果流式 AGC。原主链相位选择的既有边界仍适用。

最终有效报告 `LDPC78_Link_device-amplitude_20261015_211558_852.mat`：

| 幅度处理 | 输入/输出功率 | LDPC 后 BER | FER | 比较帧 |
|---|---|---|---|---|
| 原样 | 未额外测量 | NaN | NaN | 0/878 |
| 固定 RX RMS | 14012 / 1 | 0 | 0 | 878/878 |
| 原快速包络 | 14012 / 1.69905 | 0.279672 | 0.560364 | 878/878 |

固定缩放即恢复，证明该固定 case 的 EQ-off 失败对输入幅度尺度敏感，不需要
改变 LDPC 图或引入多径滤波才能恢复。尚未单独分离 Gardner 与后续载波环的
责任。快速包络在 FSE 前可用，不代表直接搬到 Gardner 前也可用；其误码和
约 51.05% 帧锁定遥测如实保留，不以 878/878 关联覆盖冒充持续帧锁定。
固定 RMS 的载波锁定遥测约 78.44%，也不能因最终 BER=0 就改写为全程锁定。
正式修复需要单独定义同步前功率标度/增益变化速度与下游环路的约定，诊断开关
未设为默认、未替换现有均衡开启路径。本轮试运行的两个无效报告已删除。

### 仍未完成的验收

- 已做官方 TX 码字与图结构一致性、无噪声、少量错误及固定 LLR 的 BP 对照。
- 上述三例实际 LLR 与完整链路已完成；其它时间区间、seed、噪声条件和设备
  精确文件/配置对齐仍需单独验证，不能由这三例推广为所有信道零误码。
- 不从固定 LLR 实验推断链路 coverage/FER、相位重捕获性能或设备门限。
- 归一化/偏移最小和比较留到 BP 和实际接收 LLR 对照确认后，不混进本次图替换。
- 若放弃实验，将 `LDPCDecoderMode` 留在默认 `legacy-dense-bp` 即可完整回退；
  生成的结果是独立审计资料。旧缓存无需恢复，因为没有被改写。
- 稀疏模式使用 7/8 专用的缩短位、填充位和信息位契约，不再套用旧的
  “追加未知打孔位、取前 k 位”通用假设。
