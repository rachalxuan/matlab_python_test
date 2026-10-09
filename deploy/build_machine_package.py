"""Build a flat, portable deployment copy from the user's cleaned backend.

Source files are never moved/deleted. MATLAB algorithms are copied byte for byte.
Only server.py's deployment paths are adapted, with its original saved in docs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


WORKSPACE = Path(__file__).resolve().parents[1]
EXCLUDE_ROOT = {
    "test_4d_tcm_regression.m", "test_ccsds_tm_internal_data_source.m",
    "test_tm_ldpc_decode_noiseless.m", "test_tpc_common_path.m", "test_tpc_decoded_frame_aligner.m",
    "sweep_h_channel_short_frames.m", "sweep_modcod_esno_thresholds_external.m",
    "sweep_qpsk_8psk_rs_allH.m", "sweep_tm_carrier_capture_range.m", "sweep_tm_normalized_h_system.m",
    "run_tm_apsk_pilot_damage_sweep.m", "run_tm_data_path_sweep.m", "run_tm_dualiq_triage.m",
    "debug_h_matrix_equalizer_stats_8psk.m", "TPC_SIM.m", "untitled.m", "untitled2.m",
    "extract_report_figures_from_log.py", "python_bridge.py", "python_ccsds_bridge.py", "FFT_function.m",
    "run_ccsds_FACM_modulation.m", "run_ccsds_tm_modulation.m",
    "run_ccsds_fm_extension_evaluation.m", "run_ccsds_qam_extension_evaluation.m",
    "run_ccsds_tpc_extension_evaluation.m", "run_ccsds_uqpsk_extension_evaluation.m",
    "run_qam_extension_evaluation.m", "UQPSKMod.m", "UQPSKDem.m", "InterpLag.m",
    "generate_channel_model_mat.m", "generate_channel_model_mats_7_9.m",
    "generate_named_channel_model_mats_7_9_with_large_scale.m", "convert_antenna_gain_csv.m",
    "ModSig.mat", "ModSig_300MBd_20IQRatio.mat", "sim_history.db",
    "split_path_design_notes.md", "split_path_implementation_guide.md",
}
EXCLUDE_DIRS = {"__pycache__", "apsk_pilotless_stage1", "UQPSK_modem"}
STAGE2_TESTS = {"test_apsk_pilotless_receiver_v3.m", "test_apsk_pilotless_receiver_v4.m",
                "sweep_apsk_pilotless_wide_capture.m"}
CHANNEL_FILES = ("ChannelData.mat", "2-ChannelData.mat", "3-ChannelData.mat", "4-ChannelData.mat",
                 "ChannelData_5.mat", "ChannelData_6.mat", "ChannelData_7.mat", "ChannelData_8.mat")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adapt_server(path):
    text = path.read_text(encoding="utf-8-sig")
    replacements = [
        ("project_root = os.path.abspath(os.path.join(current_dir, '..', '..'))",
         "# Standalone package root; independent of the original React/src/python layout.\n"
         "project_root = current_dir\n"
         "data_root = os.path.abspath(os.environ.get('CCSDS_DATA_DIR', os.path.join(project_root, 'data')))\n"
         "os.makedirs(data_root, exist_ok=True)"),
        ("os.path.join(project_root, 'artifacts', 'ccsds', 'channel_uploads')", "os.path.join(data_root, 'channel_uploads')"),
        ("os.path.join(project_root, 'artifacts', 'ccsds', 'results')", "os.path.join(data_root, 'results')"),
        ("r'E:\\matlab_project\\v3.0\\v3.0\\channel'", "os.path.join(project_root, 'channel')"),
        ("DB_FILE = os.path.join(os.path.dirname(\n    os.path.abspath(__file__)), 'sim_history.db')",
         "DB_FILE = os.path.join(data_root, 'sim_history.db')"),
    ]
    for before, after in replacements:
        if text.count(before) != 1:
            raise ValueError("Server changed; inspect deployment patch before rebuilding: " + before)
        text = text.replace(before, after, 1)
    path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--channel-dir", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve(); output = args.output.resolve()
    if not (source / "server.py").is_file() or not (source / "run_ccsds_tm_evaluation.m").is_file():
        parser.error("source must contain server.py and run_ccsds_tm_evaluation.m")
    if source == output or source in output.parents:
        parser.error("output must be outside source")
    if output.exists():
        parser.error("output already exists; select a new folder")
    for name in CHANNEL_FILES:
        if not (args.channel_dir / name).is_file():
            parser.error("missing channel file: " + name)
    manifest = {"source": str(source), "omitted": [], "copiedSourceFiles": [],
                "algorithmPolicy": "All retained MATLAB files are byte-identical to source; no DSP edits."}
    output.mkdir(parents=True)
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(source)
        omit = (rel.parts[0] in EXCLUDE_DIRS or any(p.startswith('.') for p in rel.parts)
                or (len(rel.parts) == 1 and rel.name in EXCLUDE_ROOT)
                or (rel.parts[0] == "apsk_pilotless_stage2_asm" and rel.name in STAGE2_TESTS))
        if omit:
            manifest["omitted"].append(rel.as_posix()); continue
        target = output / rel; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(path), str(target))
        source_hash = digest(path)
        if digest(target) != source_hash:
            raise ValueError("Source changed during copy: " + str(path))
        manifest["copiedSourceFiles"].append({"path": rel.as_posix(), "sha256": source_hash})
    (output / "docs").mkdir(exist_ok=True)
    # The cleaned source accidentally omitted this TPC decoder input table.
    # Restore the original project data; do not synthesize a replacement.
    if not (output / "err_p64.txt").is_file():
        table = WORKSPACE / "src/python/err_p64.txt"
        shutil.copy2(str(table), str(output / "err_p64.txt"))
        manifest["restoredDependencies"] = [{"path": "err_p64.txt", "source": str(table),
            "sha256": digest(table), "reason": "TPC_decoder.m:5 calls dlmread('err_p64.txt')"}]
    shutil.copy2(str(output / "server.py"), str(output / "docs/server.original.py.txt"))
    adapt_server(output / "server.py")
    manifest["serverDeploymentPatch"] = {"path": "server.py", "sha256": digest(output / "server.py"),
        "changes": ["flat package root", "CCSDS_DATA_DIR / data for uploads, results, history",
                    "local channel directory, still overridable via CCSDS_CHANNEL_DIR"]}
    (output / "channel").mkdir()
    for name in CHANNEL_FILES:
        shutil.copy2(str(args.channel_dir / name), str(output / "channel" / name))
    (output / "tests").mkdir()
    (output / "deploy").mkdir()
    for name in ("run_backend.py", "smoke_client.py", "requirements.txt", "requirements-production.txt"):
        shutil.copy2(str(WORKSPACE / "deploy" / name), str(output / "deploy" / name))
    shutil.copytree(str(WORKSPACE / "deploy/examples"), str(output / "deploy/examples"))
    shutil.copy2(str(WORKSPACE / "deploy/acceptance/run_deployment_tests.m"), str(output / "tests/run_deployment_tests.m"))
    shutil.copy2(str(WORKSPACE / "deploy/acceptance/README.md"), str(output / "README.md"))
    shutil.copy2(str(WORKSPACE / "docs/backend-file-audit.md"), str(output / "docs/backend-file-audit.md"))
    (output / "docs/cleanup-inventory.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    all_files = [p for p in output.rglob("*") if p.is_file()]
    inventory = [{"path": p.relative_to(output).as_posix(), "sha256": digest(p)} for p in sorted(all_files)]
    (output / "file-manifest.json").write_text(json.dumps(inventory, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(output), "files": len(all_files)+1,
                      "sizeMB": round(sum(p.stat().st_size for p in all_files)/1e6, 2),
                      "omittedSourceFiles": len(manifest["omitted"])}, indent=2))


if __name__ == "__main__":
    main()
