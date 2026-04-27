// src/apis/simulation.js
import { request } from "../utils/request";

/**
 * 运行 MATLAB 仿真
 * @param {object} params - 仿真参数 { modType, symbolRate... }
 * @returns {Promise} - 返回后端的计算结果
 */
export const runMatlabSimulation = (data) => {
  return request({
    url: "/simulate",
    method: "POST",
    body: JSON.stringify(data), // fetch 需要手动把对象转成字符串
  });
};
// 保存仿真记录
export const saveSimulationRecord = (data) => {
  return request({
    url: "/save_record",
    method: "POST",
    data, // fetch 需要手动把对象转成字符串
  });
};
// 获取仿真记录列表
export const getHistoryList = () => {
  return request({
    url: "/get_history_list",
    method: "GET",
  });
};
// 获取仿真记录详情
export const getRecordDetail = (id) => {
  return request({
    url: "/get_record_detail",
    method: "POST",
    data: { id },
  });
};
