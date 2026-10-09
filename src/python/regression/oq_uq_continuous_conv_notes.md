# OQPSK/UQPSK 连续卷积接入（2026-10-07）

## 边界

保留 TMgenerator、成形/接收滤波、OQPSK 半符号错位、UQPSK 三比特/两符号映射、载波和定时同步、soft demap、公共 Viterbi 与 RS 数学。仅把合路软比特接到已有 `HelperTMContinuousConvReceiver`。正式成形仍为 RRC/none，不开放 RC。

新路径限定 single、NRZ-L、ASM 开、加扰关。五种码率为 1/2、2/3、3/4、5/6、7/8。级联仍限非缩短 RS223/RS239 和 I=1/2/3/4/5/8；本轮不实现分路、缩短码或设备 I=6/7。

UQPSK 原有的两个分组起点不变，但新路径改用译码后 raw ASM 证据选择，不能按 TX BER、已比较 bit 数或 BER=0 早停。公共连续路径的外层相位比较也去掉了 `bitsComparedBest<=0` 作为替换候选的条件。旧模式和非卷积 UQPSK 保留原行为。

连续编码/软比特接收状态不等于全链路实时接收：本次仍由 `finalize()` 汇总 ASM 捕获，未实现逐块实时帧输出或损伤后的在线重捕获。

## 唯一专项测试入口

`test_oq_uq_continuous_conv.m` 集中全部阶段，不为不同调制/码率复制脚本。波形只在内存中用于比较；落盘保存参数、日志、逐阶段 SHA-256 摘要和验收指标。失败也只保存可复现的参数/seed/日志，不自动转储大波形。

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
baseline = test_oq_uq_continuous_conv('baseline');
half     = test_oq_uq_continuous_conv('half');
three    = test_oq_uq_continuous_conv('three');
contract = test_oq_uq_continuous_conv('contract');
high     = test_oq_uq_continuous_conv('high');
rs       = test_oq_uq_continuous_conv('rs');
phase    = test_oq_uq_continuous_conv('phase');
timing   = test_oq_uq_continuous_conv('timing');
legacy   = test_oq_uq_continuous_conv('legacy',baseline);
existing = test_oq_uq_continuous_conv('existing');
guards   = test_oq_uq_continuous_conv('guards');
```

建议逐行运行，每一级断言通过后再执行下一级。返回的是小型 MAT 记录文件；`load(file,'records')` 可读取每组 `Options`、`Log`、`BER`、`FER`、`Compared`、`Pass` 和失败原因。复测 baseline/legacy 只有在两次之间确实有代码改动时才构成改动前后验证，本轮的冻结基线在生产改动前采集。

## 测试定义

- baseline/legacy：OQPSK/UQPSK × RRC/none × none/RS223/Conv 1/2，共 12 组。后者逐项比对冻结基线中的 TX、参考星座、原始/粗同步/定时/载波输出和相位选择的摘要，以及覆盖和尾部信息。
- half：两种调制和两种成形，1/2 共 4 组。
- three：3/4，TF=256/257/258 Byte，卷积输入为 2080/2088/2096 bit，对打孔输入周期 3 余 1/0/2，共 12 组。
- high：2/3、5/6、7/8，TF=258 Byte，共 12 组；5/6、7/8 分别余 1、3。
- contract：两种调制 × 五种码率，共 10 组；真实 TX batch/split 比特及波形相同，真实 none 软流丢弃开头一个接收 bit 后，整段/随机分块/1、2、3 bit 短块的公共接收输出和诊断完全一致。另有 20 个短输入/全零软流负控。本项只比较共同有效数据，不拿 14 个恢复帧冒充 120 帧测量覆盖。
- rs：每种调制/成形抽查 RS223 I=1 + 3/4、RS239 I=1 + 5/6、RS223 I=4 + 7/8、RS239 I=8 + 2/3，共 16 组；不是所有 RS×I×码率全组合。
- phase：3/4，另一 seed=20260927，相偏 +90/-90 度，共 8 组。
- timing：3/4、seed=20260927，定时偏移 0.5/1 个输入 sample，共 8 组；不叠加相偏或频偏。
- existing：七种已接入普通调制/APSK × RRC/none，非整除 3/4，共 14 组，覆盖公共候选选择改动。
- guards：未支持请求和旧路径非整除限制的负向检查。

正向主链用例均为 No-H、无噪声、10 Msym/s、SPS=8、8 帧预热、120 帧测量，要求 BER/FER=0、120/120、无未恢复或已恢复未比较帧、主体和尾部 Fs 一致。串联码要求 RS 前码字差异、纠正符号数、不可纠帧均为 0，测量映射 120 帧；RS 前重编码一致性与最终 TF 对 TX 零误码联合验证，不以纠错成功掩盖接口错误。

## 已完成验收

2026-10-07 实际执行：half 4/4、three 12/12、high 12/12、rs 16/16、phase 8/8、timing 8/8，共 60/60 新路径主链用例通过，均 BER/FER=0、120/120。RS 16 组测量区码字差异及纠正符号数均为 0。

改动前 baseline 12/12 通过，改动后 legacy 12/12 与冻结摘要/覆盖/尾部逐项相同；existing 14/14 通过。contract 10/10 跨调用一致性通过（另 20 个短/无证据输入拒绝）；guards 14/14 明确拒绝。前端参数单元测试 35/35 通过，包含 OQPSK/UQPSK 的 RRC/none、卷积/串联码、五种码率，以及不符合条件时不偷偷修改参数。

前端现已对符合条件的合路请求自动选择新路径。MATLAB 直接调用仍需 `p.ConvolutionalReceiveMode='stream-raw-asm'`；未改变 legacy 默认，也未删除旧实现。

结果合并在 `tmp/oq_uq_continuous_conv_20261007.mat`，498268 Byte，约 0.5 MB。`Report.half.records`、`Report.three.records` 等包含各级完整日志和验收指标。顶层 `records` 同时保存改动前 baseline，可直接把这个合并文件传给 `legacy` 第二个参数。合并后已校验读回一致性，再清理本轮 11 个临时分阶段 MAT 文件；没有删除以前的测试脚本或历史结果。

归档命令在保存及读回断言通过后，退出时输出了 MATLAB Java 后台 `Java is shutting down` 提示，进程退出码为 0。各级链路测试此前均已正常完成；此提示没有被当作新的链路测试结果。

```matlab
S = load('E:/web_code/react/fft_project/react-fft/tmp/oq_uq_continuous_conv_20261007.mat');
disp(S.Report.three.records{1});
fprintf('%s\n', S.Report.half.records{3}.Log); % UQPSK RRC 1/2 的分组/ASM证据
```

未声称完成：有噪声/多径性能、频偏范围扫描、所有 RS×深度×码率全组合、分路/差分/加扰、全链实时化、浏览器手动端到端操作。短输入拒绝在公共接收器层验证，不等价于已经遍历主链所有尾部截断情形。本轮无需修改原有滤波、同步或软解调算法来获得通过。
