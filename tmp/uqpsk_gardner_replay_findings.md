# UQPSK RC：同输入 Gardner 重放结果

> 后续非零 delay 回归更新：本报告的零延迟结论仍成立，但不能推广成默认修复。RC/seed917/delay=1 出现归一化后 0/120 的新增退化，已撤回默认启用，仅保留诊断开关。完整 58/59 结果见 `uqpsk_timing_normalization_acceptance.md`。

日期：2026-09-25；MATLAB R2022a。本轮只增加诊断入口和脚本，没有修改正式接收链的默认参数、滤波器、统计门限。

## 结论

已定位到匹配滤波输出与 Gardner 定时同步器之间的幅度/检测器增益适配。原路径直接把未归一化的 `filtered` 送入固定 `DetectorGain=2.7` 的 Gardner，随后才归一化 `TimeSynced`。后置归一化不能消除已经发生的错误定时插值。

固定同一份 RC `filtered`，只在 Gardner 前统一缩放复信号，测量区错误全部消失；保持输入不变、改用数学等效检测器增益也得到同样结果。没有改载波环、解调、ASM 或 BER acquisition。因而不需要先扫带宽或改统计门限，也没有证据要求重写 RC 滤波器。

不能简化为“只有 RC 的幅度太低”：RRC 输入功率也接近，而且原路径已经通过。脉冲形状会影响 TED 特性与容差；本次证明的是原标定对这组 RC 波形不适配，不是证明 2.7 对所有脉冲都正确。

## 条件和可重复性

RC 原始捕获：`C:/Users/admin/AppData/Local/Temp/UQRC_Debug_20260924_213530.mat`。

UQPSK、无编码、单路、NRZ-L、256 Byte、ASM 32 bit、No-H、无噪声、seed=917、10 Msym/s、SPS=8、rolloff=0.35、span=10，8 帧预热、120 帧测量。RC 不重跑 TX/信道；RRC 对照单独生成一次，并断言两者发送比特完全一致。

每个原始重放都断言：定时输出、载波输出逐样本完全一致；BER、计数帧数和逐帧统计门限表完全一致。这确保诊断重放没有偷偷绕过旧失败。

## 实测结果

| 输入与处理 | 测量区定时后符号错误 | BER | FER | 已比较帧 |
| --- | ---: | ---: | ---: | ---: |
| RC，原始 Gardner | 38 | 3.310381e-5 | 0.0254237 | 118/120 |
| RC，Gardner 前单位功率 | 0 | 0 | 0 | 120/120 |
| RC，等效 DetectorGain | 0 | 0 | 0 | 120/120 |
| RC，固定抽样相位 1（仅诊断） | 0 | 0 | 0 | 120/120 |
| RRC，原始 Gardner | 0 | 0 | 0 | 120/120 |
| RRC，Gardner 前单位功率 | 0 | 0 | 0 | 120/120 |
| RRC，等效 DetectorGain | 0 | 0 | 0 | 120/120 |

RC 原测量区实际恢复了 120 帧、共 41 bit 错误；现有统计门限只纳入 118 帧、8 bit 错误。新增诊断同时记录这两种口径，没有把未计数帧当作零错误。归一化后的 120 帧既全部计数，也全部无错。原定时后第 10/12/17 帧窗口分别 32/2/4 符号错误；归一化后均为 0。符号窗口有约一个符号的帧边界量化差，不等价于最终比特计数。

固定相位 2 是有意保留的负对照，RC/RRC 均严重出错，不能把任意隔点抽样当成正式接收方案。其离线真值对齐相关度不足，定时错误指标记 NaN，而非伪造 0；下游实际 BER/覆盖照常记录。真值仅用于离线测量，不用于 Gardner、增益补偿或固定相位生成。原有下游假设选择/参考帧关联不在本轮重构范围。

## 增益等效证据

RC 输入平均功率 `P=0.120257656`，RMS `0.346781856`。

- 单位功率输入：`filtered/sqrt(P)`，仍用 `DetectorGain=2.7`。
- 等效对照：输入不动，`DetectorGain=2.7*P=0.32469567`。
- 两者后归一化定时输出最大差 `1.25e-14`，插值量最大差 `8.22e-15`。

本机官方 `comm.SymbolSynchronizer` 源码：Gardner TED 使用样本乘积，输入幅度乘 a，TED 输出乘 a²；环路 K1/K2 均除以 DetectorGain。上述等效补偿由公式计算，不是调参扫描。第二输出是分数插值量 pMu，不是原始 TED 误差。

## 最小修复方向与边界

后续正式修复应在 UQPSK Gardner 前增加统一复信号功率标定，保持 I/Q 比例，保留原后置归一化；不能分别归一化 I/Q。诊断中的整段均方功率适用于当前离线接收机，不应直接冒充流式 AGC。正式接入前补其他 seed、RRC/RC/none、非零定时偏移回归，再决定默认启用；本轮没有测试 none，也没有证明所有信道均通过。

## 复现

```matlab
dbclear all; clearvars; clear functions; rehash;
UQReplayOptions = struct('CaptureFile', ...
    'C:/Users/admin/AppData/Local/Temp/UQRC_Debug_20260924_213530.mat');
run('E:/web_code/react/fft_project/react-fft/tmp/codex_uqpsk_gardner_replay_v1.m');
disp(UQReplay.Results);
```

全部实测通过执行，进程退出码 0。输出目录：`tmp/tp1d88bc05_8868_4afd_b17f_ce5f890643d6`，含 `summary.csv`、`console.txt`、逐组独立 checkpoint。脚本新增保护断言后仅做静态检查；算法与上述完成运行相同。
