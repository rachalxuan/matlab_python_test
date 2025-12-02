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
  Tabs,
  Collapse,
  Typography,
  Select,
} from "antd";
import {
  PlayCircleOutlined,
  ReloadOutlined,
  DownloadOutlined,
  SettingOutlined,
  LineChartOutlined,
  InfoCircleOutlined,
} from "@ant-design/icons";

const { TabPane } = Tabs;
const { Panel } = Collapse;
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
    setIsLoading(true);
    try {
      // 这里调用你的Electron API
      const result = await window.electronAPI.generateFFTImages(values);
      if (result.success) {
        message.success("FFT分析完成！");
        // 注意：新的API返回的结构是 result.data.images，不是 result.images
        setImages(result.data.images || {});

        // 如果有计算参数，可以记录
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
    <div
      style={{
        padding: "24px",
        background: "#f5f7fa",
        minHeight: "80vh",
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial',
        // boxSizing: "border-box",
        // margin: "0 auto",
      }}
    >
      {/* 页面标题区域 */}
      <div
        style={{
          marginBottom: "24px",
          padding: "16px 24px",
          background: "white",
          borderRadius: "8px",
          boxShadow: "0 2px 8px rgba(0, 0, 0, 0.06)",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div>
            <Title level={3} style={{ margin: 0, color: "#1890ff" }}>
              MATLAB FFT 频谱分析
            </Title>
            <Text type="secondary" style={{ fontSize: "14px" }}>
              快速傅里叶变换频谱分析与可视化
            </Text>
          </div>
          <div style={{ display: "flex", gap: "8px" }}>
            {["音频分析", "振动分析", "通信信号"].map((preset) => (
              <Button
                key={preset}
                size="small"
                onClick={() => applyPreset(preset)}
                style={{ fontSize: "12px" }}
              >
                {preset}
              </Button>
            ))}
          </div>
        </div>
      </div>

      <Row gutter={24}>
        {/* 左侧参数区域 - 调整高度与右侧对齐 */}
        <Col span={10}>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              height: "100%",
              gap: "20px",
            }}
          >
            {/* 参数配置卡片 */}
            <Card
              title={
                <div style={{ display: "flex", alignItems: "center" }}>
                  <SettingOutlined
                    style={{ marginRight: "8px", color: "#1890ff" }}
                  />
                  <span style={{ fontSize: "16px", fontWeight: "500" }}>
                    参数配置
                  </span>
                </div>
              }
              bordered={false}
              style={{
                flex: 1,
                borderRadius: "8px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.08)",
                display: "flex",
                flexDirection: "column",
              }}
              bodyStyle={{
                flex: 1,
                display: "flex",
                flexDirection: "column",
                padding: "24px",
              }}
            >
              <Form
                form={form}
                layout="vertical"
                onFinish={generateFFTImages}
                initialValues={initialParams}
                style={{ flex: 1, display: "flex", flexDirection: "column" }}
              >
                <div
                  style={{
                    display: "flex",
                    marginBottom: "20px",
                    borderBottom: "1px solid #f0f0f0",
                  }}
                >
                  <div
                    style={{
                      padding: "8px 16px",
                      cursor: "pointer",
                      borderBottom:
                        activeTab === "basic" ? "2px solid #1890ff" : "none",
                      color: activeTab === "basic" ? "#1890ff" : "#666",
                      fontWeight: activeTab === "basic" ? "500" : "400",
                      fontSize: "14px",
                    }}
                    onClick={() => setActiveTab("basic")}
                  >
                    基本参数
                  </div>
                  <div
                    style={{
                      padding: "8px 16px",
                      cursor: "pointer",
                      borderBottom:
                        activeTab === "advanced" ? "2px solid #1890ff" : "none",
                      color: activeTab === "advanced" ? "#1890ff" : "#666",
                      fontWeight: activeTab === "advanced" ? "500" : "400",
                      fontSize: "14px",
                    }}
                    onClick={() => setActiveTab("advanced")}
                  >
                    高级设置
                  </div>
                </div>

                {activeTab === "basic" ? (
                  <div style={{ flex: 1, marginBottom: "24px" }}>
                    <Row gutter={16}>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              采样频率 (Hz)
                              <InfoCircleOutlined
                                style={{
                                  marginLeft: "4px",
                                  fontSize: "12px",
                                  color: "#bfbfbf",
                                }}
                              />
                            </span>
                          }
                          name="fs"
                          rules={[{ required: true }]}
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="1000"
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              数据点数
                              <InfoCircleOutlined
                                style={{
                                  marginLeft: "4px",
                                  fontSize: "12px",
                                  color: "#bfbfbf",
                                }}
                              />
                            </span>
                          }
                          name="n"
                          rules={[{ required: true }]}
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="1024"
                          />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16}>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              频率1 (Hz)
                            </span>
                          }
                          name="freq1"
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="50"
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              振幅1
                            </span>
                          }
                          name="amp1"
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="1.0"
                            step={0.1}
                          />
                        </Form.Item>
                      </Col>
                    </Row>

                    <Row gutter={16}>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              频率2 (Hz)
                            </span>
                          }
                          name="freq2"
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="120"
                          />
                        </Form.Item>
                      </Col>
                      <Col span={12}>
                        <Form.Item
                          label={
                            <span
                              style={{ fontSize: "13px", fontWeight: "500" }}
                            >
                              振幅2
                            </span>
                          }
                          name="amp2"
                        >
                          <InputNumber
                            style={{ width: "100%" }}
                            size="large"
                            placeholder="0.5"
                            step={0.1}
                          />
                        </Form.Item>
                      </Col>
                    </Row>
                  </div>
                ) : (
                  <div style={{ flex: 1, marginBottom: "24px" }}>
                    <Form.Item
                      label={
                        <span style={{ fontSize: "13px", fontWeight: "500" }}>
                          窗函数类型
                        </span>
                      }
                      name="windowType"
                    >
                      <Select size="large" defaultValue="hamming">
                        <Option value="hamming">汉明窗</Option>
                        <Option value="hann">汉宁窗</Option>
                        <Option value="rectangular">矩形窗</Option>
                      </Select>
                    </Form.Item>
                  </div>
                )}

                {/* 计算性能参数 */}

                <Divider style={{ margin: "16px 0" }} />

                {/* 操作按钮 */}
                {/* 操作按钮 */}
                <Space
                  style={{
                    width: "100%",
                    justifyContent: "center",
                    marginTop: "auto",
                  }}
                  size="large"
                >
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<PlayCircleOutlined />}
                    loading={isLoading}
                    size="large"
                    style={{
                      minWidth: "140px",
                      height: "44px",
                      borderRadius: "6px",
                      fontSize: "16px",
                    }}
                  >
                    {isLoading ? "分析中..." : "开始分析"}
                  </Button>
                  <Button
                    icon={<ReloadOutlined />}
                    onClick={() => form.resetFields()}
                    size="large"
                    style={{
                      minWidth: "100px",
                      height: "44px",
                      borderRadius: "6px",
                      fontSize: "16px",
                    }}
                  >
                    重置
                  </Button>
                  {/* 添加测试连接按钮 */}
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
                    style={{
                      minWidth: "120px",
                      height: "44px",
                      borderRadius: "6px",
                      fontSize: "16px",
                    }}
                  >
                    测试连接
                  </Button>
                </Space>
              </Form>
            </Card>

            {/* 更多操作卡片 */}
          </div>
        </Col>

        {/* 右侧图像显示区域 */}
        <Col span={14}>
          <Spin spinning={isLoading} tip="正在生成FFT图像...">
            <div
              style={{
                height: "100%",
                display: "flex",
                flexDirection: "column",
                gap: "24px",
              }}
            >
              <Row gutter={24}>
                {/* 全频谱分析 */}
                <Col span={12}>
                  <Card
                    bordered={false}
                    style={{
                      height: "420px",
                      borderRadius: "8px",
                      boxShadow: "0 2px 8px rgba(0, 0, 0, 0.06)",
                      display: "flex",
                      flexDirection: "column",
                    }}
                    bodyStyle={{
                      flex: 1,
                      display: "flex",
                      flexDirection: "column",
                      padding: "24px",
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        marginBottom: "20px",
                      }}
                    >
                      <div>
                        <Title
                          level={5}
                          style={{ margin: 0, color: "#1f2937" }}
                        >
                          全频谱分析
                        </Title>
                        <Text type="secondary" style={{ fontSize: "12px" }}>
                          0 - fs/2 频率范围，线性坐标
                        </Text>
                      </div>
                      <Button
                        type="text"
                        size="small"
                        icon={<DownloadOutlined />}
                        onClick={() => downloadImage("fig1")}
                        disabled={!images.fig1}
                        style={{ fontSize: "12px" }}
                      >
                        下载
                      </Button>
                    </div>

                    <div
                      style={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        background: "#fafafa",
                        borderRadius: "8px",
                        border: "1px dashed #d9d9d9",
                        padding: "20px",
                      }}
                    >
                      {images.fig1 ? (
                        <div
                          style={{
                            width: "100%",
                            height: "100%",
                            textAlign: "center",
                          }}
                        >
                          <img
                            src={`data:image/png;base64,${images.fig1}`}
                            alt="全频谱分析"
                            style={{
                              maxWidth: "100%",
                              maxHeight: "100%",
                              objectFit: "contain",
                            }}
                          />
                        </div>
                      ) : (
                        <div
                          style={{
                            textAlign: "center",
                            color: "#8c8c8c",
                            width: "100%",
                          }}
                        >
                          <div
                            style={{
                              width: "64px",
                              height: "64px",
                              borderRadius: "50%",
                              background: "#f0f0f0",
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "center",
                              margin: "0 auto 16px",
                              color: "#bfbfbf",
                              fontSize: "20px",
                            }}
                          >
                            📊
                          </div>
                          <div
                            style={{
                              fontSize: "16px",
                              fontWeight: "500",
                              marginBottom: "8px",
                            }}
                          >
                            等待生成图像
                          </div>
                          <div
                            style={{
                              fontSize: "13px",
                              color: "#999",
                              lineHeight: "1.5",
                            }}
                          >
                            设置参数并点击
                            <span
                              style={{
                                color: "#1890ff",
                                fontWeight: "500",
                                margin: "0 4px",
                              }}
                            >
                              "开始分析"
                            </span>
                            生成频谱图
                          </div>
                        </div>
                      )}
                    </div>
                  </Card>
                </Col>

                {/* Nyquist频率分析 */}
                <Col span={12}>
                  <Card
                    bordered={false}
                    style={{
                      height: "420px",
                      borderRadius: "8px",
                      boxShadow: "0 2px 8px rgba(0, 0, 0, 0.06)",
                      display: "flex",
                      flexDirection: "column",
                    }}
                    bodyStyle={{
                      flex: 1,
                      display: "flex",
                      flexDirection: "column",
                      padding: "24px",
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        marginBottom: "20px",
                      }}
                    >
                      <div>
                        <Title
                          level={5}
                          style={{ margin: 0, color: "#1f2937" }}
                        >
                          Nyquist频率分析
                        </Title>
                        <Text type="secondary" style={{ fontSize: "12px" }}>
                          0 - fs/2 频率范围，对数坐标
                        </Text>
                      </div>
                      <Button
                        type="text"
                        size="small"
                        icon={<DownloadOutlined />}
                        onClick={() => downloadImage("fig2")}
                        disabled={!images.fig2}
                        style={{ fontSize: "12px" }}
                      >
                        下载
                      </Button>
                    </div>

                    <div
                      style={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        background: "#fafafa",
                        borderRadius: "8px",
                        border: "1px dashed #d9d9d9",
                        padding: "20px",
                      }}
                    >
                      {images.fig2 ? (
                        <div
                          style={{
                            width: "100%",
                            height: "100%",
                            textAlign: "center",
                          }}
                        >
                          <img
                            src={`data:image/png;base64,${images.fig2}`}
                            alt="Nyquist频率分析"
                            style={{
                              maxWidth: "100%",
                              maxHeight: "100%",
                              objectFit: "contain",
                            }}
                          />
                        </div>
                      ) : (
                        <div
                          style={{
                            textAlign: "center",
                            color: "#8c8c8c",
                            width: "100%",
                          }}
                        >
                          <div
                            style={{
                              width: "64px",
                              height: "64px",
                              borderRadius: "50%",
                              background: "#f0f0f0",
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "center",
                              margin: "0 auto 16px",
                              color: "#bfbfbf",
                              fontSize: "20px",
                            }}
                          >
                            📈
                          </div>
                          <div
                            style={{
                              fontSize: "16px",
                              fontWeight: "500",
                              marginBottom: "8px",
                            }}
                          >
                            等待生成图像
                          </div>
                          <div
                            style={{
                              fontSize: "13px",
                              color: "#999",
                              lineHeight: "1.5",
                            }}
                          >
                            设置参数并点击
                            <span
                              style={{
                                color: "#1890ff",
                                fontWeight: "500",
                                margin: "0 4px",
                              }}
                            >
                              "开始分析"
                            </span>
                            生成频谱图
                          </div>
                        </div>
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
      <div
        style={{
          marginTop: "24px",
          padding: "16px 24px",
          background: "white",
          borderRadius: "8px",
          fontSize: "13px",
          color: "#666",
          textAlign: "center",
          boxShadow: "0 2px 8px rgba(0, 0, 0, 0.06)",
        }}
      >
        <InfoCircleOutlined
          style={{ marginRight: "8px", fontSize: "14px", color: "#1890ff" }}
        />
        MATLAB
        FFT分析基于您的参数设置生成频谱图像，确保参数设置合理以获得最佳分析结果。
      </div>
    </div>
  );
};

export default MatlabFFT;
