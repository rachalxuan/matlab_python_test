import matlab.engine
import os
import sys
import json
import base64

# 辅助打印函数，信息会出现在 Electron 控制台


def log(msg):
    print(f"[Python Bridge] {msg}", file=sys.stderr)


def generate_fft_images(params):
    try:
        fs = float(params['fs'])
        n = int(params['n'])
        freq1 = float(params['freq1'])
        freq2 = float(params['freq2'])
        amp1 = float(params['amp1'])
        amp2 = float(params['amp2'])

        log("正在调用 MATLAB 函数...")
        # 调用 MATLAB
        json_str = eng.FFT_function(fs, n, freq1, freq2, amp1, amp2, nargout=1)

        # 解析结果
        try:
            result = json.loads(json_str)
        except json.JSONDecodeError:
            log(f"MATLAB 返回了无效的 JSON: {json_str}")
            return {"success": False, "error": "MATLAB JSON解析失败"}

        if not result.get('success', False):
            log(f"MATLAB 执行报错: {result.get('error')}")
            return result

        # === 关键：获取 MATLAB 实际保存图片的路径 ===
        save_dir = result.get('save_dir')
        log(f"MATLAB 返回图片目录: {save_dir}")

        if not save_dir or not os.path.exists(save_dir):
            log(f"错误: 目录不存在 - {save_dir}")
            # 尝试回退到脚本所在目录的相对路径
            current_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.abspath(
                os.path.join(current_dir, '..', '..'))
            save_dir = os.path.join(project_root, 'temp', 'fft_images')
            log(f"尝试备用路径: {save_dir}")

        image_files = ["fig1.png", "fig2.png"]
        images_base64 = {}

        for filename in image_files:
            img_path = os.path.join(save_dir, filename)
            log(f"正在读取图片: {img_path}")

            if os.path.exists(img_path):
                # 检查文件大小，避免读取空文件
                if os.path.getsize(img_path) > 0:
                    with open(img_path, "rb") as img_file:
                        b64_str = base64.b64encode(
                            img_file.read()).decode('utf-8')
                        # 写入 keys: fig1, fig2
                        key_name = os.path.splitext(filename)[0]
                        images_base64[key_name] = b64_str
                    log(f"读取成功: {filename}")
                else:
                    log(f"警告: 文件为空 - {img_path}")
            else:
                log(f"错误: 文件未找到 - {img_path}")

        result['images'] = images_base64

        # 检查是否真的读取到了图片
        if not images_base64:
            log("警告: 没有读取到任何图片！")
            result['warning'] = "No images found on disk"

        return result

    except Exception as e:
        import traceback
        log(f"Python 异常: {str(e)}")
        log(traceback.format_exc())
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    try:
        input_json = sys.argv[1]
        output_file_path = sys.argv[2]
        params = json.loads(input_json)

        log("启动 MATLAB 引擎...")
        eng = matlab.engine.start_matlab()

        # 添加路径
        current_dir = os.path.dirname(os.path.abspath(__file__))
        eng.addpath(current_dir)
        log(f"MATLAB 路径已添加: {current_dir}")

        result = generate_fft_images(params)

        log(f"正在写入结果文件: {output_file_path}")
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
