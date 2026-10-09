"""Read health/channels, or explicitly submit a short HTTP simulation.

Only the standard library is needed. A timeout cancels only the task this client
created; it never stops the backend process or other MATLAB sessions.
"""
import argparse
import base64
import json
from pathlib import Path
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def call(base_url, path, body=None):
    request = Request(base_url.rstrip("/") + path,
                      data=None if body is None else json.dumps(body).encode("utf-8"),
                      headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=20) as response:
            return json.load(response)
    except HTTPError as exc:
        raise RuntimeError("HTTP {}: {}".format(exc.code, exc.read().decode("utf-8", errors="replace"))) from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--run-simulation", action="store_true")
    parser.add_argument("--request", type=Path,
                        default=Path(__file__).parent / "examples" / "qpsk-no-noise.json")
    parser.add_argument("--output", type=Path, default=Path("smoke-output"))
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    health = call(args.base_url, "/health")
    models = call(args.base_url, "/channel_models")
    print(json.dumps({"health": health, "channels": models}, ensure_ascii=False, indent=2), flush=True)
    if health.get("status") != "ready" or not health.get("matlabReady"):
        raise RuntimeError("Backend does not report ready")
    if not args.run_simulation:
        return 0
    # Never overwrite a previous run's evidence.
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    params = json.loads(args.request.read_text(encoding="utf-8-sig"))
    (output / "request.json").write_text(json.dumps(params, indent=2), encoding="utf-8")
    submission = call(args.base_url, "/simulate", params)
    if not submission.get("success") or not submission.get("taskId"):
        raise RuntimeError("Submission failed: " + str(submission))
    task_id = submission["taskId"]
    (output / "submission.json").write_text(json.dumps(submission, indent=2), encoding="utf-8")
    print("Task {} submitted; results: {}".format(task_id, output), flush=True)
    deadline = time.monotonic() + args.timeout
    last_status = None
    try:
        while True:
            state = call(args.base_url, "/task_status/" + task_id)
            if state.get("status") != last_status:
                last_status = state.get("status")
                print("Status: " + str(last_status), flush=True)
            if last_status in ("completed", "failed", "cancelled"):
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Task exceeded client deadline")
            time.sleep(1)
    except (TimeoutError, KeyboardInterrupt):
        cancellation = call(args.base_url, "/cancel_task/" + task_id, {})
        print("Cancellation requested for this task only: " + str(cancellation), flush=True)
        raise
    (output / "response.json").write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    if last_status != "completed":
        raise RuntimeError("Task ended with {}: {}".format(last_status, state.get("error")))
    result = state["result"]
    metrics = result["matlab_result_data"]
    if metrics.get("success") is not True:
        raise RuntimeError("MATLAB did not report success")
    for field in ("time_base64", "spectrum_base64", "constellation_base64"):
        uri = result["images"][field]
        if not uri.startswith("data:image/png;base64,"):
            raise RuntimeError("Invalid image data URI: " + field)
        png = base64.b64decode(uri.split(",", 1)[1], validate=True)
        if not png.startswith(b"\x89PNG\r\n\x1a\n"):
            raise RuntimeError("Invalid PNG: " + field)
        (output / (field + ".png")).write_bytes(png)
    monitor = call(args.base_url, "/task_monitor/" + task_id + "?after=0&limit=500")
    (output / "monitor.json").write_text(json.dumps(monitor, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = {key: metrics.get(key) for key in (
        "BER", "NoiseMode", "SymbolRate_Hz", "ModulatorBitRate_bps", "MeasurementCoverage")}
    summary.update(taskId=task_id, imagesVerified=3,
                   acceptance="HTTP and PNG contract passed; assess BER and coverage separately.")
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        sys.exit(1)
