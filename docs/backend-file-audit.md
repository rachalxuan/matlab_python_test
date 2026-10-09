# MATLAB / Python 后端文件整理清单

检查日期：2026-10-08。范围：当前工作区的 `src/python`，以 `server.py → run_ccsds_tm_evaluation.m` 为网页仿真入口。

结论：核心算法集中在这个目录，但目录同时保存正式代码、回归测试、旧版独立实现、信道生成工程和历史输出。“网页运行不需要”不等于“开发研究没有价值”。本次仅检查、建立清单，没有删除、移动或改写任何已有算法文件。

## 1. 体积与目录概况

大小以十进制 MB 计，不包含项目外的信道目录，也不包含 MATLAB / Python 安装环境。

| 位置 | 文件数 | 大小 | 当前定位 |
|---|---:|---:|---|
| 整个 `src/python` | 1223 | 2454.34 MB | 混合工程目录 |
| `ChannelModel _merge/` | 793 | 2397.75 MB | 独立信道生成工程及外部数据 |
| 根目录文件 | 140 | 37.67 MB | 正式算法、LDPC 数据、旧脚本及数据库混合 |
| `debug/` | 105 | 8.65 MB | 调试脚本及绘图/统计输出 |
| `report_figures/` | 66 | 7.31 MB | 图片、PDF、SVG、CSV 报告材料 |
| `UQPSK_modem/` | 5 | 1.93 MB | 独立 UQPSK 示例和波形数据 |
| `regression/` | 54 | 0.40 MB | 回归框架、专项测试、开发记录 |
| `+satcom/` | 34 | 0.36 MB | 包代码、MAT 数据、Windows MEX |
| `apsk_pilotless_stage2_asm/` | 8 | 0.15 MB | 正式依赖与独立测试混合 |
| `apsk_pilotless_stage1/` | 2 | 0.04 MB | 早期 APSK 实现与测试 |
| `FM_SOQPSK/` | 11 | 0.04 MB | FM 参考代码及正式运行需要的训练数据 |

体积约 97.7% 来自 `ChannelModel _merge/`。单独分离该目录，剩余 `src/python` 约 56.6 MB；这不是完整部署包大小，更不是已经验证的最小运行集。

## 2. 正式运行必须保留的部分

### 服务与 MATLAB 主链

- `server.py`、`receiver_monitor.py`。
- `run_ccsds_tm_evaluation.m`：服务工作线程实际调用的入口，见 `server.py:161`。
- `ccsdsTMWaveformGenerator.m`、`HelperCCSDSTMDecoder.m`、`HelperCCSDSTMDemodulator.m`、`HelperCCSDSTMSplitReceiver.m` 等发射、解调、译码实现。
- 主链使用的 `HelperTM*`、GMSK、FM、TPC、数据通路与帧处理函数。不能用文件名中的 `Helper`、`debug`、`extension` 等词统一判断有无用途。
- `+satcom/` 的代码、`.mat`、`.mexw64` 先整体保留。包内调用、工具箱调用及 MEX 依赖不能仅凭文本搜索裁剪。
- `tm_ldpc_H_*.mat` 先保留。这些是译码器会按参数寻找的矩阵数据/缓存，并非统一意义上的临时结果；见 `HelperCCSDSTMDecoder.m:1966` 附近。部分矩阵可以重建，但删除会改变初始化成本，需要分别验证。

### 容易误删的具体例子

| 文件/目录 | 保留证据 |
|---|---|
| `TPC_encoder.m` | `ccsdsTPCEncodeBits.m:54` 直接调用 |
| `TPC_decoder.m` | `ccsdsTPCDecodeSoft.m:50` 用 `which` 定位，`:80` 调用 |
| `err_p64.txt` | `TPC_decoder.m:5` 用 `dlmread` 加载的译码数据表，必须保留；不是错误日志 |
| `HelperCCSDSFACMReferenceConstellation.m` | 主入口 `run_ccsds_tm_evaluation.m:8743`、`:8745` 仍用于 APSK 参考星座 |
| `HelperCCSDSFACMDemodulate.m` | `HelperCCSDSTMDemodulator.m:373` 仍调用 |
| `FM_SOQPSK/FM_SOQPSK/data_training.mat` | `ccsdsFMBuildInfo.m:58` 和 `ccsdsFMDemodulateWaveform.m:236` 按相对路径加载 |
| `apsk_pilotless_stage2_asm/` | `HelperTMAPSKPilotlessFrontEnd.m:40` 指向该目录，`:261` 调用载波恢复 |

FACM 入口停用不代表所有带 FACM 名称的数学辅助函数都已停用。FM 示例目录也不能整目录直接删除。

`sim_history.db` 是用户保存的仿真历史，不是运行缓存。可选择不带到新机箱，但清理时不应默认删除。

## 3. 确认是测试/调试/扫参：运行包可排除，开发仓库应保留

根目录中以下文件是较明确的整理对象：

```text
test_4d_tcm_regression.m
test_ccsds_tm_internal_data_source.m
test_tm_ldpc_decode_noiseless.m
test_tpc_common_path.m
test_tpc_decoded_frame_aligner.m

sweep_h_channel_short_frames.m
sweep_modcod_esno_thresholds_external.m
sweep_qpsk_8psk_rs_allH.m
sweep_tm_carrier_capture_range.m
sweep_tm_normalized_h_system.m

run_tm_apsk_pilot_damage_sweep.m
run_tm_data_path_sweep.m
run_tm_dualiq_triage.m
debug_h_matrix_equalizer_stats_8psk.m
TPC_SIM.m
untitled.m
untitled2.m
extract_report_figures_from_log.py
```

其中 `untitled.m` 是独立调制/绘图实验，`untitled2.m` 用写在脚本中的 BER 数组画曲线；都不是当前 HTTP 仿真服务的入口。`TPC_SIM.m` 是仿真示例，但它旁边的 `TPC_encoder.m`、`TPC_decoder.m` 是运行依赖。

目录级建议：

- `regression/`：保留为测试资产，从后端运行包排除。这里有正式冒烟回归、数据通路契约和新算法修复测试，不能整体称为“没用的中间脚本”。
- `debug/`：其中 `.m` 是调试与探索工具，其他图表/CSV 是研究输出，可分别归档。
- `apsk_pilotless_stage2_asm/` 内的 `test_apsk_pilotless_receiver_v3.m`、`test_apsk_pilotless_receiver_v4.m`、`sweep_apsk_pilotless_wide_capture.m` 属于测试工具；其余文件先保留。不要因为目录名带 `stage2` 而把整个目录归档。

移动测试时需要同时修改路径。部分测试用 `fileparts(mfilename('fullpath'))` 推导工程位置，另一些引用 `tmp/baselines` 或特定实验结果目录；直接剪切后可能失效。最小风险的第一步是从部署清单排除，源文件位置暂时保持。

## 4. 旧入口/独立实现候选：归档前需确认外部使用情况

下列项没有在当前 HTTP 主入口的保守文本依赖遍历中发现调用路径。该结论针对当前服务，不排除 MATLAB 命令行、外部工程、Live Script 或动态调用。

| 候选 | 已发现的用途 | 建议 |
|---|---|---|
| `python_bridge.py` | 旧式桥接，调用旧 FACM 调制入口 | 归入旧接口档案候选 |
| `python_ccsds_bridge.py` | 接受命令行 JSON、启动引擎、写结果文件的独立桥接 | 当前 `server.py` 不导入它；归档候选 |
| `FFT_function.m` | 旧 FFT 图像功能 | 当前服务没有相应调用，归档候选 |
| `run_ccsds_tm_modulation.m` | 旧调制入口 | 与当前 `run_ccsds_tm_evaluation.m` 区分 |
| `run_ccsds_FACM_modulation.m` | 旧 FACM 入口 | 连同确认为其独占的 helper 整组归档 |
| `run_ccsds_fm_extension_evaluation.m` | 独立 FM 评估实现 | 不等于当前 `ccsdsFM*` 主链，归档候选 |
| `run_ccsds_qam_extension_evaluation.m` | 独立 QAM 评估实现 | 归档候选 |
| `run_ccsds_tpc_extension_evaluation.m` | 独立 TPC 评估实现 | 归档候选 |
| `run_ccsds_uqpsk_extension_evaluation.m` | 独立 UQPSK 评估实现 | 归档候选 |
| `run_qam_extension_evaluation.m` | 另一版独立 QAM 评估 | 归档候选 |
| `apsk_pilotless_stage1/` | 第一阶段载波恢复与独立测试 | 保留历史，移出生产 MATLAB 路径 |
| `UQPSK_modem/` | 原始独立例程与波形 | 与根目录重复/分叉，归档候选 |
| 根目录 `UQPSKMod.m`、`UQPSKDem.m`、`InterpLag.m` | `ModSig.mat` 文件式调制/解调例程 | 当前主链未发现调用，整组归档候选 |

其他尚未从当前主入口追到的根目录 helper：

```text
HelperBitErrorRate.m
HelperCCSDSFACMFDRecover.m
HelperCCSDSFACMFLL.m
HelperCCSDSFACMFMFrequencyEstimate.m
HelperCCSDSFACMFrameMarker.m
HelperCCSDSFACMFrameSync.m
HelperCCSDSFACMPhaseRecovery.m
HelperCCSDSFACMRxInputGenerate.m
HelperCCSDSFACMSNREstimate.m
HelperCCSDSFACMTFSynchronize.m
HelperCCSDSTMSynchronizer.m
HelperDigitalAutomaticGainControl.m
HelperDopplerShift.m
HelperSCCCDecode.m
make_tm_ldpc_H.m
```

其中多项仍被旧 FACM 入口相互调用，应整组维护。这里列的是“待复核归档候选”，不是已证明可永久删除的清单。

## 5. 信道生成模块应独立管理

`ChannelModel _merge/`、`generate_channel_model_mat.m`、`generate_channel_model_mats_7_9.m`、`generate_named_channel_model_mats_7_9_with_large_scale.m`、`convert_antenna_gain_csv.m` 属于信道生成/准备工具。

当前网页服务选择或上传已生成的 MAT 文件，再由 MATLAB 评估函数加载；它没有调用该生成工程的 `main.m`。如果目标机箱只消费现成信道文件，可以把生成工程作为独立工具包留在开发机，只交付所需信道 MAT 数据。

如果目标机箱还要重新生成场景/信道，则继续保留生成代码和外部数据。另需注意：根目录 `generate_channel_model_mat.m:24` 默认指向项目外的 `E:\matlab_project\v3.0\v3.0\ChannelModel\ChannelModel`，不自动使用此处的 `ChannelModel _merge/`。两套工程是否等价需要单独核对。

## 6. 可从运行包排除的输出、缓存和重复压缩包

- `__pycache__/`、`.pyc`：自动生成的 Python 缓存，可重新生成。
- `report_figures/`、`sweep_results/`：报告/实验输出，可独立归档，保留需要用于论文或回归对照的原始材料。
- 根目录 `16QAM_tmgen_raw_constellation.png`。
- 根目录 `ccsds_regression_suite_results.mat`、`results_4d_tcm_regression_20260528_193235.mat`、`results_known_h_equalizer_20260601_173228.mat`、`tm_turbo_regression_20260527_162038.mat`、`tpc_32qam_interleaver_sweep_20260628_204806.csv`：历史实验结果，不是译码矩阵。
- `FM_SOQPSK.zip`、`UQPSK_modem.zip`：源码存档，当前服务不解压读取。可移出运行包；未进行压缩包逐文件等价核验，不据此删除唯一历史副本。
- `.claude/`：本地开发工具配置，服务运行不需要。

`ModSig.mat`、`ModSig_300MBd_20IQRatio.mat` 是旧 UQPSK 例程的波形数据，适合和对应例程一起归档，不能把所有 `.mat` 一律当缓存删除。

**运行验证更正（2026-10-08）：初版曾误把 `err_p64.txt` 列为可排除输出。TPC 实际运行发现它是 `TPC_decoder.m:5` 的必需输入表，必须保留。整理后的备份已缺少该文件，新部署副本从原项目恢复，并单独复测 TPC。**

## 7. 同名文件比文件数量更值得优先处理

| 同名文件 | 内容比较 | 风险 |
|---|---|---|
| 根目录 / `regression/HelperTMAGC.m` | 不同；测试目录版本采用分块滤波等另一实现 | 测试或生产可能因路径顺序调用不同 AGC |
| `apsk_pilotless_stage1/` / `apsk_pilotless_stage2_asm/HelperTMAPSKCarrierRecovery.m` | 不同 | 老载波恢复可能遮蔽当前实现 |
| 根目录 / `UQPSK_modem/UQPSKDem.m` | 不同 | 修改一个副本，另一个仍保留旧行为 |
| 根目录 / `UQPSK_modem/UQPSKMod.m` | SHA-256 相同 | 重复副本 |
| 根目录 / `UQPSK_modem/InterpLag.m` | SHA-256 相同 | 重复副本 |

当前 APSK 前端先用 `exist('HelperTMAPSKCarrierRecovery','file')` 检查，找不到才添加 stage2 目录。如果错误版本已在路径上，这个检查无法保证选中 stage2。不要用 `addpath(genpath('src/python'))` 一次性把历史、测试目录全部放进服务路径。

整理验证时，在独立 MATLAB 会话检查：

```matlab
which HelperTMAGC -all
which HelperTMAPSKCarrierRecovery -all
which TPC_encoder -all
which TPC_decoder -all
which ccsdsTMWaveformGenerator -all
```

## 8. 推荐实施顺序与本次验证边界

1. 保持已有算法与路径，先把正式运行清单和开发资料清单分开。
2. 将实验结果、压缩存档、调试与测试从交付运行包排除；开发源保留。
3. 根据目标机是否生成信道，决定是否附带独立信道生成包。
4. 针对旧入口及同名实现建立归档目录，同时更新测试路径；不按 `run_*`、`Helper*` 或 `.mat` 通配删除。
5. 在副本里验证依赖解析、关键调制/编码组合、三张结果图、监控和信道加载，再确定精简包。

本次使用目录统计、文件 SHA-256 对比、服务入口核对、显式加载路径检查，以及保守的文本引用遍历。静态遍历从网页 MATLAB 入口覆盖 85 个 `.m` 文件，另有 47 个根目录 `.m` 未被该遍历覆盖；这 47 个包含测试、工具和旧入口，不能全部归类为无用代码。MATLAB 的动态调用、类分派、工具箱、MEX 和数据文件依赖仍需运行验证。

未运行全模式数值回归，未证明 85 个文件就是最小可部署集合。机器可读的辅助引用记录见 [backend-static-references.json](../artifacts/deployment/backend-static-references.json)。
