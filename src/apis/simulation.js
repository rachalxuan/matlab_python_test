// src/apis/simulation.js
import { request } from "../utils/request";

// Run MATLAB simulation.
export const runMatlabSimulation = (data) => {
  return request({
    url: "/simulate",
    method: "POST",
    body: JSON.stringify(data),
  });
};

// Query MATLAB simulation task status.
export const getSimulationTaskStatus = (taskId) => {
  return request({
    url: `/task_status/${taskId}`,
    method: "GET",
  });
};

// Cancel a queued/running MATLAB simulation task.
export const cancelSimulationTask = (taskId) => {
  return request({
    url: `/cancel_task/${taskId}`,
    method: "POST",
  });
};

// Save a simulation record.
export const saveSimulationRecord = (data) => {
  return request({
    url: "/save_record",
    method: "POST",
    data,
  });
};

// Get simulation history list.
export const getHistoryList = () => {
  return request({
    url: "/get_history_list",
    method: "GET",
  });
};

// Get a simulation history detail.
export const getRecordDetail = (id) => {
  return request({
    url: "/get_record_detail",
    method: "POST",
    data: { id },
  });
};
