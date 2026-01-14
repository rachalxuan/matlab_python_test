import React, { useState, useEffect, useRef } from "react";
import { runMatlabSimulation } from "../../apis/simulation";
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
} from "antd";
import {
  RocketOutlined,
  SettingOutlined,
  GatewayOutlined,
  CheckCircleOutlined,
  SyncOutlined,
  BarChartOutlined,
  RadarChartOutlined,
} from "@ant-design/icons";
import * as echarts from "echarts";
import "./index.scss";

const { Option } = Select;

const CCSDSPlatform = () => {
  //创建Form实例， 用于管理所有数据状态
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [simResult, setSimResult] = useState(null);
  const [isElectron, setIsElectron] = useState(false);

  // 图表 Refs
  const rawConstellationRef = useRef(null);
  // const constellationRef = useRef(null);
  const syncedConstellationRef = useRef(null);
  const spectrumRef = useRef(null);
  const chartInstances = useRef({});

  // 码率常量
  const TURBO_RATES = ["1/2", "1/3", "1/4", "1/6"];
  const LDPC_RATES = ["1/2", "2/3", "4/5", "7/8"];
  const CONVOLUTIONAL_RATES = ["1/2", "2/3", "3/4", "5/6", "7/8"];

  useEffect(() => {
    setIsElectron(window && window.matlabAPI !== undefined);

    const resizeHandler = () => {
      Object.values(chartInstances.current).forEach(
        (chart) => chart && chart.resize()
      );
    };
    window.addEventListener("resize", resizeHandler);
    return () => window.removeEventListener("resize", resizeHandler);
  }, []);

  const runSimulation = async (values) => {
    setLoading(true);
    setSimResult(null);
    try {
      const payload = { ...values, taskType: "ccsds_tm" };

      console.log("正在通过 HTTP 请求仿真...", values);
      const res = await runMatlabSimulation(values);

      if (res && res.success) {
        message.success("仿真成功！");
        setSimResult(res);
        renderCharts(res);

        //  保存到 localStorage
        localStorage.setItem("latestSimResult", JSON.stringify(res));

        if (res.stats) {
          console.log(`后端计算耗时: ${res.stats.ElapsedTime}s`);
        }
      } else {
        message.error("仿真失败: " + (res?.error || "未知错误"));
      }
    } catch (error) {
      console.error("调用失败:", error);
      message.error("请求失败，请检查 Python 服务是否启动");
    } finally {
      setLoading(false);
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
    // 1. 画修复前的图
    if (data.constellation_raw) {
      drawConstellation(
        rawConstellationRef,
        "❌ 修复前 (信道损伤)",
        data.constellation_raw
      );
    }

    // 2. 画修复后的图
    if (data.constellation_synced) {
      drawConstellation(
        syncedConstellationRef,
        "✅ 修复后 (接收机同步)",
        data.constellation_synced
      );
    }
    // 3. 频谱图（增强版：添加峰值标记线）
    if (spectrumRef.current) {
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
  };

  return (
    <div className="ccsds-platform">
      {/* 顶部 Header */}
      <div className="platform-header">
        <div className="title-area">
          <RocketOutlined className="icon" />
          <span className="title">CCSDS 遥测仿真控制台</span>
        </div>
        <div className="status-area">
          {isElectron ? (
            <Tag color="success" icon={<CheckCircleOutlined />}>
              MATLAB Ready
            </Tag>
          ) : (
            <Tag color="orange" icon={<SyncOutlined spin={loading} />}>
              Demo Mode
            </Tag>
          )}
        </div>
      </div>

      <div className="content-wrapper">
        {/* 1. 顶部：参数配置区 */}
        <Card className="config-panel" bordered={false}>
          <Form
            form={form}
            layout="vertical"
            onFinish={runSimulation}
            initialValues={{
              modType: "QPSK",
              channelCoding: "convolutional",
              symbolRate: 5000000,
              RolloffFactor: 0.35,
              snr: 10,
              phaseOffset: 0,
              sps: 8,
            }}
          >
            <Row gutter={24} align="bottom">
              <Col span={4}>
                <Form.Item name="modType" label="调制方式">
                  <Select>
                    <Option value="BPSK">BPSK</Option>
                    <Option value="QPSK">QPSK</Option>
                    <Option value="8PSK">8PSK</Option>
                    <Option value="GMSK">GMSK</Option>
                    <Option value="OQPSK">OQPSK</Option>
                    <Option value="16APSK">16APSK</Option>
                    <Option value="32APSK">32APSK</Option>
                    <Option value="PCM/PSK/PM">PCM/PSK/PM</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item name="symbolRate" label="符号率 (sps)">
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
                <Form.Item name="snr" label="信噪比 (SNR)">
                  <InputNumber min={0} max={100} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item name="sps" label="采样/符号 (SPS)">
                  <InputNumber min={4} max={32} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              {/* === 动态渲染：调制参数联动区 === */}
              <Form.Item noStyle dependencies={["modType"]}>
                {({ getFieldValue }) => {
                  const mod = getFieldValue("modType");

                  // 1. APSK (16/32) - FACM 模式
                  if (mod === "16APSK" || mod === "32APSK") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="acmFormat"
                          label="ACM 格式"
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
                  // 2. 4D-8PSK-TCM
                  else if (mod === "4D-8PSK-TCM") {
                    return (
                      <Col span={4}>
                        <Form.Item
                          name="ModulationEfficiency"
                          label="调制效率"
                          initialValue={2.0}
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
                          label="BT 值 (GMSK)"
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
                  // 4. PCM/PSK/PM (子载波调制)
                  else if (mod === "PCM/PSK/PM") {
                    return (
                      <>
                        <Col span={3}>
                          <Form.Item
                            name="ModulationIndex"
                            label="调制指数 (Rad)"
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
                            label="副载波波形"
                            initialValue="sine"
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
                  // 5. PSK/QPSK/OQPSK (标准 RRC 调制)
                  else {
                    return (
                      <>
                        <Col span={3}>
                          <Form.Item
                            name="RolloffFactor"
                            label="滚降系数 (α)"
                            // initialValue={0.35}
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
                            label="滤波器长度 (符号)"
                            initialValue={10}
                          >
                            <InputNumber
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
                <Form.Item name="channelCoding" label="信道编码">
                  <Select
                    onChange={(value) => {
                      // 当编码类型改变时，重置 CodeRate 字段
                      if (value === "Turbo") {
                        form.setFieldsValue({ CodeRate: "1/2" });
                      } else if (value === "LDPC") {
                        form.setFieldsValue({ CodeRate: "7/8" });
                      } else {
                        form.setFieldsValue({ CodeRate: "N/A" });
                      }

                      // 重置卷积码率
                      if (
                        value === "convolutional" ||
                        value === "concatenated"
                      ) {
                        form.setFieldsValue({ ConvolutionalCodeRate: "1/2" });
                      }
                    }}
                  >
                    <Option value="convolutional">Convolutional</Option>
                    {/* <Option value="concatenated">concatenated</Option> */}
                    <Option value="RS">RS码</Option>
                    <Option value="LDPC">LDPC</Option>
                    <Option value="Turbo">Turbo</Option>
                    <Option value="None">None</Option>
                  </Select>
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item label="频偏 (Hz)" name="cfo" initialValue={0}>
                  <InputNumber style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={3}>
                <Form.Item name="phaseOffset" label="相位偏移 (°)">
                  <InputNumber min={0} max={360} style={{ width: "100%" }} />
                </Form.Item>
              </Col>
              <Col span={4}>
                <Form.Item
                  label="定时偏差 (Samples)"
                  name="delay"
                  initialValue={0}
                >
                  <InputNumber step={0.1} style={{ width: "100%" }} />
                </Form.Item>
              </Col>

              <Form.Item noStyle dependencies={["channelCoding"]}>
                {({ getFieldValue }) => {
                  const coding = getFieldValue("channelCoding");
                  const showConvRate =
                    coding === "convolutional" || coding === "concatenated";
                  const showRS = coding === "RS" || coding === "concatenated";
                  const isApplicable = coding === "Turbo" || coding === "LDPC";

                  // 分别计算各自的默认值和选项
                  let convDefaultRate = "1/2";
                  let convRateOptions = CONVOLUTIONAL_RATES;

                  let turboLdpcDefaultRate = "N/A";
                  let turboLdpcRateOptions = ["N/A"];

                  if (coding === "Turbo") {
                    turboLdpcRateOptions = TURBO_RATES;
                    turboLdpcDefaultRate = "1/2";
                  } else if (coding === "LDPC") {
                    turboLdpcRateOptions = LDPC_RATES;
                    turboLdpcDefaultRate = "7/8";
                  }

                  return (
                    <>
                      {/* A. 卷积码率 */}
                      {showConvRate && (
                        <Col span={4}>
                          <Form.Item
                            name="ConvolutionalCodeRate"
                            label="卷积码率"
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

                      {/* B. RS 交织深度 */}
                      {showRS && (
                        <Col span={4}>
                          <Form.Item
                            name="RSInterleavingDepth"
                            label="RS 交织深度"
                            initialValue={1}
                          >
                            <InputNumber
                              min={1}
                              max={5}
                              style={{ width: "100%" }}
                            />
                          </Form.Item>
                        </Col>
                      )}

                      {/* C. Turbo/LDPC 码率 */}
                      <Col span={4}>
                        <Form.Item
                          name="CodeRate"
                          label="Turbo/LDPC 码率"
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
                  <Checkbox>启用加扰 (Randomizer)</Checkbox>
                </Form.Item>
              </Col>
              <Col span={6}>
                <Form.Item
                  name="hasASM"
                  valuePropName="checked"
                  initialValue={false}
                >
                  <Checkbox>插入同步头 (ASM)</Checkbox>
                </Form.Item>
              </Col>
              <Col span={10}>
                <Form.Item name="hasPilots" valuePropName="checked">
                  <Checkbox>插入导频 (Distributed Pilots)</Checkbox>
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
                    {loading ? "计算中..." : "开始仿真"}
                  </Button>
                </Form.Item>
              </Col>
            </Row>
          </Form>
        </Card>

        {/* 2. 底部：图表展示区 */}
        <div className="charts-row">
          {/* 第一行：星座图对比 (左右各占 12/24) */}
          <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
            {/* 左上：修复前 */}
            <Col span={12}>
              <Card
                title={
                  <>
                    <RadarChartOutlined /> 修复前 (Before)
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {/* 绑定 rawConstellationRef */}
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
                    <RadarChartOutlined /> 修复后 (After)
                  </>
                }
                bordered={false}
              >
                <div className="square-container">
                  {/* 🆕 绑定 syncedConstellationRef */}
                  <div
                    ref={syncedConstellationRef}
                    className="chart-box"
                    // style={{ width: "100%", height: "400px" }}
                  />
                </div>
              </Card>
            </Col>
          </Row>

          {/* 第二行：频谱图 + 统计 (占满整行 24/24) */}
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
                  {/* 频谱图通常宽一点好看，高度可以稍微给低一点 */}
                  <div ref={spectrumRef} className="chart-box" />
                </div>

                {/* 统计信息放在频谱图下面 */}
                {simResult && simResult.stats && (
                  <div
                    className="stats-bar"
                    style={{ marginTop: 20, textAlign: "center" }}
                  >
                    <Statistic
                      title="采样率"
                      value={simResult.stats.Fs / 1e6}
                      precision={2}
                      suffix="MHz"
                      style={{ display: "inline-block", margin: "0 30px" }}
                    />
                    <Divider type="vertical" />
                    <Statistic
                      title="误码率 (BER)"
                      value={simResult.ber} // 后端返回的字段
                      precision={2}
                      valueStyle={{
                        // 智能配色：0误码显绿，有误码显红，未计算显灰
                        color:
                          simResult.ber === 0
                            ? "#52c41a" // 绿色 (完美)
                            : simResult.ber > 0
                              ? "#ff4d4f" // 红色 (有误码)
                              : "#999", // 灰色 (无效状态)
                        fontWeight: "bold",
                      }}
                      formatter={(val) => {
                        // 处理 MATLAB 返回的特殊状态码
                        if (val === -1) return "未计算 (N/A)";
                        if (val === -2) return "计算错误";
                        if (val === 0) return "0 (Perfect)";
                        // 科学计数法显示 (例如 1.25e-4)
                        return Number(val).toExponential(2);
                      }}
                      style={{ display: "inline-block", margin: "0 30px" }}
                    />
                    <Divider type="vertical" />
                    <Statistic
                      title="实际码率"
                      value={simResult.stats.CodeRate}
                      precision={3}
                      style={{ display: "inline-block", margin: "0 30px" }}
                    />
                    <Divider type="vertical" />
                    <Statistic
                      title="MATLAB耗时"
                      value={simResult.stats.ElapsedTime}
                      precision={3}
                      suffix="s"
                      style={{ display: "inline-block", margin: "0 30px" }}
                    />
                  </div>
                )}
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
