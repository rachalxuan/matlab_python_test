// Ordinary-TM web contract. DSP algorithms remain in MATLAB; never silently
// replace a requested code rate, data path or equalizer with another one.
export const ADAPTIVE_EQ_MODS = ["BPSK", "QPSK", "8PSK", "16QAM", "32QAM"];
export const PCM_MODS = ["BPSK", "QPSK", "8PSK", "OQPSK", "UQPSK", "16QAM", "32QAM", "16APSK", "32APSK"];
export const TURBO_BLOCKS = [1784, 3568, 7136, 8920];

export function codingDefaults(coding) {
  if (coding === "Turbo") return { CodeRate: "1/2", NumBitsInInformationBlock: 3568 };
  if (coding === "LDPC") return { CodeRate: "1/2", NumBitsInInformationBlock: 1024, LDPCCodeblockSize: 1 };
  if (coding === "concatenated") return { CodeRate: "N/A", ConvolutionalCodeRate: "1/2" };
  if (coding === "convolutional") return { CodeRate: "N/A", ConvolutionalCodeRate: "5/6", NumBytesInTransferFrame: 1151 };
  return { CodeRate: "N/A", TPCCodeRate: "2/3", TPCBlocksPerTF: 4 };
}

export function finalizeTMRequest(input) {
  const p = { ...input, WaveformMode: "ordinaryTM" };
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
  if (p.channelCoding === "Turbo" && !TURBO_BLOCKS.includes(Number(p.NumBitsInInformationBlock))) {
    throw new Error("Turbo 信息块长度须为 1784、3568、7136 或 8920 bit；不能沿用 LDPC 的 K=1024。");
  }
  if (["convolutional", "concatenated"].includes(p.channelCoding) && p.hasASM !== false) {
    const period = { "5/6": 5, "7/8": 7 }[p.ConvolutionalCodeRate];
    const isRS = p.channelCoding === "concatenated";
    const rsK = Number(p.RSMessageLength || 223);
    const rsS = p.IsRSMessageShortened ? Number(p.RSShortenedMessageLength) : rsK;
    const frameBytes = isRS ? (255 - rsK + rsS) * Number(p.RSInterleavingDepth || 1) : Number(p.NumBytesInTransferFrame);
    const convInputBits = 32 + 8 * frameBytes;
    if (period && convInputBits % period !== 0) {
      throw new Error(isRS
        ? `级联码配置不兼容：ASM + RS 编码后数据为 ${convInputBits} bit，不能整除卷积 ${p.ConvolutionalCodeRate} 的打孔输入周期 ${period}。请优先使用内码 1/2；不要把 RS 信息帧任意改成 1116 字节。`
        : `卷积 ${p.ConvolutionalCodeRate} 要求 ASM + 信息帧长度可整除 ${period}。当前为 ${convInputBits} bit；可选 TF=1151 字节。`);
    }
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
