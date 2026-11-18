import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/ui/ios/ios_official_carrier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dsh/ios-local');
const _generation = '01234567-89ab-4def-8123-456789abcdef';
const _streamPath = '/api/ios-app/stream';
const _setup = {
  'apiKey': 'fixture-key',
  'protocol': 'openai-chat',
  'baseUrl': 'https://models.example/v1',
  'modelId': 'fixture-model',
};

Future<IosOfficialCarrier> _start() => IosOfficialCarrier.start(
  apiKey: _setup['apiKey']!,
  protocol: _setup['protocol']!,
  baseUrl: _setup['baseUrl']!,
  modelId: _setup['modelId']!,
);

Map<String, Object?> _args(MethodCall call) => Map<String, Object?>.from(call.arguments as Map);
Map<String, Object?> _body(MethodCall call) => jsonDecode(_args(call)['body']! as String) as Map<String, Object?>;
Map<String, Object?> _reply(Map<String, Object?> body, {int status = 200}) => {
  'status': status,
  'body': jsonEncode(body),
};

TypeMatcher<IosOfficialTransportException> _failure(String code) =>
    isA<IosOfficialTransportException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  void install(
    FutureOr<Object?> Function(MethodCall) onPost, {
    FutureOr<Object?> Function()? onStop,
    String generation = _generation,
  }) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'startOfficialRuntime':
          expect(call.arguments, _setup);
          return generation;
        case 'callOfficialRuntime':
          expect(_args(call).keys, unorderedEquals(['generation', 'path', 'body']));
          expect(_args(call)['generation'], generation);
          return onPost(call);
        case 'stopOfficialRuntime':
          expect(call.arguments, {'generation': generation});
          return onStop?.call();
        default:
          fail('unexpected MethodChannel operation: ${call.method}');
      }
    });
  }

  test('unary RPC uses the official request and response envelopes', () async {
    var attempt = 0;
    const remoteError = {'code': 'gateway/arguments-invalid', 'message': 'invalid request'};
    install((call) {
      expect(_args(call)['path'], '/api/session/list');
      final body = _body(call);
      final rpcId = body['rpcId'];
      expect(rpcId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(body, {
        'type': 'client-request',
        'rpcId': rpcId,
        'method': 'session/list',
        'payload': {'args': {'_request': {}}},
      });
      return _reply({
        'type': 'server-response',
        'rpcId': switch (attempt) {0 => rpcId, 1 => 'invalid-request', _ => 'different-rpc'},
        'result': attempt++ == 1
            ? {'ok': false, 'error': remoteError}
            : {'ok': true, 'value': {'items': []}},
      });
    });

    final carrier = await _start();
    addTearDown(carrier.close);
    expect(carrier.generation, _generation);
    const args = <String, Object?>{'_request': <String, Object?>{}};
    expect(await carrier.call('session/list', args), isA<IosOfficialRpcSuccess>().having(
      (result) => result.value,
      'value',
      {'items': []},
    ));
    expect(await carrier.call('session/list', args), isA<IosOfficialRpcFailure>().having(
      (result) => result.error,
      'error',
      remoteError,
    ));
    await expectLater(carrier.call('session/list', args), throwsA(_failure('IOS_OFFICIAL_INVALID_REPLY')));
    final stopped = carrier.close();
    expect(carrier.close(), same(stopped));
    await stopped;
    await expectLater(carrier.call('session/list', args), throwsA(_failure('IOS_OFFICIAL_CLOSED')));
    expect(calls.map((call) => call.method), [
      'startOfficialRuntime',
      'callOfficialRuntime',
      'callOfficialRuntime',
      'callOfficialRuntime',
      'stopOfficialRuntime',
    ]);
  });

  test('rejects malformed generation before exposing a carrier', () async {
    install((_) => fail('invalid generation must not post'), generation: _generation.toUpperCase());
    await expectLater(_start(), throwsA(_failure('IOS_OFFICIAL_INVALID_REPLY')));
    expect(calls, hasLength(1));
  });

  test('raw POST preserves wire text; interpreted failures omit response or platform details', () async {
    var attempt = 0;
    install((call) {
      switch (attempt++) {
        case 0:
          expect(_args(call)['path'], '/api/session/search');
          expect(_args(call)['body'], ' { "fixture" : true } ');
          return {'status': 403, 'body': 'raw-denial'};
        case 1:
          return {'status': 403, 'body': 'do-not-log-body'};
        case 2:
          return {'status': 200, 'body': 'do-not-log-malformed-json'};
        case 3:
          return {'status': '200', 'body': '{}'};
        default:
          throw PlatformException(code: 'IOS_OFFICIAL_BUSY', message: 'fixture-key', details: 'do-not-log-details');
      }
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    final raw = await carrier.rawPost('/api/session/search', ' { "fixture" : true } ');
    expect(raw.status, 403);
    expect(raw.body, 'raw-denial');
    await expectLater(carrier.call('session/search', {}), throwsA(
      _failure('IOS_OFFICIAL_STATUS').having((error) => error.status, 'status', 403)
          .having((error) => error.toString(), 'description', isNot(contains('do-not-log-body'))),
    ));
    await expectLater(carrier.call('session/search', {}), throwsA(
      _failure('IOS_OFFICIAL_INVALID_REPLY').having(
        (error) => error.toString(), 'description', isNot(contains('do-not-log-malformed-json')),
      ),
    ));
    await expectLater(carrier.call('session/search', {}), throwsA(_failure('IOS_OFFICIAL_INVALID_REPLY')));
    await expectLater(carrier.call('session/search', {}), throwsA(
      _failure('IOS_OFFICIAL_BUSY').having(
        (error) => error.toString(), 'description', allOf(isNot(contains('fixture-key')), isNot(contains('details'))),
      ),
    ));
  });

  test('downlink opens on listen and treats idle as another pull, not a data event', () async {
    final types = <String>[];
    late String id;
    var pulls = 0;
    install((call) {
      expect(_args(call)['path'], _streamPath);
      final body = _body(call);
      final type = body['type']! as String;
      types.add(type);
      if (type == 'open') {
        id = body['id']! as String;
        expect(id, matches(RegExp(r'^s[0-9a-f]{32}$')));
        expect(body, {
          'type': 'open',
          'id': id,
          'endpoint': 'session/follow',
          'payload': {'args': {'request': {'address': {'kind': 'session', 'sessionId': 'session-fixture'}}}},
        });
        return _reply({'opened': true});
      }
      expect(body, {'type': 'next', 'id': id});
      return switch (++pulls) {
        1 => _reply({'idle': true}),
        2 => _reply({'done': false, 'value': {'header': {'id': 'session-fixture'}}}),
        3 => _reply({'done': false, 'value': null}),
        _ => _reply({'done': true}),
      };
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    final stream = carrier.openStream('session/follow', {
      'request': {'address': {'kind': 'session', 'sessionId': 'session-fixture'}},
    });
    expect(types, isEmpty);
    expect(await stream.toList(), [{'header': {'id': 'session-fixture'}}, null]);
    expect(types, ['open', 'next', 'next', 'next', 'next']);
  });

  test('cancel closes immediately with next in flight and ignores its late reply', () async {
    final nextSeen = Completer<void>();
    final nextReply = Completer<Object?>();
    final types = <String>[];
    late Object? id;
    install((call) {
      final body = _body(call);
      final type = body['type']! as String;
      types.add(type);
      if (type == 'open') {
        id = body['id'];
        return _reply({'opened': true});
      }
      expect(body, {'type': type, 'id': id});
      if (type == 'next') {
        nextSeen.complete();
        return nextReply.future;
      }
      expect(type, 'close');
      expect(nextReply.isCompleted, isFalse);
      return _reply({'closed': true});
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    final events = <Object?>[];
    final subscription = carrier.openStream(r'$events', {}).listen(events.add);
    await nextSeen.future;
    await subscription.cancel();
    nextReply.complete(_reply({'done': false, 'value': 'late'}));
    await Future<void>.delayed(Duration.zero);
    expect(types, ['open', 'next', 'close']);
    expect(events, isEmpty);
  });

  test('cancel during open defers native close until admission and never pulls', () async {
    final openSeen = Completer<void>();
    final openReply = Completer<Object?>();
    final closeSeen = Completer<void>();
    final types = <String>[];
    late Object? id;
    install((call) {
      final body = _body(call);
      final type = body['type']! as String;
      types.add(type);
      if (type == 'open') {
        id = body['id'];
        openSeen.complete();
        return openReply.future;
      }
      expect(body, {'type': 'close', 'id': id});
      closeSeen.complete();
      return _reply({'closed': true});
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    final subscription = carrier.openStream(r'$events', {}).listen((_) => fail('cancelled stream delivered data'));
    await openSeen.future;
    await subscription.cancel();
    expect(types, ['open']);
    openReply.complete(_reply({'opened': true}));
    await closeSeen.future;
    expect(types, ['open', 'close']);
  });

  test('failed pull terminates the stream and releases the native stream once', () async {
    final types = <String>[];
    install((call) {
      final type = _body(call)['type']! as String;
      types.add(type);
      return switch (type) {
        'open' => _reply({'opened': true}),
        'next' => _reply({'error': 'mailbox-failure'}, status: 500),
        'close' => _reply({'closed': true}),
        _ => fail('unexpected stream command: $type'),
      };
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    await expectLater(carrier.openStream(r'$events', {}), emitsInOrder([
      emitsError(_failure('IOS_OFFICIAL_STATUS')),
      emitsDone,
    ]));
    expect(types, ['open', 'next', 'close']);
  });

  test('generation close aborts app consumers without waiting for pending native replies', () async {
    final nextSeen = Completer<void>();
    final unarySeen = Completer<void>();
    final nextReply = Completer<Object?>();
    final unaryReply = Completer<Object?>();
    install((call) {
      if (_args(call)['path'] == '/api/session/list') {
        unarySeen.complete();
        return unaryReply.future;
      }
      switch (_body(call)['type']) {
        case 'open':
          return _reply({'opened': true});
        case 'next':
          nextSeen.complete();
          return nextReply.future;
        default:
          fail('runtime stop, not a stream close, owns cleanup of this generation');
      }
    });
    final carrier = await _start();
    addTearDown(carrier.close);
    final items = carrier.openStream(r'$events', {}).toList();
    final unary = expectLater(carrier.call('session/list', {}), throwsA(_failure('IOS_OFFICIAL_CLOSED')));
    await Future.wait([nextSeen.future, unarySeen.future]);
    await carrier.close();
    expect(await items, isEmpty);
    await unary;
    nextReply.complete(_reply({'done': false, 'value': 'late'}));
    unaryReply.complete(_reply({'type': 'server-response'}));
    await expectLater(carrier.openStream(r'$events', {}).toList(), throwsA(_failure('IOS_OFFICIAL_CLOSED')));
    expect(calls.map((call) => call.method).where((method) => method == 'stopOfficialRuntime'), hasLength(1));
  });
}
