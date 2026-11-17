#!/usr/bin/env python3
"""Stage a checksum-pinned iOS Node framework; never install or run Node."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PINNED_URL = 'https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-ios-24.22.1-0.zip'
PINNED_SHA256 = '3fa1b8fb0720768b01c2e0dae3a17e788476e8c1613a1d9a54e206793b45326e'
PINNED_BYTES = 62732962
RESOURCE_NAMES = ('probe.cjs', 'meta-probe.mjs', 'requirements.json')
MAX_EXPANDED_BYTES = 1024 * 1024 * 1024


class PreparationError(ValueError):
    """A deterministic input/artifact validation failure."""


def load_requirements(root: Path = ROOT) -> dict:
    requirements = json.loads((root / 'runtime/ios/requirements.json').read_text('utf-8'))
    engine = requirements['engine']
    if engine['lockfile'] != 'runtime/locks/dsh-0.2.2-rc.3/package-lock.json':
        raise PreparationError('ENGINE_LOCK_PATH_MISMATCH')
    lock = json.loads((root / engine['lockfile']).read_text('utf-8'))
    package = lock['packages']['node_modules/' + engine['package']]
    if (engine['package'] != '@deepseek-ai/dsh' or engine['version'] != package['version']
            or engine['node'] != package['engines']['node'] or engine['node'] != '>=24.9.0'):
        raise PreparationError('ENGINE_LOCK_REQUIREMENTS_MISMATCH')
    mobile = requirements['nodeMobile']
    if (mobile['url'], mobile['sha256'], mobile['bytes']) != (PINNED_URL, PINNED_SHA256, PINNED_BYTES):
        raise PreparationError('NODE_MOBILE_PIN_MISMATCH')
    if mobile['flavor'] != 'full' or mobile['version'] != '24.22.1-0':
        raise PreparationError('NODE_MOBILE_VARIANT_MISMATCH')
    return requirements


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify_archive(path: Path, expected_digest: str = PINNED_SHA256,
                   expected_bytes: int = PINNED_BYTES) -> None:
    if not path.is_file() or path.is_symlink():
        raise PreparationError('ARCHIVE_NOT_REGULAR_FILE')
    if path.stat().st_size != expected_bytes or digest_file(path) != expected_digest:
        raise PreparationError('ARCHIVE_INTEGRITY_MISMATCH')


def download_archive(cache: Path) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / 'nodejs-mobile-ios-24.22.1-0.zip'
    if destination.exists() or destination.is_symlink():
        verify_archive(destination)
        return destination
    descriptor, name = tempfile.mkstemp(prefix='.node-mobile-', suffix='.zip', dir=cache)
    temporary = Path(name)
    try:
        request = urllib.request.Request(PINNED_URL, headers={'User-Agent': 'dsh-ios-runtime-preparer/1'})
        with os.fdopen(descriptor, 'wb') as output, urllib.request.urlopen(request, timeout=120) as response:
            total = 0
            while block := response.read(1024 * 1024):
                total += len(block)
                if total > PINNED_BYTES:
                    raise PreparationError('ARCHIVE_SIZE_EXCEEDED')
                output.write(block)
        verify_archive(temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


def archive_members(archive: zipfile.ZipFile) -> tuple[PurePosixPath, list[tuple[zipfile.ZipInfo, PurePosixPath]]]:
    """Inspect every member before extracting; no traversal, links or special files."""
    members = []
    seen = set()
    total = 0
    roots = set()
    for info in archive.infolist():
        name = info.filename
        if '\\' in name or '\x00' in name or ':' in name or name.startswith('/'):
            raise PreparationError('ARCHIVE_PATH_INVALID')
        parts = name.rstrip('/').split('/')
        if any(part in ('', '.', '..') for part in parts):
            raise PreparationError('ARCHIVE_PATH_INVALID')
        member = PurePosixPath(*parts)
        if str(member).casefold() in seen:
            raise PreparationError('ARCHIVE_DUPLICATE_PATH')
        seen.add(str(member).casefold())
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise PreparationError('ARCHIVE_LINK_OR_SPECIAL_FILE')
        if info.flag_bits & 1:
            raise PreparationError('ARCHIVE_ENCRYPTED_MEMBER')
        total += info.file_size
        if total > MAX_EXPANDED_BYTES or len(seen) > 20000:
            raise PreparationError('ARCHIVE_EXPANSION_LIMIT')
        if member.name == 'Info.plist' and member.parent.name == 'NodeMobile.xcframework':
            roots.add(member.parent)
        members.append((info, member))
    if len(roots) != 1:
        raise PreparationError('FRAMEWORK_ROOT_AMBIGUOUS')
    return next(iter(roots)), members


def validate_framework(framework: Path, expected_slices: list[str]) -> dict:
    if framework.is_symlink() or not framework.is_dir():
        raise PreparationError('FRAMEWORK_DIRECTORY_INVALID')
    for item in framework.rglob('*'):
        if item.is_symlink() or not (item.is_file() or item.is_dir()):
            raise PreparationError('FRAMEWORK_LINK_OR_SPECIAL_FILE')
    plist = plistlib.loads((framework / 'Info.plist').read_bytes())
    libraries = plist.get('AvailableLibraries', [])
    if sorted(library.get('LibraryIdentifier', '') for library in libraries) != sorted(expected_slices):
        raise PreparationError('FRAMEWORK_SLICES_MISMATCH')
    for library in libraries:
        identifier = library['LibraryIdentifier']
        if (library.get('SupportedArchitectures') != ['arm64']
                or library.get('SupportedPlatform') != 'ios'
                or library.get('LibraryPath') != 'NodeMobile.framework'):
            raise PreparationError('FRAMEWORK_PLATFORM_MISMATCH')
        expected_variant = 'simulator' if identifier.endswith('-simulator') else None
        if library.get('SupportedPlatformVariant') != expected_variant:
            raise PreparationError('FRAMEWORK_VARIANT_MISMATCH')
        bundle = framework / identifier / 'NodeMobile.framework'
        header = (bundle / 'Headers/NodeMobile.h').read_text('utf-8')
        if 'int node_start(int argc, char *argv[]);' not in header:
            raise PreparationError('FRAMEWORK_ENTRY_API_MISMATCH')
        binary = bundle / 'NodeMobile'
        with binary.open('rb') as stream:
            header_bytes = stream.read(16)
        if (header_bytes[:4] != b'\xcf\xfa\xed\xfe'
                or int.from_bytes(header_bytes[4:8], 'little') != 0x0100000C
                or int.from_bytes(header_bytes[12:16], 'little') != 6):
            raise PreparationError('FRAMEWORK_MACHO_DYLIB_MISMATCH')
    return {'slices': sorted(expected_slices), 'linkage': 'dynamic-framework'}


def extract_framework(archive_path: Path, destination: Path, expected_slices: list[str]) -> dict:
    """Install from one inspected root; never guess extra directory nesting."""
    if destination.is_symlink():
        raise PreparationError('DESTINATION_IS_LINK')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path) as archive:
        root, members = archive_members(archive)
        with tempfile.TemporaryDirectory(prefix='.node-framework-', dir=destination.parent) as temporary:
            staging = Path(temporary) / 'NodeMobile.xcframework'
            staging.mkdir()
            for info, member in members:
                try:
                    relative = member.relative_to(root)
                except ValueError:
                    continue
                if relative == PurePosixPath('.'):
                    continue
                target = staging.joinpath(*relative.parts)
                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info) as source, target.open('xb') as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(0o755 if (info.external_attr >> 16) & 0o111 else 0o644)
            result = validate_framework(staging, expected_slices)
            if destination.exists():
                # Validate links before hashing existing files, then compare all bytes.
                validate_framework(destination, expected_slices)
                old = {str(p.relative_to(destination)): digest_file(p) for p in destination.rglob('*') if p.is_file()}
                new = {str(p.relative_to(staging)): digest_file(p) for p in staging.rglob('*') if p.is_file()}
                if old != new:
                    raise PreparationError('EXISTING_FRAMEWORK_DIFFERS')
            else:
                staging.rename(destination)
            return result


def stage_resources(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise PreparationError('RESOURCE_DESTINATION_IS_LINK')
    for name in RESOURCE_NAMES:
        source = root / 'runtime/ios' / name
        target = destination / name
        if target.is_symlink():
            raise PreparationError('RESOURCE_FILE_IS_LINK')
        with tempfile.NamedTemporaryFile(prefix='.resource-', dir=destination, delete=False) as output:
            temporary = Path(output.name)
            output.write(source.read_bytes())
        try:
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true', help='verify requirements against lock; no network or writes')
    mode.add_argument('--download', action='store_true', help='download/verify and stage framework plus probe resources')
    parser.add_argument('--archive', type=Path, help='use an existing pinned archive instead of network (with --download)')
    args = parser.parse_args(argv)
    if args.archive and not args.download:
        parser.error('--archive requires --download')
    try:
        requirements = load_requirements()
        report = {'schemaVersion': 1, 'mode': 'check', 'requiredNode': requirements['engine']['node'],
                  'nodeMobile': requirements['nodeMobile']['version'], 'engineReady': False}
        if args.download:
            archive = args.archive or download_archive(ROOT / 'runtime/.cache/ios')
            verify_archive(archive)
            embedded = ROOT / 'app/ios/EmbeddedNode'
            report.update(extract_framework(archive, embedded / 'Vendor/NodeMobile.xcframework',
                                            requirements['nodeMobile']['slices']))
            stage_resources(ROOT, embedded / 'Resources')
            report['mode'] = 'download'
            report['archiveSHA256'] = PINNED_SHA256
        print(json.dumps(report, sort_keys=True))
        return 0
    except (PreparationError, OSError, ValueError, KeyError, zipfile.BadZipFile):
        # Deterministic diagnostic, without dumping paths or environment data.
        print(json.dumps({'errorCode': 'IOS_RUNTIME_PREPARATION_FAILED', 'engineReady': False}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
