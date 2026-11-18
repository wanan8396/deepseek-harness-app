#!/usr/bin/env python3
"""Verify a real Xcode/Flutter iOS application without claiming DSH booted."""
import argparse
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path

from ios_engine_pin import validate_lock


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
    engine = validate_lock(root)
    lock_bytes = (root / engine['lockfile']).read_bytes()
    lock_hash = hashlib.sha256(lock_bytes).hexdigest()
    for name in ['probe.cjs', 'meta-probe.mjs', 'requirements.json', 'NodeMobile-LICENSE.txt']:
        assert (app / 'Frameworks/DshEmbeddedNode.framework' / name).read_bytes() == (root / 'runtime/ios' / name).read_bytes(), name
    framework = app / 'Frameworks/DshEmbeddedNode.framework'
    for test_only in ('chat-ci-entry.cjs', 'dsh-official-host-ci', 'official-host-ci-mailbox.mjs', 'dsh-web-shell-preview'):
        assert not any(app.rglob(test_only)), f'CI fixture entered shipped resources: {test_only}'
    assert not any(app.rglob('test-chat.mjs')), 'CI runner entered shipped resources'
    for directory, distribution in [('dsh-loader', 'ios-adapted-loader-probe'),
                                    ('dsh-core', 'ios-adapted-core-probe'),
                                    ('dsh-persistence', 'ios-adapted-persistence-probe'),
                                    ('dsh-chat', 'ios-local-text-chat')]:
        bundle = app / 'Frameworks/DshEmbeddedNode.framework' / directory
        manifest = json.loads((bundle / 'distribution-manifest.json').read_text())
        assert manifest['distribution'] == distribution
        assert manifest['engineVersion'] == engine['version'] and manifest['engineReady'] is False
        assert manifest['sourceLockSHA256'] == lock_hash
        for entry in manifest['files']:
            relative = Path(entry['path'])
            assert not relative.is_absolute() and '..' not in relative.parts
            assert hashlib.sha256((bundle / relative).read_bytes()).hexdigest() == entry['sha256']
    frontend = framework / 'dsh-web-frontend'
    web = json.loads((frontend / 'distribution-manifest.json').read_bytes())
    assert web['package'] == '@deepseek-ai/dsh-web-frontend' and web['version'] == engine['version']
    assert web['sourceLockSHA256'] == lock_hash
    assert web['integrity'] == json.loads(lock_bytes)['packages']['node_modules/@deepseek-ai/dsh-web-frontend']['integrity']
    expected = {'distribution-manifest.json'}
    for entry in web['files']:
        relative = Path(entry['path'])
        assert not relative.is_absolute() and '..' not in relative.parts and entry['path'] not in expected
        item = frontend / relative
        assert item.is_file() and not item.is_symlink() and item.stat().st_size == entry['bytes']
        assert hashlib.sha256(item.read_bytes()).hexdigest() == entry['sha256']
        expected.add(entry['path'])
    assert {file.relative_to(frontend).as_posix() for file in frontend.rglob('*') if file.is_file()} == expected
    bootstrap = framework / 'dsh-web-bootstrap'
    startup = json.loads((bootstrap / 'distribution-manifest.json').read_bytes())
    assert startup['schemaVersion'] == 1 and startup['package'] == '@deepseek-ai/dsh-client-modules'
    assert startup['version'] == web['version'] and startup['sourceLockSHA256'] == web['sourceLockSHA256']
    assert startup['integrity'] == json.loads(lock_bytes)['packages']['node_modules/@deepseek-ai/dsh-client-modules']['integrity']
    assert startup['stockIndexSHA256'] == hashlib.sha256((frontend / 'index.html').read_bytes()).hexdigest()
    assert startup['index']['path'] == 'index.html' and startup['license']['path'] == 'LICENSE'
    assert {entry['path'] for entry in startup['resources']} == {'bootstrap-combo.js', 'bootstrap-entry.js'}
    for entry in [startup['index'], startup['license'], *startup['resources']]:
        item = bootstrap / entry['path']
        assert item.is_file() and not item.is_symlink() and item.stat().st_size == entry['bytes']
        assert hashlib.sha256(item.read_bytes()).hexdigest() == entry['sha256']
    app_runtime = framework / 'dsh-official-app'
    release_host = json.loads((app_runtime / 'distribution-manifest.json').read_bytes())
    assert release_host['phase'] == 'official-app' and release_host['sourceLockSHA256'] == lock_hash
    assert release_host['engineVersion'] == engine['version']
    assert (app_runtime / 'official-app-mailbox.mjs').is_file()
    assert not (app_runtime / 'core-fixture-model.mjs').exists()
    for entry in release_host['files']:
        relative = Path(entry['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        item = app_runtime / relative
        assert item.is_file() and not item.is_symlink() and item.stat().st_size == entry['bytes']
        assert hashlib.sha256(item.read_bytes()).hexdigest() == entry['sha256']
    app_web = framework / 'dsh-official-web'
    release_web = json.loads((app_web / 'distribution-manifest.json').read_bytes())
    assert release_web['sourceLockSHA256'] == lock_hash
    assert release_web['graph']['release']['version'] == engine['version']
    assert len(release_web['graph']['entries']) == 28 and len(release_web['appAssets']) == 1
    assert release_web['stage'] == 'official-shell-preview' and release_web['officialUIReady'] is False
    for entry in [release_web['index'], release_web['license'], *release_web['resources'], *release_web['appAssets']]:
        relative = Path(entry['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        item = app_web / relative
        assert item.is_file() and not item.is_symlink() and item.stat().st_size == entry['bytes']
        assert hashlib.sha256(item.read_bytes()).hexdigest() == entry['sha256']
    assert (framework / 'official-web-bridge.js').read_bytes() == (root / 'runtime/ios/official-web-bridge.js').read_bytes()
    bridge = app / 'Frameworks/DshEmbeddedNode.framework/DshEmbeddedNode'
    assert bridge.is_file(), 'Embedded runtime bridge framework missing'
    deps = subprocess.check_output(['otool', '-L', str(bridge)], text=True)
    assert '@rpath/NodeMobile.framework/NodeMobile' in deps, 'Bridge does not link the embedded runtime'
    result = dict(bundle=info['CFBundleIdentifier'], target='iOS Simulator' if args.simulator else 'iOS device',
                  nodeFrameworkSha256=hashlib.sha256(node.read_bytes()).hexdigest(),
                  platforms=info['CFBundleSupportedPlatforms'], devices=info['UIDeviceFamily'],
                  embeddedRuntime=True, dshBootVerified=False, signedForDevice=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
