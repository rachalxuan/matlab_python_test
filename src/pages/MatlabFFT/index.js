import React, { useState, useEffect } from "react";
import {
  Card,
  Row,
  Col,
  Form,
  InputNumber,
  Button,
  Space,
  Divider,
  Spin,
  message,
  Typography,
  Select,
  Alert,
  Statistic,
  Table,
} from "antd";
import {
  PlayCircleOutlined,
  ReloadOutlined,
  DownloadOutlined,
  SettingOutlined,
  InfoCircleOutlined,
  CheckCircleOutlined,
  LineChartOutlined,
  BarChartOutlined,
  TableOutlined,
  WarningOutlined,
} from "@ant-design/icons";
import "./index.scss";

const { Title, Text } = Typography;
const { Option } = Select;

// 表格列定义
const dataColumns = [
  {
    title: "频率 (Hz)",
    dataIndex: "freq",
    key: "freq",
    sorter: (a, b) => a.freq - b.freq,
  },
  {
    title: "振幅",
    dataIndex: "amp",
    key: "amp",
    sorter: (a, b) => a.amp - b.amp,
  },
  {
    title: "相对强度 (%)",
    dataIndex: "relative",
    key: "relative",
    sorter: (a, b) => a.relative - b.relative,
  },
];

const MatlabFFT = () => {
  const [form] = Form.useForm();
  const [isLoading, setIsLoading] = useState(false);
  const [images, setImages] = useState({ fig1: null, fig2: null });
  const [fftData, setFftData] = useState(null);
  const [activeTab, setActiveTab] = useState("basic");
  const [dataViewMode, setDataViewMode] = useState("chart");
  const [connectionStatus, setConnectionStatus] = useState(null);
  const [processingStats, setProcessingStats] = useState(null);
  const [isElectron, setIsElectron] = useState(false);
  const [apiAvailable, setApiAvailable] = useState(false);

  // 检查是否在Electron环境中
  useEffect(() => {
    // 检查Electron特有的API
    const electronCheck = () => {
      const isElectronEnv =
        window &&
        (window.electronAPI !== undefined ||
          window.matlabAPI !== undefined ||
          navigator.userAgent.toLowerCase().indexOf("electron") > -1);

      console.log("环境检查:", {
        isElectronEnv,
        hasElectronAPI: window.electronAPI !== undefined,
        hasMatlabAPI: window.matlabAPI !== undefined,
        userAgent: navigator.userAgent,
      });

      setIsElectron(isElectronEnv);

      if (isElectronEnv) {
        // 检查具体哪个API可用
        if (window.matlabAPI) {
          setApiAvailable(true);
          console.log("使用 matlabAPI");
        } else if (window.electronAPI) {
          setApiAvailable(true);
          console.log("使用 electronAPI");
        }
      } else {
        // 浏览器环境，显示警告
        console.warn("当前在浏览器环境中运行，MATLAB功能不可用");
        message.info("当前在浏览器环境中，MATLAB功能仅在Electron应用中可用");
      }
    };

    // 延迟检查，确保window对象已完全加载
    const timer = setTimeout(electronCheck, 500);
    return () => clearTimeout(timer);
  }, []);

  // 初始参数
  const initialParams = {
    fs: 100,
    n: 1024,
    freq1: 50,
    freq2: 120,
    amp1: 1.0,
    amp2: 0.5,
  };

  // 监听MATLAB处理状态 - 只在Electron环境中设置
  useEffect(() => {
    if (!apiAvailable) return;

    const handleMatlabStatus = (status) => {
      console.log("MATLAB状态更新:", status);
      if (status.status === "processing") {
        message.loading({ content: status.message, key: "matlab-status" });
      } else if (status.status === "completed") {
        message.success({ content: status.message, key: "matlab-status" });
      } else if (status.status === "error") {
        message.error({ content: status.message, key: "matlab-status" });
      }
    };

    try {
      if (window.matlabAPI && window.matlabAPI.onMatlabStatus) {
        window.matlabAPI.onMatlabStatus(handleMatlabStatus);

        return () => {
          if (window.matlabAPI && window.matlabAPI.removeMatlabStatusListener) {
            window.matlabAPI.removeMatlabStatusListener(handleMatlabStatus);
          }
        };
      } else if (window.electronAPI) {
        // 如果只有旧版API，也可以添加状态监听
        // 这里根据你的实际API进行调整
        console.log("使用 electronAPI 状态监听");
      }
    } catch (error) {
      console.error("设置MATLAB状态监听器失败:", error);
    }
  }, [apiAvailable]);

  // 导出参数
  const exportParameters = () => {
    const params = form.getFieldsValue();
    const dataStr = JSON.stringify(params, null, 2);
    const dataUri =
      "data:application/json;charset=utf-8," + encodeURIComponent(dataStr);
    const link = document.createElement("a");
    link.href = dataUri;
    link.download = `fft_parameters_${Date.now()}.json`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    message.success("参数导出成功");
  };

  // 保存所有数据（包括图像和FFT数据）
  const saveAllData = async () => {
    if (!fftData) {
      message.warning("没有数据可保存");
      return;
    }

    try {
      // 在浏览器中直接下载
      const dataStr = JSON.stringify(
        {
          parameters: fftData.parameters || {},
          fft_data: fftData.fft_data || {},
          timestamp: new Date().toISOString(),
          processing_stats: processingStats || {},
        },
        null,
        2
      );

      const dataUri =
        "data:application/json;charset=utf-8," + encodeURIComponent(dataStr);
      const link = document.createElement("a");
      link.href = dataUri;
      link.download = `fft_data_${Date.now()}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      message.success("数据已保存到本地文件");
    } catch (error) {
      message.error(`保存失败: ${error.message}`);
    }
  };

  // 生成FFT图像 - 浏览器环境使用模拟数据
  const generateFFTImages = async (values) => {
    console.log("提交参数:", values);
    setIsLoading(true);
    setFftData(null);
    setProcessingStats(null);

    // 模拟处理时间
    await new Promise((resolve) => setTimeout(resolve, 1500));

    try {
      if (apiAvailable && isElectron) {
        // Electron环境中调用真实API
        let result;

        if (window.matlabAPI && window.matlabAPI.generateFFT) {
          result = await window.matlabAPI.generateFFT(values);
        } else if (window.electronAPI && window.electronAPI.generateFFTImages) {
          result = await window.electronAPI.generateFFTImages(values);
        } else {
          throw new Error("没有可用的FFT生成API");
        }

        if (result.success) {
          handleSuccessResult(result.data || result, values);
        } else {
          message.error(`生成失败: ${result.error || "未知错误"}`);
        }
      } else {
        // 浏览器环境中使用模拟数据
        const mockData = generateMockFFTData(values);
        handleSuccessResult(mockData, values);
        message.info(
          "浏览器环境中使用模拟数据，请在Electron应用中获取真实MATLAB计算结果"
        );
      }
    } catch (error) {
      console.error("调用错误:", error);
      message.error(`请求失败: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  // 处理成功结果
  const handleSuccessResult = (data, values) => {
    message.success("FFT分析完成！");

    // 如果有图像数据，设置图像
    if (data.images) {
      setImages(data.images || {});
    }

    // 设置FFT数据
    setFftData(data);

    // 设置处理统计
    setProcessingStats({
      timestamp: new Date().toISOString(),
      parameters: values,
      data_points: {
        f1: data.fft_data?.f1?.length || 0,
        f2: data.fft_data?.f2?.length || 0,
      },
      peak_amplitude: Math.max(...(data.fft_data?.mag1 || [0])),
    });

    console.log("FFT数据详情:", data);
  };

  // 生成模拟FFT数据
  const generateMockFFTData = (params) => {
    const { fs, n, freq1, freq2, amp1, amp2 } = params;
    const halfN = Math.floor(n / 2);

    // 生成频率数据
    const f1 = Array.from({ length: halfN }, (_, i) => i * (fs / n));
    const f2 = Array.from({ length: n }, (_, i) => i * (fs / n));

    // 生成振幅数据 - 在指定频率处有峰值
    const mag1 = f1.map((f) => {
      const dist1 = Math.abs(f - freq1);
      const dist2 = Math.abs(f - freq2);
      const peak1 = dist1 < 2 ? amp1 * Math.exp(-dist1 * 2) : 0;
      const peak2 = dist2 < 2 ? amp2 * Math.exp(-dist2 * 2) : 0;
      const noise = Math.random() * 0.05;
      return peak1 + peak2 + noise;
    });

    const mag2 = f2.map((f) => {
      const dist1 = Math.abs(f - freq1);
      const dist2 = Math.abs(f - freq2);
      const peak1 = dist1 < 2 ? amp1 * Math.exp(-dist1 * 2) : 0;
      const peak2 = dist2 < 2 ? amp2 * Math.exp(-dist2 * 2) : 0;
      const noise = Math.random() * 0.05;
      return peak1 + peak2 + noise;
    });

    return {
      success: true,
      parameters: params,
      fft_data: {
        f1,
        mag1,
        f2,
        mag2,
      },
      images: {
        // 模拟图像数据 - 在实际应用中这里是base64图片
        fig1: null,
        fig2: null,
      },
    };
  };

  // 下载图像
  const downloadImage = (imageKey) => {
    if (images[imageKey]) {
      const link = document.createElement("a");
      link.href = `data:image/png;base64,${images[imageKey]}`;
      link.download = `fft_${imageKey}_${Date.now()}.png`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      message.success("图像下载成功");
    } else {
      message.warning("暂无图像可下载");
    }
  };

  // 测试MATLAB连接
  const testMatlabConnection = async () => {
    if (!isElectron) {
      message.warning(
        "当前在浏览器环境中，MATLAB连接测试仅在Electron应用中可用"
      );
      return;
    }

    try {
      message.loading({
        content: "正在测试MATLAB连接...",
        key: "connection-test",
        duration: 0,
      });

      let result;
      if (window.matlabAPI && window.matlabAPI.testConnection) {
        result = await window.matlabAPI.testConnection();
      } else if (
        window.electronAPI &&
        window.electronAPI.testMatlabConnection
      ) {
        result = await window.electronAPI.testMatlabConnection();
      } else {
        throw new Error("没有可用的测试连接API");
      }

      if (result.success) {
        message.success({
          content: "✅ MATLAB连接测试成功！",
          key: "connection-test",
        });
        setConnectionStatus(result.data);
        console.log("连接测试结果:", result.data);
      } else {
        message.error({
          content: `❌ 测试失败: ${result.error || result.message}`,
          key: "connection-test",
        });
      }
    } catch (error) {
      message.error({
        content: `❌ 测试请求失败: ${error.message}`,
        key: "connection-test",
      });
    }
  };

  // 快速应用预设
  const applyPreset = (presetName) => {
    const presets = {
      基础测试: { fs: 100, n: 128, freq1: 10, freq2: 20, amp1: 1, amp2: 0.5 },
      高频测试: {
        fs: 1000,
        n: 1024,
        freq1: 100,
        freq2: 300,
        amp1: 1.5,
        amp2: 0.8,
      },
      低频测试: { fs: 50, n: 256, freq1: 5, freq2: 15, amp1: 0.8, amp2: 0.3 },
      大点数测试: {
        fs: 200,
        n: 2048,
        freq1: 30,
        freq2: 80,
        amp1: 1,
        amp2: 0.5,
      },
    };

    if (presets[presetName]) {
      form.setFieldsValue(presets[presetName]);
      message.info(`已应用 ${presetName} 预设`);
    }
  };

  // 准备表格数据
  const prepareTableData = () => {
    if (!fftData?.fft_data?.f1 || !fftData?.fft_data?.mag1) return [];

    const { f1, mag1 } = fftData.fft_data;
    const maxAmp = Math.max(...mag1);

    return f1.map((freq, index) => ({
      key: index,
      freq: Number(freq.toFixed(3)),
      amp: Number(mag1[index].toFixed(6)),
      relative: Number(((mag1[index] / maxAmp) * 100).toFixed(2)),
    }));
  };

  // 渲染数据视图
  const renderDataView = () => {
    if (!fftData) return null;

    switch (dataViewMode) {
      case "chart":
        return (
          <div className="data-chart">
            <Alert
              message="FFT数据图表"
              description="可以使用ECharts等图表库在这里绘制频谱图"
              type="info"
              showIcon
            />
            <div className="chart-placeholder">
              <LineChartOutlined style={{ fontSize: 48, color: "#1890ff" }} />
              <p>频谱图表视图</p>
              <small>这里可以集成ECharts图表</small>
            </div>
          </div>
        );

      case "table":
        const tableData = prepareTableData();
        return (
          <div className="data-table">
            <Table
              columns={dataColumns}
              dataSource={tableData}
              size="small"
              pagination={{ pageSize: 10 }}
              scroll={{ y: 300 }}
            />
          </div>
        );

      case "stats":
        return (
          <div className="data-stats">
            <Row gutter={16}>
              <Col span={8}>
                <Statistic
                  title="f1 数据点数"
                  value={fftData.fft_data?.f1?.length || 0}
                  prefix={<BarChartOutlined />}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="f2 数据点数"
                  value={fftData.fft_data?.f2?.length || 0}
                  prefix={<BarChartOutlined />}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="最大振幅"
                  value={Math.max(...(fftData.fft_data?.mag1 || [0])).toFixed(
                    6
                  )}
                  prefix={<LineChartOutlined />}
                />
              </Col>
            </Row>
            {fftData.parameters && (
              <div style={{ marginTop: 16 }}>
                <Alert
                  message="处理参数详情"
                  description={
                    <pre
                      style={{
                        fontSize: 12,
                        background: "#f6f8fa",
                        padding: 8,
                        borderRadius: 4,
                      }}
                    >
                      {JSON.stringify(fftData.parameters, null, 2)}
                    </pre>
                  }
                  type="info"
                  showIcon
                />
              </div>
            )}
          </div>
        );

      default:
        return null;
    }
  };

  return (
    <div className="matlab-fft-container">
      {/* 环境提示 */}
      {!isElectron && (
        <Alert
          message={
            <div style={{ display: "flex", alignItems: "center" }}>
              <WarningOutlined style={{ marginRight: 8 }} />
              <span>当前在浏览器环境中运行</span>
            </div>
          }
          description="MATLAB FFT功能仅在Electron桌面应用中可用。当前页面展示模拟数据。"
          type="warning"
          showIcon
          style={{ marginBottom: 16 }}
        />
      )}

      {/* 页面标题区域 */}
      <div className="page-title">
        <div className="title-content">
          <div className="title-left">
            <Title level={3}>MATLAB FFT 频谱分析</Title>
            <Text className="subtitle">快速傅里叶变换频谱分析与可视化</Text>
          </div>
          <div className="preset-buttons">
            {["基础测试", "高频测试", "低频测试", "大点数测试"].map(
              (preset) => (
                <Button
                  key={preset}
                  size="small"
                  onClick={() => applyPreset(preset)}
                >
                  {preset}
                </Button>
              )
            )}
          </div>
        </div>
      </div>

      <Row gutter={24} className="main-content">
        {/* 左侧参数区域 */}
        <Col span={10}>
          <div className="parameter-container">
            <Card
              className="parameter-card"
              bordered={false}
              title={
                <div className="card-header">
                  <SettingOutlined />
                  <span>参数配置</span>
                </div>
              }
              extra={
                <Button type="link" size="small" onClick={exportParameters}>
                  导出参数
                </Button>
              }
            >
              <Form
                form={form}
                layout="vertical"
                onFinish={generateFFTImages}
                initialValues={initialParams}
                className="parameter-form"
              >
                <div className="tab-nav">
                  <div
                    className={`tab-item ${activeTab === "basic" ? "active" : ""}`}
                    onClick={() => setActiveTab("basic")}
                  >
                    基本参数
                  </div>
                  <div
                    className={`tab-item ${activeTab === "advanced" ? "active" : ""}`}
                    onClick={() => setActiveTab("advanced")}
                  >
                    高级设置
                  </div>
                </div>

                {activeTab === "basic" ? (
                  <div className="form-content">
                    <Row gutter={16} className="form-row">
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span>
                              采样频率 (Hz)
                              <InfoCircleOutlined style={{ marginLeft: 4 }} />
                            </span>
                          }
                          name="fs"
                          rules={[
                            { required: true, message: "请输入采样频率" },
                          ]}
                          help="信号每秒采样次数"
                        >
                          <InputNumber
                            size="large"
                            placeholder="100"
                            min={1}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span>
                              数据点数 (N)
                              <InfoCircleOutlined style={{ marginLeft: 4 }} />
                            </span>
                          }
                          name="n"
                          rules={[
                            { required: true, message: "请输入数据点数" },
                            {
                              pattern: /^[0-9]*[02468]$/,
                              message: "必须是偶数",
                            },
                          ]}
                          help="必须是偶数，建议2的幂次"
                        >
                          <InputNumber
                            size="large"
                            placeholder="1024"
                            min={2}
                            step={2}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16} className="form-row">
                      <Col span={12}>
                        <Form.Item
                          label="频率1 (Hz)"
                          name="freq1"
                          rules={[{ required: true, message: "请输入频率1" }]}
                        >
                          <InputNumber
                            size="large"
                            placeholder="50"
                            min={0}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label="振幅1"
                          name="amp1"
                          rules={[{ required: true, message: "请输入振幅1" }]}
                        >
                          <InputNumber
                            size="large"
                            placeholder="1.0"
                            step={0.1}
                            min={0}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16} className="form-row">
                      <Col span={12}>
                        <Form.Item
                          label="频率2 (Hz)"
                          name="freq2"
                          rules={[{ required: true, message: "请输入频率2" }]}
                        >
                          <InputNumber
                            size="large"
                            placeholder="120"
                            min={0}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label="振幅2"
                          name="amp2"
                          rules={[{ required: true, message: "请输入振幅2" }]}
                        >
                          <InputNumber
                            size="large"
                            placeholder="0.5"
                            step={0.1}
                            min={0}
                            style={{ width: "100%" }}
                          />
                        </Form.Item>
                      </Col>
                    </Row>
                  </div>
                ) : (
                  <div className="form-content">
                    <Alert
                      message="高级设置"
                      description="MATLAB FFT函数当前仅支持基本参数，高级功能将在后续版本中添加"
                      type="info"
                      showIcon
                    />
                  </div>
                )}

                <Divider />

                <Space className="action-buttons" size="large">
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<PlayCircleOutlined />}
                    loading={isLoading}
                    size="large"
                    className="primary-btn"
                  >
                    {isLoading ? "分析中..." : "开始分析"}
                  </Button>
                  <Button
                    icon={<ReloadOutlined />}
                    onClick={() => {
                      form.resetFields();
                      setFftData(null);
                      setImages({ fig1: null, fig2: null });
                    }}
                    size="large"
                    className="secondary-btn"
                  >
                    重置
                  </Button>
                  <Button
                    onClick={testMatlabConnection}
                    size="large"
                    className="test-btn"
                    disabled={!isElectron}
                  >
                    测试连接
                  </Button>
                </Space>

                {/* 连接状态显示 */}
                {connectionStatus && (
                  <Alert
                    style={{ marginTop: 16 }}
                    message="连接状态"
                    description={
                      <div>
                        <p>
                          <CheckCircleOutlined style={{ color: "#52c41a" }} />{" "}
                          Python可用
                        </p>
                        <p>
                          <CheckCircleOutlined style={{ color: "#52c41a" }} />{" "}
                          MATLAB可用
                        </p>
                        {connectionStatus.fftData && (
                          <p>
                            数据点: f1={connectionStatus.fftData.f1_length}, f2=
                            {connectionStatus.fftData.f2_length}
                          </p>
                        )}
                      </div>
                    }
                    type="success"
                    showIcon
                  />
                )}
              </Form>
            </Card>
          </div>
        </Col>

        {/* 右侧图像显示区域 */}
        <Col span={14}>
          <Spin spinning={isLoading} tip="正在生成FFT数据...">
            <div className="image-display-area">
              <Row gutter={24}>
                {/* 全频谱分析 */}
                <Col span={12}>
                  <Card className="image-card" bordered={false}>
                    <div className="card-header">
                      <div>
                        <Title level={5}>全频谱分析</Title>
                        <Text className="subtitle">频率范围: 0 - fs Hz</Text>
                      </div>
                      <div className="card-actions">
                        <Button
                          type="text"
                          size="small"
                          icon={<DownloadOutlined />}
                          onClick={() => downloadImage("fig1")}
                          disabled={!images.fig1}
                          className="download-btn"
                        >
                          下载
                        </Button>
                      </div>
                    </div>

                    <div
                      className={`image-container ${images.fig1 ? "filled" : "empty"}`}
                    >
                      {images.fig1 ? (
                        <img
                          src={`data:image/png;base64,${images.fig1}`}
                          alt="全频谱分析"
                        />
                      ) : (
                        <>
                          <div className="placeholder-icon">📊</div>
                          <div className="placeholder-title">等待生成图像</div>
                          <div className="placeholder-description">
                            {isElectron ? (
                              <>
                                设置参数并点击
                                <span className="highlight">"开始分析"</span>
                                生成频谱图
                              </>
                            ) : (
                              <>请在Electron应用中获取真实MATLAB生成图像</>
                            )}
                          </div>
                        </>
                      )}
                    </div>
                  </Card>
                </Col>

                {/* Nyquist前频谱分析 */}
                <Col span={12}>
                  <Card className="image-card" bordered={false}>
                    <div className="card-header">
                      <div>
                        <Title level={5}>Nyquist前频谱分析</Title>
                        <Text className="subtitle">频率范围: 0 - fs/2 Hz</Text>
                      </div>
                      <div className="card-actions">
                        <Button
                          type="text"
                          size="small"
                          icon={<DownloadOutlined />}
                          onClick={() => downloadImage("fig2")}
                          disabled={!images.fig2}
                          className="download-btn"
                        >
                          下载
                        </Button>
                      </div>
                    </div>

                    <div
                      className={`image-container ${images.fig2 ? "filled" : "empty"}`}
                    >
                      {images.fig2 ? (
                        <img
                          src={`data:image/png;base64,${images.fig2}`}
                          alt="Nyquist前频谱分析"
                        />
                      ) : (
                        <>
                          <div className="placeholder-icon">📈</div>
                          <div className="placeholder-title">等待生成图像</div>
                          <div className="placeholder-description">
                            {isElectron ? (
                              <>
                                设置参数并点击
                                <span className="highlight">"开始分析"</span>
                                生成频谱图
                              </>
                            ) : (
                              <>请在Electron应用中获取真实MATLAB生成图像</>
                            )}
                          </div>
                        </>
                      )}
                    </div>
                  </Card>
                </Col>
              </Row>

              {/* FFT数据显示区域 */}
              {fftData && (
                <Card
                  className="data-display-card"
                  style={{ marginTop: 24 }}
                  title={
                    <div className="card-header">
                      <TableOutlined />
                      <span>FFT数据分析</span>
                      <div className="data-view-controls">
                        <Button.Group size="small">
                          <Button
                            type={
                              dataViewMode === "chart" ? "primary" : "default"
                            }
                            icon={<LineChartOutlined />}
                            onClick={() => setDataViewMode("chart")}
                          >
                            图表
                          </Button>
                          <Button
                            type={
                              dataViewMode === "table" ? "primary" : "default"
                            }
                            icon={<TableOutlined />}
                            onClick={() => setDataViewMode("table")}
                          >
                            表格
                          </Button>
                          <Button
                            type={
                              dataViewMode === "stats" ? "primary" : "default"
                            }
                            icon={<BarChartOutlined />}
                            onClick={() => setDataViewMode("stats")}
                          >
                            统计
                          </Button>
                        </Button.Group>
                        <Button
                          type="primary"
                          size="small"
                          icon={<DownloadOutlined />}
                          onClick={saveAllData}
                          style={{ marginLeft: 8 }}
                        >
                          保存数据
                        </Button>
                      </div>
                    </div>
                  }
                >
                  {renderDataView()}

                  {/* 环境提示 */}
                  {!isElectron && (
                    <Alert
                      style={{ marginTop: 16 }}
                      message="模拟数据"
                      description="当前显示的是基于参数的模拟FFT数据。真实MATLAB计算结果仅在Electron桌面应用中可用。"
                      type="info"
                      showIcon
                    />
                  )}
                </Card>
              )}
            </div>
          </Spin>
        </Col>
      </Row>

      {/* 底部提示信息 */}
      <div className="bottom-hint">
        <InfoCircleOutlined />
        <span>
          {isElectron
            ? "MATLAB FFT分析基于您的参数设置生成频谱图像，并返回详细的FFT数据。确保参数设置合理以获得最佳分析结果。"
            : "当前在浏览器环境中，展示模拟FFT数据。真实MATLAB FFT分析功能仅在Electron桌面应用中可用。"}
        </span>
      </div>
    </div>
  );
};

export default MatlabFFT;
