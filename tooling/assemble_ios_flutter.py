#!/usr/bin/env python3
"""Assemble a throwaway iOS Flutter checkout from the target tree and the
reviewed historical Android donor snapshot.

The target repository stays Android-first: this script writes only into a new
output directory, with the current theme, startup media and iOS native code
kept as-is and the historical chat, sessions drawer and approval UI restored
from the pinned donor source. Nothing here runs Flutter; CI does that.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

import stage_ios_flutter as stage

ROOT = Path(__file__).absolute().parent.parent
DONOR = Path('vendor', 'ios-flutter-donor')
TEMPLATES = Path('app', 'lib', 'ui', 'ios', 'donor')
TEST_TEMPLATES = Path('app', 'test', 'ios', 'donor')
REPORT = '.ios-flutter-stage.json'
# Kept from the target: product shell, palette, launch media, iOS bridge code.
PRESERVE = (
    'app/lib/main.dart',
    'app/lib/app.dart',
    'app/lib/ui/ios/',
    'app/lib/ui/shell/root_gate.dart',
    'app/lib/launch/launch_state.dart',
    'app/lib/ui/theme/',
    'app/lib/ui/web/startup_cover.dart',
    'app/lib/l10n/app_',
    'app/lib/l10n/parts/ios_local_',
    'app/lib/l10n/gen/',
)
COPY_PREFIXES = ('app/ios/', 'app/lib/', 'app/assets/', 'app/tool/', 'packages/dsh_client/',
                 'runtime/ios/', 'runtime/locks/', 'tooling/')
COPY_EXACT = frozenset({'LICENSE', 'ASSETS.md', 'THIRD_PARTY_NOTICES.md', 'app/l10n.yaml',
                        'app/analysis_options.yaml', 'app/pubspec.yaml', 'app/pubspec.lock',
                        'app/test/ios/ios_official_carrier_test.dart'})
DONOR_EXACT = frozenset({'app/l10n.yaml', 'app/tool/l10n_catalog.py', 'app/tool/l10n_merge.py',
                         'app/assets/licenses/unicode-15.0.txt', 'packages/dsh_client/pubspec.yaml',
                         'packages/dsh_remote/pubspec.yaml', 'packages/dsh_remote/LICENSE-ds-harness-remote'})
# These target settings pages are tied to the trimmed Android runtime contract;
# the staged donor supplies its own independent desktop launch references.
OMIT_TARGET = frozenset({'app/lib/ui/web/local_settings_document.dart',
                         'app/lib/ui/web/web_view_platform.dart'})
GENERATED_INPUTS = ('app/ios/EmbeddedNode/Vendor', 'app/ios/EmbeddedNode/Resources')
DONOR_DEPENDENCIES = frozenset({'gpt_markdown', 'val_latex_flutter', 're_highlight', 'dsh_remote',
                               'dartssh2', 'image_picker', 'file_picker', 'crypto', 'cryptography',
                               'timezone', 'yaml', 'xterm', 'http', 'html', 'pointycastle',
                               'flutter_webrtc', 'archive', 'image'})
# template -> staged path. Each one replaces a donor surface that would
# otherwise mount Android-only hosts or removed third-party artwork.
APPLY = (
    ('ios_flutter_entry.dart', 'app/lib/ui/ios/ios_flutter_entry.dart'),
    ('ios_dsh_client_adapter.dart', 'app/lib/ui/ios/ios_dsh_client_adapter.dart'),
    ('home_shell.dart', 'app/lib/ui/shell/home_shell.dart'),
    ('root_gate.dart', 'app/lib/ui/shell/root_gate.dart'),
    ('sessions_drawer.dart', 'app/lib/ui/shell/sessions_drawer.dart'),
    ('shims/ui/shell/brand_mark.dart', 'app/lib/ui/shell/brand_mark.dart'),
    ('shims/ui/chat/widgets/whale_tail.dart', 'app/lib/ui/chat/widgets/whale_tail.dart'),
    ('shims/ui/common/feature_tile.dart', 'app/lib/ui/common/feature_tile.dart'),
    ('shims/ui/settings/appearance/app_icon_picker.dart', 'app/lib/ui/settings/appearance/app_icon_picker.dart'),
    ('shims/ui/settings/appearance/launch_screen_section.dart', 'app/lib/ui/settings/appearance/launch_screen_section.dart'),
    ('shims/ui/launch/launch_preview_page.dart', 'app/lib/ui/launch/launch_preview_page.dart'),
)
TEST_APPLY = (
    ('ios_dsh_client_adapter_test.dart', 'app/test/ios/ios_dsh_client_adapter_test.dart'),
    ('ios_historical_host_test.dart', 'app/integration_test/ios_historical_host_test.dart'),
)


class AssemblyError(ValueError):
    pass


def run(args: list[str], cwd: Path) -> bytes:
    result = subprocess.run(args, cwd=str(cwd), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AssemblyError(f'{args[0]} failed: {result.stderr.decode("utf-8", "replace").strip()}')
    return result.stdout


def eligible(name: str) -> bool:
    return (name in COPY_EXACT or name.startswith(COPY_PREFIXES)) and name not in OMIT_TARGET


def tracked(root: Path, include_untracked: bool = False) -> list[tuple[str, str]]:
    raw = run(['git', 'ls-files', '--stage', '-z'], root)
    names = []
    for item in raw.rstrip(b'\0').split(b'\0') if raw else []:
        header, name = item.decode('utf-8').split('\t', 1)
        mode, _, index_stage = header.split()
        if not eligible(name):
            continue
        if index_stage != '0' or mode not in ('100644', '100755'):
            raise AssemblyError(f'expected an ordinary tracked target file: {name}')
        names.append((name, mode))
    if include_untracked:
        # Local overlay only: the new iOS sources are untracked in this clone.
        other = run(['git', 'ls-files', '--others', '--exclude-standard', '-z'], root)
        known = {name for name, _ in names}
        for item in other.rstrip(b'\0').split(b'\0') if other else []:
            name = item.decode('utf-8')
            if name in known or not eligible(name):
                continue
            names.append((name, '100644'))
    if not names:
        raise AssemblyError('the target tree has no stageable files')
    return names


def preserved(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in PRESERVE)


def copy_target(root: Path, output: Path, include_untracked: bool = False) -> list[str]:
    target_root = root
    copied = []
    for name, mode in tracked(root, include_untracked):
        source = root / name
        stage.check_node(source, directory=False)
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if os.name != 'nt':
            target.chmod(0o755 if mode == '100755' else 0o644)
        copied.append(name)
    # Downloaded build inputs are untracked, so name them explicitly.
    for extra in GENERATED_INPUTS:
        source = target_root / extra
        if not source.is_dir():
            continue
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise AssemblyError(f'refusing a symlinked build input: {path}')
            if not path.is_file():
                continue
            name = path.relative_to(target_root).as_posix()
            destination = output / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
            copied.append(name)
    return copied


def export_donor(root: Path, output: Path, plan: Path, source: Path) -> None:
    run([sys.executable, str(root / 'tooling' / 'stage_ios_flutter.py'), 'export',
         '--source-repo', str(source), '--plan', str(plan), '--target-root', str(output)], root)


def tracked_donor(root: Path, pinned: str) -> dict[str, bytes]:
    """Reuse the committed, independently pinned donor snapshot.

    CI checks out the repository without the donor Git object, so the tracked
    snapshot is verified against the reviewed manifest digest itself.
    """
    stage.reverify(root, pinned=pinned)
    return donor_files(root, pinned)


def donor_files(root: Path, pinned: str) -> dict[str, bytes]:
    base = root / DONOR
    raw = stage.read_regular(base / stage.MANIFEST, stage.MAX_MANIFEST)
    if stage.digest(raw) != pinned:
        raise AssemblyError('donor manifest changed before copying')
    entries, hashes = stage.load_manifest(raw)
    files = {}
    for entry in entries:
        data = stage.read_regular(base / entry.path, entry.size)
        if len(data) != entry.size or stage.digest(data) != hashes[entry.path]:
            raise AssemblyError(f'donor file changed before copying: {entry.path}')
        files[entry.path] = data
    return files


def overlay_donor(output: Path, files: dict[str, bytes]) -> list[str]:
    written = []
    for name, data in files.items():
        if name not in DONOR_EXACT and not name.startswith(('app/lib/', 'packages/dsh_client/lib/',
                                                             'packages/dsh_remote/lib/')):
            continue
        if preserved(name):
            continue
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if name.startswith('app/lib/l10n/parts/') and target.is_file():
            # Retain current text/metadata for shared keys, plus donor-only
            # keys, in the same per-area file rather than duplicating keys.
            restored = json.loads(data)
            restored.update(json.loads(target.read_bytes()))
            data = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
        target.write_bytes(data)
        written.append(name)
    return sorted(written)


def apply_templates(output: Path, root: Path, pairs, kind: str) -> list[str]:
    applied = []
    base = TEMPLATES if kind == 'source' else TEST_TEMPLATES
    for template, destination in pairs:
        source = root / base / f'{template}.template'
        if not source.is_file():
            raise AssemblyError(f'missing {kind} template: {template}')
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        applied.append(destination)
    return applied


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise AssemblyError(f'expected one staged patch site in {path.name}')
    path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')


def parse_dependencies(text: str) -> dict[str, str]:
    """Read the top-level `dependencies:` block as name -> raw block lines."""
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.rstrip() == 'dependencies:')
    except StopIteration as exc:
        raise AssemblyError('pubspec has no dependencies block') from exc
    found: dict[str, str] = {}
    current: list[str] | None = None
    name = ''
    for line in lines[start + 1:]:
        if line and not line.startswith(' '):
            break
        stripped = line.strip()
        if line.startswith('  ') and not line.startswith('    ') and stripped and not stripped.startswith('#'):
            if current is not None:
                found[name] = '\n'.join(current)
            name = stripped.split(':', 1)[0]
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        found[name] = '\n'.join(current)
    return found


def merge_pubspec(output: Path, donor_files: dict[str, bytes]) -> list[str]:
    """Keep the target asset/font declarations; add the donor's dependencies.

    The restored historical UI imports packages the current iPhone shell never
    needed. Assets stay target-owned: the donor's brand, pet and whale media are
    not redistributed, so their declarations must not come along.
    """
    pubspec = output / 'app' / 'pubspec.yaml'
    target = pubspec.read_text(encoding='utf-8')
    donor = donor_files.get('app/pubspec.yaml')
    if donor is None:
        return []
    donor_text = donor.decode('utf-8')
    have = parse_dependencies(target)
    donor_deps = parse_dependencies(donor_text)
    if not DONOR_DEPENDENCIES <= donor_deps.keys():
        raise AssemblyError('the donor dependency contract changed')
    missing = [name for name in donor_deps if name in DONOR_DEPENDENCIES and name not in have]
    marker = '\ndev_dependencies:\n'
    if target.count(marker) != 1 or '\n  integration_test:' in target:
        raise AssemblyError('the target test dependency contract changed')
    addition = ''.join(f'{donor_deps[name]}\n' for name in missing)
    staged_pubspec = target.replace(marker, '\n' + addition + marker + '  integration_test:\n    sdk: flutter\n', 1)
    if '    - assets/web/\n' not in staged_pubspec:
        raise AssemblyError('the target asset declaration changed')
    staged_pubspec = staged_pubspec.replace('    - assets/web/\n',
                                            '    - assets/web/\n    - assets/licenses/unicode-15.0.txt\n', 1)
    pubspec.write_text(staged_pubspec, encoding='utf-8', newline='\n')
    return missing


def generate_staged(output: Path) -> list[str]:
    """Run the repository's own generators on the staged copy only."""
    generated = []
    merger = output / 'app' / 'tool' / 'l10n_merge.py'
    if merger.is_file():
        run([sys.executable, str(merger), '--no-gen'], output)
        generated.append('app/lib/l10n')
    return generated


def patch_staged(output: Path) -> list[str]:
    patched = []
    main = output / 'app' / 'lib' / 'main.dart'
    replace_once(main, "import 'package:flutter_riverpod/flutter_riverpod.dart';\n", '')
    replace_once(main, "import 'app.dart';", "import 'ui/ios/ios_flutter_entry.dart';")
    replace_once(main, 'runApp(const ProviderScope(child: DshApp()));', 'runApp(const IosFlutterEntry());')
    patched.append('app/lib/main.dart:entry')
    sessions = output / 'app' / 'lib' / 'state' / 'sessions_state.dart'
    # The App-owned Host selects its private Workspace; a client-supplied cwd
    # would be rejected by the iOS route policy and is never trusted.
    replace_once(sessions, 'cwd: conn.isLocal ? localWorkspaceDir : conn.workingDirectory,',
                 'cwd: conn.isLocal ? null : conn.workingDirectory,')
    patched.append('app/lib/state/sessions_state.dart:cwd')
    return patched


def constrain_mobile_surfaces(output: Path) -> list[str]:
    """Narrow only iOS-staged donor behavior; leave the core widgets intact."""
    lib = output / 'app' / 'lib'
    policies = [
        ('app_variant.dart', 'const phoneControlCapability = !localWebLite;', 'const phoneControlCapability = false;'),
        ('app_variant.dart', 'const companionCapability = !localWebLite;', 'const companionCapability = false;'),
        ('ui/pets/pet_stage.dart', "import '../../pets/pet_mood.dart';",
         "import '../../app_variant.dart';\nimport '../../pets/pet_mood.dart';"),
        ('ui/pets/pet_stage.dart', '    // The overlay outside the app hears every state while the chat lives.',
         '    if (!companionCapability) return widget.child;\n    // The overlay outside the app hears every state while the chat lives.'),
        ('state/sessions_state.dart', "import '../runtime/runtime_state.dart';\n", ''),
        ('state/sessions_state.dart', "import 'settings_state.dart';\n", ''),
        ('state/sessions_state.dart', '    final safeMode = ref.read(localRuntimeProvider).status.inSafeMode;\n', ''),
        ('state/chat_state.dart', '    setAutoApprove(true);\n    await _autoAllow(request);',
         '    await respond(request, ApprovalDecision.allowOnce);'),
        ('state/chat_state.dart', '''    _autoApprove = enabled;
    state = state.copyWith(autoApprove: enabled);
    if (!enabled) return;
    for (final pending in _transcript.pendingApprovals.values) {
      unawaited(_autoAllow(pending));
    }''', '    _autoApprove = false;\n    state = state.copyWith(autoApprove: false);'),
        ('ui/chat/chat_list.dart', '  Future<void> _allowAll(ApprovalRequest request) =>\n'
         '      ref.read(chatProvider(widget.sessionId).notifier).allowAll(request);\n', ''),
        ('ui/chat/chat_list.dart', '      ApprovalRow(:final request) => ApprovalCard(request: request, onRespond: _respond, onAllowAll: _allowAll),'.lstrip(),
         'ApprovalRow(:final request) => ApprovalCard(request: request, onRespond: _respond),'),
        ('ui/chat/model_sheet.dart', '            if (picking) ...[const SizedBox(height: 12), const ManageModelsLink()],\n', ''),
        ('ui/session/session_detail_page.dart', "import '../../state/chat_state.dart';",
         "import '../../state/chat_state.dart';\nimport '../../state/connection_state.dart';"),
        ('ui/session/session_detail_page.dart', '  void _openTerminal() => Navigator.of(context).push(TerminalPage.route(widget.sessionId));',
         '  bool get _hasTerminal => ref.watch(activeConnectionProvider).value?.client.supportsTerminals == true;\n\n'
         '  void _openTerminal() => Navigator.of(context).push(TerminalPage.route(widget.sessionId));'),
        ('ui/session/session_detail_page.dart',
         'actions: [SheetIconButton(icon: AppIcons.terminal, tooltip: l10n.hubTerminal, onPressed: _openTerminal)],',
         'actions: [if (_hasTerminal) SheetIconButton(icon: AppIcons.terminal, tooltip: l10n.hubTerminal, onPressed: _openTerminal)],'),
        ('ui/chat/chat_screen.dart', '                                    onContentInserted: connected ? _pasteContent : null,',
         "                                     onContentInserted: conn?.client.supportsEndpoint('ios-app/image-input') == true\n"
         "                                         ? _pasteContent : null,"),
        ('ui/chat/chat_screen.dart', '                                    leading: AttachButton(onPressed: connected ? _attach : null),',
         '                                    leading: AttachButton(onPressed: connected &&\n'
         '                                         canStageFiles(conn, ref.watch(activeHostProvider)) ? _attach : null),'),
    ]
    for name, old, new in policies:
        replace_once(lib / name, old, new)
    sessions = lib / 'state/sessions_state.dart'
    replace_once(sessions, '''    if (autoApprove && conn.isLocal && !safeMode && ref.read(settingsProvider).autoApproveCommands) {
      try {
        await conn.client.setPermissionPreset(created.sessionId, 'danger-full-access');
      } catch (_) {
        // Keep the default preset if the command is unavailable.
      }
    }
''', '')
    path = lib / 'ui/chat/chat_list.dart'
    text = path.read_text(encoding='utf-8')
    if text.count('        onAllowAll: _allowAll,\n') != 2:
        raise AssemblyError('unexpected original approval card seams')
    path.write_text(text.replace('        onAllowAll: _allowAll,\n', ''), encoding='utf-8', newline='\n')
    return sorted(set(name for name, _, _ in policies))


def verify_imports(output: Path) -> None:
    root = output / 'app' / 'lib'
    broken = []
    pattern = re.compile(r'''^\s*(?:import|export|part)\s+['"]([^:'"]+\.dart)['"]''', re.M)
    for path in sorted(root.rglob('*.dart')):
        for uri in pattern.findall(path.read_text(encoding='utf-8')):
            if not (path.parent / uri).is_file():
                broken.append(f'{path.relative_to(root)} -> {uri}')
    if broken:
        raise AssemblyError('staged relative Dart imports missing:\n' + '\n'.join(broken[:20]))


def assemble(target: Path, output: Path, plan: Path | None, source: Path | None,
             pinned: str | None = None, *, untracked: bool = False) -> dict[str, object]:
    if output.exists() and any(output.iterdir()):
        raise AssemblyError('the output directory must be new or empty')
    output.mkdir(parents=True, exist_ok=True)
    copied = copy_target(target, output, untracked)
    if pinned is not None:
        files = tracked_donor(target, pinned)
        digest = pinned
    else:
        if plan is None or source is None:
            raise AssemblyError('staging needs a reviewed plan and donor source, or a pinned snapshot')
        export_donor(target, output, plan, source)
        digest = hashlib.sha256(plan.read_bytes()).hexdigest()
        files = tracked_donor(output, digest)
    restored = overlay_donor(output, files)
    applied = apply_templates(output, target, APPLY, 'source')
    tests = apply_templates(output, target, TEST_APPLY, 'test')
    dependencies = merge_pubspec(output, files)
    generated = generate_staged(output)
    patched = patch_staged(output)
    mobile_policy = constrain_mobile_surfaces(output)
    verify_imports(output)
    report = {
        'schema': 'ios-flutter-stage/v1',
        'donorManifestSha256': digest,
        'targetFilesCopied': len(copied),
        'donorFilesRestored': len(restored),
        'templatesApplied': applied,
        'testsStaged': tests,
        'dependenciesAdded': dependencies,
        'generated': generated,
        'patched': patched,
        'iosPolicyFiles': mobile_policy,
        'androidIncluded': False,
    }
    (output / REPORT).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-root', type=Path, default=ROOT)
    parser.add_argument('--source-repo', type=Path)
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--vendor-manifest-sha256', dest='pinned')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--include-untracked', action='store_true')
    args = parser.parse_args(argv)
    try:
        report = assemble(args.target_root.absolute(), args.output.absolute(),
                          args.plan.absolute() if args.plan else None,
                          args.source_repo.absolute() if args.source_repo else None, args.pinned,
                          untracked=args.include_untracked)
        print(json.dumps(report, indent=2))
    except (OSError, ValueError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
