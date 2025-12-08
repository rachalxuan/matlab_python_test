const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const fs = require("fs");

class ModemApp {
  constructor() {
    this.mainWindow = null;
    this.matlabService = null;
    this.initApp();
  }

  initApp() {
    app
      .whenReady()
      .then(() => {
        this.loadMatlabService();
        this.createWindow();
        this.setupIPC();
      })
      .catch((error) => {
        console.error("应用启动失败:", error);
        app.quit();
      });

    app.on("window-all-closed", () => {
      if (process.platform !== "darwin") {
        app.quit();
      }
    });

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        this.createWindow();
      }
    });
  }

  loadMatlabService() {
    try {
      // 尝试加载服务
      const servicePath = path.join(
        __dirname,
        "src",
        "service",
        "matlabService.js"
      );
      console.log("尝试加载MATLAB服务:", servicePath);

      if (fs.existsSync(servicePath)) {
        this.matlabService = require(servicePath);
        console.log("MATLAB服务加载成功");
      } else {
        console.warn("MATLAB服务文件不存在，使用模拟服务");
        this.matlabService = this.createMockService();
      }
    } catch (error) {
      console.error("加载MATLAB服务失败:", error.message);
      this.matlabService = this.createMockService();
    }
  }

  createMockService() {
    return {
      generateFFTImages: async (parameters) => {
        console.log("模拟: 生成FFT图像，参数:", parameters);
        // 模拟延迟
        await new Promise((resolve) => setTimeout(resolve, 1000));

        return {
          success: true,
          images: [
            {
              name: "时域信号图",
              description: `采样频率: ${parameters.fs}Hz, 信号频率: ${parameters.f1}Hz, ${parameters.f2}Hz`,
              data: "模拟图像数据1",
            },
            {
              name: "频谱分析图",
              description: "FFT分析结果",
              data: "模拟图像数据2",
            },
          ],
          statistics: {
            peakFrequencies: [parameters.f1, parameters.f2],
            snr: 25.6,
            thd: 0.012,
          },
        };
      },

      testConnection: async () => {
        console.log("模拟: 测试MATLAB连接");
        await new Promise((resolve) => setTimeout(resolve, 500));
        return {
          connected: true,
          version: "MATLAB R2023a (模拟模式)",
          message: "当前运行在模拟模式，请配置MATLAB环境以使用完整功能",
        };
      },

      getExampleParameters: () => {
        return {
          example1: {
            fs: 1000,
            f1: 50,
            f2: 120,
            noiseLevel: 0.5,
            duration: 1,
            nfft: 1024,
          },
          example2: {
            fs: 2000,
            f1: 100,
            f2: 250,
            noiseLevel: 0.2,
            duration: 2,
            nfft: 2048,
          },
        };
      },
    };
  }

  createWindow() {
    this.mainWindow = new BrowserWindow({
      width: 1400,
      height: 900,
      show: false,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        preload: path.join(__dirname, "preload.js"),
      },
      title: "MATLAB FFT分析系统",
    });

    // 开发环境
    if (process.env.NODE_ENV === "development") {
      console.log("开发环境: 加载 http://localhost:3000");
      this.mainWindow.loadURL("http://localhost:3000");
      this.mainWindow.webContents.openDevTools();
    } else {
      // 生产环境
      const indexPath = path.join(__dirname, "..", "build", "index.html");
      console.log("生产环境路径:", indexPath);

      if (fs.existsSync(indexPath)) {
        this.mainWindow.loadFile(indexPath);
      } else {
        console.warn("构建文件不存在，尝试启动开发服务器...");
        // 如果build不存在，尝试加载开发服务器
        this.mainWindow.loadURL("http://localhost:3000");
      }
    }

    // 页面加载完成后显示窗口
    this.mainWindow.once("ready-to-show", () => {
      this.mainWindow.show();
    });

    this.mainWindow.webContents.on("did-finish-load", () => {
      console.log("页面加载完成");
    });
  }

  setupIPC() {
    // MATLAB FFT生成
    ipcMain.handle("matlab-generate-fft", async (event, parameters) => {
      console.log("收到FFT生成请求:", parameters);
      try {
        if (!this.matlabService) {
          throw new Error("MATLAB服务未初始化");
        }
        const result = await this.matlabService.generateFFTImages(parameters);
        console.log("FFT生成成功");
        return { success: true, data: result };
      } catch (error) {
        console.error("FFT生成错误:", error);
        return {
          success: false,
          error: error.message,
          timestamp: new Date().toISOString(),
        };
      }
    });

    // 测试连接
    ipcMain.handle("matlab-test-connection", async () => {
      console.log("测试MATLAB连接");
      try {
        if (!this.matlabService) {
          throw new Error("MATLAB服务未初始化");
        }
        const result = await this.matlabService.testConnection();
        return { success: true, data: result };
      } catch (error) {
        return {
          success: false,
          error: error.message,
        };
      }
    });

    // 获取示例参数
    ipcMain.handle("get-example-parameters", async () => {
      console.log("获取示例参数");
      try {
        if (!this.matlabService) {
          throw new Error("MATLAB服务未初始化");
        }
        const examples = this.matlabService.getExampleParameters();
        return { success: true, data: examples };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });
  }
}

// 启动应用
try {
  console.log("应用启动，当前目录:", __dirname);
  new ModemApp();
} catch (error) {
  console.error("应用初始化失败:", error);
  app.quit();
}
