// src/main/main.js
const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const matlabService = require("./src/service/matlabService");

class ModemApp {
  constructor() {
    this.mainWindow = null;
    this.initApp();
  }

  initApp() {
    app.whenReady().then(() => {
      this.createWindow();
      this.setupIPC();
    });

    app.on("window-all-closed", () => {
      if (process.platform !== "darwin") {
        app.quit();
      }
    });
  }

  createWindow() {
    this.mainWindow = new BrowserWindow({
      width: 1400,
      height: 900,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        preload: path.join(__dirname, "./preload.js"),
      },
      title: "MATLAB FFT分析系统",
    });

    // 开发环境
    if (process.env.NODE_ENV === "development") {
      this.mainWindow.loadURL("http://localhost:3000");
      this.mainWindow.webContents.openDevTools();
    } else {
      // 生产环境
      this.mainWindow.loadFile(path.join(__dirname, "./build/index.html"));
    }
  }

  setupIPC() {
    // MATLAB FFT生成
    ipcMain.handle("matlab-generate-fft", async (event, parameters) => {
      console.log("收到FFT生成请求:", parameters);
      try {
        const result = await matlabService.generateFFTImages(parameters);
        console.log("FFT生成结果:", result);
        return { success: true, data: result };
      } catch (error) {
        console.error("FFT生成错误:", error);
        return { success: false, error: error.message };
      }
    });

    // 测试连接
    ipcMain.handle("matlab-test-connection", async () => {
      console.log("测试MATLAB连接");
      try {
        const result = await matlabService.testConnection();
        return { success: true, data: result };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });
  }
}

// 启动应用
new ModemApp();
