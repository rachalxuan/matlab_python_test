# matlab_bridge.py
import matlab.engine
import os
import time
import sys
import json
import base64


def generate_fft_images(params):
    """生成FFT图像（接收参数字典，返回结果字典）"""
    try:
        # 从参数字典中提取参数
        fs = float(params['fs'])
        n = float(params['n'])
        freq1 = float(params['freq1'])
        freq2 = float(params['freq2'])
        amp1 = float(params['amp1'])
        amp2 = float(params['amp2'])

        print(f"调用MATLAB函数: fs={fs}, n={n}, freq1={freq1}, freq2={freq2}, amp1={amp1}, amp2={amp2}", file=sys.stderr)

        # 调用MATLAB函数
        eng.FFT_function(fs, n, freq1, freq2, amp1, amp2, nargout=0)

        # 等待文件保存完成
        time.sleep(1)

        # 图像文件路径
        image_dir = r"E:\Python_project\Matlab_Py"
        image_files = ["fig1.png", "fig2.png"]

        # 读取图像并转换为Base64
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
                    "images": None
                }

        # 成功时返回状态和Base64图像数据
        return {
            "success": True,
            "error": None,
            "images": images_base64,
            "parameters": {
                'fs': fs,
                'n': n,
                'freq1': freq1,
                'freq2': freq2,
                'amp1': amp1,
                'amp2': amp2
            }
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "images": None
        }


if __name__ == "__main__":
    try:
        # 1. 启动MATLAB引擎
        eng = matlab.engine.start_matlab()
        eng.addpath(r"E:\Python_project\Matlab_Py")

        # 2. 从命令行接收Electron传递的参数
        input_json = sys.argv[1]
        params = json.loads(input_json)

        # 3. 执行生成图像的逻辑
        result = generate_fft_images(params)

        # 4. 输出结果给Electron
        print(json.dumps(result))

    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": f"脚本执行错误：{str(e)}",
            "images": None
        }))
    finally:
        # 确保MATLAB引擎关闭
        if 'eng' in locals():
            eng.quit()