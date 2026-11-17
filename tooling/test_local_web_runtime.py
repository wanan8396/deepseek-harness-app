import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from check_local_web_runtime import ABIS, REQUIRED_LIBS, check_runtime


class RuntimePreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.abi = ABIS["arm64"]
        self.base = self.root / "runtime" / "out" / self.abi
        self.assets = self.base / "assets" / "runtime"
        self.assets.mkdir(parents=True)
        self.libs = self.base / "jniLibs" / self.abi
        self.libs.mkdir(parents=True)
        rootfs = b"synthetic-rootfs-fixture"
        (self.assets / "rootfs.tar.xz").write_bytes(rootfs)
        self.manifest = {
            "abi": self.abi, "runtimeVersion": "fixture-1", "dshVersion": "fixture-1",
            "rootfs": "rootfs.tar.xz", "rootfsBytes": len(rootfs),
            "rootfsSha256": hashlib.sha256(rootfs).hexdigest(), "jniLibs": {},
        }
        for name in REQUIRED_LIBS:
            value = name.encode()
            (self.libs / name).write_bytes(value)
            self.manifest["jniLibs"][name] = {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
        self.save()

    def save(self):
        (self.assets / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def test_matching_manifest_and_payloads(self):
        self.assertEqual(check_runtime(self.root, "arm64"), self.abi)

    def official_manifest(self):
        self.manifest.update({
            "engineDistribution": "official-unmodified",
            "capabilities": {"legacyBridge": False, "enginePatches": False},
            "launch": {"argv": ["proot", "/bin/sh", "-c", "exec /usr/local/bin/dsh web --no-open"]},
        })
        self.save()

    def test_official_distribution_passes_only_with_explicit_capabilities(self):
        self.official_manifest()
        self.assertEqual(check_runtime(self.root, "arm64", official=True), self.abi)

    def test_old_or_missing_distribution_is_rejected_for_lite(self):
        with self.assertRaisesRegex(ValueError, "official_runtime_required"):
            check_runtime(self.root, "arm64", official=True)

    def test_false_like_values_are_not_capability_declarations(self):
        self.official_manifest()
        for key in ("legacyBridge", "enginePatches"):
            for value in (True, "false", 0, None):
                with self.subTest(key=key, value=value):
                    self.manifest["capabilities"] = {"legacyBridge": False, "enginePatches": False, key: value}
                    self.save()
                    with self.assertRaisesRegex(ValueError, "official_runtime_required"):
                        check_runtime(self.root, "arm64", official=True)

    def test_legacy_patch_and_preload_are_rejected_in_official_launch(self):
        self.official_manifest()
        for extra in (" --patch /old.yml", " --import=/old.mjs"):
            with self.subTest(extra=extra):
                self.manifest["launch"]["argv"] = ["exec /usr/local/bin/dsh web" + extra]
                self.save()
                with self.assertRaisesRegex(ValueError, "legacy patch or preload"):
                    check_runtime(self.root, "arm64", official=True)

    def test_gzip_asset_is_rejected_before_android_silently_renames_it(self):
        archive = self.assets / "rootfs.tar.gz"
        (self.assets / "rootfs.tar.xz").rename(archive)
        self.manifest["rootfs"] = archive.name
        self.save()
        with self.assertRaisesRegex(ValueError, "renamed by Android packaging"):
            check_runtime(self.root, "arm64")

    def test_missing_manifest_explains_build_command(self):
        (self.assets / "manifest.json").unlink()
        with self.assertRaisesRegex(ValueError, "build-official-runtime.py"):
            check_runtime(self.root, "arm64")

    def test_wrong_abi_is_rejected(self):
        self.manifest["abi"] = "x86_64"
        self.save()
        with self.assertRaisesRegex(ValueError, "ABI/version"):
            check_runtime(self.root, "arm64")

    def test_corrupted_same_size_rootfs_is_rejected(self):
        path = self.assets / "rootfs.tar.xz"
        path.write_bytes(b"X" * path.stat().st_size)
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            check_runtime(self.root, "arm64")

    def test_missing_native_file_is_rejected(self):
        (self.libs / "libproot.so").unlink()
        with self.assertRaisesRegex(ValueError, "Missing runtime asset"):
            check_runtime(self.root, "arm64")

    def test_missing_native_manifest_entry_is_rejected(self):
        self.manifest["jniLibs"].pop("libproot-loader.so")
        self.save()
        with self.assertRaisesRegex(ValueError, "Missing required JNI library"):
            check_runtime(self.root, "arm64")

    def test_truncated_runtime_is_rejected(self):
        (self.assets / "rootfs.tar.xz").write_bytes(b"X")
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            check_runtime(self.root, "arm64")

    def test_path_escape_is_rejected(self):
        self.manifest["rootfs"] = "../outside.tar.xz"
        self.save()
        with self.assertRaisesRegex(ValueError, "Invalid runtime asset name"):
            check_runtime(self.root, "arm64")


if __name__ == "__main__":
    unittest.main()
