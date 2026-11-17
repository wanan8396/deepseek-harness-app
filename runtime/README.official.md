# Official DSH runtime payload

This builder is the migration path from the old patched runtime. It does not edit
files inside the official npm packages and does not package the old bridge,
engine patches, Direct preload, or boot cache.

## Inputs and reproducibility

- `runtime/locks/dsh-0.2.2-rc.3/` pins the official CLI and the complete dependency graph.
- Install a new prefix for **Linux / arm64 / glibc**. Preserve optional dependencies:

  ```powershell
  npm ci --prefix PREFIX --os=linux --cpu=arm64 --libc=glibc --ignore-scripts --no-audit --no-fund --registry=https://registry.npmjs.org/
  ```

- `--ignore-scripts` is only for cross-platform staging. On Linux ARM64, execute
  the install hooks in an isolated staging directory, not the user's DSH home.
  `node-pty`, `koffi` and the subprocess package carry precompiled Node-API
  binaries; do not force compilation. Validate loading and PTY execution on the
  phone before releasing the resulting archive.
- Supply the previous, checksum-verified rootfs **build artifact** and its
  manifest as a system seed. Never archive the installed phone filesystem:
  that could contain private conversations, credentials and user files.
- The builder copies the unchanged Ubuntu/Python/Node/pnpm system, removes the
  old engine trees, and installs the pinned official dependency tree. Package
  source-map/type metadata and foreign-platform binaries may be omitted; the
  retained executable JavaScript files are not patched.

```powershell
python runtime/build-official-runtime.py `
  --seed-manifest SEED/assets/runtime/manifest.json `
  --official-prefix PREFIX `
  --output OUTPUT/arm64-v8a `
  --work WORK
python -m unittest discover -s runtime/tests -p test_official_runtime.py
python -m unittest discover -s runtime/tests -p test_runtime_artifacts.py
```

The official builder loads only `lib/runtime_artifacts.py` for npm-file pruning
and ELF inspection. The legacy builder, patch CLI, bridge, Direct preload, boot
cache, media plugin, SDK and examples have been retired from source. The artifact
tests use independently encoded ELF/path fixtures and build a tiny verified seed
twice, then inspect archive contents, modes, metadata and reproducibility. Upgrade
contract tests retain the exact native installer path list and seed identity. None
of these desktop tests replaces ARM64 device validation.

The output is separate from the seed and uses deterministic GNU tar + xz with
fixed timestamps. `official-runtime-report.json` records the official CLI file
hashes, exact dependency lock, archive hash and pruning totals. Keep this report
with the build evidence.

## Installer contract

The verified system `upgrade.baseId` and Ubuntu/Python bytes remain unchanged.
The current installer owns exactly 14 engine paths; its incoming manifest alone
grants mutation scope. Retired seed-only slots are not forwarded or recreated in
the output archive. The installer checks the installed system identity rather
than replaying its former mutation list, and no longer adopts systems without a
current upgrade descriptor. Unknown or incomplete transactions stop without
falling back to replacing the user's whole Linux filesystem.

The r17 wrapper archive differs from the preceding r16 payload only by removal
of its obsolete empty engine directory and an updated `etc/dsh-app/runtime.json`.
All 514 retained official package files, system executables, and JNI inputs are
byte-preserved. These wrapper changes do not patch the official npm engine.

The manifest declares:

```json
{
  "engineDistribution": "official-unmodified",
  "capabilities": {
    "legacyBridge": false,
    "enginePatches": false
  }
}
```

The Android startup checks all three values explicitly and reports
`official_runtime_required` for an older distribution. The removed bridge
loader, generator and 36 generated assets have been deleted. The legacy
search/auth/speech adapter classes, their launch flags, and the old auth bridge
scripts have also been deleted. The official branch bypasses last-known-good
configuration replay.
A version number alone is not a capability declaration. Normal launch uses `dsh web --host 127.0.0.1 --port PORT
--no-open`, with no app patch flag. Rescue mode uses the official CLI's fresh
profile initializer in an isolated home.

## Migration status

The payload has been built, archive-checked and installed through the existing
rc.1-to-rc.2 transaction on an ARM64 phone. Root/private-chroot and real-App-UID
PRoot launches were observed separately. PTY, koffi, sharp image creation,
ripgrep, Node SQLite, DNS and npm probes passed on the installed payload. The
initial PTY probe's non-recursive `/dev` bind was corrected; this was a probe
setup issue, not an engine patch. A separate official fresh recovery profile
also returned HTTP 401/303/200 with its boot object present. The original 20
upgrade-transaction tests passed on Android ART with synthetic temporary trees;
Windows directory-fsync/Unix-attribute failures were kept separate.

These checks do not establish every UI/remote feature. Continue the rc.2 DOM,
phone geometry, App recovery-mode transitions and external computer/QR checks
before treating this build as the completed product migration.

The retired source is deleted rather than moved into another full-edition tree.
Existing runtime archives, immutable seeds and historical dependency locks remain
separate build/provenance inputs; source retirement does not rewrite those assets
or establish that a new APK has been built or verified on a phone.
