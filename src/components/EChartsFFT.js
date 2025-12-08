// src/components/EChartsFFT/EChartsFFT.jsx
import React, { useEffect, useRef } from "react";
import * as echarts from "echarts";
import "./EChartsFFT.scss";

const EChartsFFT = ({ fftData, loading = false }) => {
  const timeChartRef = useRef(null);
  const freqChartRef = useRef(null);
  const combinedChartRef = useRef(null);

  useEffect(() => {
    if (!fftData) return;

    // 1. 时域图
    if (timeChartRef.current && fftData.timeDomain) {
      const timeChart = echarts.init(timeChartRef.current);

      const timeOption = {
        title: {
          text: "时域信号",
          left: "center",
          textStyle: {
            fontSize: 16,
            fontWeight: "bold",
          },
        },
        tooltip: {
          trigger: "axis",
          formatter: (params) => {
            const [param] = params;
            return `时间: ${param.data[0].toFixed(3)} s<br/>幅度: ${param.data[1].toFixed(4)}`;
          },
        },
        grid: {
          left: "3%",
          right: "4%",
          bottom: "3%",
          containLabel: true,
        },
        xAxis: {
          type: "value",
          name: "时间 (s)",
          nameLocation: "middle",
          nameGap: 25,
          axisLine: {
            lineStyle: {
              color: "#999",
            },
          },
        },
        yAxis: {
          type: "value",
          name: "幅度",
          nameLocation: "middle",
          nameGap: 30,
          axisLine: {
            lineStyle: {
              color: "#999",
            },
          },
        },
        series: [
          {
            data: fftData.timeDomain.time.map((t, i) => [
              t,
              fftData.timeDomain.signal[i],
            ]),
            type: "line",
            smooth: true,
            lineStyle: {
              width: 2,
              color: "#1890ff",
            },
            itemStyle: {
              opacity: 0,
            },
            areaStyle: {
              color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
                { offset: 0, color: "rgba(24, 144, 255, 0.6)" },
                { offset: 1, color: "rgba(24, 144, 255, 0.1)" },
              ]),
            },
            symbol: "circle",
            symbolSize: 4,
          },
        ],
      };

      timeChart.setOption(timeOption);

      // 响应式
      const handleResize = () => timeChart.resize();
      window.addEventListener("resize", handleResize);

      return () => {
        window.removeEventListener("resize", handleResize);
        timeChart.dispose();
      };
    }

    // 2. 频域图
    if (freqChartRef.current && fftData.frequencyDomain) {
      const freqChart = echarts.init(freqChartRef.current);

      // 标记峰值
      const peaks = fftData.peaks || [];
      const peakMarkPoints = peaks.map((peak) => ({
        coord: [peak.freq, peak.amplitude],
        symbol: "pin",
        symbolSize: 30,
        label: {
          show: true,
          formatter: `${peak.freq.toFixed(1)} Hz`,
          position: "top",
        },
        itemStyle: {
          color: "#ff4d4f",
        },
      }));

      const freqOption = {
        title: {
          text: "频域信号 (FFT)",
          left: "center",
          textStyle: {
            fontSize: 16,
            fontWeight: "bold",
          },
        },
        tooltip: {
          trigger: "axis",
          formatter: (params) => {
            const [param] = params;
            return `频率: ${param.data[0].toFixed(2)} Hz<br/>幅度: ${param.data[1].toFixed(4)}`;
          },
        },
        grid: {
          left: "3%",
          right: "4%",
          bottom: "3%",
          containLabel: true,
        },
        xAxis: {
          type: "value",
          name: "频率 (Hz)",
          nameLocation: "middle",
          nameGap: 25,
          min: 0,
          max: fftData.statistics?.sample_rate
            ? fftData.statistics.sample_rate / 2
            : null,
          axisLine: {
            lineStyle: {
              color: "#999",
            },
          },
        },
        yAxis: {
          type: "value",
          name: "幅度",
          nameLocation: "middle",
          nameGap: 30,
          axisLine: {
            lineStyle: {
              color: "#999",
            },
          },
        },
        series: [
          {
            data: fftData.frequencyDomain.frequencies.map((f, i) => [
              f,
              fftData.frequencyDomain.amplitudes[i],
            ]),
            type: "line",
            smooth: false,
            lineStyle: {
              width: 2,
              color: "#52c41a",
            },
            itemStyle: {
              opacity: 0,
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
            areaStyle: {
              color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
                { offset: 0, color: "rgba(82, 196, 26, 0.6)" },
                { offset: 1, color: "rgba(82, 196, 26, 0.1)" },
              ]),
            },
          },
        ],
      };

      freqChart.setOption(freqOption);

      const handleResize = () => freqChart.resize();
      window.addEventListener("resize", handleResize);

      return () => {
        window.removeEventListener("resize", handleResize);
        freqChart.dispose();
      };
    }

    // 3. 组合图（时域+频域）
    if (
      combinedChartRef.current &&
      fftData.timeDomain &&
      fftData.frequencyDomain
    ) {
      const combinedChart = echarts.init(combinedChartRef.current);

      const combinedOption = {
        title: {
          text: "信号综合分析",
          left: "center",
          textStyle: {
            fontSize: 16,
            fontWeight: "bold",
          },
        },
        tooltip: {
          trigger: "axis",
          axisPointer: {
            type: "cross",
          },
        },
        legend: {
          data: ["时域信号", "频域信号"],
          top: "7%",
        },
        grid: [
          {
            left: "7%",
            right: "3%",
            top: "20%",
            bottom: "55%",
          },
          {
            left: "7%",
            right: "3%",
            top: "60%",
            bottom: "5%",
          },
        ],
        xAxis: [
          {
            type: "value",
            gridIndex: 0,
            name: "时间 (s)",
            axisLine: {
              lineStyle: {
                color: "#999",
              },
            },
          },
          {
            type: "value",
            gridIndex: 1,
            name: "频率 (Hz)",
            min: 0,
            max: fftData.statistics?.sample_rate
              ? fftData.statistics.sample_rate / 2
              : null,
            axisLine: {
              lineStyle: {
                color: "#999",
              },
            },
          },
        ],
        yAxis: [
          {
            type: "value",
            gridIndex: 0,
            name: "幅度",
            axisLine: {
              lineStyle: {
                color: "#999",
              },
            },
          },
          {
            type: "value",
            gridIndex: 1,
            name: "幅度",
            axisLine: {
              lineStyle: {
                color: "#999",
              },
            },
          },
        ],
        series: [
          {
            name: "时域信号",
            type: "line",
            xAxisIndex: 0,
            yAxisIndex: 0,
            data: fftData.timeDomain.time.map((t, i) => [
              t,
              fftData.timeDomain.signal[i],
            ]),
            smooth: true,
            lineStyle: {
              width: 2,
              color: "#1890ff",
            },
            showSymbol: false,
          },
          {
            name: "频域信号",
            type: "line",
            xAxisIndex: 1,
            yAxisIndex: 1,
            data: fftData.frequencyDomain.frequencies.map((f, i) => [
              f,
              fftData.frequencyDomain.amplitudes[i],
            ]),
            smooth: false,
            lineStyle: {
              width: 2,
              color: "#52c41a",
            },
            showSymbol: false,
          },
        ],
      };

      combinedChart.setOption(combinedOption);

      const handleResize = () => combinedChart.resize();
      window.addEventListener("resize", handleResize);

      return () => {
        window.removeEventListener("resize", handleResize);
        combinedChart.dispose();
      };
    }
  }, [fftData]);

  if (loading) {
    return (
      <div className="echarts-loading">
        <div className="loading-spinner"></div>
        <div className="loading-text">图表数据加载中...</div>
      </div>
    );
  }

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

  return (
    <div className="echarts-container">
      <div className="chart-row">
        <div className="chart-container">
          <div
            ref={timeChartRef}
            className="chart"
            style={{ height: "300px" }}
          />
        </div>
        <div className="chart-container">
          <div
            ref={freqChartRef}
            className="chart"
            style={{ height: "300px" }}
          />
        </div>
      </div>
      <div className="chart-row">
        <div className="chart-container full-width">
          <div
            ref={combinedChartRef}
            className="chart"
            style={{ height: "400px" }}
          />
        </div>
      </div>
    </div>
  );
};

export default EChartsFFT;
