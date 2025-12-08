// src/components/EChartsFFT/EChartsFFT.jsx
import React, { useEffect, useRef } from "react";
import * as echarts from "echarts";
import "./EChartsFFT.scss";

const EChartsFFT = ({ fftData, loading = false }) => {
  // 只需要一个 ref 来显示主图表（频谱）
  const freqChartRef = useRef(null);

  useEffect(() => {
    // 检查是否具备绘制频谱图的必要数据
    if (
      !fftData ||
      !fftData.frequencyDomain ||
      !fftData.frequencyDomain.frequencies
    ) {
      // 清理旧图表实例
      if (freqChartRef.current) {
        const chartInstance = echarts.getInstanceByDom(freqChartRef.current);
        if (chartInstance) chartInstance.dispose();
      }
      return;
    }

    const { frequencies, amplitudes } = fftData.frequencyDomain;
    const sampleRate = fftData.statistics?.sample_rate;

    // 初始化/获取 ECharts 实例
    let freqChart = echarts.getInstanceByDom(freqChartRef.current);
    if (!freqChart) {
      freqChart = echarts.init(freqChartRef.current);
    }

    // 查找最大振幅和对应频率，用于标记峰值
    const maxAmp = Math.max(...amplitudes);
    const peakIndex = amplitudes.indexOf(maxAmp);
    const peakFreq = frequencies[peakIndex];

    const peakMarkPoints = [];
    if (peakFreq) {
      peakMarkPoints.push({
        coord: [peakFreq, maxAmp],
        symbol: "pin",
        symbolSize: 30,
        label: {
          show: true,
          formatter: `${peakFreq.toFixed(1)} Hz`,
          position: "top",
        },
        itemStyle: {
          color: "#ff4d4f",
        },
      });
    }

    const freqOption = {
      title: {
        text: "FFT 频谱分析 (Nyquist 前)",
        subtext: `采样率: ${sampleRate} Hz | 数据点: ${frequencies.length} | 最大振幅: ${maxAmp.toFixed(4)}`,
        left: "center",
        textStyle: {
          fontSize: 16,
          fontWeight: "bold",
        },
      },
      tooltip: {
        trigger: "axis",
        // 优化 tooltip 格式，显示更准确的数字
        formatter: (params) => {
          const [param] = params;
          return `频率: ${param.data[0].toFixed(2)} Hz<br/>幅度: ${param.data[1].toFixed(6)}`;
        },
      },
      grid: {
        left: "5%",
        right: "5%",
        top: "20%",
        bottom: "10%",
        containLabel: true,
      },
      xAxis: {
        type: "value",
        name: "频率 (Hz)",
        nameLocation: "middle",
        nameGap: 25,
        min: 0,
        // 最大频率限制在 Nyquist 频率 (fs/2)
        max: sampleRate ? sampleRate / 2 : null,
        axisLine: {
          lineStyle: {
            color: "#999",
          },
        },
      },
      yAxis: {
        type: "value",
        name: "振幅",
        nameLocation: "middle",
        nameGap: 35,
        axisLine: {
          lineStyle: {
            color: "#999",
          },
        },
      },
      series: [
        {
          // 关键修改：使用柱状图 (Bar) 更适合频谱显示
          data: frequencies.map((f, i) => [f, amplitudes[i]]),
          type: "bar",
          barWidth: "95%",
          itemStyle: {
            // 添加渐变色，增强视觉效果
            color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
              { offset: 0, color: "#1890ff" },
              { offset: 1, color: "#1677ff" },
            ]),
            borderRadius: 4,
          },
          markPoint: {
            data: peakMarkPoints,
            symbol: "circle",
            symbolSize: 8,
            label: {
              show: true,
              position: "top",
              color: "#ff4d4f",
              fontWeight: "bold",
            },
          },
        },
      ],
    };

    freqChart.setOption(freqOption);

    // 响应式
    const handleResize = () => freqChart.resize();
    window.addEventListener("resize", handleResize);

    return () => {
      window.removeEventListener("resize", handleResize);
      freqChart.dispose();
    };
  }, [fftData, loading]);

  if (loading) {
    return (
      <div className="echarts-loading">
        <div className="loading-spinner"></div>
        <div className="loading-text">图表数据加载中...</div>
      </div>
    );
  }

  // 只有在没有数据时才显示空状态
  if (!fftData) {
    return (
      <div className="echarts-empty">
        <div className="empty-icon">📊</div>
        <div className="empty-title">暂无FFT数据</div>
        <div className="empty-description">
          设置参数并点击"开始分析"生成频谱数据
        </div>
      </div>
    );
  }

  // 渲染单个图表容器
  return (
    <div className="echarts-container">
      <div className="chart-row">
        <div className="chart-container full-width">
          <div
            ref={freqChartRef}
            className="chart"
            style={{ height: "450px" }} // 调整高度以适应单个大图表
          />
        </div>
      </div>
    </div>
  );
};

export default EChartsFFT;
