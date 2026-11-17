#!/usr/bin/env python3
"""Verify a real Xcode/Flutter iOS application without claiming DSH booted."""
import argparse
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--simulator', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'app.dsh.ios'
    assert info['UIDeviceFamily'] == [1, 2], 'Expected iPhone and iPad target'
    assert info['CFBundleSupportedPlatforms'] == (['iPhoneSimulator'] if args.simulator else ['iPhoneOS'])
    assert info.get('LSRequiresIPhoneOS') is True
    node = app / 'Frameworks/NodeMobile.framework/NodeMobile'
    binary = app / info['CFBundleExecutable']
    assert node.is_file() and binary.is_file()
    assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(node)], text=True)
    assert not any(app.rglob('libproot.so')), 'Android runtime entered the iOS bundle'
    assert not any(app.rglob('rootfs-*.tar.xz')), 'Linux rootfs entered the iOS bundle'
    root = Path(__file__).resolve().parents[1]
    for name in ['probe.cjs', 'meta-probe.mjs', 'requirements.json']:
        assert (app / name).read_bytes() == (root / 'runtime/ios' / name).read_bytes(), name
    deps = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    assert 'NodeMobile' in deps or node.exists()
    result = dict(bundle=info['CFBundleIdentifier'], target='iOS Simulator' if args.simulator else 'iOS device',
                  nodeFrameworkSha256=hashlib.sha256(node.read_bytes()).hexdigest(),
                  platforms=info['CFBundleSupportedPlatforms'], devices=info['UIDeviceFamily'],
                  embeddedRuntime=True, dshBootVerified=False, signedForDevice=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
