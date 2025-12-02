import { useEffect, useRef } from 'react'
import * as echarts from 'echarts'
import BarChart from '@/pages/Home/components/BarChart'
import { data } from 'react-router-dom'

const Home = () => {


  return (
    <div>
      <BarChart title={'三大框架满意度'} data_x={['vue', 'react', 'angular']} data_y={[100, 80, 90]} />
      <BarChart title={'三大框架使用度'} data_x={['vue', 'react', 'angular']} data_y={[80, 90, 100]} />
    </div >
  )
}

export default Home