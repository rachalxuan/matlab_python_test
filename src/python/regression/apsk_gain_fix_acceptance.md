# APSK 后级幅度估计修复（2026-09-27）

## 修改范围

生产代码只修改两处，没有 seed/帧号/FEC/成形方式专用修补，也没有新增 tracker 或前端参数。

1. `HelperTMAPSKPilotlessFrontEnd.m`：普通 No-H APSK 后级默认复用已有 `decision`
   幅度估计，保持 `TrackPhase=false`。现有 H/shared-reliability 专用策略保持不变；
   显式指定旧模式仍然有效，供历史诊断和 A/B 使用。
2. `HelperTMComplexGainTracker.m`：只有 `power` 模式允许退出 fade 时按原始功率重设增益。
   `decision` 与 `ring-directed` 保留自己的估计，使用原有更新/恢复逻辑继续运行。
   这消除了另一条“正常判决更新后，被数据包络重新覆盖”的通路。

没有调整步长、判决门限、同步带宽、warmup 或 BER 统计。
没有修改 TX、滤波、Gardner、载波恢复、ASM、映射或 FEC。
保留 H 专用策略是迁移边界，不表示判决导向已经通过所有深衰落/重捕获情形。
短时功率仍用于原有 fade 辅助检测；本轮未把该检测改造成真实物理衰落的判定器。

## 固定坏帧与机制验证

`test_apsk_gain_fix` 使用已保存的同一份定时输出，不重新生成信道。
旧 power 模式重放与历史 pilotless capture 逐元素相同；新默认模式直接送原 demapper，
未给接收机传 TX 真值，未用真值修改幅度或相位。

- seed=20260927、RRC：2 bit → 0 bit；两错误点最终半径约 1.0087/1.0234 → 0.7375/0.7430。
- 同 seed、none：2 bit → 0 bit；半径约 1.0203/1.0185 → 0.7071/0.7064。
- 16/32APSK、16/32QAM：固定真实增益，只改变环/幅度占用，输出与输入差异小于 1e-12。
- 四种星座施加 ±12% 缓慢幅度变化，判错符号为 0，校正幅度偏差小于 1%；不是冻结增益规避错误。
- 外部 HOLD 后恢复：不再按原始包络重新放大，单位真实增益下输出差异小于 1e-12。

旧 H 行为在修改前现场冻结：
`tmp/tp55c9efcc_a166_4a1c_bcb9_f355bdd95780`。
修复后验证目录：`tmp/tp32b5fe18_6235_4b3f_9cfe_47e02e7f7f65`。
采用 `4-ChannelData.mat`、RRC、无编码、32 测量帧的四个代表例：
16/32APSK、16/32QAM 的完整波形及最终接收输出均与修改前逐元素相同。
其中 32APSK 原来就是覆盖 31/32，修复后仍为 31/32；其余 32/32、BER/FER=0。
这里证明没有改变该 H 路径，不将原有覆盖不足标成验收通过。

## 回归口径

APSK 的后级幅度输出本来就是修改目标，不应要求继续匹配旧错误算法。
冻结 RRC 回归保持 TX、参考星座、粗同步、定时输出逐元素比较；其他七种调制仍要求
最终接收输出也逐元素相同。APSK 则要求最终 BER/FER 和完整比较覆盖通过。
`LegacyFinalIdentical` 单独记录，未删除或覆盖旧基线文件。

完整成形/FEC 回归：68/68 全部 BER=0、FER=0、120/120，未恢复帧及已恢复未比较帧为 0。
包括 12 个 LDPC/RS 代表例、不同 seed、独立 CFO/相偏/delay、TF=254:258 全映射余数。
20 组 TX 分块/一次性/尾部延续一致性检查通过。
结果：`tmp/tpc11423d4_7d77_4c01_a6db_6a848ab57f2e`。

冻结 RRC 回归 9/9 通过：七种非 APSK 调制最终数组完全相同，APSK 上游完全相同，
后级幅度输出按预期改变且 BER/FER=0、16/16。
结果：`tmp/tp377d55bf_ba7f_4c14_91d2_ecf2b80077bb`。

原成形核心 8 个 none 用例再次通过，均 BER/FER=0、120/120、主体与尾部保持一致；
两种 APSK RRC 的上游冻结对照亦通过。
结果：`tmp/tpa06b10a7_826f_4921_b73f_73ac6e725cd3`。

上述零误码验收是 No-H、无噪声条件；H 测试只验证已有路径未改变，不是全面多径验收。

## 重跑

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_apsk_gain_fix('check', ...
    'E:/web_code/react/fft_project/react-fft/tmp/tp55c9efcc_a166_4a1c_bcb9_f355bdd95780');
test_apsk_pulse_acceptance;
test_apsk_pulse_shaping;
```

历史诊断 `debug_apsk_seed20260927` 显式选择旧 power 模式，以便继续重现和解释原始失败；
不能把该历史重放的两处错误误认为生产默认修复未生效。
