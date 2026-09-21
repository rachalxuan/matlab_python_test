"""Small, read-only HTTP adapter for MATLAB's selected-result monitor.

No MATLAB import: reading progress must not wait for the busy engine. Rows
are paged without resampling or dropping error/missing-frame observations.
"""
import json
import math
import os
import threading
from collections import OrderedDict

from flask import jsonify, request


def _finite_json(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {k: _finite_json(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_finite_json(v) for v in value]
    return value


class MonitorSnapshots:
    def __init__(self, capacity=16):
        self.cache = OrderedDict()
        self.lock = threading.Lock()
        self.capacity = capacity

    def read(self, path):
        with self.lock:
            cached = self.cache.get(path)
            try:
                stat = os.stat(path)
                key = (stat.st_mtime_ns, stat.st_size)
                if cached and cached[0] == key:
                    self.cache.move_to_end(path)
                    return cached[1]
                with open(path, encoding='utf-8-sig') as handle:
                    value = _finite_json(json.load(handle))
                if not isinstance(value, dict) or value.get('schemaVersion') != 1:
                    raise ValueError('Unsupported receiver monitor schema')
                self.cache[path] = (key, value)
                self.cache.move_to_end(path)
                while len(self.cache) > self.capacity:
                    self.cache.popitem(last=False)
                return value
            except (OSError, ValueError):
                # A Windows rename/read race may briefly hide the file.
                return cached[1] if cached else None


def monitor_page(task, snapshot, after=0, limit=500):
    timeline = (snapshot or {}).get('timeline') or {}
    rows = timeline.get('Rows') or []
    if isinstance(rows, dict):
        rows = [rows]  # MATLAB encodes a scalar struct as an object.
    after = min(max(0, after), len(rows))
    end = min(len(rows), after + min(1000, max(1, limit)))
    public = {k: task.get(k) for k in (
        'taskId', 'status', 'position', 'createdAt', 'startedAt', 'finishedAt', 'error', 'summary')}
    public.update(success=True, processingMode='batch',
                  stage=(snapshot or {}).get('stage', task.get('status')),
                  publishedAtUnix=(snapshot or {}).get('publishedAtUnix'),
                  metricsReady=bool((snapshot or {}).get('metricsReady')),
                  rows=rows[after:end], nextCursor=end, totalRows=len(rows),
                  timeline={k: v for k, v in timeline.items() if k != 'Rows'})
    # Charts are bounded static snapshots, sent once, never replayed as IQ.
    if after == 0:
        for field in ('locks', 'equalizer', 'constellation', 'spectrum'):
            public[field] = (snapshot or {}).get(field)
    return public


def register_monitor_routes(app, task_snapshot, result_dir):
    snapshots = MonitorSnapshots()

    @app.get('/task_monitor/<task_id>')
    def get_receiver_monitor(task_id):
        task = task_snapshot(task_id)
        if task is None:
            return jsonify(success=False, error='任务不存在或后台已重启'), 404
        try:
            after = int(request.args.get('after', 0))
            limit = int(request.args.get('limit', 500))
            if after < 0 or not 1 <= limit <= 1000:
                raise ValueError()
        except ValueError:
            return jsonify(success=False, error='无效的监控分页参数'), 400
        path = os.path.join(result_dir(task_id), 'receiver-monitor.json')
        snapshot = snapshots.read(path)
        response = jsonify(monitor_page(task, snapshot, after, limit))
        response.headers['Cache-Control'] = 'no-store'
        return response
