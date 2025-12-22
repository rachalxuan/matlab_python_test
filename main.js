const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const fs = require("fs");

class ModemApp {
  constructor() {
    this.mainWindow = null;
    this.initApp();
  }

  initApp() {
    app
      .whenReady()
      .then(() => {
        // 不需要 loadMatlabService 了
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

  // loadMatlabService 和 createMockService 都可以删掉了

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

    if (process.env.NODE_ENV === "development") {
      console.log("开发环境: 加载 http://localhost:3000");
      this.mainWindow.loadURL("http://localhost:3000");
      this.mainWindow.webContents.openDevTools();
    } else {
      const indexPath = path.join(__dirname, "..", "build", "index.html");
      if (fs.existsSync(indexPath)) {
        this.mainWindow.loadFile(indexPath);
      } else {
        this.mainWindow.loadURL("http://localhost:3000");
      }
    }

    this.mainWindow.once("ready-to-show", () => {
      this.mainWindow.show();
    });
  }

  setupIPC() {
    // 这里只保留纯粹的系统级 IPC，仿真逻辑已经移交给 HTTP 了
    // 如果你前端还有用 ipcRenderer.invoke('matlab-test-connection')，也可以在这里删掉
    // 建议把前端的测试连接也改成发 HTTP 请求给 Python
  }
}

try {
  console.log("应用启动，当前目录:", __dirname);
  new ModemApp();
} catch (error) {
  console.error("应用初始化失败:", error);
  app.quit();
}
