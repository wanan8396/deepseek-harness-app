# On-device engine adaptation for iPhone and iPad

[简体中文](ios.md)

This branch targets iOS phones and tablets, not a macOS desktop app. Android stays on `main`; iOS development is isolated on `feat/ios-local-engine`.

## Current stage

Stage one adds the iOS project, an embedded Node framework, and a real JavaScript capability probe. **A successful probe is not a DSH engine boot. Full on-device DSH conversations on iOS are not implemented yet.**

- Runner targets both iPhone and iPad, minimum iOS 16.
- `node_start()` runs inside an application-owned thread. It does not unpack Ubuntu, execute Linux binaries, use Root/PRoot, or depend on an external computer.
- The iOS landing page checks local capabilities. It does not restore a computer destination or invoke Android runtime installation.
- The probe checks private-directory read/write, ICU/Intl, builtin module loading, SQLite/FTS5 and ESM metadata, reporting actual versions and results.
- `engineReady` remains false. Missing resources, timeouts and invalid responses are explicit failures, not fabricated URLs or login tokens.
- iOS may suspend background applications. Continuous background execution is not claimed.

## Runtime provenance

The checked-in `@deepseek-ai/dsh@0.2.2-rc.3` lock requires Node `>=24.9.0`. The main Node.js Mobile project's prebuilt 18.20.4 release does not meet that requirement. This branch pins [fogtape's full Node.js Mobile 24.22.1 framework](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0), including device arm64 and Simulator arm64 slices.

[requirements.json](../runtime/ios/requirements.json) records the exact URL, size, SHA-256 and source/recipe commits. Preparation verifies the archive before inspecting extraction paths, framework slices and the entry API. Framework binaries remain in an ignored Vendor directory, outside Git. The probe writes only to its supplied private report path.

This is a third-party mobile port, not an Apple or official Node.js iOS distribution. Pinning and probe success do not verify all DSH modules. The framework's complete Node and third-party notices are pinned in [NodeMobile-LICENSE.txt](../runtime/ios/NodeMobile-LICENSE.txt) and bundled with the App; sourced from its [LICENSE](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE).

## Build directly on GitHub

The [iOS workflow](../.github/workflows/ios.yml) runs on branch pushes and manual dispatch:

1. Verify dependency requirements and runtime integrity.
2. Generate bilingual localization and run Python, Node and Flutter regressions on GitHub.
3. Build an iOS Simulator application, then use XCTest to execute embedded Node inside the simulator application process.
4. Build an unsigned iPhone/iPad Release application and verify its platform, device families, framework and probe resources.
5. Preserve build verification, XCTest results and the unsigned device application.

The macOS runner supplies Xcode; the product target remains iOS. An unsigned application is not an installable IPA. Device installation requires Apple development signing and suitable provisioning. Simulator success is not physical iPhone acceptance.

## Gates before full engine readiness

The probe is not a finished chat product. Remaining work includes:

- An iOS-compatible `node-addon-require-builtin` and internal ESM/CJS access used by `dsh-app-boot`; a macOS arm64 addon is not an iOS arm64 addon.
- App-sandbox storage for sessions/workspaces, and compatible filesystem, image and native-extension dependencies.
- Replacing or disabling plugins that require subprocesses, terminals, OS shells or dynamic tool installation, with an explicit supported feature inventory.
- Independently verifying profile startup, authentication, web/API transport, streamed conversations, approvals, persistence and background/foreground lifecycle.
- A zero-TCP in-process transport would require separate complete request and streaming adaptation; it is not implemented by this stage.

Android's official runtime, signing assets, theme and startup GIF are unchanged.
