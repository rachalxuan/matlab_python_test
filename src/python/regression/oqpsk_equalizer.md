# OQPSK 抽头约束诊断与回归

## 本轮结论

原始失败点：OQPSK、none、CDL_D1、seed=917、30 Msym/s、8 SPS、
卷积 3/4、TF=258 Byte、215 个预热帧和 1546 个测量帧，关闭噪声和已知 H 补偿。
测试复用了用户保存的 `SystemTestInputs`，没有缩短波形或更换信道。

在约 80.3403 ms，抽头范数从 3.99997377 增至 4.00000825。
该次更新幅度只有 0.0006482，全部数值有限，旧实现却立即抛出
`OQPSKEQ:UnstableWeights`，中止整条链路。这是保护条件处理错误，
不是证据充分的“信道不可恢复”或“数值发散”。

固定同一份 CarrierSynchronizer 输出并匹配滤波，离线重放结果如下。
TX 波形仅用于事后比对，不参与抽头更新或方案运行时选择。

| 固定输入的处理 | 末尾抽头范数 | 编码比特错误 / 比较量 |
| --- | ---: | ---: |
| 不均衡 | 1 | 0 / 4,925,086 |
| 原 CMA，诊断中取消中止 | 4.08769 | 0 / 4,925,086 |
| CMA，保持原上限 4 并投影约束 | 3.99999 | 0 / 4,925,086 |
| 诊断用轻微正则化 + 约束 | 3.13931 | 0 / 4,925,086 |

约 75 ms 的输入回归向量协方差条件数约为 809；原始最终抽头约 86%
的能量落在最弱的三个特征方向。该现象与相关输入下的系数漂移相符，
但不能由此推断全部信道的失败原因。正则化没有在本例带来额外误码收益，
因此没有加入新的生产参数；也没有放大原来的范数上限。

## 已实施的最小修改

`HelperTMNormalizedTapUpdate` 只复用复数归一化梯度更新和稳定性约束。
调用方仍负责选择输入采样和计算 CMA/MMA/RDE/DD 等误差。

OQPSK 保持原来的匹配滤波、T/2 FIR、交替 I/Q 眼中心更新、软解调和译码。
更新超过范数上限时，把候选抽头投影回同一个允许范围；候选非有限时拒绝
该次更新并计数。没有跳过接收样本、错误帧或 BER 比较，也不重置累计量。

普通公共均衡器的 DD 路径复用此函数，但保持原来的“越界就拒绝本次更新”
策略，其公式与策略通过 1000 组逐项等价检查。没有顺手改变其 CMA、
载波环、判决门限、FEC，亦没有重写 PSK 的官方 2 sps CMA 路径。

这不是把所有调制强行改成同一种 CMA：共用的是更新内核，OQPSK 的半符号
错位和其他调制的参考星座仍由各自已有适配层处理。

新增结果字段：`AdaptiveEqualizerProjectedUpdates`、`RejectedUpdates`、
`UpdateAttempts`、`PeakTapNorm`、`MaxCandidateTapNorm`、`FirstConstrainedSample`
（后五项也带 `AdaptiveEqualizer` 前缀）。未提供该遥测的其他路径为 NaN。
约束触发次数和 `OutputAccepted` 都不是正确判决概率或收敛证明。

## 已确认的验收范围

- D1 + none 主链：BER=0、FER=0、1546/1546，已恢复未比较帧为 0。
  投影更新 7392 次，非有限拒绝更新 0 次；原始波形长度不变。
- D1 + RRC 主链：BER=0、FER=0、1546/1546，已恢复未比较帧为 0，
  投影更新为 0，末尾范数 2.80091；原已通过路径没有出现退化。
- No-H：RRC/none × 无编码/卷积 3/4 × 均衡开/关，8 组均为 120/120、BER=FER=0。
- 固定复数回波：同样 8 组均为 120/120、BER=FER=0。
- 固定回波、另一 seed、分别施加正负 3 kHz、30 度或 0.5 sample 偏移：
  RRC/none 共 8 组均为 120/120、BER=FER=0。
- BPSK/QPSK/8PSK/UQPSK/16QAM/32QAM/16APSK/32APSK：8 组原始
  No-H、均衡关闭的普通链路冒烟检查均为 120/120、BER=FER=0。
  这不能代替各调制开启自适应均衡后的多径验收；公共 DD 本轮的非退化依据
  是逐项更新公式和拒绝策略的等价测试。

以下是**尚未通过的接收性能点**，不是零误码验收结果。BER 仅代表已比较量：

| 原来会中止的 none 用例 | 修复后 BER | 比较帧 / 应测帧 | 已恢复未比较 |
| --- | ---: | ---: | ---: |
| CDL_B1 | 0.000398708 | 1186 / 1546 | 2 |
| CDL_A4 | 0.393707 | 1404 / 1546 | 2 |

二者不再因抽头上限中止，但覆盖不足必须保留为失败，不能解释为已恢复整个链路。
本次并未证明这两个信道不可恢复，也未完成全部调制的 CDL 性能验收。

B1 + none 再做完全同配置的 EQ OFF 对照：BER=0.000445778、FER=0.0280778，
只比较了 463/1546 帧，已恢复未比较也是 2 帧。第 216–1296 帧记录为
`unobserved-leading`，1297/1298 为 `recovered-not-counted`，1299 才开始比较。
可见 B1 在不经过该均衡器时已有严重覆盖问题，不能归咎于本次范数投影。
开启均衡提高了比较覆盖，但两个 BER 的比较区间不同，不能据此直接量化误码改善。

## 复测命令

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));

% 单元、短链路、独立损伤：不保存大波形。
test_oqpsk_equalizer('unit');
test_oqpsk_equalizer('baseline');
test_oqpsk_equalizer('multipath');
test_oqpsk_equalizer('offsets');

% 原始 D1 失败点：原样加载用户保存的配置。
T = test_oqpsk_equalizer('saved', ...
    fullfile(root,'tmp','TM_System_EQ_cdl_20261010_230304_623.mat'),13);
assert(all(T.ZeroErrorComplete));

% 两个困难点仅如实输出，不预设 BER=0。
B = test_oqpsk_equalizer('saved', ...
    fullfile(root,'tmp','TM_System_EQ_cdl_20261010_215755_087.mat'),13);
A = test_oqpsk_equalizer('saved', ...
    fullfile(root,'tmp','TM_System_EQ_cdl_20261010_103527_648.mat'),20);
```

`saved` 模式要求给出保存文件和明确的 case 序号，不偷偷改帧数、预热、
信道、均衡开关、seed 或采样参数。它报告 `ZeroErrorComplete`，
并不把“运行结束”当成 BER 验收通过。

## 后续方案

先固定 B1 的第一个异常区间，比较均衡前后的同一段数据：载波相位、
I/Q 采样位置、抽头变化、译码前错误和帧边界。保留现有载波/译码参数，
不用整批扫描或按 BER 选择生产接收路径。必要时可做仅离线的 TX 辅助
线性均衡上界实验；上界能恢复说明接收实现有改进空间，上界失败也不等于
已经证明理论不可恢复。

只有确定剩余误差来源后，再决定是否增加正则化、时变定时跟踪或门控 DD。
共享层继续以 FIR/归一化更新/稳定性遥测为边界，避免为了统一名称而重写
已验证的调制器、同步器或调制特有的误差观测。
