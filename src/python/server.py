from flask import Flask, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename
from flask_cors import CORS  # ✅ 1. 新增这行：引入插件
import matlab.engine
import base64
import os
import sys
import json
import time
import threading
import queue
import uuid

import sqlite3
import datetime
from receiver_monitor import register_monitor_routes

# --- 全局单例：启动时只运行一次 MATLAB ---
print("🚀 [Server] 正在启动 MATLAB 引擎，请耐心等待 (约 5-10秒)...")
t_start = time.time()

# 启动引擎
eng = matlab.engine.start_matlab()

# 添加当前目录到路径，并放到 MATLAB path 最前面。
# 这样前端服务会优先使用本项目里改过的 ccsdsTMWaveformGenerator 和 +satcom 包。
current_dir = os.path.dirname(os.path.abspath(__file__))
eng.addpath(current_dir, '-begin', nargout=0)
eng.eval("rehash; clear classes;", nargout=0)

print(f"✅ [Server] MATLAB 引擎启动完毕！耗时: {time.time() - t_start:.2f} 秒")
# ----------------------------------------

project_root = os.path.abspath(os.path.join(current_dir, '..', '..'))
frontend_build_dir = os.path.join(project_root, 'build')

app = Flask(
    __name__,
    static_folder=frontend_build_dir,
    static_url_path='',
)
app.config['MAX_CONTENT_LENGTH'] = 256 * 1024 * 1024
CORS(app)  # ✅ 2. 新增这行：开启跨域许可

channel_upload_dir = os.path.join(project_root, 'artifacts', 'ccsds', 'channel_uploads')
os.makedirs(channel_upload_dir, exist_ok=True)
simulation_result_dir = os.path.join(project_root, 'artifacts', 'ccsds', 'results')
os.makedirs(simulation_result_dir, exist_ok=True)
channel_library_dir = os.environ.get(
    'CCSDS_CHANNEL_DIR',
    r'E:\matlab_project\v3.0\v3.0\channel',
)
channel_library = [
    ('default', '默认 ChannelData', 'ChannelData.mat'),
    ('tdl', 'TDL', '2-ChannelData.mat'),
    ('cdl', 'CDL', '3-ChannelData.mat'),
    ('itu_p681', 'ITU-P681', '4-ChannelData.mat'),
    ('jakes', 'Jakes', 'ChannelData_5.mat'),
    ('cloo', 'C. Loo', 'ChannelData_6.mat'),
    ('corazza', 'Corazza', 'ChannelData_7.mat'),
    ('lutz', 'Lutz', 'ChannelData_8.mat'),
]

task_queue = queue.Queue()
tasks = {}
tasks_lock = threading.Lock()


def _task_result_dir(task_id):
    return os.path.abspath(os.path.join(simulation_result_dir, task_id))


def _path_to_base64(file_path):
    with open(file_path, 'rb') as image_file:
        encoded = base64.b64encode(image_file.read()).decode('ascii')
    return f'data:image/png;base64,{encoded}'


def _image_paths_to_base64(image_paths, task_id):
    """Match link_simulation's three-image Base64 result contract."""
    paths = [path for path in str(image_paths).split(';') if path]
    if len(paths) != 3:
        raise ValueError(
            f'run_ccsds_tm_evaluation 必须返回 3 张图片，实际为 {len(paths)} 张'
        )

    expected_dir = _task_result_dir(task_id)
    resolved_paths = [os.path.abspath(path) for path in paths]
    for path in resolved_paths:
        if os.path.commonpath([expected_dir, path]) != expected_dir:
            raise ValueError(f'MATLAB 返回了任务目录之外的图片路径: {path}')
        if not os.path.isfile(path):
            raise FileNotFoundError(f'MATLAB 图片不存在: {path}')

    return {
        'time_base64': _path_to_base64(resolved_paths[0]),
        'spectrum_base64': _path_to_base64(resolved_paths[1]),
        'constellation_base64': _path_to_base64(resolved_paths[2]),
    }


def _task_snapshot(task_id):
    with tasks_lock:
        task = tasks.get(task_id)
        if not task:
            return None
        public_keys = [
            "taskId", "status", "position", "createdAt", "startedAt",
            "finishedAt", "result", "error", "summary",
        ]
        return {key: task.get(key) for key in public_keys if key in task}


def _set_task(task_id, **updates):
    with tasks_lock:
        if task_id in tasks:
            tasks[task_id].update(updates)


def _queue_position(task_id):
    with tasks_lock:
        queued_ids = [
            item.get("taskId")
            for item in list(task_queue.queue)
            if item.get("taskId") in tasks and tasks[item.get("taskId")].get("status") == "queued"
        ]
    try:
        return queued_ids.index(task_id) + 1
    except ValueError:
        return 0


def _worker_loop():
    while True:
        item = task_queue.get()
        task_id = item["taskId"]
        params_json = item["paramsJson"]

        with tasks_lock:
            task = tasks.get(task_id)
            if not task:
                task_queue.task_done()
                continue
            if task.get("cancelRequested"):
                task.update({
                    "status": "cancelled",
                    "finishedAt": datetime.datetime.now().isoformat(timespec="seconds"),
                })
                task_queue.task_done()
                continue
            task.update({
                "status": "running",
                "startedAt": datetime.datetime.now().isoformat(timespec="seconds"),
                "position": 0,
            })

        future = None
        try:
            print(f"▶️ [Task {task_id}] 开始 MATLAB 仿真")
            eng.eval("clear run_ccsds_tm_evaluation", nargout=0)
            future = eng.run_ccsds_tm_evaluation(params_json, nargout=2, background=True)

            while not future.done():
                with tasks_lock:
                    cancel_requested = tasks.get(task_id, {}).get("cancelRequested", False)
                if cancel_requested:
                    try:
                        future.cancel()
                    except Exception as cancel_err:
                        print(f"⚠️ [Task {task_id}] MATLAB cancel 请求失败: {cancel_err}")
                    _set_task(task_id, status="cancelling")
                    break
                time.sleep(0.2)

            result_json, image_paths = future.result()
            with tasks_lock:
                cancel_requested = tasks.get(task_id, {}).get("cancelRequested", False)

            if cancel_requested:
                _set_task(
                    task_id,
                    status="cancelled",
                    finishedAt=datetime.datetime.now().isoformat(timespec="seconds"),
                )
                print(f"⏹️ [Task {task_id}] 已停止")
            else:
                result_data = json.loads(result_json)
                print(
                    f"[Task {task_id}] ResidualCFO_Hz="
                    f"{result_data.get('ResidualCFO_Hz')} "
                    f"ResidualCFO_valid={result_data.get('ResidualCFO_valid')}"
                )
                finished_at = datetime.datetime.now().isoformat(timespec="seconds")
                if result_data.get("success") is True:
                    images = _image_paths_to_base64(image_paths, task_id)
                    result_package = {
                        "status": "success",
                        "mode": "sync",
                        "matlab_result_data": result_data,
                        "images": images,
                    }
                    _set_task(
                        task_id,
                        status="completed",
                        result=result_package,
                        finishedAt=finished_at,
                    )
                    print(f"✅ [Task {task_id}] 完成")
                else:
                    matlab_error = (
                        result_data.get("error")
                        or result_data.get("errorMsg")
                        or "MATLAB 仿真失败"
                    )
                    _set_task(
                        task_id,
                        status="failed",
                        result=result_data,
                        error=matlab_error,
                        finishedAt=finished_at,
                    )
                    print(f"❌ [Task {task_id}] MATLAB 返回失败: {matlab_error}")
        except Exception as e:
            with tasks_lock:
                cancel_requested = tasks.get(task_id, {}).get("cancelRequested", False)
            if cancel_requested:
                _set_task(
                    task_id,
                    status="cancelled",
                    finishedAt=datetime.datetime.now().isoformat(timespec="seconds"),
                    error=str(e),
                )
                print(f"⏹️ [Task {task_id}] 已停止: {e}")
            else:
                _set_task(
                    task_id,
                    status="failed",
                    error=str(e),
                    finishedAt=datetime.datetime.now().isoformat(timespec="seconds"),
                )
                print(f"❌ [Task {task_id}] 失败: {e}")
        finally:
            task_queue.task_done()


worker_thread = threading.Thread(target=_worker_loop, daemon=True)
worker_thread.start()

register_monitor_routes(app, _task_snapshot, _task_result_dir)

# 初始化数据库

DB_FILE = os.path.join(os.path.dirname(
    os.path.abspath(__file__)), 'sim_history.db')


def init_db():
    """
    检查有没有数据库，没有就创建一个。
    创建一个叫 'history' 的表，用来存放我们的仿真记录。
    """
    conn = sqlite3.connect(DB_FILE)  # 连接（或创建）数据库文件
    c = conn.cursor()               # 创建一个游标（像个指针，用来执行 SQL）

    # 执行 SQL 语句：如果表不存在，就创建
    # 字段解释：
    # id: 唯一编号，自动增加 (1, 2, 3...)
    # timestamp: 存时间字符串
    # summary: 存一些简短的配置（比如调制方式、信噪比），方便列表展示
    # full_data: 存完整的大数据（结果、波形点），用 TEXT 存 JSON 字符串
    c.execute('''
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            summary TEXT,
            full_data TEXT
        )
    ''')
    conn.commit()  # 提交保存
    conn.close()  # 哪怕是单机文件，用完也要关闭连接


# 只要程序一启动，就先运行这个函数，确保数据库就绪
init_db()

# 调用matlab接口


@app.route('/', methods=['GET'])
def frontend_index():
    """Serve the production React build from the simulation computer."""
    index_file = os.path.join(frontend_build_dir, 'index.html')
    if not os.path.isfile(index_file):
        return jsonify({
            'success': False,
            'error': 'React 前端尚未构建，请先在项目根目录执行 npm run build。',
        }), 503
    return send_from_directory(frontend_build_dir, 'index.html')


@app.route('/health', methods=['GET'])
def health():
    """Report whether the web build, MATLAB engine, and worker are ready."""
    with tasks_lock:
        running_task_ids = [
            task_id
            for task_id, task in tasks.items()
            if task.get('status') in ('running', 'cancelling')
        ]

    return jsonify({
        'status': 'ready',
        'matlabReady': eng is not None,
        'frontendBuilt': os.path.isfile(
            os.path.join(frontend_build_dir, 'index.html')
        ),
        'workerBusy': bool(running_task_ids),
        'runningTaskId': running_task_ids[0] if running_task_ids else None,
        'queueLength': task_queue.qsize(),
    })


@app.route('/channel_models', methods=['GET'])
def get_channel_models():
    models = []
    for model_id, label, file_name in channel_library:
        file_path = os.path.abspath(os.path.join(channel_library_dir, file_name))
        models.append({
            'id': model_id,
            'label': label,
            'fileName': file_name,
            'path': file_path,
            'available': os.path.isfile(file_path),
            'source': 'builtin',
        })
    for stored_name in sorted(os.listdir(channel_upload_dir)):
        if not stored_name.lower().endswith('.mat'):
            continue
        display_name = stored_name.split('_', 1)[-1]
        models.append({
            'id': f'upload:{stored_name}',
            'label': f'自定义：{display_name}',
            'fileName': display_name,
            'path': os.path.abspath(os.path.join(channel_upload_dir, stored_name)),
            'available': True,
            'source': 'upload',
        })
    return jsonify({'success': True, 'models': models})


@app.route('/upload_channel', methods=['POST'])
def upload_channel():
    upload = request.files.get('file')
    if upload is None or not upload.filename:
        return jsonify({'success': False, 'error': '未选择 MAT 文件'}), 400

    original_name = upload.filename
    if not original_name.lower().endswith('.mat'):
        return jsonify({'success': False, 'error': '只允许上传 .mat 信道文件'}), 400
    safe_name = secure_filename(original_name)
    if not safe_name.lower().endswith('.mat'):
        safe_name = 'channel.mat'

    stored_name = f'{uuid.uuid4().hex}_{safe_name}'
    stored_path = os.path.abspath(os.path.join(channel_upload_dir, stored_name))
    upload.save(stored_path)
    return jsonify({
        'success': True,
        'model': {
            'id': f'upload:{stored_name}',
            'label': original_name,
            'fileName': safe_name,
            'path': stored_path,
            'available': True,
            'source': 'upload',
        },
    })


@app.route('/simulate', methods=['POST'])
def run_simulation():
    try:
        # 1. 获取前端传来的 JSON 数据
        params = dict(request.get_json(silent=True) or {})
        task_id = uuid.uuid4().hex
        output_dir = _task_result_dir(task_id)
        os.makedirs(output_dir, exist_ok=True)

        # 远控接口固定生成参考项目同款的三张 PNG。完整绘图数组默认关闭；
        # 以后确实需要时，调用方可显式传 includeRawData=true 重新开启。
        params['remoteMode'] = True
        params['includeRawData'] = bool(params.get('includeRawData', False))
        params['outputDir'] = output_dir
        # Monitoring only exports receiver evidence; it never steers DSP.
        params['enableWebMonitor'] = True
        params['enableRuntimeLockTelemetry'] = True
        params['enableReceiverTimeline'] = True
        params_json = json.dumps(params)

        print(f"📩 [Server] 收到仿真请求: Mod={params.get('modType', 'Unknown')}")

        # 2. 调用 MATLAB
        debug_params = {
            "modType": params.get("modType"),
            "symbolRate": params.get("symbolRate"),
            "sps": params.get("sps"),
            "snr": params.get("snr"),
            "cfo": params.get("cfo"),
            "phaseOffset": params.get("phaseOffset"),
            "delay": params.get("delay"),
            "channelCoding": params.get("channelCoding"),
            "ConvolutionalCodeRate": params.get("ConvolutionalCodeRate"),
            "CodeRate": params.get("CodeRate"),
            "NumBytesInTransferFrame": params.get("NumBytesInTransferFrame"),
            "RSMessageLength": params.get("RSMessageLength"),
            "RSInterleavingDepth": params.get("RSInterleavingDepth"),
            "IsRSMessageShortened": params.get("IsRSMessageShortened"),
            "RSShortenedMessageLength": params.get("RSShortenedMessageLength"),
            "RolloffFactor": params.get("RolloffFactor"),
            "hasASM": params.get("hasASM"),
            "RandomizerEnabled": params.get("RandomizerEnabled"),
            "RandomizerFECPosition": params.get("RandomizerFECPosition"),
            "DataPathMode": params.get("DataPathMode"),
            "berWarmUpFrames": params.get("berWarmUpFrames"),
            "berFrames": params.get("berFrames"),
            "TMDataSource": params.get("TMDataSource"),
            "TMDataSourceI": params.get("TMDataSourceI"),
            "TMDataSourceQ": params.get("TMDataSourceQ"),
            "WaveformMode": params.get("WaveformMode"),
            "AGCEnabled": params.get("AGCEnabled"),
            "AGCTimeConstantMs": params.get("AGCTimeConstantMs"),
            "enableHChannel": params.get("enableHChannel"),
            "HMode": params.get("HMode"),
            "channelFilePath": params.get("channelFilePath"),
            "channelFilePaths": params.get("channelFilePaths"),
            "channelSampleRateHz": params.get("channelSampleRateHz"),
            "enableEqualizer": params.get("enableEqualizer"),
        }
        print("[Server] 参数摘要:", json.dumps(debug_params, ensure_ascii=False))

        now = datetime.datetime.now().isoformat(timespec="seconds")
        with tasks_lock:
            tasks[task_id] = {
                "taskId": task_id,
                "status": "queued",
                "position": task_queue.qsize() + 1,
                "createdAt": now,
                "summary": debug_params,
                "cancelRequested": False,
            }
        task_queue.put({"taskId": task_id, "paramsJson": params_json})

        return jsonify({
            "success": True,
            "taskId": task_id,
            "status": "queued",
            "position": _queue_position(task_id),
        })

    except Exception as e:
        print(f"❌ [Server] 发生错误: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/task_status/<task_id>', methods=['GET'])
def get_task_status(task_id):
    task = _task_snapshot(task_id)
    if not task:
        return jsonify({"success": False, "error": "任务不存在"}), 404

    if task.get("status") == "queued":
        task["position"] = _queue_position(task_id)
    task["success"] = True
    return jsonify(task)


@app.route('/cancel_task/<task_id>', methods=['POST'])
def cancel_task(task_id):
    with tasks_lock:
        task = tasks.get(task_id)
        if not task:
            return jsonify({"success": False, "error": "任务不存在"}), 404

        status = task.get("status")
        if status in ("completed", "failed", "cancelled"):
            return jsonify({
                "success": True,
                "taskId": task_id,
                "status": status,
                "message": "任务已经结束",
            })

        task["cancelRequested"] = True
        if status == "queued":
            task["status"] = "cancelled"
            task["finishedAt"] = datetime.datetime.now().isoformat(timespec="seconds")
        elif status == "running":
            task["status"] = "cancelling"
        new_status = task.get("status")

    return jsonify({
        "success": True,
        "taskId": task_id,
        "status": new_status,
    })


# 存入数据库接口
@app.route('/save_record', methods=['POST'])
def save_record():
    try:
        # 1. 拿到前端发来的数据
        data = request.json
        # 前端会传两部分：config(配置) 和 result(结果)
        config = data.get('config', {})
        result = data.get('result', {})

        # 2. 准备要存的数据
        # 获取当前时间
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # 提取关键信息做摘要（方便以后在列表中只显示这些，不用加载全部数据）
        summary_info = {
            "modType": config.get('modType', 'Unknown'),
            "snr": config.get('snr', 0),
            "symbolRate": config.get('symbolRate', 0)
        }

        # 将摘要和完整数据都转成 JSON 字符串（序列化）
        summary_str = json.dumps(summary_info)
        full_data_str = json.dumps(data)  # 把整个 config+result 打包存起来

        # 3. 写入数据库
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute('''
            INSERT INTO history (timestamp, summary, full_data)
            VALUES (?, ?, ?)
        ''', (timestamp, summary_str, full_data_str))

        conn.commit()
        conn.close()

        print(f"💾 [Server] 数据已保存: {timestamp}")
        return jsonify({"success": True, "message": "保存成功"})

    except Exception as e:
        print(f"❌ [Server] 保存失败: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

# 读档接口


@app.route('/get_history_list', methods=['GET'])
def get_history_list():
    """只获取列表摘要，不读取庞大的 full_data"""
    try:
        conn = sqlite3.connect(DB_FILE)
        conn.row_factory = sqlite3.Row  # 这行代码让我们可以用字段名访问数据
        c = conn.cursor()

        # 只查询 id, timestamp, summary 三列
        c.execute('SELECT id, timestamp, summary FROM history ORDER BY id DESC')
        rows = c.fetchall()
        conn.close()

        # 整理成列表返回给前端
        history_list = []
        for row in rows:
            history_list.append({
                "id": row['id'],
                "timestamp": row['timestamp'],
                "summary": json.loads(row['summary'])  # 把字符串还原成对象
            })

        return jsonify(history_list)
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/get_record_detail', methods=['POST'])
def get_record_detail():
    """根据 ID 获取完整数据"""
    try:
        record_id = request.json.get('id')

        conn = sqlite3.connect(DB_FILE)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # 根据 ID 精确查找
        c.execute('SELECT full_data FROM history WHERE id = ?', (record_id,))
        row = c.fetchone()
        conn.close()

        if row:
            # 拿到 full_data 并解析
            return jsonify({
                "success": True,
                "data": json.loads(row['full_data'])
            })
        else:
            return jsonify({"success": False, "error": "未找到该记录"}), 404

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


if __name__ == '__main__':
    # 启动 HTTP 服务
    app.run(host='0.0.0.0', port=5000, use_reloader=False, threaded=True)
