#!/usr/bin/env python3
"""Resolve and verify the single iOS upstream engine selection (no npm execution)."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read_pin(root: Path = ROOT) -> dict:
    pin = json.loads((root / 'runtime/ios/requirements.json').read_bytes())['engine']
    version = pin.get('version', '')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*)?', version):
        raise ValueError('ENGINE_VERSION_INVALID')
    if pin.get('lockfile') != f'runtime/locks/dsh-{version}/package-lock.json':
        raise ValueError('ENGINE_LOCK_PATH_MISMATCH')
    if pin.get('package') != '@deepseek-ai/dsh':
        raise ValueError('ENGINE_PACKAGE_MISMATCH')
    floor = pin.get('node', '')
    if not isinstance(floor, str) or not re.fullmatch(r'>=[0-9]+\.[0-9]+\.[0-9]+', floor):
        raise ValueError('ENGINE_NODE_CONSTRAINT_UNSUPPORTED')
    # The HTML bootstrap fallback requires the stock release identity. It is
    # tracked here, independently of the mobile Node framework ABI/signature.
    commit = pin.get('webReleaseCommit', '')
    if not isinstance(commit, str) or not re.fullmatch(r'[0-9a-f]{7,40}', commit):
        raise ValueError('ENGINE_RELEASE_COMMIT_INVALID')
    return pin


def validate_lock(root: Path = ROOT) -> dict:
    pin = read_pin(root)
    path = root / pin['lockfile']
    if path.is_symlink() or path.parent.is_symlink() or not path.is_file():
        raise ValueError('ENGINE_LOCK_FILE_INVALID')
    lock = json.loads(path.read_bytes())
    package = pin['package']
    key = 'node_modules/' + package
    rows = lock.get('packages', {})
    official = rows.get(key, {})
    version = pin['version']
    url = f'https://registry.npmjs.org/{package}/-/dsh-{version}.tgz'
    if (rows.get('', {}).get('dependencies', {}).get(package) != version
            or official.get('version') != version or official.get('resolved') != url
            or not re.fullmatch(r'sha512-[A-Za-z0-9+/]{86}==', official.get('integrity', ''))
            or official.get('engines', {}).get('node') != pin.get('node')):
        raise ValueError('ENGINE_LOCK_REQUIREMENTS_MISMATCH')
    package_json = path.with_name('package.json')
    if package_json.is_symlink() or json.loads(package_json.read_bytes()).get('dependencies', {}).get(package) != version:
        raise ValueError('ENGINE_SEED_MANIFEST_MISMATCH')
    return pin


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('field', choices=('version', 'lock-directory', 'node', 'webReleaseCommit'))
    args = parser.parse_args()
    pin = validate_lock()
    if args.field == 'lock-directory':
        print(Path(pin['lockfile']).parent.as_posix())
    else:
        print(pin[args.field])


if __name__ == '__main__':
    main()
