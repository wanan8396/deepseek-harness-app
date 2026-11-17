import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_bridge.dart';
import '../runtime/runtime_state.dart';
import 'web_connection_state.dart';

/// The official phone-local client; no remote transport or native chat owner.
class HostConnection {
  const HostConnection({required this.client, bool isLocal = true}) : assert(isLocal);

  final DshClient client;
}

typedef LocalClientConnector = Future<DshClient> Function({required Uri baseUri, required String token});

/// One connection seam shared by official notification and recent-session readers.
final localClientConnectorProvider = Provider<LocalClientConnector>(
  (ref) =>
      ({required baseUri, required token}) =>
          DshClient.connect(baseUri: baseUri, token: token, backgroundSessionLists: true, startMux: false),
);

final networkKicksProvider = Provider<Stream<void>>((ref) => _networkKicks());

/// Retry a failed local reader when sockets can run again. The initial
/// connectivity snapshot is not a retry; returning to the app always is.
Stream<void> _networkKicks() {
  late final StreamController<void> controller;
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  AppLifecycleListener? lifecycle;
  List<ConnectivityResult>? last;

  controller = StreamController<void>.broadcast(
    onListen: () {
      try {
        connectivity = Connectivity().onConnectivityChanged.listen((results) {
          final previous = last;
          last = results;
          if (previous == null) return;
          if (!results.contains(ConnectivityResult.none)) controller.add(null);
        }, onError: (_) {});
      } catch (_) {
        // No plugin in tests or unsupported desktops: retry on resume only.
      }
      lifecycle = AppLifecycleListener(onResume: () => controller.add(null));
    },
    onCancel: () {
      unawaited(connectivity?.cancel());
      lifecycle?.dispose();
      connectivity = null;
      lifecycle = null;
      last = null;
    },
  );
  return controller.stream;
}

/// Read-only owner for the phone's official Web service. Computer pages never
/// provide an endpoint here, and never initialize the local runtime through it.
class OfficialLocalConnectionController extends AsyncNotifier<HostConnection?> {
  @override
  Future<HostConnection?> build() async {
    final r = ref;
    final destination = r.watch(webConnectionProvider.select((s) => (s.loaded, s.mode)));
    if (!destination.$1 || destination.$2 != WebConnectionMode.local) return null;
    final endpoint = r.watch(
      localRuntimeProvider.select((s) {
        final status = s.status;
        return status.phase == RuntimePhase.running ? (status.baseUrl, status.token) : (null, null);
      }),
    );
    final (baseUrl, token) = endpoint;
    if (baseUrl == null || token == null) return null;

    final kicks = r.read(networkKicksProvider).listen((_) {
      if (r.mounted && state.hasError && !state.isLoading) r.invalidateSelf();
    });
    r.onDispose(() => unawaited(kicks.cancel()));

    DshClient? owned;
    var closed = false;
    Future<void> closeOwned() async {
      final client = owned;
      if (client == null || closed) return;
      closed = true;
      await client.close();
    }

    r.onDispose(() => unawaited(closeOwned()));
    final client = await r.read(localClientConnectorProvider)(baseUri: Uri.parse(baseUrl), token: token);
    owned = client;
    if (!r.mounted) {
      await closeOwned();
      return null;
    }

    final ready = client.mux.ready(timeout: const Duration(seconds: 20));
    unawaited(
      ready.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (r.mounted && identical(state.value?.client, client)) state = const AsyncData(null);
          unawaited(closeOwned());
        },
      ),
    );
    final connection = HostConnection(client: client, isLocal: true);
    state = AsyncData(connection);
    await ready;
    if (!r.mounted) return null;
    return connection;
  }
}

/// Consumers share one client. Mode/token changes dispose the build's captured
/// owner; late connectors close their client exactly once instead of publishing.
final officialLocalConnectionProvider = AsyncNotifierProvider<OfficialLocalConnectionController, HostConnection?>(
  OfficialLocalConnectionController.new,
);
