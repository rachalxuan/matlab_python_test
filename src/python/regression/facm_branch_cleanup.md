# 独立 FACM 帧格式分支清理

## 范围

普通 TM APSK 仍然使用现有 pilotless 接收器、RRC/none 成形以及原来的星座映射和软解调。本次不是调制体制迁移，不改变环半径、标签、归一化、LLR 极性、噪声方差或同步/FEC 算法。

`run_ccsds_tm_evaluation.m` 删除独立 FACM 调度、`isFACMEvaluation`、`runFACMOneShot` 及其专用接收/物理帧同步/译码/均衡/BER 局部函数，共 20 个专用函数；同时去除专用残余频偏结果分支。保留共用的 `localFlagValue`。这些被删局部函数没有普通 TM 调用者。

保留明确拒绝 FACM、额外导频及旧 APSK 接收模式的入口校验。非法请求不会被静默转换成普通 TM。

保留 `satcom.internal.ccsds.facmModulate`、`HelperCCSDSFACMDemodulate` 和 `HelperCCSDSFACMReferenceConstellation`。这些名字中的 FACM 不意味着发送 FACM 帧。本次没有修改它们，也没有修改 `ccsdsTMWaveformGenerator`、`HelperCCSDSTMDemodulator`、pilotless 前端、幅度跟踪器或尾部延续。

没有批量删除仓库内旧 FACM helper 文件或底层生成器的 FACM/SMTF 共用能力，也没有清理普通 TM 历史导频诊断分支。当前应用入口只能使用普通 TM；本次目标是移除主评估脚本内独立 FACM 帧格式路径，而不是消灭所有包含 FACM 的名字。

## 验证方法

脚本：`test_facm_branch_cleanup.m`。先在生产代码修改前运行 capture，再修改并运行 check。使用的是已完成 APSK 幅度修复后的当前基线，不能拿早期幅度修复前的最终接收输出代替。

- 16APSK/32APSK × RRC/none × 无编码/RS223 I=1/LDPC 1/2 K=1024，共 12 组。每组 8 帧预热、120 帧测量，seed=20260927，No-H、无噪声、零频偏/相偏/定时偏移。
- BPSK、QPSK、8PSK、16QAM、32QAM、OQPSK、UQPSK 的 RRC 无编码对照，共 7 组。每组 8 帧预热、16 帧测量，seed=917。
- 对比完整 TX 波形、参考星座、原始接收符号、粗同步、定时同步、最终同步输出、选定相位、实际配置、BER/FER、覆盖、尾部延续和残余载波指标，使用 `isequaln` 精确比较。
- APSK 对全部星座标签及实际接收序列产生的软值做逐项精确比较；比较软值时两边固定使用相同的 0.07 噪声方差。这是数学接口等价检查，不是替换正式接收器的可靠度估计。
- 7 个共用生产文件与清理前源码逐字比较，防止清理过程中改变收发算法。
- 12 个 FACM/导频/旧接收模式请求必须报错。前端参数契约另行测试。

失败结果先保存再断言；TX 真值只用于原有离线评估，没有添加真值反馈或按测试结果选择接收参数。

## 文件与复测

清理前基线：`tmp/tp36898d07_8ccc_4d1f_9cc1_09c0551bf209`。其中 `manifest.mat` 保存清理前完整主脚本及共用源文件文本，可用于审计或选择性恢复本次删除；不要用它覆盖后续用户修改。

清理后结果：`tmp/tpddaabe90_1cb7_40a5_b86a_94dcbb956be2`。

实际结果：19/19 组通过，所列数组及结果与清理前精确一致。12 组 APSK 均 BER=0、FER=0、120/120；7 组普通调制均 BER=0、FER=0、16/16。12 个非法 MATLAB 请求全部拒绝；前端 `parameterContract.test.js` 29/29 通过。`git diff --check` 通过（仅行尾格式提示）。

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));
outDir = test_facm_branch_cleanup('check', ...
    fullfile(root,'tmp','tp36898d07_8ccc_4d1f_9cc1_09c0551bf209'));
disp(outDir);
```

这是帧格式代码清理的等价回归，不是新增全信道性能验收，也不代表 No-H 结果可以外推到所有信道损伤。
