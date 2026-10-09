"""Verify every ZIP payload against its SHA-256 manifest without extracting it."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(str(args.archive)) as archive:
        manifest_name = "CCSDSBackend/package-manifest.json"
        manifest = json.loads(archive.read(manifest_name))
        expected = {manifest_name}
        count = 0
        for entry in manifest["files"]:
            path = PurePosixPath(entry["path"])
            if path.is_absolute() or ".." in path.parts or "\\" in entry["path"] or ":" in entry["path"]:
                raise ValueError("Unsafe archive path: " + str(path))
            name = "CCSDSBackend/" + str(path)
            if name in expected:
                raise ValueError("Duplicate manifest entry: " + name)
            expected.add(name)
            digest = hashlib.sha256()
            length = 0
            with archive.open(name) as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(block)
                    length += len(block)
            if digest.hexdigest() != entry["sha256"] or length != entry["bytes"]:
                raise ValueError("Hash or length mismatch: " + name)
            count += 1
        if len(archive.namelist()) != len(expected) or set(archive.namelist()) != expected:
            raise ValueError("ZIP inventory differs from manifest")
    print(json.dumps({"verifiedFiles": count, "archive": str(args.archive), "status": "PASS"}, indent=2))


if __name__ == "__main__":
    main()
