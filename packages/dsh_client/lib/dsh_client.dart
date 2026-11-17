/// Client for the official local DSH Web service.
///
/// This package retains only the HTTP/RPC transport, host event mux, and the
/// session/workspace reads used by the Lite Android shell.
library;

export 'src/carrier.dart';
export 'src/connection.dart' show DshConnection, DshCookie, DshHttpResponse, DshTraceEntry, DshTracer;
export 'src/errors.dart';
export 'src/models.dart';
export 'src/mux.dart';
export 'src/rpc.dart';
export 'src/session_api.dart' show DshClient;
export 'src/workspaces_api.dart' show workspaceReplaceFrame;
