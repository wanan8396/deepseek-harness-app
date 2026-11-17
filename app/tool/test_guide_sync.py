"""python3 -m unittest discover -s app/tool -p 'test_guide_sync.py'"""
import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

import guide_sync

REPO = Path(__file__).resolve().parents[2]

SKILL = """---
# deepseek-harness:managed — remove this line to take ownership of this guide.
name: deepseek-harness-guide
description: The guide.
whenToUse: How to use the app.
---

Read [README](README.md).
"""

PAGE = {
    'zh': '# 引擎\n\n<!-- nav: commonSettings,hubSettingsEngine -->\n`设置 › 引擎`\n\n点**启动**，或点**停止操作**。见 [设置](02-settings.md)。\n',
    'en': '# Engine\n\n<!-- nav: commonSettings,hubSettingsEngine -->\n`Settings › Engine`\n\nTap **Start**, or **Stop actions**. See [Settings](02-settings.md).\n',
}


class GuideSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.guide = self.repo / 'docs/guide'
        self.write('app/pubspec.yaml', 'name: app\nversion: 1.0.15+1\n')
        self.write('runtime/locks/dsh-0.2.2-rc.3/package.json',
                   json.dumps({'dependencies': {'@deepseek-ai/dsh': '0.2.2-rc.3'}}))
        self.write('app/lib/l10n/parts/hub_zh.arb', json.dumps(
            {'commonSettings': '设置', 'hubSettingsEngine': '引擎', 'phoneEngineStart': '启动', 'count': '{n} 个'}))
        self.write('app/lib/l10n/parts/hub_en.arb', json.dumps(
            {'commonSettings': 'Settings', 'hubSettingsEngine': 'Engine', 'phoneEngineStart': 'Start', 'count': '{n}'}))
        res = 'app/android/app/src/main/res'
        self.write(f'{res}/values-zh/s.xml', '<resources><string name="stop">停止操作</string></resources>')
        self.write(f'{res}/values/s.xml', '<resources><string name="stop">Stop actions</string></resources>')
        self.write('docs/guide/SKILL.md', SKILL)
        self.write('docs/guide/README.md', '# DeepSeek harness guide\n\n> DeepSeek harness 0.2.2-rc.3\n\n- [引擎](zh/01-engine.md)\n- [Engine](en/01-engine.md)\n')
        for locale, text in PAGE.items():
            self.write(f'docs/guide/{locale}/01-engine.md', text)
            self.write(f'docs/guide/{locale}/02-settings.md', '# Settings\n')

    def write(self, rel, text):
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def errors(self):
        return guide_sync.check(self.repo, self.guide)

    def assertFails(self, needle):
        errors = self.errors()
        self.assertTrue(any(needle in e for e in errors), f'{needle!r} not in {errors}')

    def test_valid_guide_builds_without_runtime_outputs_or_retired_routes(self):
        self.assertFalse((self.repo / 'runtime/out').exists())
        self.assertFalse((self.repo / 'app/lib/links').exists())
        self.assertFalse((self.repo / 'app/lib/ui/settings').exists())
        self.assertEqual(self.errors(), [])
        self.assertEqual(guide_sync.run(self.repo, write=True), [])
        self.assertEqual(guide_sync.run(self.repo, write=False), [])
        assets = self.repo / 'app/assets/skills/dsh-app-guide'
        manifest = json.loads((assets / 'manifest.json').read_text())
        self.assertEqual(manifest['name'], 'deepseek-harness-guide')
        self.assertEqual(manifest['dshVersion'], '0.2.2-rc.3')
        self.assertEqual(manifest['files']['zh-01-engine.md'], 'zh/01-engine.md')
        self.assertEqual(set(manifest['files']), {p.name for p in assets.iterdir()} - {'manifest.json'})
        for flat, target in manifest['files'].items():
            self.assertEqual((assets / flat).read_bytes(), (self.guide / target).read_bytes())

    def test_generated_assets_cannot_drift(self):
        guide_sync.run(self.repo, write=True)
        assets = self.repo / 'app/assets/skills/dsh-app-guide'
        (assets / 'zh-01-engine.md').write_text('edited by hand')
        self.assertTrue(any('out of date' in e for e in guide_sync.run(self.repo, write=False)))
        guide_sync.run(self.repo, write=True)
        (assets / 'stale.md').write_text('old page')
        self.assertTrue(any('stale.md' in e for e in guide_sync.run(self.repo, write=False)))
        guide_sync.run(self.repo, write=True)
        self.assertFalse((assets / 'stale.md').exists())

    def test_nav_label_must_match_the_arb(self):
        self.write('docs/guide/zh/01-engine.md', PAGE['zh'].replace('`设置 › 引擎`', '`设置 › 运行环境`'))
        self.assertFails('want `设置 › 引擎`')

    def test_nav_key_must_exist(self):
        self.write('docs/guide/en/01-engine.md', PAGE['en'].replace('hubSettingsEngine', 'hubSettingsGone'))
        self.assertFails('no en ARB key hubSettingsGone')

    def test_nav_uses_the_page_locale(self):
        self.write('docs/guide/en/01-engine.md', PAGE['en'].replace('`Settings › Engine`', '`设置 › 引擎`'))
        self.assertFails('want `Settings › Engine`')

    def test_placeholder_labels_are_not_paths(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n<!-- nav: count -->\n`{n} 个`\n')
        self.assertFails('not a plain label')

    def test_path_without_annotation_fails(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n在 `设置 › 引擎` 里。\n')
        self.assertFails('path without a nav annotation')

    def test_malformed_annotation_fails(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n<!-- nav: commonSettings, hubSettingsEngine -->\n`设置 › 引擎`\n')
        self.assertFails('malformed annotation')

    def test_bold_must_be_a_label_of_that_locale(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n点**开始**。\n')
        self.assertFails('**开始** is not a zh UI label')
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n点**Start**。\n')
        self.assertFails('**Start** is not a zh UI label')

    def test_relative_links_must_resolve_inside_the_guide(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n见 [帮助](missing.md)。\n')
        self.assertFails('broken link missing.md')
        self.write('docs/outside.md', '# Outside\n')
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n见 [帮助](../../outside.md)。\n')
        self.assertFails('broken link ../../outside.md')
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n见 [英文](../en/01-engine.md#engine)。\n')
        self.assertEqual(self.errors(), [])

    def test_readme_version_must_match_official_dependency(self):
        self.write('docs/guide/README.md', '> DeepSeek harness 0.2.2-rc.2\n')
        self.assertFails('`> DeepSeek harness 0.2.2-rc.3`')
        self.assertFails('runtime/locks/dsh-0.2.2-rc.3/package.json @deepseek-ai/dsh')

    def test_existing_runtime_manifest_must_match_official_dependency(self):
        self.write('runtime/out/arm64-v8a/assets/runtime/manifest.json',
                   json.dumps({'dshVersion': '0.2.2-rc.3', 'runtimeVersion': 'packaging-id'}))
        self.assertEqual(self.errors(), [])
        self.assertEqual(guide_sync.run(self.repo, write=True), [])
        self.write('runtime/out/arm64-v8a/assets/runtime/manifest.json',
                   json.dumps({'dshVersion': '0.2.2-rc.2'}))
        with self.assertRaisesRegex(ValueError, 'dshVersion must match .*0.2.2-rc.3'):
            self.errors()

    def test_official_dependency_must_be_an_exact_version(self):
        for value in (None, '', 2, '^0.2.2-rc.3', '~0.2.2', 'latest', '0.2.2 rc.3', '0.2.2-rc.3\n'):
            with self.subTest(value=value):
                self.write('runtime/locks/dsh-0.2.2-rc.3/package.json',
                           json.dumps({'dependencies': {'@deepseek-ai/dsh': value}}))
                with self.assertRaisesRegex(ValueError, 'must be an exact version'):
                    self.errors()
        for data in ({}, [], {'dependencies': []}, {'dependencies': {}}):
            with self.subTest(data=data):
                self.write('runtime/locks/dsh-0.2.2-rc.3/package.json', json.dumps(data))
                with self.assertRaisesRegex(ValueError, 'must be an exact version'):
                    self.errors()

    def test_runtime_manifest_does_not_replace_missing_official_lock(self):
        self.write('runtime/out/arm64-v8a/assets/runtime/manifest.json',
                   json.dumps({'dshVersion': '0.2.2-rc.3'}))
        (self.repo / 'runtime/locks/dsh-0.2.2-rc.3/package.json').unlink()
        with self.assertRaises(FileNotFoundError):
            self.errors()

    def test_pubspec_is_not_the_guide_version_source(self):
        self.write('app/pubspec.yaml', 'version: 9.9.9+123\n')
        self.assertEqual(self.errors(), [])
        (self.repo / 'app/pubspec.yaml').unlink()
        self.assertEqual(self.errors(), [])

    def test_duplicate_runtime_version_markers_fail(self):
        self.write('docs/guide/README.md', '> DeepSeek harness 0.2.2-rc.3\n' * 2)
        self.assertFails('want one line')

    def test_existing_runtime_manifest_requires_matching_dsh_version(self):
        for value in (None, '', 2, '0.2.2 rc.3', '0.2.2-rc.3\n'):
            with self.subTest(value=value):
                self.write('runtime/out/arm64-v8a/assets/runtime/manifest.json',
                           json.dumps({'dshVersion': value}))
                with self.assertRaisesRegex(ValueError, 'dshVersion must match'):
                    self.errors()
        for data in ([], {'runtimeVersion': '0.2.2-rc.3'}):
            with self.subTest(data=data):
                self.write('runtime/out/arm64-v8a/assets/runtime/manifest.json', json.dumps(data))
                with self.assertRaisesRegex(ValueError, 'dshVersion must match'):
                    self.errors()

    def test_both_languages_hold_the_same_pages(self):
        (self.guide / 'en/02-settings.md').unlink()
        self.assertFails('zh/en pages differ')

    def test_skill_front_matter(self):
        self.write('docs/guide/SKILL.md', SKILL.replace('# deepseek-harness:managed — remove this line to take ownership of this guide.\n', ''))
        self.assertFails('# deepseek-harness:managed')
        self.write('docs/guide/SKILL.md', SKILL.replace('name: deepseek-harness-guide', 'name: personal-guide'))
        self.assertFails('name must be deepseek-harness-guide')
        self.write('docs/guide/SKILL.md', SKILL.replace('whenToUse', 'when'))
        self.assertFails('needs whenToUse')
        self.write('docs/guide/SKILL.md', SKILL.replace('description: The guide.', 'description: The guide: where things are.'))
        self.assertFails('description must be a plain one-line value')

    def test_product_copy_words(self):
        self.write('docs/guide/zh/02-settings.md', '# 设置\n\n新会话。\n')
        self.assertFails('avoid 「会话」')

    def test_stray_files_fail(self):
        self.write('docs/guide/notes.txt', 'draft')
        self.assertFails('notes.txt: not part of the guide')


class RepositoryGuideTest(unittest.TestCase):
    def test_docs_guide_matches_the_app_and_its_assets(self):
        self.assertEqual(guide_sync.run(REPO, write=False), [])

    def test_checkout_inputs_check_without_runtime_outputs_or_retired_routes(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            for directory in ('docs/guide', 'app/lib/l10n/parts',
                              'app/android/app/src/main/res', 'app/assets/skills/dsh-app-guide'):
                shutil.copytree(REPO / directory, repo / directory)
            package = repo / 'runtime/locks/dsh-0.2.2-rc.3/package.json'
            package.parent.mkdir(parents=True)
            shutil.copyfile(REPO / 'runtime/locks/dsh-0.2.2-rc.3/package.json', package)
            self.assertFalse((repo / 'runtime/out').exists())
            self.assertFalse((repo / 'app/lib/links').exists())
            self.assertFalse((repo / 'app/lib/ui/settings').exists())
            self.assertEqual(guide_sync.run(repo, write=False), [])

    def test_native_reader_uses_current_topic_filenames(self):
        pages = {
            '01-chat.md', '02-models.md', '03-engine-hosts.md', '04-permissions.md',
            '05-web.md', '06-navigation.md', '07-sharing.md', '08-plugins.md',
            '09-appearance.md', '10-settings.md', '11-faq.md', '12-automation.md',
        }
        manifest = json.loads((REPO / 'app/assets/skills/dsh-app-guide/manifest.json')
                              .read_text(encoding='utf-8'))
        package = json.loads((REPO / 'runtime/locks/dsh-0.2.2-rc.3/package.json')
                             .read_text(encoding='utf-8'))
        self.assertEqual(manifest['dshVersion'], package['dependencies']['@deepseek-ai/dsh'])
        self.assertEqual(manifest['name'], 'deepseek-harness-guide')
        self.assertEqual(set(manifest['files'].values()),
                         {'README.md', 'SKILL.md'} |
                         {f'{locale}/{page}' for locale in ('zh', 'en') for page in pages})
        for locale in ('zh', 'en'):
            self.assertEqual({p.name for p in (REPO / 'docs/guide' / locale).glob('*.md')}, pages)
        for retired in ('04-phone-control.md', '06-pets.md', '12-bots.md'):
            for page in (REPO / 'docs/guide').rglob('*.md'):
                with self.subTest(retired=retired, page=page.relative_to(REPO)):
                    self.assertNotIn(retired, page.read_text(encoding='utf-8'))

    def test_visible_guide_has_no_old_brand_or_retired_action_links(self):
        for page in (REPO / 'docs/guide').rglob('*.md'):
            text = page.read_text(encoding='utf-8')
            with self.subTest(page=page.relative_to(REPO)):
                self.assertNotRegex(text, r'(?i)dsh[- ]go|dshgo://|1\.0\.15')
                self.assertNotRegex(text, r'(?i)\b(?:DSH Remote|WebRTC|TURN|Relay|dsh-go-ui)\b')
                self.assertNotIn('<!-- nav: commonSettings,hubSettingsPhoneControl', text)

    def test_both_languages_describe_current_lite_not_old_capabilities(self):
        guide = REPO / 'docs/guide'
        for locale, facts in {
            'zh': {
                '01-chat.md': ('三点', '归档', '文件夹与对话记录保留'),
                '02-models.md': ('官方网页设置', 'API Key', 'token', 'cookie'),
                '03-engine-hosts.md': ('Root', 'PRoot', 'HOME/profile', '普通升级不是重置'),
                '04-permissions.md': ('普通模式', '恢复模式', 'PRoot', '文件', '通知', '后台'),
                '05-web.md': ('HTTP/HTTPS', '预览', '确认', '最近连接'),
                '06-navigation.md': ('键盘', '侧栏', '鲸鱼'),
                '07-sharing.md': ('不会因接收分享就自动发送', '16 MiB'),
                '08-plugins.md': ('普通官方 Web 插件', '不依赖旧手机专用原生 SDK'),
                '09-appearance.md': ('官方网页', '40 帧循环 GIF'),
                '10-settings.md': ('本机', '连接电脑', '权限图标', '不是数据迁移'),
                '11-faq.md': ('重试', '后台', '浮层', '菜单'),
                '12-automation.md': ('官方网页的自动化任务', '时区', '已排队消息不会因此撤回'),
            },
            'en': {
                '01-chat.md': ('three-dot', 'archive', 'directory and conversation records remain'),
                '02-models.md': ('official web settings', 'API key', 'token', 'cookie'),
                '03-engine-hosts.md': ('Root', 'PRoot', 'HOME/profile', 'Ordinary upgrade is not reset'),
                '04-permissions.md': ('normal local-engine start', 'Recovery mode', 'PRoot', 'files', 'notifications', 'background'),
                '05-web.md': ('HTTP/HTTPS', 'preview', 'confirm', 'Recent connections'),
                '06-navigation.md': ('keyboard', 'sidebar', 'whale'),
                '07-sharing.md': ('does not automatically send', '16 MiB'),
                '08-plugins.md': ('ordinary official Web plugins', 'not the old phone-specific native SDK'),
                '09-appearance.md': ('official webpage', '40-frame looping GIF'),
                '10-settings.md': ('This phone', 'Connect computer', 'permission icon', 'not the location of existing data'),
                '11-faq.md': ('Retry', 'Background', 'overlay', 'menus'),
                '12-automation.md': ('official webpage', 'time zone', 'queued messages are not withdrawn'),
            },
        }.items():
            for name, needles in facts.items():
                text = (guide / locale / name).read_text(encoding='utf-8')
                with self.subTest(locale=locale, page=name):
                    for needle in needles:
                        self.assertIn(needle, text)

    def test_connection_instructions_do_not_advertise_removed_guide_entry(self):
        for locale, removed in [('zh', '- 使用说明：'), ('en', '- User guide reads')]:
            text = (REPO / 'docs/guide' / locale / '10-settings.md').read_text(encoding='utf-8')
            with self.subTest(locale=locale):
                self.assertNotIn(removed, text)

    def test_guide_does_not_embed_credential_examples_or_personal_hosts(self):
        for page in (REPO / 'docs/guide').rglob('*.md'):
            text = page.read_text(encoding='utf-8')
            with self.subTest(page=page.relative_to(REPO)):
                self.assertNotRegex(text, r'https?://[^\s)]+')
                self.assertNotRegex(text, r'(?i)(?:sk-[A-Za-z0-9]{16,}|Bearer\s+\S+|[?&]token=\S+)')


if __name__ == '__main__':
    unittest.main()
