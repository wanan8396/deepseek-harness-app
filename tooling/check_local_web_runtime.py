#!/usr/bin/env python3
"""Fail before APK assembly when the phone-local runtime is missing or corrupt."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ABIS = {"arm64": "arm64-v8a", "x64": "x86_64"}
REQUIRED_LIBS = ("libproot.so", "libproot-loader.so", "libtalloc.so", "libandroid-shmem.so")


def verified_file(directory, name, metadata):
    if not isinstance(name, str) or not name or Path(name).name != name or "/" in name or "\\" in name:
        raise ValueError("Invalid runtime asset name")
    path = directory / name
    if not path.is_file():
        raise ValueError(f"Missing runtime asset: {path}")
    expected_size = metadata.get("bytes")
    digest = metadata.get("sha256")
    if not isinstance(expected_size, int) or expected_size <= 0 or path.stat().st_size != expected_size:
        raise ValueError(f"Runtime asset size mismatch: {path}")
    if not isinstance(digest, str) or len(digest) != 64:
        raise ValueError(f"Missing SHA256 in runtime manifest: {name}")
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    if hasher.hexdigest() != digest.lower():
        raise ValueError(f"Runtime asset SHA256 mismatch: {path}")


def check_runtime(root, flavor, *, official=False):
    abi = ABIS[flavor]
    base = Path(root) / "runtime" / "out" / abi
    assets = base / "assets" / "runtime"
    manifest_path = assets / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"Missing {manifest_path}; prepare the official payload with "
                         "python runtime/build-official-runtime.py (see runtime/README.official.md)")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("abi") != abi or not manifest.get("runtimeVersion") or not manifest.get("dshVersion"):
        raise ValueError(f"Invalid ABI/version in {manifest_path}")
    if official:
        capabilities = manifest.get("capabilities")
        if (manifest.get("engineDistribution") != "official-unmodified" or not isinstance(capabilities, dict)
                or capabilities.get("legacyBridge") is not False or capabilities.get("enginePatches") is not False):
            raise ValueError("official_runtime_required: Lite builds require the unmodified official distribution")
        argv = manifest.get("launch", {}).get("argv", [])
        if not argv or any("--patch" in arg or "--import=" in arg for arg in argv):
            raise ValueError("Official Lite launch contains a legacy patch or preload")
    # Android's asset packager transparently inflates *.gz and strips that suffix.
    # The installer needs the exact named archive plus its compressed-byte digest.
    if str(manifest.get("rootfs", "")).endswith(".gz"):
        raise ValueError("Gzip runtime assets are renamed by Android packaging; use tar.xz")
    verified_file(assets, manifest["rootfs"], {
        "bytes": manifest.get("rootfsBytes"), "sha256": manifest.get("rootfsSha256")})
    libraries = manifest.get("jniLibs", {})
    for name in REQUIRED_LIBS:
        if name not in libraries:
            raise ValueError(f"Missing required JNI library in manifest: {name}")
    for name, metadata in libraries.items():
        verified_file(base / "jniLibs" / abi, name, metadata)
    return abi


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flavor", choices=[*ABIS, "all"], default="arm64")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--official", action="store_true", help="require the unmodified official Lite distribution")
    args = parser.parse_args(argv)
    try:
        flavors = ABIS if args.flavor == "all" else [args.flavor]
        for flavor in flavors:
            abi = check_runtime(args.root, flavor, official=args.official)
            print(f"Phone-local runtime verified: {abi}")
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"local-web-build: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
