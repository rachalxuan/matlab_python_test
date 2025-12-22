// src/apis/simulation.js
import { request } from "../utils/request";

/**
 * 运行 MATLAB 仿真
 * @param {object} params - 仿真参数 { modType, symbolRate... }
 * @returns {Promise} - 返回后端的计算结果
 */
export const runMatlabSimulation = (data) => {
  return request("/simulate", {
    method: "POST",
    body: JSON.stringify(data), // fetch 需要手动把对象转成字符串
  });
};

// 如果以后有“测试连接”的接口，也可以写在这里
// export const testConnection = () => request('/test', { method: 'GET' });
