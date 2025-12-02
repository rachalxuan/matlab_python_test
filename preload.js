// src/preload/preload.js
const { contextBridge, ipcRenderer } = require("electron");

// 暴露安全的API给渲染进程
contextBridge.exposeInMainWorld("electronAPI", {
  // MATLAB FFT功能
  generateFFTImages: (parameters) =>
    ipcRenderer.invoke("matlab-generate-fft", parameters),
  testMatlabConnection: () => ipcRenderer.invoke("matlab-test-connection"),

  // 监听事件
  onUpdateStatus: (callback) => ipcRenderer.on("status-update", callback),
});
