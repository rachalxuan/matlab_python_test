# 16APSK 10 dB 固定波形相位诊断（2026-10-08）

## 范围与复现

只检查 `APSK_NoiseModeCompare_20261008_104234_192.mat` 的 case 2（RRC）和 case 7（none）。配置为 No-H、零频偏/初相/定时偏移、卷积 3/4、seed 917、30 Msym/s、8 sps，PSD 对应采样点 SNR 10 dB。没有扫描其他配置，也没有改变接收算法参数。

历史文件没有保存大波形。诊断按原 seed 重现一次，首先断言 BER、FER、覆盖与历史结果完全相同；随后固定此次捕获的同一份定时输出重放 pilotless，不再经过 TX/信道。捕获开关前后的 pilotless 输出逐样本完全相同。

```matlab
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
rrcReport = diagnose_apsk_noise_boundary([],2);
noneReport = diagnose_apsk_noise_boundary([],7);
D = load(rrcReport);
disp(D.PilotlessStageSummary);
disp(D.CarrierDiagnostics);
disp(D.BPSFirstEvent);
disp(D.BPSBadObservations);
```

最终紧凑报告（无波形、无 LLR、无 TX 业务数据）：

- RRC：`tmp/APSK_NoiseBoundary_20261008_151222_194.mat`
- none：`tmp/APSK_NoiseBoundary_20261008_151233_686.mat`

## 逐级归因

归一化输入 → NDA 捕获 → Mth → 前级增益 → 环归一化 → BPS → DD → 后级增益。

两例 Mth、前级增益、环归一化、DD 实际均未启用；BPS 启用。捕获阶段存在小残余相位斜率，但没有持续 90° 分支切换。持续分支错误首先出现在 BPS，后面的输出继承该错误。最终 ASM 候选输出与 pilotless 输出只有一个固定复数系数的差异，相对残差分别为 3.74e-16 和 1.74e-16。

正式结果保持不变：RRC 为 64/120、BER 0.0545815；none 为 98/120、BER 0.292477。利用已知零物理相位的离线对照，保留实际定时与幅度，只撤销相位校正，两例均为 120/120、BER=FER=0。此对照不是正式接收算法，也不代表所有 SNR 均可恢复。

## 首次持续分支偏离的事件

先在 TX symbol 512–1023 建立固定相位分支参考；用连续两个 128-symbol 窗口确认持续偏离，再回溯到 BPS 中心的 45° 边界越界。时间按已验证的固定符号偏移转换到 TX 时间；不是任意重新对齐坏段，也不是逐窗口旋转后统计 BER。

RRC：RX symbol 2529，约 0.083900 ms，TX 第 4 帧。紧邻的事件为：

1. symbol 2513：输入局部相位约 1.79°，BPS 测量约 31.43°，被接受（confidence 0.02235，门限 0.02）。频率状态升至约 110.5 kHz。
2. symbol 2517：再次接受约 31.38°；频率状态仍约 107.6 kHz。
3. symbol 2521/2525：不可靠测量被拒绝，但仍按旧频率预测，相位推进到 36.67°/41.84°。
4. symbol 2529：测量已恢复到 1.22°，预测却达到 47.00°，最近分支选择把测量提升为 91.22°。
5. 随后轨迹收敛到约 90°，形成持续错误分支。

none：RX symbol 1365，约 0.045433 ms，TX 第 2 帧。symbol 1341/1345/1349 接受约 29–30° 的错误测量；频率状态达到数万 Hz，随后维持约 76.7 kHz。symbol 1357/1361 的正常测量因大 innovation 暂未接受，预测继续前进。symbol 1365 把 -1.27° 测量提升为 88.73°；symbol 1373 的重捕获动作把轨迹拉到约 92.81°。

两次首次持续偏离都在 warmup 内，但后续还有反复分支切换；不能靠延长 warmup 解决。

## 为何会出现约 30° 错误观测

BPS 当前用 33-symbol 最近星座距离窗口、4-symbol hop。16APSK 外环 12 点对 30° 旋转存在环内对称，区分错误旋转依赖内环及完整窗口证据。在这些带噪短窗口里，错误 30° 候选的实际距离代价确实更低，并通过了现有 confidence 判据，不是仅仅日志角度显示错了。

逐窗口重算全部 61 个候选，最小代价与正式 BPS 一致（误差断言 <1e-12）。例如 RRC symbol 2513 的 33 点窗口有 7 个内环、26 个外环符号，错误候选代价 0.013508，接近真实相位的网格候选代价 0.013817。none symbol 1341 有 4 个内环、29 个外环，分别为 0.017907 和 0.018710。TX 标签只用于离线解释环占比，不进入 BPS。

因此已观察到的薄弱点是：短窗口错误相位最小值被接受 → 快速相位更新污染频率状态 → 拒绝测量期间继续沿污染的频率预测 → 按预测最近分支提升正常测量 → 固定在错误的 90° 分支。

粗频偏估计分别约 -21.10 Hz、-10.12 Hz，非巨大的假峰。日志中的 NDA residual 约 +918/-1676 Hz 在这两例没有被应用，不应误认为实际补偿量。小粗频偏残差仍会产生长期相位斜率，但不能解释首次事件中突然出现的约 30° 错误观测与十万 Hz 级预测状态。

## 诊断阶段结论（修复前）

尚未实施算法修复。优先在同一波形上设计 BPS 相位观测与频率更新的解耦/可靠性处理，并检查拒绝观测期间的预测与分支重捕获；不要只为当前 seed 调高一个 confidence 门限。修复后先验证这两例及已有正常点，再独立回归真实正负频偏。当前证据不推广为 5 dB 或所有 APSK 的性能结论。

本轮只扩展现有诊断函数，并在 carrier helper 添加默认关闭的 `CapturePhaseStages` 只读捕获。没有改 FEC、成形、定时、相位更新公式或默认接收配置。

## 后续修复：trusted-slope（2026-10-08）

已在共同 BPS helper 中添加 `trusted-slope` 轨迹更新。APSK 默认配置通过 `BlindPhaseSearchTrajectoryMode` 选择它，其他共同 BPS 调用者仍保留原默认行为。没有修改 FEC、成形、定时、BPS 星座候选或距离代价。

主要变化：

- 快速相位更新不再直接成为频率观测。频率使用已接受相位观测的时间斜率；观测至少间隔一个完整 BPS 窗口，最多保留 9 个，积累至少 4 个后对两两斜率取中位数，再使用原频率平滑系数更新。历史有限，不保存整段数据。
- 普通更新复用已有重捕获一致性容差（默认 12°），不再让 35° 内的所有瞬时创新直接更新相位。更大创新进入原重捕获确认路径。
- 重捕获除了满足次数，还要求证据跨越完整窗口的时间跨度；默认三次要求首尾至少相隔两个窗口。相位重锚时清空斜率历史，不跨相位跳变拟合频率。
- 拒绝观测期间沿已确认频率预测，不把可疑相位校正写入频率。
- 新增 `ObservationAccepted` 和 `FrequencyUpdated` 诊断字段；原 `Reliable` 仍只表示局部度量门限通过，不能视作最终更新已被接受。

验收脚本 `test_apsk_bps_trajectory.m` 对旧版/新版使用相同 seed，并断言 TX、信道输出、定时输出、BPS 相位观测、候选最佳代价及局部可靠性标记完全相同。只有轨迹更新不同。正式 BER/FER 和 coverage 来自主接收器，未用离线真值补计。

结果：

- 原 10 dB RRC 反例：64/120、BER≈0.05458 → 120/120、BER=FER=0；最大 BPS 频率状态约 238.7 kHz → 612.85 Hz。
- 原 10 dB none 反例：98/120、BER≈0.29248 → 120/120、BER=FER=0；最大频率状态约 228.9 kHz → 449.26 Hz。
- 16APSK 正常 PSD 工作点的 RRC/none 及两种成形的 ±150 kHz 真实频偏：均 120/120、BER=FER=0。
- 32APSK 正常 PSD 工作点 RRC/none：均 120/120、BER=FER=0。
- 历史无噪声 H 抽查：16APSK 旧/新均 32/32、BER=FER=0；32APSK 旧/新均 31/32、已比较部分 BER=FER=0，并保留 1 个 recovered-not-compared 帧。后者只证明本例无新增退化，`AcceptancePassed=false`，不是完整验收。
- 核心四例另外运行“不指定 trajectory 模式”的默认调用，结果和显式 `trusted-slope` 的 pilotless 输出逐样本一致。
- 独立 seed 20260927、同一 10 dB 配置：旧 RRC BER≈0.27696（120/120），旧 none BER≈0.20241（114/120）；新 RRC/none 均 120/120、BER=FER=0、无 recovered-not-compared，最大 BPS 频率状态分别约 589.87/435.11 Hz。该 seed 仅存在于回归配置，不进入接收算法。

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_apsk_bps_trajectory('core');   % 失败点、正常点、默认接入
test_apsk_bps_trajectory('cfo');    % 正负真实频偏
test_apsk_bps_trajectory('apsk32'); % 32APSK 正常点
test_apsk_bps_trajectory('seed');   % 相同 10 dB 条件、另一个 seed
test_apsk_bps_trajectory('h');      % 历史 H 非退化，不掩盖覆盖缺口
```

每个 scope 只覆盖写入一个小型 `tmp/APSK_BPS_Trajectory_<scope>.mat`，不保存波形。旧 `diagnose_apsk_noise_boundary` 现已显式选择 legacy，用于重现历史问题；验收新路径应使用上述测试，不能把旧诊断命令的失败误认为新默认仍失败。

仍未完成完整的噪声/动态信道性能边界验证。特别是 5 dB、长时间衰落和快速真实相位变化不能由这些测试保证。`LargeSingleHopSteps=0` 也不证明没有周跳，因为分支可以通过多个小步滑移；它仅是辅助诊断，正式验收依赖主接收器完整比较及 BER/FER。

## 32APSK 粗频偏捕获修复（2026-10-09）

这次与上述 BPS 问题分开处理。历史 32APSK 全环归一化 x^48 在 10 dB 下选择了远离真实 CFO 的峰；单段 FFT 的最高峰/背景比不能证明存在稳定载波谱线。不是修改 FEC、增大 warmup 或使用真实零频偏绕过捕获。

最小接入点为 `HelperTMAPSKFourthPowerCoarseCFO.m`、`HelperTMAPSKCarrierRecovery.m` 和 `apskPilotlessDefaultConfig.m`：

- 32APSK 默认复用已有内/中环选择及 x^12 观测；不压缩时间轴，被排除环的位置置零。16APSK 保持原路径。
- 第一段默认 4096 symbols 用 Hann FFT 生成最多 4 个候选，并排除同一个主瓣的重复候选；下一段最多 4096 symbols 只验证这些固定候选的相干能量，不重新搜索频率。
- 验证段也使用 Hann 窗，避免矩形窗泄漏给邻峰制造确认。通过能量检查后，还要求胜出候选相对次强候选明确占优，复用既有 6 dB 对比度门限。不能要求所有次峰都低于噪声门限，因为时变 H 下真实谱线会有可测侧带。
- 能量门限 `-log(1e-3/4)` 来源于独立圆对称噪声下的名义多候选误警预算；滤波、环选择和多径下不能解释成经过标定的实际误警概率。
- 证据不足明确拒绝捕获，不把候选当成已应用补偿量，不根据 BER/TX 真值选择频偏。后续 NDA、BPS、定时、成形和 FEC 算法不变。
- 修正禁用 FFT 时范围容差可能为 NaN 的问题，并补全捕获拒绝原因打印。

默认捕获观察量从最多 4096 增为最多 8192 symbols；短输入会平分可用样本。当前是整段接收，未来如改流式，需要等待这段真实接收数据，不能当作无额外捕获延迟。已有 `EnableWideRangeRingCoarseCFO=false` 仍可显式重现旧路径；未增加前端配置项。

验收使用保存的用户输入配置重新生成同 seed 波形。旧/新接收均成功返回捕获数据时，断言 TX 波形、前端粗同步波形和定时输出逐样本相同；16APSK 还要求最终载波同步输出逐样本相同。旧路径捕获失败而不返回数据的 case 不声称通过逐样本对照。

实测结果：

- seed 917、32APSK、RRC、10 dB：旧估计 +41988 Hz、BER=0.333204、105/120；新估计 +94.6 Hz、BER=FER=0、120/120。
- 同配置 none、10 dB：旧估计约 -197935 Hz、0/120；新估计 -11.3 Hz、BER=FER=0、120/120。
- 32APSK RRC/none 的 15、20 dB：新旧均 120/120、BER=FER=0。
- 16/32APSK × RRC/none 的真实正负 150 kHz（20 dB），及独立 seed 20260927（10 dB、零配置 CFO），12 个新路径组合全部 120/120、BER=FER=0，无 recovered-not-compared。
- 5 dB 两种成形均未通过独立验证，明确返回捕获失败及 NaN BER，仍然未解决；不能据此断言已达到物理性能极限。
- 历史无噪声 H：16APSK 旧/新均 32/32、零误码；32APSK 旧/新均 31/32、已比较部分零误码，保留原有 1 个 recovered-not-compared。仅证明这两例无新增退化，不算 32APSK 完整 H 验收。
- 单元检查通过：正负/零 CFO、前后段不一致的谱线拒绝、无信号拒绝、双强谱线歧义拒绝、禁用 FFT 后范围容差有限。

本轮只新增一个复用测试函数，四份报告按固定文件名覆盖写入，不保存大波形：

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_apsk_coarse_acquisition('unit');
test_apsk_coarse_acquisition('fixed');      % 原 32APSK 失败点和正常点；5 dB 仅诊断
test_apsk_coarse_acquisition('regression'); % 16/32APSK、正负 CFO、独立 seed
test_apsk_coarse_acquisition('h');          % 历史 H 非退化，不掩盖覆盖缺口
```

报告为 `tmp/APSK_Coarse_Acquisition_<scope>.mat`。测试依赖本机保存的 `TM_System_awgn_20261008_202837_091.mat` 输入配置；H scope 另外依赖历史 `tp55c9efcc_a166_4a1c_bcb9_f355bdd95780` 两份 H 基线。报告里的失败 case 的 `EstimatedCFO_Hz` 是被拒绝的候选，不是已应用的频偏补偿。
