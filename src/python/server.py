from flask import Flask, request, jsonify
from flask_cors import CORS  # ✅ 1. 新增这行：引入插件
import matlab.engine
import os
import sys
import json
import time

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
    app.run(host='127.0.0.1', port=5000, use_reloader=False)
