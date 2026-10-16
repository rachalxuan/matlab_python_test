# 三个固定系统失败点：逐级诊断

诊断阶段只增加默认关闭的只读观测接口，没有改变均衡、载波、FEC、统计门限或实际测试参数。2026-10-11/12 在保存的原始配置和 seed 上复现。下文前三节保留当时证据；后续修复及当前测试命令见文末“已实施修复”。

## 复现入口

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));

% 读取此前保存的故障诊断，不重新运行已修改的接收器。
diagnose_tm_system_failures('report');
```

已有诊断结果时，只运行 `report` 即可重新生成离线分析，不必重新发送/过信道。脚本依赖以下原始归档，不能删除后继续声称可复现：

`bpsk/qam/apsk` 无后缀模式用于旧接收器上的严格复现，含原 BER/FER 断言；修复后的代码不应再满足这些故障断言。需要新增局部观察时用 `bpsk-after/qam-after/apsk-after`；日常验收用下文轻量回归，避免重复保存诊断样本。

- `artifacts/ccsds/system-eq/TM_EQ_cd_20261011_184320_360.mat`：第 6、67 项。
- `artifacts/ccsds/system-eq/TM_EQ_psd_20261011_201140_162.mat`：第 41 项。

每次固定用例运行保存一份 `Diagnosis_<case>_<timestamp>.mat`，只含有限局部样本、窗口统计和配置，不保存整段接收波形。重复运行会新增归档；不用反复重跑已经完成的用例。汇总文件为 `Diagnosis_fixed_cases_report.mat`，其中 `R.Sources` 记录所用归档的确切路径。

## 1. BPSK + C1 + none：CMA 的恒模假收敛与后续跟踪耦合

均衡关闭时原对照 BER=0；开启时 BER=0.372786、FER=0.571798，测量覆盖均为 773/773。故障约从第 440 帧、40.856 ms 开始。插入观测后精确复现原 BER、FER 和比较帧数。

匹配滤波固定相位网格在故障局部可以正确判决。FSE 输出却已不是干净的 BPSK：离线拟合发现，它主要由相隔两个符号的两个数据分量组成，二者相位约差 90°。40.6 ms 的 CarrierOutput 近似为：

```text
y[n] = 0.714 b[n] + j*0.683 b[n+2] + 残余误差
```

这解释了为何 CMA 指标很好却没有真正消除 ISI：对 b∈{−1,+1}，`|a*b[n] + j*c*b[n+2]|² = a²+c²`，不随数据变化。CMA 的恒模目标本身无法排除这种混合。

载波环后及第一次快速跟踪后，实轴仍以正确的 b[n] 为主，固定锚点对齐后的局部符号错误为零。第二次快速复增益跟踪后，约 40.92 ms 开始出现错误；41.1 ms 时实轴主要变成 `−0.713*b[n+2]`，而正确分量到了虚轴。当前 BPSK 默认 `legacy-dual` 路径会执行两次此类跟踪，即使后置均衡关闭也如此。

因此不是只发生了一个可由全局 ±180° 消歧解决的旋转，也不能仅以“关闭第二次跟踪”宣称根治。上游 CMA 的两分量混合是结构性问题，第二次跟踪是观测到的错误触发位置。帧时间和内部符号时间含滤波/译码延迟，不应要求数值完全重合。

建议下一步保留共享 FIR/抽头更新框架，验证适合 BPSK 的实轴/非圆性约束或误差准则，并明确载波跟踪的唯一职责。先在同一信号上做最小对照，再决定是否去掉重复跟踪；本轮未实施这些修复。

## 2. 32QAM + none + PSD −105：载波环相位分支滑移

该用例为 No-H、均衡关闭，输入采样 SNR 约 11.1979 dB；BER=0.348211、FER=0.697283，覆盖 3865/3865，观测运行精确复现。相同条件 RRC 对照 BER=0。此前已有零星错误，持续错误约从 31.858 ms 开始。

该 No-H 配置实际没有运行 QAM BPS，而是 `comm.CarrierSynchronizer('QAM')`。不能把这次问题归因于盲相位搜索。

故障附近匹配滤波及 Gardner 后的 CarrierInput 仍然稳定：局部 EVM 约 0.095–0.100，符号错误率约 0–0.00586，对齐 lag 不变。CarrierOutput 则出现持续约 +90° 的旋转：31.903 ms 约 +43°，32.159 ms 约 +84°，32.398 ms 约 +89°。同一末段去除局部单一相位后 SER 仅约 0.00195；固定原锚点则 SER=1。

载波环自身输出的相位估计直接记录到：

| 时间 ms | phEst 度 |
| --- | ---: |
| 31.65 | −0.547 |
| 31.86 | +0.706 |
| 31.90 | −36.666 |
| 32.10 | −91.073 |
| 32.35 | −91.346 |

因此持续错误首次产生于载波环，不是均衡、译码或统计覆盖问题。它不证明该噪声条件应该绝对零误码，但持续灾难性错误不能仅解释为普通 AWGN 误码。

下一步应冻结 CarrierInput，从记录起点保留完整环路历史重放，评估相位观测和环路更新保护。尚未证明缩窄带宽就能解决，也没有修改带宽。不能用短坏段重新初始化 PLL 冒充同状态对照。

## 3. 32APSK + D1：捕获前 ISI 破坏十二次幂频偏观测

本轮深入诊断原记录第 67 项（RRC，均衡关闭）；开启后置均衡的第 68 项也在均衡到达前失败。none 对应失败不能据此宣称已经单独验收或完全定位。

原捕获及仅重放归一化后的前缀得到相同资格判定，候选统计在数值容差内一致。十二次幂的四个候选约为 +119489、+29338、−158690、−15090 Hz；独立段验证能量约为 1.9695、1.1497、0.4268、1.4242，均远低于要求的 8.294，优势也不足 6 dB。拒绝候选是正确行为，不应直接放宽门限。

离线 TX 参考观察显示这一段存在约 −18.825 kHz 的公共相位变化，正确频偏没有进入候选。用户设置的额外频偏为零，不代表时变 H 信道之后的有效频偏也为零。环选择误纳比例仅约 0.18%；即使用真实环标签选择样本，原信号十二次幂观测仍很弱，因此不能只归咎于半径分类。

用一个离线上界实验判断是否有可恢复的信息：

- 只用训练段真值估计公共频偏及一个固定 17 抽头 FIR。
- 训练 15487 symbols；留出间隔后验证 11999 symbols，不使用验证标签训练。
- 仅去频偏/复增益时，验证 SER=0.2098、EVM=0.2093。
- 加该 FIR 后，验证 SER=0、EVM=0.0148。
- 将去掉的频偏重新加回 FIR 输出，原十二次幂捕获器仍需自己捕获：得到约 −18.826 kHz，验证能量约 5062.6、优势约 37.9 dB，正常接受。

这证明该前缀不是“信道信息已经完全不可恢复”；残余 ISI 对当前捕获方法是关键障碍。现有后置均衡必须等 pilotless 前端成功才能运行，故无法帮助已经失败的粗捕获。

17 抽头 FIR 使用了 TX 真值，仅是离线诊断，不是正式盲接收算法；该结果也不是整段 82 ms / 全帧 BER 验收。下一步应研究接收数据驱动的捕获前均衡或联合捕获，复用共享 FIR 框架但使用适合 APSK 的准则。不能把依赖可靠判决的后置 DD 均衡直接搬到捕获前，更不能给正式接收机喂入真实频偏或训练抽头。

## 诊断边界与实现

观测 helper `HelperTMObserveDiagnosticStage` 没有返回信号，默认不执行。接收器只把阶段样本送到本地测试回调；TX 参考在回调/报告里用于离线对齐、评分和上界分析，不参与接收决策。

固定锚点 SER 用于保留分支滑移证据；LocalScalarSER 会去除每个窗口的单一相位/增益，只是辅助定位，不能替代真实 BER 或掩盖相位跳变。窗口中加入局部误差拟合也不能证明一条正式盲算法已经成功。

三个问题应依次修复、分别回归：BPSK 的 CMA/重复跟踪，32QAM 的载波环，最后 APSK 的捕获与 ISI 先后关系；不能通过一起调参得出责任归属。

## 已实施修复（2026-10-12）

未修改 TX、信道、噪声、FEC、ASM、帧关联、预热及 BER 分母；没有把 TX 真值、真实频偏或 BER 反馈给正式接收器，也没有删除错误帧。三项按顺序实现：

1. **BPSK 的 2 sps 均衡**：直接复用已有 `HelperTMFractionallySpacedDualModeEqualizer`，以 CMA 捕获、同一组抽头 DD-NLMS 跟踪，避免单纯恒模判据容许两个正交数据流混合。默认关闭 FSE 后重复的两次幂次相位跟踪；显式历史覆盖值仍有效。QPSK/8PSK 的原路由不变。`AdaptiveFractionalDualModeApplied` 和日志报告实际算法，`AdaptiveEqualizerSamplingMode` 仍描述 2 sps 采样层。
2. **QAM 非 BPS 路径的载波环**：`HelperTMQAMCarrierSynchronizer` 以实际参考星座的最近点、距离及判决裕量产生相位误差，复用已有 `HelperTMSecondOrderCarrierLoop` 的 PI/NCO。官方对象仅用于有界前缀启动，之后从整段记录起点重放；不是截取坏段重新初始化。原带宽不变，不增设坏帧时间或 seed 特判。已有 H/QAM BPS 路径不改。
3. **APSK 捕获前盲均衡**：仅当粗捕获失败且调用者明确启用自适应均衡时，在原定时输出后、载波捕获前用 `HelperTMBlindAcquisitionEqualizer` 做一次旋转不敏感的 RDE FIR，再尝试原捕获器。抽头更新复用 `HelperTMNormalizedTapUpdate`。17 抽头、3 遍有界前缀学习，不按 BER 挑选参数；候选和留出验证期间冻结抽头，之后继续同一 RDE 更新以跟踪时变 ISI。原 CFO 资格门限保持不变；失败仍报错，均衡关闭仍不执行此路径。正常首次捕获通过的输入保持原流程。

APSK 新 FIR 是当前整段处理架构中的居中 FIR，有 8 symbols 前视并保持样本总数；不是新增实时流式接收功能。验证段不参与抽头训练；有限 FIR 邻域使段边界样本相关，不能将此称为严格统计独立性证明。其后原 pilotless 相位恢复、后置 DD 均衡及译码顺序不变。

### 固定原配置结果

| 原故障用例 | 修改前 BER | 修改后 BER / FER | 比较覆盖 |
| --- | ---: | --- | --- |
| BPSK C1 none，均衡开启 | 0.372786 | 0 / 0 | 773/773 |
| 32QAM No-H none，PSD −105，均衡关闭 | 0.348211 | 0 / 0 | 3865/3865 |
| 32APSK D1 RRC，均衡开启 | 捕获失败 | 0 / 0 | 3865/3865 |
| 32APSK D1 none，均衡开启 | 捕获失败 | 0 / 0 | 3865/3865 |

以上完整覆盖用例的已恢复未比较帧均为 0。32APSK D1 RRC **均衡关闭**仍如实报粗捕获失败，这是控制条件，不自动偷偷开启均衡。

已完成的补充检查：

- BPSK C1/D1 × RRC/none 原配置均为 BER=FER=0、773/773；C1 none 换 seed=20260927 同样通过。
- 32QAM RRC −105、16QAM none −105 分别为 3865/3865、3091/3091，BER=FER=0。
- 32QAM none −115 为 BER=FER=0、3865/3865。
- QAM 载波单元测试：16/32QAM × 两个 seed × 正负 500 Hz，固定相偏 0.71 rad，8 组无噪声回归通过。这里离线允许固定象限歧义，不允许按窗口重选相位来隐藏滑移。
- 9 种普通调制 × RRC/none × No-H 无噪声，30 帧预热、120 帧测量的 18 组短回归中，17 组 BER=FER=0、120/120；8PSK none 为 BER=0、105/120，另有已恢复未比较 2 帧。用修改前快照重跑此用例完全复现相同覆盖，属于已有问题，**不能将这一组计为通过**。
- 16APSK D1 RRC/none 仍有误码和覆盖不足：分别 BER=0.28517、2417/3091；BER=0.21832、2516/3091。与原归档结果相同，没有触发新捕获前均衡，尚未解决，不能宣称 APSK 全部多径验收。
- QAM 其他入口：16/32QAM + TPC 1/2 + none，均记录 BER=FER=0、120/120；16/32QAM + 分路卷积 1/2 + RRC，均记录 BER=FER=0、240/240（两路各 120）。已写入 `Repair_qam-integration.mat`，但该 MATLAB 批量进程退出时报 `0xc0000374, Heap corruption`，故仅认可已保存的功能数值，不计为干净结束的批量进程验收。

这只证明上述固定故障点及列出的回归，不证明所有噪声、C/D 子型号、频偏和帧配置均能零误码。期间有多 case MATLAB 进程发生原生堆退出，一次在中途、一次在所有 case 已保存后退出时发生；未完成部分不计为通过，批量进程稳定性仍待单独核查。三个原故障点的独立复测均正常结束。回归入口每 case 落盘，避免此前已完成的数据随进程丢失。

### 当前复测命令

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));

Tb = test_tm_fixed_repairs('bpsk');  % 原 BPSK C1 none
Tq = test_tm_fixed_repairs('qam');   % 原 32QAM none −105 PSD
Ta = test_tm_fixed_repairs('apsk');  % 先 EQ OFF，后 EQ ON；OFF 允许如实捕获失败

% 按需补充，不需要再次扫描全部 FEC/信道。
test_tm_fixed_repairs('bpsk-regression');
test_tm_fixed_repairs('bpsk-seed');
test_tm_fixed_repairs('qam-rrc');
test_tm_fixed_repairs('qam-16none');
test_tm_fixed_repairs('qam-lownoise');
test_tm_fixed_repairs('apsk-regression'); % 包含上述尚未解决的 16APSK 对照
test_tm_fixed_repairs('unit');
% 可选：TPC 和分路功能对照；本机曾出现上述原生退出错误。
test_tm_fixed_repairs('qam-integration');
```

命令复用归档 `inputs`，不另造有利的测试条件。原配置中的信道文件路径必须可访问。`RunCompleted` 只表示函数完成，不表示零误码；`ZeroErrorFullCoverage` 才同时检查 BER、FER、完整覆盖和已恢复未比较帧数。EQ OFF 捕获失败、已有 16APSK 失败都不会被改写成成功。

固定用例只保留一个回归入口 `test_tm_fixed_repairs.m`，同组复测覆盖更新 `artifacts/ccsds/system-eq/Repair_<group>.mat`，保存配置、表格、日志与小型诊断字段，不保存整段波形。`overrides` 是明确标记的诊断覆盖参数，不是正式接收器自动调参。只读逐级诊断入口和先前有限样本档案继续保留。

## 16APSK + D1 无噪声：后续只读定位（2026-10-12）

本轮没有修改正式接收算法。仅给已有阶段观测接口补充 APSK 内部状态出口，并扩展原诊断入口，未新增独立测试脚本。固定原 CD 档案第 60 项：16APSK、RRC、D1、30 Msymbol/s、SPS=8、卷积 3/4 连续接收、TF=258 Byte、430 帧预热、3091 帧测量、noiseMode=off、额外 CFO/相偏/delay 均为 0、盲均衡开启。

### 可重复性与 seed 的作用

| seed | BER | FER | 比较覆盖 | 未恢复 / 已恢复未比较 |
| --- | ---: | ---: | --- | --- |
| 917 | 0.285170 | 0.624741 | 2417/3091 | 672 / 2 |
| 918 | 0.349572028424 | 0.739351851852 | 2160/3091 | 929 / 2 |

917 的只读观测运行与原归档 BER、FER、比较帧数精确一致；918 只改变 randomSeed，保持信道文件、时间区间和其他配置不变。两次 MATLAB 进程均正常退出。原档案第 59 项（917，均衡关闭）同样失败。因此这是可复现且非单一 seed 独有的问题；误码数量、局部相位轨迹随发送数据改变，不能把它说成每次随机发生的运行异常。

此前用户提交的三项修复回归为 seed=918 的 4+1+4 组；`seed=20261012` 是建议增加的一批数据，不是把已有回归判作没跑，也不是开始诊断本问题的前提。

### 已定位的责任链

1. **不是原 32APSK 的粗捕获拒绝。** 917 的十二次幂估计约 −18824 Hz、置信度 27.75 dB，资格通过；918 约 −18828 Hz、26.13 dB，也通过。用户额外 CFO=0 不排除时变 H 引入有效频移。
2. **捕获通过不等于 ISI 已消除。** 在 917 的同一段定时后样本上，离线仅拟合公共 CFO 和复增益，留出验证段 SER=0.045361、EVM=0.20875。该度量去除了公共旋转，但没有用逐符号参考修正信号。
3. **相位搜索确实发生分支跳变。** 917 在约 1.109–1.246 ms 两个窗口间，BPS 前相位平滑变化约 9.7°；BPS 后相位变化约 −89.5°。这不是一个从头到尾固定、可由单次 ASM 消歧解决的象限旋转。整段 BPS 记录到 90 次重新捕获，fade hold 仅 83/615288 个观测块，不能将主要故障归咎于深衰落 HOLD；918 也有相位滑移，重新捕获 105 次。
4. **前置均衡触发条件漏掉这一类输入。** `HelperTMAPSKPilotlessFrontEnd` 仅在 coarse 与 acquisition 均不合格时尝试捕获前盲 FIR；16APSK 粗捕获已经通过，所以没有执行。这个条件能修复 32APSK 的捕获失败，却不能保证相位跟踪所需的输入质量。
5. **后置均衡实际退成了单抽头。** `HelperTMBlindCMAEqualizer` 根据短启动后的旁抽头能量占比判断 scalar，没有要求这一结构判断来自已充分收敛的多抽头解。917 旁抽头占比 0.0119、启动资格未通过，仍归类 scalar，DD=0；918 占比 0.0115、内部资格通过，也归类 scalar、DD=0。单抽头无法消除实测的跨符号干扰，因此开启开关不等于这里真正执行了有效的多抽头均衡。

### 同一失败样本的隔离对照

固定已保存接收前缀，不重新生成 TX/信道。训练与验证分开，验证 7297 symbols。参考只在测试仪器里做离线对齐、估计公共 CFO/复增益和评分；盲 FIR 只使用接收样本与公开星座环半径，不使用 TX/H/BER。

| 前端处理 | 验证 SER | 验证 EVM |
| --- | ---: | ---: |
| 仅去公共 CFO/复增益 | 0.045361 | 0.208750 |
| TX 参考训练的 17 抽头 FIR（仅作可恢复性上界） | 0 | 0.012776 |
| 复用已有 17 抽头盲 RDE FIR | 0 | 0.012333 |

独立的同前缀载波恢复对照中，原路径 SER=0.074962；仅关闭 NDA 残余 CFO 回填为 0.076470，仅关闭 ring normalizer 为 0.076744；先经过已有盲 FIR 再进入原捕获/BPS 为 0。这里只允许一个固定象限消歧和训练段幅度定标，没有逐窗口选择旋转。前缀从可对齐的第 11 个样本开始，因此其重新初始化的残余 CFO 数值不同于完整运行，不能把它冒充完整环路状态重放。

这证明该前缀有可恢复信息，残余 ISI 和均衡介入顺序是已验证的关键因素；不能据此承诺整段 82 ms 已达 BER=0，也不能宣称 none 已完成相同深度诊断。本轮未更改 FEC、ASM、BER 计数、同步带宽或接受门限。

下一步应复用公共盲 FIR，设计“相位跟踪之前的 ISI 处理/资格判断”，而不是只用粗频偏捕获是否成功决定是否需要均衡；同时修正未收敛抽头不能作为无 ISI 证据的结构判定。先固定本案例做全链 A/B，再检查 32APSK 原修复、No-H 与 RRC/none，避免按 seed 特判或仅放宽相位门限。

证据文件：`Diagnosis_apsk16_20261012_195608_067.mat`（有限样本约 13.8 MB）、`Diagnosis_apsk16_report.mat`（小型隔离结果）、`Diagnosis_apsk16-seed_20261012_200324_915.mat`（918 汇总，不保存第二份样本）。

复核命令（前两条读取固定 917 配置；最后一条只换成 918）：

```matlab
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
diagnose_tm_system_failures('apsk16');
diagnose_tm_system_failures('apsk16-report');
diagnose_tm_system_failures('apsk16-seed');
```

## APSK 均衡介入顺序与 FIR 结构修复（2026-10-13）

本节是上一节只读诊断之后的实现，不覆盖此前失败记录。

- `HelperTMAPSKPilotlessFrontEnd`：普通 TM pilotless APSK 开启 `blind-cma-lms` 时，先运行已有 17 抽头旋转不变盲 RDE，再执行一次原载波捕获/BPS。不再用“粗捕获失败”作为唯一介入条件，也不根据 seed、信道型号或 BER 选择路径。关闭均衡不自动代开。
- `HelperTMBlindAcquisitionEqualizer`：保留原更新公式、步长和训练预算；补充抽头、位置、输入/输出长度和训练/跟踪更新数。训练前缀与 CFO 留出验证段分离。该实现使用居中离线 FIR（8 symbols 前视），不冒充实时流式接收。
- `run_ccsds_tm_evaluation`：前置 FIR 已应用时，不再重复启动后置盲 FIR/DD，保留现有幅度跟踪。导出 `AdaptiveEqualizerPosition` 与 `APSKAcquisitionEqualizer`；`OutputAccepted` 只说明使用了输出，不将其伪装成独立收敛证明。
- `HelperTMBlindCMAEqualizer`：旁抽头能量仅作诊断，不再据此删除多抽头；公共 helper 显式 `adaptiveEqualizerTaps=1` 仍支持 scalar。旧 AutoScalar/SideTapOnRatio 参数不再控制自动降阶。DD 启动资格与输出质量回退保护保持原样，不能为了保留 FIR 强行开启不合格 DD。

未改同步带宽、相位算法、FEC、ASM、噪声模式、预热或 BER/覆盖统计。APSK 捕获前 FIR 继续沿用既有固定 17 抽头设计，不新增自动阶数选择器。

### 本轮验收

- 原 16APSK + D1 + RRC：seed=917、918 均 BER=FER=0，3091/3091，已恢复未比较帧为 0；批量进程正常结束。
- No-H 无噪声：16/32APSK × RRC/none × 均衡开/关共 8 组均 BER=FER=0、120/120，已恢复未比较帧为 0；进程正常结束。
- 单元测试：QAM 载波 8 组、前置 FIR 长度/旋转等变/冻结验证前缀、显式多抽头与单抽头结构检查均通过，进程正常结束。

- D1 其余成形：16APSK none 为 3091/3091；32APSK RRC/none 均为 3865/3865，三组均 BER=FER=0、已恢复未比较帧为 0，进程正常结束。
- 公共路径固定回归：BPSK C1 none 为 773/773；32QAM none −105 PSD 为 3865/3865；16QAM none −105 PSD 为 3091/3091，均 BER=FER=0、已恢复未比较帧为 0，进程正常结束。
- 公共 FIR 开启的短回归：16/32QAM × RRC/none × No-H 无噪声，4 组均 BER=FER=0、120/120、已恢复未比较帧为 0，进程正常结束。
- 保存的 APSK 诊断字段核验：前置 17 抽头 FIR，输入/输出符号数一致，`PostBlindStartupSkipped=true`，结构 `fir`，后置 `DDPasses=0`。原 16APSK RRC 两个 seed 各为 2461148/2461148 symbols。

本轮共 20 个全链用例通过，另有上述单元检查。没有扫描其他噪声、C/D 子型号或 FEC，不能由这些固定回归外推所有恶劣信道均零误码。最初两次测试因新诊断字段未对齐而中断，修正字段与结果导出后重新完整运行；这些中断不计入验收。

### 固定回归命令

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_tm_fixed_repairs('apsk16-fixed'); % 原 D1 RRC，917/918
test_tm_fixed_repairs('apsk-d1-pulse'); % D1：16 none、32 RRC/none
test_tm_fixed_repairs('apsk-noh'); % 两种 APSK × 两种成形 × EQ OFF/ON
test_tm_fixed_repairs('unit');
test_tm_fixed_repairs('bpsk');
test_tm_fixed_repairs('qam');
test_tm_fixed_repairs('qam-16none');
test_tm_fixed_repairs('qam-fir-noh');
```

沿用唯一的固定修复回归入口，每组覆盖保存小型 `Repair_<group>.mat`，未新增临时测试脚本或整段波形档案。

## 2026-10-13：QPSK Stage 2 公共逻辑审计（仅诊断，未修接收算法）

固定配置来自 `artifacts/ccsds/system-eq/TM_EQ_files_20261013_103200_321.mat`：
QPSK、RRC、调制器输入 100 Mbps（50 Msym/s）、SPS=8、卷积 3/4、TF=258 Byte、
seed=917、无额外噪声、保留原始 H 幅度、49 抽头 2-sps CMA。测量帧为 359～2935，
共 2577 帧。没有调整带宽、抽头、warmup、门限、FEC，也没有把 TX 真值反馈给接收机。

### 可复现性及归档

加入现有只读 `DiagnosticStageObserver` 并重跑原始配置后：

- 第 29 项 TDL D1：BER=0.000211871098150、FER=0.026256224536，2209/2577；与原档精确一致。
- 第 3 项 CDL A3：BER=0.000038541600864、FER=0.005432673652，2577/2577；与原档精确一致。

诊断文件在同一 `artifacts/ccsds/system-eq` 目录：

- `QPSK_stage2_diagnosis_case29.mat`：逐级窗口统计、帧关联、锁定轨迹和日志。
- `QPSK_stage2_diagnosis_case3.mat`：同上，加 9.5～14 ms 的有限局部接收样本和离线参考。
- `QPSK_stage2_logic_probes.mat`：连续卷积 ASM 最小反例。
- `QPSK_stage2_A3_offline_FIR_bound.mat`：仅用于诊断的 TX 辅助 FIR 拟合/独立验证结果。

总计约 14.5 MB；没有保存整段波形。一次性诊断脚本在完成后删除。

### 确定缺陷一：小幅度非零 H 被插值器清零

`run_ccsds_tm_evaluation.m / interpolateHMatrixCoefficients` 当前判断：

```matlab
if all(srcMag <= eps)
    coeff(pathIdx,:) = complex(zeros(1, numOut));
    continue;
end
```

ITU 618 的 H 幅度为 4.02889470059e-17，ITU 619 为 3.17535473733e-26；
两者各有 100000 个非零样本，均触发该条件。其功率约 1.62e-33、1.01e-51，
仍远高于 double 的最小正规数。`eps` 是 1 附近的浮点间距，不是物理接收门限。
这解释了后级 FSE 的无功率错误：它收到的信号已在信道层被清零。
缺陷与调制无关，不能通过提高均衡增益、归一化 H 或调整同步门限掩盖。
修正数值处理也不意味着如此大路径损耗下有噪声时仍可接收；链路预算需另行核验。

### 确定缺陷二：最长 ASM 好段被当作输出起点

`HelperTMContinuousConvReceiver / localFindPeriodicASM` 用最长连续好段评分，
又用 `positions(runStart)` 作为 `FirstFrameStart`，只返回该位置之后的帧。
评分证据的起点和物理数据输出边界因此被绑在一起。

最小反例：20 帧随机 payload、连续卷积 3/4、无噪声，先全部正确，再只将第 8 帧的
5 个 ASM bit 翻转后编码；payload 保持完全不变。

- 全部 ASM 正确：输出第 1～20 帧，20 帧 payload 全对。
- 仅第 8 帧 ASM 不满足门限：输出从第 9 帧开始，仅 12 帧，payload 全对；第 1～7 帧也被丢掉。

这是不需要多径或特定 seed 就能复现的公共逻辑缺陷。未来修正应保留有可信边界的早期帧和
真实坏帧，不能将“最长稳定段”作为可测数据全集；也不能盲目将所有未知起点前的数据强行配对。

### 确定缺陷三：锁定时间使用截断后序号，忽略物理位置

`localContinuousConvFrameSyncTelemetry` 生成 `ObservationIndex=1:n`，同时保留
`PeakPosition`；但 `HelperTMRuntimeLockTelemetry / localFrameTrack` 仅用
`(ObservationIndex-0.5)*FrameDuration` 生成时间，没有使用实际比特位置。

单元核验：保持 ASM 观测不变，将所有 `PeakPosition` 后移 723 帧（20.20544 ms），
报告的首次锁定仍为 0.04192 ms，没有随之移动。
所以本轮 TDL D1 的“很早锁定、无失锁”不能代表完整 82 ms 的真实帧锁定历史。
后续需按位置域、码率及译码/滤波延迟统一映射时间，未知区不得标成已锁定。

### TDL D1：真实局部失真、90 度滑移及全段单角度选择叠加

离线对齐固定 lag=-23，TX 真值仅用于评估：

- 11.02/17.00 ms：CarrierOutput 相对早期锚点相位约 0 度，4096-symbol 窗口 SER=0。
- 19.95 ms：CarrierInput 去除局部常数复增益后 SER 约 24.9%，说明失真在 PLL 前已存在。
- 20.035 ms：CarrierOutput 相对相位约 +51 度；20.116 ms 后进入约 +90 度分支。
- 21.018/60.012 ms：固定早期相位判决 SER=1，去掉局部整体旋转后 SER=0。

原始 H 在 20.2 ms、±25 MHz 内的最小/平均频响功率比约 -23.5 dB，21 ms 回到约
-8.2 dB。短时频率选择性失真与错误事件相邻，但这并不能证明现有盲均衡已达到最优性能。

主接收器对整段只选一个全局旋转，连续卷积路径又跳过原 coded-ASM 逐帧相位校正。
原始候选日志中，一种旋转有 710 帧最长好段、712 个好 ASM；另一种有 2213 帧连续好段。
最终选择后者，首个输出对应 TX 第 724 帧；724～726 帧又因 BER acquisition gate 尚未通过而未计数，
第 727 帧才开始比较。因此 368 帧缺口并非全部信道不可恢复：
前段和后段需要不同相位假设，而当前全段单一选择无法同时保留它们。

这里正确的问题是失锁/相位分支改变后的分段重捕获能力，不是换 FEC 或增加 warmup。
后续用接收端 raw ASM 证据做分段相位选择时，必须维持/重建 puncture 和 Viterbi 状态，
不能任意拼接译码比特，更不能按 TX BER 选择分段。

### CDL A3：先有均衡残余 ISI，不是同一类持续分支滑移

同一波形、对齐 lag=-22，10.03 ms 的 CarrierInput 局部标量校正 SER 约 4.20%，
CarrierOutput 约 4.17%；11.02 ms 分别约 3.93%、3.61%。载波后相位相对早期锚点
保持在约 0 度附近，没有 D1 那种持续 +90 度分支变化。约 20 ms 的采样窗口已无符号错误。
测量区最终 14 帧共 205 bit 错误仍正常计数。

9.5～14 ms 的有限样本另做离线线性拟合，训练/验证区间分开。10.1 ms 附近的
等效残余响应主抽头幅度约 0.822，在相对符号 +7、+8、-7、-15、-8 仍有约
0.140～0.182 的分量；33-tap 线性模型解释了约 97.8% 的接收功率。
使用真值训练的独立 FIR 验证将三个 4096-symbol 窗口的错误数从 167/152/97 降到 40/41/12，
但没有达到零错误。它只是可改进空间的离线证据，不是已实现盲接收机，也不是最优界的证明。

因此已定位到当前 CMA 后仍有明显残余 ISI；尚未分离有限抽头覆盖、纯 CMA 收敛/跟踪准则、
快速包络处理对残余误差的各自贡献，不能据此宣称只增加抽头或减小步长就能修好。

### 后续最小公共修正顺序（本轮未实施）

1. 修正 H 的非零/有限性判断及功率报告，不改物理损耗或噪声。
2. 分离 ASM 候选评分、物理帧输出边界、锁定时间轴；保留错误与未知状态。
3. 为连续卷积路径补相位分支变化后的接收端重捕获，先固定 D1 同一波形验证。
4. 在可信时间轴上单独研究 CMA 的残余 ISI，先同波形诊断，再决定公共更新规则/抽头设计。

这些是共享接口和状态语义的修正，不应增加 `if channel==D1`、`if seed==917` 等特例。
固定 seed 的失败可重复；更换数据/信道会改变触发位置，不等于 MATLAB 随机运行出错。
TDL A/B 等长时延场景仍需独立能力评估，不能由这两个局部诊断外推全部恢复为零误码。

### 2026-10-13 公共逻辑修正及回归

本次实施上述前三个确定缺陷的修正，不改 CMA/PLL 参数、FEC、噪声、H 物理增益，
不使用信道名或 seed 分支，也未实现 D1 的分段相位重捕获。

- H 插值仅跳过确实全零的路径，拒绝非有限系数。H-matrix 功率报告不再加绝对 eps
  底噪；幅度动态范围、相对频响和有效路径计数也按相对尺度计算，避免小 H 被误报为零路径。
  显式请求功率归一化且输入/输出功率为零或非有限时会报错，不伪造信号。
- ASM 最长好段仍只用于原有候选评分；输出改从**最早达到原 MinASMFrames 条件的好段**
  开始，包括该段的确认帧及此后的坏 ASM/坏 payload 帧。孤立的早期 ASM 不足以建立边界，
  未确认的起始数据不强行加入比较。
- 连续卷积帧遥测携带 decoded-raw-bit 位置域、原始帧长及名义打孔偏移。
  时间不再按截断后的 1:n 重置；无效坐标明确不可用。时间仍为接收输入相对时间，
  **不是校准滤波延迟后的 TX 绝对时钟**。逐帧记录在首个观测前保持未知。

`test_tm_fixed_repairs('qpsk-logic-unit')` 的 50 项检查全部通过：五种卷积码率，
每种覆盖完整输入/137 bit 分块输入，以及 clean、坏 ASM、坏 payload、启动未确认、
完全无法锁定五类输入。第 8 帧坏 ASM 的反例从原来的 12 帧恢复为 20 帧；刻意加入的
1 bit payload 错误仍为 1 bit，没有剔除错误数据。整体后移 723 帧时，帧锁定时刻同步后移；
损坏坐标不会回退到假想零点。原有 QAM carrier 和 FIR 结构单元回归也通过。

完整链路复用 `TM_EQ_files_20261013_103200_321.mat` 原始 inputs，seed=917，
QPSK/RRC、卷积 3/4、调制器码流 100 Mbps、无额外噪声、原均衡配置，2577 个测量帧：

- ITU 618/619：原来的无信号异常消失，均为 2577/2577，BER=FER=0。
  实际 H 增益分别约 -327.90/-509.96 dB；无噪声数字仿真可恢复不代表实际噪声下可接收。
- CDL A2：2577/2577，BER=FER=0，原通过点没有退化。
- CDL A3：2577/2577，BER=3.85416008639e-5，FER=0.00543267365，
  原有 205 个错误 bit 保留，不能宣称均衡残余 ISI 已修复。
- TDL D1：2209/2577，BER=0.00021187109815，FER=0.026256224536，
  已恢复未比较仍为 3 帧，继续报覆盖不足。首次帧锁定观测改为约 20.2423 ms，
  而不是原来约 0.04 ms；20 ms 前的 357 个测量帧的帧锁状态为未知。
  原有前后相位分支不一致未被掩盖，下一步仍需单独修复接收端重捕获。

复测命令（使用现有固定回归入口，不新增临时脚本）：

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_tm_fixed_repairs('qpsk-logic-unit');
T = test_tm_fixed_repairs('qpsk-stage2');
```

完整回归结果覆盖写入 `artifacts/ccsds/system-eq/Repair_qpsk-stage2.mat`，保留实际配置、
日志、统计和时间轴，不保存整段 IQ。没有创建一次性脚本，也没有删除历史诊断证据。

### 2026-10-13 QPSK 连续卷积的相位接续

新增 `HelperTMConvPhaseReacquirer`，默认仅接入 QPSK、single、NRZ-L、
`stream-raw-asm` 路径。支持该路径已有的五种内码率，以及原有串联 RS 外码。
其他调制、分路、PCM 格式和 legacy-coded-ASM 路径不变；不改 TX、CMA、PLL、
软解调映射、打孔图样、Viterbi 或 RS 译码算法。

实现仍是**离线整段接收**：四种旋转各自调用原软解调和
`HelperTMContinuousConvReceiver`，独立保留译码状态，然后按物理帧时间顺序消费
ASM 证据。不是完成持续流式前端，也没有向 PLL 反馈跳变相位。

规则与边界：

- 以最早得到原有 MinASMFrames（默认 4）连续确认的相位建立帧位置；不按最长晚期好段
  丢掉前段，不按 TX/BER/VCFC 选择相位。helper 不接收发送真值。
- 当前相位有效时保持；坏 ASM 达到现有失锁门限（默认 3）才失去确认。
  新候选必须唯一且连续通过原 ASM 门限，才恢复接收。多候选同样可信时不猜测。
- 相位候选必须来自同一长度软比特输入，并具有相同打孔起点和相容 raw-frame 网格。
  不支持把定时插删、打孔错位冒充相位变化；不兼容候选不会被拼接。
- 确认可释放尚未输出的缓存帧，但不覆盖已经输出的错误帧。切换期间无法确认的区间
  保持缺口；物理帧位置、warmup 和累计计数不重新归零。
- `ContinuousConvPhaseRecovery` 输出所选补偿角、相位事件、原始位位置及帧锁定轨迹。
  存在多个补偿角时 `PhaseAmbiguityRotation_deg=NaN`；星座快照明确是未做整体旋转的
  载波输出，不再冒充一份全段消歧后的波形。监控发布与页面说明同步更新。
- 原先只属于未旋转候选的 predecoder 诊断，在所选相位不同或改变时置为不可用，
  不发布成新接收器的 predecoder BER；最终译码 BER/FER 和覆盖继续正常统计。

测试结果：

- 70 项相位/连续状态测试通过：五种码率 × clean、固定 90 度、坏 ASM、坏 payload、
  帧边界 +90 度、帧内 -90 度、两次滑移 × 整段/137-bit 分块。无滑移无误切换，
  刻意注入的 payload 错误及已提交过渡错误保留，分块输出一致。
- 另测同样可信候选和无 ASM 证据，均不输出伪造锁定/帧。
- 8 项 No-H 主链路均为 120/120、BER=FER=0：五种卷积码率 RRC、
  RS223 I=1 + 3/4、RS239 I=1 + 5/6，以及卷积 3/4 + none。
- 原 CDL A2 仍为 2577/2577、BER=FER=0；CDL A3 仍有 205 错误 bit，
  BER/FER 和完整覆盖不变。本次没有修复 A3 残余 ISI。
- 原 TDL D1 从 2209/2577 增至 **2572/2577**，恢复未比较从 3 帧变为 0。
  检测到补偿角 90→0 度的一次接续。仍缺 TX 第 719～723 帧，约 20.06～20.20 ms，
  继续报告覆盖不足，不能宣称 D1 全部通过。
- D1 原新共同的 2209 帧错误数逐帧完全相同，共 966 bit；新增比较的 363 帧有
  7112 错误 bit，总计 8078 bit，BER 约 0.0015217。比原来 0.00021187 更高
  是因为把原来漏测的错误区间纳入了统计，不能对不同覆盖直接比较总 BER。

常用复测：

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_tm_fixed_repairs('phase-unit');         % 可控滑移、状态连续及拒绝歧义
test_tm_fixed_repairs('qpsk-phase-noh');     % 五种码率、串联码及 none
T = test_tm_fixed_repairs('qpsk-phase');     % 原 D1、A2、A3
```

只做原 D1 公平 A/B（同配置同 seed，唯一改变相位接续开关）：

```matlab
T = test_tm_fixed_repairs('qpsk-phase-ab');
```

第一行关闭、第二行开启 `enableContinuousConvPhaseReacquisition`。直接调用主入口时，
设此字段为 `false` 可回到全段单相位选择，用于诊断回退；不是按信道自动回退。
结果仍覆盖写入固定 `Repair_<group>.mat` 文件，不保存整段波形，不新建临时测试脚本。
