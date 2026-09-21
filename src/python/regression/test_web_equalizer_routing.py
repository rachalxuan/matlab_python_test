"""Opt-in localhost smoke test. Uses the real MATLAB worker, not mocked IQ.
Run only with the local simulation server already started.
"""
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen


def api(path, body=None):
    req = Request('http://127.0.0.1:5000' + path,
                  data=None if body is None else json.dumps(body).encode(),
                  headers={'Content-Type': 'application/json'})
    with urlopen(req, timeout=15) as response:
        return json.load(response)


def main():
    rows = []
    for mode in ('1sps', '2sps', '2sps-dual'):
        p = dict(modType='QPSK', channelCoding='none', WaveformMode='ordinaryTM',
                 symbolRate=50e6, sps=8, snr=100, noiseMode='off',
                 cfo=0, phaseOffset=0, delay=0, NumBytesInTransferFrame=1151,
                 hasASM=True, RandomizerEnabled=False, AGCEnabled=False,
                 DataPathMode='single', enableHChannel=True, HMode='siso_multipath',
                 H={'real': [1, 0, 0.05], 'imag': [0, 0, 0.05]}, normalizeHChannel=True,
                 enableEqualizer=True, equalizerMode='blind-cma-lms',
                 adaptiveEqualizerSamplingMode=mode, adaptiveFractionalPostMode='off',
                 berWarmUpFrames=8, berFrames=12, excludeBERWarmUpFrames=True,
                 RolloffFactor=.35, FilterSpanInSymbols=10, showFigures=False)
        task = api('/simulate', p)
        assert task.get('success'), task
        task_id = task['taskId']
        deadline = time.monotonic() + 600
        while time.monotonic() < deadline:
            state = api('/task_status/' + task_id)
            if state['status'] in ('completed', 'failed', 'cancelled'):
                break
            time.sleep(2)
        else:
            raise TimeoutError(task_id)
        envelope = state.get('result', {})
        r = envelope.get('matlab_result_data', envelope)
        if isinstance(r, str):
            r = json.loads(r)
        row = dict(requested=mode, taskId=task_id, success=r.get('success'),
                   actual=r.get('AdaptiveEqualizerMode'),
                   applied=r.get('AdaptiveEqualizerEnabled'),
                   fractionalApplied=r.get('AdaptiveFractionalEqualizerApplied'),
                   noiseMode=r.get('NoiseMode'), BER=r.get('BER'),
                   coverage=r.get('ReceiverTimeline', {}).get('MeasurementCoverage'),
                   error=r.get('error'))
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    folder = Path(__file__).resolve().parents[3] / 'artifacts/ccsds/frontend-contract'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'equalizer-http.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding='utf-8')
    for row in rows:
        assert row['success'] and row['noiseMode'] == 'off', row
        assert row['applied'], row
        if row['requested'] != '1sps':
            assert row['fractionalApplied'], row
    print('PASS: requested adaptive equalizers were actually used. BER/coverage are reported separately.')


if __name__ == '__main__':
    main()
