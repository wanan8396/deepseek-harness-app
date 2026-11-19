# DeepSeek Harness · Android

[简体中文](README.md)

Run DeepSeek Harness on an Android phone or open the DSH webpage already running on your computer. The original webpage owns chat, file and command tools, without duplicate native configuration screens.

- **Application:** DeepSeek harness
- **Package:** `app.dsh`
- **Repository:** [wanan8396/deepseek-harness-source](https://github.com/wanan8396/deepseek-harness-source) (private)
- **Versioning:** the display version follows bundled DSH; Android build numbers increase independently.

## Current source status

The current source uses the official `@deepseek-ai/dsh@0.2.2-rc.5` webpage. Same-certificate ARM64 Release has been built, verified and installed over the previous app, retaining the read-only configuration viewer, private dependency layout, original theme and startup GIF. Focused shell regressions passed 423 tests with 20 skips, and 53 key native tests passed. Full suites still have documented golden-image, icon-role and Windows-filesystem failures; neither full-suite success nor complete device acceptance is claimed. See the [latest cleanup record](docs/maintenance/round23-compatibility-marker-removal.md). The reported New conversation navigation failure has not been reverified and is not marked as fixed. See [PROJECT.md](PROJECT.md) for actual functionality and source entry points.

## Download and install

This new repository currently uploads source only; it does not publish an APK automatically. Future official attachments will appear under [Releases](https://github.com/wanan8396/deepseek-harness-source/releases), with the actual release contents defining availability. Private source and attachments require a GitHub account with repository access.

Release packages use a dedicated signing certificate. Updates must retain the package ID and certificate; older debug packages may have another certificate and cause an update conflict. Do not uninstall an older package when you need to preserve its data.

**Each Release's notes and attachments define its shipped features.** On every local start, the current source checks for real UID 0 and prefers Root when the launch requirements pass, otherwise falling back to PRoot. This is automatic, not a user-selectable mode; the permissions page has no Root switch. See [local and Root startup](docs/local-web.en.md#default-root-startup-and-proot-fallback).

## Two ways to connect

### Local

- Run bundled Ubuntu, Node.js and DSH on the phone and display that engine's webpage.
- Entering local mode starts the engine; a real App exit stops it.
- Backgrounding, screen locking and rotation do not count as an exit.
- Model requests still go to the provider configured in the webpage. A local engine does not imply offline inference.

### Computer webpage

- Enter the computer DSH's HTTP(S) URL or scan its LAN connection QR code.
- Manual URLs, scanning and connection history remain available.
- The destination webpage owns PIN entry and login state; the App does not add another login flow.
- Computer mode does not require the phone's local engine to start first.

## Interface and permissions

- **Bottom-left whale:** opens conversations/workspaces and stays reachable while the sidebar is open; the keyboard and genuinely blocking dialogs can temporarily hide it.
- **Bottom-right Local/Computer:** selects the destination. Model, theme, language and chat settings stay in the webpage.
- The top row supports horizontal touch scrolling; menus open independently and browser-tab close buttons are centred.
- The original webpage theme, looping startup animation and “探索未至之境” tagline are retained.
- New deliverables default to `Download/DeepSeek-harness`; files in historical download folders remain in place and readable.
- Local “Open configuration file” uses an in-App read-only viewer, without exporting or writing the document. Computer mode retains the webpage's original action.
- Extra phone tools, downloads and compilation caches use a private dependency root configured at local startup. The bundled guide and managed instructions describe its layout; existing dependencies remain in place.
- First-run permissions share one page with explicit per-item actions and Continue. Returning only refreshes state, never chains more prompts.
- Files, notifications and battery access use actual readings. Vendor settings offer View settings / I've enabled it, keeping user confirmation distinct from system detection.

See the [detailed guide](docs/local-web.en.md) for current operation, local startup and building.

## Build

Prepare a real matching-ABI runtime, Flutter, JDK, Android SDK/NDK and Python/Pillow, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tooling\build-local-web-apk.ps1 -Mode release
```

Linux entry point:

```sh
bash tooling/build-local-web-apk.sh -f arm64
```

Keep release signing configuration and private keys local and outside Git. See the [build guide](docs/local-web.en.md#build) for toolchains, runtime preparation and signing requirements.

## Documentation and source scope

- [Actual functionality and source entry points](PROJECT.md)
- [Current architecture](docs/architecture.md)
- [Current-edition guide](docs/local-web.en.md)
- [Development and validation](CONTRIBUTING.en.md)
- [Dependency and tool directory policy](DEPENDENCIES.md)
- [Reporting issues](SECURITY.en.md)
- This repository contains current source, build scripts, dependency locks, required assets and licenses. APKs, rootfs/JNI runtime archives, signing keys, device configuration and local plugin backups are excluded. Additional plugins are installed by the destination engine, not bundled in the App.

## Attribution and license

This modified edition is maintained by **wanan8396**. Original authors' copyrights, notices and licenses are preserved. See [attribution](docs/ATTRIBUTION.en.md), [AGPL-3.0](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md) and [asset terms](ASSETS.md). The legacy SDK and examples have been removed; retained third-party content keeps its original licenses.

This is a community modification, not an official DeepSeek release. Names and marks remain the property of their respective owners.
