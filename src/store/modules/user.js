//和用户相关的状态管理
import { createSlice } from '@reduxjs/toolkit'

import { getToken, removeToken, setToken as _setToken } from '@/utils'
import { loginAPI, getProfileAPI } from '@/apis/user'

const userStore = createSlice({
  name: 'user',
  initialState: {
    token: getToken() || '',
    userInfo: {}
  },
  //   11111111111111111111
  reducers: {
    setToken(state, action) {
      state.userInfo = action.payload
      _setToken(action.payload)
    },
    setUserInfo(state, action) {
      state.userInfo = action.payload
    },
    clearUserInfo(state) {
      state.userInfo = {}
      state.token = ''
      removeToken()
    }
  }
})

//获取actionCreator
const { setToken, setUserInfo, clearUserInfo } = userStore.actions
//异步
const fetchLogin = (loginForm) => {
  return async (dispatch) => {
    const res = await loginAPI(loginForm)
    console.log(res.data)
    dispatch(setToken(res.data.token))

  }
}
const fetchUserInfo = () => {
  return async (dispatch) => {
    const res = await getProfileAPI()
    dispatch(setUserInfo(res.data))
  }
}
const reducer = userStore.reducer
export { fetchLogin, setToken, fetchUserInfo, setUserInfo, clearUserInfo }
export default reducer
