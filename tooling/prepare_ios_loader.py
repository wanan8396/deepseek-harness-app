#!/usr/bin/env python3
"""Export a reviewed, locked pure-JS DSH Loader probe from a prior npm-ci seed.

This script does not install, execute, bundle, or patch any supplier package.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'runtime/locks/dsh-0.2.2-rc.3/package-lock.json'
DEFAULT_OUTPUT = ROOT / 'app/ios/EmbeddedNode/Resources/dsh-loader'
ENTRY_PACKAGE = '@deepseek-ai/dsh-app-boot'
# Any dependency-graph expansion requires a source review, not automatic copying.
REVIEWED_PACKAGES = frozenset({
    '@deepseek-ai/dsh-app-boot', '@deepseek-ai/dsh-atomic-write',
    '@deepseek-ai/dsh-home-paths', '@deepseek-ai/dsh-launch-environment',
    '@deepseek-ai/dsh-native-command', '@deepseek-ai/dsh-official-bundles',
    '@deepseek-ai/dsh-package-manifest', '@deepseek-ai/cordis',
    '@deepseek-ai/cordis-plugin-loader', '@deepseek-ai/cordis-plugin-include',
    '@deepseek-ai/cordis-plugin-group', '@deepseek-ai/cosmokit',
    '@deepseek-ai/schemastery', '@standard-schema/spec',
    '@eslint-community/regexpp', 'ajv', 'argparse', 'fast-deep-equal',
    'fast-uri', 'js-yaml', 'json-schema-traverse', 'require-from-string',
    'resolve.exports', 'semver',
})
EXCLUDED = {
    'node-addon-require-builtin': (
        'Unused by this relative-fixture-only boot: no PluginPackages, runtime '
        'profile resolution, schema projection or HMR. Loader optional internal '
        'lookup has its existing no-internals fallback. No replacement shim.'),
}
RUNTIME_EXTENSIONS = {'.js', '.mjs', '.cjs', '.json', '.yml', '.yaml'}
NATIVE_MAGIC = {b'\x7fELF', b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe',
                b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


class ExportError(ValueError):
    """A deterministic contract failure; its code contains no private data."""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def regular_directory(path: Path, base: Path) -> None:
    if path.is_symlink() or not path.is_dir() or not path.resolve().is_relative_to(base.resolve()):
        raise ExportError('SEED_DIRECTORY_INVALID')


def locked_package(seed: Path, lock: dict, parent: PurePosixPath | None, name: str) -> tuple[PurePosixPath, dict, dict]:
    if not re.fullmatch(r'(?:@[a-zA-Z0-9_.-]+/)?[a-zA-Z0-9_.-]+', name):
        raise ExportError('PACKAGE_NAME_INVALID')
    candidates = []
    if parent is not None:
        parts = parent.parts
        for index in range(len(parts), 0, -1):
            if parts[index - 1] != 'node_modules':
                candidates.append(PurePosixPath(*parts[:index], 'node_modules', name))
    candidates.append(PurePosixPath('node_modules', name))
    for relative in candidates:
        entry = lock['packages'].get(str(relative))
        package_dir = seed.joinpath(*relative.parts)
        if entry is None or not (package_dir / 'package.json').is_file():
            continue
        regular_directory(package_dir, seed)
        if (package_dir / 'package.json').is_symlink():
            raise ExportError('PACKAGE_MANIFEST_IS_LINK')
        manifest = json.loads((package_dir / 'package.json').read_text('utf-8'))
        if (entry.get('link') or manifest.get('name') != name
                or manifest.get('version') != entry.get('version')):
            raise ExportError('INSTALLED_PACKAGE_LOCK_MISMATCH')
        for key in ('dependencies', 'peerDependencies', 'optionalDependencies'):
            if manifest.get(key, {}) != entry.get(key, {}):
                raise ExportError('INSTALLED_DEPENDENCY_CONTRACT_MISMATCH')
        url = urlparse(entry.get('resolved', ''))
        if (url.scheme != 'https' or url.netloc != 'registry.npmjs.org'
                or not re.fullmatch(r'sha512-[A-Za-z0-9+/=]+', entry.get('integrity', ''))):
            raise ExportError('PACKAGE_SOURCE_NOT_LOCKED_NPM')
        return relative, entry, manifest
    raise ExportError('REQUIRED_LOCKED_PACKAGE_MISSING')


def dependency_closure(seed: Path, lock: dict) -> tuple[dict, list]:
    selected = {}
    omitted = []
    queue = [(None, ENTRY_PACKAGE)]
    while queue:
        parent, name = queue.pop(0)
        if name in EXCLUDED:
            omitted.append({'parent': str(parent), 'package': name, 'reason': EXCLUDED[name]})
            continue
        if name not in REVIEWED_PACKAGES:
            raise ExportError('UNREVIEWED_DEPENDENCY_EXPANSION')
        relative, locked, manifest = locked_package(seed, lock, parent, name)
        if str(relative) in selected:
            continue
        selected[str(relative)] = (locked, manifest)
        dependencies = dict(manifest.get('dependencies', {}))
        dependencies.update(manifest.get('peerDependencies', {}))
        for dependency in sorted(dependencies):
            queue.append((relative, dependency))
        for dependency in sorted(manifest.get('optionalDependencies', {})):
            if dependency not in dependencies:
                raise ExportError('UNREVIEWED_OPTIONAL_DEPENDENCY')
    return selected, omitted


def is_runtime_file(relative: Path) -> bool:
    name = relative.name.lower()
    return (relative.suffix.lower() in RUNTIME_EXTENSIONS
            or name.startswith(('license', 'licence', 'copying', 'notice', 'readme')))


def runtime_targets(value, condition=None):
    if isinstance(value, str):
        if condition != 'types' and not value.endswith(('.ts', '.cts', '.mts')):
            yield value
    elif isinstance(value, list):
        for child in value:
            yield from runtime_targets(child, condition)
    elif isinstance(value, dict):
        for key, child in value.items():
            if key == 'types' or key.startswith('./src/') or key == 'standard-schema-spec':
                continue
            yield from runtime_targets(child, key)


def validate_entry_targets(manifest: dict, kept: set[str]) -> None:
    # Types and source-only exports are not executable Node targets. Do not
    # modify package.json to hide their deliberate development-source omission.
    targets = list(runtime_targets(manifest.get('exports', {})))
    for key in ('main', 'module'):
        target = manifest.get(key)
        if isinstance(target, str):
            targets.append(target)
    for target in targets:
        clean = target[2:] if target.startswith('./') else target
        if clean.startswith(('node:', '#')):
            continue
        pure = PurePosixPath(clean)
        if pure.is_absolute() or '..' in pure.parts or '\\' in clean:
            raise ExportError('PACKAGE_ENTRY_TARGET_INVALID')
        if '*' in clean:
            pattern = re.compile('^' + re.escape(clean).replace(r'\*', '.*') + '$')
            if not any(pattern.match(filename) for filename in kept):
                raise ExportError('RUNTIME_EXPORT_TARGET_MISSING')
        elif not any(candidate in kept for candidate in (clean, clean + '.js', clean + '.json', clean + '/index.js')):
            raise ExportError('RUNTIME_ENTRY_TARGET_MISSING')


def collect_files(seed: Path, selected: dict) -> tuple[list, list]:
    files = []
    omitted_files = []
    for relative_name, (locked, manifest) in sorted(selected.items()):
        package_dir = seed / relative_name
        kept = set()
        has_license = False
        for directory, directories, names in os.walk(package_dir, followlinks=False):
            current = Path(directory)
            for name in list(directories):
                child = current / name
                if child.is_symlink():
                    raise ExportError('PACKAGE_DIRECTORY_IS_LINK')
                if name == 'node_modules':
                    directories.remove(name)
            for name in sorted(names):
                source = current / name
                if source.is_symlink() or not source.is_file():
                    raise ExportError('PACKAGE_FILE_NOT_REGULAR')
                data = source.read_bytes()
                if (source.suffix.lower() == '.node' or data[:4] in NATIVE_MAGIC
                        or data.startswith((b'MZ', b'!<arch>'))):
                    raise ExportError('NATIVE_PACKAGE_CONTENT_UNSUPPORTED')
                local = source.relative_to(package_dir)
                destination = PurePosixPath(relative_name, local.as_posix())
                if is_runtime_file(local):
                    kept.add(local.as_posix())
                    has_license |= name.lower().startswith(('license', 'licence', 'copying'))
                    files.append((source, str(destination), sha256(data), len(data)))
                else:
                    omitted_files.append({'path': str(destination), 'sha256': sha256(data),
                                          'reason': 'non-runtime-source-map-type-or-development-resource'})
        if not has_license:
            raise ExportError('PACKAGE_LICENSE_MISSING')
        validate_entry_targets(manifest, kept)
    return files, omitted_files


def prepare(seed: Path, destination: Path, check: bool = False) -> dict:
    regular_directory(seed, seed)
    lock_bytes = LOCK.read_bytes()
    if (seed / 'package-lock.json').is_symlink() or (seed / 'package-lock.json').read_bytes() != lock_bytes:
        raise ExportError('SEED_LOCK_BYTES_MISMATCH')
    lock = json.loads(lock_bytes)
    if lock['packages']['node_modules/@deepseek-ai/dsh-app-boot']['version'] != '0.2.2-rc.3':
        raise ExportError('ENGINE_VERSION_MISMATCH')
    selected, omitted = dependency_closure(seed, lock)
    files, omitted_files = collect_files(seed, selected)
    own_files = [ROOT / 'runtime/ios' / name for name in ('loader-probe.mjs', 'loader-fixture.mjs')]
    for source in own_files:
        data = source.read_bytes()
        files.append((source, source.name, sha256(data), len(data)))
    omitted_native = [{'path': key, 'version': value.get('version'),
                       'integrity': value.get('integrity'),
                       'reason': 'Excluded require-builtin native dependency chain; no shim is installed'}
                      for key, value in sorted(lock['packages'].items())
                      if key.rsplit('/node_modules/', 1)[-1].startswith((
                          'node_modules/node-addon-require-builtin', 'node_modules/node-addon-native-custom-loader'))
                      or key.split('node_modules/')[-1].startswith((
                          'node-addon-require-builtin', 'node-addon-native-custom-loader'))]
    manifest = {
        'schemaVersion': 1, 'distribution': 'ios-adapted-loader-probe', 'engineVersion': '0.2.2-rc.3',
        'sourceLockSHA256': sha256(lock_bytes),
        'integrityVerification': 'Seed must be created by npm ci --ignore-scripts; exporter verifies exact lock and package identities, then hashes output files',
        'entryPackage': ENTRY_PACKAGE, 'engineReady': False,
        'excludedFeatures': ['PluginPackages', 'profile-runtime-resolution', 'HMR', 'agents', 'models', 'subprocesses'],
        'packages': [{'path': key, 'name': value[1]['name'], 'version': value[0]['version'],
                      'resolved': value[0]['resolved'], 'integrity': value[0]['integrity'],
                      'sourceManifestSHA256': sha256((seed / key / 'package.json').read_bytes()),
                      'license': value[1].get('license')}
                     for key, value in sorted(selected.items())],
        'omittedDependencies': omitted, 'omittedNativePackages': omitted_native,
        'omittedFiles': omitted_files,
        'files': [{'path': relative, 'sha256': digest, 'bytes': size}
                  for _source, relative, digest, size in sorted(files, key=lambda item: item[1])],
    }
    if check:
        return manifest
    if destination.exists() or destination.is_symlink():
        raise ExportError('DESTINATION_ALREADY_EXISTS')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.dsh-loader-stage-', dir=destination.parent) as temporary:
        staging = Path(temporary) / 'dsh-loader'
        staging.mkdir()
        for source, relative, digest, _size in files:
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            data = source.read_bytes()
            if sha256(data) != digest:
                raise ExportError('SOURCE_CHANGED_DURING_EXPORT')
            target.write_bytes(data)
            target.chmod(0o644)
        (staging / 'distribution-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        staging.rename(destination)
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=Path, required=True, help='Independent exact-lock npm ci seed')
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--check', action='store_true', help='Inspect seed and hashes only; write nothing')
    args = parser.parse_args(argv)
    try:
        manifest = prepare(args.seed, args.output, args.check)
        print(json.dumps({'distribution': manifest['distribution'], 'packageCount': len(manifest['packages']),
                          'fileCount': len(manifest['files']), 'sourceLockSHA256': manifest['sourceLockSHA256'],
                          'engineReady': False}, sort_keys=True))
        return 0
    except (ExportError, OSError, ValueError, KeyError) as error:
        code = str(error) if isinstance(error, ExportError) else 'IOS_LOADER_EXPORT_FAILED'
        print(json.dumps({'errorCode': code, 'engineReady': False}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
