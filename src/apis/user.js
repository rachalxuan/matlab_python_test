//用户相关的所有请求
import { request } from '@/utils'
//1、登录请求
// const res = await request.post('/authorizations', loginForm)
export function loginAPI(dataForm) {
  return request({
    url: '/authorizations',
    method: 'POST',
    data: dataForm
  })

}

// const res = await request.get('/user/profile')
export function getProfileAPI() {
  return request({
    url: '/user/profile',
    method: 'GET'
  })
}