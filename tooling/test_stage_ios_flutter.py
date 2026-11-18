"""Tests for the donor staging contract; uses synthetic Git data, never the target."""

from __future__ import annotations

from dataclasses import replace
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import stage_ios_flutter as stage


EXTRA_SOURCE = 'app/lib/ui/chat/message.dart'
TEST_SOURCE = 'app/test/chat/message_test.dart'
L10N_INPUT = 'app/lib/l10n/parts/chat_en.arb'
EXCLUDED = {
    'app/assets/branding/startup-cover.gif',
    'app/assets/fonts/DshIcons.ttf',
    'app/assets/brand/tile.svg',
    'app/assets/tiles/glassy/community.webp',
    'app/assets/web/dsh_web_appearance.js',
    'app/lib/ui/theme/app_theme.dart',
    'app/lib/ui/ios/bridge.dart',
    'app/lib/ui/shell/brand_glyph.g.dart',
    'app/lib/ui/shell/brand_mark.dart',
    'app/lib/ui/common/feature_tile_shapes.g.dart',
    'app/lib/ui/chat/widgets/whale_tail.dart',
    'app/lib/ui/web/startup_cover.dart',
    'app/lib/l10n/app_en.arb',
    'app/lib/l10n/gen/app_localizations.dart',
    'app/android/app/src/main/AndroidManifest.xml',
    'app/ios/Runner/AppDelegate.swift',
    'app/test/chat/goldens/preview.png',
    'app/test/chat/fixtures/maybe_private.dart',
    'packages/dsh_remote/test/fixtures/credential.json',
    'runtime/install.sh',
    'site/home/dist/index.html',
    'docs/assets/screenshot.png',
}


def fixture() -> tuple[list[stage.Entry], dict[str, bytes]]:
    paths = stage.LICENSES | stage.METADATA | stage.L10N | stage.SOURCE | {
        EXTRA_SOURCE, TEST_SOURCE, L10N_INPUT,
    }
    data = {path: f'fixture for {path}\r\n'.encode('ascii') for path in sorted(paths)}
    entries = [stage.Entry(path, stage.classify(path), '100644', stage.blob_oid(blob), len(blob))
               for path, blob in data.items()]
    return entries, data


def encode(entries, data):
    return stage.manifest_bytes(entries, {name: stage.digest(blob) for name, blob in data.items()})


def row(entry, *, kind='blob'):
    return (f'{entry.mode} {kind} {entry.blob} {entry.size:>7}\t{entry.path}\0').encode('utf-8')


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.entries, self.data = fixture()
        self.raw = encode(self.entries, self.data)

    def test_policy(self):
        self.assertEqual(stage.classify(EXTRA_SOURCE), 'source')
        self.assertEqual(stage.classify(TEST_SOURCE), 'test-source')
        self.assertEqual(stage.classify(L10N_INPUT), 'l10n-input')
        self.assertEqual(stage.classify('app/assets/fonts/OFL.txt'), 'license')
        for path in sorted(EXCLUDED):
            with self.subTest(path=path):
                self.assertIsNone(stage.classify(path))

    def test_inventory_order_and_record_validation(self):
        excluded = replace(self.entries[0], path='app/lib/ui/theme/theme.dart', mode='120000')
        raw = row(excluded) + b''.join(row(entry) for entry in reversed(self.entries))
        self.assertEqual(stage.parse_inventory(raw), self.entries)
        with self.assertRaises(stage.StageError):
            stage.parse_inventory(raw[:-1])
        for mode, kind in (('120000', 'blob'), ('100755', 'blob'), ('160000', 'commit')):
            with self.subTest(mode=mode), self.assertRaises(stage.StageError):
                stage.parse_inventory(b''.join(row(entry) for entry in self.entries[:-1])
                                      + row(replace(self.entries[-1], mode=mode), kind=kind))

    def test_nonportable_paths(self):
        for name in ('../x.dart', '/x.dart', 'C:/x.dart', 'a\\x.dart',
                     'a/x.dart:stream', 'a/./x.dart', 'a//x.dart', 'a/.git/config',
                     'a/con.dart', 'a/f./x.dart', 'a/COM1.dart', 'a/ß.dart',
                     f'a/{"x" * 256}.dart', 'a/dir /x.dart', 'a/b\nx.dart'):
            with self.subTest(name=name), self.assertRaises(stage.StageError):
                stage.validate_path(name)

    def test_rejects_aliases_collisions_and_size_limits(self):
        original = next(item for item in self.entries if item.path == EXTRA_SOURCE)
        for bad in (original, replace(original, path='app/lib/ui/chat/Message.dart'),
                    replace(original, path=EXTRA_SOURCE + '/nested.dart'),
                    replace(original, path='app/lib/ui/chat/large.dart', size=stage.MAX_FILE + 1),
                    replace(original, path='app/lib/ui/chat/another.dart', size=True),
                    replace(original, path='app/lib/ui/chat/other.dart', role='license')):
            with self.subTest(bad=bad), self.assertRaises(stage.StageError):
                stage.validate_entries(sorted([*self.entries, bad], key=lambda item: item.path))

    def test_canonical_manifest_and_tampering(self):
        adopted, hashes = stage.load_manifest(self.raw)
        self.assertEqual(adopted, self.entries)
        self.assertEqual(hashes[EXTRA_SOURCE], stage.digest(self.data[EXTRA_SOURCE]))
        self.assertEqual(encode(adopted, self.data), self.raw)
        for bad in (self.raw.replace(b'\n', b'\r\n'),
                    self.raw.replace(b'{\n', b'{"commit":"fake",\n', 1),
                    self.raw.replace(stage.COMMIT.encode(), b'0' * 40),
                    self.raw.replace(stage.TREE.encode(), b'0' * 40),
                    self.raw.replace(b'  "schema":', b'  "extra":1,\n  "schema":')):
            with self.subTest(bad=bad[:50]), self.assertRaises(stage.StageError):
                stage.load_manifest(bad)
        bad = json.loads(self.raw)
        bad['files'][0]['path'] = '../outside'
        with self.assertRaises(stage.StageError):
            stage.load_manifest(json.dumps(bad).encode())


class StageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.target = Path(temporary.name).resolve()
        self.repo = self.target / 'mock-donor'
        self.dest = self.target / stage.DEST
        self.entries, self.data = fixture()
        self.raw = encode(self.entries, self.data)
        self.sha = stage.digest(self.raw)
        mocked = patch.object(stage, 'plan', return_value=(self.raw, self.data))
        self.addCleanup(mocked.stop)
        mocked.start()

    def test_export_preserves_target_theme_gif_and_every_donor_byte(self):
        protected = {
            'app/assets/branding/startup-cover.gif': b'GIF89a\x00target',
            'app/assets/fonts/DshIcons.ttf': b'target font',
            'app/lib/ui/theme/app_theme.dart': b'target theme',
            'app/ios/Runner/Info.plist': b'target ios',
        }
        for name, data in protected.items():
            path = self.target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.assertEqual(stage.export(self.repo, self.target, self.raw), self.dest)
        for name, data in protected.items():
            self.assertEqual((self.target / name).read_bytes(), data)
            self.assertFalse((self.dest / name).exists())
        self.assertEqual((self.dest / EXTRA_SOURCE).read_bytes(), self.data[EXTRA_SOURCE])
        self.assertEqual((self.dest / stage.MANIFEST).read_bytes(), self.raw)
        self.assertEqual((self.dest / stage.ATTRIBUTES).read_bytes(), stage.ATTRIBUTE_BYTES)
        self.assertEqual(stage.reverify(self.target, repo=self.repo), len(self.entries))
        self.assertEqual(stage.reverify(self.target, pinned=self.sha), len(self.entries))
        with self.assertRaises(FileExistsError):
            stage.export(self.repo, self.target, self.raw)

    def test_fake_but_canonical_plan_never_writes(self):
        fake = self.raw.replace(stage.digest(self.data[EXTRA_SOURCE]).encode(), b'0' * 64)
        stage.load_manifest(fake)
        with self.assertRaisesRegex(stage.StageError, 'does not match'):
            stage.export(self.repo, self.target, fake)
        self.assertFalse((self.target / 'vendor').exists())

    def test_reverify_rejects_mutation_missing_extras_and_untrusted_pin(self):
        stage.export(self.repo, self.target, self.raw)
        victim = self.dest / EXTRA_SOURCE
        original = victim.read_bytes()
        victim.write_bytes(b'q' + original[1:])
        with self.assertRaisesRegex(stage.StageError, 'differs'):
            stage.reverify(self.target, pinned=self.sha)
        victim.unlink()
        with self.assertRaisesRegex(stage.StageError, 'missing'):
            stage.reverify(self.target, pinned=self.sha)
        victim.write_bytes(original)
        extra = self.dest / 'extra-directory'
        extra.mkdir()
        with self.assertRaisesRegex(stage.StageError, 'unexpected'):
            stage.reverify(self.target, pinned=self.sha)
        extra.rmdir()
        with self.assertRaisesRegex(stage.StageError, 'independent pin'):
            stage.reverify(self.target, pinned='0' * 64)
        (self.dest / stage.MANIFEST).write_bytes(self.raw + b' ')
        with self.assertRaisesRegex(stage.StageError, 'independent pin'):
            stage.reverify(self.target, pinned=self.sha)

    def test_export_rejects_linked_parent(self):
        outside = self.target / 'outside'
        outside.mkdir()
        try:
            (self.target / 'vendor').symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(str(exc))
        with self.assertRaises(stage.StageError):
            stage.export(self.repo, self.target, self.raw)
        self.assertEqual(list(outside.iterdir()), [])

    def test_reverify_rejects_links_even_if_hash_matches(self):
        stage.export(self.repo, self.target, self.raw)
        victim = self.dest / EXTRA_SOURCE
        outside = self.target / 'outside.dart'
        outside.write_bytes(victim.read_bytes())
        victim.unlink()
        try:
            os.link(outside, victim)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(str(exc))
        with self.assertRaises(stage.StageError):
            stage.reverify(self.target, pinned=self.sha)


@unittest.skipUnless(shutil.which('git'), 'requires a local Git executable')
class LocalGitTests(unittest.TestCase):
    def test_pinned_blobs_are_independent_of_dirty_worktree(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp).resolve()

            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args],
                                               env=stage.git_environment(), stderr=subprocess.PIPE)

            git('init', '-q')
            git('config', 'core.autocrlf', 'false')
            _, data = fixture()
            # Control test filters irrespective of host/user Git config.
            (repo / '.gitattributes').write_bytes(stage.ATTRIBUTE_BYTES)
            for path, blob in data.items():
                full = repo / path
                full.parent.mkdir(parents=True, exist_ok=True)
                full.write_bytes(blob)
            git('add', '-f', '.')
            tree = git('write-tree').strip().decode('ascii')
            commit = git('-c', 'user.name=Donor Test', '-c', 'user.email=test@example.invalid',
                         '-c', 'commit.gpgsign=false', 'commit-tree', tree, '-m', 'fixture').strip().decode('ascii')
            with patch.object(stage, 'COMMIT', commit), patch.object(stage, 'TREE', tree):
                initial, contents = stage.plan(repo)
                (repo / EXTRA_SOURCE).write_bytes(b'dirty')
                (repo / 'app/lib/ui/chat/untracked.dart').write_bytes(b'untracked')
                repeated, after = stage.plan(repo)
                self.assertEqual(contents, data)
                self.assertEqual(after, data)
                self.assertEqual(initial, repeated)
                self.assertEqual(stage.load_manifest(initial)[0], fixture()[0])


if __name__ == '__main__':
    unittest.main()
