/// Minimal client surface used by the official local Web shell.
///
library;

import 'dart:async';

import 'carrier.dart';
import 'connection.dart';
import 'errors.dart';
import 'json.dart';
import 'models.dart';
import 'mux.dart';
import 'rpc.dart';

/// Read-only client for session inventory, projections, history pages,
/// workspace updates and host-wide approval events.
class DshClient {
  DshClient(DshConnection connection, {MuxOptions muxOptions = const MuxOptions(), bool backgroundSessionLists = false})
    : this.withCarrier(
        DshHttpCarrier(connection),
        muxOptions: muxOptions,
        backgroundSessionLists: backgroundSessionLists,
      );

  DshClient.withCarrier(this.carrier, {MuxOptions muxOptions = const MuxOptions(), bool backgroundSessionLists = false})
    : _backgroundSessionLists = backgroundSessionLists,
      rpc = DshRpc(carrier),
      mux = DshMux(carrier, options: muxOptions);

  /// Connects to the local DSH web service and exchanges the launch token for
  /// the authority-bound HTTP session cookie. The mux may be started by the
  /// owner after installing its event listeners.
  static Future<DshClient> connect({
    required Uri baseUri,
    required String token,
    MuxOptions muxOptions = const MuxOptions(),
    DshTracer? tracer,
    bool backgroundSessionLists = false,
    bool startMux = true,
    Duration readyTimeout = const Duration(seconds: 20),
  }) async {
    final connection = DshConnection(baseUri, tracer: tracer);
    final client = DshClient(connection, muxOptions: muxOptions, backgroundSessionLists: backgroundSessionLists);
    try {
      await connection.login(token);
      if (startMux) await client.mux.ready(timeout: readyTimeout);
      return client;
    } on Object {
      await client.close();
      rethrow;
    }
  }

  final DshCarrier carrier;
  final DshRpc rpc;
  final DshMux mux;
  final bool _backgroundSessionLists;

  /// The HTTP connection of the default carrier.
  DshConnection get connection => switch (carrier) {
    DshHttpCarrier(:final connection) => connection,
    _ => throw StateError('DshClient.connection is only available on the HTTP carrier'),
  };

  /// All parsed `$events` items, in Host delivery order.
  Stream<HostEvent> get hostEvents => mux.hostEvents;

  /// Returns the complete session inventory, including archived and child
  /// sessions. A later history page uses the precise session/subagent address
  /// learned from these rows rather than rewriting the session id.
  Future<List<SessionSummary>> listSessions() async {
    final List<SessionSummary> rows;
    if (_backgroundSessionLists && carrier is DshHttpCarrier && connection.canReadSessionsInBackground) {
      rows = await connection.readSessionsInBackground();
    } else {
      final value = asMapOrEmpty(await rpc.call('session/list', {'_request': <String, Object?>{}}));
      rows = asListOrEmpty(value['items']).map(SessionSummary.fromJson).toList(growable: false);
    }
    for (final row in rows) {
      if (row.isSubagent && (row.parentSessionId?.isNotEmpty ?? false)) {
        final child = asMap(row.projections.values['subagent']);
        final mode = switch (asString(child?['mode'])) {
          'one-shot' => 'one-shot',
          'continuable' => 'continuable',
          _ => 'unknown',
        };
        _sessionAddresses[row.sessionId] = {
          'kind': 'subagent',
          'parentSessionId': row.parentSessionId!,
          'childSessionId': row.sessionId,
          'mode': mode,
        };
      } else {
        _sessionAddresses.remove(row.sessionId);
      }
    }
    return rows;
  }

  final Map<String, Map<String, Object?>> _sessionAddresses = {};

  /// Address required by the Host's session page/follow contract. Child
  /// session rows retain their parent relation and mode; ordinary ids pass
  /// through unchanged as a `kind: session` address.
  Map<String, Object?> sessionAddressOf(String sessionId) =>
      _sessionAddresses[sessionId] ?? {'kind': 'session', 'sessionId': sessionId};

  /// `session/projections` is a non-activating read; null means the session
  /// has no projection row on this Host.
  Future<SessionProjections?> projections(String sessionId) async {
    final value = await rpc.call('session/projections', {
      'request': {'sessionId': sessionId},
    });
    return value == null ? null : SessionProjections.fromJson(value);
  }

  /// Reads the history cut ending at [throughSeq]. The Host receives the
  /// original session identity (including a child-address record when known).
  Future<HistoryPage> history(
    String sessionId, {
    required int throughSeq,
    int? beforeSeq,
    int? maxMessages,
    TurnWindow? turnWindow,
  }) async {
    final value = asMapOrEmpty(
      await rpc.call('session/page', {
        'request': {
          'address': sessionAddressOf(sessionId),
          'throughSeq': throughSeq,
          'beforeSeq': ?beforeSeq,
          'maxMessages': ?maxMessages,
          if (turnWindow != null) 'turnWindow': turnWindow.toJson(),
        },
      }),
    );
    return HistoryPage(
      asListOrEmpty(
        value['records'],
      ).map((record) => SessionLogEvent.fromJson(asMapOrEmpty(record)['event'])).toList(growable: false),
      value['hasMore'] == true,
    );
  }

  /// Answers an approval using the currently-ready `$events` generation. A
  /// stale event stream gets the same bounded retry behavior as the Host API.
  Future<void> respondApproval(ApprovalRequest request, ApprovalDecision decision) async {
    final outcome = decision == ApprovalDecision.pass ? {'kind': 'next'} : {'kind': 'result', 'value': decision.wire};
    for (var attempt = 0; ; attempt++) {
      final generation = await mux.ready();
      try {
        await rpc.call(r'$events/result', {
          'clientId': generation.clientId,
          'eventId': request.eventId,
          'outcome': outcome,
        });
        mux.resolvePendingRequest(request.eventId);
        return;
      } on DshRemoteException catch (error) {
        final stale = error.message.contains('identifies no active event stream');
        if (!stale || attempt >= 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// A resilient read-only `workspace/follow`; every mux generation reopens
  /// the stream and begins with the Host's replacement baseline.
  Stream<WorkspaceUpdate> watchWorkspaces() {
    late final StreamController<WorkspaceUpdate> controller;
    MuxStream? current;
    var stopped = false;

    Future<void> run() async {
      while (!stopped) {
        try {
          await mux.ready();
        } on Object catch (error) {
          if (!stopped) controller.addError(error);
          break;
        }
        if (stopped) break;
        try {
          final stream = current = mux.open('workspace/follow', const {});
          await for (final item in stream.items) {
            if (stopped) break;
            controller.add(WorkspaceUpdate.fromJson(item));
          }
          if (stopped) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } on DshCarrierLostException {
          continue;
        } on DshClosedException {
          break;
        } on Object catch (error) {
          if (!stopped) controller.addError(error);
          break;
        }
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<WorkspaceUpdate>(
      onListen: () => unawaited(run()),
      onCancel: () async {
        stopped = true;
        await current?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> close() async {
    await mux.close();
    await carrier.close();
  }
}
