from flask import Flask, request, jsonify
from flask_cors import CORS  # ✅ 1. 新增这行：引入插件
import matlab.engine
import os
import sys
import json
import time
import threading
import queue
import uuid

import sqlite3
import datetime

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

task_queue = queue.Queue()
tasks = {}
tasks_lock = threading.Lock()


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
            future = eng.run_ccsds_tm_evaluation(params_json, nargout=1, background=True)

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

            result_json = future.result()
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
                _set_task(
                    task_id,
                    status="completed",
                    result=result_data,
                    finishedAt=datetime.datetime.now().isoformat(timespec="seconds"),
                )
                print(f"✅ [Task {task_id}] 完成")
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


@app.route('/simulate', methods=['POST'])
def run_simulation():
    try:
        # 1. 获取前端传来的 JSON 数据
        params = request.json
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
            "hasRandomizer": params.get("hasRandomizer"),
        }
        print("[Server] 参数摘要:", json.dumps(debug_params, ensure_ascii=False))

        task_id = uuid.uuid4().hex
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
    app.run(host='127.0.0.1', port=5000, use_reloader=False, threaded=True)
