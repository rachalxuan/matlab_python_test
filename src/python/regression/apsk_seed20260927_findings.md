# 32APSK seed=20260927：固定坏帧逐级定位

后续修复已完成：普通 No-H APSK 默认使用现有判决导向幅度估计，两个失败例均归零，
完整 68 组回归通过。见 `apsk_gain_fix_acceptance.md`。
本文与诊断脚本保留旧 power 模式的失败证据，不代表修复后的默认行为。

## 结论

本例已定位到 pilotless 后级 `HelperTMComplexGainTracker` 的短时功率幅度估计。
它将数据序列的内/中/外环占用波动误当作信道幅度变化，额外放大约 1.43 倍，
将两个正确的中环点推入外环判决区。不是本例的 Gardner 错采样或载波相位滑移。
RRC 与 none 共用该后级，因而同一数据序列在同一位置出错。
这不说明只有这个 seed 才可能失败，也不否定其他信道条件下可能存在独立同步问题。

本次仅增加诊断脚本，未修改生产接收算法，也未扫描参数。

## 固定输入与真实性检查

输入：`tmp/tp63073790_9ecf_426c_af05_892069c58600/32APSK_{root_raised_cosine,none}_seed20260927.mat`。
No-H、无噪声、无编码、TF=256 Byte、零 CFO/相偏/delay、120 测量帧。
没有重新发射或生成信道，使用已有匹配滤波/定时/载波 capture。
Gardner 和完整 pilotless 重放均与 capture 逐元素相同。
TX 真值来自 none 的矩形保持波形，仅用于离线标签、固定延迟/增益对齐、误码核对。
RRC 定时输出的固定增益只在早期 4096 符号拟合一次；没有对坏帧单独校正。
最终 bit 使用项目原 `HelperCCSDSFACMDemodulate`，不进行真值辅助的相位或幅度修正。
最终错误数及错误帧与生产 ReceiverTimeline 一致。

## 精确错误位置

编号均从 1 开始。TX 第 60 帧，测量区第 52 帧，时间 2.4544–2.4960 ms。
TF 编号不包含前方的 32 bit ASM；字节内 bit 按 MSB first。

| 项目 | 第一个错误 | 第二个错误 |
|---|---:|---:|
| 连续发送比特编号（含 ASM） | 123139 | 123144 |
| 帧内编号（含 ASM） | 419 | 424 |
| TF 内 bit | 387 | 392 |
| TF Byte | 49 | 49 |
| 字节内 bit | 3 | 8 |
| 全局 TX 符号 | 24628 | 24629 |
| 帧内符号（含 ASM） | 84 | 85 |
| 5 bit 符号标签 | 10000 → 10010 | 01000 → 01010 |
| 出错 bit | 0 → 1 | 0 → 1 |

RRC 与 none 的位置、标签变化完全相同；TF 第 49 Byte 均从 `0x04` 变成 `0x25`。
实际 RX 符号索引因滤波时延不同：
RRC 为 24639/24640，none 为 24629/24630，不能直接按相同数组下标比较。

## 首次错误发生的级别

以下计数覆盖全部 120 个测量帧，阶段 bit 计数包含 ASM；本次错误全部位于 TF。

| 阶段 | RRC 错 bit | none 错 bit |
|---|---:|---:|
| Gardner 后，离线固定增益对齐 | 0 | 0 |
| 原载波恢复后、最终幅度 tracker 前 | 0 | 0 |
| 最终幅度 tracker 后 | 1 | 2 |
| ASM 后及最终归一化、实际 demapper 输入 | 2 | 2 |

RRC 的第二个错误由幅度 tracker 直接产生；第一个点已被推到边界附近，
后续全局归一化再乘 1.00586003575 才越界。
最终输出与 pilotless 输出只相差这个实数缩放，最大残差 4.97e-16，
所以不能把此处多出来的 1 bit 误判为 ASM 相位修正错误。

## 星座与判决边界

本项目 32APSK 中环半径约 0.70804，外环约 1.26770。

- 标签 16：正确点 (0.18325, 0.68391)，75°；错误点标签 18 为
  (0.48513, 1.17120)，67.5°。两点垂直平分线沿正确点角度的交点半径约 1.0074。
- 标签 8：正确点 (0.50066, -0.50066)，-45°；错误点标签 10 为
  (0.89640, -0.89640)，同为 -45°。边界半径为两半径中点，约 0.98787。

| 符号 | RRC tracker 前/后/最终半径 | none tracker 前/后/最终半径 |
|---|---|---|
| 24628 | 0.69943 / 1.0029 / 1.0087 | 0.70706 / 1.0143 / 1.0203 |
| 24629 | 0.71041 / 1.0174 / 1.0234 | 0.70638 / 1.0125 / 1.0185 |

实际判定使用完整复平面欧氏距离，不用径向近似代替；精确的带符号边界距离记录在
`*_symbols.csv`。正值表示正确点一侧，负值表示错误点一侧。
两点的相位误差绝对值均小于 0.32°；它们主要是被径向放大，并非大角度分支跳变。

## 为什么这个 seed 触发

`HelperTMAPSKPilotlessFrontEnd.m` 的 No-H 默认选择 `MagnitudeEstimationMode='power'`，
`FadePowerTauSymbols=16`。`HelperTMComplexGainTracker.m` 每符号执行：

```matlab
a = exp(-1/16);
powerIIR = a*powerIIR + (1-a)*abs(x(k))^2;
hMagnitude = sqrt(powerIIR/refPower);
y(k) = x(k)/hMagnitude; % 本例 TrackPhase=false、Regularization=0
```

多环 APSK 即使信道恒定，数据本身也改变瞬时功率。
第一个坏点前 32 个符号的内/中/外环数量为 13/13/6，平均真实功率 0.532514；
第二个坏点前为 12/14/6，平均真实功率 0.546063。
短时功率估计约 0.486–0.488，于是 tracker 产生约 1/sqrt(0.486)=1.434 的逆增益。
这段偏多的小半径符号不是真实信道衰落，然而后级把随后的中环点也一起放大了。

使用相同已恢复载波输出，单独按上述功率公式重放，和实际 tracker 输出最大差值：
RRC 4.44e-16，none 3.14e-16。因果归属并非只看相关性或猜测。

seed 控制数据内容；这个已测 seed 暴露出局部环占用变化导致的边界穿越。
本次未继续搜索其他 seed，不能声称它在所有 seed 中唯一。

## 重跑与产物

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
debugDir = debug_apsk_seed20260927;
```

最终诊断目录：`tmp/tpe7992f16_d6bc_4ae7_b7b3_2d7be712062b`。
每种成形保存 stages、bits、bytes、symbols、neighborhood CSV 以及汇总 MAT。
下一步应针对这个幅度估计机制设计局部修复并验证，而不是更换成形滤波、调 Gardner
或增加 warmup；本轮尚未将关闭 tracker 或任何其他诊断对照设为生产默认。
