# 接收时间记录与后续页面监控

## 当前实现的范围

`run_ccsds_tm_evaluation` 仍然是整段波形评估器。本次新增的是处理结束后的统一仿真时间记录，返回在 `result.ReceiverTimeline`，`Mode` 明确为 `offline-simulation-timeline`。没有把接收机改成连续分块解调，也没有把结果回放伪装成实时接收。

记录只使用最终选中的相位候选的统计结果，不把未选中的候选误码累加进去。TX 真值只用于离线比较，不参与同步、均衡或译码反馈。2026-09-15 的修正将常规 TM 译码分支的参考配对改为物理帧位置关联，修复坏 VCFC 导致预热帧越界计数的问题；没有修改均衡、载波恢复、帧同步判决或 FEC 更新公式。

## 使用步骤

第一步，保留现有调制、编码、信道、噪声和接收机设置，只在传入评估器的 `p` 中开启记录。已有 `enableRuntimeLockTelemetry=true` 时，记录默认随之开启；显式设置 `enableReceiverTimeline=false` 可以单独关闭记录。

```matlab
p.enableReceiverTimeline = true;
[result,~] = run_ccsds_tm_evaluation(p);
L = result.ReceiverTimeline;
assert(L.Available, '%s', L.Reason);
T = struct2table(L.Rows);
disp(L.Summary);
```

第二步，查看逐帧增量与累计量。只有 `ComparedBitsDelta>0` 且 `ErrorBitsDelta=0` 才表示这一行确实比较了数据且没有新增误码。没有可比较数据时，`FrameBER=NaN`，JSON 中对应 `null`，不能当作 BER=0。

```matlab
disp(T(:,{'Lane','TxFrameIndex','TimeEnd_s','Coverage', ...
    'ErrorBitsDelta','ComparedBitsDelta', ...
    'CumulativeErrorBits','CumulativeComparedBits', ...
    'UnrecoveredFramesDelta','RecoveredCopies', ...
    'CarrierLastObservedState','TimingLastObservedState', ...
    'FrameLastObservedState'}));
```

第三步，筛选有误码或未恢复的测量帧，再检查对应锁定轨迹。`LockTracks` 保留原始载波、定时、帧锁定观测；不是每一帧都产生新的载波/定时状态。

```matlab
bad = T.MeasurementEligible & ...
    (T.ErrorBitsDelta>0 | T.UnrecoveredFramesDelta>0);
disp(T(bad,{'TxFrameIndex','TimeStart_s','TimeEnd_s', ...
    'Coverage','FrameBER','ErrorBitsDelta','ComparedBitsDelta', ...
    'CarrierLastObservedState','CarrierEvidenceAge_s', ...
    'FrameLastObservedState','FrameEvidenceAge_s'}));
```

使用 `codex_new_channel_psd_sync_sweep_v1.m` 时，可在 `ReceiverOverrides` 内设置 `enableReceiverTimeline=true`。每个选中信道的时间记录会保存在 `NewChannelPSDSweepTimelines{k}`，顺序与 `NewChannelPSDSweepResults` 的行相同，**k 不是目录中的 FileIndex**。例如只选择 A4 时，A4 是结果第 1 行，对应 `{1}`。再次运行 sweep 会更新这些工作区变量，不自动写入磁盘。

```matlab
L = NewChannelPSDSweepTimelines{1};
assert(L.Available, '%s', L.Reason);
T = struct2table(L.Rows);
disp(L.Summary);
```

## 统计口径与限制

- `ErrorBitsDelta / ComparedBitsDelta` 与原评估器所选候选的译码后传输帧比较口径一致，包括传输帧头，不是应用净荷吞吐量。TPC 的 `hard-systematic-debug` 会明确标注为诊断数据，不是完整迭代译码 BER。
- `RecoveredCopies` 暴露重复匹配。累计比较量保留原来重复比较的行为，以便对照原 BER；它不是去重后的有效吞吐量。
- `missing-in-observed-span` 表示两个已匹配 TX 帧之间有帧未匹配，`unobserved-leading/trailing` 表示边界未观察到。边界未输出可能涉及捕获或缓冲未排空，不能直接归为信道丢帧。
- 无输出、无法匹配、重复匹配和中间缺帧分别保留。每支路的 `Observations.Association` 说明关联方法；常规 TM 译码器现在附带输入比特位置，统计器在连续可信参考帧处建立锚点，随后仅按物理位置推进，坏 VCFC 不再重选 TX 参考。旧记录或未提供帧位置的专用路径仍可能使用旧匹配器，必须检查 `Available` 与 `Reason`，不能把缺口全部认定为信道丢帧。
- `DecodedVCFC / ExpectedVCFC / VCFCValid` 将头部连续性与帧位置分开；`VCFCValid=0` 不会自动排除测量区坏帧。预热仍是 TX 序列的前 N 帧，不是每次重新捕获后额外跳过 N 个输出。缺少可信参考锚点时不推测对应关系，也不报告零误码。
- `Rows` 按 TX 帧网格排序；`Observations` 保留 RX 输出顺序。当匹配异常时，前者不是严格的接收交付顺序。时间轴使用原测试帧的 `MeasurementDuration_s`，不把尾部保护数据摊进每帧时长。这仍是近似网格，未校准各级滤波/译码延迟，不用于精确判断几个符号内的故障先后。
- 锁定值为 `1/0/NaN`：锁定、未锁定、不可用。`LastObservedState` 是最近一次观测，需一起看 `EvidenceAge_s`；不是无限期有效的“实时绿灯”。帧窗内的锁定观测比例、质量均值和状态转换次数也保存在对应字段中。
- `TimingLastObservedState=NaN` 可能是该接收路径未暴露独立定时遥测，不能替换为失锁。锁定本身也不能保证 payload 正确。
- 不支持的观测分支、无效尺寸或计数不一致会返回 `Available=false` 和原因，不能伪造零误码。记录失败不应让已完成的译码被标成运行失败。

## 与页面、真正流式接收的边界

现有后端结果 JSON 会携带 `ReceiverTimeline`。页面之后可以在任务完成时读取它并展示锁定历史、错误增量、累计比较量和未恢复帧。这是**结果监控**。任务运行中显示“排队／运行中／完成”则是**任务进度**，两者都不等于流式解调。

真正的流式接收是输入依次到达，例如先处理第一段，再处理下一段；载波环相位、均衡器抽头、定时环、ASM 缓冲和 FEC 缓冲要延续，不能每段重新初始化。块边界也不一定就是帧边界。需要接收机在确认输出帧或确认缺帧后发布事件，页面按墙钟时间限速刷新；界面刷新不控制同步算法更新周期。I/Q 同一时刻的数据应聚合后发布，不能把另一支路尚未处理当作丢帧。

后续若要求真实“边接收边刷新”，应单独实现并验证有状态分块路径，明确首部捕获、尾部缓冲排空、帧消歧候选提交和缺帧等待规则；与整段运行做分块长度不变性回归。当前含全段归一化、全段相位候选选择等处理，不能只给主函数套分块循环就宣称等价。

## 快速回归

```matlab
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
report = test_receiver_timeline(true);
```

该命令检查缺帧、重复、无输出、I/Q、JSON 空值和计数一致性，并短测 QPSK 无编码、QPSK+RS、QPSK 分路在无 H/无噪声条件下开启和关闭记录的一致性。不执行长信道 sweep。

物理参考配对的专项回归：

```matlab
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
report = test_tm_frame_association(true);
```

其中 false 只运行快速注错及译码器位置测试；true 再运行上述 QPSK 对照和 8PSK 七种代表编码的短无信道测试。专项注错覆盖预热 VCFC 污染、测量区头部错误、中间缺输出、较晚初次捕获、256 帧回绕与比特边界改变后的重新锚定。真实 RS 译码器测试还验证拒绝帧后的物理空缺及两次输入的缓冲连续性。

该修正改变的是参考比较与统计，不会消除真实信道误码。历史结果若出现重复匹配、坏 VCFC 提前越过预热边界，需重新计算，不能把新旧 BER 差异当成同步或译码算法收益。实际长信道验收仍应保留原配置重新运行。

原 TPC+A4 配置重跑后（无需修改均衡或译码参数），在工作区查看最终选中候选的预热情况：

```matlab
L = result.ReceiverTimeline;
assert(L.Available, '%s', L.Reason);
O = L.Observations{1};
A = O.Association;
disp(table(O.RxFrameIndex,O.TxFrameIndex,A.DecodedVCFC,A.ExpectedVCFC, ...
    A.VCFCValid,O.ErrorBits,O.Counted, ...
    'VariableNames',{'RxFrame','TxFrame','VCFC','ExpectedVCFC', ...
    'VCFCValid','ErrorBits','Counted'}));
assert(~any(O.Counted & O.TxFrameIndex < O.FirstMeasurementFrame));
disp(L.Summary);
```

这里的 `ErrorBits` 包括未计数的预热比较，`Counted` 明确标注是否进入最终 BER 分子和分母。坏帧号只应使 `VCFCValid=0`，不应再令 TX 参考帧跳走。该命令依赖原 sweep 留在工作区的最后一次 `result`，多信道时也可改用对应的 `NewChannelPSDSweepTimelines{k}`。

## 有限波形收尾与完整测量覆盖

2026-09-15 的 8PSK/TPC 1/2×8、30+120 帧记录中，编码器生成 4,920,000 bit，但返回的波形只承载 4,916,448 bit；3,552 bit 尚在发送端调制分块缓冲中。接收端 ASM 从软比特 127 开始，对齐后仅有 149 个完整的 32,800-bit 编码帧，最后余 29,122 bit。这不是“测量区坏帧被 BER 筛掉”的证据，也不能只在 RX 补零软比特冒充未发送数据。

`HelperTMCompleteBurst` 在原 TX 生成调用后，用同一个有状态生成器追加至少两组明确不参与测量的保护数据，释放编码/调制分块余量，并让测量帧经过成形滤波、接收滤波、均衡与译码缓冲。保护组由末尾信息组按位取反构造，再经过正常编码调制，不消耗 RNG，也不直接复制最后一个参考帧冒充它的恢复结果；保护组不作为合法业务帧评估。原发射波形前缀不变，TX 参考帧和编码比特参考仍仅包含原测试帧。这里完成的是原测量区，不要求最后一个保护组也被完整译码；保护组不属于额外的 BER 样本，更不是导频或训练序列。

自动收尾接入常规 TM 的 BPSK/QPSK/8PSK/QAM/无导频 APSK（包括 QPSK 合路/等速 I/Q 分路）。GMSK/MSK/OQPSK/UQPSK、FM/PCM、4D-TCM、FACM、带物理层 APSK 导频和 LDPC SMTF 的专用波形结构暂不改动；`BurstCompletion.Applied/Reason` 明确说明。极长时延或捕获失败仍可能覆盖不足，不能因为追加了保护组就宣称全部恢复。

`MeasurementDuration_s` 为原测试数据时长，`ActualWaveformDuration_s` 包含保护段。锁定遥测按前者截取，避免用保护段中的重锁改善原测试终点。时间轴还未校准接收滤波延迟。接收机仍含全段归一化/频偏估计，追加输入可能轻微改变全段统计；保证的是 TX 原始前缀不变，不是宣称所有 RX 采样及 BER 必然与旧短截波形逐点相同。

`result.MeasurementCoverage` 不依赖开启完整时间记录，始终给出原请求帧中唯一的恢复数、比较数、未恢复数、恢复但未比较数和重复比较数。`COMPLETE` 要求原测量帧全部且各比较一次；无输出帧保持 BER 未知。`MeasurementCoverageStatus` 独立于译码/同步故障原因保留在 sweep 表中。BER/FER 为零但覆盖不足时，不再给出 `SHORT_PASS`，而是 `MEASUREMENT_INCOMPLETE`；专用分支若无所需观测则标 `MEASUREMENT_COVERAGE_UNAVAILABLE`。已有同步/译码失败仍保留对应 Verdict，旁边同时显示覆盖状态。

短回归（不运行长 A4 sweep）：

```matlab
dbclear all; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_tm_burst_completion(true);
```

`false` 只验证 TX 缓冲余量、原波形/RNG 不变、保护段不替代测量帧和锁定时间窗；`true` 再验证物理帧配对、QPSK 合路/分路、8PSK 七种代表编码、8PSK/TPC 双模 FSE，以及 BPSK/QAM/无导频 APSK 无编码的短无 H 链路，要求完整的指定比较帧数。这些不是原 A4 120 帧验收，不能据此宣称该信道零误码。原配置重跑后检查：

```matlab
disp(result.BurstCompletion);
disp(result.MeasurementCoverage);
L = result.ReceiverTimeline;
T = struct2table(L.Rows);
disp(T(end-2:end,{'TxFrameIndex','Coverage','ComparedBitsDelta','ErrorBitsDelta','FrameBER'}));
% 这是验收检查，遇到真正缺帧应报错，不会修改统计结果。
assert(result.MeasurementCoverage.Complete);
assert(result.MeasurementCoverage.ExpectedFrames == 120);
assert(result.CountedFrames == 120);
```
