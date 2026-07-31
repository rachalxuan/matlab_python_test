# CCSDS TM I/Q 分路模式 设计讨论与背景

> 本文档记录设计 `DataPathMode='dualIQ'` 时的概念澄清、FPGA 参考分析、设计决策。具体代码改动清单见 `split_path_implementation_guide.md`。

---

## 1. 概念澄清：合路 vs 分路

### 老师原话
> "分路意思是 I 是完整一帧，Q 是完整一帧，各自有帧头。合路就是 IQ 合到一起是一帧，有一个帧头。分路 IQ 各自译码。调制解调是一样的。"

### "调制解调是一样的" 是什么意思

关键要区分两层：

- **调制器本身**（QPSK/OQPSK/UQPSK 硬件模块）：一直都是"吃 I-bit 和 Q-bit 两个输入、输出 I+jQ 复符号"。这块在合路和分路两种模式下**完全一样**——星座图、成型滤波、载波调制、匹配滤波、载波恢复、定时恢复、解映射，全都一样。
- **调制器上游 / 解调器下游**（帧、编码、加扰）：合路只有一条 CCSDS 数据链路，分路是两条独立的 CCSDS 数据链路。

所以老师说的"调制解调是一样的" = **物理层调制解调模块完全不用改**，改的只是它两个输入口的"喂料方式"和两个输出口的"接料方式"。

### 合路模式（当前代码）

```
serial bits: b0 b1 b2 b3 b4 b5 ...
             ↓
iBit stream: b0    b2    b4  ...   ← 都来自同一帧
qBit stream: b1    b3    b5  ...   ← 都来自同一帧
             ↓
QPSK Mod  →  complex symbols
```

只有一个 `msg → 加扰 → 编码 → ASM → 串并转换 → 调制器`。I 和 Q 两条物理线上跑的都是**同一帧**的比特，只是奇偶位分开。

### 分路模式（要实现的）

```
msgI → 加扰I → 编码I → ASM_I → iBit stream  ─┐
                                              ├→ QPSK Mod → symbols
msgQ → 加扰Q → 编码Q → ASM_Q → qBit stream  ─┘
```

两个独立数据源、两条独立 CCSDS 链路，各自加自己的帧头、各自编码、各自加扰。**在调制器输入端并行喂进去**，调制器仍然做 `(1-2·iBit) + j·(1-2·qBit)`。

### "在调制之前再合并"？不需要

QPSK 调制器天生就有 I-bit 和 Q-bit 两个输入。它内部就是把两路各自当作 I 分量和 Q 分量，输出一个复数。**"合并"这个动作本来就是调制器自己做的事，外面不用再做**。

在 MATLAB 里等价于：
```matlab
iBits = tmEncode(msgI, ...);   % I 路完整 CCSDS 帧+编码+加扰
qBits = tmEncode(msgQ, ...);   % Q 路完整 CCSDS 帧+编码+加扰
symbols = (1-2*iBits) + 1j*(1-2*qBits);
```

### 哪些调制能分路

只对"I/Q 可分离的调制"有物理意义：

| 调制 | 能不能分路 | 原因 |
|---|---|---|
| BPSK | ❌ | 只有 I 轴，没有 Q |
| QPSK | ✅ | 天然 1 bit → I，1 bit → Q |
| OQPSK | ✅ | 同 QPSK，只是 Q 半符号延迟 |
| UQPSK | ✅✅ | 天生就是 I/Q 独立不同速率 |
| 16QAM | ✅ | FPGA 里用位交织进 mapper，不保 I/Q 轴分离但比特复原正确 |
| 32QAM | Phase 2 | merge 链路已通，split 当前 BER=0.5；需要 symbol-lane split mapper |
| 8PSK | Phase 2 | merge 链路已通，split 当前 BER=0.5；需要 symbol-lane split mapper |
| 4D-8PSK-TCM | ❌ | 网格编码跨 4 维符号 |
| GMSK/FM | ❌ | 连续相位调制，I/Q 强耦合 |
| PCM/PSK/PM | ❌ | 单载波相位调制 |

---

## 2. FPGA 参考分析

### 2.1 `map_data_switch.v`——分路开关在这里

**文件**：`E:/vivado_project/ccsds_fpga_prj_mod_tx.xpr/fpga_prj/fpga_prj.srcs/sources_1/imports/mod_tx/rtl/mod/mapping/map_data_switch.v`

关键信号：
```verilog
input [15:0] conv_I_tdata_0,   // I 路编码器输出 0
input [15:0] conv_I_tdata_1,   // I 路编码器输出 1
input [15:0] conv_Q_tdata_0,   // Q 路编码器输出 0
input [15:0] conv_Q_tdata_1,   // Q 路编码器输出 1
input        double_single,    // 0=合路(single) 1=分路(double)
input [ 2:0] modu_type,
```

模块天生就有两组输入 `conv_I_*` 和 `conv_Q_*`。上游是两条完全独立的编码链路。

### QPSK 合路（`double_single=0`）

行 243-281：
```verilog
S_qpsk_conv_enable_32b <= {
  conv_I_tdata_0[15], conv_I_tdata_1[15],   // 全部来自 I 编码器
  conv_I_tdata_0[14], conv_I_tdata_1[14],
  ...
};
```

只用 `conv_I_*`，把卷积编码器 rate 1/2 的两个输出比特 G0/G1 **交织**成 QPSK 一个符号的两个 bit。Q 编码器完全没用。

### QPSK 分路（`double_single=1`）

行 514-586：
```verilog
D_qpsk_conv_enable_64b <= {
  DataI[31], DataQ[31],    // I 轴的比特从 I 编码器来
  DataI[30], DataQ[30],    // Q 轴的比特从 Q 编码器来
  ...
};
```

`DataI` 只由 `conv_I_tdata_*` 打包，`DataQ` 只由 `conv_Q_tdata_*` 打包。两条独立编码器，各占 QPSK 星座的一个轴。

### 8PSK/16QAM/32QAM 分路

同样支持 `double_single=1`，但做法是**逐 bit 交织**：
```verilog
D_qam16_conv_bypass_32b <= {
  DataI[15], DataQ[15], DataI[14], DataQ[14], ...
};
```

对 16QAM 4bit/符号来说，符号 0 拿到 `{I0,Q0,I1,Q1}`——I-encoder 的比特和 Q-encoder 的比特**混在了一个星座点里**。这**不是真正的 I/Q 分离调制**，只是"两个编码器的输出被穿插起来喂给同一个 mapper"。

### 调制器本身共用

行 1122：
```verilog
MAP_QPSK MAP_QPSK (
    .DATA_IN(qpsk_map_fifo_out_data),  // 单/双模式共用同一个 FIFO 输出
    .DOUT_I (QPSK_I_data_map),
    .DOUT_Q (QPSK_Q_data_map),
    ...
);
```

**只有一个 MAP_QPSK 模块**。合路和分路走的是完全相同的 QPSK 映射器，只是它前面的 FIFO 里灌的 64bit 数据组织方式不同。这就是老师说的"调制解调是一样的"的字面意思。

---

### 2.2 `Mod_TOP.v`——顶层就是双入口架构

**文件**：`E:/vivado_project/ccsds_fpga_prj_mod_tx.xpr/fpga_prj/fpga_prj.srcs/sources_1/imports/mod_tx/rtl/mod/Mod_TOP.v`

#### 数据源就分 I/Q 两个入口

```verilog
input  [ 7:0] fix_data_I,          // I 路固定数据
input  [ 7:0] fix_data_Q,          // Q 路固定数据
input  [63:0] frame_asm_I,         // I 路帧头
input  [63:0] frame_asm_Q,         // Q 路帧头
input  [31:0] pn_state_I,          // I 路 PN 加扰初态
input  [31:0] pn_state_Q,          // Q 路 PN 加扰初态
```

用户在最顶层给的就是 I 和 Q 两组独立的数据、独立的 ASM、独立的 PN 初态。

#### AOS 组帧、加扰、RS 编码都是两条独立链

`aos_gen`（行 278-298）输出 `data_out_I` 和 `data_out_Q`，两路独立组帧。

`rs_enc_interleaver_I` 和 `rs_enc_interleaver_Q` 是两个独立的实例，各跑各的 RS 编码 + 加扰：
```verilog
rs_enc_interleaver rs_enc_interleaver_I ( .data_in(data_ini), .pn_state(pn_state_I), .frame_asm(frame_asm_I), ... );
rs_enc_interleaver rs_enc_interleaver_Q ( .data_in(data_inq), .pn_state(pn_state_Q), .frame_asm(frame_asm_Q), ... );
```

#### 卷积编码也一样

`conv_encoder`（行 548-562）同时处理 `din_i` 和 `din_q`：
```verilog
.din_i(nrz_data_I),     .dout_i_0(conv_I_tdata_0),   .dout_i_1(conv_I_tdata_1),
.din_q(nrz_data_Q),     .dout_q_0(conv_Q_tdata_0),   .dout_q_1(conv_Q_tdata_1),
```

#### `double_single` 只在 `map_data_switch` 才起作用

前面所有环节 I/Q 都是独立跑的。`map_data_switch` 才决定：
- `double_single=0`（合路）：**只用 `conv_I_tdata_*`**，Q 编码器出的数据被扔掉
- `double_single=1`（分路）：I 编码器上 I 轴，Q 编码器上 Q 轴

**FPGA 里"合路模式下 Q 那条编码链路是在空转"**——硬件资源浪费，但代码结构统一。

---

## 3. MATLAB 侧设计决策（用户已确认）

### 3.1 接口 Phase 1：单入口自动对半拆

```matlab
[wf, encoded] = tmWaveGen(msg);  % 保持不变
```

split 模式下：
- `NumInputBits` getter 返回值翻倍
- 内部把 `msg = [msgI; msgQ]` 前一半当 I，后一半当 Q

**Phase 2** 才重构成双入口 API `tmWaveGen(msgI, msgQ)`，对齐 FPGA 顶层。

**理由**：API 变化最小，先跑通端到端 BER，再重构 System object 输入端口数。

### 3.2 ASM / PRN：默认共享，预留扩展位

- 类里新增 `ASM_Q = []` 和 `PRNSequenceQ = []` public 属性
- 空 → fallback 到标准 ASM（`0x1ACFFC1D`）和 `pPRNSequence`
- Phase 2 启用时可以让 I/Q 用不同 ASM 和 PN 初态（对齐 FPGA `frame_asm_I/Q`, `pn_state_I/Q`）

### 3.3 编码器状态：I/Q 两套私有属性

不共享 `pConvEnc`。类里存 `pConvEncI` 和 `pConvEncQ` 两个独立的 `comm.ConvolutionalEncoder` 实例，各自跑各自的状态。对齐 FPGA 的两个 module 实例。

**⚠️ 不能写 `obj.pConvEncQ = obj.pConvEnc`**——MATLAB System object 是句柄类，会共享内部状态。必须 `clone()` 或分别 `new`。

### 3.4 调制白名单

**支持分路**（对齐 FPGA）：
- QPSK, OQPSK（真 I/Q 轴分离）
- 16QAM（FPGA 位交织方式，不保 I/Q 轴分离但比特复原正确）

**不支持分路**（split 下报错）：
- BPSK（无 Q 轴）
- 8PSK, 32QAM（Phase 2：奇数 bits/symbol，需要 symbol-lane split mapper）
- GMSK, FM（连续相位）
- 4D-8PSK-TCM（网格编码跨维符号）
- PCM/PSK/PM, PCM/PM/biphase-L
- UQPSK（Phase 1 暂不支持，Phase 2 加）
- FACM, LDPC-on-SMTF（分支结构复杂，pilots/SCCC 会跟 split 冲突）

---

## 4. 关键代码位置速查

### 发端 `ccsdsTMWaveformGenerator.m`
- **属性定义**：`RandomizerFECPosition`、`DataPathMode` 等，以及私有属性 pConvEnc/pInputBuffer/pCodewordIndex 等
- **setupImpl**：L352-495（编码器/调制器初始化）
- **stepImpl**：L497-609（主 step 入口，走 FACM 分支或普通 tmEncode+tmModulate）
- **tmEncode**：L1091-1377（split 报错在 L1097-1101，其它 case 分支里也各有 split 报错）
- **tmModulate**：L1380-1611（各 Modulation 分支）
- **updateInputBuffer**：L1651-1686
- **updateModInputBuffer**：L1688-1708
- **resetImpl**：L611-654
- **releaseImpl**：L656-681
- **saveObjectImpl/loadObjectImpl**：L684-750
- **NumInputBits getter**：L1072-1074
- **MinNumTransferFrames getter**：L1076-1087

### 收端 `HelperCCSDSTMDecoder.m`
- **split 报错点**：L457-461
- **stepImpl 入口**：L453
- **各 ChannelCoding 分支**：L545-895
- **pPRNSequence 使用**：L574 / L589 / L699 等

### 评估脚本 `run_ccsds_tm_evaluation.m`
- **DataPathMode 参数入口**
- **传给 tmWaveGen**：L250-252
- **传给 Decoder**：L2432-2434
- **msg 生成**：L385-423
- **decoder 调用**：L923

---

## 5. 现状盘点：当前已实现 vs 待实现

### 已实现
- `RandomizerEnabled` 总开关
- `RandomizerFECPosition ∈ {afterEncoding, beforeEncoding}`
- `DataPathMode='single'`：整条 TF 使用单路信息流
- 关闭加扰只使用 `RandomizerEnabled=false`，不再由路径模式表达
- 帧头 ASM 不加扰、每帧 PRN 复位（`single` 模式天然行为）

### 当前实现
- `DataPathMode='dualIQ'`：I/Q 双链路 + 位交织 + 分路解码
- 对齐 FPGA `map_data_switch.v` 的 `double_single=1` 行为

---

## 6. 下一步

参考 `split_path_implementation_guide.md` 按 Step 1 → Step 5 → Step 8 → Step 2 → Step 3+4 → Step 9 → Step 7 → Step 10 顺序改。
