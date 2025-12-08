import React, { useState, useEffect } from "react";
import {
  Card,
  Row,
  Col,
  Form,
  InputNumber,
  Button,
  Space,
  Spin,
  message,
  Typography,
  Alert,
  Statistic,
  Table,
  Tag,
  Tooltip,
} from "antd";
import {
  PlayCircleOutlined,
  ReloadOutlined,
  DownloadOutlined,
  SettingOutlined,
  BarChartOutlined,
  AreaChartOutlined,
  SaveOutlined,
  ThunderboltOutlined,
  ExperimentOutlined,
  InfoCircleOutlined,
} from "@ant-design/icons";
import EChartsFFT from "@/components/EChartsFFT";
import "./index.scss";
// 引入 Dayjs 方便处理时间戳
import dayjs from "dayjs";

const { Title, Text } = Typography;

// 1. 新增：通用的数组扁平化工具函数
// 解决 MATLAB 返回 [[1],[2]] 这种列向量导致前端无法读取的问题
const flattenData = (data) => {
  if (!Array.isArray(data)) return [];
  // 如果是空数组，直接返回
  if (data.length === 0) return [];
  // 如果第一项是数组（说明是二维数组），则展平
  if (Array.isArray(data[0])) {
    return data.map((item) => item[0]);
  }
  // 否则本身就是一维数组，直接返回
  return data;
};

// 2. 修改：prepareTableData 函数
const prepareTableData = (fftData) => {
  if (!fftData?.fft_data) return [];

  // 使用扁平化处理
  const f1 = flattenData(fftData.fft_data.f1);
  const mag1 = flattenData(fftData.fft_data.mag1);

  if (f1.length === 0 || mag1.length === 0) return [];

  const max = Math.max(...mag1);

  return f1
    .map((f, i) => ({
      key: i,
      freq: f,
      amp: mag1[i],
      relative: max > 0 ? (mag1[i] / max) * 100 : 0,
    }))
    .filter((item) => item.amp > max * 0.01)
    .sort((a, b) => b.amp - a.amp);
};
// // 辅助函数：准备表格数据
// const prepareTableData = (fftData) => {
//   // 安全检查：如果数据不存在，返回空数组
//   if (!fftData?.fft_data?.f1 || !fftData?.fft_data?.mag1) return [];

//   const { f1, mag1 } = fftData.fft_data;
//   const max = Math.max(...mag1);

//   return f1
//     .map((f, i) => ({
//       key: i,
//       freq: f,
//       amp: mag1[i],
//       relative: (mag1[i] / max) * 100,
//     }))
//     .filter((item) => item.amp > max * 0.01) // 过滤掉噪音
//     .sort((a, b) => b.amp - a.amp); // 按振幅排序
// };

// 表格列定义
const dataColumns = [
  {
    title: "频率 (Hz)",
    dataIndex: "freq",
    key: "freq",
    width: 150,
    sorter: (a, b) => a.freq - b.freq,
    render: (val) => <Text strong>{val?.toFixed(2)}</Text>,
  },
  {
    title: "振幅 (Magnitude)",
    dataIndex: "amp",
    key: "amp",
    width: 150,
    sorter: (a, b) => a.amp - b.amp,
    render: (val) => val?.toFixed(6),
  },
  {
    title: "强度占比",
    dataIndex: "relative",
    key: "relative",
    sorter: (a, b) => a.relative - b.relative,
    render: (val) => (
      <div style={{ width: "100px" }}>
        <div
          style={{
            height: "6px",
            background: "#f0f0f0",
            borderRadius: "3px",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              width: `${val?.toFixed(2)}%`,
              height: "100%",
              background: val > 50 ? "#ff4d4f" : "#1890ff",
            }}
          />
        </div>
        <span style={{ fontSize: "12px", color: "#8c8c8c" }}>
          {val?.toFixed(2)}%
        </span>
      </div>
    ),
  },
];

const MatlabFFT = () => {
  const [form] = Form.useForm();
  const [isLoading, setIsLoading] = useState(false);
  const [images, setImages] = useState({ fig1: null, fig2: null });
  const [fftData, setFftData] = useState(null);
  const [isElectron, setIsElectron] = useState(false);

  // 初始参数
  const initialParams = {
    fs: 100,
    n: 1024,
    freq1: 10,
    freq2: 20,
    amp1: 1.0,
    amp2: 0.5,
  };

  // 环境检查
  useEffect(() => {
    const isElectronEnv = window && window.matlabAPI !== undefined;
    setIsElectron(isElectronEnv);
  }, []);

  // 状态监听
  useEffect(() => {
    if (!isElectron) return;
    const handleStatus = (status) => {
      if (status.status === "processing")
        message.loading({ content: status.message, key: "proc" });
      else if (status.status === "completed")
        message.success({ content: status.message, key: "proc" });
      else if (status.status === "error")
        message.error({ content: status.message, key: "proc" });
    };
    if (window.matlabAPI && window.matlabAPI.onMatlabStatus) {
      window.matlabAPI.onMatlabStatus(handleStatus);
      return () => {
        if (window.matlabAPI && window.matlabAPI.removeMatlabStatusListener) {
          window.matlabAPI.removeMatlabStatusListener(handleStatus);
        }
      };
    }
  }, [isElectron]);

  // 生成 FFT 核心逻辑
  const handleAnalyze = async (values) => {
    setIsLoading(true);
    setFftData(null); // 清空旧数据

    try {
      let result;
      if (isElectron) {
        // Electron 环境：调用真实 Python/MATLAB
        const rawResponse = await window.matlabAPI.generateFFT(values);
        result = rawResponse.data;
        // === 调试代码：查看后端到底返回了什么 ===
        console.log("Electron 返回结果:", result);

        if (result.fft_data) {
          console.log("FFT 数据长度:", result.fft_data.f1?.length);
        } else {
          console.warn("FFT 数据丢失！");
        }

        if (result.images) {
          console.log("图片 Key:", Object.keys(result.images));
          console.log("Fig1 数据长度:", result.images.fig1?.length);
        } else {
          console.warn("图片数据丢失！");
        }
        // ========================================
      } else {
        // 浏览器环境：模拟数据
        await new Promise((r) => setTimeout(r, 800));
        result = generateMockData(values);
        message.warning("浏览器演示模式：使用模拟数据");
      }

      if (result && result.success) {
        setImages(result.images || {});
        setFftData(result);
        message.success(`分析完成`);
      } else {
        message.error(result?.error || "分析失败");
      }
    } catch (error) {
      message.error(`调用错误: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  // 生成模拟数据 (仅用于浏览器演示)
  const generateMockData = (params) => {
    const { fs, n, freq1, freq2, amp1, amp2 } = params;
    const halfN = Math.floor(n / 2);
    // 模拟频域数据 (X轴: 频率, Y轴: 幅值)
    const f1 = Array.from({ length: halfN }, (_, i) => i * (fs / n));
    const mag1 = f1.map((f) => {
      // 简单模拟两个峰值
      const noise = Math.random() * 0.02;
      const peak1 = Math.abs(f - freq1) < 1 ? amp1 : 0;
      const peak2 = Math.abs(f - freq2) < 1 ? amp2 : 0;
      return noise + peak1 + peak2;
    });

    return {
      success: true,
      parameters: params,
      fft_data: { f1, mag1 }, // 关键数据结构
      images: { fig1: null, fig2: null },
    };
  };

  // 下载数据
  const saveJSON = () => {
    if (!fftData) return;
    const blob = new Blob([JSON.stringify(fftData, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `fft_analysis_${dayjs().format("YYYYMMDD_HHmmss")}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // ----------------------------------------------------
  // 准备 ECharts 数据
  // ----------------------------------------------------
  // 3. 修改：prepareChartData 函数
  const prepareChartData = () => {
    if (!fftData?.fft_data) return null;

    // 使用扁平化处理
    const f1 = flattenData(fftData.fft_data.f1);
    const mag1 = flattenData(fftData.fft_data.mag1);

    if (f1.length === 0) return null;

    const params = fftData.parameters || {};

    return {
      frequencyDomain: {
        frequencies: f1,
        amplitudes: mag1,
      },
      timeDomain: null,
      statistics: {
        sample_rate: params.fs || 0,
      },
    };
  };
  //   const prepareChartData = () => {
  //     // 增加数据存在性检查
  //     if (
  //       !fftData ||
  //       !fftData.fft_data ||
  //       !fftData.fft_data.f1 ||
  //       !fftData.fft_data.mag1
  //     ) {
  //       return null;
  //     }

  //     const { f1, mag1 } = fftData.fft_data;
  //     const params = fftData.parameters || {};

  //     return {
  //       frequencyDomain: {
  //         frequencies: f1,
  //         amplitudes: mag1,
  //       },
  //       timeDomain: null,
  //       statistics: {
  //         sample_rate: params.fs || 0,
  //       },
  //     };
  //   };

  const tableData = prepareTableData(fftData);

  return (
    <div className="matlab-fft-container">
      {/* 头部 */}
      <div className="page-header">
        <div className="header-title">
          <h2>频谱分析工作台</h2>
          <span>MATLAB Engine & Electron Integration</span>
        </div>
        <Space>
          <Button
            icon={<ThunderboltOutlined />}
            onClick={() => form.setFieldsValue(initialParams)}
          >
            恢复默认
          </Button>
          <Button
            type="primary"
            ghost
            icon={<SaveOutlined />}
            onClick={saveJSON}
            disabled={!fftData}
          >
            导出数据
          </Button>
        </Space>
      </div>

      <div className="main-layout">
        {/* 左侧控制面板 */}
        <div className="control-panel">
          <Card title="参数配置" bordered={false}>
            <Form
              form={form}
              layout="vertical"
              onFinish={handleAnalyze}
              initialValues={initialParams}
            >
              <div className="form-section-title">系统参数</div>
              <Row gutter={12}>
                <Col span={12}>
                  <Form.Item
                    name="fs"
                    label={
                      <Tooltip title="信号每秒采样次数">
                        采样频率 (Hz) <InfoCircleOutlined />
                      </Tooltip>
                    }
                  >
                    <InputNumber style={{ width: "100%" }} min={1} />
                  </Form.Item>
                </Col>
                <Col span={12}>
                  <Form.Item
                    name="n"
                    label={
                      <Tooltip title="FFT计算点数，建议是2的幂次">
                        采样点数 (N) <InfoCircleOutlined />
                      </Tooltip>
                    }
                  >
                    <InputNumber style={{ width: "100%" }} min={2} step={2} />
                  </Form.Item>
                </Col>
              </Row>

              <div className="form-section-title">信号源 1</div>
              <Row gutter={12}>
                <Col span={12}>
                  <Form.Item name="freq1" label="频率 (Hz)">
                    <InputNumber style={{ width: "100%" }} min={0} />
                  </Form.Item>
                </Col>
                <Col span={12}>
                  <Form.Item name="amp1" label="振幅">
                    <InputNumber style={{ width: "100%" }} min={0} step={0.1} />
                  </Form.Item>
                </Col>
              </Row>

              <div className="form-section-title">信号源 2</div>
              <Row gutter={12}>
                <Col span={12}>
                  <Form.Item name="freq2" label="频率 (Hz)">
                    <InputNumber style={{ width: "100%" }} min={0} />
                  </Form.Item>
                </Col>
                <Col span={12}>
                  <Form.Item name="amp2" label="振幅">
                    <InputNumber style={{ width: "100%" }} min={0} step={0.1} />
                  </Form.Item>
                </Col>
              </Row>

              <Button
                type="primary"
                htmlType="submit"
                className="submit-btn"
                block
                loading={isLoading}
                icon={<ExperimentOutlined />}
              >
                {isLoading ? "正在计算..." : "开始 FFT 分析"}
              </Button>
            </Form>
          </Card>
        </div>

        {/* 右侧结果展示 */}
        <div className="results-panel">
          {/* ECharts 交互图表 */}
          <Card bordered={false} className="result-card">
            <div className="card-title">
              <h4>
                <BarChartOutlined style={{ color: "#1677ff" }} /> 交互式频谱图
                (Interactive Spectrum)
              </h4>
              {fftData && (
                <Tag color="green">
                  计算完成{" "}
                  {fftData.timestamp
                    ? dayjs(fftData.timestamp).format("HH:mm:ss")
                    : ""}
                </Tag>
              )}
            </div>
            <div className="chart-wrapper">
              {fftData ? (
                <EChartsFFT fftData={prepareChartData()} loading={isLoading} />
              ) : (
                <div
                  style={{
                    height: "400px",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "#ccc",
                    flexDirection: "column",
                  }}
                >
                  <AreaChartOutlined
                    style={{ fontSize: 48, marginBottom: 16 }}
                  />
                  <p>请输入参数并点击开始分析以生成图表</p>
                </div>
              )}
            </div>
          </Card>

          {/* 统计数据 & 表格 - 修复了这里的崩溃点 */}
          {fftData && (
            <Card bordered={false} className="result-card">
              <div className="stat-grid">
                <Statistic
                  title="峰值频率 (Peak 1)"
                  value={form.getFieldValue("freq1")}
                  suffix="Hz"
                />
                <Statistic
                  title="峰值频率 (Peak 2)"
                  value={form.getFieldValue("freq2")}
                  suffix="Hz"
                />
                <Statistic
                  title="最大能量"
                  // 使用 flattenData 确保 Math.max 接收的是一维数组
                  value={
                    fftData?.fft_data?.mag1
                      ? Math.max(...flattenData(fftData.fft_data.mag1))
                      : 0
                  }
                  precision={4}
                  valueStyle={{ color: "#3f8600" }}
                />
              </div>
              <Table
                dataSource={tableData}
                columns={dataColumns}
                size="small"
                pagination={{ pageSize: 5 }}
                rowKey="key"
              />
            </Card>
          )}

          {/* MATLAB 原图 */}
          <div className="image-grid">
            <div className="image-box">
              {images.fig1 ? (
                <img
                  src={`data:image/png;base64,${images.fig1}`}
                  alt="Spectrum Full"
                />
              ) : (
                <div className="empty-state">
                  <InfoCircleOutlined />
                  <p>MATLAB 全频谱图</p>
                </div>
              )}
            </div>
            <div className="image-box">
              {images.fig2 ? (
                <img
                  src={`data:image/png;base64,${images.fig2}`}
                  alt="Spectrum Nyquist"
                />
              ) : (
                <div className="empty-state">
                  <InfoCircleOutlined />
                  <p>MATLAB Nyquist 图</p>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MatlabFFT;
