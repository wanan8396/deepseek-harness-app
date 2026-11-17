import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

class _MemoryCarrier extends DshCarrier {
  final Map<String, RpcResult Function(Map<String, Object?> args)> handlers = {};
  final List<_MemoryLink> links = [];
  Object? refuseWith;
  int clientIds = 0;

  @override
  String get kind => 'memory';
  @override
  DshTracer? get tracer => null;

  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async =>
      handlers[endpoint]?.call(args) ?? const RpcError(DshRemoteException('gateway/not-found', 'missing'));

  @override
  Future<DshMuxLink> openLink(MuxOptions options) async {
    final refusal = refuseWith;
    if (refusal != null) throw refusal;
    final link = _MemoryLink(this);
    links.add(link);
    return link;
  }

  @override
  Future<void> close() async {}
}

class _MemoryLink implements DshMuxLink {
  _MemoryLink(this.carrier);
  final _MemoryCarrier carrier;
  late DshMuxFrameHandler onFrame;
  late DshMuxLossHandler onLost;
  bool closed = false;

  void item(String streamId, Object? value) => onFrame({'type': 'item', 'streamId': streamId, 'value': value});

  @override
  void start({required DshMuxFrameHandler onFrame, required DshMuxLossHandler onLost}) {
    this.onFrame = onFrame;
    this.onLost = onLost;
  }

  @override
  void open(String streamId, String endpoint, Map<String, Object?> payload) {
    if (endpoint != r'$events') return;
    scheduleMicrotask(
      () => item(streamId, {
        'type': 'ready',
        'clientId': 'memory-${++carrier.clientIds}',
        'host': {'home': '/home'},
      }),
    );
  }

  @override
  void sendItem(String streamId, Object? value) {}
  @override
  void endUplink(String streamId) {}
  @override
  void cancel(String streamId) {}
  @override
  Future<void> close(int code, String reason) async => closed = true;
}

const fastMux = MuxOptions(readyTimeout: Duration(seconds: 2), retryCaps: [Duration(milliseconds: 10)]);

void main() {
  test('DshClient.withCarrier uses the common mux and session-list RPC', () async {
    final carrier = _MemoryCarrier();
    carrier.handlers['session/list'] = (args) {
      expect(args, {'_request': <String, Object?>{}});
      return const RpcOk({
        'items': [
          {'sessionId': 's1'},
        ],
      });
    };
    final client = DshClient.withCarrier(carrier, muxOptions: fastMux);
    addTearDown(client.close);
    await client.mux.ready();
    expect(client.mux.generation?.clientId, 'memory-1');
    expect((await client.listSessions()).single.sessionId, 's1');
    expect(() => client.connection, throwsStateError);
    await expectLater(client.rpc.call('bad endpoint'), throwsArgumentError);
  });

  test('a refused link parks the mux until an explicit reconnect', () async {
    final carrier = _MemoryCarrier()
      ..refuseWith = const DshCarrierRefusedException('HOST_REFUSED', 'host refused connection');
    final client = DshClient.withCarrier(carrier, muxOptions: fastMux);
    addTearDown(client.close);
    await expectLater(
      client.mux.ready(),
      throwsA(isA<DshCarrierRefusedException>().having((error) => error.code, 'code', 'HOST_REFUSED')),
    );
    expect(client.mux.state, DshConnectionState.unauthorized);
    expect(carrier.links, isEmpty);
    carrier.refuseWith = null;
    client.mux.reconnect();
    await client.mux.ready(timeout: const Duration(seconds: 2));
    expect(client.mux.state, DshConnectionState.connected);
  });
}
