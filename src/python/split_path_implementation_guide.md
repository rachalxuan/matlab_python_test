# CCSDS TM I/Q 分路模式 手改指南（Phase 1 MVP）

> Note: `ConvolutionalCodeRate` 为 `5/6` 或 `7/8` 时，推荐 `NumBytesInTransferFrame` (`TF`) 使用 `1116` 或 `1123`。其中 `1116` 同时适用于 `5/6` 和 `7/8`，`1123` 适用于 `7/8`；这些帧长能让 `ASM + TF` 长度与高码率打孔周期对齐。

> 目标：让 `DataPathMode='dualIQ'` 真正工作。I/Q 两路各自跑完整的 CCSDS 编码+加扰+ASM 链路，在调制器输入端按位交织成 `{I(1), Q(1), I(2), Q(2), ...}`，喂给同一个映射器。对齐 FPGA `map_data_switch.v` 的 `double_single=1` 行为。
>
> 建议按最后一节的"建议顺序"逐步做，每一小步跑一次 merge 用例回归，别一口气改完。

---

## Step 1 — 加属性

**文件**：`src/python/ccsdsTMWaveformGenerator.m`

### 1.1 Public 属性（约 L272-292 的 `properties` 块内，`TPCInterleaver = 'auto'` 之后追加）

```matlab
% ASM_Q Q-rail ASM override for split path mode.
%   Empty means use the same ASM as the I rail. Reserved for Phase 2.
ASM_Q = []
% PRNSequenceQ Q-rail PRN sequence override for split path mode.
%   Empty means use the same PRN sequence as the I rail. Reserved for Phase 2.
PRNSequenceQ = []
```

### 1.2 私有属性（约 L321-341 的 `properties(Access = private)` 块内，`pCodewordIndex` 之后追加）

```matlab
% -------- Split-path I/Q duplicated state (Phase 1) --------
pConvEncI
pConvEncQ
pConvEnc1I
pConvEnc1Q
pConvEnc2I
pConvEnc2Q
pConvEncStateI
pConvEncStateQ
pDiffEncI
pDiffEncQ
pInputBufferI
pInputBufferQ
pNumBitsInInputBufferI
pNumBitsInInputBufferQ
pCodewordIndexI
pCodewordIndexQ
pASM_Q
pPRNSequenceQ
pIsSplit = false     % cached from DataPathMode, set in setupImpl
```

### 1.3 Decoder 侧对应属性

`src/python/HelperCCSDSTMDecoder.m`，找到对应的 `properties(Access = private)` 块（pInputBuffer/pOutputBuffer 附近，L79-98 区域）追加：

```matlab
pInputBufferI
pInputBufferQ
pOutputBufferI
pOutputBufferQ
pASM_Q
pPRNSequenceQ
pIsSplit = false
```

Decoder 里 encoder 换成 decoder（Viterbi/LDPC/Turbo decoder），Step 9 里细化。

---

## Step 5 — 位交织/反交织函数（先做这个，独立可测）

### 5.1 交织函数

在 `ccsdsTMWaveformGenerator.m` 末尾（`localPCMDifferentialEncode` 附近，file-local function 区）加：

```matlab
function out = localBitInterleaveIQ(encI, encQ)
    % 位交织成 {I(1), Q(1), I(2), Q(2), ...}
    assert(length(encI)==length(encQ), 'localBitInterleaveIQ: I/Q length mismatch');
    encI = int8(encI(:));
    encQ = int8(encQ(:));
    n = length(encI);
    out = zeros(2*n, 1, 'int8');
    out(1:2:end) = encI;
    out(2:2:end) = encQ;
end
```

### 5.2 反交织函数

在 `HelperCCSDSTMDecoder.m` 末尾加：

```matlab
function [iStream, qStream] = localBitDeinterleaveIQ(interleaved)
    interleaved = interleaved(:);
    assert(mod(length(interleaved),2)==0, 'localBitDeinterleaveIQ: odd length');
    iStream = interleaved(1:2:end);
    qStream = interleaved(2:2:end);
end
```

### 5.3 单元测试（强推）

新建 `src/python/tests/test_split_bit_interleave.m`：

```matlab
function tests = test_split_bit_interleave
    tests = functiontests(localfunctions);
end
function testRoundTrip(testCase)
    rng(0);
    encI = int8(randi([0 1], 128, 1));
    encQ = int8(randi([0 1], 128, 1));
    interleaved = localBitInterleaveIQ(encI, encQ);   % 需 addpath
    verifyEqual(testCase, length(interleaved), 256);
    verifyEqual(testCase, interleaved(1:2:end), encI);
    verifyEqual(testCase, interleaved(2:2:end), encQ);
    [i2, q2] = localBitDeinterleaveIQ(interleaved);
    verifyEqual(testCase, i2, encI);
    verifyEqual(testCase, q2, encQ);
end
```

跑通这两个函数，位对齐就锁定了，后面再做大改。

---

## Step 2 — setupImpl 改动

**文件**：`ccsdsTMWaveformGenerator.m`，`setupImpl` 在 L352。

### 2.1 白名单校验 + pIsSplit 缓存

在 `setupImpl` 函数的**最开始**（`setupImpl@satcom.internal.ccsds.tmBase(obj)` 那行之后）加：

```matlab
obj.pIsSplit = strcmpi(obj.DataPathMode, 'dualIQ');
if obj.pIsSplit
    splitOkMods = {'QPSK','OQPSK','16QAM'};
    if ~ismember(obj.Modulation, splitOkMods)
        error('ccsdsTMWaveformGenerator:SplitModUnsupported', ...
            'DataPathMode="dualIQ" not supported for Modulation="%s". Phase 1 supports %s.', ...
            obj.Modulation, strjoin(splitOkMods, ', '));
    end
    if obj.pIsFACM || (obj.IsLDPCOnSMTF && strcmp(obj.ChannelCoding,'LDPC'))
        error('ccsdsTMWaveformGenerator:SplitFACMUnsupported', ...
            'Split path is not supported for FACM or LDPC-on-SMTF in Phase 1.');
    end
end
```

### 2.2 编码器双份实例化

在 `switch(obj.ChannelCoding)` 的每个 case 里（L362-400），把现有 `obj.pConvEnc = comm.ConvolutionalEncoder(...)` 之类的构造语句抽成一个局部函数或重复两次。

**以 `case 'convolutional'` 为例**，原来（L362-379 简化）：

```matlab
case {'convolutional','concatenated'}
    switch obj.ConvolutionalCodeRate
        case '1/2'
            obj.pConvEnc = comm.ConvolutionalEncoder('TrellisStructure',obj.ConvolutionalCodesTrellis);
        case '2/3'
            obj.pConvEnc = comm.ConvolutionalEncoder(...'PuncturePattern',[1;1;0;1]);
        ...
    end
```

改成：

```matlab
case {'convolutional','concatenated'}
    ceArgs = localBuildConvArgs(obj);   % 抽成一个 helper 返回 varargin cell
    obj.pConvEnc = comm.ConvolutionalEncoder(ceArgs{:});
    if obj.pIsSplit
        obj.pConvEncI = comm.ConvolutionalEncoder(ceArgs{:});
        obj.pConvEncQ = comm.ConvolutionalEncoder(ceArgs{:});
    end
```

`localBuildConvArgs(obj)` 是文件末尾的 local function，把原来 switch 里的参数打包成 cell。

Turbo 的 `pConvEnc1/pConvEnc2` 同理，split 下额外造 `pConvEnc1I/Q`、`pConvEnc2I/Q`。

**⚠️ 关键**：不能写 `obj.pConvEncQ = obj.pConvEnc`。System object 是句柄，会共享内部状态。必须 `clone()` 或分别 new 一次。

### 2.3 差分编码器

L477-479 有：

```matlab
if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
    obj.pDiffEnc = comm.DifferentialEncoder;
end
```

改成：

```matlab
if any(strcmp(obj.PCMFormat,{'NRZ-M','NRZ-S'}))
    obj.pDiffEnc = comm.DifferentialEncoder;
    if obj.pIsSplit
        obj.pDiffEncI = comm.DifferentialEncoder;
        obj.pDiffEncQ = comm.DifferentialEncoder;
    end
end
```

### 2.4 pNumModInBits 翻倍

在 `switch(obj.Modulation)` 结束后（L473 附近的 `obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8')` 之前）：

```matlab
if obj.pIsSplit
    obj.pNumModInBits = obj.pNumModInBits * 2;
end
obj.pModInputBuffer = zeros(obj.pNumModInBits,1,'int8');
obj.pNumBitsInpModInputBuffer = 0;
```

### 2.5 pASM_Q / pPRNSequenceQ 填充 + 双份 InputBuffer 初始化

在 `setupImpl` 末尾（L494 `end` 之前）加：

```matlab
if isempty(obj.ASM_Q)
    obj.pASM_Q = obj.pASM;
else
    obj.pASM_Q = int8(obj.ASM_Q(:));
end
if isempty(obj.PRNSequenceQ)
    obj.pPRNSequenceQ = obj.pPRNSequence;
else
    obj.pPRNSequenceQ = int8(obj.PRNSequenceQ(:));
end

% Split 下 pInputBuffer 双份初始化
if obj.pIsSplit
    if any(strcmp(obj.ChannelCoding,{'concatenated','convolutional'}))
        obj.pInputBufferI = zeros(obj.pConvEncInLen,1,'int8');
        obj.pInputBufferQ = zeros(obj.pConvEncInLen,1,'int8');
    else
        obj.pInputBufferI = zeros(obj.pK,1,'int8');
        obj.pInputBufferQ = zeros(obj.pK,1,'int8');
    end
    obj.pNumBitsInInputBufferI = 0;
    obj.pNumBitsInInputBufferQ = 0;
    obj.pCodewordIndexI = 1;
    obj.pCodewordIndexQ = 1;
    obj.pConvEncStateI = zeros(6,1,'int8');
    obj.pConvEncStateQ = zeros(6,1,'int8');
end
```

---

## Step 8 — NumInputBits getter

在 `NumInputBits` 的 getter（L1072-1074 附近）改：

```matlab
function l = get.NumInputBits(obj)
    l = getNumBytesInTransferFrame(obj)*8;
    if strcmpi(obj.DataPathMode, 'dualIQ')
        l = l * 2;
    end
end
```

---

## Step 3 + Step 4 — stepImpl 分路走线 + tmEncode 重构（最重的部分）

### 4.1 tmEncode 重构成 tmEncodeOneRail

**思路**：把 `tmEncode(obj, bits)` 里所有出现的 `obj.pConvEnc`、`obj.pInputBuffer`、`obj.pPRNSequence`、`obj.pASM`、`obj.pDiffEnc` 都通过一个 rail 参数选择。改造成：

```matlab
function encoded = tmEncodeOneRail(obj, bits, rail)
    % rail: 'I' / 'Q' / 'M'
    [convEnc, inBuf, numInBuf, prnSeq, asm, diffEnc, cwIdx] = localGetRailState(obj, rail);

    % ...原来的 tmEncode 主体，但把 obj.pConvEnc 换成 convEnc
    %                              obj.pInputBuffer 换成 inBuf
    %                              obj.pPRNSequence 换成 prnSeq
    %                              obj.pASM 换成 asm
    %                              obj.pDiffEnc 换成 diffEnc
    %                              obj.pCodewordIndex 换成 cwIdx

    % 结束时写回状态：
    localSetRailState(obj, rail, convEnc, inBuf, numInBuf, prnSeq, asm, diffEnc, cwIdx);
end

function encoded = tmEncode(obj, bits)   % 保留原有 API 作为 wrapper
    encoded = tmEncodeOneRail(obj, bits, 'M');
end
```

**注意**：System object（`convEnc`）是句柄，直接传引用即可，不用写回。缓冲变量（`inBuf`、`numInBuf`）是值类型，必须写回。

`localGetRailState` / `localSetRailState` 是文件内 local function，根据 `rail` 返回对应的 `obj.pXxxI/Q/M` 状态：

```matlab
function [convEnc, inBuf, numInBuf, prnSeq, asm, diffEnc, cwIdx] = localGetRailState(obj, rail)
    switch rail
        case 'I'
            convEnc = obj.pConvEncI;
            inBuf = obj.pInputBufferI;
            numInBuf = obj.pNumBitsInInputBufferI;
            prnSeq = obj.pPRNSequence;
            asm = obj.pASM;
            diffEnc = obj.pDiffEncI;
            cwIdx = obj.pCodewordIndexI;
        case 'Q'
            convEnc = obj.pConvEncQ;
            inBuf = obj.pInputBufferQ;
            numInBuf = obj.pNumBitsInInputBufferQ;
            prnSeq = obj.pPRNSequenceQ;
            asm = obj.pASM_Q;
            diffEnc = obj.pDiffEncQ;
            cwIdx = obj.pCodewordIndexQ;
        otherwise  % 'M'
            convEnc = obj.pConvEnc;
            inBuf = obj.pInputBuffer;
            numInBuf = obj.pNumBitsInInputBuffer;
            prnSeq = obj.pPRNSequence;
            asm = obj.pASM;
            diffEnc = obj.pDiffEnc;
            cwIdx = obj.pCodewordIndex;
    end
end
```

**同时把所有 `error('ccsdsTMWaveformGenerator:SplitNotImplemented', ...)` 分支删除**。这些分支原来是“如果 dualIQ 就报错”，现在因为 `tmEncodeOneRail` 每次只处理一条 rail，单 rail 编码逻辑与 `single` 相同，可直接复用。

### 4.2 stepImpl 分路分支

在 `stepImpl`（L497-609）里，找到原来的 else 分支（L591-597）：

```matlab
else
    % Channel encoding, randomization and ASM insertion
    encodedBits = tmEncode(obj,int8(bits));
    % Modulate the encoded bits
    symbols = tmModulate(obj,encodedBits);
end
```

改成：

```matlab
else
    if obj.pIsSplit
        N = length(bits);
        assert(mod(N,2)==0, 'split 模式下 bits 长度必须为偶数');
        msgI = bits(1:N/2);
        msgQ = bits(N/2+1:end);
        encI = tmEncodeOneRail(obj, int8(msgI), 'I');
        encQ = tmEncodeOneRail(obj, int8(msgQ), 'Q');
        encodedBits = localBitInterleaveIQ(encI, encQ);
    else
        encodedBits = tmEncode(obj, int8(bits));
    end
    symbols = tmModulate(obj, encodedBits);
end
```

---

## Step 7 — reset / release / save / load 补齐

### resetImpl（L611-654）

在末尾加：

```matlab
if obj.pIsSplit
    if ~isempty(obj.pConvEncI), reset(obj.pConvEncI); end
    if ~isempty(obj.pConvEncQ), reset(obj.pConvEncQ); end
    if ~isempty(obj.pConvEnc1I), reset(obj.pConvEnc1I); end
    if ~isempty(obj.pConvEnc1Q), reset(obj.pConvEnc1Q); end
    if ~isempty(obj.pConvEnc2I), reset(obj.pConvEnc2I); end
    if ~isempty(obj.pConvEnc2Q), reset(obj.pConvEnc2Q); end
    if ~isempty(obj.pDiffEncI), reset(obj.pDiffEncI); end
    if ~isempty(obj.pDiffEncQ), reset(obj.pDiffEncQ); end
    obj.pInputBufferI = zeros(size(obj.pInputBuffer),'int8');
    obj.pInputBufferQ = zeros(size(obj.pInputBuffer),'int8');
    obj.pNumBitsInInputBufferI = 0;
    obj.pNumBitsInInputBufferQ = 0;
    obj.pCodewordIndexI = 1;
    obj.pCodewordIndexQ = 1;
    obj.pConvEncStateI = zeros(6,1,'int8');
    obj.pConvEncStateQ = zeros(6,1,'int8');
end
```

### releaseImpl（L656-681）

类似加 6 个 System object 的 release 调用：

```matlab
if obj.pIsSplit
    if ~isempty(obj.pConvEncI), release(obj.pConvEncI); end
    if ~isempty(obj.pConvEncQ), release(obj.pConvEncQ); end
    % ... 其他 6 个 System object 同理
end
```

### saveObjectImpl / loadObjectImpl（L684-750）

`saveObjectImpl` 把所有新增 `pXxxI/Q` 属性写进 `s`；`loadObjectImpl` 把它们从 `s` 里读回来。跟现有的 `s.pInputBuffer = obj.pInputBuffer` 模式一致。

---

## Step 9 — Decoder 侧（HelperCCSDSTMDecoder.m）

按跟 Encoder 完全对称的方式改：

1. 删除 L457-461 的 split error
2. `setupImpl` 里加 `pIsSplit` 缓存 + split 下把 `pASM` 交织成 `localBitInterleaveIQ(pASM, pASM_Q)`
3. 重构 `stepImpl` 主体为 `tmDecodeOneRail(rail)`
4. split 分支：拿到 `u`（剥 ASM 后的 payload LLR）后 `[iLLR, qLLR] = localBitDeinterleaveIQ(u)`，各跑一遍 decoder，`y = [yI; yQ]`
5. Viterbi decoder 也需要复制成 `pVitDecI/Q`（这个具体属性名要看你现在 Decoder 里怎么命名的 Viterbi decoder System object）

**Decoder 侧 stepImpl 分路伪代码**：

```matlab
if obj.pIsSplit
    % u 是剥了 ASM 的 payload LLR
    [iLLR, qLLR] = localBitDeinterleaveIQ(u);
    yI = tmDecodeOneRail(obj, iLLR, 'I');
    yQ = tmDecodeOneRail(obj, qLLR, 'Q');
    y = [yI; yQ];
else
    y = tmDecodeOneRail(obj, u, 'M');
end
```

**关键**：ASM 也参与位交织，所以在 setupImpl 里 split 下要把 `obj.pASM = localBitInterleaveIQ(obj.pASM, obj.pASM_Q)`（因为 TX 侧 ASM 也是每条 rail 各附一份然后一起交织的）。让 `frameSynchronize` 直接对交织后的 ASM 做同步。

---

## Step 10 — 主脚本 + 验证

### 10.1 主脚本适配

`run_ccsds_tm_evaluation.m` 里 msg 生成走 `tmWaveGen.NumInputBits`（getter 已经翻倍），理论上不用改。跑一遍 merge 用例先确认没破坏原有行为。

可选：加个 opt 参数 `splitPathDebug`，split 模式下额外打印 I/Q 各自的 BER（调试用）。

### 10.2 验证阶梯

按这个顺序跑：

| 阶段 | 参数 | 预期 |
|---|---|---|
| 1 | QPSK + none + HasASM=false + RandomizerEnabled=false + dualIQ | 无信道 BER=0 |
| 2 | QPSK + none + HasASM=true + dualIQ | ASM 交织后同步能锁上 |
| 3 | QPSK + none + RandomizerEnabled=true + afterEncoding + dualIQ | 每 rail 独立复位 PRN |
| 4 | QPSK + convolutional 1/2 + dualIQ（AWGN SNR 5-10 dB） | BER 曲线趋势跟 single 一致 |
| 5 | OQPSK + convolutional + split | 同上 |
| 6 | 16QAM + none + split | 只做比特复原验证 |
| 7 | 8PSK + convolutional + split | Phase 2：需要 symbol-lane split mapper |
| 8 | 32QAM + LDPC + split | Phase 2：需要 symbol-lane split mapper |

每阶段跑一次同参数的 merge 做对照。

---

## 建议顺序

1. **Step 1**（属性声明）+ **Step 5**（交织函数 + 单元测试）→ 跑单元测试通过
2. **Step 8**（NumInputBits getter）→ 跑一次 merge 用例，确认 getter 逻辑没影响
3. **Step 2**（setupImpl 白名单 + 双 encoder 实例化）→ 跑 merge 用例回归
4. **Step 3+4**（stepImpl 分路 + tmEncode 重构）→ 端到端 QPSK-none 跑通（不带 ASM 不带信道）
5. **Step 9**（Decoder 侧）→ 端到端 QPSK-none 闭环
6. **Step 7**（reset/release/save/load）→ 跑多 step / 多次调用测试
7. **Step 10**（验证阶梯）→ 逐档加复杂度

**任何一步跑挂了就先停下来查，别一口气全改完再调。**

---

## 风险点速查

- **System object clone**：`pConvEncQ = clone(pConvEncI)` 或分别新建。**不要**赋值 `pConvEncQ = pConvEncI`（共享内部状态）
- **卷积码连续状态**：I/Q 的 `pInputBuffer` 分别持有，跨 step 各自累积，不能污染
- **ASM 交织顺序**：TX 侧和 RX 侧 `bitInterleaveIQ` 的偶奇约定必须完全一致。用 fixed pattern 测试对齐
- **afterEncoding randomizer**：`tmEncodeOneRail` 尾部 XOR，绝对不能放在交织之后（否则 I/Q 加扰序列混掉）
- **`saveObjectImpl`/`loadObjectImpl`**：新增所有 `pXxxI/Q` 属性必须序列化，否则 codegen / MAT 读取失败
- **NumInputBits getter 依赖**：调用方必须用 `tmWaveGen.NumInputBits` 而不是硬编码 `getNumBytesInTransferFrame*8`

---

## Phase 2 TODO（本 phase 不做，作为下一阶段目标）

- **双入口 API**：`stepImpl(obj, msgI, msgQ)`，`setupImpl` 里 `numInputs = 2`
- **UQPSK 分路**：`iBits` 按 `rRatio` 分组进 I 轴 PAM，`qBits` 每 1 bit 进 Q 轴
- **启用 `ASM_Q` 和 `PRNSequenceQ`** public 属性，允许 I/Q 独立配置
- **4D-8PSK-TCM 分路**（如果需要）
- **FACM / LDPC-on-SMTF 分支**的分路支持
