# APSK 连续卷积接入记录

## 改动边界

在 `run_ccsds_tm_evaluation.m` 的 `localUseContinuousConvStreamReceiver` 中允许 `16APSK/32APSK`。继续使用原 TMgenerator、pilotless 前端、APSK soft demapper 和 `HelperTMContinuousConvReceiver`，不新增 APSK 专属 Viterbi、不修改打孔图样、不调整同步带宽或幅度算法。

MATLAB 直接调用仍需显式指定 `ConvolutionalReceiveMode='stream-raw-asm'`，未改变旧调用的默认路径。前端 `CONTINUOUS_CONV_MODS` 已加入 16APSK/32APSK，符合条件的卷积/串联码请求自动提交新路径，无须新增页面开关。此入口仍限合路 single、NRZ-L、ASM 开、加扰关；RS 限非缩短 RS223/RS239，I=1/2/3/4/5/8。未覆盖的分路、差分、加扰和缩短 RS 不在本轮开放范围。

APSK 软值采用 MSB 顺序，正值表示 bit 1。回归枚举所有 16/32 个标签，同时调用 FACM 命名的共用数学 helper 和生产 `HelperCCSDSTMDemodulator` 验证，不添加额外反相适配。相位候选和打孔候选沿用 raw ASM 结构评分，不以 TX BER 选参数。TX 真值仅在接收候选确定后的评估中使用。

## 测试分级

`test_apsk_continuous_conv` 使用真实主入口，每组 No-H、无噪声、8 帧预热、120 帧测量，默认 seed=20260927。首个失败即停止并保存完整样本，不自动切回旧接收器，也不调参后将原失败标成通过。

1. `conv`：16/32APSK × RRC/none × 1/2、3/4、5/6、7/8、2/3，20 组。TF=258 Byte，ASM+TF=2096 bit；对于 3/4、5/6、7/8 分别余 2、1、3 bit，是真正非整除测试。
2. `rs`：相同 20 组，外码 RS223 I=1；ASM+RS=2072 bit，其中 3/4 和 5/6 非整除，7/8 恰好整除。不能把此 7/8 结果当成非整除串联码证据。
3. `rs-spots`：RS239 I=1/2/3/4/5/8 分别配 1/2、3/4、5/6、7/8、2/3、7/8，跨两种 APSK 和两种成形，共 24 组。I=4 的 7/8 输入为 8192 bit、余 2，属于非整除；I=8 输入为 16352 bit、可被 7 整除，是长交织块对照。这是交织深度代表抽查，不是所有 RS×I×码率的笛卡尔积验收。
4. `phase`：3/4、TF=255 Byte、seed=917，分别相偏 +90/-90 度，跨两种 APSK 和两种成形，共 8 组。验证另一种映射/帧余数及相位候选，不叠加频偏/噪声/多径。

每组要求 BER=0、FER=0、120/120、无未恢复或已恢复未比较帧；none 的主体及尾部必须保持每符号 SPS 个一致采样点。串联码还要求测量区 RS 前码字差异为零、RS 纠正符号数为零、映射帧数为 120。RS 前指标来自重新编码译码后 TF 与接收 RS 码字的比较；与最终 TF 对 TX 的 BER=0 联合使用，排除 RS 修正或错误有效码字掩盖边界错误。

## 原始记录

- 首轮 `conv`：`tmp/tpb44a39b1_a0d7_41c7_9f51_15e84c8e9d64`，前 15 组通过，第 16 组期间 MATLAB 进程退出 `0xc0000374, Heap corruption`。无该组最终结果，不能算通过。
- 第 16 组同配置独立复现：`tmp/apsk_conv78_none_crash_probe.mat` 和 `.log`，32APSK/none/7/8，BER=0、FER=0、120/120。不能据此声称已确定原进程崩溃的原因。
- 完整独立 `conv` 重跑：`tmp/tp41325141_3243_41b2_8836_68b659de27c8`，20/20 通过，包括原退出位置的同一配置；每组 BER/FER=0、120/120。
- `rs`：`tmp/tp4620e609_d616_4491_b593_50e2550b868f`，20/20 通过；每组 BER/FER=0、120/120、测量区 RS 前错误和纠正符号数均为 0。
- `rs-spots`：`tmp/tp769ab699_e436_4315_849d_0a1b8817c1f6`，24/24 通过；每组 BER/FER=0、120/120、测量区 RS 前错误和纠正符号数均为 0。
- `phase`：`tmp/tp5320582f_d497_43da_bbf1_955336a8216b`，8/8 通过；每组 BER/FER=0、120/120。
- 合计 72/72 个专项链路用例通过；不把首次进程退出当作成功或从记录中删除。这里不是所有 RS 参数组合的穷举，也不是有噪声/多径下的性能结论。
- `test_apsk_continuous_conv_guards`：14/14 个未支持配置/旧路径非整除请求均被拒绝；没有全局删除旧路径的帧长保护。
- 旧路径等价回归：`tmp/tp5d8b6c10_0ac6_4ad5_80ac_7f01528f9768`，19/19 组输出与清理前冻结基线相同；包括 APSK 无编码/独立 RS/LDPC，以及普通调制对照。
- 前端参数契约测试：`parameterContract.test.js`，31/31 通过，覆盖 APSK 普通 TM/pilotless、RRC/none、五种卷积码率及串联码的新路径提交，并检查不支持配置仍明确拒绝。这是参数单元测试，不代表浏览器端到端操作或完整信道性能验收。

## 复测命令

建议各级分别运行，先确认上一级 PASS，再执行下一行：

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
convDir = test_apsk_continuous_conv('conv');
rsDir = test_apsk_continuous_conv('rs');
rsSpotDir = test_apsk_continuous_conv('rs-spots');
phaseDir = test_apsk_continuous_conv('phase');
test_apsk_continuous_conv_guards;
```

只测某一码率可指定第二个参数，例如 `test_apsk_continuous_conv('conv',"3/4")`。函数返回目录内保存逐组 MAT、console.txt、summary.csv 与 summary.mat。

单独使用主入口时，在原配置里保留以下选择：

```matlab
p.modType = '32APSK';
p.PulseShapingFilter = 'none'; % 或 'root raised cosine'
p.channelCoding = 'convolutional';
p.ConvolutionalCodeRate = '7/8';
p.ConvolutionalReceiveMode = 'stream-raw-asm';
p.NumBytesInTransferFrame = 258;
p.DataPathMode = 'single';
p.PCMFormat = 'NRZ-L';
p.hasASM = true;
p.RandomizerEnabled = false;
% 其余仿真长度、噪声、频偏等配置仍由调用者明确设置。
result = run_ccsds_tm_evaluation(p);
```

这只是连续卷积接口接入验收，不是 CDL/TDL 下的全系统性能验收，也没有把整段批处理改成设备式实时接收。
