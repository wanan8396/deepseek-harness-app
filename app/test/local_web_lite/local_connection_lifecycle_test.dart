import 'dart:async';

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/local_connection_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ready_mux.dart';

class _Destination extends WebConnectionController {
  _Destination(this.initial);
  final WebConnectionState initial;
  @override
  WebConnectionState build() => initial;
  void select(WebConnectionMode mode) => state = WebConnectionState(loaded: true, mode: mode);
}

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => running('first');
  static LocalRuntimeState running(String token) => LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:9', token: token),
  );
  void replace(String token) => state = running(token);
}

class _Client extends DshClient {
  _Client() : super(DshConnection(Uri.parse('http://127.0.0.1:9')));
  final _mux = ReadyMux();
  @override
  DshMux get mux => _mux;
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold computer does not initialize runtime, network watchers or a client', () async {
    final destination = _Destination(const WebConnectionState(loaded: true, mode: WebConnectionMode.computer));
    var runtimeReads = 0;
    var networkReads = 0;
    var connects = 0;
    final c = ProviderContainer(
      overrides: [
        webConnectionProvider.overrideWith(() => destination),
        localRuntimeProvider.overrideWith(() {
          runtimeReads++;
          return _Runtime();
        }),
        networkKicksProvider.overrideWith((_) {
          networkReads++;
          return const Stream.empty();
        }),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async {
          connects++;
          return _Client();
        }),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(officialLocalConnectionProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await c.read(officialLocalConnectionProvider.future), isNull);
    expect(runtimeReads, 0);
    expect(networkReads, 0);
    expect(connects, 0);
    expect(c.exists(localRuntimeProvider), isFalse);
  });

  test('local computer local closes each owner once and cannot publish a late connector', () async {
    final destination = _Destination(const WebConnectionState(loaded: true));
    final pending = <Completer<DshClient>>[];
    final tokens = <String>[];
    final c = ProviderContainer(
      overrides: [
        webConnectionProvider.overrideWith(() => destination),
        localRuntimeProvider.overrideWith(_Runtime.new),
        networkKicksProvider.overrideWithValue(const Stream.empty()),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) {
          tokens.add(token);
          final value = Completer<DshClient>();
          pending.add(value);
          return value.future;
        }),
      ],
    );
    final sub = c.listen(officialLocalConnectionProvider, (_, _) {});
    await settle();
    expect(pending, hasLength(1));
    destination.select(WebConnectionMode.computer);
    expect(await c.read(officialLocalConnectionProvider.future), isNull);
    final stale = _Client();
    pending.first.complete(stale);
    await settle();
    expect(stale.closes, 1);
    expect(c.read(officialLocalConnectionProvider).value, isNull);

    destination.select(WebConnectionMode.local);
    await settle();
    expect(pending, hasLength(2));
    final current = _Client();
    pending.last.complete(current);
    expect((await c.read(officialLocalConnectionProvider.future))?.client, same(current));
    expect(current.closes, 0);
    destination.select(WebConnectionMode.computer);
    expect(await c.read(officialLocalConnectionProvider.future), isNull);
    await settle();
    expect(current.closes, 1);
    expect(stale.closes, 1);
    expect(tokens, ['first', 'first']);
    sub.close();
    c.dispose();
    await settle();
    expect(current.closes, 1);
  });

  test('token replacement retires the old client and shares one new client across readers', () async {
    final destination = _Destination(const WebConnectionState(loaded: true));
    final clients = <_Client>[];
    final c = ProviderContainer(
      overrides: [
        webConnectionProvider.overrideWith(() => destination),
        localRuntimeProvider.overrideWith(_Runtime.new),
        networkKicksProvider.overrideWithValue(const Stream.empty()),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async {
          final client = _Client();
          clients.add(client);
          return client;
        }),
      ],
    );
    final first = c.listen(officialLocalConnectionProvider, (_, _) {});
    final second = c.listen(officialLocalConnectionProvider, (_, _) {});
    expect((await c.read(officialLocalConnectionProvider.future))?.client, same(clients.single));
    (c.read(localRuntimeProvider.notifier) as _Runtime).replace('second');
    await settle();
    final replacement = await c.read(officialLocalConnectionProvider.future);
    expect(clients, hasLength(2));
    expect(clients.first.closes, 1);
    expect(replacement?.client, same(clients.last));
    expect(clients.last.closes, 0);
    first.close();
    second.close();
    c.dispose();
    await settle();
    expect(clients.map((client) => client.closes), [1, 1]);
  });
}
