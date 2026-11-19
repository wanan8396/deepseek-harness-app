# iOS Flutter donor source

The donor is the locally available Git commit `aa3578557b1500ecf4ec62f9ad86223e6e3f1bf5` (tree `ba6c61585eb728e18a34b7fe35077ff63f4de324`, `Initial source snapshot: DeepSeek harness Android rc.2`). The enclosing repository currently has this object; the iOS overlay's own Git repository does not. The generator reads the object directly, without a checkout, fetch, build, or dependency installation. Supply the path to a trusted local repository that already contains the commit and blobs; the remote donor is not needed. This is not a floating upstream reference.

**The output is a reference source subtree for the iOS port, not an application or a dependency.** It preserves the selected donor bytes as evidence for later iOS changes. No files in the live [Flutter app](../app) or iOS runner are replaced; there is no package registration, build hook, or UI change. Do not publish the staged tree as a runnable copy of the original Android app.

## What is inventoried

| Role | Included |
| --- | --- |
| Source | Reviewed Dart path families under `app/lib`, plus the two Dart client packages `dsh_client` and `dsh_remote`, exact supporting generator/input paths for emoji, Unicode/pet validation and replay, and the three editable replay viewer sources. Some code describes Android-dependent behavior; staging it does not expose that capability on iOS. |
| Localization inputs | English and Chinese per-area ARB files, small Dart localization handoff code, the donor's configuration, and merge/catalog tooling. No merged ARB files or generated localization Dart. |
| Test source | Dart test source from selected app areas and both client packages. Excludes data fixtures, captures, goldens, screenshots and generated snapshots; donor tests are references and are not guaranteed to run against the source-only snapshot. |
| Metadata | Selected pubspecs, lockfiles and analyzer/test configuration, plus package READMEs. They describe donor dependencies and may reference assets/platforms omitted here. They are not a dependency plan for the live iOS app. |
| Rights and provenance | The donor's original `LICENSE`, `THIRD_PARTY_NOTICES.md`, `ASSETS.md`, both attribution documents, and exact component license texts for DSH Remote, Phosphor, JetBrains Mono and the Unicode data. This includes two text-only notice paths under `app/assets`, not the assets themselves. Keep all applicable notices and original source headers when porting. |

The [literal source rules](../tooling/stage_ios_flutter.py) and pinned tree, not pattern matches against a changing checkout, determine eligibility. The donor's `ASSETS.md` separately reserves its brand and mascot rights; the source license does not cover those assets. The staging rules exclude donor Android and native payloads, launchers, branding and original or generated art, fonts, web-shell assets, site/home and assets, bundled media, test data, and the generated Dart brand glyph and feature tile shapes with their asset-specific wrappers. The donor theme, wordmark, startup-cover code, app icon picker and whale activity renderer are deliberately left out. Licensed text notices are retained even when a listed component is absent. The subtree does not confer rights to distribute anything not separately licensed.

The target retains its existing [asset notice](../ASSETS.md), fonts, launcher, theme, startup widget, and original 40-frame [startup GIF](../app/assets/branding/startup-cover.gif) with SHA-256 `28819e73e7a94d680a70a5bd4d2eca6c88bff734aafca9615b882950faec3e0b`. The generator enforces this separation by never writing into the target `app` directory. It does not hash or change the target's theme or assets as a side effect. Future iOS adapters, target-specific UI decisions and merged bilingual localization (including existing iOS keys) belong in separately reviewed target changes, not in donor file edits or transformations to this provenance manifest.

## Plan, then explicitly export

Requires Python 3.10+ and Git on `PATH`. Run from the iOS overlay root. The examples use POSIX shell redirection; on older Windows PowerShell, do not use `>` on a native process if it changes bytes or adds a BOM. A `cmd.exe` shell can redirect the raw Python stdout. Use a scratch path **outside** the subtree and outside tracked files for the plan. Replace the example paths with existing, trusted local directories; `--target-root` defaults to the generator's project root.

```sh
python3 tooling/stage_ios_flutter.py plan --source-repo /path/to/local/donor-repo > /path/to/scratch/ios-donor-plan.json
# Inspect the complete plan, allowlist and notices before approving materialization.
python3 tooling/stage_ios_flutter.py export --source-repo /path/to/local/donor-repo --plan /path/to/scratch/ios-donor-plan.json
python3 tooling/stage_ios_flutter.py reverify --source-repo /path/to/local/donor-repo
```

- `plan` writes canonical, sorted LF JSON to stdout and does not create files or consult donor worktree files, index, branches or tags. The manifest records schema, commit/tree, the staging attributes digest, and each relative path, role, Git mode/OID, byte size and SHA-256. It contains no time, machine paths or credentials.
- `export` requires that reviewed byte-exact plan and independently recomputes it from the pinned local object before writing. It creates only the detached `vendor/ios-flutter-donor/` subtree below the chosen root (and `vendor/` if needed). Existing destination directories, including empty ones, are not merged or overwritten. Every donor path stays relative and unchanged under the stage; payload files are written as raw Git blob bytes. The generated `.gitattributes` keeps Git from applying ancestor line-ending or content filters to those raw bytes. The completion manifest is written last. If an I/O error leaves a partial export, inspect it and remove only the incomplete subtree before retrying; the tool never auto-deletes existing files.
- `reverify` is read-only. It compares the exact staged file and directory roster, checks hashes and sizes (including the exact manifest and attributes), and rejects extras, missing members, links, junctions and unexpected file types. Source paths are restricted to portable relative names and checked for case/ancestor collisions; only normal, non-executable UTF-8 Git blobs are eligible. Use a trusted target directory with no concurrent writers or link changes during export or verification.

For a later tracked subtree checked out on a machine without the donor object, retain the manifest SHA-256 printed by successful `export` (or compute it directly from an independently reviewed `plan`) in a separately trusted review or CI pin. Then use:

```sh
python3 tooling/stage_ios_flutter.py reverify --manifest-sha256 APPROVED_MANIFEST_SHA256
```

The pin in this mode authenticates the **reviewed manifest**, which in turn defines the exact staged bytes. Computing a new pin from the same untrusted checkout is not independent verification. When the donor object is available, use `--source-repo` to cross-check the stage directly. Git staging, publication and wiring into any build are separate actions and are not performed by these commands.

## Focused tests

The [generator tests](../tooling/test_stage_ios_flutter.py) cover policy cutouts, path and manifest tampering, stable bytes from a dirty synthetic Git worktree, exact-stage verification, preservation of protected target files, and no-overwrite/link behavior. Run them when permitted, without Flutter or npm:

```sh
python3 -m unittest discover -s tooling -p test_stage_ios_flutter.py -v
```

## Assembled iOS checkout

[`tooling/assemble_ios_flutter.py`](../tooling/assemble_ios_flutter.py) writes a throwaway checkout that keeps this repository's iPhone shell, theme, startup GIF and iOS bridge, restores the reviewed historical chat, session drawer, model and approval widgets, and applies the reviewed `app/lib/ui/ios/donor/*.template` replacements for the Android-only or removed-art surfaces. It never writes into the checked-in `app/`, never includes `app/android/`, and fails closed if a patch site, template or relative Dart import is missing. The target keeps its own `main.dart` and hands the staged entry its own Riverpod container, so the historical provider graph cannot fall back to Android providers.

```sh
python3 tooling/assemble_ios_flutter.py --target-root . --output /tmp/ios-flutter \
  --vendor-manifest-sha256 PINNED_MANIFEST_SHA256
python3 -m unittest discover -s tooling -p test_assemble_ios_flutter.py -v
```

The `flutter-ui` job assembles the tracked snapshot, checks that the theme and GIF are byte-identical to the target, and installs the same official runtime bundles tested by the Linux `loader` job. It runs analysis and carrier tests, verifies the Simulator app, and exports an unsigned `*-flutter-unsigned.ipa` for iPhone and iPad after checking the embedded runtime and package layout. The similarly named IPA from the independent `ios` job is the baseline diagnostic shell, not the historical Flutter UI. Neither build proves signing, physical-device operation, or live model inference. `--include-untracked` exists only for a local overlay clone whose new iOS files are not committed yet.
