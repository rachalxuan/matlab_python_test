// Ordinary-TM web contract. DSP algorithms remain in MATLAB; never silently
// replace a requested code rate, data path or equalizer with another one.
export const ADAPTIVE_EQ_MODS = ["BPSK", "QPSK", "8PSK", "16QAM", "32QAM"];
export const PCM_MODS = ["BPSK", "QPSK", "8PSK", "OQPSK", "UQPSK", "16QAM", "32QAM", "16APSK", "32APSK"];
export const TURBO_BLOCKS = [1784, 3568, 7136, 8920];
export const FULL_RS_MESSAGE_LENGTHS = [223, 239];
export const FULL_RS_INTERLEAVING_DEPTHS = [1, 2, 3, 4, 5, 8];
export const CONTINUOUS_CONV_MODS = ["BPSK", "QPSK", "8PSK", "16QAM", "32QAM"];
export const SELECTABLE_PULSE_SHAPING_MODS = ["BPSK", "QPSK", "8PSK", "16QAM", "32QAM", "OQPSK", "UQPSK"];

// This is the number of coded bits presented to the mapper for one symbol.
// It is deliberately separate from the FEC code rate.  The equipment UI calls
// codedBitRate "码率 (Mbps)", while the MATLAB DSP chain needs symbolRate (Hz).
export function modulationBitsPerSymbol(modType, modulationEfficiency = 2) {
  const mod = String(modType || "").toUpperCase();
  if (mod.includes("4D-8PSK-TCM")) {
    const efficiency = Number(modulationEfficiency);
    return Number.isFinite(efficiency) && efficiency > 0 ? efficiency : 2;
  }
  if (mod.includes("UQPSK")) return 1.5;
  if (mod.includes("32QAM") || mod.includes("32APSK")) return 5;
  if (mod.includes("16QAM") || mod.includes("16APSK")) return 4;
  if (mod.includes("8PSK")) return 3;
  if (mod.includes("QPSK") || mod.includes("OQPSK")) return 2;
  return 1;
}

export function resolveModulationRates(input) {
  const p = { ...input };
  const bitsPerSymbol = modulationBitsPerSymbol(
    p.modType,
    p.ModulationEfficiency,
  );
  const bitRateMbps = Number(p.modulatorBitRateMbps);
  const legacySymbolRate = Number(p.symbolRate);

  if (Number.isFinite(bitRateMbps) && bitRateMbps > 0) {
    p.NominalBitsPerSymbol = bitsPerSymbol;
    p.ModulatorBitRate_bps = bitRateMbps * 1e6;
    p.symbolRate = p.ModulatorBitRate_bps / bitsPerSymbol;
    p.RateInputMode = "modulator-bit-rate";
  } else if (Number.isFinite(legacySymbolRate) && legacySymbolRate > 0) {
    // Backward compatibility for saved jobs and MATLAB-oriented callers.
    p.NominalBitsPerSymbol = bitsPerSymbol;
    p.ModulatorBitRate_bps = legacySymbolRate * bitsPerSymbol;
    p.modulatorBitRateMbps = p.ModulatorBitRate_bps / 1e6;
    p.RateInputMode = "symbol-rate";
  }
  return p;
}

export const RS_PRESETS = Object.fromEntries(
  FULL_RS_MESSAGE_LENGTHS.flatMap((messageLength) =>
    FULL_RS_INTERLEAVING_DEPTHS.map((interleavingDepth) => [
      `rs-255-${messageLength}-i${interleavingDepth}`,
      {
        label: `RS(255,${messageLength}), I=${interleavingDepth}, TF=${messageLength * interleavingDepth}`,
        RSMessageLength: messageLength,
        RSInterleavingDepth: interleavingDepth,
        IsRSMessageShortened: false,
        NumBytesInTransferFrame: messageLength * interleavingDepth,
      },
    ]),
  ),
);

export function codingDefaults(coding) {
  if (coding === "Turbo") return { CodeRate: "1/2", NumBitsInInformationBlock: 3568 };
  if (coding === "LDPC") return { CodeRate: "1/2", NumBitsInInformationBlock: 1024, LDPCCodeblockSize: 1 };
  if (coding === "concatenated") return { CodeRate: "N/A", ConvolutionalCodeRate: "1/2" };
  if (coding === "convolutional") return { CodeRate: "N/A", ConvolutionalCodeRate: "5/6", NumBytesInTransferFrame: 1151 };
  return { CodeRate: "N/A", TPCCodeRate: "2/3", TPCBlocksPerTF: 4 };
}

export function finalizeTMRequest(input) {
  const p = resolveModulationRates({ ...input, WaveformMode: "ordinaryTM" });
  if (!Number.isFinite(Number(p.symbolRate)) || Number(p.symbolRate) < 1e3 || Number(p.symbolRate) > 1e9) {
    throw new Error("由调制码率换算出的符号率必须在 1 ksym/s～1 Gsym/s 之间。");
  }
  if (p.DataPathMode !== "single" && p.DataPathMode) {
    if (!["QPSK", "OQPSK", "8PSK", "16QAM", "32QAM", "16APSK", "32APSK", "UQPSK"].includes(p.modType)) {
      throw new Error(`${p.modType} 当前仅支持合路，请将数据通路改为合路。`);
    }
    if (["TPC", "concatenated"].includes(p.channelCoding)) {
      throw new Error("TPC / 级联码尚未接入 I/Q 分路，请选择合路；不会自动改成其他编码。");
    }
    if (p.modType === "UQPSK" && p.PCMFormat !== "NRZ-L") {
      throw new Error("UQPSK 不等速分路当前仅支持 NRZ-L。");
    }
  }
  if (!Number.isInteger(Number(p.sps)) || Number(p.sps) < 2 || Number(p.sps) % 2) {
    throw new Error("当前页面接收前端要求 SPS 为不小于 2 的偶数。");
  }
  const pulseShapeKey = String(
    p.PulseShapingFilter || "root raised cosine",
  )
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ");
  if (["root raised cosine", "square root raised cosine", "rrc", "sqrt raised cosine"].includes(pulseShapeKey)) {
    p.PulseShapingFilter = "root raised cosine";
  } else if (["raised cosine", "normal raised cosine", "rc"].includes(pulseShapeKey)) {
    p.PulseShapingFilter = "raised cosine";
  } else if (["none", "off", "bypass", "no shaping"].includes(pulseShapeKey)) {
    p.PulseShapingFilter = "none";
  } else {
    throw new Error("成型滤波支持平方根升余弦（RRC）、升余弦（RC）或旁路（none）。");
  }
  if (p.PulseShapingFilter === "raised cosine" && !["OQPSK", "UQPSK"].includes(p.modType)) {
    throw new Error("升余弦（RC）本轮仅开放 OQPSK/UQPSK。");
  }
  if (p.PulseShapingFilter !== "root raised cosine") {
    if (!SELECTABLE_PULSE_SHAPING_MODS.includes(p.modType)) {
      throw new Error(`${p.modType} 使用专用波形前端，当前不能选择成型滤波旁路。`);
    }
    if (p.DataPathMode && p.DataPathMode !== "single") {
      throw new Error("新增 RC/旁路成型当前只支持合路（单路 TM）数据通路。");
    }
  }
  if (p.channelCoding === "Turbo" && !TURBO_BLOCKS.includes(Number(p.NumBitsInInformationBlock))) {
    throw new Error("Turbo 信息块长度须为 1784、3568、7136 或 8920 bit；不能沿用 LDPC 的 K=1024。");
  }
  if (["RS", "concatenated"].includes(p.channelCoding)) {
    const rsK = Number(p.RSMessageLength || 223);
    const rsI = Number(p.RSInterleavingDepth || 1);
    if (p.IsRSMessageShortened) {
      throw new Error("当前前端只开放已验证的非缩短 RS 配置；缩短 RS 尚未接入。");
    }
    if (!FULL_RS_MESSAGE_LENGTHS.includes(rsK)) {
      throw new Error("非缩短 RS 仅支持 RS(255,223) 或 RS(255,239)。");
    }
    if (!FULL_RS_INTERLEAVING_DEPTHS.includes(rsI)) {
      throw new Error("RS 交织深度仅开放已验证的 1、2、3、4、5、8。");
    }
    p.RSMessageLength = rsK;
    p.RSInterleavingDepth = rsI;
    p.IsRSMessageShortened = false;
    p.NumBytesInTransferFrame = rsK * rsI;
    delete p.RSShortenedMessageLength;
  }
  if (["convolutional", "concatenated"].includes(p.channelCoding)) {
    const continuousStreamEligible =
      p.hasASM !== false &&
      CONTINUOUS_CONV_MODS.includes(p.modType) &&
      (!p.DataPathMode || p.DataPathMode === "single") &&
      (!p.PCMFormat || p.PCMFormat === "NRZ-L") &&
      !p.RandomizerEnabled;
    p.ConvolutionalReceiveMode = continuousStreamEligible
      ? "stream-raw-asm"
      : "legacy-coded-asm";

    // The stream receiver carries encoder, puncture and Viterbi state across
    // TM-frame boundaries.  Only the legacy coded-ASM path still requires a
    // frame to end on the high-rate puncture period.
    if (p.ConvolutionalReceiveMode === "legacy-coded-asm" && p.hasASM !== false) {
      const period = { "5/6": 5, "7/8": 7 }[p.ConvolutionalCodeRate];
      const isRS = p.channelCoding === "concatenated";
      const frameBytes = isRS
        ? 255 * Number(p.RSInterleavingDepth || 1)
        : Number(p.NumBytesInTransferFrame);
      const convInputBits = 32 + 8 * frameBytes;
      if (period && convInputBits % period !== 0) {
        throw new Error(isRS
          ? `当前配置不能使用旧 coded-ASM 接收路径：ASM + RS 码字为 ${convInputBits} bit，不能整除卷积 ${p.ConvolutionalCodeRate} 的打孔输入周期 ${period}。请选择已接入连续接收器的普通合路调制、NRZ-L、关闭加扰。`
          : `当前配置不能使用旧 coded-ASM 接收路径：卷积 ${p.ConvolutionalCodeRate} 的 ${convInputBits} bit 输入不能整除打孔周期 ${period}。请选择已接入连续接收器的普通合路调制、NRZ-L、关闭加扰。`);
      }
    }
  } else {
    delete p.ConvolutionalReceiveMode;
  }
  if (/APSK$/.test(p.modType)) {
    p.APSKReceiverMode = "pilotless";
    p.HasTMAPSKPilots = false;
  }
  for (const key of ["acmFormat", "ACMFormat", "enableFACMEqualizer", "facmEqualizerMode", "facmEqualizerTaps", "facmEqualizerReg", "TMAPSKPilotInterval", "TMAPSKPilotLength", "TMAPSKPilotPreambleLength"]) delete p[key];
  if (p.enableEqualizer) {
    if (!p.enableHChannel) throw new Error("当前均衡对照请先选择 H 信道；无 H 基线请关闭均衡。");
    if (!ADAPTIVE_EQ_MODS.includes(p.modType)) throw new Error(`${p.modType} 使用专用前端，尚未接入此页面的通用自适应均衡选项，请关闭该选项。`);
    p.equalizerMode = "blind-cma-lms";
    p.adaptiveEqualizerSamplingMode = p.adaptiveEqualizerSamplingMode || "2sps";
    p.adaptiveFractionalPostMode = "off";
  } else {
    p.equalizerMode = "off";
    p.adaptiveEqualizerSamplingMode = "off";
  }
  p.noiseMode = p.noiseMode || "snr";
  if (!["off", "snr", "psd"].includes(p.noiseMode)) throw new Error("请选择无噪声、SNR 或固定 PSD 噪声模式。");
  for (const [key, fallback, min] of [["berWarmUpFrames", 8, 0], ["berFrames", 100, 1]]) {
    p[key] = Number(p[key] ?? fallback);
    if (!Number.isInteger(p[key]) || p[key] < min) throw new Error(`${key} 必须是大于等于 ${min} 的整数。`);
  }
  p.excludeBERWarmUpFrames = true;
  return p;
}

export function constellationExplanation(mod) {
  if (mod === "MSK") return "观察位置：MSK 前端固定码元定时抽样后的实际 IQ（若启用粗频偏校正，则位于其后）。MSK 初相位为 0，码元时刻可呈十字形四点；与对角四点相差显示相位，不代表它按 QPSK 解调。本页面不人为旋转或重画星座。";
  if (mod === "GMSK") return "显示接收链实际复采样。GMSK 有连续相位和高斯脉冲记忆，点云取决于 BT 与观察位置；不应强制画成 QPSK 四点。";
  if (mod === "OQPSK") return "OQPSK 的 I/Q 错开半个符号；定时及错位处理后的四点不表示其波形等同于 QPSK。";
  if (mod === "UQPSK") return "UQPSK 的 I/Q 幅度、速率可能不等，四点可呈矩形；请同时核对 I/Q 功率和速率比。";
  return "显示选定接收相位后的实际 IQ，不是理想模板；星座聚集并不保证无滑移或无误码。";
}
