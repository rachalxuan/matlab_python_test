// src/main/services/matlabService.js
const { spawn } = require("child_process");
const path = require("path");

class MATLABService {
  constructor() {
    // 注意：这里需要指定Python路径
    // 如果是Windows，可能需要完整路径，如：'C:\\Python39\\python.exe'
    this.pythonPath =
      process.platform === "win32" ? "E:/Python/python.exe" : "python3";

    // Python脚本的路径 - 根据你的项目结构调整
    // 假设python_bridge.py在项目的python目录下
    this.scriptPath = path.join(__dirname, "../python/python_bridge.py");

    console.log("Python路径:", this.pythonPath);
    console.log("脚本路径:", this.scriptPath);
  }

  /**
   * 调用MATLAB生成FFT图像
   */
  async generateFFTImages(parameters) {
    return await this._callPythonScript(parameters);
  }

  /**
   * 通用的Python脚本调用方法
   */
  _callPythonScript(params) {
    return new Promise((resolve, reject) => {
      const paramsJson = JSON.stringify(params);

      console.log("调用Python脚本，参数:", params);

      const pythonProcess = spawn(this.pythonPath, [
        this.scriptPath,
        paramsJson,
      ]);

      let stdoutData = "";
      let stderrData = "";

      pythonProcess.stdout.on("data", (data) => {
        stdoutData += data.toString();
      });

      pythonProcess.stderr.on("data", (data) => {
        stderrData += data.toString();
        console.error("Python错误输出:", data.toString());
      });

      pythonProcess.on("close", (code) => {
        console.log("Python进程退出，代码:", code);
        console.log("Python标准输出:", stdoutData);

        if (code === 0) {
          try {
            const result = JSON.parse(stdoutData);
            console.log("解析后的结果:", result);

            if (result.success) {
              resolve(result);
            } else {
              reject(new Error(result.error || "MATLAB调用失败"));
            }
          } catch (parseError) {
            console.error("解析错误:", parseError);
            reject(
              new Error(
                `结果解析失败: ${parseError.message}\n原始输出: ${stdoutData}`
              )
            );
          }
        } else {
          reject(
            new Error(`Python进程异常退出: ${code}\n错误输出: ${stderrData}`)
          );
        }
      });

      pythonProcess.on("error", (error) => {
        console.error("进程启动错误:", error);
        reject(
          new Error(
            `无法启动Python进程: ${error.message}\n请确保Python已安装并在PATH中`
          )
        );
      });

      // 设置超时（60秒）
      setTimeout(() => {
        if (pythonProcess && !pythonProcess.killed) {
          pythonProcess.kill();
          reject(new Error("MATLAB调用超时（60秒）"));
        }
      }, 60000);
    });
  }

  /**
   * 测试MATLAB连接
   */
  async testConnection() {
    return await this.generateFFTImages({
      fs: 100,
      n: 1024,
      freq1: 50,
      freq2: 120,
      amp1: 1,
      amp2: 0.5,
    });
  }
}

// 导出单例实例
module.exports = new MATLABService();
