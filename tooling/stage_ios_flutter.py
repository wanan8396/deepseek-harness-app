#!/usr/bin/env python3
"""Stage an immutable source-only iOS donor snapshot from local Git blobs."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


COMMIT = 'aa3578557b1500ecf4ec62f9ad86223e6e3f1bf5'
TREE = 'ba6c61585eb728e18a34b7fe35077ff63f4de324'
DEST = Path('vendor', 'ios-flutter-donor')
TARGET_ROOT = Path(__file__).absolute().parent.parent
MANIFEST = 'manifest.json'
ATTRIBUTES = '.gitattributes'
# Preserve exact Git bytes, including any CRLF in the donor, across checkouts.
ATTRIBUTE_BYTES = b'* -text -filter -ident -working-tree-encoding\n'
SCHEMA = 'ios-flutter-donor/v1'
MAX_FILE = 2 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
MAX_MANIFEST = 2 * 1024 * 1024
SHA1 = re.compile(r'[0-9a-f]{40}')
SHA256 = re.compile(r'[0-9a-f]{64}')
SAFE_PART = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_.-]*')
DEVICE = re.compile(r'(?:aux|con|nul|prn|com[0-9]|lpt[0-9])', re.I)
COLLISION_FILES = (MANIFEST, ATTRIBUTES)

# Exact names and narrowly typed source families; do not widen these to the
# repository generally. The commit and tree pins make the set immutable.
LICENSES = frozenset({
    'LICENSE', 'ASSETS.md', 'THIRD_PARTY_NOTICES.md',
    'docs/ATTRIBUTION.md', 'docs/ATTRIBUTION.en.md',
    'packages/dsh_remote/LICENSE-ds-harness-remote',
    'app/tool/icons/phosphor/LICENSE', 'app/tool/unicode-15.0-LICENSE.txt',
    'app/assets/fonts/OFL.txt', 'app/assets/licenses/unicode-15.0.txt',
})
METADATA = frozenset({
    'app/analysis_options.yaml', 'app/pubspec.yaml', 'app/pubspec.lock',
    *(f'packages/{package}/{name}'
      for package in ('dsh_client', 'dsh_remote')
      for name in ('analysis_options.yaml', 'dart_test.yaml', 'pubspec.yaml',
                   'pubspec.lock', 'README.md')),
})
L10N = frozenset({
    'app/l10n.yaml', 'app/tool/l10n_catalog.py', 'app/tool/l10n_merge.py',
    'app/lib/l10n/l10n.dart', 'app/lib/l10n/host_text.dart',
})
SOURCE = frozenset({
    'app/lib/app.dart', 'app/lib/app_variant.dart', 'app/lib/main.dart',
    'app/tool/generate_pet_validation_data.py', 'app/tool/pet-pack.rules.json',
    'infra/forum/tools/gen_emoji_table.py',
    'app/tool/make_replay_viewer.py',
    'site/share/viewer.css', 'site/share/viewer.html', 'site/share/viewer.js',
    'packages/dsh_client/bin/probe.dart', 'packages/dsh_remote/bin/remote_probe.dart',
})
APP_AREAS = frozenset('''
    companion dev diagnostics forum launch links media notify performance
    pets phone plugins remote runtime share_code share_hosted state ui ui_config
    update usage voice wallpaper
'''.split())
UI_AREAS = frozenset('''
    access account agents bots chat common community companion cordis engine
    engine_settings features files forum launch notify onboarding pets phone plugins
    providers remote replay safe_mode session settings share share_code
    share_hosted shell star terminal update wallpaper web workspace
'''.split())
APP_TEST_AREAS = frozenset('''
    account agents chat common diagnostics engine engine_settings files l10n
    landscape links local_web_lite notify onboarding providers remote replay
    runtime search session settings share share_code share_hosted shell state
    support terminal theme web workspace
'''.split())
# The donor ASSETS.md explicitly calls out the generated brand glyph. The tile
# paths are also generated from art masters. Do not stage either or their visual
# wrappers, the target's theme/startup, or generated l10n/replay output.
OMIT = frozenset({
    'app/lib/share_code/replay_viewer.g.dart',
    'app/lib/ui/chat/widgets/whale_tail.dart',
    'app/lib/ui/common/feature_tile.dart',
    'app/lib/ui/common/feature_tile_shapes.g.dart',
    'app/lib/ui/launch/launch_overlay.dart',
    'app/lib/ui/settings/appearance/app_icon_picker.dart',
    'app/lib/ui/shell/brand_glyph.g.dart',
    'app/lib/ui/shell/brand_mark.dart',
    'app/lib/ui/shell/harness_wordmark.dart',
    'app/lib/ui/web/startup_cover.dart',
})
OMIT_SEGMENTS = frozenset({'fixtures', 'goldens', 'snapshots', 'testdata', 'build', 'cache'})


class StageError(ValueError):
    pass


@dataclass(frozen=True)
class Entry:
    path: str
    role: str
    mode: str
    blob: str
    size: int


def classify(path: str) -> str | None:
    if path in OMIT:
        return None
    if path in LICENSES:
        return 'license'
    if path in METADATA:
        return 'metadata'
    if path in L10N or re.fullmatch(r'app/lib/l10n/parts/[a-z0-9_]+_(en|zh)\.arb', path):
        return 'l10n-input'
    if path in SOURCE:
        return 'source'
    if path == 'app/test/flutter_test_config.dart':
        return 'test-source'
    if not path.endswith('.dart'):
        return None
    parts = path.split('/')
    if any(part.lower() in OMIT_SEGMENTS for part in parts):
        return None
    if parts[:2] == ['app', 'lib'] and len(parts) >= 4 and parts[2] in APP_AREAS:
        if parts[2] == 'ui' and (len(parts) < 5 or parts[3] not in UI_AREAS):
            return None
        return 'source'
    if parts[:2] == ['app', 'test'] and len(parts) >= 4 and parts[2] in APP_TEST_AREAS:
        return 'test-source'
    if len(parts) >= 4 and parts[0] == 'packages' and parts[1] in ('dsh_client', 'dsh_remote'):
        if parts[2] == 'lib':
            return 'source'
        if parts[2] == 'test':
            return 'test-source'
    return None


def validate_path(path: str) -> None:
    if len(path) > 240 or any(
        not SAFE_PART.fullmatch(part) or part.endswith('.')
        or DEVICE.fullmatch(part.split('.', 1)[0])
        for part in path.split('/')
    ):
        raise StageError(f'non-portable source path: {path!r}')


def validate_entries(entries: list[Entry]) -> None:
    files = set(COLLISION_FILES)
    names = {name.casefold(): name for name in files}
    dirs = set()
    previous = ''
    total = 0
    for entry in entries:
        path = entry.path
        validate_path(path)
        if path <= previous or classify(path) != entry.role:
            raise StageError(f'duplicate, out-of-order or disallowed source path: {path!r}')
        previous = path
        if entry.mode != '100644' or not SHA1.fullmatch(entry.blob):
            raise StageError(f'expected an ordinary non-executable Git blob: {path!r}')
        if type(entry.size) is not int or not 0 <= entry.size <= MAX_FILE:
            raise StageError(f'invalid blob size: {path!r}')
        total += entry.size
        parts = path.split('/')
        for i in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:i])
            key = prefix.casefold()
            if names.setdefault(key, prefix) != prefix or prefix in files:
                raise StageError(f'file/directory or case collision: {path!r}')
            if i < len(parts):
                dirs.add(prefix)
        if path in dirs:
            raise StageError(f'file/directory collision: {path!r}')
        files.add(path)
    if total > MAX_TOTAL:
        raise StageError('donor exceeds the source size limit')
    required = LICENSES | METADATA | L10N | SOURCE
    if not required <= files:
        raise StageError(f'missing required donor files: {sorted(required - files)}')
    for role in ('l10n-input', 'source', 'test-source'):
        if not any(entry.role == role for entry in entries):
            raise StageError(f'missing donor role: {role}')


def git_command(repo: Path, *args: str) -> list[str]:
    return ['git', '--no-replace-objects', '-C', str(repo.absolute()), *args]


def git_environment() -> dict[str, str]:
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith('GIT_')}
    # Block lazy promisor fetches and all network/file transport fallback, even
    # in Git versions predating GIT_NO_LAZY_FETCH. Only local object reads follow.
    env.update(GIT_NO_LAZY_FETCH='1', GIT_ALLOW_PROTOCOL='', GIT_TERMINAL_PROMPT='0',
               GIT_OPTIONAL_LOCKS='0')
    return env


def git(repo: Path, *args: str) -> bytes:
    result = subprocess.run(git_command(repo, *args), env=git_environment(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        detail = result.stderr.decode('utf-8', 'replace').strip()
        raise StageError(f'local Git {args[0]} failed: {detail}')
    return result.stdout


def parse_inventory(raw: bytes) -> list[Entry]:
    if not raw or not raw.endswith(b'\0'):
        raise StageError('incomplete Git tree listing')
    entries = []
    for row in raw[:-1].split(b'\0'):
        try:
            header, encoded_path = row.split(b'\t', 1)
            mode, kind, oid, size = header.decode('ascii').split()
            path = encoded_path.decode('utf-8', 'surrogateescape')
        except ValueError as exc:
            raise StageError('invalid Git tree record') from exc
        role = classify(path)
        if role is None:
            continue
        if kind != 'blob' or not size.isascii() or not size.isdecimal():
            raise StageError(f'not a plain source blob: {path!r}')
        entries.append(Entry(path, role, mode, oid, int(size)))
    entries.sort(key=lambda entry: entry.path)
    validate_entries(entries)
    return entries


def inventory(repo: Path) -> list[Entry]:
    if git(repo, 'cat-file', '-t', COMMIT).strip() != b'commit':
        raise StageError('the pinned donor object is not a commit')
    if git(repo, 'rev-parse', '--verify', f'{COMMIT}^{{tree}}').strip() != TREE.encode('ascii'):
        raise StageError('the donor commit does not resolve to the pinned tree')
    return parse_inventory(git(repo, 'ls-tree', '-r', '-z', '-l', '--full-tree', TREE))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def blob_oid(data: bytes) -> str:
    return hashlib.sha1(f'blob {len(data)}\0'.encode('ascii') + data,
                        usedforsecurity=False).hexdigest()


def bounded_read(handle, size: int) -> bytes:
    data = handle.read(size)
    if len(data) != size:
        raise StageError('incomplete Git blob')
    return data


def source_bytes(repo: Path, entries: list[Entry]) -> dict[str, bytes]:
    result = {}
    # One batch process without a shell or a worktree checkout. Request by OID,
    # never by path or revision expression, and verify the returned Git hash.
    with subprocess.Popen(git_command(repo, 'cat-file', '--batch'),
                          env=git_environment(), stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE) as process:
        try:
            for entry in entries:
                request = entry.blob.encode('ascii')
                process.stdin.write(request + b'\n')
                process.stdin.flush()
                header = process.stdout.readline(128)
                if header != f'{entry.blob} blob {entry.size}\n'.encode('ascii'):
                    raise StageError(f'unexpected Git blob metadata: {entry.path!r}')
                data = bounded_read(process.stdout, entry.size)
                if bounded_read(process.stdout, 1) != b'\n':
                    raise StageError(f'invalid Git blob framing: {entry.path!r}')
                if blob_oid(data) != entry.blob:
                    raise StageError(f'Git blob hash mismatch: {entry.path!r}')
                if b'\0' in data or data.startswith(b'version https://git-lfs.github.com/spec/'):
                    raise StageError(f'binary or Git LFS pointer in donor source: {entry.path!r}')
                try:
                    data.decode('utf-8')
                except UnicodeDecodeError as exc:
                    raise StageError(f'donor source is not UTF-8: {entry.path!r}') from exc
                result[entry.path] = data
            process.stdin.close()
            if process.stdout.read(1) or process.wait():
                raise StageError('unexpected output or exit from git cat-file')
        except BaseException:
            if process.poll() is None:
                process.kill()
            raise
    return result


def manifest_bytes(entries: list[Entry], hashes: dict[str, str]) -> bytes:
    document = {
        'schema': SCHEMA, 'commit': COMMIT, 'tree': TREE,
        'attributesSha256': digest(ATTRIBUTE_BYTES),
        'files': [dict(path=e.path, role=e.role, mode=e.mode, blob=e.blob,
                       size=e.size, sha256=hashes[e.path]) for e in entries],
    }
    return (json.dumps(document, sort_keys=True, indent=2, ensure_ascii=True) + '\n').encode('ascii')


def load_manifest(raw: bytes) -> tuple[list[Entry], dict[str, str]]:
    if len(raw) > MAX_MANIFEST:
        raise StageError('manifest exceeds the size limit')
    try:
        doc = json.loads(raw)
        if type(doc) is not dict or type(doc.get('files')) is not list:
            raise StageError('invalid manifest object or file list')
        entries = []
        hashes = {}
        for row in doc['files']:
            if type(row) is not dict or set(row) != {'path', 'role', 'mode', 'blob', 'size', 'sha256'}:
                raise StageError('invalid manifest file row')
            if any(type(row[name]) is not str for name in ('path', 'role', 'mode', 'blob', 'sha256')):
                raise StageError('invalid manifest file fields')
            if not SHA256.fullmatch(row['sha256']):
                raise StageError('invalid SHA-256 in manifest')
            entry = Entry(*(row[name] for name in ('path', 'role', 'mode', 'blob', 'size')))
            entries.append(entry)
            hashes[entry.path] = row['sha256']
    except StageError:
        raise
    except (ValueError, RecursionError) as exc:
        raise StageError('invalid manifest JSON') from exc
    validate_entries(entries)
    # Byte comparison also rejects duplicate keys, alternate spellings,
    # unknown headers, misleading pins and noncanonical order/formatting.
    if manifest_bytes(entries, hashes) != raw:
        raise StageError('manifest is not the canonical pinned plan')
    return entries, hashes


def plan(repo: Path) -> tuple[bytes, dict[str, bytes]]:
    entries = inventory(repo)
    data = source_bytes(repo, entries)
    encoded = manifest_bytes(entries, {path: digest(blob) for path, blob in data.items()})
    if len(encoded) > MAX_MANIFEST:
        raise StageError('manifest exceeds the size limit')
    return encoded, data


def check_node(path: Path, *, directory: bool) -> os.stat_result:
    node = path.lstat()
    standard = stat.S_ISDIR(node.st_mode) if directory else stat.S_ISREG(node.st_mode)
    reparse = getattr(node, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT
    if not standard or reparse or (not directory and node.st_nlink != 1):
        raise StageError(f'unexpected linked or special filesystem object: {path}')
    return node


def checked_directory(path: Path) -> Path:
    path = path.absolute()
    if '..' in path.parts:
        raise StageError(f'parent traversal in directory: {path}')
    for node in (*reversed(path.parents), path):
        check_node(node, directory=True)
    return path


def read_regular(path: Path, maximum: int) -> bytes:
    if check_node(path, directory=False).st_size > maximum:
        raise StageError(f'file exceeds the size limit: {path}')
    with path.open('rb') as handle:
        data = handle.read(maximum + 1)
    if len(data) > maximum:
        raise StageError(f'file exceeds the size limit: {path}')
    return data


def write_new(path: Path, data: bytes) -> None:
    with path.open('xb') as handle:
        handle.write(data)


def export(repo: Path, target: Path, reviewed: bytes) -> Path:
    load_manifest(reviewed)
    expected, data = plan(repo)
    if reviewed != expected:
        raise StageError('reviewed plan does not match the pinned Git source')
    root = checked_directory(target)
    vendor = root / DEST.parent
    try:
        vendor.mkdir()
    except FileExistsError:
        pass
    checked_directory(vendor)
    dest = root / DEST
    # Reserve the exact path exclusively. Do not merge even into an empty or
    # previously checked export. Write the completion manifest only at the end.
    dest.mkdir()
    write_new(dest / ATTRIBUTES, ATTRIBUTE_BYTES)
    created = {dest}
    for path, blob in data.items():
        output = dest.joinpath(*path.split('/'))
        for parent in reversed(output.parents):
            if parent == dest or dest not in parent.parents or parent in created:
                continue
            parent.mkdir()
            created.add(parent)
        write_new(output, blob)
    write_new(dest / MANIFEST, expected)
    return dest


def reverify(target: Path, *, repo: Path | None = None, pinned: str | None = None) -> int:
    if (repo is None) == (pinned is None) or (pinned is not None and not SHA256.fullmatch(pinned)):
        raise StageError('reverify requires one local source repository or one pinned manifest SHA-256')
    dest = checked_directory(target.absolute() / DEST)
    raw = read_regular(dest / MANIFEST, MAX_MANIFEST)
    if repo is not None:
        expected, _ = plan(repo)
        if raw != expected:
            raise StageError('staged manifest differs from the pinned Git source')
    elif digest(raw) != pinned:
        raise StageError('staged manifest SHA-256 does not match the independent pin')
    entries, hashes = load_manifest(raw)
    files = {entry.path: entry for entry in entries}
    directories = {str(parent.as_posix()) for path in files for parent in Path(path).parents
                   if parent != Path('.')}
    seen_files = set()
    seen_dirs = set()
    pending = [(dest, '')]
    while pending:
        directory, prefix = pending.pop()
        for path in sorted(directory.iterdir(), key=lambda item: item.name):
            name = prefix + path.name
            if name in directories:
                check_node(path, directory=True)
                seen_dirs.add(name)
                pending.append((path, name + '/'))
            elif name in files:
                entry = files[name]
                data = read_regular(path, entry.size)
                if len(data) != entry.size or digest(data) != hashes[name] or blob_oid(data) != entry.blob:
                    raise StageError(f'staged file differs: {name!r}')
                if os.name != 'nt' and check_node(path, directory=False).st_mode & 0o111:
                    raise StageError(f'staged file is executable: {name!r}')
                seen_files.add(name)
            elif name in COLLISION_FILES:
                expected = raw if name == MANIFEST else ATTRIBUTE_BYTES
                if read_regular(path, len(expected)) != expected:
                    raise StageError(f'staged metadata differs: {name!r}')
                seen_files.add(name)
            else:
                raise StageError(f'unexpected staged path: {name!r}')
    missing = (files.keys() | set(COLLISION_FILES)) - seen_files
    if missing or directories != seen_dirs:
        raise StageError(f'missing staged paths: {sorted(missing | (directories - seen_dirs))}')
    return len(entries)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('plan', help='write the canonical manifest to stdout; create no files')
    p.add_argument('--source-repo', type=Path, required=True)
    p = sub.add_parser('export', help='write a new isolated source tree from a reviewed plan')
    p.add_argument('--source-repo', type=Path, required=True)
    p.add_argument('--plan', type=Path, required=True)
    p.add_argument('--target-root', type=Path, default=TARGET_ROOT)
    p = sub.add_parser('reverify', help='read and compare the exact staged tree')
    p.add_argument('--target-root', type=Path, default=TARGET_ROOT)
    trust = p.add_mutually_exclusive_group(required=True)
    trust.add_argument('--source-repo', type=Path)
    trust.add_argument('--manifest-sha256')
    args = parser.parse_args(argv)
    try:
        if args.command == 'plan':
            raw, _ = plan(args.source_repo)
            sys.stdout.buffer.write(raw)
        elif args.command == 'export':
            plan_path = args.plan.absolute()
            checked_directory(plan_path.parent)
            raw = read_regular(plan_path, MAX_MANIFEST)
            dest = export(args.source_repo, args.target_root, raw)
            print(f'{dest}: manifest SHA-256 {digest(raw)}')
        else:
            count = reverify(args.target_root, repo=args.source_repo, pinned=args.manifest_sha256)
            print(f'Verified {count} source files under {DEST.as_posix()}')
    except (StageError, OSError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
