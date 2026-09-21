"""Run: python -m unittest discover -s src/python/regression -p test_receiver_monitor.py"""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flask import Flask
from receiver_monitor import MonitorSnapshots, monitor_page, register_monitor_routes


class ReceiverMonitorTests(unittest.TestCase):
    def setUp(self):
        self.task = dict(taskId='case1', status='running', summary={'modType': 'QPSK'})

    def test_no_snapshot_is_unknown_not_zero(self):
        page = monitor_page(self.task, None)
        self.assertFalse(page['metricsReady'])
        self.assertEqual(page['rows'], [])
        self.assertEqual(page['processingMode'], 'batch')
        self.assertNotIn('BER', page)

    def test_paging_preserves_missing_and_error_rows(self):
        rows = [dict(TxFrameIndex=k, ErrorBitsDelta=2 if k == 2 else 0,
                     ComparedBitsDelta=0 if k == 3 else 128) for k in range(1, 6)]
        snapshot = dict(schemaVersion=1, metricsReady=True, timeline=dict(Rows=rows))
        first = monitor_page(self.task, snapshot, 0, 2)
        second = monitor_page(self.task, snapshot, first['nextCursor'], 3)
        self.assertEqual(first['rows'] + second['rows'], rows)
        self.assertEqual(second['nextCursor'], 5)
        self.assertNotIn('constellation', second)

    def test_scalar_row_from_matlab(self):
        snapshot = dict(timeline=dict(Rows=dict(TxFrameIndex=1)))
        self.assertEqual(len(monitor_page(self.task, snapshot)['rows']), 1)

    def test_cache_read_race_and_finite_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, 'receiver-monitor.json')
            cache = MonitorSnapshots()
            self.assertIsNone(cache.read(path))
            Path(path).write_text('{"schemaVersion":1,"value":NaN}', encoding='utf-8')
            self.assertIsNone(cache.read(path)['value'])
            Path(path).write_text('{', encoding='utf-8')
            self.assertEqual(cache.read(path)['schemaVersion'], 1)

    def test_route_is_lightweight_and_validates_cursor(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Flask(__name__)
            register_monitor_routes(app, lambda task_id: self.task if task_id == 'case1' else None, lambda _: folder)
            client = app.test_client()
            self.assertEqual(client.get('/task_monitor/missing').status_code, 404)
            self.assertEqual(client.get('/task_monitor/case1?after=-1').status_code, 400)
            self.assertEqual(client.get('/task_monitor/case1?limit=1001').status_code, 400)
            response = client.get('/task_monitor/case1')
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers['Cache-Control'], 'no-store')
            self.assertNotIn('result', response.json)
            json.dumps(response.json, allow_nan=False)


if __name__ == '__main__':
    unittest.main()
