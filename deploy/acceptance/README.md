# CCSDS 机箱部署与短测试

此包从 `E:\matlab_project\ccsds_backup` 的整理版复制生成。保留的 MATLAB 算法逐字节不变；Python 服务仅调整部署路径。旧入口、长扫参、历史数据和重复实现未装入运行包，原备份没有删除或改写。

## 目录

```text
ccsds-machine/
  server.py / receiver_monitor.py     HTTP 服务
  run_ccsds_tm_evaluation.m           MATLAB 主入口
  其他 .m / +satcom/                 算法、矩阵与 MEX
  apsk_pilotless_stage2_asm/          当前 APSK 依赖
  FM_SOQPSK/                         FM 参考资料与必需训练数据
  tm_ldpc_H_*.mat                    译码矩阵
  err_p64.txt                        TPC 译码必需数据表（不是错误日志）
  channel/                          8 个内置信道 MAT 文件
  tests/run_deployment_tests.m       新的独立机箱短测试
  deploy/                           环境检查、启动及 HTTP 测试
  docs/cleanup-inventory.json        源文件保留/排除清单
  file-manifest.json                交付文件 SHA-256
  data/                             启动后生成：数据库、上传、仿真结果
  artifacts/acceptance/              MATLAB 测试后生成：报告与日志
```

此包故意保持主算法在根目录，不改 MATLAB 的相对加载关系。不要把整个目录递归加入 MATLAB path。没有复制原 `sim_history.db`，首次启动创建空历史；若需要迁移历史，先停止原服务，再将一致的数据库副本放到 `data/sim_history.db`。

实际检查发现整理版遗漏了 `err_p64.txt`，TPC 译码器会通过 `dlmread` 读取它。本包从原项目恢复了该表，具体来源和哈希记录在清单中。初版静态清理建议曾将它误判为日志，现已更正。

## 1. MATLAB 环境与路径

原机为 Windows 64 位、MATLAB R2022a 9.12.0.1884302、Python 3.8.8，Engine 为 R2022a。初次算法验收优先用相同 MATLAB 版本和工具箱。源代码依赖 Communications、DSP System、Satellite Communications、Signal Processing 等工具箱；包里的 `+satcom` 不能替代工具箱安装。包含 `.mexw64`，不能原样迁移到 Linux。

在全新的 MATLAB 会话进入此包根目录：

```matlab
cd('D:/CCSDS/ccsds-machine');  % 改成机箱上的实际位置
addpath(fullfile(pwd,'tests'));
run_deployment_tests('Profile','quick','DryRun',true);
report = run_deployment_tests('Profile','quick');
```

测试不依赖原 React 工程、旧 regression 目录或旧 `tmp` 数据。测试会临时恢复默认路径，只加入当前包和 stage2，核验实际选中的算法路径，结束时恢复路径、工作目录和随机数状态。仍应在新 MATLAB 会话运行，避免之前已经加载的旧类缓存。

## 2. 三级验收

### 快速接收测试：4 例

`quick` 覆盖 QPSK 无编码、QPSK 卷积 5/6、QPSK LDPC 1/2、16APSK 卷积 5/6。固定种子、无 H、关闭噪声和其他损伤，8 帧预热 + 12 帧正式测量。

通过条件：算法返回成功、实际无噪声无 H、BER=0、比较比特数大于零、测量覆盖完整。没有比较数据或只测到部分帧都不能算通过。

### 扩展代表性测试：12 例

```matlab
report = run_deployment_tests('Profile','extended');
% 或只复测某项
report = run_deployment_tests('Profile','extended','CaseIds',{'qpsk_tpc'});
```

包含 quick 四例，以及 QPSK Turbo、QPSK TPC、8PSK RS、16QAM 无编码、32QAM 级联、32APSK 卷积、OQPSK 和 UQPSK。实际耗时取决于机箱和编码方式，不承诺固定秒数。

这是分支完整性和基本正确性检查，不覆盖所有调制×编码×信道组合；不覆盖完整 FM/GMSK/MSK/4D-TCM/PCM-PSK-PM 性能，也不是低 BER 指标认证。后续可按机箱真正使用的模式补例。

### MAT 信道加载检查

```matlab
report = run_deployment_tests('Profile','channel', ...
    'ChannelFile',fullfile(pwd,'channel','ChannelData.mat'), ...
    'ChannelSampleRateHz',100000);
```

这里的默认信道采样率来自现有页面设置，使用其他 MAT 文件时应填写其真实采样率。此例显式归一化 H、关闭噪声，用于确认数据格式/加载路径与 H 模式接入，成功状态为 `LOAD_OK`，只证明信道文件已加载并完成运算；BER 和覆盖单独报告，不把未知信道性能判成合格。

每次输出到新的 `artifacts/acceptance/<profile>_<时间>/`，包含 `summary.json`、`summary.mat`、每例 `matlab.log` / `result.mat`，失败时还有 `failure.txt`。默认失败后保留完整报告并抛错，方便自动验收读取退出状态；可用 `FailOnFailure=false` 交互检查全部结果。

## 3. Python 服务环境检查与启动

MATLAB Engine 必须从目标机对应 MATLAB 版本安装，不能复制原机的 Python site-packages。当前 `.m + matlab.engine` 方案需要完整 MATLAB；仅 Runtime 不够。

在包根目录的 PowerShell 中，使用已安装匹配 Engine 的 Python：

```powershell
python -m pip install -r deploy/requirements.txt
python -X utf8 deploy/run_backend.py --check --development
python -X utf8 deploy/run_backend.py --development --host 127.0.0.1
```

`--check` 只核验依赖导入与关键文件，不启动 MATLAB，不证明工具箱授权可用。`--development` 用于本机联调。需要其他电脑临时联调时显式设置 `--host 0.0.0.0`，并按局域网范围配置防火墙。

长期运行使用单进程 Waitress：

```powershell
python -m pip install -r deploy/requirements-production.txt
python -X utf8 deploy/run_backend.py --check
python -X utf8 deploy/run_backend.py --host 0.0.0.0 --port 5000
```

Waitress 3.0.2 需要 Python >=3.9；R2022a 的兼容范围包括 Python 3.9。原机 Python 3.8.8 只用于此包的开发模式验证，不能声称已验证生产模式。若更换 MATLAB，重新核对 Python 兼容表并运行上述测试。Engine 安装应遵循该 MATLAB 版本自带说明，勿直接安装不匹配的最新版 Engine。

包内默认路径：信道在 `channel/`；上传、结果、历史在 `data/`。可以在启动前用 `CCSDS_CHANNEL_DIR` 和 `CCSDS_DATA_DIR` 环境变量改变位置。当前只有一个进程内队列和一个 MATLAB Engine，不要开多进程 worker。任务状态在重启后丢失，历史记录需要显式保存。

服务没有附带旧 React build，访问 `/` 会提示前端未构建，验收应请求 `/health`。现有 CORS 开放且没有身份验证，连接范围按已有受控局域网安排；对方 HTTPS 页面宜通过同源代理接入，避免浏览器拦截 HTTP 混合内容。

## 4. Python → HTTP → MATLAB 完整链路

服务启动后，在另一个终端运行：

```powershell
python -X utf8 deploy/smoke_client.py --base-url http://127.0.0.1:5000
python -X utf8 deploy/smoke_client.py --base-url http://127.0.0.1:5000 --run-simulation --output artifacts/http-check-01
```

第二条会真正提交一个短任务，轮询状态、下载指标、验证三张 PNG、读取监控并保存证据。输出目录必须是新目录。HTTP/PNG 检查通过不替代 MATLAB 严格接收测试；需查看 BER 与 MeasurementCoverage。客户端超时会请求取消自己提交的任务，取消是异步的，不代表 MATLAB 立即停止。

接口保持现有名称：`POST /simulate` → `taskId` → `GET /task_status/{taskId}`；监控用 `GET /task_monitor/{taskId}`；信道列表/上传用 `/channel_models`、`/upload_channel`。新前端应使用服务端返回的信道路径；当前还没有新增信道 ID 到路径的适配接口。

## 5. 还应不应该继续删

本包已按明确清单排除旧入口、长扫参、独立 UQPSK 例程、stage1、原来的散落测试和历史数据。`docs/cleanup-inventory.json` 给出逐文件记录。尚未充分证明可删除的旧 helper 体积很小，暂时保留，避免用静态搜索替代动态依赖验证。

先在这个副本上通过 quick、实际使用模式的 extended 子集、信道加载和 HTTP 链路，再把副本复制到机箱。原 `ccsds_backup` 可作为回退版本；不要继续对它批量删除。

参考：[MathWorks Python 兼容表](https://www.mathworks.com/support/requirements/python-compatibility.html)、[MATLAB Engine 要求](https://www.mathworks.com/help/matlab/matlab-engine-for-python.html)、[Waitress 官方文档](https://docs.pylonsproject.org/projects/waitress/en/stable/)。
