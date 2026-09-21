# 仿真页面与 MATLAB 参数核对

## 调用入口

“信号调制”页面调用 `/simulate`，Python 工作线程调用 `run_ccsds_tm_evaluation`；并不是直接运行 IDE 中打开的 `ChannelModel _merge/main.m`。后者用于生成信道数据。MAT 文件通过选择/上传后作为评估接收链的输入。

当前监控仍是整段接收处理阶段推送，以及选定结果后的时间记录；不是持续分块接收。

## 本轮修正

- **APSK**：页面原来已经指定 `WaveformMode=ordinaryTM`，但同时强制 `HasTMAPSKPilots=true`，与接收端默认的 `APSKReceiverMode=pilotless` 冲突。现在页面明确提交 ordinaryTM / pilotless / 无自定义导频；删除旧 FACM、ACMFormat、pilot-ls 参数。没有修改 APSK 相位跟踪算法。
- **RS＋卷积高码率**：校验对象必须是“ASM＋RS 编码后数据”，不是未使用的 TF 属性默认值 223 字节。RS(255,223)、I=5 对应 10232 bit，不能整除 5/6 的打孔输入周期 5。页面切换级联码时默认内码 1/2；手动选择不兼容配置会在提交前提示，不擅自更换用户选择的码率。后端校验也使用真实的内码输入长度。完整 RS 帧不能通过任意改成 1116 字节来修复。
- **Turbo/LDPC 切换**：Turbo 默认 K=3568，并提供 1784/3568/7136/8920 选择；LDPC 默认 K=1024。不会把 LDPC 的 1024 残留给 Turbo。
- **噪声**：增加 SNR / 固定 PSD / 关闭噪声选择。新页面默认 `noiseMode=snr`，因此 SNR 输入实际生效；旧页面没有提交模式，会落到 MATLAB 默认 PSD。新旧结果比较时必须核对噪声模式，不能只比较 SNR 文本框数值。PSD 模式只启用 PSD 输入，结果区显示实际噪声模式。
- **均衡**：旧勾选框提交 `equalizerMode=mmse`，实际上是已知 H 参考均衡。页面现在明确提供自适应 1 sps、2 sps CMA、2 sps 同抽头双模（实验）结构，默认 2 sps；启用时提交 `blind-cma-lms`，不提交 oracle 或 FACM 均衡。通用入口目前限 BPSK/QPSK/8PSK/16QAM/32QAM；其他专用前端不能把此勾选框当成已接入均衡，提交时会明确拒绝。
- **测量**：显式提供预热 8 帧、测量 100 帧，提交 `excludeBERWarmUpFrames=true`，TPC 不再偷偷改成 2+6 帧。实际覆盖不足会在结果页、监控页单独标出。
- **滤波跨度**：普通 TM 的 RRC 发射/接收参数不再强制覆盖为 10，使用页面输入，默认仍为 10。MSK 不使用 RRC，页面不再为它显示无效的滚降/跨度输入。
- **MAT 信道增益**：提供“归一化 H 平均功率”选择，默认关闭以保留之前的原始增益行为；与 normalized-H sweep 比较时需主动打开。不再在信道目录找不到所选条目时静默退回无 H。
- **其他边界**：QAM/APSK 显示已接入的 NRZ-M/S 选项；TPC/级联码尚未接入 I/Q 分路，会拒绝而不是静默改成合路。当前页面的接收采样率要求偶数 SPS。不声称所有调制×编码×信道组合已验证。
- **错误展示**：参数校验、仿真失败、上传、保存、历史加载等错误使用居中弹窗；无自动关闭、无右上角关闭按钮、Esc/点击遮罩无效，只能点击“确认”。非错误的运行/成功消息保持原样。
- **结果与监控衔接**：完成结果保留其任务 ID，“打开接收监控”会直接加载该次任务。结果页按实际噪声模式标出 SNR 是否生效；非 APSK 不再显示 APSK 接收模式。覆盖不足时不再显示“接收端已稳定”，而是明确说明 BER 仅代表已比较帧。

## MSK 星座图为什么是十字

项目 MSK 发射器使用 `comm.MSKModulator`、`InitialPhaseOffset=0`。页面绘制 `ctx.fineSynced`，MSK 路径中它来自固定码元定时抽样，而软解调保留另一份过采样 CPM 波形。四个坐标轴上的点是这种观察方式的正常可能结果，并不是前端误接成了 QPSK。

MathWorks 的 [MSK Signal Recovery](https://www.mathworks.com/help/comm/ug/msk-signal-recovery.html) 也在其载波同步示例中使用 0° 相位偏置的 QPSK 星座来处理 MSK。这里说的是相位状态/观察坐标，不表示 MSK 是无记忆的 QPSK。设备显示对角四点可能采用不同相位参考或 I/Q 观察位置，仅凭截图无法确定其内部算法。

页面现在解释取样位置，保留真实点云，不旋转或重画成理想模板。

## 短回归记录

测试条件：50 Msym/s、8 sps、无 H、无噪声、CFO/初相位/时延为 0、合路、关闭加扰与 AGC、预热 8 帧、测量 12 帧。固定随机种子 8401。以下是接口回归，不是 BER < 10^-6 的统计证明。

16APSK＋卷积 5/6、32APSK＋卷积 5/6、32QAM＋RS(255,223) I=5＋卷积 1/2、QPSK＋Turbo 1/2 K=3568、QPSK＋LDPC 1/2 K=1024、QPSK 无编码 RRC 跨度=12，以及 QPSK＋RS I=1＋卷积 7/8：均成功返回，12/12 帧覆盖，BER=0。

MSK＋卷积 5/6：成功返回，已比较部分 BER=0，但仅覆盖 11/12 帧。该尾部覆盖缺口尚未在本轮修复，不能算完整测量通过。该缺口与“十字星座”不是同一问题。

此外，用页面真实提交了 32APSK＋卷积 5/6，无 H、无噪声、8+12 帧；实际返回 `APSKReceiverMode=pilotless`、`NoiseMode=off`、12/12 帧、BER=0。模拟级联 5/6 配置错误，验证中央弹窗在 Esc、点击背景及等待后仍保留，点击确认才关闭。

最终页面又提交了 QPSK＋卷积 5/6、无 H、无噪声、8+12 帧；任务 `b69e12d40f804dffb21ee29bd1865f42` 返回 12/12 帧、BER=0，并从结果页任务链接进入对应接收监控。监控显示 110496 个实际比较 bit、累计错误 0，同时对载波/码元锁定与“帧同步未观测”分别显示，未把缺失证据伪装成锁定。

用 HTTP 接口测试 QPSK、弱三抽头合成 H、无噪声、8+12 帧，并分别选择 1 sps / 2 sps / 2 sps-dual；三组均确认实际启用所选结构，12/12 帧覆盖、BER=0。实际启用信息见 `artifacts/ccsds/frontend-contract/equalizer-http.json`。这只检验参数接入和弱多径基线，不代表 CDL A1–A4 性能验证。

## 复测

第一步启动 Python/MATLAB 服务，刷新前端。选择调制/编码后再配置对应码率与信息块长。先选无 H、关闭噪声，预热 8 帧、测量 12 帧。运行后核对结果中的实际模式与监控页面的已比较/应测帧数。

第二步切到级联码，确认默认卷积 1/2；再手动选择 5/6，确认出现中文居中配置错误。不要为了让错误消失而随意改 RS 帧长。

MATLAB 命令：

```matlab
addpath('E:/web_code/react/fft_project/react-fft/src/python/regression');
test_web_parameter_contract
```

参数与监控前端测试：`npm test -- --watchAll=false --runInBand --testPathPattern=parameterContract` 和 `--testPathPattern=ReceiverMonitor/model`。前者 6 项、后者 4 项通过。生产构建成功，保留已有未使用变量/BOM 等警告。

HTTP 均衡入口复测（会新建 3 个真实仿真任务，需要已启动本地服务）：`python -X utf8 src/python/regression/test_web_equalizer_routing.py`。

本轮改动包含 MATLAB 类文件。若长期运行的 MATLAB Engine 缓存旧类，请在无任务运行时重启 Python/MATLAB 服务；单独清除普通函数未必会清除类缓存。不要关闭其他正在运行的 MATLAB 仿真。
