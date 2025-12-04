import React, { useState } from "react";
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
} from "antd";
import {
  PlayCircleOutlined,
  ReloadOutlined,
  DownloadOutlined,
  SettingOutlined,
  InfoCircleOutlined,
} from "@ant-design/icons";
import "./index.scss"; // 引入SCSS文件

const { Title, Text } = Typography;
const { Option } = Select;

const MatlabFFT = () => {
  const [form] = Form.useForm();
  const [isLoading, setIsLoading] = useState(false);
  const [images, setImages] = useState({ fig1: null, fig2: null });
  const [activeTab, setActiveTab] = useState("basic");

  // 初始参数
  const initialParams = {
    fs: 100,
    n: 1024,
    freq1: 50,
    freq2: 120,
    amp1: 1.0,
    amp2: 0.5,
    windowType: "hamming",
  };

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

  // 生成FFT图像
  const generateFFTImages = async (values) => {
    console.log("参数:", values);
    setIsLoading(true);
    try {
      const result = await window.electronAPI.generateFFTImages(values);
      if (result.success) {
        message.success("FFT分析完成！");
        setImages(result.data.images || {});

        if (result.data.parameters) {
          console.log("MATLAB返回的参数:", result.data.parameters);
        }
      } else {
        message.error(`生成失败: ${result.error}`);
      }
    } catch (error) {
      console.error("调用错误:", error);
      message.error(`请求失败: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
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

  // 快速应用预设
  const applyPreset = (presetName) => {
    const presets = {
      音频分析: {
        fs: 44100,
        n: 2048,
        freq1: 440,
        freq2: 880,
        amp1: 1,
        amp2: 0.7,
      },
      振动分析: { fs: 1000, n: 1024, freq1: 10, freq2: 50, amp1: 1, amp2: 0.3 },
      通信信号: {
        fs: 10000,
        n: 4096,
        freq1: 1000,
        freq2: 3000,
        amp1: 1,
        amp2: 0.5,
      },
    };

    if (presets[presetName]) {
      form.setFieldsValue(presets[presetName]);
      message.info(`已应用 ${presetName} 预设`);
    }
  };

  return (
    <div className="matlab-fft-container">
      {/* 页面标题区域 */}
      <div className="page-title">
        <div className="title-content">
          <div className="title-left">
            <Title level={3}>MATLAB FFT 频谱分析</Title>
            <Text className="subtitle">快速傅里叶变换频谱分析与可视化</Text>
          </div>
          <div className="preset-buttons">
            {["音频分析", "振动分析", "通信信号"].map((preset) => (
              <Button
                key={preset}
                size="small"
                onClick={() => applyPreset(preset)}
              >
                {preset}
              </Button>
            ))}
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
                              <InfoCircleOutlined />
                            </span>
                          }
                          name="fs"
                          rules={[{ required: true }]}
                        >
                          <InputNumber size="large" placeholder="1000" />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span>
                              数据点数
                              <InfoCircleOutlined />
                            </span>
                          }
                          name="n"
                          rules={[{ required: true }]}
                        >
                          <InputNumber size="large" placeholder="1024" />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16} className="form-row">
                      <Col span={12}>
                        <Form.Item label="频率1 (Hz)" name="freq1">
                          <InputNumber size="large" placeholder="50" />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item label="振幅1" name="amp1">
                          <InputNumber
                            size="large"
                            placeholder="1.0"
                            step={0.1}
                          />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16} className="form-row">
                      <Col span={12}>
                        <Form.Item label="频率2 (Hz)" name="freq2">
                          <InputNumber size="large" placeholder="120" />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item label="振幅2" name="amp2">
                          <InputNumber
                            size="large"
                            placeholder="0.5"
                            step={0.1}
                          />
                        </Form.Item>
                      </Col>
                    </Row>
                  </div>
                ) : (
                  <div className="form-content">
                    <Form.Item label="窗函数类型" name="windowType">
                      <Select size="large" defaultValue="hamming">
                        <Option value="hamming">汉明窗</Option>
                        <Option value="hann">汉宁窗</Option>
                        <Option value="rectangular">矩形窗</Option>
                      </Select>
                    </Form.Item>
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
                    onClick={() => form.resetFields()}
                    size="large"
                    className="secondary-btn"
                  >
                    重置
                  </Button>
                  <Button
                    onClick={async () => {
                      try {
                        const result =
                          await window.electronAPI.testMatlabConnection();
                        if (result.success) {
                          message.success("✅ MATLAB连接测试成功！");
                          console.log("测试结果:", result.data);
                        } else {
                          message.error(`❌ 测试失败: ${result.error}`);
                        }
                      } catch (error) {
                        message.error(`❌ 测试请求失败: ${error.message}`);
                      }
                    }}
                    size="large"
                    className="test-btn"
                  >
                    测试连接
                  </Button>
                </Space>
              </Form>
            </Card>
          </div>
        </Col>

        {/* 右侧图像显示区域 */}
        <Col span={14}>
          <Spin spinning={isLoading} tip="正在生成FFT图像...">
            <div className="image-display-area">
              <Row gutter={24}>
                {/* 全频谱分析 */}
                <Col span={12}>
                  <Card className="image-card" bordered={false}>
                    <div className="card-header">
                      <div>
                        <Title level={5}>全频谱分析</Title>
                        <Text className="subtitle">
                          0 - fs/2 频率范围，线性坐标
                        </Text>
                      </div>
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
                            设置参数并点击
                            <span className="highlight">"开始分析"</span>
                            生成频谱图
                          </div>
                        </>
                      )}
                    </div>
                  </Card>
                </Col>

                {/* Nyquist频率分析 */}
                <Col span={12}>
                  <Card className="image-card" bordered={false}>
                    <div className="card-header">
                      <div>
                        <Title level={5}>Nyquist频率分析</Title>
                        <Text className="subtitle">
                          0 - fs/2 频率范围，对数坐标
                        </Text>
                      </div>
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

                    <div
                      className={`image-container ${images.fig2 ? "filled" : "empty"}`}
                    >
                      {images.fig2 ? (
                        <img
                          src={`data:image/png;base64,${images.fig2}`}
                          alt="Nyquist频率分析"
                        />
                      ) : (
                        <>
                          <div className="placeholder-icon">📈</div>
                          <div className="placeholder-title">等待生成图像</div>
                          <div className="placeholder-description">
                            设置参数并点击
                            <span className="highlight">"开始分析"</span>
                            生成频谱图
                          </div>
                        </>
                      )}
                    </div>
                  </Card>
                </Col>
              </Row>
            </div>
          </Spin>
        </Col>
      </Row>

      {/* 底部提示信息 */}
      <div className="bottom-hint">
        <InfoCircleOutlined />
        MATLAB
        FFT分析基于您的参数设置生成频谱图像，确保参数设置合理以获得最佳分析结果。
      </div>
    </div>
  );
};

export default MatlabFFT;
