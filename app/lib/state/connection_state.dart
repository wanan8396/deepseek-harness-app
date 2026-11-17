import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'host_ref.dart';
import 'local_connection_state.dart';
import 'selection_state.dart';

export 'local_connection_state.dart'
    show HostConnection, LocalClientConnector, localClientConnectorProvider, networkKicksProvider;

/// The phone's read-only client, shared with official Web integrations.
class LocalConnectionController extends AsyncNotifier<HostConnection?> {
  @override
  Future<HostConnection?> build() => ref.watch(officialLocalConnectionProvider.future);
}

final localConnectionProvider = AsyncNotifierProvider<LocalConnectionController, HostConnection?>(
  LocalConnectionController.new,
);

/// Passive observations only: reading diagnostics never starts a connection.
/// Snapshots contain state names and a timestamp, not addresses or raw errors.
class ConnectionDiagnostics {
  static const _unobserved = <String, Object?>{'host': 'not_observed', 'state': 'not_observed'};
  Map<String, Object?> _value = _unobserved;
  final _changes = StreamController<void>.broadcast();

  Map<String, Object?> get snapshot => Map.unmodifiable(_value);
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _value = _unobserved;
    unawaited(_changes.close());
  }

  void _observe(Ref ref, HostRef host, AsyncValue<HostConnection?> connection) {
    final value = <String, Object?>{
      'host': 'local',
      'state': switch (connection) {
        AsyncData(:final value) => value == null ? 'disconnected' : 'connected',
        AsyncError() => 'failed',
        _ => 'connecting',
      },
      'observedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    };
    _value = value;
    _changed();
    ref.onDispose(() {
      if (!identical(_value, value)) return;
      _value = _unobserved;
      _changed();
    });
  }
}

final connectionDiagnosticsProvider = Provider((ref) {
  final diagnostics = ConnectionDiagnostics();
  ref.onDispose(diagnostics.dispose);
  return diagnostics;
});

/// Passive connection state of the phone's official local service.
final activeConnectionProvider = Provider<AsyncValue<HostConnection?>>((ref) {
  final host = ref.watch(activeHostProvider);
  final connection = ref.watch(localConnectionProvider);
  ref.read(connectionDiagnosticsProvider)._observe(ref, host, connection);
  return connection;
});
