# DeepSeek Harness · Android App

[简体中文](local-web.md)

- Package: `app.dsh`
- App name: DeepSeek harness
- Display version: the bundled runtime's `dshVersion`, such as `0.2.2-rc.5`; the Android build number remains monotonically increasing.
- Repository: [wanan8396/deepseek-harness-source](https://github.com/wanan8396/deepseek-harness-source) (private). See [attribution and licenses](ATTRIBUTION.en.md) for source authorship.

> This page covers the interface and local startup. Every local start in the current source checks for real UID 0, preferring Root when launch requirements pass and falling back to PRoot otherwise; there is no manual Root selection. Each Release's notes and attachments define its shipped features.

## Local or computer webpage

**Local:** run bundled Ubuntu, Node.js and DSH on the phone, automatically checking Root at startup and using it only with real UID 0 and suitable conditions, otherwise falling back to PRoot, and display the engine's original web UI. Entering local mode starts the engine. Finishing the app from its root page or removing its task stops it; ordinary backgrounding, screen locking and rotation do not. Model settings and ordinary tool approvals stay in the webpage. Local execution does not imply offline model inference.

**Computer:** enter an HTTP(S) address or scan a computer LAN QR code, review the origin, and connect. The verified `@neil-yu/dsh-remote-access@0.1.3` plugin encodes a plain HTTP URL. Its PIN is entered in the webpage, with website cookies handling login; the app does not collect or display PINs.

History retains host/name/last-used time. Preference URLs omit query and fragment; complete login URLs, when needed, use the app's secret store rather than lists or logs. Computer pages do not read or overwrite local phone conversation identities. Switching back restores the local webpage.

## Phone interface

- One bottom-left whale directly toggles the webpage's conversations/workspaces sidebar. There is no extra menu or native app-settings entry. A reserved 48dp footer protects the composer and hides for the keyboard or web dialogs.
- The bottom-right local/computer selector is the only additional native entry. It offers just those two destinations; the computer page retains manual URLs, QR and history. Theme, language, model and other settings remain in the original webpage.
- Phone web layout is enabled by default without a duplicate switch. Session breadcrumbs, subagent/background-task status, utilities and the right-panel button stay on one touch-scrollable horizontal row. Utility frames fit their 40dp touch targets without clipping. Header dropdowns position independently in the viewport, outside the scrolling row's clip. Right-panel browser tabs and their close targets share a 40px centre line and reserve separate title space.
- Normal startup and initial web loading show the original 40-frame GIF and “探索未至之境”, without loading text or a progress bar. First-run permissions retain the existing theme and crisp wordmark. First-run permissions are listed on one page with real status and one explicit enable button per item, plus Continue. Continuing without grants remains possible; returning only refreshes status and never opens the next prompt automatically.
- Native connection routes use the bundled webpage's actual panel, label, border, selected-item and primary-button colors. They and the bottom whale follow the active webpage's light/dark appearance without a duplicate theme preference.
- Web settings use the system-safe viewport without duplicate native control reserves. Visible web dialogs temporarily hide native floating controls, restoring them on close. Long welcome text scrolls independently of the checkbox and confirmation area.
- Computer mode does not construct local setup or read the local runtime provider. Explicit HTTP LAN URLs work in the current shell's network configuration; HTTPS retains platform certificate validation.
- Initial file/notification/background permissions may be skipped. Root is checked automatically at each local start, with no Root switch on the permission page, as described below. Camera permission is requested for an explicit scan. Missing permissions are explained at the operation, not scattered across settings switches. Files, notifications and system battery exemption use actual readings. Vendor switches without a read API offer View settings and I've enabled it; an explicit confirmation is shown separately from system-detected grants. Opening or returning from settings alone is not treated as a grant.
- The local engine uses official `@deepseek-ai/dsh@0.2.2-rc.5`; web, plugin and session APIs use the official implementation.

This is the repository's only Android shell product; no product-mode define is required.

## Default Root startup and PRoot fallback

> Root/PRoot is determined automatically on each local start, not by a user-selectable switch. A given APK's features are defined by that Release's notes.

The permission page offers files, notifications and background access, with **no manual Root controls**.

- Each local-engine start checks real Android Root once. Verified UID 0 and suitable platform conditions select Root; denial, timeout or unsupported devices fall back to PRoot.
- The Root manager may prompt on the first check. Opening permissions, resuming the app or reading status does not repeat detection. Old saved Root switches do not gate the check.
- Root starts Ubuntu/Node/DSH as real Root in a private mount namespace/chroot, without PRoot or a PID-namespace requirement. Ordinary command tools run directly without an extra manual bridge command.
- Ubuntu paths and software remain available. Scripts under mounted Android paths can be executed with `/system/bin/sh /actual/path/script.sh`; interpreters and libraries still need to match the Android or Ubuntu environment.
- Root can change system files. Web tool approval settings are unchanged, and this does not restore accessibility or the phone-control MCP.
- Root/PRoot mode stays fixed while running and is checked again at the next local start. Home, lock and rotation keep the engine; a real exit reaps the owned Root namespace and processes.
- On Root exit, ownership repair is limited to files and directories inside the App-private physical rootfs whose owner is not the App UID. Modes are preserved, external mounts and symlinks are not followed, and hardlinks are processed only when all links are contained in that rootfs. Interrupted cleanup keeps data and reports an explicit error; PRoot fallback waits for repair instead of continuing with incompatible ownership.

Platform support and real operation require target-device verification. Desktop tests do not replace Root/PRoot device acceptance.

## Build

Prepare the real ABI payload using the [official runtime build instructions](../runtime/README.official.md). The current shell requires explicit official-distribution metadata with the legacy bridge and patch capabilities disabled. Missing, legacy or corrupt runtime assets stop preflight instead of producing an engine-less shell.

Windows, with Flutter/JDK/Android SDK+NDK and Python/Pillow available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

The script regenerates brand assets, verifies the official runtime and uses an ASCII build alias for non-ASCII paths. Kotlin incremental compilation is disabled for cross-drive Windows compatibility. Options include `-PythonPath`, `-BuildRoot`, `-Mode release` and `-BuildNumber`.

Release builds require a local `app/android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`; the store path is relative to `app/android/app`. Both configuration and private keystores are excluded from Git, and missing release signing stops the build. Keep the same release key for future upgrades. Older debug test builds use another certificate; this process does not uninstall them or erase their data.

Run `python tooling/verify_local_web_release.py dist/deepseek-harness-local-0.2.2-rc.5-release.apk --output dist/release-verification.json` to check non-debuggable ARM64 AOT output, the release certificate and bundled assets.

Linux:

```bash
# Build the official payload per runtime/README.official.md into runtime/out/arm64-v8a/ first.
python3 tooling/make_local_web_brand.py
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
bash tooling/build-local-web-apk.sh -f arm64
```

Version defaults to runtime `dshVersion`. Flutter's APK output remains unchanged; the Windows script also copies the deliverable to `dist/`. Regenerate derived assets from inputs rather than editing them manually.

## Validate

```bash
cd app
# DSH_TEST_FONT_DIR points to real Noto CJK Light/Regular/Bold TTC files.
flutter test test/local_web_lite
cd ..
python3 tooling/test_local_web_runtime.py -v
python3 tooling/check_local_web_runtime.py --flavor arm64 --official
```

Inspect final package/version/signature/runtime assets and merged manifest. Device acceptance covers first connection/permissions, QR/manual URL, PIN login, restored history, local runtime install/start/exit-stop, bottom controls, keyboard and settings. Keep desktop, browser and device evidence separate.

## Attribution

See [attribution and licenses](ATTRIBUTION.en.md) for source authorship and modifications. [AGPL-3.0](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md) and [asset terms](../ASSETS.md) are retained, alongside separate branding inputs/provenance. Downloads and feedback point to the current private maintenance repository.
