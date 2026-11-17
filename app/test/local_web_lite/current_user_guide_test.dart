import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current guide ships matching bilingual official runtime pages, not legacy feature instructions', () {
    const base = 'assets/skills/dsh-app-guide/';
    final manifest = jsonDecode(File('${base}manifest.json').readAsStringSync()) as Map;
    expect(manifest['dshVersion'], '0.2.2-rc.3');
    expect(manifest['name'], 'deepseek-harness-guide');
    final skill = File('${base}SKILL.md').readAsStringSync();
    expect(skill, contains('name: deepseek-harness-guide'));
    expect(skill, contains('# deepseek-harness:managed'));
    expect(skill, isNot(matches(RegExp(r'ds[h]?-go|DSH Go', caseSensitive: false))));
    final files = (manifest['files'] as Map).cast<String, String>();
    for (final language in ['zh', 'en']) {
      final pages = files.entries.where((entry) => entry.value.startsWith('$language/')).toList();
      expect(pages, hasLength(12));
      final contents = pages.map((entry) => File('$base${entry.key}').readAsStringSync()).join('\n');
      expect(contents, contains('DeepSeek harness'));
      expect(contents, isNot(matches(RegExp(r'ds[h]?-go|DSH Go', caseSensitive: false))));
      expect(contents, contains('PRoot'));
      expect(contents, contains('Root'));
    }
  });

  test('local dependency guide fixes the private layout and four guest-only examples', () {
    const base = 'assets/skills/dsh-app-guide/';
    const layout = [
      '/root/.local/share/deepseek-harness/dependencies',
      'DSH_DEPENDENCY_ROOT',
      '`bin/`', '`npm/`', '`npm/bin`', '`python/`', '`venvs/`',
      '`downloads/`', '`sources/`', '`build/`', '`tmp/`', '`cache/`',
      '`cargo/`', '`rustup/`', '`go/`',
      'NPM_CONFIG_PREFIX', 'PYTHONUSERBASE', 'NPM_CONFIG_CACHE',
      'NPM_CONFIG_DEVDIR', 'PIP_CACHE_DIR', 'CARGO_HOME', 'RUSTUP_HOME',
      'GOPATH', 'GOMODCACHE', 'GOCACHE', 'CCACHE_DIR', 'TMPDIR',
      '`/usr`', '`dpkg/apt`', '`node_modules`', '`/opt/dsh`',
      '`Download/DeepSeek-harness`', 'noexec', 'PATH',
    ];
    const examples = [
      r'python3 -m venv "$DSH_DEPENDENCY_ROOT/venvs/my-tool"',
      r'PYTHONUSERBASE="$DSH_DEPENDENCY_ROOT/python" python3 -m pip install --user PACKAGE',
      r'NPM_CONFIG_PREFIX="$DSH_DEPENDENCY_ROOT/npm" npm install -g TOOL_PACKAGE',
      r'curl -L -o "$DSH_DEPENDENCY_ROOT/downloads/my-tool.tar.gz" "$SOURCE_URL"',
      r'cmake -S "$DSH_DEPENDENCY_ROOT/sources/my-tool" -B "$DSH_DEPENDENCY_ROOT/build/my-tool"',
    ];
    const boundaries = {
      'zh': [
        '正常与恢复 profile、Root 与 PRoot 共用同一持久私有目录',
        '电脑网页不使用手机的这些环境变量',
        '追加到 `PATH` 末尾', '旧位置已安装的工具不会自动搬迁',
        '不新增按钮', '当前 14 项引擎升级路径之外',
        '卸载、清除 App 数据或明确重置会影响这里的私有依赖',
      ],
      'en': [
        'Normal and recovery profiles, Root and PRoot share the same persistent private directory',
        'Computer webpages do not use these phone environment variables',
        'appended to the end of `PATH`', 'Previously installed tools are not moved automatically',
        'adds no buttons', 'outside the current 14 engine-upgrade paths',
        'Uninstalling, clearing app data or explicitly resetting affects these private dependencies',
      ],
    };
    for (final language in ['zh', 'en']) {
      final contents = File('$base$language-03-engine-hosts.md').readAsStringSync();
      for (final required in [...layout, ...examples, ...boundaries[language]!]) {
        expect(contents, contains(required), reason: '$language: $required');
      }
      expect(RegExp(r'```bash\n[\s\S]*?```').allMatches(contents), hasLength(4));
      expect(contents, isNot(matches(RegExp(r'\bPIP_(?:TARGET|PREFIX|USER)\s*='))));
      expect(contents, isNot(contains(r'D:\Tools')));
    }
  });
}
