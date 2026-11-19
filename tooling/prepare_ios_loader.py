#!/usr/bin/env python3
"""Export a reviewed, locked pure-JS DSH Loader or core probe from a prior npm-ci seed.

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

from ios_engine_pin import ROOT, read_pin

ENGINE = read_pin()
LOCK = ROOT / ENGINE['lockfile']
ENGINE_VERSION = ENGINE['version']
DEFAULT_OUTPUT = ROOT / 'app/ios/EmbeddedNode/Resources/dsh-loader'
DEFAULT_CORE_OUTPUT = DEFAULT_OUTPUT.with_name('dsh-core')
DEFAULT_PERSISTENCE_OUTPUT = DEFAULT_OUTPUT.with_name('dsh-persistence')
DEFAULT_CHAT_OUTPUT = DEFAULT_OUTPUT.with_name('dsh-chat')
DEFAULT_OFFICIAL_HOST_OUTPUT = ROOT / 'app/ios/RunnerTests/dsh-official-host-ci'
DEFAULT_OFFICIAL_APP_OUTPUT = DEFAULT_OUTPUT.with_name('dsh-official-app')
OFFICIAL_PHASES = ('official-host-ci', 'official-app')
OFFICIAL_HOST_ENTRY_PACKAGES = (
    '@deepseek-ai/dsh-agent-default-model', '@deepseek-ai/dsh-api-gateway',
    '@deepseek-ai/dsh-api-remote-access', '@deepseek-ai/dsh-api-remotes',
    '@deepseek-ai/dsh-api-session-controller', '@deepseek-ai/dsh-api-workspace-controller',
    '@deepseek-ai/dsh-attachment-local', '@deepseek-ai/dsh-client-connection',
    '@deepseek-ai/dsh-client-file-upload', '@deepseek-ai/dsh-commands',
    '@deepseek-ai/dsh-credentials-local', '@deepseek-ai/dsh-fs-local',
    '@deepseek-ai/dsh-session-query-sqlite', '@deepseek-ai/dsh-storage-json',
    '@deepseek-ai/dsh-typert-registry', '@deepseek-ai/dsh-tool-fs', '@deepseek-ai/dsh-fs-observation-policy',
)
# Official Host composition. Files are still checked for native executable content.
OFFICIAL_HOST_REVIEWED_PACKAGES = frozenset(OFFICIAL_HOST_ENTRY_PACKAGES) | frozenset({
    '@babel/code-frame', '@babel/helper-validator-identifier', '@deepseek-ai/cordis-plugin-timer',
    '@deepseek-ai/dsh-agent-preset-registry', '@deepseek-ai/dsh-chunked-list',
    '@deepseek-ai/dsh-cmdline', '@deepseek-ai/dsh-compaction', '@deepseek-ai/dsh-compaction-image-offload',
    '@deepseek-ai/dsh-config-editor', '@deepseek-ai/dsh-credentials', '@deepseek-ai/dsh-deque',
    '@deepseek-ai/dsh-file-reference', '@deepseek-ai/dsh-hmr',
    '@deepseek-ai/dsh-host-directory-picker', '@deepseek-ai/dsh-http-proxy',
    '@deepseek-ai/dsh-lazy-require', '@deepseek-ai/dsh-permission-presets', '@deepseek-ai/dsh-sandbox-policy',
    '@deepseek-ai/dsh-session-format', '@deepseek-ai/dsh-session-format-catalog',
    '@deepseek-ai/dsh-session-format-v0-to-v1', '@deepseek-ai/dsh-session-format-v1-to-v2',
    '@deepseek-ai/dsh-session-format-v2-to-v3', '@deepseek-ai/dsh-session-format-v3-to-v4',
    '@deepseek-ai/dsh-session-projection-cache', '@deepseek-ai/dsh-session-query',
    '@deepseek-ai/dsh-session-title', '@deepseek-ai/dsh-settings', '@deepseek-ai/dsh-shell',
    '@deepseek-ai/dsh-skill', '@deepseek-ai/dsh-subagent', '@deepseek-ai/dsh-subprocess',
    '@deepseek-ai/dsh-tool-todo', '@deepseek-ai/dsh-util-time', '@deepseek-ai/dsh-util-workspace-path',
    '@deepseek-ai/dsh-util-code-language', 'diff',
    '@deepseek-ai/dsh-working-directory', '@js-temporal/polyfill', 'chokidar', 'js-tokens', 'jsbi',
    'mime-db', 'mime-types', 'picocolors', 'picomatch', 'readdirp', 'rrule', 'tslib', 'undici', 'ws', 'yaml',
})
OFFICIAL_HOST_EXCLUSIONS = {
    ('dsh-attachment-local', 'sharp'): 'Lazy raster normalization is not exercised or exposed by the CI session seam.',
    ('dsh-fs-local', 'koffi'): 'Windows-only file operations are not used by this composition.',
    ('ws', 'bufferutil'): 'Optional WebSocket accelerator; no WebSocket carrier is mounted.',
    ('ws', 'utf-8-validate'): 'Optional WebSocket accelerator; no WebSocket carrier is mounted.',
}
CHECKPOINT_PACKAGE = '@deepseek-ai/dsh-session-checkpoint-policy'
CHAT_PROVIDER_PACKAGE = '@deepseek-ai/dsh-llm-deepseek'
ENTRY_PACKAGE = '@deepseek-ai/dsh-app-boot'
CORE_ENTRY_PACKAGES = (
    '@deepseek-ai/dsh-session-projection', '@deepseek-ai/dsh-session',
    '@deepseek-ai/dsh-system-prompt', '@deepseek-ai/dsh-tools',
    '@deepseek-ai/dsh-tool-executor-native', '@deepseek-ai/dsh-llm',
    '@deepseek-ai/dsh-agent', '@deepseek-ai/dsh-agent-loop',
)
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
# Reviewed rc.3 npm manifests and shipped lib/*.js: these add service/registry,
# event-log, scoped-context and direct JS tool execution seams, not native addons.
# Include agent's optional workspace peer and its abstract storage dependencies;
# do not substitute concrete persistence, model-provider or subprocess packages.
CORE_REVIEWED_PACKAGES = REVIEWED_PACKAGES | frozenset({
    '@deepseek-ai/dsh-session-projection', '@deepseek-ai/dsh-session',
    '@deepseek-ai/dsh-system-prompt', '@deepseek-ai/dsh-tools',
    '@deepseek-ai/dsh-tool-executor-native', '@deepseek-ai/dsh-llm',
    '@deepseek-ai/dsh-agent', '@deepseek-ai/dsh-agent-loop',
    '@deepseek-ai/dsh-brand', '@deepseek-ai/dsh-error', '@deepseek-ai/dsh-scope',
    '@deepseek-ai/dsh-session-persistence', '@deepseek-ai/dsh-storage',
    '@deepseek-ai/dsh-storage-domain', '@deepseek-ai/dsh-timeout',
    '@deepseek-ai/dsh-typert-protocol', '@deepseek-ai/dsh-user-approval',
    '@deepseek-ai/dsh-util-crypto', '@deepseek-ai/dsh-util-values',
    '@deepseek-ai/dsh-workspace', 'zod',
})
# Official Messages adapter, SSE parser, and manifest dependencies. The App mounts
# only its text adapter; attachment, sandbox and filesystem plugin services are not mounted.
CHAT_REVIEWED_PACKAGES = frozenset({
    CHAT_PROVIDER_PACKAGE, 'eventsource-parser', '@deepseek-ai/dsh-attachment',
    '@deepseek-ai/dsh-anonymous-user-id', '@deepseek-ai/dsh-deepseek-llm-api-extensions',
    '@deepseek-ai/dsh-fs', '@deepseek-ai/dsh-fs-patch', '@deepseek-ai/dsh-sandbox',
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
    """A deterministic code, optionally with bounded public npm export details."""

    def __init__(self, code: str, *, package: str | None = None, target: str | None = None):
        super().__init__(code)
        self.public_details = {}
        if (isinstance(package, str) and len(package) <= 214
                and re.fullmatch(r'(?:@[a-zA-Z0-9_.-]+/)?[a-zA-Z0-9_.-]+', package)):
            self.public_details['package'] = package
        if (isinstance(target, str) and len(target) <= 256
                and re.fullmatch(r'[a-zA-Z0-9_./@*+-]+', target)
                and not PurePosixPath(target).is_absolute() and '..' not in PurePosixPath(target).parts):
            self.public_details['target'] = target


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


def phase_entry_packages(phase: str) -> tuple[str, ...]:
    if phase == 'loader':
        return (ENTRY_PACKAGE,)
    if phase == 'core':
        return (ENTRY_PACKAGE, *CORE_ENTRY_PACKAGES)
    if phase in ('persistence', 'chat', *OFFICIAL_PHASES):
        entries = (ENTRY_PACKAGE, *CORE_ENTRY_PACKAGES, CHECKPOINT_PACKAGE)
        if phase == 'chat':
            return (*entries, CHAT_PROVIDER_PACKAGE)
        if phase in OFFICIAL_PHASES:
            return (*entries, CHAT_PROVIDER_PACKAGE, *OFFICIAL_HOST_ENTRY_PACKAGES)
        return entries
    raise ExportError('EXPORT_PHASE_INVALID')


def dependency_closure(seed: Path, lock: dict, phase: str = 'loader') -> tuple[dict, list]:
    selected = {}
    omitted = []
    queue = [(None, name) for name in phase_entry_packages(phase)]
    reviewed = REVIEWED_PACKAGES if phase == 'loader' else CORE_REVIEWED_PACKAGES
    if phase in ('persistence', 'chat', *OFFICIAL_PHASES):
        reviewed = reviewed | {CHECKPOINT_PACKAGE}
    if phase in ('chat', *OFFICIAL_PHASES):
        reviewed = reviewed | CHAT_REVIEWED_PACKAGES
    if phase in OFFICIAL_PHASES:
        reviewed = reviewed | OFFICIAL_HOST_REVIEWED_PACKAGES
    while queue:
        parent, name = queue.pop(0)
        if phase in OFFICIAL_PHASES and parent is not None:
            why = OFFICIAL_HOST_EXCLUSIONS.get((parent.name, name))
            if why is not None:
                omitted.append({'parent': str(parent), 'package': name, 'reason': why})
                continue
        if name in EXCLUDED:
            omitted.append({'parent': str(parent), 'package': name, 'reason': EXCLUDED[name]})
            continue
        if name not in reviewed:
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


def reviewed_development_exports(manifest: dict) -> list:
    # zod 4.6.6 declares ./src/v4/locales/* without a .ts suffix under its
    # development-only condition. Node is not launched with @zod/source.
    if manifest.get('name') != 'zod' or manifest.get('version') != '4.6.6':
        return []
    exports = manifest.get('exports', {})
    if not isinstance(exports, dict):
        return []
    targets = [value['@zod/source'] for value in exports.values()
               if isinstance(value, dict) and '@zod/source' in value]
    if not targets or any(not isinstance(target, str) or not target.startswith('./src/')
                          or len(target) > 256 or not re.fullmatch(r'[a-zA-Z0-9_./@*+-]+', target)
                          or '..' in PurePosixPath(target).parts for target in targets):
        return []
    return [{'package': 'zod', 'condition': '@zod/source', 'targets': sorted(set(targets)),
             'reason': 'official development-source condition is not selected by Node; source files omitted, no synthesized files'}]


def runtime_targets(value, condition=None, skipped_conditions=frozenset()):
    if isinstance(value, str):
        if condition != 'types' and not value.endswith(('.ts', '.cts', '.mts')):
            yield value
    elif isinstance(value, list):
        for child in value:
            yield from runtime_targets(child, condition, skipped_conditions)
    elif isinstance(value, dict):
        for key, child in value.items():
            if key == 'types' or key.startswith('./src/') or key == 'standard-schema-spec' or key in skipped_conditions:
                continue
            yield from runtime_targets(child, key, skipped_conditions)


def validate_entry_targets(manifest: dict, kept: set[str]) -> list:
    # Types and reviewed development conditions are not executable Node targets.
    # Keep package.json's complete exports unchanged in the supplier output.
    omitted = reviewed_development_exports(manifest)
    skipped = frozenset(entry['condition'] for entry in omitted)
    targets = list(runtime_targets(manifest.get('exports', {}), skipped_conditions=skipped))
    for key in ('main', 'module'):
        target = manifest.get(key)
        if isinstance(target, str):
            targets.append(target)
    for target in targets:
        # Locked tslib exposes a package-root directory alias as well as its
        # concrete entry points. The other targets and every kept file are checked.
        if target == './' and manifest.get('name') == 'tslib' and manifest.get('version') == '2.9.1':
            continue
        clean = target[2:] if target.startswith('./') else target
        if clean.startswith(('node:', '#')):
            continue
        pure = PurePosixPath(clean)
        if pure.is_absolute() or '..' in pure.parts or '\\' in clean:
            raise ExportError('PACKAGE_ENTRY_TARGET_INVALID')
        if '*' in clean:
            pattern = re.compile('^' + re.escape(clean).replace(r'\*', '.*') + '$')
            if not any(pattern.match(filename) for filename in kept):
                raise ExportError('RUNTIME_EXPORT_TARGET_MISSING', package=manifest.get('name'), target=target)
        else:
            # diff's compatibility aliases use directory targets with trailing
            # slashes. Check the actual archived index, not a doubled separator.
            candidates = ((clean + 'index.js',) if clean.endswith('/') else
                          (clean, clean + '.js', clean + '.json', clean + '/index.js'))
            if not any(candidate in kept for candidate in candidates):
                raise ExportError('RUNTIME_ENTRY_TARGET_MISSING', package=manifest.get('name'), target=target)
    return omitted


def collect_files(seed: Path, selected: dict, omitted_exports: list | None = None) -> tuple[list, list]:
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
        omitted = validate_entry_targets(manifest, kept)
        if omitted_exports is not None:
            omitted_exports.extend(omitted)
    return files, omitted_files


def prepare(seed: Path, destination: Path, check: bool = False, phase: str = 'loader') -> dict:
    entries = phase_entry_packages(phase)
    regular_directory(seed, seed)
    lock_bytes = LOCK.read_bytes()
    if (seed / 'package-lock.json').is_symlink() or (seed / 'package-lock.json').read_bytes() != lock_bytes:
        raise ExportError('SEED_LOCK_BYTES_MISMATCH')
    lock = json.loads(lock_bytes)
    if lock['packages']['node_modules/@deepseek-ai/dsh-app-boot']['version'] != ENGINE_VERSION:
        raise ExportError('ENGINE_VERSION_MISMATCH')
    selected, omitted = dependency_closure(seed, lock, phase)
    omitted_exports = []
    files, omitted_files = collect_files(seed, selected, omitted_exports)
    own_names = {
        'loader': ('loader-probe.mjs', 'loader-fixture.mjs'),
        'core': ('core-probe.mjs', 'core-fixture-model.mjs'),
        'persistence': ('persistence-probe.mjs', 'sqlite-session-persistence.mjs', 'core-fixture-model.mjs'),
        'chat': ('chat-engine.mjs', 'chat-deepseek-provider.mjs', 'chat-mailbox.mjs',
                 'chat-approval.mjs', 'chat-model-channel.mjs', 'chat-workspace-tools.mjs',
                 'sqlite-session-persistence.mjs'),
        'official-host-ci': ('official-host.mjs', 'official-host-ci-mailbox.mjs', 'sqlite-session-persistence.mjs',
                             'core-fixture-model.mjs', 'official-app-services.mjs', 'official-app-routes.mjs', 'chat-model-channel.mjs',
                             'chat-deepseek-provider.mjs', 'official-workspace-fs.mjs'),
        'official-app': ('official-host.mjs', 'official-app-services.mjs', 'official-app-routes.mjs', 'official-app-mailbox.mjs',
                         'sqlite-session-persistence.mjs', 'chat-model-channel.mjs', 'chat-deepseek-provider.mjs',
                         'official-workspace-fs.mjs'),
    }[phase]
    own_files = [ROOT / 'runtime/ios' / name for name in own_names]
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
        'schemaVersion': 1, 'engineVersion': ENGINE_VERSION,
        'distribution': 'ios-local-text-chat' if phase == 'chat' else f'ios-adapted-{phase}-probe',
        'sourceLockSHA256': sha256(lock_bytes),
        'integrityVerification': 'Seed must be created by npm ci --ignore-scripts; exporter verifies exact lock and package identities, then hashes output files',
        'entryPackage': ENTRY_PACKAGE, 'engineReady': False,
        'excludedFeatures': ['PluginPackages', 'profile-runtime-resolution', 'HMR', 'subprocesses'] + {
            'loader': ['agents', 'models'],
            'core': ['web-profile', 'model-provider-network', 'concrete-session-persistence'],
            'persistence': ['web-profile', 'model-provider-network', 'official-jsonl-storage', 'chat-transport'],
            'chat': ['web-profile', 'official-jsonl-storage', 'unrestricted-tools', 'attachments', 'remote-engine'],
            'official-host-ci': ['production-web-ui', 'raster-attachments', 'model-provider-network'],
            'official-app': ['raster-attachments', 'file-upload', 'directory-picker', 'remote-engine', 'desktop-opener'],
        }[phase],
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
    if phase != 'loader':
        manifest['phase'] = phase
        manifest['entryPackages'] = list(entries)
        manifest['omittedExports'] = omitted_exports
    if check:
        return manifest
    if destination.exists() or destination.is_symlink():
        raise ExportError('DESTINATION_ALREADY_EXISTS')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f'.dsh-{phase}-stage-', dir=destination.parent) as temporary:
        staging = Path(temporary) / f'dsh-{phase}'
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
    parser.add_argument('--phase', choices=('loader', 'core', 'persistence', 'chat', *OFFICIAL_PHASES), default='loader')
    parser.add_argument('--output', type=Path, help='Defaults to the phase-specific dsh-* resources directory')
    parser.add_argument('--check', action='store_true', help='Inspect seed and hashes only; write nothing')
    args = parser.parse_args(argv)
    output = args.output if args.output is not None else {
        'loader': DEFAULT_OUTPUT, 'core': DEFAULT_CORE_OUTPUT, 'persistence': DEFAULT_PERSISTENCE_OUTPUT,
        'chat': DEFAULT_CHAT_OUTPUT, 'official-host-ci': DEFAULT_OFFICIAL_HOST_OUTPUT, 'official-app': DEFAULT_OFFICIAL_APP_OUTPUT,
    }[args.phase]
    try:
        manifest = prepare(args.seed, output, args.check, args.phase)
        print(json.dumps({'distribution': manifest['distribution'], 'packageCount': len(manifest['packages']),
                          'fileCount': len(manifest['files']), 'sourceLockSHA256': manifest['sourceLockSHA256'],
                          'engineReady': False}, sort_keys=True))
        return 0
    except (ExportError, OSError, ValueError, KeyError) as error:
        code = str(error) if isinstance(error, ExportError) else 'IOS_LOADER_EXPORT_FAILED'
        details = error.public_details if isinstance(error, ExportError) else {}
        print(json.dumps({'errorCode': code, 'engineReady': False, **details}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
