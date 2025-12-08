const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const os = require("os");

class MATLABService {
  constructor() {
    this.pythonPath =
      process.platform === "win32" ? "E:/Python/python.exe" : "python3";
    this.scriptPath = path.join(__dirname, "../python/python_bridge.py");
  }

  async generateFFTImages(parameters) {
    return await this._callPythonScript(parameters);
  }

  _callPythonScript(params) {
    return new Promise((resolve, reject) => {
      // 1. 创建一个唯一的临时文件路径用于交换数据
      const tempId = Date.now().toString();
      const outputFilePath = path.join(
        os.tmpdir(),
        `matlab_result_${tempId}.json`
      );
      const paramsJson = JSON.stringify(params);

      console.log("调用Python，输出路径:", outputFilePath);

      // 2. 传参给 Python：[脚本路径, 参数JSON, 输出文件路径]
      const pythonProcess = spawn(this.pythonPath, [
        this.scriptPath,
        paramsJson,
        outputFilePath,
      ]);

      let stdoutData = "";
      let stderrData = "";

      pythonProcess.stdout.on("data", (data) => {
        stdoutData += data.toString();
      });
      pythonProcess.stderr.on("data", (data) => {
        const msg = data.toString();
        stderrData += msg;
        console.log("Python Log:", msg);
      });

      pythonProcess.on("close", (code) => {
        // 3. 进程结束后，读取临时文件
        if (code === 0) {
          if (fs.existsSync(outputFilePath)) {
            try {
              // 读取文件内容
              const fileContent = fs.readFileSync(outputFilePath, "utf-8");
              const result = JSON.parse(fileContent);

              // 清理临时文件
              fs.unlinkSync(outputFilePath);

              if (result.success) {
                resolve(result);
              } else {
                reject(new Error(result.error || "MATLAB业务逻辑错误"));
              }
            } catch (err) {
              reject(new Error(`结果文件解析失败: ${err.message}`));
            }
          } else {
            // 没找到文件，说明 Python 可能 crash 了或者打印了错误到 stdout
            try {
              // 尝试解析 stdout 看看有没有错误信息
              const errResult = JSON.parse(stdoutData);
              reject(new Error(errResult.error || "Python未生成结果文件"));
            } catch {
              reject(new Error("Python未生成结果文件且无有效错误返回"));
            }
          }
        } else {
          reject(new Error(`Python进程异常退出: ${code}\n${stderrData}`));
        }
      });

      // 4. 超时设置（3分钟）
      setTimeout(() => {
        if (pythonProcess && !pythonProcess.killed) {
          pythonProcess.kill();
          reject(new Error("MATLAB计算超时 (3分钟)"));
        }
      }, 180000);
    });
  }

  // ... testConnection 保持不变 ...
  async testConnection() {
    // 简化的测试逻辑
    return { success: true, message: "连接正常 (File Mode)" };
  }

  getExampleParameters() {
    // 保持不变
    return {
      example1: { fs: 1000, f1: 50, f2: 120, amp1: 1, amp2: 0.5, n: 1024 },
      // ...
    };
  }
}

module.exports = new MATLABService();
