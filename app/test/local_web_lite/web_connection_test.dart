import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/storage/secret_store.dart';
import 'package:dsh_app/state/secret_store_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedSecrets extends MemorySecretStore {
  _DelayedSecrets([super.initial]);
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    return super.write(key, value);
  }
}

class _UnavailableSecrets extends MemorySecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('private storage details');
  @override
  Future<void> write(String key, String value) async => throw StateError('private storage details');
  @override
  Future<void> delete(String key) async => throw StateError('private storage details');
}

ProviderContainer _container(SecretStore secrets) {
  final container = ProviderContainer(overrides: [secretStoreProvider.overrideWithValue(secrets)]);
  addTearDown(container.dispose);
  return container;
}

Future<WebConnectionState> _ready(ProviderContainer container) async {
  await container.read(webConnectionProvider.notifier).ready;
  return container.read(webConnectionProvider);
}

Future<Map<String, dynamic>> _saved() async {
  final raw = (await SharedPreferences.getInstance()).getString(WebConnectionController.prefsKey)!;
  return jsonDecode(raw) as Map<String, dynamic>;
}

Map<String, Object> _record(String id, String url, {String label = 'Test computer', String? used}) => {
  'id': id,
  'label': label,
  'baseUrl': url,
  'lastUsed': used ?? '2026-01-01T00:00:00.000Z',
};

void _seed(List<Map<String, Object>> records, {String mode = 'computer', String? selectedId}) {
  SharedPreferences.setMockInitialValues({
    WebConnectionController.prefsKey: jsonEncode({'mode': mode, 'selectedId': selectedId, 'records': records}),
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new install defaults local and loading does not write preferences', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    expect(c.read(webConnectionProvider).loaded, isFalse);
    final state = await _ready(c);
    expect(state.loaded, isTrue);
    expect(state.mode, WebConnectionMode.local);
    expect(state.computerUrl, isNull);
    expect(state.records, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(secrets.values, isEmpty);
  });

  test('plain LAN QR saves one record without PIN, query, cookies or secure data', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    await c.read(webConnectionProvider.notifier).connectQr('http://192.168.2.73:3090', label: 'Office PC');
    final state = c.read(webConnectionProvider);
    expect(state.mode, WebConnectionMode.computer);
    expect(state.computerUrl, 'http://192.168.2.73:3090');
    expect(state.records.single.label, 'Office PC');
    expect(state.records.single.baseUrl, 'http://192.168.2.73:3090');
    expect(state.records.single.lastUsed.isUtc, isTrue);
    expect(secrets.values, isEmpty);
    final saved = await _saved();
    expect(saved['mode'], 'computer');
    expect(saved['selectedId'], state.records.single.id);
    expect((saved['records'] as List).single.keys, unorderedEquals(['id', 'label', 'baseUrl', 'lastUsed']));
  });

  test('valid port endpoints and case-sensitive paths remain usable', () async {
    final c = _container(MemorySecretStore());
    final controller = c.read(webConnectionProvider.notifier);
    for (final url in ['http://localhost:1/Case', 'https://192.168.0.1:65535/Case', 'http://[::1]:65535/Case']) {
      await controller.connectComputer(url);
      expect(c.read(webConnectionProvider).computerUrl, url);
    }
    expect(c.read(webConnectionProvider).records, hasLength(3));
  });

  test('query and fragment live only in memory and per-record secure storage', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    const url = 'https://PC.EXAMPLE:443/dsh/a%2Fb?token=secret-test%2Bvalue&pin=123456#auth=fragment-test';
    await c.read(webConnectionProvider.notifier).connectComputer(url);
    final state = c.read(webConnectionProvider);
    final record = state.records.single;
    expect(record.baseUrl, 'https://pc.example/dsh/a%2Fb');
    expect(record.label, 'pc.example');
    expect(state.computerUrl, contains('secret-test'));
    expect(secrets.values[WebConnectionController.secretKey(record.id)], state.computerUrl);
    final prefs = await SharedPreferences.getInstance();
    final allPrefs = jsonEncode({for (final key in prefs.getKeys()) key: prefs.get(key)});
    for (final privatePart in ['secret-test', 'fragment-test', '123456', 'token=', 'pin=', '?', '#']) {
      expect(allPrefs, isNot(contains(privatePart)));
    }
  });

  test('computer restart restores matching full URL from secure storage without writes', () async {
    final secrets = MemorySecretStore();
    final first = _container(secrets);
    await first.read(webConnectionProvider.notifier).connectComputer('https://pc.test/app?token=test#login');
    final before = (await SharedPreferences.getInstance()).getString(WebConnectionController.prefsKey);
    final second = _container(secrets);
    final restored = await _ready(second);
    expect(restored.mode, WebConnectionMode.computer);
    expect(restored.computerUrl, 'https://pc.test/app?token=test#login');
    expect(restored.records.single.id, first.read(webConnectionProvider).records.single.id);
    expect((await SharedPreferences.getInstance()).getString(WebConnectionController.prefsKey), before);
  });

  for (final stored in [
    null,
    'http://other.test/?token=foreign',
    'https://pc.test/other?token=stale',
    'javascript:bad',
  ]) {
    test('missing or mismatched secure URL falls back to base ($stored)', () async {
      _seed([_record('pc', 'https://pc.test/app')], selectedId: 'pc');
      final secrets = MemorySecretStore({WebConnectionController.secretKey('pc'): ?stored});
      final state = await _ready(_container(secrets));
      expect(state.mode, WebConnectionMode.computer);
      expect(state.computerUrl, 'https://pc.test/app');
    });
  }

  test('lost secure storage still restores base URL for cookie or PIN login', () async {
    _seed([_record('pc', 'https://pc.test/app')], selectedId: 'pc');
    expect((await _ready(_container(_UnavailableSecrets()))).computerUrl, 'https://pc.test/app');
  });

  test('new bare address needs no secure-store implementation', () async {
    final c = _container(_UnavailableSecrets());
    await c.read(webConnectionProvider.notifier).connectComputer('http://pc.test:3090');
    expect(c.read(webConnectionProvider).computerUrl, 'http://pc.test:3090');
  });

  test('multiple computers survive local mode and a restart', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('http://first.test:3090?token=one', label: 'First');
    await controller.connectComputer('https://second.test', label: 'Second');
    final ids = c.read(webConnectionProvider).records.map((record) => record.id).toList();
    expect(ids, hasLength(2));
    await controller.setLocal();
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
    expect(c.read(webConnectionProvider).computerUrl, isNull);
    final restarted = await _ready(_container(secrets));
    expect(restarted.mode, WebConnectionMode.local);
    expect(restarted.records.map((record) => record.id), ids);
    expect(secrets.values.values.single, contains('token=one'));
  });

  test('record reconnect restores its URL and updates order and lastUsed', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('http://first.test?token=first', label: 'First');
    final first = c.read(webConnectionProvider).records.single;
    await controller.connectComputer('http://second.test', label: 'Second');
    await controller.connectRecord(first.id);
    final state = c.read(webConnectionProvider);
    expect(state.computerUrl, 'http://first.test?token=first');
    expect(state.records.first.id, first.id);
    expect(state.records.first.lastUsed.isAfter(first.lastUsed), isTrue);
    expect(state.records.first.label, 'First');
    expect(state.records, hasLength(2));
    expect((await _saved())['selectedId'], first.id);
  });

  test('canonical host and effective port deduplicate one origin while updating path and label', () async {
    final c = _container(MemorySecretStore());
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('HTTP://PC.EXAMPLE:00080/one?token=one', label: 'Old');
    final id = c.read(webConnectionProvider).records.single.id;
    await controller.connectComputer('http://pc.example/two', label: 'New');
    expect(c.read(webConnectionProvider).records.single.id, id);
    expect(c.read(webConnectionProvider).records.single.label, 'New');
    expect(c.read(webConnectionProvider).records.single.baseUrl, 'http://pc.example/two');
    await controller.connectComputer('http://PC.example:80/three');
    expect(c.read(webConnectionProvider).records.single.label, 'New');
    await controller.connectComputer('https://pc.example:443/');
    await controller.connectComputer('https://pc.example:8443/');
    expect(c.read(webConnectionProvider).records, hasLength(3));
  });

  for (final pair in [
    ['http://[0:0:0:0:0:0:0:1]:3090/', 'http://[::1]:3090/'],
    ['https://[2001:DB8:0:0:1:0:0:1]:443', 'https://[2001:db8::1:0:0:1]'],
    ['http://[::ffff:192.0.2.1]:80', 'http://[0:0:0:0:0:ffff:c000:201]'],
  ]) {
    test('equivalent numeric IPv6 hosts share a record (${pair.first})', () async {
      final c = _container(MemorySecretStore());
      final controller = c.read(webConnectionProvider.notifier);
      await controller.connectComputer(pair.first);
      final first = c.read(webConnectionProvider).records.single;
      await controller.connectComputer(pair.last);
      expect(c.read(webConnectionProvider).records.single.id, first.id);
      expect(c.read(webConnectionProvider).records.single.baseUrl, first.baseUrl);
    });
  }

  test('replacing a full login URL with a bare URL clears only that record secret', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('http://first.test/?token=one');
    final first = c.read(webConnectionProvider).records.single;
    await controller.connectComputer('http://second.test/?token=two');
    final second = c.read(webConnectionProvider).records.first;
    await controller.connectComputer('http://first.test/');
    expect(secrets.values.containsKey(WebConnectionController.secretKey(first.id)), isFalse);
    expect(secrets.values[WebConnectionController.secretKey(second.id)], contains('token=two'));
    expect((await _ready(_container(secrets))).computerUrl, 'http://first.test/');
  });

  test('removing inactive and active records clears secrets without dangling computer mode', () async {
    final secrets = MemorySecretStore();
    final c = _container(secrets);
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('http://first.test/?token=one');
    final first = c.read(webConnectionProvider).records.single;
    await controller.connectComputer('http://second.test/?token=two');
    final second = c.read(webConnectionProvider).records.first;
    await controller.removeRecord(first.id);
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.computer);
    expect(c.read(webConnectionProvider).computerUrl, 'http://second.test/?token=two');
    expect(secrets.values.containsKey(WebConnectionController.secretKey(first.id)), isFalse);
    await controller.removeRecord(second.id);
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
    expect(c.read(webConnectionProvider).computerUrl, isNull);
    expect(c.read(webConnectionProvider).records, isEmpty);
    expect(secrets.values, isEmpty);
    expect((await _ready(_container(secrets))).mode, WebConnectionMode.local);
  });

  test('local choice during a delayed restore is never overwritten by old computer state', () async {
    _seed([_record('pc', 'http://pc.test/')], selectedId: 'pc');
    final secrets = _DelayedSecrets({WebConnectionController.secretKey('pc'): 'http://pc.test/?token=old'})
      ..readGate = Completer<void>();
    final c = _container(secrets);
    final observed = <WebConnectionMode>[];
    c.listen(webConnectionProvider, (_, next) => observed.add(next.mode), fireImmediately: true);
    await secrets.readStarted.future;
    final local = c.read(webConnectionProvider.notifier).setLocal();
    secrets.readGate!.complete();
    await local;
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
    expect(observed, everyElement(WebConnectionMode.local));
    expect(c.read(webConnectionProvider).records.single.id, 'pc');
    expect((await _saved())['mode'], 'local');
  });

  test('slow secure write cannot overwrite a later local selection', () async {
    final secrets = _DelayedSecrets()..writeGate = Completer<void>();
    final c = _container(secrets);
    final controller = c.read(webConnectionProvider.notifier);
    final connect = controller.connectComputer('http://pc.test/?token=new');
    await secrets.writeStarted.future;
    final local = controller.setLocal();
    secrets.writeGate!.complete();
    await Future.wait([connect, local]);
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
    expect(c.read(webConnectionProvider).computerUrl, isNull);
    expect((await _saved())['mode'], 'local');
  });

  test('actions before ready preserve restored records and execute in requested order', () async {
    _seed([_record('saved', 'http://saved.test')], mode: 'local');
    final c = _container(MemorySecretStore());
    final controller = c.read(webConnectionProvider.notifier);
    await Future.wait([
      controller.connectComputer('http://first.test'),
      controller.connectComputer('http://second.test'),
      controller.setLocal(),
    ]);
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
    expect(c.read(webConnectionProvider).records.map((record) => record.baseUrl), [
      'http://second.test',
      'http://first.test',
      'http://saved.test',
    ]);
  });

  test('failed secret write exposes a stable error and does not poison later actions', () async {
    final c = _container(_UnavailableSecrets());
    final controller = c.read(webConnectionProvider.notifier);
    await expectLater(
      controller.connectComputer('http://pc.test/?token=private'),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'web_connection_secret_save_failed')),
    );
    expect(c.read(webConnectionProvider).records, isEmpty);
    expect((await SharedPreferences.getInstance()).containsKey(WebConnectionController.prefsKey), isFalse);
    await controller.connectComputer('http://plain.test');
    expect(c.read(webConnectionProvider).computerUrl, 'http://plain.test');
  });

  test('secret deletion failure leaves the record intact and later local selection works', () async {
    _seed([_record('pc', 'http://pc.test')], selectedId: 'pc');
    final c = _container(_UnavailableSecrets());
    final controller = c.read(webConnectionProvider.notifier);
    await controller.ready;
    await expectLater(
      controller.removeRecord('pc'),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'web_connection_secret_delete_failed')),
    );
    expect(c.read(webConnectionProvider).records.single.id, 'pc');
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.computer);
    await controller.setLocal();
    expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
  });

  test('unknown records fail clearly, removal is idempotent, current state remains', () async {
    final c = _container(MemorySecretStore());
    final controller = c.read(webConnectionProvider.notifier);
    await controller.connectComputer('http://pc.test');
    await expectLater(controller.connectRecord('missing'), throwsA(isA<StateError>()));
    await controller.removeRecord('missing');
    expect(c.read(webConnectionProvider).computerUrl, 'http://pc.test');
    expect(c.read(webConnectionProvider).records, hasLength(1));
  });

  test('corrupt settings and invalid selected ids recover locally without writes', () async {
    SharedPreferences.setMockInitialValues({WebConnectionController.prefsKey: '{broken'});
    expect((await _ready(_container(MemorySecretStore()))).mode, WebConnectionMode.local);
    expect((await SharedPreferences.getInstance()).getString(WebConnectionController.prefsKey), '{broken');
    _seed([_record('pc', 'http://pc.test')], selectedId: 'missing');
    final state = await _ready(_container(MemorySecretStore()));
    expect(state.mode, WebConnectionMode.local);
    expect(state.records.single.id, 'pc');
  });

  test('load filters bad records, strips plaintext query and deduplicates origins', () async {
    _seed([
      _record('old', 'HTTP://PC.TEST:80/old', used: '2025-01-01T00:00:00Z'),
      _record('new', 'http://pc.test/new?token=legacy'),
      _record('bad', 'file:///secret'),
      _record('bad-date', 'http://other.test', used: 'not-a-date'),
    ], mode: 'local');
    final state = await _ready(_container(MemorySecretStore()));
    expect(state.records.single.id, 'new');
    expect(state.records.single.baseUrl, 'http://pc.test/new');
  });

  test('escaped path and query delimiters survive normalization without credential leakage', () async {
    final c = _container(MemorySecretStore());
    await c
        .read(webConnectionProvider.notifier)
        .connectComputer('https://pc.test/a%2Fb/%25%3F%23?token=a%2Bb%3D#x%23y');
    expect(c.read(webConnectionProvider).records.single.baseUrl, 'https://pc.test/a%2Fb/%25%3F%23');
    expect(c.read(webConnectionProvider).computerUrl, 'https://pc.test/a%2Fb/%25%3F%23?token=a%2Bb%3D#x%23y');
  });

  for (final input in [
    '',
    '   ',
    '192.168.2.73:3090',
    '//pc.test',
    'file:///tmp',
    'ftp://pc.test',
    'javascript:alert(1)',
    'dsh://connect?host=pc',
    '{"url":"http://pc.test"}',
    'http://',
    'http:///path',
    'http://user:private@pc.test',
    'http://@pc.test',
    'http://user%40pc.test',
    'http://pc.test\\path',
    'http://pc.test/\n',
    '\thttp://pc.test',
    'http://pc.test/\u007f',
    'http://pc.test:0',
    'http://pc.test:65536',
    'http://pc.test:',
    'http://pc.test:-1',
    'http://pc.test:+80',
    'http://pc.test:port',
    'http://pc.test:80:90',
    'http://pc.test:99999999999999999999',
    'http://bad_host',
    'http://-bad.test',
    'http://bad..test',
    'http://256.1.1.1',
    'http://127.1',
    'http://[::1',
    'http://::1',
    'http://[::gg]',
    'http://[::1]:0',
    'http://[fe80::1%25eth0]',
    'http://pc.test/%ZZ',
    'http://pc.test/?q=%',
    'http://pc.test/a b',
  ]) {
    test('invalid QR is rejected without persisting or echoing input (${input.hashCode})', () async {
      final secrets = MemorySecretStore();
      final c = _container(secrets);
      final controller = c.read(webConnectionProvider.notifier);
      await controller.ready;
      await expectLater(
        controller.connectQr(input),
        throwsA(
          isA<FormatException>()
              .having((error) => error.message, 'message', 'Invalid HTTP(S) computer address.')
              .having((error) => error.source, 'source', isNull),
        ),
      );
      expect(c.read(webConnectionProvider).mode, WebConnectionMode.local);
      expect(c.read(webConnectionProvider).records, isEmpty);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(secrets.values, isEmpty);
    });
  }
}
