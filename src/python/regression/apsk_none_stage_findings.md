# APSK none 逐级诊断（2026-09-27）

后续实施说明：APSK none 主链现已保留全采样率匹配输出进入现有 Gardner；
验收见 `apsk_pulse_shaping_notes.md`。本文件下方保留修复前诊断证据。
诊断脚本现按 capture 中的实际定时 SPS 重放，兼容旧 2 sps 和新全采样率记录；
奇偶固定网格仍为离线对照，TX 真值不参与正式接收。定时相位轨迹 RMS 不等于锁定误差。

新增 `debug_apsk_none_stages.m`，未修改接收算法、带宽、计数或 FEC。
`captureBaselineData` 打开时额外保存实际匹配滤波输出、定时配置、定时轨迹及
pilotless 输出；默认关闭，不经页面 JSON 传输。

## 运行

```matlab
dbclear all; clearvars; clear functions; rehash;
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
debugDir = debug_apsk_none_stages;
```

默认 No-H、无噪声、无编码、TF=256 Byte、SPS=8、10 Msym/s、seed=917，
16/32APSK 各跑 delay=0/1，warmup=8，测量 120 帧，rolloff 参数固定为 0.35。
none 不用 rolloff 构造滤波器，但当前主链仍用它计算定时 DetectorGain；本轮未改。
脚本输出实际生效的 DetectorGain/BW，避免默认值差异。

如已保存上轮完整 capture，可跳过 TX/信道，直接重放：

```matlab
debugDir = debug_apsk_none_stages( ...
    'E:/web_code/react/fft_project/react-fft/tmp/tpa37b7ba8_7bed_4da2_9a05_0a13d16cd251');
```

自动保存 console.txt、每例 capture.mat（新运行时）、debug.mat、stages.csv、frames.csv。
新运行会断言离线重放的 Gardner/pilotless 输出与实际抓取的对应输出逐元素一致。
旧 capture 无中间数组时，仍断言 Gardner 重放与已保存输出一致。

## 口径

TX 真值仅用于离线检查，不传入同步器。每级用测量区开头最多 4096 符号拟合一次
固定延迟和固定复增益，此后不逐帧重新校正。pilotless 保持符号顺序，沿用 Gardner
的延迟，不能在相位旋转后重新搜索一个虚假的符号偏移。

符号错误包括 ASM，排除 warmup 和 guard；它不是实际接收机的 payload BER。
高采样率的固定网格搜索是 oracle 对照，不能作为正式接收能力。
`ConstantGainReliable=false` 表示固定校准不足以描述该信号，此时使用功率尺度防止
近零相关增益导致 EVM 人为爆大；不应据此断言发生了符号滑移。
三抽头系数只是残余 ISI 的描述性拟合，没有用来修正 SER。

## 实测证据

新运行目录：`tmp/tp93ae025d_1943_4b0a_95b1_c4345bff84b7`。
对旧数据的独立重放目录：`tmp/tp98106501_6bdf_4030_80b4_405c41e1158c`。

两种调制在 delay=1 时，高采样率矩形匹配滤波输出的第 1 个采样相位可以精确
恢复符号，EVM 在浮点误差量级。因此本例信号并没有不可恢复的损伤。
delay=0 的正确相位为第 8 个；现有固定降采样保留每个符号第 4、8 个采样点。
delay=1 时该固定网格不再直接保留理想积分终点；后续 Gardner 未完全消除残余 ISI。

16APSK、delay=1：

- Gardner 输出固定校准后 EVM=8.4228%，0 个符号错误（62400 个比较符号）。
- pilotless 内部载波处理后、最后一个 gain tracker 之前，已出现 14 个错误符号。
- 最后 gain tracker 后仍为 14；ASM/最终输出仅相差固定比例和旋转，没有新增错误。
- 错误帧为 12、20、30、33，各为 4、4、3、3，和实际 payload 误 bit 逐帧对应。
- 粗频偏为 -1.55622 Hz（真实 0），不像 32APSK 的大频偏误捕获。
- 因而不能把这 14 个错误归咎于 FEC、尾部、最终 gain tracker 或 ASM。
  pilotless 内部具体哪个步骤跨过判决边界仍需进一步拆分；不直接断言是 PLL。

32APSK、delay=1：

- Gardner 输出固定校准后 EVM=8.5048%，0 个符号错误（49920 个比较符号）。
- pilotless 的 48 次幂粗频偏估计为约 -60248.5 Hz，而真实 CFO=0。
- pilotless 后出现持续旋转/严重失真，实际帧覆盖为 0/120，BER/FER 为 NaN。
- delay=0 对照的粗频偏为 -0.07948 Hz，BER=0，覆盖 120/120。

结论：不是“none 本身不能通信”。本例先出现固定抽取/定时插值后的残余失真，
然后 pilotless 处理引入实际判决错误；32APSK 已明确暴露粗频偏误捕获。
不能仅凭这些结果把 Gardner 判为唯一责任方，也不能直接把 CFO 写死为零当修复。
下一步应固定 Gardner 输出，检查 pilotless 的粗频偏候选和内部相位处理，
并对矩形波形的抽取/插值单独诊断；不要先改 ASM/FEC 或加大 warmup。
