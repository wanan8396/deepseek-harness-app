# Development and validation

[中文](CONTRIBUTING.md) · [Project overview](README.en.md) · [Actual functionality](PROJECT.md) · [Architecture](docs/architecture.md)

## Current development target

Before installing, reusing or cleaning dependencies, read the shared [dependency and tool directory policy](DEPENDENCIES.md). Executors and subagents use its path categories and reuse existing tools rather than placing new dependencies in Desktop DSH or user-data directories.

The product is a single Android phone shell: Flutter owns startup, connections and permissions, while the official `@deepseek-ai/dsh@0.2.2-rc.3` webpage owns conversations and settings. Every local start checks for real UID 0, preferring Root when launch requirements pass and falling back to PRoot otherwise. There is no user-selectable Root switch.

The local webpage connection uses [`dsh_client`](packages/dsh_client/README.md) for lightweight HTTP/RPC/mux access and read-only session/workspace data. Read [PROJECT.md](PROJECT.md) and [architecture](docs/architecture.md), then scope changes using the actual call paths.

## Toolchain and build

- Use the Flutter version in the [existing CI configuration](.github/workflows/ci.yml), currently `3.47.7`; Dart must satisfy the [App SDK constraint](app/pubspec.yaml), `^3.13.5`.
- Android requires JDK 17 and Android SDK/NDK. Match the runtime ABI to the APK flavor.
- Build tooling requires Python 3 and Pillow. Web checks require Node.js; existing CI uses `24.22.1`.
- Prepare a separate, verifiable payload using the [official-runtime instructions](runtime/README.official.md). Do not use the installed phone environment as a build seed.

Build the Android app from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

Linux:

```bash
python3 tooling/make_local_web_brand.py
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
bash tooling/build-local-web-apk.sh -f arm64
```

These entry points build the same Android phone shell and verify that its runtime is an official, unmodified distribution. The display version comes from runtime `dshVersion`; build numbers increase independently. Keep signing configuration and private keys local. Updates must retain the package ID and certificate. Installing a debug build over an existing release is not the default development workflow. See the [build guide](docs/local-web.en.md#build) for parameters and signing requirements.

## Change conventions

- Solve one independently verifiable problem per change. Explain the old behavior, trigger and resulting behavior; avoid unrelated renames, formatting or dependency upgrades.
- Preserve the existing webpage theme and original startup animation. Layout fixes should target relevant positioning, dimensions or input behavior.
- Keep the [Chinese and English ARB inputs](app/lib/l10n/parts/) and bilingual documentation synchronized. Regenerate outputs from their source inputs.
- For runtime, platform-channel or still-consumed protocol changes, check producers, consumers, failure paths and compatibility. Establish references and side effects before deleting retired code.
- Keep credentials, login state, real conversations, device identifiers, private operations material and build caches out of changes. Review diagnostic files, screenshots and logs manually before sharing.
- Record the source project, version or commit, source files and license for new or adapted third-party content. Preserve required attribution, license text and modification notices; moving a directory does not change its license.

## Common checks

Run these commands from the repository root, selecting those relevant to the change. Record actual commands, results, skips and unverified areas. Distinguish static checks, desktop regressions, APK inspection and device acceptance.

**Documentation only:** check bilingual content, links and source references, then run:

```bash
git diff --check
```

**Flutter and Android shell regressions:** install the real test fonts and point `DSH_TEST_FONT_DIR` at the Noto CJK Light/Regular/Bold TTC directory. See the [existing CI](.github/workflows/ci.yml) for font setup.

```bash
(cd app && flutter pub get --enforce-lockfile && flutter analyze --no-pub)
(cd app && flutter test --no-pub test/local_web_lite)
```

**Desktop regressions for the runtime builder, networking and APK verifier:**

```bash
python3 tooling/test_local_web_runtime.py -v
python3 tooling/test_local_web_network.py -v
python3 tooling/test_verify_local_web_release.py -v
python3 -m unittest discover -s runtime/tests -p test_official_runtime.py
python3 -m unittest discover -s runtime/tests -p test_runtime_artifacts.py
```

**Android native unit tests:** after preparing the Flutter/Android toolchain and local configuration, use the Gradle task from the [existing CI](.github/workflows/ci.yml):

```bash
(cd app/android && gradle --stacktrace :app:testArm64DebugUnitTest)
```

**Actual payload and release APK:** require real runtime assets. APK inspection also needs Android SDK build-tools `35.0.0` and `ANDROID_HOME` or `ANDROID_SDK_ROOT`.

```bash
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
python3 tooling/verify_local_web_release.py dist/deepseek-harness-local-0.2.2-rc.3-release.apk --output dist/release-verification.json
```

For web layout changes, select the [header](tooling/test_web_header_layout.mjs), [dialog](tooling/test_web_dialog_layout.mjs) or [settings-menu](tooling/test_web_settings_menu_layout.mjs) regression. First prepare the extracted official rc.2 packages, browser and dedicated port expected by that script. These are local synthetic DOM/input checks, not phone-WebView acceptance or persistence checks against real account settings.

**Localization and bundled user guide:** edit source inputs, regenerate, then run the read-only checks:

```bash
python3 app/tool/l10n_merge.py
python3 app/tool/l10n_merge.py --check
python3 app/tool/guide_sync.py
python3 app/tool/guide_sync.py --check
```

## Retained lightweight client module

The Android shell's local webpage connection uses [`dsh_client`](packages/dsh_client/README.md). When changing this package, follow its README for static analysis and fixture checks. It has no checked-in lockfile, so do not run `pub get --enforce-lockfile`. See the preceding section for bundled-guide synchronization checks.

## Device acceptance and delivery record

For local startup, Root/PRoot, permissions, WebView or update-install changes, record the ABI, Android version, device, package version and actual launch path. Check first connection, installation/upgrade, automatic local startup, computer URLs/QR/PIN login, connection history, menus/keyboard/settings, backgrounding versus a real exit, and both Root and PRoot paths. Use a test package with a matching certificate and preserve existing data. Desktop or CI passes do not establish phone behavior.

Deliver the problem and change scope, source evidence, actual check results and remaining work, with interface evidence according to verification needs. Keep unverified defects, including the New conversation navigation failure, unverified. CI checks do not replace Android phone-shell device acceptance; record them separately.

Issue reports should include minimal repeatable steps, App/Android versions, connection type and redacted evidence. Follow [SECURITY.en.md](SECURITY.en.md) for private reports. Production deployment, real accounts and online checks for companion services are not routine local validation.
