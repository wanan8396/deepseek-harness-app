import io
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

from verify_local_web_release import assert_retired_skill_assets_absent, main


class RetiredSkillAssetsTest(unittest.TestCase):
    def names(self, entries):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            for name in entries:
                archive.writestr(name, 'fixture')
        buffer.seek(0)
        with zipfile.ZipFile(buffer) as archive:
            return set(archive.namelist())

    def test_guide_and_unrelated_assets_remain_allowed(self):
        assert_retired_skill_assets_absent(self.names([
            'assets/flutter_assets/assets/skills/dsh-app-guide/manifest.json',
            'assets/flutter_assets/assets/skills/dsh-app-guide/SKILL.md',
            'assets/flutter_assets/assets/skills/companion-adapt/manifest.json',
            'assets/flutter_assets/assets/skills/dsh-app-ui-example/SKILL.md',
        ]))

    def test_every_retired_directory_is_rejected_including_nested_files(self):
        for skill in ('dsh-app-ui', 'dsh-app-plugin', 'dsh-app-support'):
            for suffix in ('', '/', '/SKILL.md', '/nested/extra.txt'):
                with self.subTest(skill=skill, suffix=suffix):
                    names = self.names([f'assets/flutter_assets/assets/skills/{skill}{suffix}'])
                    with self.assertRaisesRegex(AssertionError, f'Retired native skill assets returned: {skill}'):
                        assert_retired_skill_assets_absent(names)

    def test_repository_assets_and_registrations_are_absent(self):
        app = Path(__file__).resolve().parents[1] / 'app'
        pubspec = (app / 'pubspec.yaml').read_text(encoding='utf-8')
        for skill in ('dsh-app-ui', 'dsh-app-plugin', 'dsh-app-support'):
            with self.subTest(skill=skill):
                self.assertFalse((app / 'assets' / 'skills' / skill).exists())
                self.assertNotIn(f'assets/skills/{skill}/', pubspec)
        self.assertIn('assets/skills/dsh-app-guide/', pubspec)
        self.assertTrue((app / 'assets/skills/dsh-app-guide/manifest.json').is_file())

    def test_release_cli_actually_runs_retired_asset_gate(self):
        badging = ("package: name='app.dsh' versionName='fixture' versionCode='1'\n"
                   "application-label:'DeepSeek harness'\nnative-code: 'arm64-v8a'\n")
        def run(command, **kwargs):
            return SimpleNamespace(stdout=badging if 'badging' in command else '')
        with tempfile.TemporaryDirectory() as temp:
            apk = Path(temp) / 'fixture.apk'
            for skill in ('dsh-app-ui', 'dsh-app-plugin', 'dsh-app-support'):
                with self.subTest(skill=skill):
                    with zipfile.ZipFile(apk, 'w') as archive:
                        archive.writestr(f'assets/flutter_assets/assets/skills/{skill}/unexpected.txt', 'fixture')
                    with patch.dict(os.environ, {'ANDROID_HOME': temp}), \
                         patch.object(sys, 'argv', ['verify_local_web_release.py', str(apk)]), \
                         patch('verify_local_web_release.subprocess.run', side_effect=run):
                        with self.assertRaisesRegex(AssertionError, f'Retired native skill assets returned: {skill}'):
                            main()


if __name__ == '__main__':
    unittest.main()
