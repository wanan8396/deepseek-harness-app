#!/usr/bin/env python3
"""Build an unpatched official DSH payload over a verified, immutable system seed.

The seed supplies only the unchanged Ubuntu/Python/Node/pnpm system. No installed
phone filesystem or user home is used. The official npm prefix is installed from
runtime/locks with Linux/ABI optional dependencies before invoking this builder.
The original output remains separate until its archive and metadata are verified.
"""
from __future__ import annotations

import argparse
import copy
import lzma
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import posixpath
import shutil
import tarfile
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
EPOCH = 1767225600
OFFICIAL_VERSION = "0.2.2-rc.3"
ENGINE_PATHS = [
    "opt/dsh", "opt/node", "etc/dsh-app",
    "etc/profile.d/dsh-app.sh", "usr/local/lib/node_modules/pnpm",
    "usr/local/bin/dsh", "usr/local/bin/node", "usr/local/bin/npm", "usr/local/bin/npx",
    "usr/local/bin/corepack", "usr/local/bin/pnpm", "usr/local/bin/pnpx", "usr/local/bin/pn", "usr/local/bin/pnx",
]


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def tree_member(name: str, prefix: str) -> bool:
    return name == prefix or name.startswith(prefix + "/")


def check_member(name: str) -> str:
    # Never silently reinterpret an absolute or escaping archive member.
    if name.startswith("/") or "\\" in name:
        raise ValueError(f"Invalid archive path: {name}")
    while name.startswith("./"):
        name = name[2:]
    name = name.rstrip("/")
    if not name or name == "." or posixpath.normpath(name) != name or ".." in name.split("/"):
        raise ValueError(f"Invalid archive path: {name}")
    return name


def official_identity(prefix: Path) -> dict:
    package = read_json(prefix / "node_modules/@deepseek-ai/dsh/package.json")
    if package.get("name") != "@deepseek-ai/dsh" or package.get("version") != OFFICIAL_VERSION:
        raise ValueError("The prefix is not the pinned official DSH release")
    expected = ROOT / f"runtime/locks/dsh-{OFFICIAL_VERSION}/package-lock.json"
    if sha256(expected) != sha256(prefix / "package-lock.json"):
        raise ValueError("The prefix lock differs from the committed official lock input")
    return {"name": package["name"], "version": package["version"],
            "registry": "https://registry.npmjs.org/", "lockSha256": sha256(expected)}


def describe_official_manifest(seed: dict, prefix: Path) -> dict:
    identity = official_identity(prefix)
    descriptor = seed.get("upgrade")
    if not isinstance(descriptor, dict) or descriptor.get("schema") != 1:
        raise ValueError("The verified system seed must carry the engine-upgrade contract")
    # Keep the seed's verified system identity, not its retired mutation slots.
    if (not isinstance(descriptor.get("baseId"), str) or
            not isinstance(descriptor.get("paths"), list) or
            any(path not in descriptor["paths"] for path in ENGINE_PATHS)):
        raise ValueError("Unexpected engine upgrade path contract")
    upgrade = copy.deepcopy(descriptor)
    upgrade["paths"] = list(ENGINE_PATHS)
    runtime = {
        "runtimeVersion": f"r17-official-dsh{OFFICIAL_VERSION}-node{seed['nodeVersion']}-{identity['lockSha256'][:12]}",
        "abi": seed["abi"], "dshVersion": OFFICIAL_VERSION,
        "nodeVersion": seed["nodeVersion"], "pnpmVersion": seed["pnpmVersion"],
        "ubuntuVersion": seed["ubuntuVersion"], "prootVersion": seed["prootVersion"],
        "engineDistribution": "official-unmodified",
        "capabilities": {"legacyBridge": False, "enginePatches": False},
        "officialPackage": identity, "upgrade": upgrade,
    }
    return runtime


def overlay(runtime: dict) -> dict[str, tuple[str, int, bytes | str]]:
    info = (json.dumps(runtime, ensure_ascii=False, indent=2) + "\n").encode()
    return {
        "etc/dsh-app": ("dir", 0o755, b""),
        "etc/dsh-app/runtime.json": ("file", 0o644, info),
        "usr/local/bin/dsh": ("file", 0o755, (
            "#!/bin/sh\n"
            "# DeepSeek Assistant: invoke the unmodified official npm CLI.\n"
            "exec /opt/node/bin/node /opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js \"$@\"\n"
        ).encode()),
    }


def launch(seed: dict) -> dict:
    value = copy.deepcopy(seed["launch"])
    expected = "exec /usr/local/bin/dsh web --patch /etc/dsh-app/dsh-web.patch.yml"
    hits = 0
    for i, arg in enumerate(value["argv"]):
        if expected in arg:
            value["argv"][i] = arg.replace(expected, "exec /usr/local/bin/dsh web")
            hits += 1
    if hits != 1:
        raise ValueError("The seed must have one known DSH launch command")
    if any("--patch" in arg or "--import=" in arg for arg in value["argv"]):
        raise ValueError("An engine patch or legacy preload remained in official launch")
    return value


def source_module():
    # Load only pure artifact helpers, never the legacy patched runtime CLI.
    spec = importlib.util.spec_from_file_location("runtime_artifacts", ROOT / "runtime/lib/runtime_artifacts.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build(seed_path: Path, prefix: Path, output: Path, work: Path) -> dict:
    seed = read_json(seed_path)
    runtime = describe_official_manifest(seed, prefix)
    archive = seed_path.parent / seed["rootfs"]
    if archive.stat().st_size != seed["rootfsBytes"] or sha256(archive) != seed["rootfsSha256"]:
        raise ValueError("System seed checksum/size mismatch")
    if seed.get("engineDistribution") == "official-unmodified":
        raise ValueError("Use the preserved immutable system seed, not a previously repacked engine")
    if seed["abi"] != "arm64-v8a":
        raise ValueError("This builder currently validates Linux ARM64 only")
    if output.resolve() == seed_path.parent.parent.parent.resolve():
        raise ValueError("Build into a separate output, not over the seed")
    output.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    base_tar = work / "system-seed.tar"
    excluded = ("opt/dsh", "opt/dsh-go", "etc/dsh-app")
    # A sequential pass never loads the whole rootfs in memory or follows links.
    with tarfile.open(archive, "r|*") as source, tarfile.open(base_tar, "w", format=tarfile.GNU_FORMAT) as target:
        for member in source:
            name = check_member(member.name)
            if any(tree_member(name, p) for p in excluded) or name == "usr/local/bin/dsh":
                continue
            if not (member.isdir() or member.isreg() or member.issym()):
                raise ValueError(f"Unexpected system seed member type: {name}")
            target.addfile(member, source.extractfile(member) if member.isreg() else None)
    helpers = source_module()
    entries = {}  # name -> ('base' | 'prefix' | 'overlay', metadata)
    dropped = Counter()
    package_files = {}
    with tarfile.open(base_tar, "r:") as base:
        for member in base.getmembers():
            entries[member.name] = ("base", member)
        for path in sorted(prefix.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(prefix).as_posix()
            if rel.startswith("node_modules/.bin/"):
                continue  # npm Windows command wrappers are not Linux executables.
            reason = helpers.dsh_drop_reason(rel, seed["abi"], True)
            if reason:
                dropped[reason] += path.stat().st_size
                continue
            if path.is_symlink():
                raise ValueError(f"Expected materialized npm prefix, not host link: {rel}")
            with path.open("rb") as stream:
                magic = stream.read(4)
            mode = 0o644
            if magic == b"\x7fELF":
                summary = helpers.elf_summary(path.read_bytes())
                if summary["e_machine"] != 183 or summary["musl"]:
                    dropped["foreign-native"] += path.stat().st_size
                    continue
                if summary["type"] in ("EXEC", "DYN") and not rel.endswith((".so", ".node")):
                    mode = 0o755
            if rel.endswith(".sh") or path.name == "spawn-helper" or "/bin/" in rel:
                mode = 0o755
            entries["opt/dsh/" + rel] = ("prefix", (path, mode))
            # Inventory every shipped official package file, including package metadata.
            if rel.startswith("node_modules/@deepseek-ai/dsh/"):
                package_files[rel] = sha256(path)
        for name, value in overlay(runtime).items():
            entries[name] = ("overlay", value)
        for name in list(entries):
            parent = posixpath.dirname(name)
            while parent and parent not in entries:
                entries[parent] = ("overlay", ("dir", 0o755, b""))
                parent = posixpath.dirname(parent)
        final = output / "assets/runtime/rootfs-arm64-v8a.tar.xz"
        final.parent.mkdir(parents=True, exist_ok=True)
        temporary = final.with_suffix(final.suffix + ".tmp")
        counts = Counter()
        uncompressed = 0
        with lzma.open(temporary, mode="wb", preset=3) as zipped:
            with tarfile.open(fileobj=zipped, mode="w|", format=tarfile.GNU_FORMAT) as tar:
                for name in sorted(entries, key=lambda n: n.split("/")):
                    origin, value = entries[name]
                    member = tarfile.TarInfo(name)
                    member.uid = member.gid = 0
                    member.uname = member.gname = "root"
                    member.mtime = EPOCH
                    data = None
                    if origin == "base":
                        original = value
                        member.mode = original.mode
                        member.type = original.type
                        member.linkname = original.linkname
                        member.size = original.size
                        if member.isreg():
                            data = base.extractfile(original)
                    elif origin == "prefix":
                        path, member.mode = value
                        member.size = path.stat().st_size
                        data = path.open("rb")
                    else:
                        kind, member.mode, payload = value
                        if kind == "dir":
                            member.type = tarfile.DIRTYPE
                        elif kind == "symlink":
                            member.type = tarfile.SYMTYPE
                            member.linkname = payload
                        else:
                            member.size = len(payload)
                            data = io.BytesIO(payload)
                    # No member may be written beneath a symlink or non-directory.
                    parent = posixpath.dirname(name)
                    while parent:
                        parent_kind, parent_value = entries[parent]
                        is_dir = parent_value.isdir() if parent_kind == "base" else parent_kind == "overlay" and parent_value[0] == "dir"
                        if not is_dir:
                            raise ValueError(f"Member below non-directory: {name}")
                        parent = posixpath.dirname(parent)
                    if member.issym():
                        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
                        if member.linkname.startswith("/") or resolved == ".." or resolved.startswith("../"):
                            raise ValueError(f"Invalid symbolic link: {name}")
                    counts["dir" if member.isdir() else "symlink" if member.issym() else "file"] += 1
                    uncompressed += member.size
                    try:
                        tar.addfile(member, data)
                    finally:
                        if data is not None:
                            data.close()
        os.replace(temporary, final)
    manifest = copy.deepcopy(seed)
    for name in ("dshPatches", "dshGoBridge", "directEngine", "pluginRegistries"):
        manifest.pop(name, None)
    manifest.update(runtime)
    manifest.update({"rootfs": final.name, "rootfsFormat": "tar.xz", "rootfsSha256": sha256(final),
                     "rootfsBytes": final.stat().st_size, "uncompressedBytes": uncompressed,
                     "entries": dict(counts), "launch": launch(seed),
                     "archiveNotes": "GNU tar, parent-before-child, regular files/directories/relative symlinks only; system seed unchanged outside exact engine trees",
                     "build": {"systemSeedSha256": seed["rootfsSha256"], "officialLockSha256": runtime["officialPackage"]["lockSha256"],
                               "sourceDateEpoch": EPOCH, "npmPlatform": "linux", "npmCpu": "arm64", "npmLibc": "glibc"}})
    manifest.pop("tarBytes", None)
    manifest.pop("tarSha256", None)
    (final.parent / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    # A checksum-verified original native tree may live separately from a retained seed.
    native_source = seed_path.parents[2] / "jniLibs"
    if not native_source.is_dir():
        native_source = ROOT / "runtime/out" / seed["abi"] / "jniLibs"
    for name, metadata in seed["jniLibs"].items():
        native_file = native_source / seed["abi"] / name
        if native_file.stat().st_size != metadata["bytes"] or sha256(native_file) != metadata["sha256"]:
            raise ValueError(f"Native system seed checksum mismatch: {name}")
    shutil.copytree(native_source, output / "jniLibs", dirs_exist_ok=True)
    report = {"runtime": runtime, "rootfsSha256": manifest["rootfsSha256"], "rootfsBytes": manifest["rootfsBytes"],
              "entries": dict(counts), "droppedBytes": dict(dropped), "officialCliFileHashes": package_files,
              "legacyRuntimeCodeIncluded": False}
    (output / "official-runtime-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-manifest", type=Path, required=True)
    parser.add_argument("--official-prefix", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    report = build(args.seed_manifest, args.official_prefix, args.output, args.work)
    print(json.dumps({k: report[k] for k in ("rootfsSha256", "rootfsBytes", "entries", "legacyRuntimeCodeIncluded")}, indent=2))


if __name__ == "__main__":
    main()
