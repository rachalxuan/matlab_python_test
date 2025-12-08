// src/main/preload.js
const { contextBridge, ipcRenderer } = require("electron");

// 暴露安全的API给渲染进程
contextBridge.exposeInMainWorld("matlabAPI", {
  // MATLAB FFT功能
  generateFFT: (parameters) =>
    ipcRenderer.invoke("matlab-generate-fft", parameters),

  testConnection: () => ipcRenderer.invoke("matlab-test-connection"),

  getExampleParameters: () => ipcRenderer.invoke("get-example-parameters"),

  // 文件操作
  selectFile: () => ipcRenderer.invoke("select-file"),

  saveData: (data) => ipcRenderer.invoke("save-data", data),

  // 监听MATLAB处理状态
  onMatlabStatus: (callback) =>
    ipcRenderer.on("matlab-status", (event, status) => callback(status)),

  // 移除监听器
  removeMatlabStatusListener: (callback) =>
    ipcRenderer.removeListener("matlab-status", callback),
});

// 暴露版本信息
contextBridge.exposeInMainWorld("appInfo", {
  version: process.env.npm_package_version || "1.0.0",
  platform: process.platform,
  isDev: process.env.NODE_ENV === "development",
});
