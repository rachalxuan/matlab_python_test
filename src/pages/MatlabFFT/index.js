import React, { useState, useEffect, useRef } from "react";
import {
  runMatlabSimulation,
  saveSimulationRecord,
  getHistoryList,
  getRecordDetail,
} from "../../apis/simulation";

import {
  Card,
  Form,
  Input,
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
} from "@ant-design/icons";
import * as echarts from "echarts";
import "./index.scss";

const { Option } = Select;
const RS_PRESETS = {
  "rs-255-223-i5": {
    label: "RS(223,255), I=5, TF=1115",
    RSMessageLength: 223,
    RSInterleavingDepth: 5,
    IsRSMessageShortened: false,
    RSShortenedMessageLength: 223,
    NumBytesInTransferFrame: 1115,
  },
  "rs-255-239-i5": {
    label: "RS(239,255), I=5, TF=1195",
    RSMessageLength: 239,
    RSInterleavingDepth: 5,
    IsRSMessageShortened: false,
    RSShortenedMessageLength: 239,
    NumBytesInTransferFrame: 1195,
  },
  "rs-255-223-i1": {
    label: "RS(223,255), I=1, TF=223",
    RSMessageLength: 223,
    RSInterleavingDepth: 1,
    IsRSMessageShortened: false,
    RSShortenedMessageLength: 223,
    NumBytesInTransferFrame: 223,
  },
  "rs-255-239-i1": {
    label: "RS(239,255), I=1, TF=239",
    RSMessageLength: 239,
    RSInterleavingDepth: 1,
    IsRSMessageShortened: false,
    RSShortenedMessageLength: 239,
    NumBytesInTransferFrame: 239,
  },
};

const TCM_FRAME_PRESETS = {
  2: 1115,
  2.25: 1112,
  2.5: 1116,
  2.75: 1118,
};

const getRecommendedTCMFrameBytes = (eff) =>
  TCM_FRAME_PRESETS[Number(eff)] || TCM_FRAME_PRESETS[2];

const parsePiExpression = (value) => {
  const text = String(value || "")
    .trim()
    .replace(/\s+/g, "")
    .toLowerCase();

  if (!text) return 0;
  if (!text.includes("pi")) {
    const numeric = Number(text);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  const sign = text.startsWith("-") ? -1 : 1;
  const unsigned = text.replace(/^[+-]/, "");
  const [numeratorText, denominatorText] = unsigned.split("/");
  const multiplierText = numeratorText.replace("*pi", "").replace("pi", "");
  const multiplier =
    multiplierText === "" ? 1 : Number(multiplierText.replace("*", ""));
  const denominator = denominatorText ? Number(denominatorText) : 1;

  return (
    sign *
    Math.PI *
    (Number.isFinite(multiplier) ? multiplier : 1) /
    (Number.isFinite(denominator) && denominator !== 0 ? denominator : 1)
  );
};

const parseComplexTap = (token) => {
  const text = String(token || "")
    .trim()
    .replace(/\s+/g, "")
    .toLowerCase();

  if (!text) return { re: 0, im: 0 };

  const expMatch = text.match(/^(?:(.+)\*)?exp\(([+-]?)(?:1j|j|1i|i)\*?(.+)\)$/);
  if (expMatch) {
    const scaleText = expMatch[1];
    const angleSign = expMatch[2] === "-" ? -1 : 1;
    const angle = angleSign * parsePiExpression(expMatch[3]);
    const scale =
      scaleText === undefined || scaleText === "" ? 1 : Number(scaleText);
    const mag = Number.isFinite(scale) ? scale : 1;
    return { re: mag * Math.cos(angle), im: mag * Math.sin(angle) };
  }

  const imagOnly = text.match(/^([-+]?\d*\.?\d+(?:e[-+]?\d+)?)\*?(?:j|i)$/);
  if (imagOnly) return { re: 0, im: Number(imagOnly[1]) };

  const complex = text.match(
    /^([-+]?\d*\.?\d+(?:e[-+]?\d+)?)([-+]\d*\.?\d+(?:e[-+]?\d+)?)\*?(?:j|i)$/,
  );
  if (complex) return { re: Number(complex[1]), im: Number(complex[2]) };

  const real = Number(text);
  return { re: Number.isFinite(real) ? real : 0, im: 0 };
};

const parseComplexVector = (value) => {
  if (!value) return { real: [], imag: [] };
  if (typeof value !== "string") return value;

  const taps = value
    .split(",")
    .map(parseComplexTap)
    .filter((tap) => Number.isFinite(tap.re) && Number.isFinite(tap.im));

  return {
    real: taps.map((tap) => tap.re),
    imag: taps.map((tap) => tap.im),
  };
};

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
    raw?.ConvolutionalCodeRate ?? raw?.codeRate ?? raw?.CodeRate ?? null;

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

const getBerSummary = (ber) => {
  if (!isFiniteNumber(ber) || ber < 0) return "当前场景下未得到有效 BER。";
  if (ber === 0) return "当前链路误码表现很好，接收端已基本稳定。";
  if (ber < 1e-4) return "链路质量较好，误码已经很低。";
  if (ber < 1e-2) return "链路可用，但已经能看到明显损伤影响。";
  return "链路误码偏高，建议优先检查同步或信道损伤设置。";
};

const getEvmSummary = (evmPercent) => {
  if (!isFiniteNumber(evmPercent) || evmPercent < 0) {
    return "当前调制方式下没有可靠的 EVM 结果。";
  }
  if (evmPercent < 5) return "星座点聚集得比较紧，调制质量很好。";
  if (evmPercent < 12) return "星座有一定扩散，但接收机通常还能稳定工作。";
  if (evmPercent < 20) return "调制质量已经明显下降，误码可能快速上升。";
  return "星座偏离较大，当前损伤已经比较重。";
};

const getGMSKEvmSummary = () =>
  "GMSK 是一种连续相位调制，因此该数值仅作为 IQ 或包络的粗略指示，而非标准的星座图 EVM。在评估 GMSK 的信号质量时，建议优先参考 BER（误码率）、LockRate（锁定率）、PAPR（峰均功率比）、相位轨迹、相位差以及 PSD（功率谱密度）。";

const normalizeSimulationResult = (raw) => {
  if (!raw) return null;

  if (raw.success === false) {
    return raw;
  }

  if (Object.prototype.hasOwnProperty.call(raw, "BER")) {
    const lockRate = isFiniteNumber(raw.LockRate) ? raw.LockRate : null;
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
      constellation_raw: raw.constellation_raw,
      constellation_synced: raw.constellation_synced,
      pipeline: raw.pipeline, // 4 阶段星座 + EVM 数组 + 标签
      stats: {
        Fs: raw.Fs,
        CodeRate: formatCodeRateDisplay(raw),
        ElapsedTime: elapsedTime,
        EVMPercent: raw.EVM_post_pct,
        EVMPrePercent: raw.EVM_pre_pct,
        MERdB: raw.MER_dB,
        SNREstdB: raw.SNR_est_dB,
        PAPRdB: raw.PAPR_dB,
        LockRate: lockRate,
        LockRatePercent: isFiniteNumber(lockRate) ? lockRate * 100 : null,
        LockStatus: isFiniteNumber(lockRate) ? lockRate > 0.8 : null,
        InputSNR: raw.snr_in,
        InputCFO: raw.cfo_in,
        InputPhase: raw.phase_in,
        InputDelay: raw.delay_in,
        BestTCMSkip: isFiniteNumber(raw.BestTCMSkip)
          ? raw.BestTCMSkip
          : isFiniteNumber(raw.bestTCMSkip)
          ? raw.bestTCMSkip
          : null,
        BestTCMSampleOffset: isFiniteNumber(raw.BestTCMSampleOffset)
          ? raw.BestTCMSampleOffset
          : isFiniteNumber(raw.bestTCMSampleOffset)
          ? raw.bestTCMSampleOffset
          : null,
        BestTCMBitSkip: isFiniteNumber(raw.BestTCMBitSkip)
          ? raw.BestTCMBitSkip
          : isFiniteNumber(raw.bestTCMBitSkip)
          ? raw.bestTCMBitSkip
          : null,
        BestRotDeg: isFiniteNumber(raw.BestRot_deg)
          ? raw.BestRot_deg
          : isFiniteNumber(raw.bestRot_deg)
          ? raw.bestRot_deg
          : null,
        // 残余损伤（同步链路压制后的剩余，理想值接近 0）
        ResidCFOHz: isFiniteNumber(raw.residCFO_Hz) ? raw.residCFO_Hz : null,
        ResidPhaseDeg: isFiniteNumber(raw.residPhase_deg)
          ? raw.residPhase_deg
          : null,
      },
      rawEvaluation: raw,
    };
  }

  return raw;
};

const CCSDSPlatform = () => {
  // 创建 Form 实例，用于管理所有数据状态
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [simResult, setSimResult] = useState(null);
  const [isElectron, setIsElectron] = useState(false);
  const [historyVisible, setHistoryVisible] = useState(false);
  const [historyList, setHistoryList] = useState([]);

  // 图表 Refs
  const rawConstellationRef = useRef(null);
  // const constellationRef = useRef(null);
  const syncedConstellationRef = useRef(null);
  const spectrumRef = useRef(null);
  const chartInstances = useRef({});

  // 码率常量
  const TURBO_RATES = ["1/2", "1/3", "1/4", "1/6"];
  const TURBO_INFO_BLOCKS = [1784, 3568, 7136, 8920];
  const LDPC_RATES = ["1/2", "2/3", "4/5", "7/8"];
  const LDPC_INFO_BLOCKS = [1024, 4096, 16384, 7136];
  const CONVOLUTIONAL_RATES = ["1/2", "2/3", "3/4", "5/6", "7/8"];

  useEffect(() => {
    setIsElectron(window && window.matlabAPI !== undefined);

    const resizeHandler = () => {
      Object.values(chartInstances.current).forEach(
        (chart) => chart && chart.resize(),
      );
    };
    window.addEventListener("resize", resizeHandler);
    return () => window.removeEventListener("resize", resizeHandler);
  }, []);

  const runSimulation = async (values) => {
    setLoading(true);
    setSimResult(null);
    try {
      const payload = {
        ...values,
        taskType: "ccsds_tm",
        NumBytesInTransferFrame: Number(values.NumBytesInTransferFrame ?? 1151),
      };

      if (payload.modType === "4D-8PSK-TCM") {
        payload.ModulationEfficiency = Number(payload.ModulationEfficiency ?? 2);
        payload.NumBytesInTransferFrame = getRecommendedTCMFrameBytes(
          payload.ModulationEfficiency,
        );
      }

      if (
        payload.channelCoding === "convolutional" ||
        payload.channelCoding === "concatenated"
      ) {
        payload.ConvolutionalCodeRate = payload.ConvolutionalCodeRate || "5/6";
      }

      if (payload.channelCoding === "LDPC") {
        const k = Number(payload.NumBitsInInformationBlock ?? 1024);
        payload.NumBitsInInformationBlock = k;
        payload.CodeRate = k === 7136 ? "7/8" : payload.CodeRate || "1/2";
        payload.IsLDPCOnSMTF = Boolean(payload.IsLDPCOnSMTF);
        payload.LDPCCodeblockSize = Number(payload.LDPCCodeblockSize ?? 1);
      }

      if (payload.channelCoding === "Turbo") {
        payload.NumBitsInInformationBlock = Number(
          payload.NumBitsInInformationBlock ?? 1784,
        );
        payload.CodeRate = payload.CodeRate || "1/2";
      }

      if (
        payload.channelCoding === "RS" ||
        payload.channelCoding === "concatenated"
      ) {
        const preset =
          RS_PRESETS[payload.rsPreset] || RS_PRESETS["rs-255-223-i5"];
        Object.assign(payload, preset);
      }

      payload.enableHChannel = Boolean(payload.enableHChannel);
      payload.normalizeHChannel = Boolean(payload.normalizeHChannel);
      payload.enableEqualizer = Boolean(payload.enableEqualizer);
      payload.normalizeEqualizerOutput = Boolean(
        payload.normalizeEqualizerOutput,
      );
      payload.enableFACMEqualizer = Boolean(payload.enableFACMEqualizer);
      payload.ddEqualizerStep = Number(payload.ddEqualizerStep ?? 2e-4);
      payload.ddEqualizerPasses = Number(payload.ddEqualizerPasses ?? 2);

      if (payload.enableHChannel && typeof payload.H === "string") {
        payload.H = parseComplexVector(payload.H);
      }

      console.log("正在通过 HTTP 请求仿真...", payload);
      const res = await runMatlabSimulation(payload);
      const normalizedRes = normalizeSimulationResult(res);

      if (normalizedRes && normalizedRes.success) {
        message.success("仿真成功！");
        setSimResult(normalizedRes);
        renderCharts(normalizedRes);

        // 保存到 localStorage
        localStorage.setItem("latestSimResult", JSON.stringify(normalizedRes));

        if (normalizedRes.stats?.ElapsedTime) {
          console.log(`后端计算耗时: ${normalizedRes.stats.ElapsedTime}s`);
        }
      } else {
        message.error("仿真失败: " + (normalizedRes?.error || "未知错误"));
      }
    } catch (error) {
      console.error("调用失败:", error);
      message.error("请求失败，请检查 Python 服务是否启动");
    } finally {
      setLoading(false);
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
        message.success("保存成功！");
      }
    } catch (error) {
      console.error(error);
      message.error("保存失败，请检查后端连接");
    }
  };

  // === 新增功能 B: 打开历史记录列表 ===
  const openHistory = async () => {
    setHistoryVisible(true);
    try {
      const res = await getHistoryList();
      if (Array.isArray(res)) {
        setHistoryList(res);
      } else {
        setHistoryList([]);
      }
    } catch (error) {
      message.error("获取历史记录失败");
    }
  };

  // === 新增功能 C: 点击某条历史记录进行回放 ===
  const loadHistoryItem = async (id) => {
    const hide = message.loading("正在加载历史数据...", 0);
    try {
      const res = await getRecordDetail(id);

      if (res && res.success && res.data) {
        const { config, result } = res.data;
        const normalizedResult = normalizeSimulationResult(result);

        form.setFieldsValue(config);
        setSimResult(normalizedResult);
        renderCharts(normalizedResult);

        message.success("\u5df2\u52a0\u8f7d\u5386\u53f2\u8bb0\u5f55");
        setHistoryVisible(false);
      }
    } catch (error) {
      console.error(error);
      message.error("\u52a0\u8f7d\u5931\u8d25");
    } finally {
      hide();
    }
  };

  const drawConstellation = (domRef, title, data) => {
    const dom = domRef.current;

    if (!dom || !data) return;

    // Dispose previous chart instance.
    const oldChart = echarts.getInstanceByDom(dom);
    if (oldChart) oldChart.dispose();

    const chart = echarts.init(dom);

    // Build ECharts point data.
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
    const maxPower = Math.max(...powers);
    const threshold = maxPower - 15;

    let sumFreqTimesEnergy = 0;
    let sumEnergy = 0;

    powers.forEach((p_db, i) => {
      if (p_db > threshold) {
        const energy = Math.pow(10, p_db / 10);
        sumFreqTimesEnergy += freqs[i] * energy;
        sumEnergy += energy;
      }
    });

    if (sumEnergy === 0) return freqs[powers.indexOf(maxPower)];
    return sumFreqTimesEnergy / sumEnergy;
  };

  const renderCharts = (data) => {
    if (!data) return;

    if (data.constellation_raw) {
      drawConstellation(
        rawConstellationRef,
        "修复前 (信道损伤)",
        data.constellation_raw,
      );
    }

    if (data.constellation_synced) {
      drawConstellation(
        syncedConstellationRef,
        "修复后 (接收机同步)",
        data.constellation_synced,
      );
    }

    if (spectrumRef.current && data.spectrum) {
      const domSpe = spectrumRef.current;
      let instance = echarts.getInstanceByDom(domSpe);
      if (instance) instance.dispose();

      const chart = echarts.init(domSpe);
      if (chartInstances.current) {
        chartInstances.current.spectrum = chart;
      }

      const { f, p_rx, p_tx } = data.spectrum;
      const rxCenterFreqHz = calculateCenterFreq(f, p_rx);
      const txCenterFreqHz = calculateCenterFreq(f, p_tx);
      const rxFreqMHz = rxCenterFreqHz / 1e6;
      const txFreqMHz = txCenterFreqHz / 1e6;

      chart.setOption({
        backgroundColor: "#fff",
        title: {
          text: "功率谱密度 (PSD)",
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
              data: [{ xAxis: f.findIndex((val) => val === rxCenterFreqHz) }],
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
              title="SNR估计"
              value={formatMetricValue(simResult.stats.SNREstdB)}
              suffix="dB"
              valueStyle={{ color: "#1677ff", fontSize: 24 }}
            />
          </Card>
          <Card className="kpi-card" bordered={false}>
            <Statistic
              title="锁定率"
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
                      color={getMetricTone(simResult.stats.EVMPercent, {
                        good: 5,
                        warn: 12,
                      })}
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
                <Descriptions.Item label="SNR估计">
                  {formatMetricValue(simResult.stats.SNREstdB)} dB
                </Descriptions.Item>
                <Descriptions.Item label="PAPR">
                  {formatMetricValue(simResult.stats.PAPRdB)} dB
                </Descriptions.Item>
                <Descriptions.Item label="实际码率">
                  {simResult.stats.CodeRate}
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
                <Descriptions.Item label="输入SNR">
                  {formatMetricValue(simResult.stats.InputSNR)} dB
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
                <Descriptions.Item label="锁定率">
                  {formatMetricValue(simResult.stats.LockRatePercent)}%
                </Descriptions.Item>
                <Descriptions.Item label="同步状态">
                  <Tag
                    color={simResult.stats.LockStatus ? "success" : "warning"}
                  >
                    {formatLockStatus(simResult.stats.LockStatus)}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label="MATLAB耗时">
                  {formatMetricValue(simResult.stats.ElapsedTime, 3)} s
                </Descriptions.Item>
                {isFiniteNumber(simResult.stats.BestTCMSampleOffset) && (
                  <Descriptions.Item label="4D sample offset">
                    {simResult.stats.BestTCMSampleOffset}
                  </Descriptions.Item>
                )}
                {isFiniteNumber(simResult.stats.BestTCMSkip) && (
                  <Descriptions.Item label="4D TCM skip">
                    {simResult.stats.BestTCMSkip}
                  </Descriptions.Item>
                )}
                {isFiniteNumber(simResult.stats.BestTCMBitSkip) && (
                  <Descriptions.Item label="4D TCM bit skip">
                    {simResult.stats.BestTCMBitSkip}
                  </Descriptions.Item>
                )}
                <Descriptions.Item label={"\u7ed3\u8bba"}>
                  {simResult.stats.LockStatus
                    ? "\u94fe\u8def\u5df2\u9501\u5b9a\uff0c\u53ef\u7ed3\u5408 BER / EVM / MER \u5224\u65ad\u8d28\u91cf"
                    : "\u4f18\u5148\u68c0\u67e5\u540c\u6b65\u94fe\u8def\u662f\u5426\u7a33\u5b9a\u9501\u5b9a"}
                </Descriptions.Item>
              </Descriptions>
            </Col>
          </Row>

          <Alert
            className="evaluation-alert"
            type={
              simResult.stats.LockStatus &&
              isFiniteNumber(simResult.ber) &&
              simResult.ber >= 0 &&
              simResult.ber < 1e-3
                ? "success"
                : "warning"
            }
            showIcon
            message={"\u8bc4\u4f30\u89e3\u8bfb"}
            description={`${getBerSummary(simResult.ber)} ${
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
      {/* Top header */}
      <div className="platform-header">
        <div className="title-area">
          <RocketOutlined className="icon" />
          <span className="title">{"CCSDS \u9065\u6d4b\u4eff\u771f\u63a7\u5236\u53f0"}</span>
        </div>
        <div className="status-area">
          <Space size="middle">
            {/* Only enabled when a result exists. */}
            <Tooltip title={"\u5c06\u5f53\u524d\u53c2\u6570\u548c\u7ed3\u679c\u5b58\u5165\u6570\u636e\u5e93"}>
              <Button
                icon={<SaveOutlined />}
                onClick={handleSave}
                disabled={!simResult}
              >
                {"\u4fdd\u5b58\u7ed3\u679c"}
              </Button>
            </Tooltip>

            <Button icon={<HistoryOutlined />} onClick={openHistory}>
              {"\u5386\u53f2\u8bb0\u5f55"}
            </Button>

            <Divider type="vertical" />

            {isElectron ? (
              <Tag color="success" icon={<CheckCircleOutlined />}>
                MATLAB Ready
              </Tag>
            ) : (
              <Tag color="orange" icon={<SyncOutlined spin={loading} />}>
                Demo Mode
              </Tag>
            )}
          </Space>
        </div>
      </div>

      <div className="content-wrapper">
        {/* 1. Top: parameter configuration */}
        <Card className="config-panel" bordered={false}>
          <Form
            form={form}
            layout="vertical"
            onFinish={runSimulation}
            initialValues={{
              modType: "QPSK",
              channelCoding: "convolutional",
              ConvolutionalCodeRate: "5/6",
              CodeRate: "N/A",
              NumBitsInInformationBlock: 1024,
              IsLDPCOnSMTF: false,
              LDPCCodeblockSize: 1,
              NumBytesInTransferFrame: 1151,
              symbolRate: 5000000,
              RolloffFactor: 0.35,
              snr: 10,
              phaseOffset: 0,
              sps: 8,
              hasASM: true,
              hasRandomizer: false,
              rsPreset: "rs-255-223-i5",
              RSMessageLength: 223,
              RSInterleavingDepth: 5,
              IsRSMessageShortened: false,
              RSShortenedMessageLength: 223,
              enableHChannel: false,
              HMode: "siso_multipath",
              H: "1,0,0.25*exp(1j*pi/3),0,0.10*exp(-1j*pi/4)",
              normalizeHChannel: true,
              enableEqualizer: false,
              equalizerMode: "mmse",
              normalizeEqualizerOutput: true,
              enableFACMEqualizer: false,
              facmEqualizerMode: "frame-ls",
              ddEqualizerStep: 2e-4,
              ddEqualizerPasses: 2,
            }}
          >
            <Row gutter={24} align="bottom">
              <Col span={4}>
                <Form.Item name="modType" label={"\u8c03\u5236\u65b9\u5f0f"}>
                  <Select
                    onChange={(mod) => {
                      if (mod === "4D-8PSK-TCM") {
                        const eff = Number(
                          form.getFieldValue("ModulationEfficiency") ?? 2,
                        );
                        form.setFieldsValue({
                          ModulationEfficiency: eff,
                          NumBytesInTransferFrame:
                            getRecommendedTCMFrameBytes(eff),
                        });
                      }
                    }}
                  >
                    <Option value="BPSK">BPSK</Option>
                    <Option value="QPSK">QPSK</Option>
                    <Option value="8PSK">8PSK</Option>
                    <Option value="GMSK">GMSK</Option>
                    <Option value="OQPSK">OQPSK</Option>
                    <Option value="4D-8PSK-TCM">4D-8PSK-TCM</Option>
                    <Option value="16APSK">16APSK</Option>
                    <Option value="32APSK">32APSK</Option>
                    <Option value="PCM/PSK/PM">PCM/PSK/PM</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item name="symbolRate" label={"\u7b26\u53f7\u7387 (sps)"}>
                  <InputNumber
                    style={{ width: "100%" }}
                    min={1000}
                    step={100000}
                    formatter={(v) =>
                      `${v}`.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
                    }
                  />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item name="snr" label={"\u4fe1\u566a\u6bd4 (SNR)"}>
                  <InputNumber min={0} max={100} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item name="sps" label={"\u91c7\u6837/\u7b26\u53f7 (SPS)"}>
                  <InputNumber min={4} max={32} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              {/* Dynamic modulation parameter controls */}
              <Form.Item noStyle dependencies={["modType"]}>
                {({ getFieldValue }) => {
                  const mod = getFieldValue("modType");

                  if (mod === "16APSK" || mod === "32APSK") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="acmFormat"
                          label={"ACM \u683c\u5f0f"}
                          initialValue={mod === "16APSK" ? 14 : 21}
                        >
                          <Select>
                            {(mod === "16APSK"
                              ? [13, 14, 15]
                              : [20, 21, 22]
                            ).map((fmt) => (
                              <Option
                                value={fmt}
                                key={fmt}
                              >{`Fmt ${fmt}`}</Option>
                            ))}
                          </Select>
                        </Form.Item>
                      </Col>
                    );
                  }
                  if (mod === "4D-8PSK-TCM") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="ModulationEfficiency"
                          label={"\u8c03\u5236\u6548\u7387"}
                          initialValue={2.0}
                        >
                          <Select
                            onChange={(eff) => {
                              form.setFieldsValue({
                                NumBytesInTransferFrame:
                                  getRecommendedTCMFrameBytes(eff),
                              });
                            }}
                          >
                            <Option value={2.0}>2.0</Option>
                            <Option value={2.25}>2.25</Option>
                            <Option value={2.5}>2.5</Option>
                            <Option value={2.75}>2.75</Option>
                          </Select>
                        </Form.Item>
                      </Col>
                    );
                  }
                  if (mod === "GMSK") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="BandwidthTimeProduct"
                          label={"BT \u503c (GMSK)"}
                          initialValue={0.5}
                        >
                          <Select>
                            <Option value="0.25">0.25</Option>
                            <Option value="0.5">0.5</Option>
                          </Select>
                        </Form.Item>
                      </Col>
                    );
                  }
                  if (mod === "PCM/PSK/PM") {
                    return (
                      <>
                        <Col span={3}>
                          <Form.Item
                            name="ModulationIndex"
                            label={"\u8c03\u5236\u6307\u6570 (Rad)"}
                            initialValue={1.0}
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
                            label={"\u526f\u8f7d\u6ce2\u6ce2\u5f62"}
                            initialValue="sine"
                          >
                            <Select>
                              <Option value="sine">{"\u6b63\u5f26\u6ce2"}</Option>
                              <Option value="square">{"\u65b9\u6ce2"}</Option>
                            </Select>
                          </Form.Item>
                        </Col>
                      </>
                    );
                  }
                  return (
                    <>
                      <Col span={3}>
                        <Form.Item
                          name="RolloffFactor"
                          label={"\u6eda\u964d\u7cfb\u6570 (alpha)"}
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
                          name="FilterSpanInSymbols"
                          label={"\u6ee4\u6ce2\u5668\u957f\u5ea6 (\u7b26\u53f7)"}
                          initialValue={10}
                        >
                          <InputNumber min={4} max={64} style={{ width: "100%" }} />
                        </Form.Item>
                      </Col>
                    </>
                  );
                }}
              </Form.Item>
            </Row>

            <Row gutter={16} align="bottom">
              <Col span={5}>
                <Form.Item name="channelCoding" label={"\u4fe1\u9053\u7f16\u7801"}>
                  <Select
                    onChange={(value) => {
                      if (value === "Turbo") {
                        form.setFieldsValue({
                          CodeRate: "1/2",
                          NumBitsInInformationBlock: 1784,
                        });
                      } else if (value === "LDPC") {
                        form.setFieldsValue({
                          CodeRate: "1/2",
                          NumBitsInInformationBlock: 1024,
                          IsLDPCOnSMTF: false,
                          LDPCCodeblockSize: 1,
                        });
                      } else {
                        form.setFieldsValue({ CodeRate: "N/A" });
                      }

                      if (
                        value === "convolutional" ||
                        value === "concatenated"
                      ) {
                        form.setFieldsValue({
                          ConvolutionalCodeRate:
                            form.getFieldValue("ConvolutionalCodeRate") ||
                            "5/6",
                        });
                      }
                    }}
                  >
                    <Option value="convolutional">Convolutional</Option>
                    <Option value="RS">{"RS \u7801"}</Option>
                    <Option value="concatenated">Concatenated</Option>
                    <Option value="LDPC">LDPC</Option>
                    <Option value="Turbo">Turbo</Option>
                    <Option value="None">None</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item label={"\u9891\u504f (Hz)"} name="cfo" initialValue={0}>
                  <InputNumber style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item name="phaseOffset" label={"\u76f8\u4f4d\u504f\u79fb (deg)"}>
                  <InputNumber min={0} max={360} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item
                  label={"\u5b9a\u65f6\u504f\u5dee (Samples)"}
                  name="delay"
                  initialValue={0}
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
                  const infoBlock = Number(
                    getFieldValue("NumBitsInInformationBlock") ??
                      (coding === "Turbo" ? 1784 : 1024),
                  );
                  const ldpcK = infoBlock;
                  const showConvRate =
                    coding === "convolutional" || coding === "concatenated";
                  const showRS = coding === "RS" || coding === "concatenated";
                  const isApplicable = coding === "Turbo" || coding === "LDPC";

                  // Calculate defaults and options for each coding mode.
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
                      {/* A. Convolutional code rate */}
                      {showConvRate && (
                        <Col span={4}>
                          <Form.Item
                            name="ConvolutionalCodeRate"
                            label={"\u5377\u79ef\u7801\u7387"}
                            initialValue={convDefaultRate}
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

                      {/* B. RS configuration */}
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
                            label={"RS \u914d\u7f6e"}
                            initialValue="rs-255-223-i5"
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
                                    RSShortenedMessageLength:
                                      preset.RSShortenedMessageLength,
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
                      )}

                      {/* C. Turbo/LDPC code rate */}

                      {(coding === "Turbo" || coding === "LDPC") && (
                        <Col span={4}>
                          <Form.Item
                            name="NumBitsInInformationBlock"
                            label={coding === "Turbo" ? "Turbo k" : "LDPC k"}
                            initialValue={coding === "Turbo" ? 1784 : 1024}
                          >
                            <Select
                              onChange={(k) => {
                                if (coding === "LDPC") {
                                  form.setFieldsValue({
                                    CodeRate:
                                      Number(k) === 7136 ? "7/8" : "1/2",
                                  });
                                }
                              }}
                            >
                              {(coding === "Turbo"
                                ? TURBO_INFO_BLOCKS
                                : LDPC_INFO_BLOCKS
                              ).map((k) => (
                                <Option key={k} value={k}>
                                  {k} bits
                                </Option>
                              ))}
                            </Select>
                          </Form.Item>
                        </Col>
                      )}

                      <Col span={4}>
                        <Form.Item
                          name="CodeRate"
                          label={"Turbo/LDPC \u7801\u7387"}
                          key={coding}
                          initialValue={turboLdpcDefaultRate}
                        >
                          <Select disabled={!isApplicable}>
                            {turboLdpcRateOptions.map((rate) => (
                              <Option key={rate} value={rate}>
                                {rate}
                              </Option>
                            ))}
                          </Select>
                        </Form.Item>
                      </Col>
                    </>
                  );
                }}
              </Form.Item>
            </Row>
            <Row gutter={16}>
              <Col span={6}>
                <Form.Item
                  name="hasRandomizer"
                  valuePropName="checked"
                  initialValue={false}
                >
                  <Checkbox>{"\u542f\u7528\u52a0\u6270 (Randomizer)"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={6}>
                <Form.Item
                  name="hasASM"
                  valuePropName="checked"
                  initialValue={false}
                >
                  <Checkbox>{"\u63d2\u5165\u540c\u6b65\u5934 (ASM)"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={10}>
                <Form.Item name="hasPilots" valuePropName="checked">
                  <Checkbox>{"\u63d2\u5165\u5bfc\u9891 (Distributed Pilots)"}</Checkbox>
                </Form.Item>
              </Col>
            </Row>
            <Row gutter={16}>
              <Col span={4}>
                <Form.Item name="enableHChannel" valuePropName="checked">
                  <Checkbox>{"H \u4fe1\u9053"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item name="normalizeHChannel" valuePropName="checked">
                  <Checkbox>{"\u5f52\u4e00\u5316 H"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={5}>
                <Form.Item name="enableEqualizer" valuePropName="checked">
                  <Checkbox>{"\u5df2\u77e5 H \u5747\u8861"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={5}>
                <Form.Item
                  name="normalizeEqualizerOutput"
                  valuePropName="checked"
                >
                  <Checkbox>{"\u5747\u8861\u8f93\u51fa\u5f52\u4e00\u5316"}</Checkbox>
                </Form.Item>
              </Col>
              <Col span={5}>
                <Form.Item name="enableFACMEqualizer" valuePropName="checked">
                  <Checkbox>{"FACM \u5e27\u5747\u8861"}</Checkbox>
                </Form.Item>
              </Col>
            </Row>
            <Row gutter={16}>
              <Col span={4}>
                <Form.Item name="HMode" label={"H \u6a21\u5f0f"}>
                  <Select>
                    <Option value="siso_multipath">siso_multipath</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={8}>
                <Form.Item name="H" label={"H taps"}>
                  <Input placeholder="1,0,0.25*exp(1j*pi/3),0,0.10*exp(-1j*pi/4)" />
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item name="equalizerMode" label={"\u5747\u8861\u6a21\u5f0f"}>
                  <Select>
                    <Option value="mmse">mmse</Option>
                    <Option value="zf">zf</Option>
                    <Option value="dd16apsk">dd16apsk</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item
                  name="facmEqualizerMode"
                  label={"FACM \u5747\u8861"}
                >
                  <Select>
                    <Option value="frame-ls">frame-ls</Option>
                    <Option value="dd16apsk">dd16apsk</Option>
                    <Option value="rde16apsk">rde16apsk</Option>
                    <Option value="cma16apsk">cma16apsk</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={2}>
                <Form.Item name="ddEqualizerStep" label={"DD step"}>
                  <InputNumber min={0} step={1e-4} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={2}>
                <Form.Item name="ddEqualizerPasses" label={"DD pass"}>
                  <InputNumber min={1} step={1} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
            </Row>
            <Row gutter={16} align="bottom">
              <Col span={8} offset={8}>
                <Form.Item label=" ">
                  <Button
                    type="primary"
                    htmlType="submit"
                    block
                    loading={loading}
                    icon={<GatewayOutlined />}
                    size="large"
                  >
                    {loading ? "\u8ba1\u7b97\u4e2d..." : "\u5f00\u59cb\u4eff\u771f"}
                  </Button>
                </Form.Item>
              </Col>
            </Row>
          </Form>
        </Card>


        {/* 2. 底部：图表展示区 */}
        <div className="charts-row">
          {/* First row: constellation comparison */}
          <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
            {/* 左上：修复前 */}
            <Col span={12}>
              <Card
                title={
                  <>
                    <RadarChartOutlined /> {"\u4fee\u590d\u524d (Before)"}
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {/* Bind rawConstellationRef */}
                  <div
                    ref={rawConstellationRef}
                    // style={{ width: "100%", height: "400px" }}
                    className="chart-box"
                  />
                </div>
              </Card>
            </Col>

            {/* 右上：修复后 */}
            <Col span={12}>
              <Card
                title={
                  <>
                    <RadarChartOutlined /> {"\u4fee\u590d\u540e (After)"}
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {/* Bind syncedConstellationRef */}
                  <div
                    ref={syncedConstellationRef}
                    className="chart-box"
                    // style={{ width: "100%", height: "400px" }}
                  />
                </div>
              </Card>
            </Col>
          </Row>

          {/* Second row: PSD and statistics */}
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
                  {/* PSD is usually clearer with a wide, shorter panel. */}
                  <div ref={spectrumRef} className="chart-box" />
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
                            title="同步状态"
                            value={formatMetricValue(simResult.stats.SNREstdB)}
                            suffix="dB"
                            valueStyle={{
                              color: "#1677ff",
                              fontSize: 24,
                            }}
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="估计频偏"
                            value={formatMetricValue(
                              simResult.stats.LockRatePercent,
                            )}
                            suffix="%"
                          />
                        </Card>
                        <Card className="kpi-card" bordered={false}>
                          <Statistic
                            title="采样率"
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
                              <Descriptions.Item label="MER">
                                {formatMetricValue(simResult.stats.MERdB)} dB
                              </Descriptions.Item>
                              <Descriptions.Item label="EVM">
                                {isFiniteNumber(simResult.stats.EVMPercent) &&
                                simResult.stats.EVMPercent >= 0 ? (
                                  <Tag
                                    color={getMetricTone(
                                      simResult.stats.EVMPercent,
                                      { good: 5, warn: 12 },
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
                              <Descriptions.Item label="实际码率">
                                {simResult.stats.CodeRate}
                              </Descriptions.Item>
                              <Descriptions.Item label="MATLAB耗时">
                                {formatMetricValue(
                                  simResult.stats.ElapsedTime,
                                  3,
                                )}{" "}
                                s
                              </Descriptions.Item>
                              {isFiniteNumber(
                                simResult.stats.BestTCMSampleOffset,
                              ) && (
                                <Descriptions.Item label="4D sample offset">
                                  {simResult.stats.BestTCMSampleOffset}
                                </Descriptions.Item>
                              )}
                              {isFiniteNumber(simResult.stats.BestTCMSkip) && (
                                <Descriptions.Item label="4D TCM skip">
                                  {simResult.stats.BestTCMSkip}
                                </Descriptions.Item>
                              )}
                              {isFiniteNumber(simResult.stats.BestTCMBitSkip) && (
                                <Descriptions.Item label="4D TCM bit skip">
                                  {simResult.stats.BestTCMBitSkip}
                                </Descriptions.Item>
                              )}
                            </Descriptions>
                          </Col>

                          <Col xs={24} xl={7}>
                            <Descriptions
                              title="同步状态"
                              size="small"
                              column={1}
                              bordered
                            >
                              <Descriptions.Item label="锁定状态">
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
                              <Descriptions.Item label="估计频偏">
                                {formatMetricValue(
                                  simResult.stats.EstimatedCFO,
                                )}{" "}
                                Hz
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
                                {simResult.stats.ComparedFrames ?? 0}
                              </Descriptions.Item>
                              <Descriptions.Item label="出错帧数">
                                {simResult.stats.FrameErrors ?? 0}
                              </Descriptions.Item>
                              <Descriptions.Item label="结论">
                                {simResult.stats.ComparedFrames > 0
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
        title="仿真历史档案"
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
                  加载此配置并回放
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
                      Symbol Rate: {item.summary.symbolRate}
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
