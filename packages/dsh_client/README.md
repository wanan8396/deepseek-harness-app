# dsh_client

Minimal Pure-Dart client used by the official local Web connection in the Android shell. The package retains launch-token HTTP login, unary JSON RPC, the host-wide mux event stream, and read-only session/workspace data.

## Retained surface

- `DshClient.connect(baseUri:, token:, backgroundSessionLists:, startMux:)` for the local engine.
- `DshMux` ready generations, reconnects, ordered `$events`, pending approvals and event provenance.
- Read-only `listSessions`, `projections`, `history` and reconnecting `watchWorkspaces`.
- `respondApproval` sends the decision with the current generation's `clientId`.
- `SessionSummary`, projection hints, history events, approval events and workspace update parsers.

The public package surface is limited to this connection path. Session-list background decoding is opt-in with `backgroundSessionLists: true`.

## Checks

From this package directory, with the existing `.dart_tool/package_config.json` available:

```powershell
dart analyze
```

The fixture tests use the resolved `package:test` runner with the existing package configuration, so the command does not invoke dependency resolution or alter the lock file:

```powershell
dart --packages=.dart_tool/package_config.json "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\test-1.33.0\bin\test.dart" -j 1
```

No live Host or `pub get` is needed for these checks.
