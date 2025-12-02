//封装高阶组件
//核心逻辑 有token 则渲染子组件 无则跳转登录
import { getToken } from '@/utils/token'
import { Navigate } from 'react-router-dom'
// children 是组件的一个特殊属性，它代表了组件标签内包裹的所有内容
export function AuthRoute({ children }) {
  const token = getToken()
  if (token) {

    return <>{children}</>
  } else {
    return <Navigate to={'/login'} replace />
  }
}