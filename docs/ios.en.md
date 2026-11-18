# On-device engine adaptation for iPhone and iPad

[简体中文](ios.md)

This branch targets iOS phones and tablets, not a macOS desktop app. Android stays on `main`; iOS development is isolated on `feat/ios-local-engine`.

## Current stage

On iPhone and iPad, open the interim **On-device chat** screen and use the official DeepSeek endpoint or set a custom DeepSeek / OpenAI-compatible HTTPS endpoint, model ID and key. DSH's AgentLoop and SQLite run in the app process. Model inference uses the configured API and requires no computer, remote DSH or localhost bridge.

- Runner targets both iPhone and iPad, minimum iOS 16.
- `node_start()` runs inside an application-owned thread. It does not unpack Ubuntu, execute Linux binaries, use Root/PRoot, or depend on an external computer.
- The iOS landing page checks local capabilities. It does not restore a computer destination or invoke Android runtime installation.
- The probe checks private-directory read/write, ICU/Intl, builtin module loading, SQLite/FTS5 and ESM metadata, reporting actual versions and results.
- A reviewed pure-JS Loader closure from the official lock plus an App-owned test plugin verifies actual service activation, a private-file challenge, disposal and rejected startup. These checks are separate from Node capabilities. This minimal tree does not mount an Agent, model or conversation UI.
- A separate core tree mounts the actual Session, projections, Prompt, Tools, LLM, Agent and AgentLoop. Only the external model endpoint is replaced with an explicitly labeled offline fixture. Checks cover streamed deltas, second-turn history, cancellation, recovery after a model error, disposal, and missing-service rejection. It makes no live model requests, mounts no persistence, and is not a user chat entry point.
- Another tree mounts an App-owned SQLite backend through the official SessionPersistence contract and the official checkpoint policy. It verifies durable writes, same-session writer exclusion, independent reads, atomic rejection of invalid batches, rejection of damaged logs, and recovery of conversation history after closing and recreating DSH. This uses temporary files and an offline test model, not an app-kill recovery test.
- Diagnostics and chat have separate status. Diagnostic `engineReady: false` does not indicate chat availability. Chat reports its own startup, streaming, cancellation and failure.
- Swift and Node exchange bounded, atomically published requests in the app's private directory without opening a port. The API key is briefly held in a mode-`0600`, backup-excluded start request, unlinked before dispatch. It is not saved in chat history or preferences; stopping releases the runtime's key reference.
- History is stored in the app's private SQLite database and reopened when starting again. The UI shows recent messages; older history remains available to the model context.
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
5. Preserve build verification, XCTest results and the unsigned device application.

The macOS runner supplies Xcode; the product target remains iOS. An unsigned application is not an installable IPA. Device installation requires Apple development signing and suitable provisioning. Simulator success is not physical iPhone acceptance.

## Supported scope

- The interim product UI supports one text conversation and can list, read and create text files in the app's private workspace. Creating a file requires one-time user approval before writing.
- The official WebKit assets and session API have separate tests. Multiple sessions in a test page do not make them available in the released app. The official chat, sidebar, model settings, attachments and third-party plugins are not attached to the production entry point.
- iOS does not reproduce Android Root/PRoot or Linux. Terminal, shell, desktop native plugins and other apps' files are outside this port's supported capabilities.
- Chat and persistence are checked in Simulator. The paid API has not been checked on a physical device with a live API key. Recovery after force-quitting and continuous background use are not verified.
- Full profile resolution still needs separately adapted internal ESM/CJS access and `node-addon-require-builtin`. The relative-module Loader does not use that path or replace it with a shim. A macOS arm64 addon is not an iOS arm64 addon.

Android's official runtime, signing assets, theme and startup GIF are unchanged.
