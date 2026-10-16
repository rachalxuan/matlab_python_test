# 均衡入口核对与分层系统测试（2026-10-11）

## 2026-10-14：Stage 2 普通 TM LDPC 7/8 对照

现有 runner 新增 `opt.CodingProfile="ldpc-7/8"`，默认仍为 `"conv-3/4"`。
仅改变测试配置与按编码帧长度计算的帧数，不修改同步、均衡或译码算法。
LDPC 使用现有 ordinary TM 路径：7136 信息 bit（892 Byte TF）编码为 8160 bit，
外加 32 bit ASM，共 8192 bit / 1024 Byte；`IsLDPCOnSMTF=false`。
1024 Byte 是本配置的传输同步帧长度，不能填成 `NumBytesInTransferFrame=1024`。
精确码率为 7136/8160，不能用名义 7/8 反算码字长度。

在 100 Mbps 调制器编码比特率、QPSK 50 Msym/s 下，每帧 81.92 us。
`WarmupTime_s=.010, TargetEnd_s=.082` 对应 123 预热帧、878 测量帧；
帧取整造成的时间边界差异小于一帧。输入电平保留原测试 -10 dBm，seed=917，
不是一次性复制设备所有设置。设备 PN15、-12 dBm、均衡关闭等仍有区别。

```matlab
opt.CodingProfile = "ldpc-7/8";
[T, file] = run_tm_equalizer_system_checks('files',channelDir,opt);
```

结果增加 ChannelCoding、CodeRate、InformationBitsPerTF、PredecoderBER、
PredecoderSteadyBER、PredecoderASMAligned、PredecoderBitsCompared。
LDPC 开启现有离线译码前诊断，TX 真值仅用于统计，不反馈接收算法；不可用数据为 NaN。
译码前码字比特与译码后 TF 比特不是同一统计域，不可直接相减作为纠错位数。
先 No-H 无噪声验证，再跑原独立 CDL/TDL/ITU 文件。未通过时检查捕获、实际比较量、
译码前后错误和软信息；开启 LDPC 仍失败本身不能证明同步有 bug。

已验证：原 38 组卷积输入结构逐字段不变；38 组 LDPC 配置均为 123+878 帧。
QPSK/RRC/No-H LDPC、seed=917、30+120 帧，均衡 OFF/ON 均 120/120、BER=FER=0。
另一次 30+12 帧开启译码前诊断的冒烟测试为 12/12、译码前后 BER=0，ASM 已对齐。
尚未代跑全部 38 个实际信道，不宣称其 LDPC 性能通过。

2026-10-12 更新：下述为入口核对时的历史记录。当前 BPSK 2 sps 默认复用 CMA/DD 同抽头均衡，QAM 非 BPS 载波环改用参考星座判决，APSK 在明确开启均衡且粗捕获失败时可使用捕获前盲 RDE。原命令和采样配置仍可使用；修复证据与尚未解决项见 [固定故障诊断与修复](tm_system_failure_diagnosis.md)。

本轮只整理页面到接收器的配置入口，不更改同步、均衡更新、软解调或 FEC 算法。
基线目录为 `artifacts/ccsds/eq-baseline-20261011-before-routing`，约 2.6 MB。
其中保存当前接收器源码、前端配置、已有 OQPSK 回归说明及三个原始用户测试 MAT，
`manifest.json` 记录 SHA256。原始 MAT 不是伪造的修复后结果；D1 修复后结果和
A4/B1 未通过的状态见同目录快照中的 `src/python/regression/oqpsk_equalizer.md`。
未复制大波形和信道库。核对快照后，118 个顶层 MATLAB 源文件均未变化。

## 实际接线

| 调制 | 页面默认均衡路径 | 开关生效位置 |
| --- | --- | --- |
| BPSK/QPSK/8PSK | 2 sps CMA | 匹配滤波后分数间隔均衡 |
| OQPSK | oqpsk-staggered | 保留 I/Q 半符号错位的适配路径 |
| UQPSK | 公共 1 sps CMA/LMS | 专用载波恢复后 |
| 16QAM/32QAM | 公共 1 sps CMA/LMS | 盲相位恢复后 |
| 16APSK/32APSK | 公共 1 sps CMA/LMS | 普通 TM pilotless 前端后 |

统一禁止已知 H 预均衡，关闭独立的 fractional post 均衡；不把所有调制硬塞进
同一种同步顺序。QAM/APSK 后级门控明确随页面开关传递。切换调制会同步更新
合法采样方式；不兼容的直接请求报错。关闭均衡会清理残留后级开关。
MSK/GMSK、TCM、FM/PCM 不在本次验收范围；页面仍明确拒绝未接入的均衡组合。

## 已执行验证

- 前端配置测试 51/51 通过，页面 JSX 解析通过。
- 从真实 `finalizeTMRequest` 导出 36 组请求，逐个调用真实 MATLAB 接收器：
  9 种调制 × RRC/none × EQ OFF/ON，入口核对 36/36 通过。
- 该短回归固定 seed=917、卷积 3/4、TF=258 Byte、预热 8 帧、测量 12 帧，
  使用小幅复数回波；34 组 BER=FER=0 且覆盖 12/12。
- **两个失败保留**：QPSK none EQ ON 仅 10/12，BER=0 只描述已比较部分；
  8PSK none EQ ON 为 0/12、BER=NaN，均衡输出接受标志为 false。
  这不构成性能全部验收，也没有确定失败原因，不通过延长预热或调参隐藏。
- 证据：`artifacts/ccsds/eq-routing-20261011/frontend-requests.json`、
  `contract-results.csv`，详细日志/坏帧在
  `artifacts/ccsds/system-eq/TM_EQ_contract_20261011_091706_353.mat`。
- 检查了服务端 `/simulate`：JSON 配置直接送 MATLAB，没有丢弃这些均衡字段。
  本次不是浏览器点击到 HTTP 的全链路 UI 验收。
- 测试命令短验证：3 ms 总长、1 ms 预热，QPSK RRC No-H PSD=-105 的
  实际输入 SNR=11.1979 dB，43/43、BER=FER=0；OQPSK none D1 的 EQ OFF/ON
  均为 43/43、BER=FER=0。它们只验证运行入口，不替代下述 82 ms 系统测试。

## 用户测试：先 C/D，再 PSD

只保留一个可复用入口 `run_tm_equalizer_system_checks.m`。下列是系统性能试验，
不是上述短入口测试的替代。固定 30 Msym/s、8 sps、卷积 3/4、258 Byte、
seed=917、零频偏/相偏/定时偏移，RRC/none 均测试。总时长约 82 ms，
前约 10 ms 预热，按各调制码速率换算帧数，不强求不同调制相同帧数。
连续打孔不按每帧取整；边界误差在一个帧以内。不同调制的数据不是同一波形。
每个均衡 OFF/ON 配对重设相同 seed，使用相同配置及信道时间范围。

```matlab
dbclear all; clearvars; clear functions; rehash;
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));
channelDir = ['C:/Users/admin/xwechat_files/wxid_95czmz1vt20422_de63/' ...
    'msg/file/2026-09/mat文件/mat文件'];

% 第三步：C1/D1，无噪声，9 种调制 × 两种成形 × 均衡关/开，共 72 组。
[Tcd, fileCD] = run_tm_equalizer_system_checks('cd',channelDir);

% 第四步：先隔离噪声，无 H、均衡关闭，三档 PSD，共 54 组。
[Tpsd, filePSD] = run_tm_equalizer_system_checks('psd');
```

信道路径若已移动，只修改 `channelDir`。信道处理固定 H Fs=100 kHz、线性插值、
时延插值开启、嵌入路径功率、H 归一化开启、超出时间范围报错，不循环信道。
这与页面可能使用的单文件 wrap 默认值不同，不能仅凭相同文件名就比较两次结果。
文件缺失会在开始前明确报错；接收器单个 case 失败则保存原因并继续，不停止全组。

PSD 测试固定参考输出电平 -10 dBm，积分噪声带宽显式统一为 Fs=240 MHz，
PSD 为 -115/-105/-95 dBm/Hz；No-H 下接收滤波前 SNR 约 21.20/11.20/1.20 dB。
它不是 Eb/N0 或判决点 SNR。低档允许如实失锁，不要求全组 BER=0。
RRC/none 不使用各自不同的默认噪声积分带宽，避免把加噪差异误当滤波性能差异。

先分析以上结果，之后才按需扩展；不是要求现在全部跑完：

```matlab
% C/D 剩余六个子型号，无噪声，共 216 组。
opt = struct('Profiles',["C_2","C_3","C_4","D_2","D_3","D_4"]);
[Tmore,fileMore] = run_tm_equalizer_system_checks('cd',channelDir,opt);

% 叠加 C1/D1 + 三档 PSD + 均衡 OFF/ON，共 216 组。
[Tcombined,fileCombined] = run_tm_equalizer_system_checks('psd-cd',channelDir);
```

每组结束立即打印状态并更新 MAT。输出只保存汇总表 T、原始配置 inputs、
日志 logs、测量区错误/未比较帧 badFrames，不保存接收 IQ 或创建每 case 脚本。
总结果目录：`artifacts/ccsds/system-eq`。大矩阵可能耗时较长，先跑默认两组。

## 看哪些字段

`RouteOK` 仅表示预期均衡入口与实际报告一致；`EQApplied` 表示接收器报告已执行，
`EQOutputAccepted` 是内部质量判据，不保证真实判决正确或已收敛。
`ZERO_ERRORS_COMPLETE` 才表示本次测量 BER=FER=0 且完整覆盖；
`MEASUREMENT_INCOMPLETE` 必须保留，不能把未比较帧当零错误，也不捏造 bit 错误。
`RUN_ERROR` 是调用/处理错误，不应直接当作理论性能边界。
若 OFF/ON 覆盖不同，不能直接用汇总 BER 判断改善幅度，先检查同一时间区间。

提交命令行输出或打印的 MAT 路径即可。定位单组时：

```matlab
S = load(fileCD);
disp(S.T);
k = 1;                         % 替换成异常组的 CaseIndex
disp(S.inputs{k});
disp(S.badFrames{k});
fprintf('%s\n',S.logs{k});
```

## QPSK 固定速率四阶段测试（2026-10-13）

本节只扩展测试入口，不修改接收器。`noh` 为无噪声 No-H，`files` / `psd-files`
把 `ChannelFiles` 中每个文件当成独立信道，绝不把 CDL/TDL/ITU 文件拼接成一条时序。
旧 `cd`/`psd` 的默认参数保持不变。`contract` 现在可以筛选历史短测试，不改其原配置。

固定 QPSK、RRC、卷积 3/4 连续接收、258 Byte TF、SPS=8、seed=917、零额外
频偏/相偏/delay。100 Mbps 指编码后调制器输入，得到 Rs=50 Msym/s、Fs=400 MHz；
不是净信息速率 100 Mbps。约 82 ms 总长、10 ms 预热，对应 358+2577 帧。
PSD 三档 -115/-105/-95 dBm/Hz，固定输入电平 -10 dBm，显式积分带宽 Fs。
No-H 滤波前输入 SNR 分别约 18.98/8.98/-1.02 dB，不是判决点 SNR 或 Eb/N0。

本节显式 `NormalizeH=false`，保留导出文件的原始 H 增益。与之前归一化的 CD
诊断不是同一条件。ITU-RP.* 中有大尺度损耗文件，不能把它们解释为多径模型；
极大损耗、零/极小系数或无效输入导致拒绝时如实保存原因，不通过自动归一化伪装通过。
目录中的旧文件没有采样率元数据，本批导出使用 100 kHz；其他来源需核实此值，
可以传 NaN 交由原加载器优先读元数据（无元数据时仍有历史回退）。禁止超范围 wrap。

复制以下整段，每轮只改 `Stage`；大矩阵可用 `ChannelGroup` 分批。
建议先完成 Stage=1、2 后分析，不要四步一次性全跑。

```matlab
dbclear all; clearvars; clear functions; rehash;
Stage = 1;                    % 1 / 2 / 3 / 4
ChannelGroup = "ALL";         % ALL / CDL / TDL / ITU
root = 'E:/web_code/react/fft_project/react-fft';
addpath(fullfile(root,'src','python','regression'));
channelDir = ['C:/Users/admin/xwechat_files/wxid_95czmz1vt20422_de63/' ...
    'msg/file/2026-09/mat文件/mat文件'];

assert(ismember(Stage,1:4));
assert(ismember(ChannelGroup,["ALL","CDL","TDL","ITU"]));
patterns = ["3GPPNTN-CDL_*_AntennaGain_1.mat", ...
    "3GPPNTN-TDL_*_AntennaGain_1.mat","ITU-*_AntennaGain_1.mat"];
families = ["CDL","TDL","ITU"];
channelFiles = strings(0,1);
for j=1:numel(patterns)
    if ChannelGroup~="ALL" && ChannelGroup~=families(j), continue; end
    entries=dir(fullfile(channelDir,patterns(j)));
    for k=1:numel(entries)
        channelFiles(end+1,1)=string(fullfile(entries(k).folder,entries(k).name));
    end
end
channelFiles=sort(unique(channelFiles));
if Stage~=1, assert(~isempty(channelFiles),'未找到所选信道文件，请检查路径。'); end

opt=struct('Mods',"QPSK",'Pulses',"root raised cosine", ...
    'ModulatorBitRateMbps',100,'Seeds',917,'EQStates',true, ...
    'TargetEnd_s',0.082,'WarmupTime_s',0.010, ...
    'InputLevelDbm',-10,'NoisePSDdBmHz',[-115 -105 -95], ...
    'ChannelSampleRateHz',1e5,'NormalizeH',false);
opt.ChannelFiles=channelFiles;
resultFiles=strings(0,1);

switch Stage
    case 1
        opt.EQStates=[false true];
        [T,f]=run_tm_equalizer_system_checks('noh','',opt);
        resultFiles(end+1)=string(f);
        if ~all(T.Status=="ZERO_ERRORS_COMPLETE")
            warning('No-H 基线未全部通过：先分析，不要继续扩展信道。');
        end
    case {2,4}
        if Stage==4
            opt.Pulses="none";
            baselineOpt=opt; baselineOpt.EQStates=[false true];
            [Tnone,f]=run_tm_equalizer_system_checks('noh','',baselineOpt);
            resultFiles(end+1)=string(f);
            fixture=fullfile(root,'artifacts','ccsds','eq-routing-20261011','frontend-requests.json');
            shortOpt=struct('Mods',"QPSK",'Pulses',"none",'EQStates',[false true]);
            [Tshort,f]=run_tm_equalizer_system_checks('contract',fixture,shortOpt);
            resultFiles(end+1)=string(f);
            % Tshort 保留历史 10 Msym/s、8+12 帧、小回波条件，不伪装成 100 Mbps 测试。
        end
        [T,f]=run_tm_equalizer_system_checks('files',channelDir,opt);
        resultFiles(end+1)=string(f);
        failed=T.Status~="ZERO_ERRORS_COMPLETE";
        if any(failed)
            offOpt=opt; offOpt.EQStates=false;
            offOpt.ChannelFiles=channelFiles(failed);
            [Toff,f]=run_tm_equalizer_system_checks('files',channelDir,offOpt);
            resultFiles(end+1)=string(f);
            % 仅关闭均衡；相同 seed、帧数、H 文件、时间区间与噪声设置。
        end
    case 3
        [Tnoise,f]=run_tm_equalizer_system_checks('psd','',opt);
        resultFiles(end+1)=string(f);
        [T,f]=run_tm_equalizer_system_checks('psd-files',channelDir,opt);
        resultFiles(end+1)=string(f);
end
disp(T);
fprintf('\n请保留并发送本轮这些 MAT 文件：\n');
disp(resultFiles(:));
```

Stage 2 若选择 ALL，当前目录为 16 CDL + 16 TDL + 6 ITU，共 38 个开启均衡用例，
再加失败项的关闭对照。Stage 3 为 3 个 No-H + 38×3 个 H/PSD 用例，可能耗时较长。
失效记录不是通过，`RUN_ERROR` 需看 Error 区分捕获拒绝、输入功率、格式、时间越界等原因。

新结果继续每个 case 保存：`T / inputs / logs / badFrames / diagnostics`，不存 IQ。
`diagnostics{k}.Locks` 给出各级观测来源、是否可用、首次锁定时刻；
`diagnostics{k}.LockEvents` 给出失锁、恢复和恢复耗时，未恢复事件保持 NaN，
未知状态绝不写成已锁定。时间为接收器遥测时间，包含预热；不是精确误码因果判定。
`badFrames{k}` 保存测量区每个错误或未比较帧，用它区分孤立、突发和持续错误。

```matlab
S=load(resultFiles(1));
disp(S.T);
idx=find(S.T.Status~="ZERO_ERRORS_COMPLETE");
for k=reshape(idx,1,[])
    disp(S.T(k,:)); disp(S.badFrames{k});
    if ~isempty(S.diagnostics{k})
        disp(S.diagnostics{k}.Locks);
        disp(S.diagnostics{k}.LockEvents);
    end
    fprintf('%s\n',S.logs{k});
end
```

入口验证：No-H RRC、100 Mbps、3 ms 总长/1 ms 预热，EQ OFF/ON 均零误码、72/72。
同长度 No-H 三档 PSD 均完成且零误码。短 H 检查中 CDL D1 为零误码72/72，TDL D1
有错误但覆盖72/72，原始 ITU-RP.619 因 FSE 输入功率检查拒绝；不能据此推断完整82 ms
性能或直接归为理论极限。历史 QPSK none 小回波复现 OFF=12/12、ON=10/12（已比较
部分零误码），缺口仍明确标记。38文件配置生成检查通过。完整矩阵留给用户执行。
