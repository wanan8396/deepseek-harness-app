import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_dsh.dart';

const fastMux = MuxOptions(readyTimeout: Duration(seconds: 2), retryCaps: [Duration(milliseconds: 10)]);

void main() {
  late FakeDsh host;

  setUp(() async => host = await FakeDsh.start());
  tearDown(() async => host.close());

  Future<DshClient> connect({bool startMux = true}) =>
      DshClient.connect(baseUri: host.baseUri, token: FakeDsh.token, muxOptions: fastMux, startMux: startMux);

  test('login mints the cookie; RPC carries it with Host and no Origin', () async {
    host.handlers['session/list'] = (args) {
      expect(args, {'_request': <String, Object?>{}});
      return {
        'ok': true,
        'value': {'items': <Object?>[]},
      };
    };
    final client = await connect(startMux: false);
    addTearDown(client.close);
    final cookie = client.connection.cookie!;
    expect(cookie.name, FakeDsh.cookieName);
    expect(cookie.value, FakeDsh.cookieValue);
    expect(cookie.authority, '127.0.0.1:${host.port}');
    expect(DshCookie.fromJson(cookie.toJson()).header, cookie.header);
    expect(await client.listSessions(), isEmpty);

    final envelope = host.rpcCalls.single;
    expect(envelope['type'], 'client-request');
    expect(envelope['method'], 'session/list');
    expect(envelope['rpcId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    final request = host.requests.last;
    expect(request['path'], '/api/session/list');
    expect(request['host'], '127.0.0.1:${host.port}');
    expect(request['origin'], isNull);
    expect(request['cookie'], cookie.header);
  });

  test('bad launch token is a typed HTTP 401', () async {
    final connection = DshConnection(host.baseUri);
    addTearDown(connection.close);
    await expectLater(
      connection.login('wrong'),
      throwsA(isA<DshHttpException>().having((error) => error.statusCode, 'status', 401)),
    );
  });

  test('ready is delivered before pending approvals and replies bind to this generation', () async {
    host.pendingWaterfalls.addAll([
      {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'evt-1',
        'agentId': 's1',
        'request': {'toolName': 'bash', 'callId': 'call-1', 'reason': 'run command'},
      },
      {
        'type': 'waterfall',
        'event': 'user-questions/request',
        'eventId': 'evt-2',
        'agentId': 's1',
        'request': {
          'questions': [
            {'id': 'q1', 'question': 'Continue?'},
          ],
        },
      },
    ]);
    Map<String, Object?>? answer;
    host.handlers[r'$events/result'] = (args) {
      answer = args;
      return {'ok': true};
    };
    final client = await connect(startMux: false);
    addTearDown(client.close);
    final events = client.hostEvents.take(3).toList();
    await client.mux.ready();
    final delivered = await events;
    expect(delivered, [
      isA<HostReadyEvent>(),
      isA<ApprovalRequestedEvent>().having((event) => event.request.eventId, 'eventId', 'evt-1'),
      isA<UserQuestionRequestedEvent>().having((event) => event.request.eventId, 'eventId', 'evt-2'),
    ]);
    expect(
      client.mux.pendingRequests.map(
        (event) => switch (event) {
          ApprovalRequestedEvent(:final request) => request.eventId,
          UserQuestionRequestedEvent(:final request) => request.eventId,
          _ => '',
        },
      ),
      ['evt-1', 'evt-2'],
    );

    final cancelled = client.hostEvents.where((event) => event is HostRequestCancelledEvent).first;
    await client.respondApproval(
      const ApprovalRequest(eventId: 'evt-1', sessionId: 's1', toolName: 'bash'),
      ApprovalDecision.allowOnce,
    );
    expect(answer, {
      'clientId': 'client-1',
      'eventId': 'evt-1',
      'outcome': {'kind': 'result', 'value': 'allowed-once'},
    });
    expect(await cancelled, isA<HostRequestCancelledEvent>().having((event) => event.eventId, 'eventId', 'evt-1'));
    expect(host.requests.last['rawPath'], r'/api/$events/result');
  });

  test('reconnect redelivers the same approval id and response uses the new clientId', () async {
    host.pendingWaterfalls.add({
      'type': 'waterfall',
      'event': 'approval/request',
      'eventId': 'evt-replay',
      'agentId': 's2',
      'request': {'toolName': 'write', 'callId': 'call-2'},
    });
    Map<String, Object?>? answer;
    host.handlers[r'$events/result'] = (args) {
      answer = args;
      return {'ok': true};
    };
    final client = await connect();
    addTearDown(client.close);
    final first = await client.hostEvents.where((event) => event is ApprovalRequestedEvent).first;
    expect((first as ApprovalRequestedEvent).request.eventId, 'evt-replay');
    expect(client.mux.generation?.number, 1);

    final replayed = client.hostEvents.where((event) => event is ApprovalRequestedEvent).first;
    client.mux.reconnect();
    final second = await replayed.timeout(const Duration(seconds: 3));
    expect((second as ApprovalRequestedEvent).request.eventId, 'evt-replay');
    expect(client.mux.generation?.number, 2);
    await client.respondApproval(second.request, ApprovalDecision.reject);
    expect(answer?['clientId'], 'client-2');
    expect(answer?['outcome'], {'kind': 'result', 'value': 'rejected'});
  });

  test('refused WebSocket parks the mux in unauthorized', () async {
    final client = await connect(startMux: false);
    addTearDown(client.close);
    host.rejectWebSocket = true;
    await expectLater(client.mux.ready(), throwsA(isA<DshHttpException>()));
    expect(client.mux.state, DshConnectionState.unauthorized);
  });

  test('logical stream error frames surface as typed Host errors', () async {
    host.onOpen = (socket, streamId, endpoint, payload) => socket.send({
      'type': 'error',
      'streamId': streamId,
      'error': {
        'code': 'session/not-found',
        'message': 'session missing',
        'details': {'sessionId': 'x'},
      },
    });
    final client = await connect();
    addTearDown(client.close);
    final stream = client.mux.open('session/follow', const {});
    await expectLater(
      stream.items.toList(),
      throwsA(isA<DshRemoteException>().having((error) => error.code, 'code', 'session/not-found')),
    );
  });
}
