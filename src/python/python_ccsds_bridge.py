import matlab.engine
import os
import sys
import json
import base64
import time


def log(msg):
    print(f"[Python Bridge] {msg}", file=sys.stderr)


def run_ccsds_tm(params):
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
        result_json = eng.run_ccsds_tm_modulation(params_json, nargout=1)

        # 4. 将 MATLAB 返回的 JSON 字符串转回 Python 字典返回给 Node.js
        # return json.loads(result_json)
        result_dict = json.loads(result_json)

        # 3. 【这里打印】从数据里取出时间打印出来
        if 'stats' in result_dict and 'ElapsedTime' in result_dict['stats']:
            ElapsedTime = result_dict['stats']['ElapsedTime']
            log(f"MATLAB caculate time: {ElapsedTime:.4f} 秒")

        return result_dict

    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "stack": "Python Bridge Error"
        }


if __name__ == "__main__":
    try:
        input_json = sys.argv[1]
        output_file_path = sys.argv[2]
        params = json.loads(input_json)
        t_start = time.time()
        eng = matlab.engine.start_matlab()
        t_ready = time.time()
        print(
            f"MATLAB wasted time: {t_ready - t_start:.2f} seconds", file=sys.stderr)
        current_dir = os.path.dirname(os.path.abspath(__file__))
        eng.addpath(current_dir)

        # 路由逻辑
        task_type = params.get('taskType', 'ccsds_tm')  # 默认为 CCSDS

        if task_type == 'ccsds_tm':
            result = run_ccsds_tm(params)
        else:
            result = {"success": False, "error": f"未知任务类型: {task_type}"}

        with open(output_file_path, 'w', encoding='utf-8') as f:
            json.dump(result, f)

        print("SUCCESS")

    except Exception as e:
        log(f"主程序崩溃: {str(e)}")
        # 即使崩溃也尝试写入错误信息，让前端看到
        try:
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(
                    {"success": False, "error": f"Python Script Error: {str(e)}"}, f)
        except:
            pass
    finally:
        if 'eng' in locals():
            eng.quit()
