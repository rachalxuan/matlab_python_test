"""Launch the existing backend without React, Node or Electron.

Default: one Waitress process; --development explicitly selects Flask's server.
--check imports dependencies but does not start MATLAB or bind a network port.
"""
import argparse
import importlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT if (ROOT / "server.py").is_file() else ROOT / "src" / "python"
CHANNEL_FILES = (
    "ChannelData.mat", "2-ChannelData.mat", "3-ChannelData.mat",
    "4-ChannelData.mat", "ChannelData_5.mat", "ChannelData_6.mat",
    "ChannelData_7.mat", "ChannelData_8.mat",
)


def check_environment(channel_dir, production):
    errors = []
    dependencies = {}
    for module, distribution in (
        ("flask", "Flask"), ("flask_cors", "Flask-Cors"),
        ("matlab.engine", "matlabengineforpython"),
    ) + ((("waitress", "waitress"),) if production else ()):
        try:
            loaded = importlib.import_module(module)
            try:
                version = importlib.metadata.version(distribution)
            except importlib.metadata.PackageNotFoundError:
                version = "unknown; inspect matching MATLAB installation"
            dependencies[module] = {"version": version, "path": loaded.__file__}
        except Exception as exc:
            errors.append("Cannot import {}: {}".format(module, exc))
    required = (
        "server.py", "receiver_monitor.py", "run_ccsds_tm_evaluation.m",
        "ccsdsTMWaveformGenerator.m", "HelperCCSDSTMDecoder.m",
        "err_p64.txt",
        "FM_SOQPSK/FM_SOQPSK/data_training.mat",
        "apsk_pilotless_stage2_asm/HelperTMAPSKCarrierRecovery.m",
        "+satcom/+internal/+ccsds/tmLDPCGeneratorMatrices.mat",
        "+satcom/+internal/+ccsds/tcParityCheckMatrix.mat",
        "+satcom/+internal/+ccsds/cg_tmldpcEncodeCore_logical.mexw64",
        "+satcom/+internal/+ccsds/cg_rsencCore_int32.mexw64",
        "+satcom/+internal/+ccsds/cg_rsdecCore_int32.mexw64",
        "+satcom/+internal/+ccsds/cg_fourD8PSKTCMMod_int8.mexw64",
    )
    errors.extend("Missing backend file: " + name for name in required
                  if not (BACKEND / name).is_file())
    if platform.system() != "Windows" or struct.calcsize("P") != 8:
        errors.append("This package contains Windows x64 MEX files; other platforms need a separate port.")
    if production and sys.version_info < (3, 9):
        errors.append("Waitress 3.0.2 needs Python >=3.9. For R2022a use compatible Python 3.9, or --development for local checks.")
    channels = {name: (channel_dir / name).is_file() for name in CHANNEL_FILES}
    return {
        "ok": not errors, "python": sys.version, "executable": sys.executable,
        "root": str(ROOT), "channelDirectory": str(channel_dir),
        "dependencies": dependencies, "builtinChannels": channels,
        "warnings": ([] if all(channels.values()) else [
            "Some builtin channels are missing. No-H requests still work; missing channels must not be selected."
        ]),
        "errors": errors,
        "scope": "Static files and imports only; MATLAB startup, toolbox licences and numerical results are not tested.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--channel-dir", type=Path,
                        default=Path(os.environ.get("CCSDS_CHANNEL_DIR", str(ROOT / "channel"))))
    parser.add_argument("--development", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    channel_dir = args.channel_dir.resolve()
    report = check_environment(channel_dir, production=not args.development)
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
    if not report["ok"]:
        return 1
    if args.check:
        return 0
    os.environ["CCSDS_CHANNEL_DIR"] = str(channel_dir)
    sys.path.insert(0, str(BACKEND))
    os.chdir(str(BACKEND))
    # Import exactly once: server.py owns the one engine and one task worker.
    import server
    try:
        if args.development:
            server.app.run(host=args.host, port=args.port, use_reloader=False,
                           debug=False, threaded=True)
        else:
            from waitress import serve
            serve(server.app, host=args.host, port=args.port, threads=4,
                  max_request_body_size=server.app.config["MAX_CONTENT_LENGTH"])
    finally:
        server.eng.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
