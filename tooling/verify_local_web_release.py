#!/usr/bin/env python3
"""Check an actual signed, ARM64, non-debug Lite APK without exposing keys."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import zipfile


def assert_retired_skill_assets_absent(names):
    for skill in ('dsh-app-ui', 'dsh-app-plugin', 'dsh-app-support'):
        prefix = f'assets/flutter_assets/assets/skills/{skill}/'
        assert not any(name == prefix[:-1] or name.startswith(prefix) for name in names), f'Retired native skill assets returned: {skill}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
    tools = sdk / 'build-tools' / '35.0.0'
    aapt = tools / ('aapt2.exe' if os.name == 'nt' else 'aapt2')
    signer = tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    def run(*command):
        return subprocess.run([str(x) for x in command], check=True, capture_output=True,
                              text=True, encoding='utf-8', errors='replace').stdout
    badging = run(aapt, 'dump', 'badging', args.apk)
    manifest = run(aapt, 'dump', 'xmltree', args.apk, '--file', 'AndroidManifest.xml')
    assert "package: name='app.dsh'" in badging, 'Unexpected package'
    version = re.search(r"versionName='([^']+)'", badging).group(1)
    build = int(re.search(r"versionCode='(\d+)'", badging).group(1))
    assert "application-label:'DeepSeek harness'" in badging, 'Unexpected application label'
    assert "native-code: 'arm64-v8a'" in badging, 'Unexpected ABI'
    debug_lines = [line for line in manifest.splitlines() if 'android:debuggable(' in line]
    assert not any('0xffffffff' in line or 'true' in line.lower() for line in debug_lines), 'Debuggable APK'
    removed = ['PhoneA11yService', 'PhoneSelfCheckTargetActivity', 'ShizukuProvider',
               'CompanionWidgetProvider', 'PetOverlayService', 'android.permission.SYSTEM_ALERT_WINDOW',
               'android.permission.WRITE_SECURE_SETTINGS', 'moe.shizuku.manager.permission.API_V23']
    assert not any(item in manifest for item in removed), 'Removed component returned'
    assets = ['assets/web/dsh_web_phone.css', 'assets/web/dsh_web_phone.js', 'assets/web/dsh_web_modal.js',
              'assets/web/dsh_web_appearance.js', 'assets/web/dsh_web_header.js',
              'assets/web/dsh_web_sidebar.js', 'assets/branding/whale.png', 'assets/branding/wordmark.png',
              'assets/branding/startup-cover.gif']
    hashes = {}
    with zipfile.ZipFile(args.apk) as archive:
        names = set(archive.namelist())
        assert_retired_skill_assets_absent(names)
        assert 'lib/arm64-v8a/libapp.so' in names, 'Release AOT application library missing'
        assert 'assets/flutter_assets/kernel_blob.bin' not in names, 'Debug Dart kernel present'
        dex = b''.join(archive.read(name) for name in names if re.fullmatch(r'classes\d*\.dex', name))
        for entry in ('RootLaunchMain', 'RootNamespaceMain'):
            descriptor = ('Lapp/dsh/rootruntime/' + entry + ';').encode()
            assert descriptor in dex, f'Root runtime entry stripped: {entry}'
        assert b'Lapp/dsh/rootbridge/RootExecMain;' not in dex, 'Obsolete manual Root bridge remained'
        assert 'assets/flutter_assets/assets/engine/root/android-root.mjs' not in names, 'Obsolete Root CLI remained'
        assert not any(name.startswith('assets/flutter_assets/assets/engine/lite-bridge/') for name in names), 'Retired Lite bridge assets returned'
        assert b'Lapp/dsh/runtime/LiteBridgeGuest;' not in dex, 'Retired Lite bridge loader returned'
        assert not any(name.startswith('assets/flutter_assets/assets/engine/auth/') for name in names), 'Retired auth bridge assets returned'
        for retired in ('SessionSearchGuest', 'AppAuthGuest', 'SpeechGuest'):
            assert ('Lapp/dsh/runtime/' + retired + ';').encode() not in dex, f'Retired adapter returned: {retired}'
        runtime = json.loads(archive.read('assets/runtime/manifest.json'))
        assert runtime.get('engineDistribution') == 'official-unmodified', 'Lite APK is not using the official distribution'
        capabilities = runtime.get('capabilities', {})
        assert capabilities.get('legacyBridge') is False and capabilities.get('enginePatches') is False, 'Legacy engine capabilities returned'
        assert version == runtime['dshVersion'], 'Version differs from bundled DSH'
        rootfs_entry = 'assets/runtime/' + runtime['rootfs']
        assert rootfs_entry in names, 'Packaged runtime asset name differs from manifest'
        assert archive.getinfo(rootfs_entry).file_size == runtime['rootfsBytes'], 'Packaged runtime asset size differs from manifest'
        with archive.open(rootfs_entry) as payload:
            assert hashlib.file_digest(payload, 'sha256').hexdigest() == runtime['rootfsSha256'], 'Packaged runtime digest differs from manifest'
        for asset in assets:
            blob = archive.read('assets/flutter_assets/' + asset)
            assert blob == (root / 'app' / asset).read_bytes(), f'Stale asset: {asset}'
            hashes[asset] = hashlib.sha256(blob).hexdigest()
        guide_dir = 'assets/skills/dsh-app-guide/'
        guide_manifest = json.loads(archive.read('assets/flutter_assets/' + guide_dir + 'manifest.json'))
        assert guide_manifest['dshVersion'] == runtime['dshVersion'], 'Bundled user guide version is stale'
        for asset in ['manifest.json', *guide_manifest['files']]:
            name = guide_dir + asset
            assert archive.read('assets/flutter_assets/' + name) == (root / 'app' / name).read_bytes(), f'Stale guide: {asset}'
    signature = run(signer, 'verify', '--verbose', '--print-certs', args.apk)
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
    assert 'CN=Android Debug' not in signature, 'Debug signing certificate used'
    certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)', signature).group(1)
    result = dict(package='app.dsh', name='DeepSeek harness', version=version, versionCode=build,
                  buildType='release', debuggable=False, abi='arm64-v8a', dartAot=True,
                  bytes=args.apk.stat().st_size, sha256=hashlib.sha256(args.apk.read_bytes()).hexdigest(),
                  signingCertificateSha256=certificate, signatureVerified=True,
                  removedComponentsAbsent=True, rootRuntimeEntriesPresent=True, assets=hashes)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
