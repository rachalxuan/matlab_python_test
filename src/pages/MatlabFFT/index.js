import React, { useState, useEffect, useRef } from "react";
import {
  runMatlabSimulation,
  getSimulationTaskStatus,
  cancelSimulationTask,
  saveSimulationRecord,
  getHistoryList,
  getRecordDetail,
  getChannelModels,
  uploadChannelFile,
} from "../../apis/simulation";

import {
  Card,
  Form,
  InputNumber,
  Select,
  Button,
  Row,
  Col,
  message,
  Tag,
  Empty,
  Statistic,
  Divider,
  Checkbox,
  Drawer,
  List,
  Space,
  Tooltip,
  Descriptions,
  Alert,
  Upload,
  Modal,
} from "antd";
import {
  RocketOutlined,
  SettingOutlined,
  GatewayOutlined,
  CheckCircleOutlined,
  SyncOutlined,
  BarChartOutlined,
  RadarChartOutlined,
  SaveOutlined,
  HistoryOutlined,
  ClockCircleOutlined,
  InfoCircleOutlined,
  StopOutlined,
  UploadOutlined,
} from "@ant-design/icons";
import * as echarts from "echarts";
import "./index.scss";
import {
  finalizeTMRequest,
  codingDefaults,
  PCM_MODS,
  TURBO_BLOCKS,
  RS_PRESETS,
  constellationExplanation,
  modulationBitsPerSymbol,
  SELECTABLE_PULSE_SHAPING_MODS,
  resolveModulationRates,
} from "./parameterContract";

const { Option } = Select;

const DEFAULT_CCSDS_PARAMS = {
  modType: "QPSK",
  channelCoding: "convolutional",
  PCMFormat: "NRZ-L",
  ConvolutionalCodeRate: "5/6",
  CodeRate: "N/A",
  TPCCodeRate: "2/3",
  TPCBlocksPerTF: 4,
  NumBitsInInformationBlock: 1024,
  IsLDPCOnSMTF: false,
  LDPCCodeblockSize: 1,
  NumBytesInTransferFrame: 1151,
  // Device-equivalent coded bit rate at the constellation mapper input.
  modulatorBitRateMbps: 100,
  symbolRate: 50000000,
  PulseShapingFilter: "root raised cosine",
  RolloffFactor: 0.35,
  FilterSpanInSymbols: 10,
  BandwidthTimeProduct: 0.5,
  ModulationEfficiency: 2.0,
  ModulationIndex: 1.0,
  TZZS: 0.715,
  SubcarrierWaveform: "sine",
  snr: 15,
  noiseMode: "snr",
  noisePSDdBmHz: -115.3,
  berWarmUpFrames: 8,
  berFrames: 100,
  adaptiveEqualizerSamplingMode: "2sps",
  cfo: 0,
  phaseOffset: 0,
  delay: 0,
  sps: 8,
  hasASM: true,
  RandomizerMode: "off",
  DataPathMode: "single",
  TMDataSource: "random",
  TMDataSourceI: "random",
  TMDataSourceQ: "random",
  TMDataSourceFixedPattern: 85,
  TMDataSourceIncrementStart: 0,
  AGCMode: "off",
  rsPreset: "rs-255-223-i5",
  channelModel: "none",
  channelSampleRateHz: 100000,
  normalizeHChannel: false,
  enableEqualizer: false,
  // 仅导出仿真时间轴上的同步状态，不参与接收机校正。
  enableRuntimeLockTelemetry: true,
  runtimeStatusUpdateMs: 200,
};

const MODULATION_OPTIONS = [
  { value: "BPSK", label: "BPSK" },
  { value: "QPSK", label: "QPSK" },
  { value: "8PSK", label: "8PSK" },
  { value: "GMSK", label: "GMSK" },
  { value: "MSK", label: "MSK" },
  { value: "OQPSK", label: "OQPSK" },
  { value: "UQPSK", label: "UQPSK" },
  { value: "16QAM", label: "16QAM" },
  { value: "32QAM", label: "32QAM" },
  { value: "16APSK", label: "16APSK " },
  { value: "32APSK", label: "32APSK " },
  { value: "FM", label: "FM" },
  { value: "4D-8PSK-TCM", label: "4D-8PSK-TCM" },
  { value: "PCM/PSK/PM", label: "PCM/PSK/PM" },
];

const TM_DATA_SOURCE_OPTIONS = [
  { value: "random", label: "随机帧数据（原默认）" },
  ...[7, 8, 9, 10, 11, 15, 23, 31].map((order) => ({
    value: `PN${order}`,
    label: `PN${order}`,
  })),
  { value: "fixed", label: "固定码" },
  { value: "incrementing", label: "递增码" },
];

const CHANNEL_CODING_OPTIONS = [
  { value: "none", label: "无编码" },
  { value: "convolutional", label: "卷积码" },
  { value: "RS", label: "RS码" },
  { value: "concatenated", label: "级联码" },
  { value: "LDPC", label: "LDPC" },
  { value: "Turbo", label: "Turbo" },
  { value: "TPC", label: "TPC" },
];

const PCM_FORMAT_OPTIONS = ["NRZ-L", "NRZ-M", "NRZ-S"];

const MODES_WITH_PCM_FORMAT = PCM_MODS;

const H_DAMAGE_PRESETS = {
  none: null,
  medium: {
    real: [1, 0, 0.125, 0, 0.071],
    imag: [0, 0, 0.217, 0, -0.071],
  },
  strong: {
    real: [1, 0, 0.225, 0, 0.156, 0, 0.097],
    imag: [0, 0, 0.39, 0, -0.156, 0, 0.071],
  },
};

const formatDefaultValue = (value) => {
  if (typeof value === "boolean") return value ? "开启" : "关闭";
  if (typeof value === "number") return value.toLocaleString();
  return String(value);
};

const isBlankValue = (value) =>
  value === undefined || value === null || value === "";

const applyDefaultParams = (values = {}) => {
  const next = { ...DEFAULT_CCSDS_PARAMS, ...values };

  Object.entries(DEFAULT_CCSDS_PARAMS).forEach(([key, defaultValue]) => {
    if (isBlankValue(next[key])) {
      next[key] = defaultValue;
    }
  });

  return next;
};

const defaultRule = (name) => [
  {
    validator: (_, value) => {
      if (!isBlankValue(value)) return Promise.resolve();
      return Promise.reject(
        new Error(
          `未填写将使用默认值 ${formatDefaultValue(
            DEFAULT_CCSDS_PARAMS[name],
          )}`,
        ),
      );
    },
    warningOnly: true,
  },
];

const VALIDATION_LIMITS = {
  modulatorBitRateMbps: { min: 0.001, max: 5000, label: "调制码率" },
  symbolRate: { min: 1e3, max: 1e9, label: "符号率" },
  snr: { min: -20, max: 100, label: "信噪比" },
  sps: { min: 2, max: 64, label: "采样/符号" },
  RolloffFactor: { min: 0.01, max: 1, label: "滚降系数" },
  FilterSpanInSymbols: { min: 2, max: 128, label: "滤波器长度" },
  BandwidthTimeProduct: { min: 0.1, max: 1, label: "BT 值" },
  ModulationIndex: { min: 0.01, max: 2, label: "调制指数" },
  TZZS: { min: 0.1, max: 2, label: "FM 调制指数" },
  cfo: { min: -1e7, max: 1e7, label: "频偏" },
  phaseOffset: { min: -360, max: 360, label: "相位偏移" },
  delay: { min: -8, max: 8, label: "定时偏差" },
  NumBytesInTransferFrame: { min: 1, max: 65535, label: "传输帧字节数" },
};

const enumRule = (allowedValues, label = "参数") => ({
  validator: (_, value) => {
    if (isBlankValue(value)) return Promise.resolve();
    if (allowedValues.includes(value)) return Promise.resolve();
    return Promise.reject(
      new Error(`${label}不合法，请从下拉选项中选择有效值`),
    );
  },
});

const numericRangeRule = (name, { integer = false } = {}) => ({
  validator: (_, value) => {
    if (isBlankValue(value)) return Promise.resolve();
    const numberValue = Number(value);
    const limit = VALIDATION_LIMITS[name];
    const label = limit?.label || name;
    if (!Number.isFinite(numberValue)) {
      return Promise.reject(new Error(`${label}必须是有效数字`));
    }
    if (integer && !Number.isInteger(numberValue)) {
      return Promise.reject(new Error(`${label}必须是整数`));
    }
    if (limit && numberValue < limit.min) {
      return Promise.reject(new Error(`${label}不能小于 ${limit.min}`));
    }
    if (limit && numberValue > limit.max) {
      return Promise.reject(new Error(`${label}不能大于 ${limit.max}`));
    }
    return Promise.resolve();
  },
});

const fieldRules = (name, options = {}) => [
  ...defaultRule(name),
  numericRangeRule(name, options),
];

const delayBySpsRule = ({ getFieldValue }) => ({
  validator: (_, value) => {
    if (isBlankValue(value)) return Promise.resolve();

    const numberValue = Number(value);
    if (!Number.isFinite(numberValue)) {
      return Promise.reject(new Error("定时偏差必须是有效数字"));
    }

    const sps = Number(getFieldValue("sps") ?? DEFAULT_CCSDS_PARAMS.sps);
    const maxDelay =
      Number.isFinite(sps) && sps > 0 ? sps : DEFAULT_CCSDS_PARAMS.sps;
    if (Math.abs(numberValue) > maxDelay) {
      return Promise.reject(
        new Error(
          `定时偏差不能超过 ±${maxDelay} samples（当前 SPS=${maxDelay}）`,
        ),
      );
    }

    return Promise.resolve();
  },
});

const labelWithDefault = (label, name, extra = "") => (
  <span>
    {label}{" "}
    <Tooltip
      title={`默认值 ${formatDefaultValue(DEFAULT_CCSDS_PARAMS[name])}${
        extra ? `。${extra}` : ""
      }；清空后提交会自动补全。`}
    >
      <InfoCircleOutlined style={{ color: "#8c8c8c" }} />
    </Tooltip>
  </span>
);

const isFiniteNumber = (value) =>
  typeof value === "number" && Number.isFinite(value);

const formatMetricValue = (value, digits = 2) => {
  if (!isFiniteNumber(value) || value < 0) return "N/A";
  if (value === 0) return "0";
  if (Math.abs(value) >= 1000 || Math.abs(value) < 0.01) {
    return value.toExponential(digits);
  }
  return value.toFixed(digits);
};

const formatLockStatus = (locked) => {
  if (locked === true) return "Locked";
  if (locked === false) return "Unlocked";
  return "Unknown";
};

const formatCodeRateDisplay = (raw) => {
  const preferred =
    raw?.TPCCodeRate ??
    raw?.ConvolutionalCodeRate ??
    raw?.codeRate ??
    raw?.CodeRate ??
    null;

  if (typeof preferred === "string") {
    return preferred;
  }

  if (isFiniteNumber(preferred)) {
    const commonRates = new Map([
      [0.5, "1/2"],
      [1 / 3, "1/3"],
      [1 / 4, "1/4"],
      [1 / 6, "1/6"],
      [2 / 3, "2/3"],
      [3 / 4, "3/4"],
      [4 / 5, "4/5"],
      [5 / 6, "5/6"],
      [7 / 8, "7/8"],
      [1, "1"],
    ]);

    for (const [rate, label] of commonRates.entries()) {
      if (Math.abs(preferred - rate) < 1e-6) {
        return label;
      }
    }

    return formatMetricValue(preferred, 3);
  }

  return "N/A";
};

const getEvmDisplay = (stats) => {
  if (!stats || !isFiniteNumber(stats.EVMPercent) || stats.EVMPercent < 0) {
    return "未启用";
  }
  return `${formatMetricValue(stats.EVMPercent)}%`;
};

const getFerDisplay = (stats) => {
  if (!stats || !isFiniteNumber(stats.FER) || stats.FER < 0) {
    return "N/A";
  }
  if (stats.FER === 0) return "0";
  return Number(stats.FER).toExponential(2);
};

const isGMSKResult = (result) =>
  String(result?.modType || result?.info || "")
    .toUpperCase()
    .includes("GMSK");

const getEvmTitle = (result) => (isGMSKResult(result) ? "GMSK IQ err" : "EVM");

const getMerTitle = (result) => (isGMSKResult(result) ? "IQ MER" : "MER");

const getMetricTone = (value, thresholds = {}) => {
  if (!isFiniteNumber(value) || value < 0) return "default";
  const { good = 0.01, warn = 0.05 } = thresholds;
  if (value <= good) return "success";
  if (value <= warn) return "warning";
  return "error";
};

const EVM_TONE_THRESHOLDS = { good: 8, warn: 15 };

const getBerSummary = (ber, coverage) => {
  if (coverage?.Available && !coverage.Complete) {
    return `测量覆盖不足（${coverage.ComparedFrames}/${coverage.ExpectedFrames} 帧），BER 只代表已比较部分，不能判定整段无误码。`;
  }
  if (!isFiniteNumber(ber) || ber < 0) return "当前场景下未得到有效 BER。";
  if (ber === 0) return "本次已比较数据未检测到误码；不等于长期 BER 为零，也不能代替锁定检测。";
  if (ber < 1e-4) return "链路质量较好，误码已经很低。";
  if (ber < 1e-2) return "链路可用，但已经能看到明显损伤影响。";
  return "链路误码偏高，建议优先检查同步或信道损伤设置。";
};

const getEvmSummary = (evmPercent) => {
  if (!isFiniteNumber(evmPercent) || evmPercent < 0) {
    return "当前调制方式下没有可靠的 EVM 结果。";
  }
  if (evmPercent < 8) return "星座点聚集较好，当前调制质量正常。";
  if (evmPercent < 15) return "星座有一定扩散，但接收机通常还能稳定工作。";
  if (evmPercent < 25)
    return "调制质量已经明显下降，建议结合 BER 和锁定率判断。";
  return "星座偏离较大，当前损伤已经比较重。";
};

const getGMSKEvmSummary = () =>
  "GMSK 是一种连续相位调制，因此该数值仅作为 IQ 或包络的粗略指示，而非标准的星座图 EVM。在评估 GMSK 的信号质量时，建议优先参考 BER（误码率）、载波/码元/帧同步状态、PAPR（峰均功率比）、相位轨迹、相位差以及 PSD（功率谱密度）";

const normalizeRuntimeLockTrack = (track) => {
  if (!track || track.Available !== true) {
    return {
      available: false,
      source: track?.Source || "unavailable",
      reason: track?.Reason || "当前接收路径未导出该锁定状态",
      locked: null,
      ratePercent: null,
      lossEvents: 0,
      reacquisitions: 0,
      time: [],
      state: [],
      displayTime: [],
      displayState: [],
    };
  }
  return {
    available: true,
    source: track.Source || "receiver detector",
    reason: track.Reason || "",
    locked: Boolean(track.LockedAtEnd),
    ratePercent: isFiniteNumber(track.LockRate)
      ? track.LockRate * 100
      : null,
    lossEvents: Number(track.LossEvents || 0),
    reacquisitions: Number(track.Reacquisitions || 0),
    time: Array.isArray(track.Time_s) ? track.Time_s : [],
    state: Array.isArray(track.State) ? track.State : [],
    displayTime: Array.isArray(track.DisplayTime_s)
      ? track.DisplayTime_s
      : [],
    displayState: Array.isArray(track.DisplayState)
      ? track.DisplayState
      : [],
  };
};

const RuntimeLockIndicator = ({ track }) => {
  if (!track?.available) {
    return <span title={track?.reason || "当前接收路径未导出此状态"}>N/A</span>;
  }

  return (
    <>
      <Tag color={track.locked ? "success" : "error"}>
        {track.locked ? "锁定" : "失锁"}
      </Tag>
      {isFiniteNumber(track.ratePercent)
        ? `${formatMetricValue(track.ratePercent)}%`
        : ""}
    </>
  );
};

const normalizeSimulationResult = (raw) => {
  if (!raw) return null;

  // 兼容 link_simulation 的结果包装：数值指标和三张 Base64 图片分开。
  const referenceImages = raw.images || {};
  raw = raw.matlab_result_data || raw;

  if (raw.success === false) {
    return raw;
  }

  if (Object.prototype.hasOwnProperty.call(raw, "BER")) {
    const lockRate = isFiniteNumber(raw.LockRate) ? raw.LockRate : null;
    const runtimeLock = raw.RuntimeLockTelemetry?.Enabled
      ? {
          carrier: normalizeRuntimeLockTrack(
            raw.RuntimeLockTelemetry.Carrier,
          ),
          timing: normalizeRuntimeLockTrack(raw.RuntimeLockTelemetry.Timing),
          frame: normalizeRuntimeLockTrack(raw.RuntimeLockTelemetry.Frame),
          statusUpdatePeriod: raw.RuntimeLockTelemetry.StatusUpdatePeriod_s,
        }
      : null;
    const runtimeLockTracks = runtimeLock
      ? [runtimeLock.carrier, runtimeLock.timing, runtimeLock.frame]
      : [];
    const allRuntimeLocksAvailable =
      runtimeLockTracks.length === 3 &&
      runtimeLockTracks.every((track) => track.available);
    const combinedLockStatus = runtimeLock
      ? allRuntimeLocksAvailable
        ? runtimeLockTracks.every((track) => track.locked)
        : null
      : isFiniteNumber(lockRate)
        ? lockRate > 0.8
        : null;
    const elapsedTime = isFiniteNumber(raw.ElapsedTime)
      ? raw.ElapsedTime
      : null;

    return {
      success: true,
      info: raw.info || raw.modType || "CCSDS Evaluation",
      modType: raw.modType || raw.info || "",
      ber: raw.BER,
      errorMsg: raw.errorMsg || "",
      spectrum: raw.spectrum,
      constellation_tx: raw.constellation_tx,
      constellation_raw: raw.constellation_raw,
      constellation_synced: raw.constellation_synced,
      pipeline: raw.pipeline, // 4 阶段星座 + EVM 数组 + 标签
      channelPower: raw.channelPower,
      images: {
        time: referenceImages.time_base64 || raw.time_base64 || null,
        spectrum:
          referenceImages.spectrum_base64 || raw.spectrum_base64 || null,
        constellation:
          referenceImages.constellation_base64 ||
          raw.constellation_base64 ||
          null,
      },
      stats: {
        Fs: raw.Fs,
        SymbolRateHz: isFiniteNumber(raw.SymbolRate_Hz)
          ? raw.SymbolRate_Hz
          : null,
        ModulatorBitRateBps: isFiniteNumber(raw.ModulatorBitRate_bps)
          ? raw.ModulatorBitRate_bps
          : null,
        NominalBitsPerSymbol: isFiniteNumber(raw.NominalBitsPerSymbol)
          ? raw.NominalBitsPerSymbol
          : null,
        RateInputMode: raw.RateInputMode || null,
        PulseShapingFilter: raw.PulseShapingFilter || null,
        TransmitPulseShapeActual: raw.TransmitPulseShapeActual || null,
        ReceivePulseFilterActual: raw.ReceivePulseFilterActual || null,
        CodeRate: formatCodeRateDisplay(raw),
        ChannelCoding: raw.channelCoding,
        ElapsedTime: elapsedTime,
        EVMPercent: raw.EVM_post_pct,
        EVMPrePercent: raw.EVM_pre_pct,
        MERdB: raw.MER_dB,
        SNREstdB: raw.SNR_est_dB,
        PAPRdB: raw.PAPR_dB,
        FER: isFiniteNumber(raw.FER)
          ? raw.FER
          : isFiniteNumber(raw.FrameErrorRate)
            ? raw.FrameErrorRate
            : null,
        FrameErrors: isFiniteNumber(raw.FrameErrors) ? raw.FrameErrors : null,
        CountedFrames: isFiniteNumber(raw.CountedFrames)
          ? raw.CountedFrames
          : null,
        MatchedFrames: isFiniteNumber(raw.MatchedFrames)
          ? raw.MatchedFrames
          : null,
        DecodedFrames: isFiniteNumber(raw.DecodedFrames)
          ? raw.DecodedFrames
          : null,
        AcquisitionFrames: isFiniteNumber(raw.AcquisitionFrames)
          ? raw.AcquisitionFrames
          : null,
        AcquisitionTime: isFiniteNumber(raw.AcquisitionTime_s)
          ? raw.AcquisitionTime_s
          : null,
        LockRate: lockRate,
        LockRatePercent: isFiniteNumber(lockRate) ? lockRate * 100 : null,
        LegacyLockRateMeaning:
          raw.LegacyLockRateMeaning ||
          "评估器发送/接收帧匹配率，不是接收机锁定检测器",
        RuntimeLock: runtimeLock,
        CarrierLock: runtimeLock?.carrier || null,
        TimingLock: runtimeLock?.timing || null,
        FrameSyncLock: runtimeLock?.frame || null,
        LockStatus: combinedLockStatus,
        InputSNR: raw.snr_in,
        NoiseMode: raw.NoiseMode,
        NoiseEquivalentSNR: raw.NoiseEquivalentSNR_dB,
        APSKReceiverMode: raw.APSKReceiverMode,
        AdaptiveEqualizerMode: raw.AdaptiveEqualizerMode,
        MeasurementCoverage:
          raw.ReceiverTimeline?.MeasurementCoverage ||
          raw.MeasurementCoverage ||
          null,
        ConvolutionalReceiveMode: raw.ConvolutionalReceiveMode,
        RSMessageLength: isFiniteNumber(raw.RSMessageLength)
          ? raw.RSMessageLength
          : null,
        RSInterleavingDepth: isFiniteNumber(raw.RSInterleavingDepth)
          ? raw.RSInterleavingDepth
          : null,
        InputCFO: raw.cfo_in,
        InputPhase: raw.phase_in,
        InputDelay: raw.delay_in,
        DataPathMode: raw.DataPathMode,
        TMDataSource: raw.TMDataSource,
        TMDataSourceI: raw.TMDataSourceI,
        TMDataSourceQ: raw.TMDataSourceQ,
        RandomizerEnabled: raw.RandomizerEnabled,
        RandomizerFECPosition: raw.RandomizerFECPosition,
        AGCEnabled: raw.AGCEnabled,
        AGCTimeConstantMs: raw.AGCTimeConstantMs,
        AGCFinalGain_dB: raw.AGCFinalGain_dB,
        AGCSufficientObservation: raw.AGCSufficientObservation,
        // 残余损伤 (同步链路压制后剩余,理想值接近 0)
        ResidCFOValid:
          raw.ResidualCFO_valid === undefined
            ? isFiniteNumber(raw.ResidualCFO_Hz) ||
              isFiniteNumber(raw.residCFO_Hz)
            : Boolean(raw.ResidualCFO_valid),
        ResidCFOHz: isFiniteNumber(raw.ResidualCFO_Hz)
          ? raw.ResidualCFO_Hz
          : isFiniteNumber(raw.residCFO_Hz)
            ? raw.residCFO_Hz
            : null,
        ResidPhaseValid:
          raw.ResidualPhase_valid === undefined
            ? isFiniteNumber(raw.ResidualPhase_deg) ||
              isFiniteNumber(raw.residPhase_deg)
            : Boolean(raw.ResidualPhase_valid),
        ResidPhaseDeg: isFiniteNumber(raw.ResidualPhase_deg)
          ? raw.ResidualPhase_deg
          : isFiniteNumber(raw.residPhase_deg)
            ? raw.residPhase_deg
            : null,
      },
      rawEvaluation: raw,
    };
  }

  return raw;
};

const CCSDSPlatform = () => {
  //创建Form实例， 用于管理所有数据状态
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [currentTaskId, setCurrentTaskId] = useState(null);
  const [taskStatusText, setTaskStatusText] = useState("");
  const [simResult, setSimResult] = useState(null);
  const [errorNotice, setErrorNotice] = useState(null);
  const showError = (detail) => setErrorNotice(String(detail));
  const hasRemoteImages =
    !simResult?.spectrum &&
    Boolean(
      simResult?.images?.time ||
        simResult?.images?.spectrum ||
        simResult?.images?.constellation,
    );
  const [isElectron, setIsElectron] = useState(false);
  const [historyVisible, setHistoryVisible] = useState(false);
  const [historyList, setHistoryList] = useState([]);
  const [channelModels, setChannelModels] = useState([]);
  const [uploadedChannelModels, setUploadedChannelModels] = useState([]);

  // 图表 Refs
  const rawConstellationRef = useRef(null);
  // const constellationRef = useRef(null);
  const syncedConstellationRef = useRef(null);
  const spectrumRef = useRef(null);
  const channelPowerRef = useRef(null);
  const channelSpectrumRef = useRef(null);
  const chartInstances = useRef({});
  const pollCancelledRef = useRef(false);

  // 码率常量
  const TURBO_RATES = ["1/2", "1/3", "1/4", "1/6"];
  const LDPC_RATES = ["1/2", "2/3", "4/5", "7/8"];
  const LDPC_INFO_BLOCKS = [1024, 4096, 16384, 7136];
  const CONVOLUTIONAL_RATES = ["1/2", "2/3", "3/4", "5/6", "7/8"];
  const TPC_RATES = ["1/2", "2/3"];

  useEffect(() => {
    setIsElectron(window && window.matlabAPI !== undefined);

    getChannelModels()
      .then((res) => setChannelModels(res?.models || []))
      .catch((error) => console.warn("读取信道模型列表失败:", error));

    const resizeHandler = () => {
      Object.values(chartInstances.current).forEach(
        (chart) => chart && chart.resize(),
      );
    };
    window.addEventListener("resize", resizeHandler);
    return () => window.removeEventListener("resize", resizeHandler);
  }, []);

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  const waitForSimulationTask = async (taskId) => {
    while (!pollCancelledRef.current) {
      const task = await getSimulationTaskStatus(taskId);
      const status = task?.status;

      if (status === "queued") {
        setTaskStatusText(`排队中，第 ${task.position || 1} 位`);
      } else if (status === "running") {
        setTaskStatusText("计算中...");
      } else if (status === "cancelling") {
        setTaskStatusText("正在停止任务...");
      }

      if (status === "completed") {
        return task.result;
      }
      if (status === "failed") {
        throw new Error(task.error || "任务执行失败");
      }
      if (status === "cancelled") {
        throw new Error("任务已停止");
      }

      await sleep(1000);
    }

    throw new Error("任务轮询已停止");
  };

  const runSimulation = async (values) => {
    setLoading(true);
    setCurrentTaskId(null);
    setTaskStatusText("提交任务中...");
    pollCancelledRef.current = false;
    setSimResult(null);
    try {
      const completedValues = applyDefaultParams(values);
      form.setFieldsValue(completedValues);

      let payload = {
        ...completedValues,
        taskType: "ccsds_tm",
        NumBytesInTransferFrame: Number(
          completedValues.NumBytesInTransferFrame ?? 1151,
        ),
      };

      // 前端只暴露高层选项；底层参数在这里统一收口。
      payload.WaveformMode = "ordinaryTM";
      payload.showFigures = false;

      const requestedPath = payload.DataPathMode === "dualIQ" ? "dualIQ" : "single";
      const splitCapableModulations = [
        "QPSK",
        "OQPSK",
        "8PSK",
        "16QAM",
        "32QAM",
        "16APSK",
        "32APSK",
        "UQPSK",
      ];
      if (!splitCapableModulations.includes(payload.modType)) {
        if (requestedPath !== "single") throw new Error(`${payload.modType} 当前仅支持合路，请修改数据通路。`);
        payload.DataPathMode = "single";
      } else if (payload.modType === "UQPSK" && requestedPath === "dualIQ") {
        payload.DataPathMode = "unequalDualIQ";
      } else {
        payload.DataPathMode = requestedPath;
      }

      const randomizerMode = payload.RandomizerMode || "off";
      payload.RandomizerEnabled = randomizerMode !== "off";
      payload.RandomizerFECPosition =
        randomizerMode === "beforeEncoding" ? "beforeEncoding" : "afterEncoding";
      delete payload.RandomizerMode;

      const agcMode = payload.AGCMode || "off";
      payload.AGCEnabled = agcMode !== "off";
      payload.AGCTimeConstantMs = agcMode === "off" ? 10 : Number(agcMode);
      delete payload.AGCMode;

      if (payload.channelCoding === "None") {
        payload.channelCoding = "none";
      }

      if (!MODES_WITH_PCM_FORMAT.includes(payload.modType)) {
        payload.PCMFormat = "NRZ-L";
      }

      if (
        payload.channelCoding === "convolutional" ||
        payload.channelCoding === "concatenated"
      ) {
        payload.ConvolutionalCodeRate = payload.ConvolutionalCodeRate || "5/6";
      } else {
        delete payload.ConvolutionalCodeRate;
      }

      if (payload.channelCoding === "TPC") {
        delete payload.ConvolutionalCodeRate;
        payload.TPCCodeRate = payload.TPCCodeRate || "2/3";
        // TPC information blocks are not byte aligned at every shortened
        // rate.  Use the validated ordinary-TM profiles rather than
        // leaving the backend at its generic one-block default.
        payload.TPCBlocksPerTF = payload.TPCCodeRate === "1/2" ? 8 : 4;
        payload.CodeRate = "N/A";
      } else {
        delete payload.TPCCodeRate;
        delete payload.TPCBlocksPerTF;
      }

      if (payload.channelCoding === "LDPC") {
        const k = Number(payload.NumBitsInInformationBlock ?? 1024);
        payload.NumBitsInInformationBlock = k;
        payload.CodeRate = k === 7136 ? "7/8" : payload.CodeRate || "1/2";
        payload.IsLDPCOnSMTF = false;
        payload.LDPCCodeblockSize = Number(payload.LDPCCodeblockSize ?? 1);
      }

      if (payload.channelCoding === "Turbo") {
        payload.CodeRate =
          payload.CodeRate === "N/A" ? "1/2" : payload.CodeRate;
        payload.NumBitsInInformationBlock = Number(
          payload.NumBitsInInformationBlock ?? 1784,
        );
      }

      if (
        payload.channelCoding === "RS" ||
        payload.channelCoding === "concatenated"
      ) {
        const preset =
          RS_PRESETS[payload.rsPreset] || RS_PRESETS["rs-255-223-i5"];
        Object.assign(payload, {
          RSMessageLength: preset.RSMessageLength,
          RSInterleavingDepth: preset.RSInterleavingDepth,
          IsRSMessageShortened: false,
          NumBytesInTransferFrame: preset.NumBytesInTransferFrame,
        });
        delete payload.RSShortenedMessageLength;
      }

      const selectedChannel = payload.channelModel || "none";
      const hPreset = H_DAMAGE_PRESETS[selectedChannel.replace("synthetic_", "")];
      if (selectedChannel === "upload-sequence" && uploadedChannelModels.length > 1) {
        const descriptors = uploadedChannelModels.map((item) => {
          const match = String(item.fileName || "").match(/^(.*)_(\d+)\.mat$/i);
          return match ? { prefix: match[1], ordinal: Number(match[2]) } : null;
        });
        const prefixes = new Set(descriptors.filter(Boolean).map((item) => item.prefix));
        const ordinals = descriptors.filter(Boolean).map((item) => item.ordinal);
        if (
          descriptors.some((item) => item === null) ||
          prefixes.size !== 1 ||
          new Set(ordinals).size !== ordinals.length
        ) {
          throw new Error(
            "快照序列必须来自同一天线/模型前缀，并以唯一的 _1.mat、_2.mat… 结尾；不要把 A_1/A_2 等不同方向图混成时间序列。",
          );
        }
      }
      const uploadedSequence =
        selectedChannel === "upload-sequence" && uploadedChannelModels.length
          ? {
              id: "upload-sequence",
              label: `自定义快照序列（${uploadedChannelModels.length} 个）`,
              paths: uploadedChannelModels.map((item) => item.path),
            }
          : null;
      const matrixChannel =
        channelModels.find((item) => item.id === selectedChannel) ||
        uploadedSequence ||
        uploadedChannelModels.find((item) => item.id === selectedChannel) ||
        null;
      if (selectedChannel !== "none" && !hPreset && !matrixChannel) {
        throw new Error("所选信道未找到，请重新选择或上传 MAT 文件；不会自动改成无 H 信道。");
      }
      payload.enableHChannel = Boolean(hPreset || matrixChannel);
      if (hPreset) {
        payload.HMode = "siso_multipath";
        payload.H = hPreset;
        payload.normalizeHChannel = true;
      } else if (matrixChannel) {
        payload.HMode = "h_matrix_file";
        const channelPaths = matrixChannel.paths || [matrixChannel.path];
        payload.channelFilePath = channelPaths[0];
        if (channelPaths.length > 1) {
          payload.channelFilePaths = channelPaths;
        } else {
          delete payload.channelFilePaths;
        }
        payload.channelSampleRateHz = Number(
          payload.channelSampleRateHz || 100000,
        );
        payload.channelInterpolationMethod = "linear";
        // A time sequence must never silently repeat or freeze after its
        // declared end; insufficient H duration is a configuration error.
        payload.channelOutOfRangeMode = channelPaths.length > 1 ? "error" : "wrap";
        payload.interpolateChannelDelays = channelPaths.length > 1;
        payload.normalizeHChannel = Boolean(payload.normalizeHChannel);
        delete payload.H;
      } else {
        payload.HMode = "none";
        payload.H = [];
        payload.normalizeHChannel = false;
        delete payload.channelFilePath;
        delete payload.channelFilePaths;
      }
      payload.enableEqualizer = Boolean(payload.enableEqualizer);
      payload.normalizeEqualizerOutput = true;
      delete payload.channelModel;
      delete payload.acmFormat;

      if (payload.modType === "FM") {
        payload.RolloffFactor = Number(payload.RolloffFactor ?? 0.5);
        payload.TZZS = Number(payload.TZZS ?? 0.715);
      }

      if (payload.modType === "UQPSK") {
        payload.RRatio = 2;
        payload.ARatio = 2;
        payload.enableUQPSKFFTCoarseCFO = true;
      }

      // MSK/GMSK 使用单路连续相位链路，避免把底层 I/Q 分路参数传入。
      if (payload.modType === "MSK" || payload.modType === "GMSK") {
        payload.DataPathMode = "single";
      }

      payload = finalizeTMRequest(payload);
      form.setFieldsValue({
        modulatorBitRateMbps: payload.modulatorBitRateMbps,
        symbolRate: payload.symbolRate,
      });
      console.log("正在通过 HTTP 请求仿真...", payload);
      const submitRes = await runMatlabSimulation(payload);
      if (!submitRes?.success || !submitRes?.taskId) {
        throw new Error(submitRes?.error || "任务提交失败");
      }

      setCurrentTaskId(submitRes.taskId);
      try { localStorage.setItem("receiverMonitorTaskId", submitRes.taskId); }
      catch { /* A disabled browser store must not stop the simulation. */ }
      setTaskStatusText(
        submitRes.position
          ? `排队中，第 ${submitRes.position} 位`
          : "已提交任务",
      );

      const res = await waitForSimulationTask(submitRes.taskId);
      const normalizedRes = normalizeSimulationResult(res);
      if (normalizedRes) normalizedRes.taskId = submitRes.taskId;
      console.log("Residual CFO fields:", {
        rawResidualCFO: res?.ResidualCFO_Hz,
        rawResidualCFOValid: res?.ResidualCFO_valid,
        normalizedResidualCFO: normalizedRes?.stats?.ResidCFOHz,
        normalizedResidualCFOValid: normalizedRes?.stats?.ResidCFOValid,
      });

      if (normalizedRes && normalizedRes.success) {
        message.success("仿真成功！");
        setSimResult(normalizedRes);
        renderCharts(normalizedRes);

        //  保存到 localStorage
        try { localStorage.setItem("latestSimResult", JSON.stringify(normalizedRes)); }
        catch { /* Large PNG results can exceed browser storage; reception still succeeded. */ }

        if (normalizedRes.stats?.ElapsedTime) {
          console.log(`后端计算耗时: ${normalizedRes.stats.ElapsedTime}s`);
        }
      } else {
        showError("仿真失败: " + (normalizedRes?.error || "未知错误"));
      }
    } catch (error) {
      console.error("调用失败:", error);
      if (
        error.message === "任务已停止" ||
        error.message === "任务轮询已停止"
      ) {
        message.info("任务已停止");
      } else {
        showError(error.message || "请求失败，请检查 Python 服务是否启动");
      }
    } finally {
      setLoading(false);
      setCurrentTaskId(null);
      setTaskStatusText("");
      pollCancelledRef.current = false;
    }
  };

  const stopCurrentTask = async () => {
    if (!currentTaskId) {
      message.warning("当前没有正在运行或排队的任务");
      return;
    }

    try {
      setTaskStatusText("正在发送停止请求...");
      await cancelSimulationTask(currentTaskId);
      pollCancelledRef.current = true;
      setLoading(false);
      setCurrentTaskId(null);
      setTaskStatusText("");
      message.info("已请求停止任务");
    } catch (error) {
      console.error("停止任务失败:", error);
      showError("停止任务失败，请检查 Python 服务");
    }
  };

  const handleFormFinishFailed = ({ errorFields }) => {
    if (errorFields?.length) {
      form.scrollToField(errorFields[0].name);
    }
    showError("参数不合法，请修改标红字段：\n" + (errorFields || []).flatMap(field => field.errors || []).join("\n"));
  };

  const fillDefaultParams = () => {
    const completedValues = applyDefaultParams(form.getFieldsValue());
    form.setFieldsValue(completedValues);
    message.success("已补全参数");
  };

  const handleChannelUpload = async ({ file, onSuccess, onError }) => {
    try {
      const result = await uploadChannelFile(file);
      if (!result?.success || !result?.model) {
        throw new Error(result?.error || "上传失败");
      }
      setUploadedChannelModels((previous) => {
        const next = [
          ...previous.filter((item) => item.id !== result.model.id),
          result.model,
        ];
        next.sort((a, b) => {
          const parse = (name) => {
            const match = String(name || "").match(/^(.*)_(\d+)\.mat$/i);
            return match
              ? { prefix: match[1], ordinal: Number(match[2]) }
              : { prefix: String(name || ""), ordinal: Number.NaN };
          };
          const aa = parse(a.fileName);
          const bb = parse(b.fileName);
          if (aa.prefix === bb.prefix && Number.isFinite(aa.ordinal) && Number.isFinite(bb.ordinal)) {
            return aa.ordinal - bb.ordinal;
          }
          return String(a.fileName).localeCompare(String(b.fileName));
        });
        return next;
      });
      form.setFieldValue("channelModel", "upload-sequence");
      message.success(`已加入信道快照：${result.model.label}`);
      onSuccess?.(result);
    } catch (error) {
      showError(error.message || "上传信道文件失败");
      onError?.(error);
    }
  };

  // === 新增功能 A: 点击保存按钮 ===
  const handleSave = async () => {
    // 防御性编程：如果没有结果，就不让存
    if (!simResult) {
      message.warning("当前没有仿真结果可保存，请先运行仿真！");
      return;
    }

    try {
      // 1. 获取当前表单里填的所有参数
      const currentConfig = form.getFieldsValue();

      // 2. 调用 API 发送给 Python
      const res = await saveSimulationRecord({
        config: currentConfig,
        result: simResult,
      });

      if (res && res.success) {
        message.success("✅ 保存成功！");
      }
    } catch (error) {
      console.error(error);
      showError("保存失败，请检查后端连接");
    }
  };

  // === 新增功能 B: 打开历史记录列表 ===
  const openHistory = async () => {
    setHistoryVisible(true); // 打开抽屉
    try {
      // 获取列表
      const res = await getHistoryList();
      // 这里要注意：如果你的 request 封装直接返回 data，就直接用 res
      // 如果返回的是 axios 对象，可能需要 res.data
      // 假设你的 request 封装比较标准：
      if (Array.isArray(res)) {
        setHistoryList(res);
      } else {
        // 防止后端报错导致前端崩溃
        setHistoryList([]);
      }
    } catch (error) {
      showError("获取历史记录失败");
    }
  };

  // === 新增功能 C: 点击某条历史记录进行回放 ===
  const loadHistoryItem = async (id) => {
    const hide = message.loading("正在加载历史数据...", 0);
    try {
      // 1. 请求完整数据
      const res = await getRecordDetail(id);

      if (res && res.success && res.data) {
        const { config, result } = res.data;
        const normalizedResult = normalizeSimulationResult(result);

        // 2. 核心操作：把存的数据“填”回去

        // 2.1 填表单
        form.setFieldsValue(resolveModulationRates(config));

        // 2.2 恢复 React 状态（这会让界面上的数字变化）
        setSimResult(normalizedResult);

        // 2.3 这一步最关键：重新根据数据画图
        // React 的 state 更新是异步的，为了保险，直接把 result 传给画图函数
        renderCharts(normalizedResult);

        message.success("已加载历史记录");
        setHistoryVisible(false); // 关掉抽屉
      }
    } catch (error) {
      console.error(error);
      showError("加载失败");
    } finally {
      hide();
    }
  };
  const drawConstellation = (domRef, title, data) => {
    const dom = domRef.current;

    if (!dom || !data) return;

    // 销毁旧实例
    const oldChart = echarts.getInstanceByDom(dom);
    if (oldChart) oldChart.dispose();

    const chart = echarts.init(dom);

    // 构造 ECharts 数据格式
    const points = data.i.map((v, k) => [v, data.q[k]]);

    chart.setOption({
      backgroundColor: "#fff",
      title: { text: title, left: "center", top: 10 },
      grid: { top: 40, bottom: 30, left: 30, right: 30, containLabel: false },
      tooltip: { trigger: "item" },
      // 锁定坐标轴范围，方便对比
      xAxis: {
        min: -2,
        max: 2,
        axisLine: { onZero: true },
        splitLine: { show: true, lineStyle: { type: "dashed" } },
      },
      yAxis: {
        min: -2,
        max: 2,
        axisLine: { onZero: true },
        splitLine: { show: true, lineStyle: { type: "dashed" } },
      },
      series: [
        {
          type: "scatter",
          symbolSize: 4,
          data: points,
          itemStyle: { color: "rgba(24, 144, 255, 0.6)" },
        },
      ],
    });
    return chart;
  };
  // === 新增算法：计算宽带信号的中心频率 ===
  const calculateCenterFreq = (freqs, powers) => {
    // 1. 找到峰值及其索引
    const maxPower = Math.max(...powers);

    // 2. 设定阈值：选择峰值向下 X dB 的范围
    // 建议设为 10dB ~ 20dB。
    // 为什么要这么深？因为对于 QPSK/GMSK，频谱的“裙边”（斜坡）是非常陡峭且对称的。
    // 包含斜坡数据能极大地“锁住”中心位置，防止在平顶上漂移。
    const threshold = maxPower - 15;

    let sumFreqTimesEnergy = 0;
    let sumEnergy = 0;

    powers.forEach((p_db, i) => {
      // 只计算有效信号范围内的点
      if (p_db > threshold) {
        // === 关键步骤 ===
        // 将 dB (对数) 还原为 线性能量 (Linear Power)
        // 公式：Energy = 10 ^ (dB / 10)
        // 这样高峰值的点权重极大，底噪权重大幅降低，重心非常稳
        const energy = Math.pow(10, p_db / 10);

        sumFreqTimesEnergy += freqs[i] * energy;
        sumEnergy += energy;
      }
    });

    // 防止全黑洞异常
    if (sumEnergy === 0) return freqs[powers.indexOf(maxPower)];

    // 重心公式：Σ(f * E) / ΣE
    return sumFreqTimesEnergy / sumEnergy;
  };
  const renderCharts = (data) => {
    if (!data) return;
    // 1. 画修复前星座：优先显示经过信道后的同步前采样。
    const beforeConstellation = data.constellation_raw || data.constellation_tx;
    if (beforeConstellation) {
      drawConstellation(
        rawConstellationRef,
        data.constellation_raw
          ? "❌ 修复前 (信道损伤)"
          : "📡 发送端星座 (调制后)",
        beforeConstellation,
      );
    }

    // 2. 画修复后的图
    if (data.constellation_synced) {
      drawConstellation(
        syncedConstellationRef,
        "✅ 修复后 (接收机同步)",
        data.constellation_synced,
      );
    }
    // 3. 频谱图（增强版：添加峰值标记线）
    if (spectrumRef.current && data.spectrum) {
      const domSpe = spectrumRef.current;
      let instance = echarts.getInstanceByDom(domSpe);
      if (instance) instance.dispose();

      const chart = echarts.init(domSpe);
      if (chartInstances.current) {
        chartInstances.current.spectrum = chart;
      }

      const { f, p_rx, p_tx } = data.spectrum;

      // === 关键修改：使用新算法计算中心频率 ===
      // 注意：MATLAB传来的 f 是 Hz，p 是 dB
      const rxCenterFreqHz = calculateCenterFreq(f, p_rx);
      const txCenterFreqHz = calculateCenterFreq(f, p_tx);

      // 转单位
      const rxFreqMHz = rxCenterFreqHz / 1e6;
      const txFreqMHz = txCenterFreqHz / 1e6;

      // 计算频偏 (kHz)
      const freqOffset = (rxCenterFreqHz - txCenterFreqHz) / 1e3;

      chart.setOption({
        backgroundColor: "#fff",
        title: {
          text: "功率谱密度 (PSD)",
          // 标题里也显示一下计算结果
          //   subtext: `{label|智能估算频偏}  {value|${Math.abs(freqOffset).toFixed(2)} kHz}  {arrow|${
          //     freqOffset > 0 ? "⮕ (右偏)" : freqOffset < 0 ? "⬅ (左偏)" : "✔"
          //   }}`,
          subtextStyle: {
            rich: {
              label: { color: "#999", fontSize: 12 },
              value: {
                color: "#333",
                fontSize: 14,
                fontWeight: "bold",
                padding: [0, 5],
              },
              arrow: {
                color: Math.abs(freqOffset) > 1 ? "#ff4d4f" : "#52c41a",
                fontWeight: "bold",
              },
            },
          },
          left: "center",
          top: 10,
        },
        tooltip: { trigger: "axis", axisPointer: { type: "cross" } },
        grid: { top: 80, bottom: 80, left: 60, right: 40, containLabel: true },
        dataZoom: [
          {
            type: "slider",
            show: true,
            bottom: 20,
            height: 20,
            borderColor: "transparent",
          },
          { type: "inside" },
        ],
        xAxis: {
          type: "category",
          data: f.map((v) => (v / 1e6).toFixed(3)),
          name: "Freq (MHz)",
          nameLocation: "middle",
          nameGap: 30,
        },
        yAxis: { name: "Power (dB)", type: "value", scale: true },
        series: [
          {
            name: "Rx 接收信号",
            type: "line",
            data: p_rx,
            showSymbol: false,
            smooth: true,
            lineStyle: { width: 2, color: "#ff4d4f" },
            areaStyle: { opacity: 0.1, color: "#ff4d4f" },
            markLine: {
              symbol: ["none", "none"],
              silent: true,
              label: {
                formatter: `Rx中心\n{c} MHz`,
                position: "insideEndTop",
                distance: [0, 10],
                backgroundColor: "rgba(255, 77, 79, 0.9)",
                color: "#fff",
                padding: [4, 8],
                borderRadius: 4,
                shadowBlur: 4,
                shadowColor: "rgba(0,0,0,0.2)",
              },
              lineStyle: { type: "solid", color: "#ff4d4f", width: 2 },
              data: [
                // 注意：这里xAxis必须对应 xAxis data 里的字符串值，或者用 coord 坐标
                // 为了保险，我们找一下最接近的 index
                { xAxis: f.findIndex((val) => val === rxCenterFreqHz) },
              ],
            },
          },
          {
            name: "Tx 参考信号",
            type: "line",
            data: p_tx,
            showSymbol: false,
            smooth: true,
            lineStyle: { width: 2, color: "#52c41a", type: "dashed" },
            areaStyle: { opacity: 0.05, color: "#52c41a" },
            markLine: {
              symbol: ["none", "none"],
              silent: true,
              label: {
                formatter: `Tx中心\n{c} MHz`,
                position: "insideStartTop",
                distance: [0, 10],
                backgroundColor: "rgba(82, 196, 26, 0.9)",
                color: "#fff",
                padding: [4, 8],
                borderRadius: 4,
                shadowBlur: 4,
                shadowColor: "rgba(0,0,0,0.2)",
              },
              lineStyle: { type: "solid", color: "#52c41a", width: 2 },
              data: [{ xAxis: f.findIndex((val) => val === txCenterFreqHz) }],
            },
          },
        ],
        legend: { data: ["Rx 接收信号", "Tx 参考信号"], top: 45, right: 30 },
      });
    }

    // 4. 信道输入/输出功率：只显示后端抽样后的曲线，避免把原始长波形传到浏览器。
    const channelPower = data.channelPower;
    if (channelPower?.time_ms?.length) {
      if (channelPowerRef.current) {
        const old = echarts.getInstanceByDom(channelPowerRef.current);
        if (old) old.dispose();
        const chart = echarts.init(channelPowerRef.current);
        chartInstances.current.channelPower = chart;
        chart.setOption({
          title: { text: "信道输入/输出瞬时功率", left: "center", top: 8 },
          tooltip: { trigger: "axis" },
          grid: { top: 45, bottom: 45, left: 55, right: 25, containLabel: true },
          xAxis: { type: "category", data: channelPower.time_ms.map((v) => Number(v).toFixed(3)), name: "时间 (ms)" },
          yAxis: { type: "value", name: "功率 (dBm)", scale: true },
          legend: { top: 28 },
          series: [
            { name: "信道输入", type: "line", data: channelPower.input_power_dbm, showSymbol: false, smooth: true, lineStyle: { color: "#1677ff" } },
            { name: "信道输出", type: "line", data: channelPower.output_power_dbm, showSymbol: false, smooth: true, lineStyle: { color: "#ff4d4f" } },
          ],
        });
      }
    }
    if (channelPower?.frequency_mhz?.length) {
      const old = channelSpectrumRef.current && echarts.getInstanceByDom(channelSpectrumRef.current);
      if (old) old.dispose();
      if (channelSpectrumRef.current) {
        const chart = echarts.init(channelSpectrumRef.current);
        chartInstances.current.channelSpectrum = chart;
        chart.setOption({
          title: { text: "信道输入/输出 PSD", left: "center", top: 8 },
          tooltip: { trigger: "axis" },
          grid: { top: 45, bottom: 45, left: 55, right: 25, containLabel: true },
          xAxis: { type: "category", data: channelPower.frequency_mhz.map((v) => Number(v).toFixed(3)), name: "频率 (MHz)" },
          yAxis: { type: "value", name: "PSD (dBm/Hz)", scale: true },
          legend: { top: 28 },
          series: [
            { name: "信道输入", type: "line", data: channelPower.input_psd_dbmhz, showSymbol: false, lineStyle: { color: "#1677ff" } },
            { name: "信道输出", type: "line", data: channelPower.output_psd_dbmhz, showSymbol: false, lineStyle: { color: "#ff4d4f" } },
          ],
        });
      }
    }
  };

  const renderEvaluationInsights = () => {
    if (!simResult?.stats) return null;
    const isGMSK = isGMSKResult(simResult);

    return (
      <div className="result-insights">
        <div className="kpi-grid">
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title="BER"
              value={simResult.ber}
              valueStyle={{
                color:
                  simResult.ber === 0
                    ? "#389e0d"
                    : simResult.ber > 0
                      ? "#cf1322"
                      : "#8c8c8c",
              }}
              formatter={(val) => {
                if (val === -1) return "N/A";
                if (val === -2) return "Error";
                if (val === 0) return "0";
                return Number(val).toExponential(2);
              }}
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title={getEvmTitle(simResult)}
              value={getEvmDisplay(simResult.stats)}
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title={getMerTitle(simResult)}
              value={formatMetricValue(simResult.stats.MERdB)}
              suffix="dB"
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title="FER"
              value={getFerDisplay(simResult.stats)}
              valueStyle={{ color: "#1677ff", fontSize: 24 }}
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title="帧匹配率（评估）"
              value={formatMetricValue(simResult.stats.LockRatePercent)}
              suffix="%"
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title="PAPR"
              value={formatMetricValue(simResult.stats.PAPRdB)}
              suffix="dB"
            />
          </Card>
        </div>

        <Card className="evaluation-panel" bordered={false} title="链路评估">
          <Row gutter={[16, 16]}>
            <Col xs={24} xl={10}>
              <Descriptions title="链路质量" size="small" column={1} bordered>
                <Descriptions.Item label="BER">
                  <Tag
                    color={getMetricTone(simResult.ber, {
                      good: 1e-5,
                      warn: 1e-3,
                    })}
                  >
                    {simResult.ber >= 0
                      ? formatMetricValue(simResult.ber)
                      : "N/A"}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label={getEvmTitle(simResult)}>
                  {isFiniteNumber(simResult.stats.EVMPercent) &&
                  simResult.stats.EVMPercent >= 0 ? (
                    <Tag
                      color={getMetricTone(
                        simResult.stats.EVMPercent,
                        EVM_TONE_THRESHOLDS,
                      )}
                    >
                      {formatMetricValue(simResult.stats.EVMPercent)}%
                    </Tag>
                  ) : (
                    <Tag>未启用</Tag>
                  )}
                </Descriptions.Item>
                <Descriptions.Item label={getMerTitle(simResult)}>
                  {formatMetricValue(simResult.stats.MERdB)} dB
                </Descriptions.Item>
                <Descriptions.Item label="FER">
                  <Tag
                    color={getMetricTone(simResult.stats.FER, {
                      good: 0,
                      warn: 0.05,
                    })}
                  >
                    {getFerDisplay(simResult.stats)}
                  </Tag>
                  {isFiniteNumber(simResult.stats.FrameErrors) &&
                  isFiniteNumber(simResult.stats.CountedFrames)
                    ? ` (${simResult.stats.FrameErrors}/${simResult.stats.CountedFrames} 帧)`
                    : ""}
                </Descriptions.Item>
                <Descriptions.Item label="PAPR">
                  {formatMetricValue(simResult.stats.PAPRdB)} dB
                </Descriptions.Item>
                <Descriptions.Item label="实际编码率">
                  {simResult.stats.CodeRate}
                </Descriptions.Item>
                {isFiniteNumber(simResult.stats.ModulatorBitRateBps) && (
                  <Descriptions.Item label="调制码率">
                    {formatMetricValue(
                      simResult.stats.ModulatorBitRateBps / 1e6,
                      3,
                    )}{" "}
                    Mbps
                  </Descriptions.Item>
                )}
                {isFiniteNumber(simResult.stats.SymbolRateHz) && (
                  <Descriptions.Item label="符号率">
                    {formatMetricValue(
                      simResult.stats.SymbolRateHz / 1e6,
                      3,
                    )}{" "}
                    Msym/s
                  </Descriptions.Item>
                )}
                {simResult.stats.PulseShapingFilter && (
                  <Descriptions.Item label="实际成型滤波">
                    {simResult.stats.PulseShapingFilter === "none"
                      ? "旁路（矩形符号保持）"
                      : simResult.stats.PulseShapingFilter === "raised cosine"
                        ? "升余弦（RC）"
                        : "平方根升余弦（RRC）"}
                  </Descriptions.Item>
                )}
                {simResult.stats.ReceivePulseFilterActual && (
                  <Descriptions.Item label="实际接收匹配滤波">
                    {{
                      "rectangular matched filter": "矩形匹配滤波",
                      "raised cosine matched filter": "升余弦匹配滤波（RC）",
                      "root raised cosine matched filter":
                        "平方根升余弦匹配滤波",
                      "modulation-specific receiver front end":
                        "调制专用接收前端",
                    }[simResult.stats.ReceivePulseFilterActual] ||
                      simResult.stats.ReceivePulseFilterActual}
                  </Descriptions.Item>
                )}
                {simResult.stats.ConvolutionalReceiveMode && (
                  <Descriptions.Item label="卷积接收路径">
                    {simResult.stats.ConvolutionalReceiveMode ===
                    "stream-raw-asm"
                      ? "连续 Viterbi → 原始 ASM"
                      : simResult.stats.ConvolutionalReceiveMode}
                  </Descriptions.Item>
                )}
                {isFiniteNumber(simResult.stats.RSMessageLength) &&
                  isFiniteNumber(simResult.stats.RSInterleavingDepth) && (
                    <Descriptions.Item label="实际 RS 配置">
                      {`RS(255,${simResult.stats.RSMessageLength}), I=${simResult.stats.RSInterleavingDepth}, TF=${simResult.stats.RSMessageLength * simResult.stats.RSInterleavingDepth} Byte`}
                    </Descriptions.Item>
                  )}
                {/APSK/i.test(simResult.modType || "") && simResult.stats.APSKReceiverMode && <Descriptions.Item label="APSK 实际接收模式">
                  {simResult.stats.APSKReceiverMode === "pilotless" ? "普通 TM · 无导频" : simResult.stats.APSKReceiverMode}
                </Descriptions.Item>}
                <Descriptions.Item label="实际自适应均衡">
                  {simResult.stats.AdaptiveEqualizerMode || "未报告"}
                </Descriptions.Item>
                <Descriptions.Item label="数据通路">
                  {simResult.stats.DataPathMode === "unequalDualIQ"
                    ? "UQPSK 不等速 I/Q 分路"
                    : simResult.stats.DataPathMode === "dualIQ"
                      ? "I/Q 分路"
                      : "合路（单路 TM）"}
                </Descriptions.Item>
                <Descriptions.Item label="内部数据源">
                  {simResult.stats.TMDataSource === "split"
                    ? `I=${simResult.stats.TMDataSourceI || "random"}, Q=${
                        simResult.stats.TMDataSourceQ || "random"
                      }`
                    : simResult.stats.TMDataSource || "random"}
                </Descriptions.Item>
                <Descriptions.Item label="加扰">
                  {!simResult.stats.RandomizerEnabled
                    ? "关闭"
                    : simResult.stats.RandomizerFECPosition === "beforeEncoding"
                      ? "编码前"
                      : "编码后"}
                </Descriptions.Item>
                <Descriptions.Item label="采样率">
                  {isFiniteNumber(simResult.stats.Fs)
                    ? `${formatMetricValue(simResult.stats.Fs / 1e6)} MHz`
                    : "N/A"}
                </Descriptions.Item>
              </Descriptions>
            </Col>

            <Col xs={24} xl={7}>
              <Descriptions title="输入损伤" size="small" column={1} bordered>
                <Descriptions.Item label="实际噪声模式">
                  {{off:"关闭噪声",psd:"固定 PSD",measuredsnr:"按 SNR 加噪",snr:"按 SNR 加噪"}[simResult.stats.NoiseMode] || simResult.stats.NoiseMode || "未报告（旧结果）"}
                </Descriptions.Item>
                <Descriptions.Item label="输入SNR">
                  {["off","psd"].includes(simResult.stats.NoiseMode)
                    ? "未使用（由实际噪声模式决定）"
                    : `${formatMetricValue(simResult.stats.InputSNR)} dB`}
                </Descriptions.Item>
                <Descriptions.Item label="输入CFO">
                  {formatMetricValue(simResult.stats.InputCFO)} Hz
                </Descriptions.Item>
                <Descriptions.Item label="输入相位">
                  {formatMetricValue(simResult.stats.InputPhase)} deg
                </Descriptions.Item>
                <Descriptions.Item label="输入时延">
                  {formatMetricValue(simResult.stats.InputDelay, 3)} samples
                </Descriptions.Item>
              </Descriptions>
            </Col>

            <Col xs={24} xl={7}>
              <Descriptions title="运行信息" size="small" column={1} bordered>
                <Descriptions.Item label="帧匹配率（评估）">
                  {formatMetricValue(simResult.stats.LockRatePercent)}%
                </Descriptions.Item>
                <Descriptions.Item label="综合当前状态">
                  <Tag
                    color={simResult.stats.LockStatus ? "success" : "warning"}
                  >
                    {formatLockStatus(simResult.stats.LockStatus)}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label="载波锁定">
                  <RuntimeLockIndicator track={simResult.stats.CarrierLock} />
                </Descriptions.Item>
                <Descriptions.Item label="码元锁定">
                  <RuntimeLockIndicator track={simResult.stats.TimingLock} />
                </Descriptions.Item>
                <Descriptions.Item label="帧同步">
                  <RuntimeLockIndicator track={simResult.stats.FrameSyncLock} />
                </Descriptions.Item>
                <Descriptions.Item label="残余CFO">
                  {simResult.stats.ResidCFOValid &&
                  isFiniteNumber(simResult.stats.ResidCFOHz)
                    ? `${formatMetricValue(simResult.stats.ResidCFOHz, 3)} Hz`
                    : "N/A"}
                </Descriptions.Item>
                <Descriptions.Item label="捕获帧数">
                  {isFiniteNumber(simResult.stats.AcquisitionFrames)
                    ? `${formatMetricValue(simResult.stats.AcquisitionFrames, 0)} 帧`
                    : "N/A"}
                </Descriptions.Item>
                <Descriptions.Item label="捕获时间">
                  {isFiniteNumber(simResult.stats.AcquisitionTime)
                    ? `${formatMetricValue(
                        simResult.stats.AcquisitionTime * 1000,
                        3,
                      )} ms`
                    : "N/A"}
                </Descriptions.Item>
                <Descriptions.Item label="AGC">
                  {!simResult.stats.AGCEnabled
                    ? "关闭"
                    : `${formatMetricValue(simResult.stats.AGCTimeConstantMs, 0)} ms`}
                </Descriptions.Item>
                <Descriptions.Item label="MATLAB耗时">
                  {formatMetricValue(simResult.stats.ElapsedTime, 3)} s
                </Descriptions.Item>
                <Descriptions.Item label="结论">
                  {simResult.stats.LockStatus === null
                    ? "锁定遥测未完整观测，不能据此判定失锁"
                    : simResult.stats.LockStatus
                      ? "检测器报告锁定；仍需检查测量覆盖和误码"
                      : "检测器报告未锁定，需结合时间记录检查"}
                </Descriptions.Item>
              </Descriptions>
            </Col>
          </Row>

          <Alert
            className="evaluation-alert"
            type={
              simResult.stats.LockStatus &&
              simResult.stats.MeasurementCoverage?.Complete &&
              isFiniteNumber(simResult.ber) &&
              simResult.ber >= 0 &&
              simResult.ber < 1e-3
                ? "success"
                : "warning"
            }
            showIcon
            message="评估解读"
            description={`${getBerSummary(simResult.ber, simResult.stats.MeasurementCoverage)} ${
              isGMSK
                ? getGMSKEvmSummary()
                : getEvmSummary(simResult.stats.EVMPercent)
            }`}
          />
        </Card>
      </div>
    );
  };

  return (
    <div className="ccsds-platform">
      <Modal title="操作未完成，请确认提示" open={errorNotice !== null}
        centered closable={false} maskClosable={false} keyboard={false}
        footer={<Button type="primary" onClick={() => setErrorNotice(null)}>确认</Button>}>
        <div style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere", maxHeight: "60vh", overflowY: "auto" }}>
          {errorNotice}
        </div>
      </Modal>
      {/* 顶部 Header */}
      <div className="platform-header">
        <div className="title-area">
          <RocketOutlined className="icon" />
          <span className="title">CCSDS 遥测仿真控制台</span>
        </div>
        <div className="status-area">
          <Space size="middle">
            {/* 只有当有结果时，保存按钮才亮起 */}
            <Tooltip title="将当前参数和结果存入数据库">
              <Button
                icon={<SaveOutlined />}
                onClick={handleSave}
                disabled={!simResult}
              >
                保存结果
              </Button>
            </Tooltip>

            <Button icon={<HistoryOutlined />} onClick={openHistory}>
              历史记录
            </Button>

            <Divider type="vertical" />

            {isElectron ? (
              <Tag color="success" icon={<CheckCircleOutlined />}>
                MATLAB Ready
              </Tag>
            ) : (
              <Tag color="orange" icon={<SyncOutlined spin={loading} />}>
                MATLAB HTTP 服务
              </Tag>
            )}
          </Space>
        </div>
      </div>

      <div className="content-wrapper">
        {/* 1. 顶部：参数配置区 */}
        <Card className="config-panel" bordered={false}>
          <Form
            form={form}
            layout="vertical"
            onFinish={runSimulation}
            onFinishFailed={handleFormFinishFailed}
            initialValues={{
              ...DEFAULT_CCSDS_PARAMS,
              rsPreset: "rs-255-223-i5",
              RSMessageLength: 223,
              RSInterleavingDepth: 5,
              IsRSMessageShortened: false,
              RSShortenedMessageLength: 223,
            }}
          >
            <Row gutter={24} align="bottom">
              <Col span={4}>
                <Form.Item
                  name="modType"
                  label={labelWithDefault("调制方式", "modType")}
                  rules={[
                    ...defaultRule("modType"),
                    enumRule(
                      MODULATION_OPTIONS.map((item) => item.value),
                      "调制方式",
                    ),
                  ]}
                >
                  <Select
                    onChange={(value) => {
                      if (!SELECTABLE_PULSE_SHAPING_MODS.includes(value) ||
                          (form.getFieldValue("PulseShapingFilter") === "raised cosine" &&
                           !["OQPSK", "UQPSK"].includes(value))) {
                        form.setFieldValue(
                          "PulseShapingFilter",
                          "root raised cosine",
                        );
                      }
                    }}
                  >
                    {MODULATION_OPTIONS.map((item) => (
                      <Option key={item.value} value={item.value}>
                        {item.label}
                      </Option>
                    ))}
                  </Select>
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item
                  name="modulatorBitRateMbps"
                  label={labelWithDefault(
                    "调制码率 (Mbps)",
                    "modulatorBitRateMbps",
                    "与设备“码率”字段一致，表示进入星座映射的编码后比特率，不是 FEC 编码率",
                  )}
                  rules={fieldRules("modulatorBitRateMbps")}
                >
                  <InputNumber
                    style={{ width: "100%" }}
                    min={0.001}
                    max={5000}
                    step={10}
                    formatter={(v) =>
                      `${v}`.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
                    }
                  />
                </Form.Item>
              </Col>
              <Form.Item
                noStyle
                dependencies={[
                  "modType",
                  "modulatorBitRateMbps",
                  "ModulationEfficiency",
                ]}
              >
                {({ getFieldValue }) => {
                  const bitsPerSymbol = modulationBitsPerSymbol(
                    getFieldValue("modType"),
                    getFieldValue("ModulationEfficiency"),
                  );
                  const bitRateMbps = Number(
                    getFieldValue("modulatorBitRateMbps"),
                  );
                  const symbolRateMsym =
                    Number.isFinite(bitRateMbps) && bitRateMbps > 0
                      ? bitRateMbps / bitsPerSymbol
                      : undefined;
                  return (
                    <Col span={4}>
                      <Form.Item
                        label={
                          <Tooltip
                            title={`自动换算：调制码率 ÷ ${bitsPerSymbol} bit/符号。MATLAB 内部仍使用该符号率完成采样与滤波。`}
                          >
                            <span>
                              对应符号率 (Msym/s){" "}
                              <InfoCircleOutlined
                                style={{ color: "#8c8c8c" }}
                              />
                            </span>
                          </Tooltip>
                        }
                      >
                        <InputNumber
                          value={symbolRateMsym}
                          precision={6}
                          disabled
                          style={{ width: "100%" }}
                        />
                      </Form.Item>
                    </Col>
                  );
                }}
              </Form.Item>
              <Form.Item noStyle dependencies={["noiseMode"]}>
                {({ getFieldValue }) => (
              <Col span={3}>
                <Form.Item
                  name="snr"
                  label={labelWithDefault("信噪比 (SNR)", "snr")}
                  rules={fieldRules("snr")}
                >
                  <InputNumber disabled={getFieldValue("noiseMode") !== "snr"} min={-20} max={100} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
                )}
              </Form.Item>
              <Col span={3}>
                <Form.Item
                  name="sps"
                  label={labelWithDefault("采样/符号 (SPS)", "sps")}
                  rules={fieldRules("sps", { integer: true })}
                >
                  <InputNumber min={2} max={64} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              {/* === 动态渲染：调制参数联动区 === */}
              <Form.Item
                noStyle
                dependencies={["modType", "PulseShapingFilter"]}
              >
                {({ getFieldValue }) => {
                  const mod = getFieldValue("modType");
                  const supportsPulseShapeChoice =
                    SELECTABLE_PULSE_SHAPING_MODS.includes(mod);
                  const pulseShape =
                    getFieldValue("PulseShapingFilter") ||
                    DEFAULT_CCSDS_PARAMS.PulseShapingFilter;
                  const pulseShapeBypassed = pulseShape === "none";

                  // APSK 统一走 ordinary TM，不再向用户暴露 FACM/ACMFormat。
                  if (mod === "4D-8PSK-TCM") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="ModulationEfficiency"
                          label="调制效率"
                          initialValue={2.0}
                          rules={[enumRule([2.0, 2.25, 2.5, 2.75], "调制效率")]}
                        >
                          <Select>
                            <Option value={2.0}>2.0</Option>
                            <Option value={2.25}>2.25</Option>
                            <Option value={2.5}>2.5</Option>
                            <Option value={2.75}>2.75</Option>
                          </Select>
                        </Form.Item>
                      </Col>
                    );
                  }
                  // 3. GMSK
                  else if (mod === "GMSK") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="BandwidthTimeProduct"
                          label={labelWithDefault(
                            "BT 值 (GMSK)",
                            "BandwidthTimeProduct",
                          )}
                          initialValue={0.5}
                          rules={fieldRules("BandwidthTimeProduct")}
                        >
                          <Select>
                            <Option value={0.25}>0.25</Option>
                            <Option value={0.5}>0.5</Option>
                          </Select>
                        </Form.Item>
                      </Col>
                    );
                  }
                  else if (mod === "MSK") {
                    return <Col span={6}><Alert type="info" showIcon title="MSK：连续相位调制，不使用 RRC 滚降和滤波长度参数。" /></Col>;
                  }
                  // 4. FM
                  else if (mod === "FM") {
                    return (
                      <>
                        <Col span={3}>
                          <Form.Item
                            name="RolloffFactor"
                            label={labelWithDefault(
                              "滚降系数 (α)",
                              "RolloffFactor",
                            )}
                            rules={fieldRules("RolloffFactor")}
                          >
                            <InputNumber
                              step={0.05}
                              min={0.1}
                              max={1.0}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                        <Col span={3}>
                          <Form.Item
                            name="TZZS"
                            label={labelWithDefault("FM 调制指数", "TZZS")}
                            rules={fieldRules("TZZS")}
                          >
                            <InputNumber
                              step={0.01}
                              min={0.1}
                              max={2}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                      </>
                    );
                  }
                  // 4. PCM/PSK/PM (子载波调制)
                  else if (mod === "PCM/PSK/PM") {
                    return (
                      <>
                        <Col span={3}>
                          <Form.Item
                            name="ModulationIndex"
                            label={labelWithDefault(
                              "调制指数 (Rad)",
                              "ModulationIndex",
                            )}
                            initialValue={1.0}
                            rules={fieldRules("ModulationIndex")}
                          >
                            <InputNumber
                              step={0.1}
                              min={0.1}
                              max={1.5}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                        <Col span={3}>
                          <Form.Item
                            name="SubcarrierWaveform"
                            label={labelWithDefault(
                              "副载波波形",
                              "SubcarrierWaveform",
                            )}
                            initialValue="sine"
                            rules={[
                              ...defaultRule("SubcarrierWaveform"),
                              enumRule(["sine", "square"], "副载波波形"),
                            ]}
                          >
                            <Select>
                              <Option value="sine">正弦波</Option>
                              <Option value="square">方波</Option>
                            </Select>
                          </Form.Item>
                        </Col>
                      </>
                    );
                  }
                  // 5. 普通线性调制开放 RRC/旁路；专用前端保持自身波形逻辑。
                  else {
                    return (
                      <>
                        {supportsPulseShapeChoice && (
                          <Col span={4}>
                            <Form.Item
                              name="PulseShapingFilter"
                              extra={getFieldValue("PulseShapingFilter") === "raised cosine"
                                ? "RC 使用 RC 接收匹配滤波，级联仍有残余 ISI；UQPSK 部分帧长尚未通过无噪声回归，默认建议保留 RRC。"
                                : undefined}
                              label={labelWithDefault(
                                "成型滤波",
                                "PulseShapingFilter",
                                "旁路不使用带限成型；离散仿真以 SPS 点矩形保持表示符号，接收端使用对应矩形匹配滤波",
                              )}
                              rules={[
                                ...defaultRule("PulseShapingFilter"),
                                enumRule(
                                  ["root raised cosine", "none", ...(["OQPSK", "UQPSK"].includes(mod) ? ["raised cosine"] : [])],
                                  "成型滤波",
                                ),
                              ]}
                            >
                              <Select>
                                <Option value="root raised cosine">
                                  平方根升余弦（RRC）
                                </Option>
                                {["OQPSK", "UQPSK"].includes(mod) && (
                                  <Option value="raised cosine">升余弦（RC，待验证）</Option>
                                )}
                                <Option value="none">旁路（不成形）</Option>
                              </Select>
                            </Form.Item>
                          </Col>
                        )}
                        <Col span={3}>
                          <Form.Item
                            name="RolloffFactor"
                            label={labelWithDefault(
                              "滚降系数 (α)",
                              "RolloffFactor",
                            )}
                            // initialValue={0.35}
                            rules={fieldRules("RolloffFactor")}
                          >
                            <InputNumber
                              disabled={
                                supportsPulseShapeChoice && pulseShapeBypassed
                              }
                              step={0.05}
                              min={0.1}
                              max={1.0}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>

                        <Col span={3}>
                          <Form.Item
                            name="FilterSpanInSymbols"
                            label={labelWithDefault(
                              "滤波器长度 (符号)",
                              "FilterSpanInSymbols",
                            )}
                            initialValue={10}
                            rules={fieldRules("FilterSpanInSymbols", {
                              integer: true,
                            })}
                          >
                            <InputNumber
                              disabled={
                                supportsPulseShapeChoice && pulseShapeBypassed
                              }
                              min={4}
                              max={64}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                      </>
                    );
                  }
                }}
              </Form.Item>
            </Row>

            <Row gutter={16} align="bottom">
              <Col span={5}>
                <Form.Item
                  name="channelCoding"
                  label={labelWithDefault("信道编码", "channelCoding")}
                  rules={[
                    ...defaultRule("channelCoding"),
                    enumRule(
                      CHANNEL_CODING_OPTIONS.map((item) => item.value),
                      "信道编码",
                    ),
                  ]}
                >
                  <Select
                    onChange={(value) => {
                      // Block length and rate belong to the coding family.
                      form.setFieldsValue(codingDefaults(value));
                    }}
                  >
                    {CHANNEL_CODING_OPTIONS.map((item) => (
                      <Option key={item.value} value={item.value}>
                        {item.label}
                      </Option>
                    ))}
                  </Select>
                </Form.Item>
              </Col>
              <Form.Item noStyle dependencies={["modType"]}>
                {({ getFieldValue }) => {
                  const mod = getFieldValue("modType");
                  if (!MODES_WITH_PCM_FORMAT.includes(mod)) return null;
                  return (
                    <Col span={3}>
                      <Form.Item
                        name="PCMFormat"
                        label={labelWithDefault("PCM码型", "PCMFormat")}
                        rules={[
                          ...defaultRule("PCMFormat"),
                          enumRule(PCM_FORMAT_OPTIONS, "PCM码型"),
                        ]}
                      >
                        <Select>
                          {PCM_FORMAT_OPTIONS.map((fmt) => (
                            <Option key={fmt} value={fmt}>
                              {fmt}
                            </Option>
                          ))}
                        </Select>
                      </Form.Item>
                    </Col>
                  );
                }}
              </Form.Item>
              <Col span={3}>
                <Form.Item
                  label={labelWithDefault("频偏 (Hz)", "cfo")}
                  name="cfo"
                  initialValue={0}
                  rules={fieldRules("cfo")}
                >
                  <InputNumber style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item
                  name="phaseOffset"
                  label={labelWithDefault("相位偏移 (°)", "phaseOffset")}
                  rules={fieldRules("phaseOffset")}
                >
                  <InputNumber min={-360} max={360} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item
                  label={labelWithDefault(
                    "定时偏差 (Samples)",
                    "delay",
                    "允许范围为 ±SPS 个采样点",
                  )}
                  name="delay"
                  dependencies={["sps"]}
                  initialValue={0}
                  rules={[...defaultRule("delay"), delayBySpsRule]}
                >
                  <InputNumber step={0.1} style={{ width: "100%" }} />
                </Form.Item>
              </Col>

              <Form.Item
                noStyle
                dependencies={[
                  "channelCoding",
                  "NumBitsInInformationBlock",
                  "CodeRate",
                ]}
              >
                {({ getFieldValue }) => {
                  const coding = getFieldValue("channelCoding");
                  const ldpcK = Number(
                    getFieldValue("NumBitsInInformationBlock") ?? 1024,
                  );
                  const showConvRate =
                    coding === "convolutional" || coding === "concatenated";
                  const showRS = coding === "RS" || coding === "concatenated";
                  const isApplicable = coding === "Turbo" || coding === "LDPC";
                  const showTPCRate = coding === "TPC";

                  // 分别计算各自的默认值和选项
                  let convDefaultRate = "5/6";
                  let convRateOptions = CONVOLUTIONAL_RATES;

                  let turboLdpcDefaultRate = "N/A";
                  let turboLdpcRateOptions = ["N/A"];

                  if (coding === "Turbo") {
                    turboLdpcRateOptions = TURBO_RATES;
                    turboLdpcDefaultRate = "1/2";
                  } else if (coding === "LDPC") {
                    turboLdpcRateOptions =
                      ldpcK === 7136 ? ["7/8"] : LDPC_RATES;
                    turboLdpcDefaultRate = ldpcK === 7136 ? "7/8" : "1/2";
                  }

                  return (
                    <>
                      {["none", "convolutional"].includes(coding) && (
                        <Col span={4}>
                          <Form.Item name="NumBytesInTransferFrame" label="信息帧长度 (Byte)"
                            rules={fieldRules("NumBytesInTransferFrame", {integer:true})}>
                            <InputNumber min={6} max={65535} precision={0} style={{width:"100%"}} />
                          </Form.Item>
                        </Col>
                      )}
                      {/* A. 卷积码率 */}
                      {showConvRate && (
                        <Col span={4}>
                          <Form.Item
                            name="ConvolutionalCodeRate"
                            label="卷积码率"
                            extra={coding === "concatenated" ? "内码默认 1/2；高码率还须满足 RS 编码后帧长的打孔周期。" : undefined}
                            initialValue={convDefaultRate}
                            rules={[enumRule(convRateOptions, "卷积码率")]}
                          >
                            <Select>
                              {convRateOptions.map((rate) => (
                                <Option key={rate} value={rate}>
                                  {rate}
                                </Option>
                              ))}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}

                      {/* B. RS 交织深度 */}
                      {/* {showConvRate && (
                        <Col span={4}>
                          <Form.Item
                            name="NumBytesInTransferFrame"
                            label="Transfer Frame Bytes"
                            initialValue={1151}
                          >
                            <InputNumber
                              min={1}
                              max={65535}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                      )} */}

                      {/* {showFrameLength && (
                        <Col span={4}>
                          <Form.Item
                            name="NumBytesInTransferFrame"
                            label="Transfer Frame Bytes"
                            initialValue={1151}
                          >
                            <InputNumber
                              min={1}
                              max={65535}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                      )} */}

                      {showRS && (
                        <Col span={5}>
                          <Form.Item
                            name="rsPreset"
                            label="RS 配置"
                            initialValue="rs-255-223-i5"
                            rules={[
                              enumRule(Object.keys(RS_PRESETS), "RS 配置"),
                            ]}
                          >
                            <Select
                              onChange={(key) => {
                                const preset = RS_PRESETS[key];
                                if (preset) {
                                  form.setFieldsValue({
                                    RSMessageLength: preset.RSMessageLength,
                                    RSInterleavingDepth:
                                      preset.RSInterleavingDepth,
                                    IsRSMessageShortened:
                                      preset.IsRSMessageShortened,
                                    NumBytesInTransferFrame:
                                      preset.NumBytesInTransferFrame,
                                  });
                                }
                              }}
                            >
                              {Object.entries(RS_PRESETS).map(
                                ([key, preset]) => (
                                  <Option key={key} value={key}>
                                    {preset.label}
                                  </Option>
                                ),
                              )}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}

                      {/* C. Turbo/LDPC 码率 */}

                      {coding === "LDPC" && (
                        <Col span={4}>
                          <Form.Item
                            name="NumBitsInInformationBlock"
                            label="LDPC k"
                            initialValue={1024}
                            rules={[
                              enumRule(LDPC_INFO_BLOCKS, "LDPC 信息块长度"),
                            ]}
                          >
                            <Select
                              onChange={(k) => {
                                form.setFieldsValue({
                                  CodeRate: Number(k) === 7136 ? "7/8" : "1/2",
                                });
                              }}
                            >
                              {LDPC_INFO_BLOCKS.map((k) => (
                                <Option key={k} value={k}>
                                  {k} bits
                                </Option>
                              ))}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}

                      {coding === "Turbo" && (
                        <Col span={4}>
                          <Form.Item name="NumBitsInInformationBlock" label="Turbo K (bit)"
                            rules={[enumRule(TURBO_BLOCKS, "Turbo 信息块长度")]}>
                            <Select options={TURBO_BLOCKS.map(value => ({value, label: `${value} bits`}))} />
                          </Form.Item>
                        </Col>
                      )}

                      {isApplicable && (
                        <Col span={4}>
                          <Form.Item
                            name="CodeRate"
                            label="Turbo/LDPC 码率"
                            key={coding}
                            initialValue={turboLdpcDefaultRate}
                            rules={[
                              enumRule(turboLdpcRateOptions, "Turbo/LDPC 码率"),
                            ]}
                          >
                            <Select>
                              {turboLdpcRateOptions.map((rate) => (
                                <Option key={rate} value={rate}>
                                  {rate}
                                </Option>
                              ))}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}

                      {showTPCRate && (
                        <Col span={4}>
                          <Form.Item
                            name="TPCCodeRate"
                            label="TPC码率"
                            initialValue="2/3"
                            rules={[enumRule(TPC_RATES, "TPC码率")]}
                          >
                            <Select
                              onChange={(rate) =>
                                form.setFieldsValue({
                                  TPCBlocksPerTF: rate === "1/2" ? 8 : 4,
                                })
                              }
                            >
                              {TPC_RATES.map((rate) => (
                                <Option key={rate} value={rate}>
                                  {rate}
                                </Option>
                              ))}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}
                    </>
                  );
                }}
              </Form.Item>
            </Row>
            <Row gutter={16}>
              <Col span={6}>
                <Form.Item
                  name="RandomizerMode"
                  label="加扰方式"
                  initialValue="off"
                  rules={[enumRule(["off", "beforeEncoding", "afterEncoding"], "加扰方式")]}
                >
                  <Select>
                    <Option value="off">关闭</Option>
                    <Option value="beforeEncoding">编码前加扰</Option>
                    <Option value="afterEncoding">编码后加扰</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={6}>
                <Form.Item
                  name="AGCMode"
                  label="AGC时间常数"
                  initialValue="off"
                  rules={[enumRule(["off", "1", "10", "100", "1000"], "AGC时间常数")]}
                >
                  <Select>
                    <Option value="off">关闭</Option>
                    <Option value="1">1 ms</Option>
                    <Option value="10">10 ms</Option>
                    <Option value="100">100 ms</Option>
                    <Option value="1000">1000 ms</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={6}>
                <Form.Item name="hasASM" valuePropName="checked" initialValue={true}>
                  <Checkbox>插入同步头 (ASM)</Checkbox>
                </Form.Item>
              </Col>
            </Row>
            <Row gutter={16}>
              <Col span={8}>
                <Form.Item
                  name="DataPathMode"
                  label="数据通路"
                  initialValue="single"
                >
                  <Select>
                    <Option value="single">合路（共用一条 TM 帧）</Option>
                    <Option value="dualIQ">分路（I/Q 各自一条 TM 帧）</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Form.Item noStyle dependencies={["DataPathMode"]}>
                {({ getFieldValue }) => {
                  const split = getFieldValue("DataPathMode") === "dualIQ";
                  if (split) {
                    return (
                      <>
                        <Col span={8}>
                          <Form.Item
                            name="TMDataSourceI"
                            label="I路内部数据"
                            initialValue="random"
                            rules={[
                              enumRule(
                                TM_DATA_SOURCE_OPTIONS.map((item) => item.value),
                                "I路内部数据",
                              ),
                            ]}
                          >
                            <Select options={TM_DATA_SOURCE_OPTIONS} />
                          </Form.Item>
                        </Col>
                        <Col span={8}>
                          <Form.Item
                            name="TMDataSourceQ"
                            label="Q路内部数据"
                            initialValue="random"
                            rules={[
                              enumRule(
                                TM_DATA_SOURCE_OPTIONS.map((item) => item.value),
                                "Q路内部数据",
                              ),
                            ]}
                          >
                            <Select options={TM_DATA_SOURCE_OPTIONS} />
                          </Form.Item>
                        </Col>
                      </>
                    );
                  }
                  return (
                    <Col span={8}>
                      <Form.Item
                        name="TMDataSource"
                        label="内部数据"
                        initialValue="random"
                        rules={[
                          enumRule(
                            TM_DATA_SOURCE_OPTIONS.map((item) => item.value),
                            "内部数据",
                          ),
                        ]}
                      >
                        <Select options={TM_DATA_SOURCE_OPTIONS} />
                      </Form.Item>
                    </Col>
                  );
                }}
              </Form.Item>
            </Row>
            <Form.Item
              noStyle
              dependencies={[
                "DataPathMode",
                "TMDataSource",
                "TMDataSourceI",
                "TMDataSourceQ",
              ]}
            >
              {({ getFieldValue }) => {
                const split = getFieldValue("DataPathMode") === "dualIQ";
                const sources = split
                  ? [
                      getFieldValue("TMDataSourceI"),
                      getFieldValue("TMDataSourceQ"),
                    ]
                  : [getFieldValue("TMDataSource")];
                const usesFixed = sources.includes("fixed");
                const usesIncrementing = sources.includes("incrementing");
                if (!usesFixed && !usesIncrementing) return null;
                return (
                  <Row gutter={16}>
                    {usesFixed && (
                      <Col span={6}>
                        <Form.Item
                          name="TMDataSourceFixedPattern"
                          label="固定码字节"
                          initialValue={85}
                          extra="十进制 0~255；85 即 0x55"
                        >
                          <InputNumber min={0} max={255} precision={0} />
                        </Form.Item>
                      </Col>
                    )}
                    {usesIncrementing && (
                      <Col span={6}>
                        <Form.Item
                          name="TMDataSourceIncrementStart"
                          label="递增码起始字节"
                          initialValue={0}
                        >
                          <InputNumber min={0} max={255} precision={0} />
                        </Form.Item>
                      </Col>
                    )}
                  </Row>
                );
              }}
            </Form.Item>
            <Row gutter={16}>
              <Col span={10}>
                <Form.Item
                  name="channelModel"
                  label={labelWithDefault("信道模型", "channelModel", "可选择内置信道或上传 MAT 文件")}
                  rules={defaultRule("channelModel")}
                >
                  <Select>
                    <Option value="none">无 H 信道</Option>
                    <Option value="synthetic_medium">内置中等多径</Option>
                    <Option value="synthetic_strong">内置强多径</Option>
                    {channelModels.map((model) => (
                      <Option key={model.id} value={model.id} disabled={!model.available}>
                        {model.label}{model.available ? "" : "（文件不存在）"}
                      </Option>
                    ))}
                    {uploadedChannelModels.length > 0 && (
                      <Option value="upload-sequence">
                        自定义快照序列（{uploadedChannelModels.length} 个）
                      </Option>
                    )}
                    {uploadedChannelModels.map((model) => (
                      <Option key={model.id} value={model.id}>
                        单个快照：{model.label}
                      </Option>
                    ))}
                  </Select>
                </Form.Item>
              </Col>
              <Col span={5}>
                <Form.Item label="自定义信道" extra="多文件须为同一天线、按末尾 _1、_2…编号的连续快照">
                  <Upload accept=".mat" multiple showUploadList={false} customRequest={handleChannelUpload}>
                    <Button icon={<UploadOutlined />}>上传 MAT 快照</Button>
                  </Upload>
                </Form.Item>
              </Col>
              <Col span={5}>
                <Form.Item
                  name="enableEqualizer"
                  valuePropName="checked"
                  label=" "
                >
                  <Checkbox>开启自适应均衡（非已知 H）</Checkbox>
                </Form.Item>
              </Col>
            </Row>
            <Row gutter={16}>
              <Col span={5}>
                <Form.Item name="noiseMode" label="噪声模式">
                  <Select options={[{value:"snr",label:"SNR（接收功率为参考）"},{value:"psd",label:"固定噪声 PSD"},{value:"off",label:"关闭噪声"}]} />
                </Form.Item>
              </Col>
              <Form.Item noStyle dependencies={["noiseMode"]}>
                {({getFieldValue}) => <Col span={5}>
                  <Form.Item name="noisePSDdBmHz" label="噪声 PSD (dBm/Hz)" extra="仅固定 PSD 模式生效；此时 SNR 输入不参与加噪。">
                    <InputNumber disabled={getFieldValue("noiseMode") !== "psd"} style={{width:"100%"}} />
                  </Form.Item>
                </Col>}
              </Form.Item>
              <Col span={4}>
                <Form.Item name="berWarmUpFrames" label="预热帧数（不计 BER）">
                  <InputNumber min={0} precision={0} style={{width:"100%"}} />
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item name="berFrames" label="测量帧数">
                  <InputNumber min={1} precision={0} style={{width:"100%"}} />
                </Form.Item>
              </Col>
              <Col span={6}>
                <Form.Item name="adaptiveEqualizerSamplingMode" label="自适应均衡结构" extra="通用 PSK/QAM 分支；APSK、CPM、OQPSK/UQPSK 保留专用前端。">
                  <Select options={[{value:"1sps",label:"1 sps CMA/LMS"},{value:"2sps",label:"2 sps CMA"},{value:"2sps-dual",label:"2 sps 同抽头双模（实验）"}]} />
                </Form.Item>
              </Col>
            </Row>
            <Form.Item noStyle shouldUpdate={(prev, cur) => prev.channelModel !== cur.channelModel}>
              {({ getFieldValue }) => {
                const selected = getFieldValue("channelModel");
                if (!selected || selected === "none" || selected.startsWith("synthetic_")) {
                  return null;
                }
                return (
                  <Row gutter={16}>
                    <Col span={6}>
                      <Form.Item
                        name="channelSampleRateHz"
                        label="H 采样率 (Hz)"
                        extra="新信道当前为 100000；以后优先读取 MAT 元数据"
                      >
                        <InputNumber min={1} precision={0} style={{ width: "100%" }} />
                      </Form.Item>
                    </Col>
                    <Col span={8}>
                      <Form.Item name="normalizeHChannel" valuePropName="checked" label="H 增益处理"
                        extra="关闭保留 MAT 原始平均增益；与归一化 sweep 对比时请开启。">
                        <Checkbox>归一化 H 平均功率</Checkbox>
                      </Form.Item>
                    </Col>
                  </Row>
                );
              }}
            </Form.Item>
            <Row gutter={16} align="bottom">
              <Col span={8} offset={8}>
                <Form.Item label=" ">
                  <div style={{ display: "flex", gap: 8 }}>
                    <Button size="large" onClick={fillDefaultParams}>
                      默认参数
                    </Button>
                    <Button
                      type="primary"
                      htmlType="submit"
                      loading={loading}
                      icon={<GatewayOutlined />}
                      size="large"
                      style={{ flex: 1 }}
                    >
                      {loading ? taskStatusText || "计算中..." : "开始仿真"}
                    </Button>
                    <Button
                      danger
                      icon={<StopOutlined />}
                      size="large"
                      disabled={!currentTaskId}
                      onClick={stopCurrentTask}
                    >
                      停止任务
                    </Button>
                  </div>
                </Form.Item>
              </Col>
            </Row>
          </Form>
        </Card>

        {/* 2. 底部：图表展示区 */}
        <div style={{ margin: "16px 0" }}>
          <Button
            icon={<RadarChartOutlined />}
            href={`#/receiver-monitor${currentTaskId || simResult?.taskId ? `?task=${encodeURIComponent(currentTaskId || simResult.taskId)}` : ""}`}
            target="_blank"
            rel="noopener noreferrer"
          >
            打开接收监控（任务进度 / 锁定与误码时间线）
          </Button>
        </div>
        <div className="charts-row">
          {simResult?.stats?.MeasurementCoverage?.Available && !simResult.stats.MeasurementCoverage.Complete && (
            <Alert type="warning" showIcon title="测量覆盖不足，BER 仅代表已比较部分"
              description={`已比较 ${simResult.stats.MeasurementCoverage.ComparedFrames} / ${simResult.stats.MeasurementCoverage.ExpectedFrames} 个测量帧。请打开接收监控查看未恢复或未比较记录；不能用 BER=0 判定整段无误码。`}
              style={{marginBottom:16}} />
          )}
          {/* 第一行：远控图片模式显示时域和星座；完整数据模式保留原 ECharts。 */}
          <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
            <Col span={12}>
              <Card
                title={
                  <>
                    <RadarChartOutlined /> {hasRemoteImages ? "时域功率" : "修复前 (Before)"}
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {simResult?.images?.time ? (
                    <img
                      src={simResult.images.time}
                      alt="时域功率"
                      className="result-image"
                    />
                  ) : (
                    <div ref={rawConstellationRef} className="chart-box" />
                  )}
                </div>
              </Card>
            </Col>

            <Col span={12}>
              <Card
                title={
                  <>
                    <RadarChartOutlined /> {hasRemoteImages ? "星座图" : "修复后 (After)"}
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {simResult?.images?.constellation ? (
                    <img
                      src={simResult.images.constellation}
                      alt="星座图"
                      className="result-image"
                    />
                  ) : (
                    <div ref={syncedConstellationRef} className="chart-box" />
                  )}
                </div>
                <p style={{color:"#596579",marginTop:12}}>
                  {constellationExplanation(simResult?.modType || simResult?.params?.modType)}
                </p>
              </Card>
            </Col>
          </Row>

          {/* 第二行：信道功率轨迹 */}
          {!hasRemoteImages && (
            <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
              <Col span={12}>
                <Card title="信道输入/输出瞬时功率" bordered={false}>
                  <div className="rect-container" style={{ height: 300 }}>
                    <div ref={channelPowerRef} className="chart-box" />
                  </div>
                </Card>
              </Col>
              <Col span={12}>
                <Card title="信道输入/输出 PSD" bordered={false}>
                  <div className="rect-container" style={{ height: 300 }}>
                    <div ref={channelSpectrumRef} className="chart-box" />
                  </div>
                </Card>
              </Col>
            </Row>
          )}

          {/* 第三行：频谱图 + 统计 (占满整行 24/24) */}
          <Row gutter={[16, 16]}>
            <Col span={24}>
              <Card
                title={
                  <>
                    <BarChartOutlined /> 功率谱密度 (PSD)
                  </>
                }
                bordered={false}
              >
                <div className="rect-container" style={{ height: 350 }}>
                  {simResult?.images?.spectrum ? (
                    <img
                      src={simResult.images.spectrum}
                      alt="功率谱密度"
                      className="result-image"
                    />
                  ) : (
                    <div ref={spectrumRef} className="chart-box" />
                  )}
                </div>

                {simResult &&
                  simResult.stats &&
                  (simResult.rawEvaluation ? (
                    renderEvaluationInsights()
                  ) : (
                    <div className="result-insights">
                      <div className="kpi-grid">
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="BER"
                            value={simResult.ber}
                            valueStyle={{
                              color:
                                simResult.ber === 0
                                  ? "#389e0d"
                                  : simResult.ber > 0
                                    ? "#cf1322"
                                    : "#8c8c8c",
                            }}
                            formatter={(val) => {
                              if (val === -1) return "N/A";
                              if (val === -2) return "Error";
                              if (val === 0) return "0";
                              return Number(val).toExponential(2);
                            }}
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="EVM"
                            value={getEvmDisplay(simResult.stats)}
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="MER"
                            value={formatMetricValue(simResult.stats.MERdB)}
                            suffix="dB"
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="FER"
                            value={getFerDisplay(simResult.stats)}
                            valueStyle={{
                              color: "#1677ff",
                              fontSize: 24,
                            }}
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="帧匹配率（评估）"
                            value={formatMetricValue(
                              simResult.stats.LockRatePercent,
                            )}
                            suffix="%"
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="PAPR"
                            value={formatMetricValue(simResult.stats.PAPRdB)}
                            suffix="dB"
                          />
                        </Card>
                      </div>

                      <Card
                        className="evaluation-panel"
                        bordered={false}
                        title="链路评估"
                      >
                        <Row gutter={[16, 16]}>
                          <Col xs={24} xl={10}>
                            <Descriptions
                              title="链路质量"
                              size="small"
                              column={1}
                              bordered
                            >
                              <Descriptions.Item label="BER">
                                <Tag
                                  color={getMetricTone(simResult.ber, {
                                    good: 1e-5,
                                    warn: 1e-3,
                                  })}
                                >
                                  {simResult.ber >= 0
                                    ? formatMetricValue(simResult.ber)
                                    : "N/A"}
                                </Tag>
                              </Descriptions.Item>
                              <Descriptions.Item label="FER">
                                <Tag
                                  color={getMetricTone(simResult.stats.FER, {
                                    good: 0,
                                    warn: 0.05,
                                  })}
                                >
                                  {getFerDisplay(simResult.stats)}
                                </Tag>
                              </Descriptions.Item>
                              <Descriptions.Item label="MER">
                                {formatMetricValue(simResult.stats.MERdB)} dB
                              </Descriptions.Item>
                              <Descriptions.Item label="EVM">
                                {isFiniteNumber(simResult.stats.EVMPercent) &&
                                simResult.stats.EVMPercent >= 0 ? (
                                  <Tag
                                    color={getMetricTone(
                                      simResult.stats.EVMPercent,
                                      EVM_TONE_THRESHOLDS,
                                    )}
                                  >
                                    {formatMetricValue(
                                      simResult.stats.EVMPercent,
                                    )}
                                    %
                                  </Tag>
                                ) : (
                                  <Tag>未启用</Tag>
                                )}
                              </Descriptions.Item>
                              <Descriptions.Item label="实际编码率">
                                {simResult.stats.CodeRate}
                              </Descriptions.Item>
                              {isFiniteNumber(
                                simResult.stats.ModulatorBitRateBps,
                              ) && (
                                <Descriptions.Item label="调制码率">
                                  {formatMetricValue(
                                    simResult.stats.ModulatorBitRateBps / 1e6,
                                    3,
                                  )}{" "}
                                  Mbps
                                </Descriptions.Item>
                              )}
                              {isFiniteNumber(
                                simResult.stats.SymbolRateHz,
                              ) && (
                                <Descriptions.Item label="符号率">
                                  {formatMetricValue(
                                    simResult.stats.SymbolRateHz / 1e6,
                                    3,
                                  )}{" "}
                                  Msym/s
                                </Descriptions.Item>
                              )}
                              <Descriptions.Item label="MATLAB耗时">
                                {formatMetricValue(
                                  simResult.stats.ElapsedTime,
                                  3,
                                )}{" "}
                                s
                              </Descriptions.Item>
                            </Descriptions>
                          </Col>

                          <Col xs={24} xl={7}>
                            <Descriptions
                              title="同步状态"
                              size="small"
                              column={1}
                              bordered
                            >
                              <Descriptions.Item label="综合当前状态">
                                <Tag
                                  color={
                                    simResult.stats.LockStatus
                                      ? "success"
                                      : "error"
                                  }
                                >
                                  {formatLockStatus(simResult.stats.LockStatus)}
                                </Tag>
                              </Descriptions.Item>
                              <Descriptions.Item label="载波锁定">
                                <RuntimeLockIndicator
                                  track={simResult.stats.CarrierLock}
                                />
                              </Descriptions.Item>
                              <Descriptions.Item label="码元锁定">
                                <RuntimeLockIndicator
                                  track={simResult.stats.TimingLock}
                                />
                              </Descriptions.Item>
                              <Descriptions.Item label="帧同步">
                                <RuntimeLockIndicator
                                  track={simResult.stats.FrameSyncLock}
                                />
                              </Descriptions.Item>
                              <Descriptions.Item label="残余CFO">
                                {simResult.stats.ResidCFOValid &&
                                isFiniteNumber(simResult.stats.ResidCFOHz)
                                  ? `${formatMetricValue(
                                      simResult.stats.ResidCFOHz,
                                      3,
                                    )} Hz`
                                  : "N/A"}
                              </Descriptions.Item>
                              <Descriptions.Item label="捕获帧数">
                                {isFiniteNumber(
                                  simResult.stats.AcquisitionFrames,
                                )
                                  ? `${formatMetricValue(
                                      simResult.stats.AcquisitionFrames,
                                      0,
                                    )} 帧`
                                  : "N/A"}
                              </Descriptions.Item>
                              <Descriptions.Item label="建议观察">
                                {simResult.stats.LockStatus
                                  ? "优先结合 EVM 与 BER 看损伤强度"
                                  : "优先检查 CFO、延时和 SNR 是否过重"}
                              </Descriptions.Item>
                            </Descriptions>
                          </Col>

                          <Col xs={24} xl={7}>
                            <Descriptions
                              title="帧统计"
                              size="small"
                              column={1}
                              bordered
                            >
                              <Descriptions.Item label="对比帧数">
                                {simResult.stats.CountedFrames ??
                                  simResult.stats.ComparedFrames ??
                                  0}
                              </Descriptions.Item>
                              <Descriptions.Item label="出错帧数">
                                {simResult.stats.FrameErrors ?? 0}
                              </Descriptions.Item>
                              {isFiniteNumber(simResult.stats.ChannelSnapshotCount) && (
                                <Descriptions.Item label="H 快照数">
                                  {simResult.stats.ChannelSnapshotCount}
                                </Descriptions.Item>
                              )}
                              {simResult.stats.ChannelSequenceContinuity && (
                                <Descriptions.Item label="H 时间连续性">
                                  {simResult.stats.ChannelSequenceContinuity}
                                </Descriptions.Item>
                              )}
                              <Descriptions.Item label="结论">
                                {(simResult.stats.CountedFrames ??
                                  simResult.stats.ComparedFrames ??
                                  0) > 0
                                  ? "已有足够样本可用于链路对比"
                                  : "当前没有有效帧，指标参考意义有限"}
                              </Descriptions.Item>
                            </Descriptions>
                          </Col>
                        </Row>

                        <Alert
                          className="evaluation-alert"
                          type={
                            simResult.stats.LockStatus &&
                            simResult.stats.MeasurementCoverage?.Complete &&
                            isFiniteNumber(simResult.ber) &&
                            simResult.ber >= 0 &&
                            simResult.ber < 1e-3
                              ? "success"
                              : "warning"
                          }
                          showIcon
                          message="评估解读"
                          description={`${getBerSummary(
                            simResult.ber,
                            simResult.stats.MeasurementCoverage,
                          )} ${getEvmSummary(simResult.stats.EVMPercent)}`}
                        />
                      </Card>
                    </div>
                  ))}
              </Card>
            </Col>
          </Row>
        </div>

        {!simResult && !loading && (
          <div className="empty-state">
            <Empty description="请点击上方“开始仿真”按钮" />
          </div>
        )}
      </div>
      <Drawer
        title="📚 仿真历史档案"
        placement="right"
        onClose={() => setHistoryVisible(false)}
        open={historyVisible}
        width={420}
      >
        <List
          itemLayout="vertical"
          dataSource={historyList}
          renderItem={(item) => (
            <List.Item
              key={item.id}
              actions={[
                <Button
                  type="link"
                  size="small"
                  onClick={() => loadHistoryItem(item.id)}
                >
                  📥 加载此配置并回放
                </Button>,
              ]}
              style={{ padding: "12px 0", borderBottom: "1px solid #f0f0f0" }}
            >
              <List.Item.Meta
                title={
                  <Space>
                    <span style={{ fontWeight: "bold", color: "#1890ff" }}>
                      {item.summary.modType}
                    </span>
                    <Tag>SNR: {item.summary.snr}dB</Tag>
                  </Space>
                }
                description={
                  <div style={{ fontSize: "12px", color: "#999" }}>
                    <p style={{ margin: 0 }}>
                      <ClockCircleOutlined /> {item.timestamp}
                    </p>
                    <p style={{ margin: 0 }}>
                      调制码率: {item.summary.modulatorBitRateMbps ?? "-"} Mbps；
                      符号率: {isFiniteNumber(item.summary.symbolRate)
                        ? `${formatMetricValue(item.summary.symbolRate / 1e6, 3)} Msym/s`
                        : "-"}
                    </p>
                  </div>
                }
              />
            </List.Item>
          )}
        />
      </Drawer>
    </div>
  );
};

const mockData = () => ({
  success: true,
  waveform: { t: [], i: [], q: [] },
  spectrum: { f: [1, 2, 3], p: [-10, -5, -20] },
  constellation: { i: [0.7, -0.7], q: [0.7, 0.7] },
  stats: { Fs: 16e6, CodeRate: 0.5 },
});

export default CCSDSPlatform;
