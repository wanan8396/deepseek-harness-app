#!/usr/bin/env python3
"""Pure temporary-fixture tests; no downloads, SDKs or external processes."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('prepare_ios_runtime', Path(__file__).with_name('prepare_ios_runtime.py'))
preparer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preparer)


def fixture_archive(path, prefix='package/', extra=()):
    libraries = []
    macho = (b'\xcf\xfa\xed\xfe' + (0x0100000C).to_bytes(4, 'little')
             + bytes(4) + (6).to_bytes(4, 'little'))
    with zipfile.ZipFile(path, 'w') as archive:
        for identifier in ('ios-arm64', 'ios-arm64-simulator'):
            library = {'LibraryIdentifier': identifier, 'LibraryPath': 'NodeMobile.framework',
                       'SupportedArchitectures': ['arm64'], 'SupportedPlatform': 'ios'}
            if identifier.endswith('-simulator'):
                library['SupportedPlatformVariant'] = 'simulator'
            libraries.append(library)
            base = prefix + 'NodeMobile.xcframework/' + identifier + '/NodeMobile.framework/'
            archive.writestr(base + 'Headers/NodeMobile.h', 'int node_start(int argc, char *argv[]);\n')
            archive.writestr(base + 'NodeMobile', macho)
        archive.writestr(prefix + 'NodeMobile.xcframework/Info.plist', plistlib.dumps({'AvailableLibraries': libraries}))
        for name, content in extra:
            archive.writestr(name, content)


class PrepareIOSRuntimeTests(unittest.TestCase):
    def test_requirements_match_checked_in_lock(self):
        requirements = preparer.load_requirements()
        self.assertEqual(requirements['engine']['node'], '>=24.9.0')
        self.assertEqual(requirements['nodeMobile']['flavor'], 'full')
        self.assertEqual(requirements['nodeMobile']['sha256'], preparer.PINNED_SHA256)

    def test_changed_engine_requirements_fail(self):
        requirements = copy.deepcopy(preparer.load_requirements())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime/ios').mkdir(parents=True)
            lockfile = root / requirements['engine']['lockfile']
            lockfile.parent.mkdir(parents=True)
            requirements['engine']['node'] = '>=18.0.0'
            (root / 'runtime/ios/requirements.json').write_text(json.dumps(requirements))
            lockfile.write_text(json.dumps({'packages': {'node_modules/@deepseek-ai/dsh': {
                'version': '0.2.2-rc.3', 'engines': {'node': '>=24.9.0'}}}}))
            with self.assertRaises(preparer.PreparationError):
                preparer.load_requirements(root)

    def test_archive_integrity_fails_before_extract(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'input.zip'
            archive.write_bytes(b'fixture')
            digest = hashlib.sha256(b'fixture').hexdigest()
            preparer.verify_archive(archive, digest, 7)
            with self.assertRaises(preparer.PreparationError):
                preparer.verify_archive(archive, '0' * 64, 7)
            with self.assertRaises(preparer.PreparationError):
                preparer.verify_archive(archive, digest, 8)

    def test_extract_discovers_single_real_root_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'input.zip'
            fixture_archive(archive, prefix='actual/nesting/')
            destination = Path(directory) / 'Vendor/NodeMobile.xcframework'
            slices = ['ios-arm64', 'ios-arm64-simulator']
            result = preparer.extract_framework(archive, destination, slices)
            self.assertEqual(result['linkage'], 'dynamic-framework')
            self.assertTrue((destination / 'Info.plist').is_file())
            self.assertFalse((destination / 'actual').exists())
            preparer.extract_framework(archive, destination, slices)
            (destination / 'Info.plist').write_text('stale')
            with self.assertRaises((preparer.PreparationError, ValueError, plistlib.InvalidFileException)):
                preparer.extract_framework(archive, destination, slices)

    def test_unsafe_paths_and_duplicate_root_fail_before_extract(self):
        unsafe = ['../escape', '/absolute', 'C:/drive', 'a\\windows', 'a/../escape', 'a//empty', './relative']
        for name in unsafe:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'input.zip'
                fixture_archive(archive, extra=[(name, 'bad')])
                with zipfile.ZipFile(archive) as opened:
                    with self.assertRaises(preparer.PreparationError):
                        preparer.archive_members(opened)
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'input.zip'
            fixture_archive(archive, extra=[('another/NodeMobile.xcframework/Info.plist', 'bad')])
            with zipfile.ZipFile(archive) as opened:
                with self.assertRaises(preparer.PreparationError):
                    preparer.archive_members(opened)

    def test_archive_symlinks_and_special_files_are_rejected(self):
        for kind in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFCHR):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'input.zip'
                fixture_archive(archive)
                with zipfile.ZipFile(archive, 'a') as opened:
                    info = zipfile.ZipInfo('package/NodeMobile.xcframework/bad')
                    info.create_system = 3
                    info.external_attr = (kind | 0o777) << 16
                    opened.writestr(info, '../../escape')
                with zipfile.ZipFile(archive) as opened:
                    with self.assertRaises(preparer.PreparationError):
                        preparer.archive_members(opened)

    def test_resources_copy_only_declared_probe_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'Resources'
            preparer.stage_resources(preparer.ROOT, destination)
            self.assertEqual(sorted(p.name for p in destination.iterdir()), sorted(preparer.RESOURCE_NAMES))
            for name in preparer.RESOURCE_NAMES:
                self.assertEqual((destination / name).read_bytes(), (preparer.ROOT / 'runtime/ios' / name).read_bytes())


if __name__ == '__main__':
    unittest.main()
