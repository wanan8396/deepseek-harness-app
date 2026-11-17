#!/usr/bin/env python3
"""Offline exporter fixture checks; no npm, Node, download or SDK execution."""
import copy
import importlib.util
import json
from pathlib import Path, PurePosixPath
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('prepare_ios_loader', Path(__file__).with_name('prepare_ios_loader.py'))
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


def add_package(seed, lock, name, relative=None, dependencies=None, peer_dependencies=None, version='1.0.0'):
    relative = relative or 'node_modules/' + name
    package = {'name': name, 'version': version, 'type': 'module', 'main': './index.js', 'license': 'MIT'}
    if dependencies:
        package['dependencies'] = dependencies
    if peer_dependencies:
        package['peerDependencies'] = peer_dependencies
    directory = seed / relative
    directory.mkdir(parents=True)
    (directory / 'package.json').write_text(json.dumps(package), encoding='utf-8')
    (directory / 'index.js').write_text('export {};\n', encoding='utf-8')
    (directory / 'LICENSE').write_text('MIT fixture license\n', encoding='utf-8')
    locked = {'version': version, 'resolved': f'https://registry.npmjs.org/{name}/-/fixture-{version}.tgz',
              'integrity': 'sha512-Zml4dHVyZQ=='}
    for key in ('dependencies', 'peerDependencies'):
        if key in package:
            locked[key] = copy.deepcopy(package[key])
    lock['packages'][relative] = locked
    return directory


class PrepareIOSLoaderTests(unittest.TestCase):
    def test_dependency_resolution_prefers_nested_package_then_hoisted_peer(self):
        with tempfile.TemporaryDirectory() as temporary:
            seed = Path(temporary)
            lock = {'packages': {}}
            add_package(seed, lock, 'fixture-root', dependencies={'fixture-dep': '*'}, peer_dependencies={'fixture-peer': '*'})
            add_package(seed, lock, 'fixture-dep', version='1.0.0')
            nested = 'node_modules/fixture-root/node_modules/fixture-dep'
            add_package(seed, lock, 'fixture-dep', relative=nested, version='2.0.0')
            add_package(seed, lock, 'fixture-peer')
            with patch.object(exporter, 'ENTRY_PACKAGE', 'fixture-root'), patch.object(exporter, 'REVIEWED_PACKAGES',
                    frozenset({'fixture-root', 'fixture-dep', 'fixture-peer'})):
                selected, omitted = exporter.dependency_closure(seed, lock)
            self.assertEqual(set(selected), {'node_modules/fixture-root', nested, 'node_modules/fixture-peer'})
            self.assertEqual(omitted, [])

    def test_unreviewed_dependency_and_changed_installed_contract_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            seed = Path(temporary)
            lock = {'packages': {}}
            root = add_package(seed, lock, 'fixture-root', dependencies={'new-native-package': '*'})
            with patch.object(exporter, 'ENTRY_PACKAGE', 'fixture-root'), patch.object(exporter, 'REVIEWED_PACKAGES',
                    frozenset({'fixture-root'})):
                with self.assertRaisesRegex(exporter.ExportError, 'UNREVIEWED_DEPENDENCY_EXPANSION'):
                    exporter.dependency_closure(seed, lock)
            manifest = json.loads((root / 'package.json').read_text())
            manifest['version'] = '9.0.0'
            (root / 'package.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(exporter.ExportError, 'INSTALLED_PACKAGE_LOCK_MISMATCH'):
                exporter.locked_package(seed, lock, None, 'fixture-root')

    def test_require_builtin_exclusion_is_recorded_not_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            seed = Path(temporary)
            lock = {'packages': {}}
            add_package(seed, lock, 'fixture-root', dependencies={'node-addon-require-builtin': '^0.1.9'})
            with patch.object(exporter, 'ENTRY_PACKAGE', 'fixture-root'), patch.object(exporter, 'REVIEWED_PACKAGES',
                    frozenset({'fixture-root'})):
                selected, omitted = exporter.dependency_closure(seed, lock)
            self.assertEqual(set(selected), {'node_modules/fixture-root'})
            self.assertEqual(omitted[0]['package'], 'node-addon-require-builtin')
            self.assertIn('No replacement shim', omitted[0]['reason'])
            self.assertFalse((seed / 'node_modules/node-addon-require-builtin').exists())

    def test_native_magic_is_rejected_even_in_an_omitted_extension(self):
        for data in (b'\x7fELFjunk', b'MZjunk', b'\xcf\xfa\xed\xfejunk', b'!<arch>junk'):
            with self.subTest(data=data), tempfile.TemporaryDirectory() as temporary:
                seed = Path(temporary)
                lock = {'packages': {}}
                directory = add_package(seed, lock, 'fixture-root')
                (directory / 'hidden.dat').write_bytes(data)
                selected = {'node_modules/fixture-root': (lock['packages']['node_modules/fixture-root'],
                            json.loads((directory / 'package.json').read_text()))}
                with self.assertRaisesRegex(exporter.ExportError, 'NATIVE_PACKAGE_CONTENT_UNSUPPORTED'):
                    exporter.collect_files(seed, selected)

    def test_runtime_exports_preserved_and_development_exports_not_rewritten(self):
        manifest = {'main': './lib/index.js', 'exports': {'.': {'types': './types/index.d.ts',
                    'import': './lib/index.mjs', 'require': './lib/index.cjs'}, './src/*': './src/*',
                    './package.json': './package.json'}}
        files = {'lib/index.js', 'lib/index.mjs', 'lib/index.cjs', 'package.json'}
        exporter.validate_entry_targets(manifest, files)
        with self.assertRaisesRegex(exporter.ExportError, 'RUNTIME_ENTRY_TARGET_MISSING'):
            exporter.validate_entry_targets(manifest, files - {'lib/index.cjs'})
        with self.assertRaisesRegex(exporter.ExportError, 'PACKAGE_ENTRY_TARGET_INVALID'):
            exporter.validate_entry_targets({'main': '../escape.js'}, files)

    def test_file_manifest_tracks_bytes_licenses_and_omissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            seed = Path(temporary)
            lock = {'packages': {}}
            directory = add_package(seed, lock, 'fixture-root')
            (directory / 'index.js.map').write_text('{}')
            selected = {'node_modules/fixture-root': (lock['packages']['node_modules/fixture-root'],
                        json.loads((directory / 'package.json').read_text()))}
            files, omitted = exporter.collect_files(seed, selected)
            self.assertIn('node_modules/fixture-root/LICENSE', [entry[1] for entry in files])
            self.assertEqual(omitted[0]['path'], 'node_modules/fixture-root/index.js.map')
            for source, _relative, digest, size in files:
                self.assertEqual(exporter.sha256(source.read_bytes()), digest)
                self.assertEqual(source.stat().st_size, size)

    def test_export_uses_exact_seed_lock_and_refuses_existing_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            seed = directory / 'seed'
            seed.mkdir()
            lock = {'packages': {}}
            add_package(seed, lock, '@deepseek-ai/dsh-app-boot', version='0.2.2-rc.3')
            lock_bytes = json.dumps(lock).encode()
            (seed / 'package-lock.json').write_bytes(lock_bytes)
            lock_path = directory / 'lock.json'
            lock_path.write_bytes(lock_bytes)
            output = directory / 'output'
            with patch.object(exporter, 'LOCK', lock_path):
                manifest = exporter.prepare(seed, output)
                self.assertEqual(manifest['distribution'], 'ios-adapted-loader-probe')
                self.assertFalse(manifest['engineReady'])
                self.assertEqual(manifest['sourceLockSHA256'], exporter.sha256(lock_bytes))
                self.assertTrue((output / 'loader-fixture.mjs').is_file())
                self.assertTrue((output / 'distribution-manifest.json').is_file())
                with self.assertRaisesRegex(exporter.ExportError, 'DESTINATION_ALREADY_EXISTS'):
                    exporter.prepare(seed, output)
                (seed / 'package-lock.json').write_text('{}')
                with self.assertRaisesRegex(exporter.ExportError, 'SEED_LOCK_BYTES_MISMATCH'):
                    exporter.prepare(seed, directory / 'other')


if __name__ == '__main__':
    unittest.main()
