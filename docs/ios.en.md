# On-device engine adaptation for iPhone and iPad

[简体中文](ios.md)

This branch targets iOS phones and tablets, not a macOS desktop app. Android stays on `main`; iOS development is isolated on `feat/ios-local-engine`.

## Current stage

On iPhone and iPad, open the native channel setup, then the bundled official chat, sidebar, model selector and approval UI. Choose a DeepSeek or OpenAI Chat compatible HTTPS endpoint, model ID and key. DSH's AgentLoop and SQLite run in the app process. Model inference uses the configured API; DSH needs no computer, remote engine or localhost bridge.

- Runner targets both iPhone and iPad, minimum iOS 16.
- `node_start()` runs inside an application-owned thread. It does not unpack Ubuntu, execute Linux binaries, use Root/PRoot, or depend on an external computer.
- The iOS landing page checks local capabilities. It does not restore a computer destination or invoke Android runtime installation.
- The probe checks private-directory read/write, ICU/Intl, builtin module loading, SQLite/FTS5 and ESM metadata, reporting actual versions and results.
- A reviewed pure-JS Loader closure from the official lock plus an App-owned test plugin verifies actual service activation, a private-file challenge, disposal and rejected startup. These checks are separate from Node capabilities. This minimal tree does not mount an Agent, model or conversation UI.
- A separate core tree mounts the actual Session, projections, Prompt, Tools, LLM, Agent and AgentLoop. Only the external model endpoint is replaced with an explicitly labeled offline fixture. Checks cover streamed deltas, second-turn history, cancellation, recovery after a model error, disposal, and missing-service rejection. It makes no live model requests, mounts no persistence, and is not a user chat entry point.
- Another tree mounts an App-owned SQLite backend through the official SessionPersistence contract and the official checkpoint policy. It verifies durable writes, same-session writer exclusion, independent reads, atomic rejection of invalid batches, rejection of damaged logs, and recovery of conversation history after closing and recreating DSH. This uses temporary files and an offline test model, not an app-kill recovery test.
- Diagnostics and chat have separate status. Diagnostic `engineReady: false` does not indicate chat availability. Chat reports its own startup, streaming, cancellation and failure.
- Swift and Node exchange bounded, atomically published requests in the app's private directory without opening a port. The API key is briefly held in a mode-`0600`, backup-excluded start request, unlinked before dispatch. It is not saved in chat history or preferences; stopping releases the runtime's key reference.
- The official sidebar lists sessions by workspace. History lives in the app's private SQLite database. The old interim page uses a separate store; this build does not migrate its sessions.
- iOS may suspend background applications. Continuous background execution is not claimed.

## Runtime provenance

The checked-in `@deepseek-ai/dsh@0.2.2-rc.3` lock requires Node `>=24.9.0`. The main Node.js Mobile project's prebuilt 18.20.4 release does not meet that requirement. This branch pins [fogtape's full Node.js Mobile 24.22.1 framework](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0), including device arm64 and Simulator arm64 slices.

[requirements.json](../runtime/ios/requirements.json) records the exact URL, size, SHA-256 and source/recipe commits. Preparation verifies the archive before inspecting extraction paths, framework slices and the entry API. Framework binaries remain in an ignored Vendor directory, outside Git. The probe writes only to its supplied private report path.

This is a third-party mobile port, not an Apple or official Node.js iOS distribution. Pinning and probe success do not verify all DSH modules. The framework's complete Node and third-party notices are pinned in [NodeMobile-LICENSE.txt](../runtime/ios/NodeMobile-LICENSE.txt) and bundled with the App; sourced from its [LICENSE](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE).

## Build directly on GitHub

The [iOS workflow](../.github/workflows/ios.yml) runs on branch pushes and manual dispatch:

1. Verify dependency requirements and runtime integrity.
2. Generate bilingual localization and run Python, Node and Flutter regressions on GitHub.
3. Verify the Loader, AgentLoop, SQLite persistence and local chat on Ubuntu, then pass the same run's four reviewed bundles to Xcode. XCTest runs the Swift mailbox, actual DSH and official model adapter inside the iOS Simulator application process. It substitutes only the outbound fetch response with test SSE, without calling DeepSeek, and checks streaming, cancellation, history after restart, and auth errors.
4. Build an unsigned iPhone/iPad Release application and verify its platform, device families, framework and probe resources.
5. The `ios-build-and-probe` artifact preserves build verification, separate engine and WebKit XCTest results, the unsigned device app, and a commit-named `*-unsigned.ipa` with its SHA-256 checksum. The unsigned development package follows device bundle validation; build-info.txt separately records the simulator and widget gates. A failed gate is not release acceptance.

The macOS runner supplies Xcode; the product target remains iOS. The unsigned IPA is a device package, not directly installable. Device installation requires Apple signing and suitable provisioning. Simulator success is not physical iPhone acceptance.

## Supported scope

- The first official UI version is text-first with workspace list, read and exclusive file creation after one-time approval. File uploads, image attachments, third-party plugins and desktop credential management are excluded. API keys are entered natively.
- [The first green official UI build (`46f70b0`)](https://github.com/wanan8396/deepseek-harness-app/actions/runs/44298142976) passed the iPhone 16 Pro (iOS 18.5) simulator and iPhone/iPad device bundle gates. The test entry created two SQLite sessions through WebKit, Swift and the in-app official Node Host, observed a title update, and switched between the sessions by clicking the official sidebar. A separate test verified in-app native tools and one-time approval with synthetic HTTPS responses. That does not certify the full production composer and approval UI on a physical device. The device IPA bundles 28 pinned official client modules and excludes XCTest fixtures.
- iOS does not reproduce Android Root/PRoot or Linux. Terminal, shell, desktop native plugins and other apps' files are outside this port's supported capabilities.
- Chat and persistence are checked in Simulator. The paid API has not been checked on a physical device with a live API key. Recovery after force-quitting and continuous background use are not verified.
- Full profile resolution still needs separately adapted internal ESM/CJS access and `node-addon-require-builtin`. The relative-module Loader does not use that path or replace it with a shim. A macOS arm64 addon is not an iOS arm64 addon.

Android's official runtime, signing assets, theme and startup GIF are unchanged.
