from flask import Flask, request, jsonify
from flask_cors import CORS  # ✅ 1. 新增这行：引入插件
import matlab.engine
import os
import sys
import json
import time

# --- 全局单例：启动时只运行一次 MATLAB ---
print("🚀 [Server] 正在启动 MATLAB 引擎，请耐心等待 (约 5-10秒)...")
t_start = time.time()

# 启动引擎
eng = matlab.engine.start_matlab()

# 添加当前目录到路径
current_dir = os.path.dirname(os.path.abspath(__file__))
eng.addpath(current_dir, nargout=0)

print(f"✅ [Server] MATLAB 引擎启动完毕！耗时: {time.time() - t_start:.2f} 秒")
# ----------------------------------------

app = Flask(__name__)
CORS(app)  # ✅ 2. 新增这行：开启跨域许可


@app.route('/simulate', methods=['POST'])
def run_simulation():
    try:
        # 1. 获取前端传来的 JSON 数据
        params = request.json
        params_json = json.dumps(params)

        print(f"📩 [Server] 收到仿真请求: Mod={params.get('modType', 'Unknown')}")

        # 2. 调用 MATLAB
        result_json = eng.run_ccsds_tm_modulation(params_json, nargout=1)

        # 3. 解析结果并返回
        result_data = json.loads(result_json)

        if 'stats' in result_data and 'matlabTime' in result_data['stats']:
            print(
                f"⚡ [Server] MATLAB 计算耗时: {result_data['stats']['matlabTime']:.4f} 秒")

        return jsonify(result_data)

    except Exception as e:
        print(f"❌ [Server] 发生错误: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500


if __name__ == '__main__':
    # 启动 HTTP 服务
    app.run(host='127.0.0.1', port=5000, use_reloader=False)
