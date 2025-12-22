import matlab.engine
import json
import os
import sys

# 启动 MATLAB 引擎 (保持单例模式)
# 注意：如果你的启动逻辑不一样，请保留你原来的启动代码，只修改 run_ccsds_tm 函数
eng = matlab.engine.start_matlab()


def run_ccsds_tm(params):
    """
    接收前端传来的字典对象 params，
    将其转换为 JSON 字符串，传递给 MATLAB 函数。
    """
    try:
        # 1. 确保 MATLAB 能找到我们的 .m 文件
        current_dir = os.path.dirname(os.path.abspath(__file__))
        eng.addpath(current_dir, nargout=0)

        # 2. 将 Python 字典序列化为 JSON 字符串
        # MATLAB 处理 JSON 字符串比处理 Python 字典要灵活得多
        params_json = json.dumps(params)

        # 3. 调用 MATLAB 函数
        # 注意：函数名必须与文件名一致
        print(f"Calling MATLAB with: {params_json}")  # 调试日志
        result_json = eng.run_ccsds_FACM_modulation(params_json, nargout=1)

        # 4. 将 MATLAB 返回的 JSON 字符串转回 Python 字典返回给 Node.js
        return json.loads(result_json)

    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "stack": "Python Bridge Error"
        }

# ... (用于测试的 main 函数可以保留或删除)
