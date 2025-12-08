# python_bridge_json.py
import matlab.engine
import os
import time
import sys
import json
import base64


def generate_fft_images(params):
    """生成FFT图像 - 使用MATLAB返回JSON的方式"""
    try:
        # 从参数字典中提取参数
        fs = float(params['fs'])
        n = int(params['n'])  # 确保是整数
        freq1 = float(params['freq1'])
        freq2 = float(params['freq2'])
        amp1 = float(params['amp1'])
        amp2 = float(params['amp2'])

        print(f"调用MATLAB JSON函数: fs={fs}, n={n}, freq1={freq1}, freq2={freq2}, amp1={amp1}, amp2={amp2}",
              file=sys.stderr)

        # 调用MATLAB函数，返回JSON字符串
        json_str = eng.FFT_function(fs, n, freq1, freq2, amp1, amp2, nargout=1)

        # 直接将MATLAB返回的JSON字符串解析为Python字典
        result = json.loads(json_str)

        # 检查是否成功
        if not result.get('success', False):
            return result  # 直接返回错误结果

        # 等待文件保存完成
        time.sleep(1)

        # 读取图像并转换为Base64
        image_dir = r"E:\web_code\react\fft_project\react-fft\temp\fft_images"
        image_files = ["fig1.png", "fig2.png"]

        images_base64 = {}
        for i, filename in enumerate(image_files):
            img_path = os.path.join(image_dir, filename)
            if os.path.exists(img_path):
                with open(img_path, "rb") as img_file:
                    img_data = img_file.read()
                    img_base64 = base64.b64encode(img_data).decode('utf-8')
                    images_base64[f'fig{i + 1}'] = img_base64
            else:
                return {
                    "success": False,
                    "error": f"图像文件未生成：{img_path}",
                    "images": None,
                    "fft_data": None
                }

        # 将图像数据添加到结果中
        result['images'] = images_base64

        return result

    except Exception as e:
        import traceback
        error_msg = f"Python端错误: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, file=sys.stderr)
        return {
            "success": False,
            "error": str(e),
            "images": None,
            "fft_data": None
        }


if __name__ == "__main__":
    try:
        # 1. 启动MATLAB引擎
        eng = matlab.engine.start_matlab()

        # 2. 添加MATLAB函数路径
        eng.addpath(r"E:\web_code\react\fft_project\react-fft\src\python")
        print("MATLAB引擎启动成功", file=sys.stderr)

        # 3. 从命令行接收参数
        input_json = sys.argv[1]
        params = json.loads(input_json)

        # 4. 执行生成图像的逻辑
        result = generate_fft_images(params)

        # 5. 输出JSON结果给Electron
        print(json.dumps(result))

    except Exception as e:
        import traceback

        error_msg = f"脚本执行错误：{str(e)}\n{traceback.format_exc()}"
        print(error_msg, file=sys.stderr)
        print(json.dumps({
            "success": False,
            "error": str(e),
            "images": None,
            "fft_data": None
        }))
    finally:
        # 确保MATLAB引擎关闭
        if 'eng' in locals():
            eng.quit()