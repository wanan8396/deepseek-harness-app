# Local runtime

Selecting This phone starts the bundled official DeepSeek harness runtime and displays its webpage in the app. Follow the installation page on first use. The whale animation appears during startup and the initial webpage load.

## Automatic Root detection and PRoot fallback

- Each normal local-engine start checks real Android Root once. It prefers Root only after verifying UID 0 and the required startup conditions. The permission page has no Root switch or manual grant row. Recovery mode skips the Root probe and uses PRoot.
- The device's Root manager may show a grant request on the first check. Without a grant, available Root or suitable startup conditions, the app automatically uses PRoot. Ordinary use does not require rooting the phone.
- A Linux `root` user or UID 0 shown inside PRoot is simulated; it does not mean Android host Root was granted.
- The selected mode stays fixed while the engine runs. Opening permissions or resuming the app does not repeat detection or switch a running conversation. The next local start checks again.

Root has broader access; still check the target files and actions before running commands. Granting Root does not enable automatic phone tapping. See [System permissions](04-permissions.md).

## Profiles and data

The official engine's HOME/profile holds account settings, providers, plugins and conversation data; workspace files live in their selected directories. Computer mode uses the computer's own HOME/profile and does not automatically synchronize phone records.

An isolated recovery profile differs from the normal profile. If a recovery environment was selected by a page or maintenance procedure, an absent list does not prove that original records were deleted. Return to the normal configuration and check before clearing anything.

## Dependencies, downloads and builds

Local startup prepares `/root/.local/share/deepseek-harness/dependencies` and sets `$DSH_DEPENDENCY_ROOT` inside the phone's Linux environment. Normal and recovery profiles, Root and PRoot share the same persistent private directory; isolated settings do not create a second tool installation. Computer webpages do not use these phone environment variables. This directory explanation adds no buttons.

All subdirectories below are inside `$DSH_DEPENDENCY_ROOT`:

| Subdirectory | Purpose and environment variables |
| --- | --- |
| `bin/` | Manually placed command-line tools |
| `npm/` | Global user Node tools; `NPM_CONFIG_PREFIX` points here, with executables in `npm/bin` |
| `python/` | `PYTHONUSERBASE`; install user packages with `python3 -m pip install --user` |
| `venvs/` | Independent Python environments; prefer venv to avoid conflicts between tools' packages |
| `downloads/` | Downloaded installers and source archives |
| `sources/` | Extracted or checked-out source |
| `build/` | Build outputs and intermediate files |
| `tmp/` | `TMPDIR` temporary files |
| `cache/` | npm: `NPM_CONFIG_CACHE` is `cache/npm`; node-gyp: `NPM_CONFIG_DEVDIR` is `cache/node-gyp`; pip: `PIP_CACHE_DIR` is `cache/pip`; Go: `GOMODCACHE` is `cache/go-mod`, `GOCACHE` is `cache/go-build`; ccache: `CCACHE_DIR` is `cache/ccache` |
| `cargo/` | Rust user tools and dependencies, `CARGO_HOME` |
| `rustup/` | Rust toolchains, `RUSTUP_HOME` |
| `go/` | Go user workspace and tools, `GOPATH` |

These installation, cache and temporary-directory variables are set only for local Linux processes. `bin`, `npm/bin`, `python/bin`, `cargo/bin` and `go/bin` are appended to the end of `PATH`, retaining the original priority of official Node/Python; call independent environments by their full paths. Do not move Ubuntu `/usr`, `dpkg/apt` system dependencies or standard project `node_modules` into this directory, or alter the official engine `/opt/dsh`. Previously installed tools are not moved automatically; place new user tools as described above.

### Four command examples

These examples only show directory usage and are not run automatically. Replace `PACKAGE`, `TOOL_PACKAGE` and `SOURCE_URL` with the required package names or source address. The corresponding tools must already be installed; the source-build example is for a CMake project.

1. Prefer an independent Python environment, then install packages inside it:

```bash
python3 -m venv "$DSH_DEPENDENCY_ROOT/venvs/my-tool"
"$DSH_DEPENDENCY_ROOT/venvs/my-tool/bin/python" -m pip install PACKAGE
```

2. If shared user Python packages are needed, use a user installation:

```bash
PYTHONUSERBASE="$DSH_DEPENDENCY_ROOT/python" python3 -m pip install --user PACKAGE
```

3. Install global user Node tools without writing the official engine directory:

```bash
NPM_CONFIG_PREFIX="$DSH_DEPENDENCY_ROOT/npm" npm install -g TOOL_PACKAGE
```

4. Follow download redirects, specify the filename, and separate source from build output:

```bash
mkdir -p "$DSH_DEPENDENCY_ROOT/downloads" "$DSH_DEPENDENCY_ROOT/sources/my-tool" "$DSH_DEPENDENCY_ROOT/build/my-tool"
curl -L -o "$DSH_DEPENDENCY_ROOT/downloads/my-tool.tar.gz" "$SOURCE_URL"
tar -xzf "$DSH_DEPENDENCY_ROOT/downloads/my-tool.tar.gz" --strip-components=1 -C "$DSH_DEPENDENCY_ROOT/sources/my-tool"
cmake -S "$DSH_DEPENDENCY_ROOT/sources/my-tool" -B "$DSH_DEPENDENCY_ROOT/build/my-tool"
cmake --build "$DSH_DEPENDENCY_ROOT/build/my-tool"
```

Shared storage `Download/DeepSeek-harness` is only for output files such as exports and shares, not dependencies or build environments. External storage may use `noexec` and have incomplete Linux symbolic-link support; keep tools, source and builds in the private directory above.

The dependency root is outside the current 14 engine-upgrade paths, so compatible ordinary upgrades preserve its files. Uninstalling, clearing app data or explicitly resetting affects these private dependencies. Back up material you need to retain; native extensions may still need rebuilding after version changes.

## Ordinary upgrade is not reset

A compatible ordinary upgrade replaces only the exact app-managed engine components, not the whole Linux system. Existing HOME/profile, workspaces, installed system tools and user data such as Python/pip packages are preserved under the upgrade contract. Bundled versions take ownership of app-managed engine directories. Third-party native extensions may need rebuilding after changes such as a Node upgrade; preserving files does not establish extension compatibility.

If compatibility checks fail, the manifest is invalid or an upgrade is interrupted, retain the original environment and retry according to the error. Retrying is not resetting; do not delete upgrade-transaction directories by hand.

Clearing app data, uninstalling the app or explicitly resetting an environment affects local data. These are not ordinary upgrade steps. Store important files outside the runtime as well. A conversation export or diagnostics report is not a complete environment backup; the current phone shell has no one-click full environment backup/restore entry.

## Startup failure

Use Retry after the error page appears. During ordinary waiting, repeatedly reopening the app is unnecessary. If failures persist, record the version, displayed error and startup mode; see [Troubleshooting](11-faq.md). Computer mode does not install the computer engine onto the phone; see [Web connections](05-web.md).
