"""Create a complete Windows backend ZIP with SHA-256 inventory.

Copies the current working files, including uncommitted algorithm changes.
Does not install anything, edit source files, or run MATLAB.
"""
import argparse
import datetime
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import sqlite3
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {"__pycache__", ".claude", ".agents", ".git", ".codex", ".venv", "venv"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".asv", ".db", ".db-wal", ".db-shm"}
CONTRACT_REFERENCES = (
    "src/apis/simulation.js", "src/utils/request.js",
    "src/pages/MatlabFFT/parameterContract.js", "src/pages/MatlabFFT/index.js",
    "docs/frontend-tm-contract-audit.md", "docs/receiver-monitor.md",
)


def files_under(folder):
    for directory, children, files in os.walk(str(folder), followlinks=False):
        children[:] = sorted(name for name in children
                             if name not in EXCLUDED_DIRS and not name.startswith("."))
        for name in sorted(files):
            path = Path(directory) / name
            if name.startswith(".") or path.suffix.lower() in EXCLUDED_SUFFIXES:
                continue
            if path.is_symlink():
                raise ValueError("Symlinks are not supported in a portable package: " + str(path))
            yield path


def fingerprint(path):
    info = path.stat()
    return info.st_size, info.st_mtime_ns


def source_environment():
    versions = {}
    for name in ("Flask", "Flask-Cors", "matlabengineforpython", "matlabengine", "waitress"):
        try:
            versions[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            pass
    try:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=str(ROOT),
                                         stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        commit = None
    return {"python": platform.python_version(), "platform": platform.platform(),
            "packages": versions, "gitHead": commit,
            "source": "current working files, not a git archive; see file hashes"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-history", action="store_true")
    parser.add_argument("--include-uploads", action="store_true")
    parser.add_argument("--include-results", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.channel_dir.is_dir():
        parser.error("channel-dir must be an existing directory")
    output = args.output.resolve()
    if output.suffix.lower() != ".zip":
        parser.error("output must end in .zip")
    sources = []
    for folder, prefix in ((ROOT / "src/python", "src/python"),
                           (ROOT / "deploy", "deploy"),
                           (args.channel_dir.resolve(), "channel")):
        if output == folder or folder in output.parents:
            parser.error("output must be outside copied input directories")
        sources.extend((path, prefix + "/" + path.relative_to(folder).as_posix())
                       for path in files_under(folder))
    for name in CONTRACT_REFERENCES:
        sources.append((ROOT / name, "integration-reference/" + name))
    for flag, folder in ((args.include_uploads, "artifacts/ccsds/channel_uploads"),
                         (args.include_results, "artifacts/ccsds/results")):
        if flag and (ROOT / folder).is_dir():
            sources.extend((path, path.relative_to(ROOT).as_posix()) for path in files_under(ROOT / folder))
    summary = {"files": len(sources), "uncompressedBytes": sum(p.stat().st_size for p, _ in sources),
               "output": str(output), "includeHistory": args.include_history,
               "includeUploads": args.include_uploads, "includeResults": args.include_results}
    print(json.dumps(summary, indent=2), flush=True)
    if args.dry_run:
        return
    if output.exists():
        raise FileExistsError("Refusing to overwrite existing package: " + str(output))
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_suffix(".zip.partial")
    with tempfile.TemporaryDirectory(prefix="ccsds-package-") as temp:
        if args.include_history:
            history = ROOT / "src/python/sim_history.db"
            if not history.is_file():
                raise FileNotFoundError("Requested history database does not exist")
            snapshot = Path(temp) / "sim_history.db"
            # SQLite backup yields a consistent database even if the service is up.
            with sqlite3.connect(history.as_uri() + "?mode=ro", uri=True) as source:
                with sqlite3.connect(str(snapshot)) as target:
                    source.backup(target)
            sources.append((snapshot, "src/python/sim_history.db"))
        expected = {str(path): fingerprint(path) for path, _ in sources}
        manifest = {"schemaVersion": 1, "createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "sourceEnvironment": source_environment(), "options": summary,
                    "notes": ["Full src/python tree except dot metadata, Python caches, editor backups and optional database.",
                              "Contains offline channel generator data and diagnostic scripts; not a minimal runtime dependency set.",
                              "Does not contain MATLAB, Python, installed packages, licences or frontend runtime."],
                    "files": []}
        with zipfile.ZipFile(str(partial), "x", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=1, allowZip64=True) as archive:
            for path, name in sources:
                digest = hashlib.sha256()
                length = 0
                with path.open("rb") as source, archive.open("CCSDSBackend/" + name, "w", force_zip64=True) as target:
                    for block in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(block)
                        length += len(block)
                        target.write(block)
                if fingerprint(path) != expected[str(path)] or length != expected[str(path)][0]:
                    raise RuntimeError("Source changed while packaging; rerun with a new output name: " + str(path))
                manifest["files"].append({"path": name, "bytes": length, "sha256": digest.hexdigest()})
            if any(fingerprint(path) != expected[str(path)] for path, _ in sources):
                raise RuntimeError("A source file changed during packaging; partial ZIP was not published")
            archive.writestr("CCSDSBackend/package-manifest.json",
                             json.dumps(manifest, ensure_ascii=False, indent=2))
        partial.rename(output)
    digest = hashlib.sha256()
    with output.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    with output.with_suffix(".zip.sha256").open("x", encoding="utf-8") as checksum:
        checksum.write(digest.hexdigest() + "  " + output.name + "\n")
    print(json.dumps({"package": str(output), "bytes": output.stat().st_size,
                      "sha256": digest.hexdigest(), "files": len(manifest["files"])}, indent=2), flush=True)


if __name__ == "__main__":
    main()
