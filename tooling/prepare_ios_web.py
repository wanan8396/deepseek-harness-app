#!/usr/bin/env python3
"""Export the stock frontend from the exact npm-ci seed already used by iOS CI."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from prepare_ios_loader import ENGINE_VERSION as VERSION, LOCK, locked_package, regular_directory

PACKAGE = '@deepseek-ai/dsh-web-frontend'
ALLOWED = {'.css', '.html', '.jpeg', '.jpg', '.js', '.json', '.mjs', '.png', '.ico', '.svg', '.ttf', '.txt', '.wasm', '.webmanifest', '.webp', '.woff', '.woff2'}


def export(seed: Path, output: Path) -> dict:
    regular_directory(seed, seed)
    lock_bytes = LOCK.read_bytes()
    seed_lock = seed / 'package-lock.json'
    if seed_lock.is_symlink() or seed_lock.read_bytes() != lock_bytes:
        raise ValueError('IOS_WEB_SEED_LOCK_MISMATCH')
    relative, locked, package = locked_package(seed, json.loads(lock_bytes), None, PACKAGE)
    assert package['version'] == VERSION and package['license'] == 'MIT', 'IOS_WEB_PACKAGE_CONTRACT'
    root = seed / relative
    dist = root / 'dist'
    regular_directory(dist, seed)
    if output.exists() or output.is_symlink():
        raise ValueError('IOS_WEB_OUTPUT_EXISTS')
    output.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    with tempfile.TemporaryDirectory(prefix='.ios-web-export-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'web'
        stage.mkdir()
        inputs = []
        for source in sorted(dist.rglob('*')):
            if source.is_symlink():
                raise ValueError('IOS_WEB_UNEXPECTED_SYMLINK')
            if source.is_dir():
                continue
            rel = source.relative_to(dist)
            if source.suffix == '.map':
                continue
            if not source.is_file() or source.suffix not in ALLOWED:
                raise ValueError(f'IOS_WEB_UNREVIEWED_FILE:{rel.as_posix()}')
            inputs.append((source, rel))
        license_file = root / 'LICENSE'
        if not license_file.is_file() or license_file.is_symlink():
            raise ValueError('IOS_WEB_LICENSE_MISSING')
        inputs.append((license_file, Path('LICENSE')))
        for source, rel in inputs:
            if source.stat().st_size > 64 * 1024 * 1024:
                raise ValueError('IOS_WEB_FILE_TOO_LARGE')
            dest = stage / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest)
            entries.append({'path': rel.as_posix(), 'bytes': dest.stat().st_size,
                            'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()})
        if not (stage / 'index.html').is_file() or not any('/index-' in x['path'] and x['path'].endswith('.js') for x in entries):
            raise ValueError('IOS_WEB_ENTRY_MISSING')
        manifest = dict(package=PACKAGE, version=VERSION, integrity=locked['integrity'],
                        sourceLockSHA256=hashlib.sha256(lock_bytes).hexdigest(), files=entries)
        (stage / 'distribution-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        stage.rename(output)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    manifest = export(args.seed, args.output)
    print(json.dumps(dict(package=manifest['package'], version=manifest['version'], files=len(manifest['files']))))


if __name__ == '__main__':
    main()
