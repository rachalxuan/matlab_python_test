//柱状图组件

//1、把功能代码放在组件中
//2、把可变的部分抽象成pros参数
import { useEffect, useRef } from 'react'
import * as echarts from 'echarts'
const BarChart = ({ title, data_x = [], data_y = [] }) => {
  const chartRef = useRef(null)
  //useEffect在组件渲染完毕之后执行 保证dom节点是可用的
  useEffect(() => {
    // 1. 图表初始化生成实例
    const myChart = echarts.init(chartRef.current)
    // 2. 准备图表参数
    const option = {
      title: {
        text: title
      },
      xAxis: {
        type: 'category',
        data: data_x
      },
      yAxis: {
        type: 'value'
      },
      series: [
        {
          data: data_y,
          type: 'bar'
        }
      ]
    }
    // 3. 渲染参数
    myChart.setOption(option)
  }, [])
  return (
    <div ref={chartRef} style={{ width: '400px', height: '300px' }} />
  )
}
export default BarChart