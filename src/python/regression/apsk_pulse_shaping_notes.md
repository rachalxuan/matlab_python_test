# APSK ordinary TM：RRC / none 接入记录

## 当前状态：后级幅度修复后 68/68 通过

普通 No-H APSK 后级已改用既有判决导向幅度估计，并修正 decision 模式 fade 退出时
被原始功率重设增益的问题。原两个 seed=20260927 失败例归零，完整成形/LDPC/RS
验收 68/68 均 BER=0、FER=0、120/120。
生产修改仅两个 helper；现有 H 专用策略保留。
详见 `apsk_gain_fix_acceptance.md`。以下为保留的历史诊断/验收过程。

## 2026-09-27：第四步扩展验收，66/68，尚不能全部验收

后续固定波形诊断已定位这两个失败例：pilotless 后级短时功率幅度 tracker 将数据环占用
波动误当成衰落，推高两个中环点，详见 `apsk_seed20260927_findings.md`。
下方“尚未证明首次错误级别”为验收结束时的历史状态；生产算法仍未因此修改。

新增 `test_apsk_pulse_acceptance.m`，本轮只加测试，不修改生产接收链。
每例 No-H、无噪声，10 Msym/s、SPS=8、warmup=8、测量 120 帧。
16/32APSK × RRC/none 各运行 17 例（共 68）：

- 未编码 TF=256 Byte，零 CFO/相偏/delay 基础例；seed 单独改为 20260925、20260927。
- seed=917 下单独改 delay=0.5/1 输入采样点、相偏=-30/+30 度、CFO=-50/+50 kHz。
- 未编码 TF=254/255/257/258 Byte（256 已有基础例），以及 TF=255、delay=1。
- LDPC 1/2、K=1024、非 SMTF；非缩短 RS223 I=1；非缩短 RS239 I=2。
  编码例都是 seed=917、零损伤代表例，不是全部 FEC/码率/交织深度覆盖。

全部 68 例覆盖 120/120，未恢复帧和已恢复未比较帧均为 0。
实际普通 TM、pilotless、无额外导频、主体/尾部采样率及定时入口检查均通过。
其中 66 例 BER=0、FER=0；12 个 LDPC/RS 编码例全部通过。

两个失败例为 32APSK、seed=20260927、TF=256、无编码、零损伤，RRC 与 none 各一个。
两者均在 TX 第 60 帧（2.4544–2.4960 ms）产生 2 bit 错误；
总比较 245760 bit，BER=8.13802083333333e-6，FER=1/120。
错误帧已正常计入统计；失败保存完整中间波形，脚本末尾验收断言明确失败。
两种成形出现同 seed/同帧错误，不支持将其直接判成 none 独有缺陷。
诊断的 ASM-phase-slip 提示只是线索，尚未证明首次错误发生的级别；不得据此直接改载波环。

20 组独立 TX 检查通过：16/32APSK × RRC/none × TF=254:258，
17 帧逐帧调用与一次性发送波形/编码 bit 逐元素相同；使用同一生成器延续尾部后，
与“原数据+相同 guard”一次性生成结果也逐元素相同。
32APSK 每帧余数 4/2/0/3/1 全部覆盖；17 帧后缓存为 68/34/0/51/17 bit，
说明缓存以调制处理块为单位，不能误要求 pending bits 必须小于每符号 5 bit。
未编码 bit 总数严格等于帧数乘以 (32+8*TFBytes)，没有逐帧悄悄补 bit。

9 种调制冻结 RRC 基线再次通过，波形及关键接收输出逐元素一致。
这证明冻结用例未退化，但不等于新 seed 的更长测量也必然无误。

结果目录：`tmp/tp63073790_9ecf_426c_af05_892069c58600`。
冻结基线：`tmp/tpbf0139ba_1913_4e15_a5a6_d0aae1dc9000`。
`summary.csv` 为接收验收，`buffer.csv` 为缓存验收；每例 MAT 包含实际配置、结果和日志。
成功例不保存大波形，失败例保留 `r.BaselineCapture`。

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
outDir = test_apsk_pulse_acceptance; % 跑完全部，存在上述反例时最后断言失败
% 也可单独运行：test_apsk_pulse_acceptance('fec') / ('uncoded') / ('buffer')
```

失败时函数不返回 outDir，但实际目录已打印，结果在断言前全部写入。
下一步应固定上述两个失败 capture，逐级核对同一个第 60 帧；本轮没有调参掩盖失败。

## 2026-09-27：矩形接收与定时配套修复已验证

APSK `none` 复用原矩形滑动匹配 FIR，但不再在 Gardner 前固定抽取到 2 sps。
匹配输出保留输入 SPS，现有 `HelperTMSymbolSynchronizerChunked` 按实际 SPS
恢复到 1 sps，随后仍走原 pilotless、soft demap 和 TM 译码。
这是滑动积分匹配滤波加定时插值，不是另写一个积分清零接收机。
TX、尾部矩形保持、载波算法、FEC、warmup 和 BER 计数规则均保持原样。
RRC 和其他调制仍走原滤波/采样率分支。

另修正定时遥测：官方定时轨迹按输入采样返回，不能截成输出符号数；
窗口时间和相位增量使用实际输入 SPS 换算。该修复不反馈至接收算法。
APSK `none + 2-sps FSE` 当前明确报不支持，避免采样率错接或偷偷关闭均衡。

验收结果：

- 原核心 8 组：16/32APSK × seed=917/20260925 × delay=0/1，
  全部 BER=0、FER=0、120/120；主体和尾部 SPS 保持检查通过。
- 扩展 30 组：包含分数 delay=0.25/0.5、delay=2/3.5、上述两个 seed，
  非零 CFO=±1/±50 kHz 配合初相 30°、卷积 1/2，以及 SPS=4/16 的代表用例。
  全部 BER=0、FER=0、120/120。不是这些参数的全笛卡尔积。
- BPSK/QPSK/8PSK/OQPSK/UQPSK/16QAM/32QAM/16APSK/32APSK 的 RRC
  完整 TX 波形、参考星座、粗同步、定时和细同步输出均与冻结基线逐元素一致；
  各自 BER=0、FER=0、16/16。
- 定时轨迹长度/时间轴单测通过，打开遥测不改变信号输出。

结果：`tmp/tp1b7f001b_463f_4330_a653_74ec3d524736/summary.csv`（核心），
`tmp/tpcad9fe02_0035_42dc_84fc_0782ca36bc1f/summary.csv`（扩展及 RRC）。
这些是 No-H、无噪声验收，不能外推为多径、噪声、全部 FEC 或 FSE 已通过。

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_apsk_pulse_shaping;
test_apsk_none_timing_contract;
```

以下保留最初接入记录及失败数据，描述的是修复前版本。

## 初始接入范围（历史）

本阶段仅开放 16APSK、32APSK 的公共成形参数入口，并将二者加入
`HelperTMCompleteBurst` 的矩形保持名单。主体和 guard continuation 共用该适配。
RX 已调用 `localTMReceivePulseFilter`，无需新增 APSK 接收滤波分支。
同步带宽、定时算法、pilotless 载波恢复、软解调和 FEC 均未修改。
范围为 single/合路普通 TM；不代表分路或 FACM 支持。

## 重跑

在项目目录执行：

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('src/python/regression');
test_apsk_pulse_shaping;
```

脚本默认读取 `tmp/baselines/rrc_pre_apsk_migration_20260925_224040` 的冻结基线，
也可将该目录作为第一个参数传入。输出目录在启动时打印。
每例先保存配置、完整结果和日志；所有 case 完成后写出 summary.csv，再执行最终验收断言。
有误码或覆盖不足即报错，不将“代码执行成功”当作“通信验收通过”。

## 2026-09-25 实测

结果目录：`tmp/tpa37b7ba8_7bed_4da2_9a05_0a13d16cd251`。
No-H、关闭噪声、无 FEC、TF=256 Byte、10 Msym/s、SPS=8、warmup=8。

- RRC：两种 APSK 均 BER=0、FER=0、覆盖 16/16；完整 TX 波形、参考星座、
  粗同步输出、定时输出、细同步输出与原冻结基线逐元素相同。
- none：每种调制测试 seed=917、20260925，delay=0、1 个输入采样点，测量 120 帧。
- delay=0：四组均 BER=0、FER=0、覆盖 120/120。
- delay=1，16APSK：两个 seed 分别为 14 bit / 4 个错误帧、6 bit / 1 个错误帧，
  比较量均为 245760 bit，覆盖均为 120/120。
- delay=1，32APSK：两个 seed 均覆盖 0/120，BER/FER 为 NaN，不能报告为零误码。
- 八组 none 均通过主体与尾部逐符号 SPS 点重复检查、总采样数检查和 RX 2 sps 入口检查。
- 前端参数契约测试 29/29 通过。

结论：成形入口和主体/尾部采样适配已接通，RRC 基线不变；none **尚未通过非零定时偏差验收**。
以上检查不构成错误根因已经定位的证据。后续应保存并比较匹配滤波、定时和 pilotless
各级输出；本轮不为消除失败而调整同步参数、提高 warmup 或改变计数规则。
尚未覆盖有噪声、H 信道、不同 SPS 及其他 FEC 的组合。

summary 中 `FrozenRRCIdentical` 仅适用于冻结 RRC 用例，
`BodyAndTailHoldVerified` 仅适用于 none；不适用的字段为 false/NaN。
通信验收看 `ZeroErrorComplete`，而非这些单项字段。
