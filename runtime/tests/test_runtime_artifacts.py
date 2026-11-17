"""Independent binary/path fixtures for the official, side-effect-free helpers."""
import importlib.util
import io
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest

RUNTIME = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("artifact_helpers", RUNTIME / "lib/runtime_artifacts.py")
artifacts = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(artifacts)


def elf_fixture(bits=64, machine=183, kind=3, interp="/lib/ld-linux-aarch64.so.1",
                needed=("libc.so.6",), malformed_dynamic=False):
    """Encode ELF structures directly from the ELF ABI, not through production code."""
    data = bytearray(2048)
    ident = b"\x7fELF" + bytes((2 if bits == 64 else 1, 1, 1)) + bytes(9)
    phsize, ehsize = (56, 64) if bits == 64 else (32, 52)
    phnum = 3 if interp is not None else 2
    header = "<16sHHIQQQIHHHHHH" if bits == 64 else "<16sHHIIIIIHHHHHH"
    struct.pack_into(header, data, 0, ident, kind, machine, 1, 0, ehsize,
                     0, 0, ehsize, phsize, phnum, 64 if bits == 64 else 40, 0, 0)

    def program(index, typ, offset, size, align=8):
        if bits == 64:
            struct.pack_into("<IIQQQQQQ", data, ehsize + index * phsize,
                             typ, 5, offset, 0x10000 + offset, 0, size, size, align)
        else:
            struct.pack_into("<IIIIIIII", data, ehsize + index * phsize,
                             typ, offset, 0x10000 + offset, 0, size, size, 5, align)

    program(0, 1, 0, len(data), 16384)
    strings = bytearray(b"\0")
    def string(value):
        index = len(strings)
        strings.extend(value.encode() + b"\0")
        return index
    indexes = [string(name) for name in needed]
    soname, runpath = string("fixture.so"), string("$ORIGIN/lib")
    data[0x300:0x300 + len(strings)] = strings
    dynamic = [(5, 0x90000 if malformed_dynamic else 0x10300), (10, len(strings))]
    dynamic += [(1, index) for index in indexes] + [(14, soname), (29, runpath), (0, 0)]
    entrysize = 16 if bits == 64 else 8
    program(1, 2, 0x200, entrysize * len(dynamic))
    for i, (tag, value) in enumerate(dynamic):
        struct.pack_into("<qQ" if bits == 64 else "<iI", data, 0x200 + entrysize * i, tag, value)
    if interp is not None:
        encoded = interp.encode() + b"\0"
        data[0x400:0x400 + len(encoded)] = encoded
        program(2, 3, 0x400, len(encoded))
    return bytes(data)


class ArtifactHelpersTest(unittest.TestCase):
    def test_filter_exact_reasons_and_kept_paths(self):
        for abi, cpu, foreign in (("arm64-v8a", "arm64", "x64"), ("x86_64", "x64", "arm64")):
            cases = {
                f"pkg/prebuilds/linux-{cpu}/addon.node": None,
                f"pkg/prebuilds/linux-{cpu}-glibc/addon.node": None,
                f"pkg/prebuilds/linux-{cpu}-musl/addon.node": "foreign-prebuild",
                f"pkg/prebuilds/linux-{foreign}/addon.node": "foreign-prebuild",
                f"pkg/prebuilds/darwin-{cpu}/addon.node": "foreign-prebuild",
                "pkg/prebuilds": None,
                "pkg/prebuilds/win32-x64/addon.dll": "foreign-prebuild",
                "pkg/TOOL.EXE": "foreign-binary", "pkg/a.dll": "foreign-binary",
                "pkg/a.pdb": "foreign-binary", "pkg/a.dylib": "foreign-binary",
                "node_modules/node-pty/third_party/conpty/license": "foreign-binary",
                "pkg/index.d.ts": "dev-metadata", "pkg/index.d.mts": "dev-metadata",
                "pkg/index.d.cts": "dev-metadata", "pkg/a.tsbuildinfo": "dev-metadata",
                "pkg/a.js.map": "dev-metadata", "pkg/a.mjs.map": "dev-metadata",
                "pkg/a.cjs.map": "dev-metadata", "pkg/a.ts.map": "dev-metadata",
                "pkg/a.css.map": "dev-metadata",
                "node_modules/typescript/lib/lib.d.ts": None,
                "typescript/lib/lib.d.mts": None, "pkg/index.ts": None,
                "pkg/LICENSE": None, "pkg/index.js": None, "pkg/source.map": None,
            }
            for rel, expected in cases.items():
                with self.subTest(abi=abi, rel=rel):
                    self.assertEqual(expected, artifacts.dsh_drop_reason(rel, abi, True))
                    self.assertEqual(None if expected == "dev-metadata" else expected,
                                     artifacts.dsh_drop_reason(rel, abi, False))

    def test_elf32_and_elf64_have_literal_summary_contract(self):
        for bits, machine, name, kind, label in ((64, 183, "aarch64", 3, "DYN"),
                                                (32, 3, "i386", 2, "EXEC"),
                                                (64, 62, "x86-64", 1, "REL"),
                                                (32, 40, "arm", 4, "CORE"),
                                                (64, 999, "999", 9, "9")):
            with self.subTest(bits=bits, machine=machine):
                self.assertEqual({"class": bits, "machine": name, "e_machine": machine,
                                  "type": label, "interp": "/lib/ld-linux-aarch64.so.1",
                                  "minLoadAlign": 16384, "needed": ["libc.so.6"],
                                  "soname": "fixture.so", "runpath": "$ORIGIN/lib", "musl": False},
                                 artifacts.elf_summary(elf_fixture(bits, machine, kind)))

    def test_musl_detection_and_static_header_fallback(self):
        for interp, needed in (("/lib/ld-musl-aarch64.so.1", ()), (None, ("libc.so",)),
                               (None, ("libmusl-fixture.so",))):
            with self.subTest(interp=interp, needed=needed):
                self.assertTrue(artifacts.elf_summary(elf_fixture(interp=interp, needed=needed))["musl"])
        info = artifacts.elf_summary(elf_fixture(interp=None, malformed_dynamic=True))
        self.assertEqual({"class": 64, "machine": "aarch64", "e_machine": 183,
                          "type": "DYN", "interp": None, "minLoadAlign": 16384, "musl": False}, info)
        static = bytearray(elf_fixture(interp=None))
        struct.pack_into("<H", static, 56, 0)  # e_phnum: no LOAD or DYNAMIC
        self.assertEqual({"class": 64, "machine": "aarch64", "e_machine": 183,
                          "type": "DYN", "interp": None, "minLoadAlign": None, "musl": False,
                          "needed": [], "soname": None, "runpath": None}, artifacts.elf_summary(static))

    def test_invalid_and_truncated_elf_still_raise(self):
        for data, error in ((b"not ELF", ValueError), (b"\x7fELF", IndexError),
                            (elf_fixture()[:30], struct.error)):
            with self.subTest(data=data[:8]), self.assertRaises(error):
                artifacts.elf_summary(data)
        big = bytearray(elf_fixture())
        big[5] = 2
        with self.assertRaisesRegex(ValueError, "big-endian"):
            artifacts.elf_summary(big)

    def test_full_elf_reader_inspects_independent_binary_fixture(self):
        for bits in (32, 64):
            data = elf_fixture(bits=bits)
            elf = artifacts.Elf(data)
            self.assertEqual((0x300, 34), elf.dynstr())
            self.assertEqual(0x300, elf.vaddr_to_offset(0x10300))
            with self.assertRaisesRegex(ValueError, "not in any LOAD"):
                elf.vaddr_to_offset(0x90000)


class OfficialArchiveIntegrationTest(unittest.TestCase):
    def test_real_cli_build_without_legacy_module_and_checks_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            # A minimal builder checkout deliberately has no rtbuild/patches/bridge.
            runtime = root / "checkout/runtime"
            (runtime / "lib").mkdir(parents=True)
            shutil.copyfile(RUNTIME / "build-official-runtime.py", runtime / "build-official-runtime.py")
            shutil.copyfile(RUNTIME / "lib/runtime_artifacts.py", runtime / "lib/runtime_artifacts.py")
            lock_dir = runtime / "locks/dsh-0.2.2-rc.3"
            lock_dir.mkdir(parents=True)
            lock = RUNTIME / "locks/dsh-0.2.2-rc.3/package-lock.json"
            shutil.copyfile(lock, lock_dir / "package-lock.json")
            prefix = root / "prefix"
            prefix.mkdir()
            shutil.copyfile(lock, prefix / "package-lock.json")
            files = {
                "node_modules/@deepseek-ai/dsh/package.json": b'{"name":"@deepseek-ai/dsh","version":"0.2.2-rc.3"}',
                "node_modules/@deepseek-ai/dsh/lib/bin.js": b'console.log("unmodified official CLI fixture");\n',
                "node_modules/@deepseek-ai/dsh/LICENSE": b"license fixture\n",
                "node_modules/.bin/dsh.cmd": b"host npm wrapper",
                "node_modules/pkg/index.d.ts": b"declare const fixture: string;",
                "node_modules/pkg/index.js.map": b"map fixture",
                "node_modules/typescript/lib/lib.d.ts": b"kept TypeScript declarations",
                "node_modules/pkg/tool.exe": b"foreign executable",
                "node_modules/pkg/prebuilds/linux-x64/addon.node": b"foreign prebuild",
                "node_modules/pkg/prebuilds/linux-arm64-musl/addon.node": b"musl prebuild",
                "node_modules/pkg/prebuilds/linux-arm64/addon.node": elf_fixture(),
                "node_modules/pkg/bin/tool": elf_fixture(kind=2),
                "node_modules/pkg/lib/helper.so": elf_fixture(),
                "node_modules/pkg/native-x64.node": elf_fixture(machine=62),
                "node_modules/pkg/native-musl.node": elf_fixture(interp=None, needed=("libc.so",)),
                "node_modules/pkg/setup.sh": b"#!/bin/sh\nexit 0\n",
            }
            for name, content in files.items():
                path = prefix / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            seed_dir = root / "seed/assets/runtime"
            seed_dir.mkdir(parents=True)
            system = {"etc/os-release": (b"ID=ubuntu\n", 0o644),
                      "opt/python/bin/python3": (b"immutable python", 0o755),
                      "opt/node/bin/node": (b"immutable node", 0o755),
                      "usr/local/lib/node_modules/pnpm/bin/pnpm.mjs": (b"immutable pnpm", 0o755),
                      "var/lib/dpkg/status": (b"immutable dpkg", 0o644),
                      "root/seed-marker": (b"immutable fixture, not a phone home", 0o600)}
            retired = {"opt/dsh/old.js": (b"old engine", 0o644),
                       "opt/dsh-go/bridge.js": (b"old bridge", 0o644),
                       "etc/dsh-app/old.patch.yml": (b"old patch", 0o644),
                       "usr/local/bin/dsh": (b"old shim", 0o755)}
            with tarfile.open(seed_dir / "seed.tar.gz", "w:gz") as tar:
                for name, (content, mode) in {**system, **retired}.items():
                    member = tarfile.TarInfo(name)
                    member.mode, member.size = mode, len(content)
                    tar.addfile(member, io.BytesIO(content))
                member = tarfile.TarInfo("usr/local/bin/python3")
                member.type, member.linkname = tarfile.SYMTYPE, "../../../opt/python/bin/python3"
                member.mode = 0o777
                tar.addfile(member)
            native = root / "seed/jniLibs/arm64-v8a/libproot.so"
            native.parent.mkdir(parents=True)
            native.write_bytes(b"native system fixture")
            digest = lambda data: hashlib.sha256(data).hexdigest()
            archive = seed_dir / "seed.tar.gz"
            current_paths = [
                "opt/dsh", "opt/node", "etc/dsh-app", "etc/profile.d/dsh-app.sh",
                "usr/local/lib/node_modules/pnpm", "usr/local/bin/dsh", "usr/local/bin/node",
                "usr/local/bin/npm", "usr/local/bin/npx", "usr/local/bin/corepack",
                "usr/local/bin/pnpm", "usr/local/bin/pnpx", "usr/local/bin/pn", "usr/local/bin/pnx",
            ]
            seed = {"abi": "arm64-v8a", "rootfs": archive.name, "rootfsBytes": archive.stat().st_size,
                    "rootfsSha256": digest(archive.read_bytes()), "nodeVersion": "24", "pnpmVersion": "11",
                    "ubuntuVersion": "24.04", "prootVersion": "5",
                    "upgrade": {"schema": 1, "baseId": "immutable-base-fixture",
                                "paths": list(current_paths) + ["opt/retired-seed-slot"]},
                    "launch": {"argv": ["proot", "exec /usr/local/bin/dsh web --patch /etc/dsh-app/dsh-web.patch.yml --no-open"]},
                    "jniLibs": {"libproot.so": {"bytes": native.stat().st_size, "sha256": digest(native.read_bytes())}},
                    "dshPatches": ["old"], "dshGoBridge": {"old": True},
                    "directEngine": {"old": True}, "pluginRegistries": {"old": True}}
            manifest_path = seed_dir / "manifest.json"
            manifest_path.write_text(json.dumps(seed), encoding="utf-8")
            seed_before = archive.read_bytes()
            hashes = []
            for iteration in range(2):
                output = root / ("out" + str(iteration))
                result = subprocess.run([sys.executable, "-I", str(runtime / "build-official-runtime.py"),
                                         "--seed-manifest", str(manifest_path), "--official-prefix", str(prefix),
                                         "--output", str(output), "--work", str(root / ("work" + str(iteration)))],
                                        capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                final = output / "assets/runtime/rootfs-arm64-v8a.tar.xz"
                manifest = json.loads((final.parent / "manifest.json").read_text())
                report = json.loads((output / "official-runtime-report.json").read_text())
                hashes.append(digest(final.read_bytes()))
                self.assertEqual(hashes[-1], manifest["rootfsSha256"])
                self.assertEqual(manifest["rootfsSha256"], report["rootfsSha256"])
                self.assertEqual(final.stat().st_size, manifest["rootfsBytes"])
                self.assertEqual(seed["upgrade"]["baseId"], manifest["upgrade"]["baseId"])
                self.assertEqual(current_paths, manifest["upgrade"]["paths"])
                self.assertNotIn("opt/retired-seed-slot", manifest["upgrade"]["paths"])
                self.assertEqual(seed["jniLibs"], manifest["jniLibs"])
                self.assertEqual(native.read_bytes(), (output / "jniLibs/arm64-v8a/libproot.so").read_bytes())
                self.assertEqual("official-unmodified", manifest["engineDistribution"])
                self.assertEqual({"legacyBridge": False, "enginePatches": False}, manifest["capabilities"])
                self.assertEqual(False, report["legacyRuntimeCodeIncluded"])
                self.assertEqual("exec /usr/local/bin/dsh web --no-open", manifest["launch"]["argv"][-1])
                for key in ("dshPatches", "dshGoBridge", "directEngine", "pluginRegistries"):
                    self.assertNotIn(key, manifest)
                dropped = {"dev-metadata": len(files["node_modules/pkg/index.d.ts"]) + len(files["node_modules/pkg/index.js.map"]),
                           "foreign-binary": len(files["node_modules/pkg/tool.exe"]),
                           "foreign-prebuild": len(files["node_modules/pkg/prebuilds/linux-x64/addon.node"]) + len(files["node_modules/pkg/prebuilds/linux-arm64-musl/addon.node"]),
                           "foreign-native": len(files["node_modules/pkg/native-x64.node"]) + len(files["node_modules/pkg/native-musl.node"])}
                self.assertEqual(dropped, report["droppedBytes"])
                removed = {"node_modules/.bin/dsh.cmd", "node_modules/pkg/index.d.ts", "node_modules/pkg/index.js.map",
                           "node_modules/pkg/tool.exe", "node_modules/pkg/prebuilds/linux-x64/addon.node",
                           "node_modules/pkg/prebuilds/linux-arm64-musl/addon.node", "node_modules/pkg/native-x64.node",
                           "node_modules/pkg/native-musl.node"}
                expected_files = set(system) | {"opt/dsh/" + name for name in files.keys() - removed}
                expected_files |= {"opt/dsh/package-lock.json", "etc/dsh-app/runtime.json", "usr/local/bin/dsh"}
                with tarfile.open(final, "r:xz") as tar:
                    members = tar.getmembers()
                    self.assertEqual(expected_files, {m.name for m in members if m.isreg()})
                    self.assertEqual({"usr/local/bin/python3"}, {m.name for m in members if m.issym()})
                    self.assertEqual("../../../opt/python/bin/python3", tar.getmember("usr/local/bin/python3").linkname)
                    self.assertFalse(any(m.name == "opt/dsh-go" or m.name.startswith("opt/dsh-go/") for m in members))
                    self.assertEqual([], [m.name for m in members if m.name in retired and m.name != "usr/local/bin/dsh"])
                    for name, (content, mode) in system.items():
                        self.assertEqual(content, tar.extractfile(name).read())
                        self.assertEqual(mode, tar.getmember(name).mode)
                    for name in files.keys() - removed:
                        self.assertEqual(files[name], tar.extractfile("opt/dsh/" + name).read())
                    for name, mode in (("node_modules/pkg/bin/tool", 0o755),
                                       ("node_modules/pkg/setup.sh", 0o755),
                                       ("node_modules/pkg/lib/helper.so", 0o644),
                                       ("node_modules/pkg/prebuilds/linux-arm64/addon.node", 0o644)):
                        self.assertEqual(mode, tar.getmember("opt/dsh/" + name).mode)
                    archived = json.load(tar.extractfile("etc/dsh-app/runtime.json"))
                    self.assertEqual(manifest["upgrade"], archived["upgrade"])
                    self.assertEqual("official-unmodified", archived["engineDistribution"])
                    shim = tar.extractfile("usr/local/bin/dsh").read()
                    self.assertEqual(b'#!/bin/sh\n# DeepSeek Assistant: invoke the unmodified official npm CLI.\nexec /opt/node/bin/node /opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"\n', shim)
                    self.assertTrue(all((m.uid, m.gid, m.mtime) == (0, 0, 1767225600) for m in members))
                    self.assertEqual(manifest["uncompressedBytes"], sum(m.size for m in members))
                    self.assertEqual(manifest["entries"], {"dir": sum(m.isdir() for m in members),
                                                          "file": sum(m.isreg() for m in members),
                                                          "symlink": sum(m.issym() for m in members)})
                    positions = {m.name: i for i, m in enumerate(members)}
                    for member in members:
                        parent = member.name.rpartition("/")[0]
                        if parent:
                            self.assertLess(positions[parent], positions[member.name])
                self.assertEqual({name: digest(content) for name, content in files.items()
                                  if name.startswith("node_modules/@deepseek-ai/dsh/")}, report["officialCliFileHashes"])
            self.assertEqual(hashes[0], hashes[1])
            self.assertEqual(seed_before, archive.read_bytes())
            self.assertFalse((runtime / "lib/rtbuild.py").exists())


if __name__ == "__main__":
    unittest.main()
