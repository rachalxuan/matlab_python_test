# UQPSK Gardner 前置归一化：验收未通过

2026-09-25，MATLAB R2022a。候选归一化已接入真实接收分支并执行回归；发现新增退化后撤回默认启用。正式默认仍与修改前相同。只保留 `debugUQPSKTimingInputNormalization=true` 的诊断路径，以便复现；前端不增加配置。

## 条件

固定 No-H、无噪声、UQPSK 单路、无编码、NRZ-L、ASM、256 Byte、10 Msym/s、SPS=8、rolloff=.35、span=10、预热8帧、测量120帧。未改载波环、Gardner 带宽/DetectorGain、BER 门限、参考帧关联及尾部补齐。

- 成形：RRC、RC、none。
- 种子：917、42、2026。
- 输入采样延迟：0、1、1.25、2.5、5.75、7.75 samples（80 MHz），共54组。
- 补充 RC 254 Byte 三个种子；QPSK/OQPSK RRC 各一组，共5组。
- 每组检查 BER/FER=0、120个唯一测量帧、每帧2048 bit（254 Byte对照为2032）、没有已恢复未比较帧、无观测错误、尾部和主体采样率一致。

延迟确实经主链 `dsp.VariableFractionalDelay` 施加。核对官方对象 `info` 得到 ValidDelayRange='[1, 100]'：默认 Farrow 的非零小延迟会被夹到1。首轮误用了.25，已保留原始证据并改用明确的1，同时补1.25，不能把.25一组称为真实分数.25延迟。0走现有显式旁路。本轮未新增负延迟实现。

## 结果

| 测试组 | 通过数 |
| --- | ---: |
| UQPSK RRC，256 Byte | 18/18 |
| UQPSK RC，256 Byte | 17/18 |
| UQPSK none，256 Byte | 18/18 |
| UQPSK RC，254 Byte | 3/3 |
| QPSK/OQPSK RRC 对照 | 2/2 |
| 总计 | 58/59 |

唯一失败为 RC、seed917、delay=1：0/120，无可比较比特，BER/FER=NaN、MEASUREMENT_INCOMPLETE；不能解释为0误码。测试脚本在保留所有结果后故意断言失败，MATLAB退出码1是未通过验收，不是测试未执行完。

## 同输入因果检查

重新抓取这组失败用例的同一份2-sps filtered，分别送入原Gardner和单位功率输入Gardner，再复用原载波、soft demap、ASM、BER链。参数不变，不扫描带宽或增益。归一化重放与主链定时/载波输出逐样本一致。

| 处理 | 输入样本 | 输出符号 | 已比较帧 | BER |
| --- | ---: | ---: | ---: | ---: |
| 原始幅度 | 360360 | 180180 | 120/120 | 3.662109375e-5 |
| 前置单位功率 | 360360 | 198198 | 0/120 | NaN |

原始幅度并非完美，但有9 bit错误、完整覆盖；前置归一化反而让Gardner输出数异常增加，触发官方对象缓冲上限，警告丢弃最后56120个输入样本。异常已发生在Gardner，早于载波环/ASM；不能靠扩大输出缓冲、改统计门限或跳过这个seed解决。

这证明“单位功率+固定DetectorGain=2.7、BW=.01”并非已验证的通用标定。零延迟的成功仍有效，但不能据此宣称已找到完整通用修复。具体TED增益、捕获初始相位与环路轨迹的关系尚需进一步诊断，本轮不猜测精确原因，不盲扫参数。

## 当前代码与复现

默认归一化已撤回，诊断候选默认关闭。`run_ccsds_tm_evaluation.m` 只在显式诊断开关下做一次复信号统一缩放，不改变I/Q比例，也不引入TX真值。默认恢复和诊断开关重现均另做逐样本相等断言，通过后才交付。

```matlab
dbclear all; clearvars; clear functions; rehash;
run('E:/web_code/react/fft_project/react-fft/tmp/codex_uqpsk_timing_normalization_regression_v1.m');
% 预期58/59，并在最后报验收断言失败，不能跳过失败行。
```

仅复现失败用例的同输入A/B：

```matlab
run('E:/web_code/react/fft_project/react-fft/tmp/codex_uqpsk_delay1_timing_ab_v1.m');
```

## 原始证据

- 59组完整回归：`tmp/tpd95ea405_2fd6_45e6_af00_44ed48c7724c/results.csv`、`results.mat`、`failure_020.mat`。
- 同输入A/B：`tmp/tp395545a8_af7f_4b05_9aee_d2e7a3f84967/diagnosis.mat`、`diagnosis.csv`。
- 日志：`tmp/uq_timing_normalization_verified_delays.log`、`tmp/uq_delay1_ab.log`。
- 默认恢复核验：`tmp/uq_timing_default_restored.log`。
- 首轮含被夹取.25的50组结果保留在 `tmp/tpfad6ce0a_9cad_4377_acd2_90b34cf7d9b7`，不作为分数.25的验收证据。
