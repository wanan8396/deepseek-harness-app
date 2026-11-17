# iOS embedded Node inputs and acceptance phases

These are first-stage inputs for a **real in-process Node engine on iPhone/iPad**, not a Mac executable or a remote engine client. `probeReady` means only that the Node probe completed. `runtimeCompatible` means only that its current version/API conditions passed, **not that DSH started**. The probe always reports `engineReady: false`.

[中文](README.md)

## Pinned provenance

- Provider: third-party `fogtape/nodejs-mobile`, not an official Node.js iOS distribution or a new official `nodejs-mobile/nodejs-mobile` release.
- Full variant: [`v24.22.1-0`](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0), Node `24.22.1`. Do not select lite, which omits SQLite/SEA.
- [Archive](https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-ios-24.22.1-0.zip): 62,732,962 bytes; SHA256 `3fa1b8fb0720768b01c2e0dae3a17e788476e8c1613a1d9a54e206793b45326e`.
- [Pinned source](https://github.com/fogtape/nodejs-mobile/tree/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5); [recipe commit](https://github.com/fogtape/nodejs-mobile/commit/d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5); [MIT and dependency notices](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/LICENSE). The archive does not contain the complete LICENSE. Its full text is pinned as [NodeMobile-LICENSE.txt](NodeMobile-LICENSE.txt) and copied into App resources by the preparer; the link does not substitute for the distributed notices.
- The actual `NodeMobile.xcframework` contains dynamic frameworks: `ios-arm64` and `ios-arm64-simulator`, both minimum iOS 14.0. There is no Intel/x86_64 simulator slice.
- The [public header](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/tools/ios-framework/NodeMobile/NodeMobile.h) exposes only `int node_start(int argc, char *argv[])`. The [build recipe](https://github.com/fogtape/nodejs-mobile/blob/b5bcc8d8e70f055333cd5efc317e3eb55bf0c9a5/tools/ios_framework_prepare.sh) uses jitless V8 and full ICU, retains SQLite, and bundles polywasm for undici/fetch. Recipe declarations are not this project's device verification.

## Preparation and CI

No toolchains are installed. Builds and tests run through GitHub Actions; local work in this stage only verified public archive hashes, headers, and Mach-O metadata.

```sh
python3 tooling/prepare_ios_runtime.py --check
python3 tooling/test_prepare_ios_runtime.py
node --test runtime/ios/probe.test.cjs
python3 tooling/prepare_ios_runtime.py --download
# Existing archives: --download --archive /path/to/nodejs-mobile-ios-24.22.1-0.zip
```

`--check` only reads and compares `requirements.json` with `engines.node` in the official rc.3 lock. `--download` pins the URL, size and hash, installs the unique actual framework root at `app/ios/EmbeddedNode/Vendor/NodeMobile.xcframework`, and copies the probe, ESM probe, and requirements to `app/ios/EmbeddedNode/Resources`. Its default cache is `runtime/.cache/ios`. Cache, Vendor, and generated Resources must stay out of Git.

Before extraction, the preparer validates every ZIP member and rejects traversal, absolute/Windows paths, duplicate paths, symlinks, special files, and excessive expansion. It then validates slices, the C API and arm64 MH_DYLIB. Existing Vendor contents must match the verified archive byte for byte; differences fail rather than being silently overwritten.

## Native runner contract

Call `node_start` once on a dedicated background thread with `node`, the actual absolute bundled `probe.cjs` path, and an absolute report path in an **App-private directory whose parent already exists**. Keep `char **argv` memory alive until the call returns; the call occupies its thread. The runtime supports one instance per App process. Do not pretend it supports stopping and restarting in the same process.

The probe writes a random same-directory temporary file (0600), then publishes complete JSON using rename. It emits no environment, user configuration, tokens, or raw errors; failures contain machine codes only. A timer holds the event loop without calling `process.exit`. Native code uses the JSON `phase` and `schemaVersion` to detect completion. Errors and timeouts stay errors; framework presence, a Node version, or generated test reports do not establish DSH readiness.

Observed checks: Node/V8/ABI/N-API/platform/arch, the version floor, private-directory file round-trip, `process.getBuiltinModule`, in-memory `node:sqlite` and FTS5, Intl, and actual local ESM `import.meta.main/filename/dirname`. Requested jitless arguments, recipe expectations, and runtime state not independently proven are recorded separately.

## DSH gates still open

1. The official DSH rc.3 lock requires `>=24.9.0`. Node24.22.1 clears the version gate, not the whole dependency graph.
2. Profile resolution in `dsh-app-boot` directly depends on `node-addon-require-builtin` and five internal loader modules. A Linux ARM64/glibc or Mac darwin-arm64 addon is not an iOS addon.
3. The CLI and `runProfile` contain host-process exit paths. Calling them directly affects the entire App. Next, validate the actual Loader using `dsh-app-boot.boot(...)` and a relative-module tiny profile, then implement an App-owned controlled profile lifecycle.
4. The full web profile, HTTP/RPC, actual session persistence, model calls, native tools, background/lock/memory-pressure handling, and physical devices each require separate evidence. There is no established reuse percentage or small fixed native-module count.
