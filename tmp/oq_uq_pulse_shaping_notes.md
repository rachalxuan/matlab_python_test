# OQPSK / UQPSK 成形接入记录

2026-09-23：合路 CCSDS TM 开放 `root raised cosine`、`raised cosine`、`none`。
默认仍为 RRC。新增 RC/none 暂不开放 I/Q 分路；原分路 RRC 入口保留。

## 实际处理

- OQPSK TX 继续使用 `comm.OQPSKModulator`：Root/Normal raised cosine，或 Custom + SPS 点矩形 FIR。官方对象保留 Q 路半符号延迟和跨调用状态。其输出已是 SPS 倍采样，不重复矩形保持。
- OQPSK RX 保留 `localOQPSKSoftLLR`，仅选择接收滤波系数。定时选择、错位抽样、bit 顺序、LLR 极性及限幅未替换为官方硬解调器。
- UQPSK 保留既有 I/Q 映射、分组、载波环和软解映射；公共收发滤波层选择 RRC/RC/矩形匹配滤波，RX 恢复到现有 2 sps 定时入口。
- `HelperTMPulseShapeConfig` 集中定义系数、滤波器类型和暂态长度。none 不使用 rolloff/span。
- 主体与保护延续使用同一个 generator。保护数据不加入 TX 测量参考。`Fs = SymbolRate * SPS` 不变。
- 星座显示和 OQPSK 质量指标使用对应接收滤波，不再固定使用 RRC。

RC 定义为 TX RC + RX RC 匹配滤波，级联并非 Nyquist RRC/RRC。rolloff=0.35、span=10、SPS=8 下，级联脉冲在相邻符号采样点的归一化旁瓣 RMS 为：RRC 0.00885731、RC 0.173199、none 0。该量不是 BER；No-H 零误码不代表 RC 没有残余 ISI，也不证明有噪声或多径下性能相同。

## 已完成验证

条件：No-H、noiseMode=off、10 Msym/s、SPS=8、rolloff=0.35、span=10、TF=254 Byte、预热8帧、测量120帧、固定随机种子917。

| 调制 | 编码 | 成形 | BER / FER | 测量覆盖 |
|---|---|---|---|---|
| OQPSK | none | RRC / RC / none | 各为 0 / 0 | 各为 120/120 |
| UQPSK | none | RRC / RC / none | 各为 0 / 0 | 各为 120/120 |
| OQPSK | convolutional 1/2 | RRC / RC / none | 各为 0 / 0 | 各为 120/120 |
| UQPSK | convolutional 1/2 | RRC / RC / none | 各为 0 / 0 | 各为 120/120 |

额外检查通过：OQPSK 矩形 I/Q 跳变相差 SPS/2；发射器分两次调用与一次调用波形完全一致；主体与尾部的编码 bit / 样本数符合采样率约定。

改动前保存的 OQPSK/UQPSK/QPSK RRC 发射波形与改动后逐采样完全一致；OQPSK RRC soft 输出完全一致。普通调制原有6组回归通过（每组12/12帧）；UQPSK 原有不等速分路合约检查8/8通过。前端参数测试17/17通过，生产构建通过（保留既有 lint / 浏览器数据版本警告）。

## 复测

### 尚未通过的边界用例

追加 TF=256 Byte（ASM+TF 不能整除 UQPSK 的 3-bit 映射分组）后，OQPSK三种成形、UQPSK的RRC/none均为 BER=0、FER=0、120/120；UQPSK RC 为 BER=3.31038e-5、FER=3/118、覆盖118/120。两种帧长的12组无编码用例共11组通过，全部采样率检查通过。保留相同随机种子、预热长度和同步参数，没有排除错误帧。完整结果在 `oq_uq_pulse_boundary_results/latest.csv`。

开启时间记录确认：第9、10帧 recovered-not-counted，第11/12/17帧分别有1/3/4 bit错误；全部120测量帧已恢复。粗频偏估计为0 Hz。故该用例不是尾部缺样，也没有证据支持粗频偏假锁；异常集中在接收起始阶段，具体定时/载波/帧关联责任尚未进一步隔离。不能据此把根因直接归为某一个同步环。RC*RC 的残余 ISI 是已知风险，但尚未单独证明是该故障唯一原因。

RC 入口标记为待验证，不修改原有同步环、不增加预热、不跳过错误帧。此轮是滤波功能已接入，但 RC 尚未全面验收。诊断日志：`oq_uq_rc256_diagnostic.log`、`oq_uq_rc256_coverage.log`。后续需要固定同一 RC 波形做分级诊断，而不是更换 FEC 或提高预热门限。

脚本默认同时测254/256 Byte，已知RC失败会如实触发最终断言；输出不会伪装为全部通过。

```matlab
dbclear all; clearvars; clear functions; rehash;
OQUPulseOptions = struct( ...
    'Codings',["none","convolutional"], ...
    'BERFrames',120);
run('E:/web_code/react/fft_project/react-fft/tmp/codex_oqpsk_uqpsk_pulse_regression_v1.m');
```

结果保存在工作区 `OQUPulseResults`、`OQUPulseMetrics`、`OQUPulseLogs`，以及脚本目录的 `oq_uq_pulse_results`。失败会保留日志并使断言失败，不会删除错误帧或降低覆盖要求。

`pulse_psd_comparison.png` 是同输入数据、同采样率、归一化为相同平均功率的 TX PSD 对比；统计排除保护延续与滤波边缘。该图的 dB/Hz 不代表绝对 dBm/Hz。
