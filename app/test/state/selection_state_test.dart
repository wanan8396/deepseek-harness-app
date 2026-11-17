import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _remote = '{"kind":"relay","id":"saved-mac"}';

final class _Starts extends ProviderObserver {
  final providers = <Object>{};
  final failures = <Object>[];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) => providers.add(context.provider);

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) => failures.add(error);
}

class _DelayedPreferences extends InMemorySharedPreferencesStore {
  _DelayedPreferences(super.data) : super.withData();

  final requested = Completer<void>();
  final reply = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    final saved = await super.getAll();
    requested.complete();
    await reply.future;
    return saved;
  }
}

Future<void> _settle(ProviderContainer container) async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.value();
    await container.pump();
  }
}

ProviderContainer _open([_Starts? starts]) {
  final container = ProviderContainer(observers: [?starts]);
  addTearDown(container.dispose);
  return container;
}

Future<_DelayedPreferences> _delay(Map<String, Object> values) async {
  final original = SharedPreferencesStorePlatform.instance;
  final store = _DelayedPreferences({for (final entry in values.entries) 'flutter.${entry.key}': entry.value});
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  addTearDown(() {
    if (!store.reply.isCompleted) store.reply.complete();
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('current selection initializes only canonical selection providers, with no overrides', () async {
    SharedPreferences.setMockInitialValues({
      'active_host': HostRef.local.encode(),
      'last_session_selection': jsonEncode({'host': 'local:local', 'sessionId': 'saved-local'}),
    });
    final starts = _Starts();
    final container = _open(starts);
    expect(container.read(currentSessionProvider), isNull);
    await _settle(container);
    expect(container.read(currentSessionProvider), 'saved-local');
    container.read(currentSessionProvider.notifier).select('chosen-local');
    container.read(currentSessionProvider.notifier).select(null);
    await _settle(container);
    expect(container.read(currentSessionProvider), isNull);
    expect(container.read(currentSessionProvider.notifier).selectionRevision, 2);
    // An exhaustive observer set catches even a provider that starts and then
    // disposes; importing legacy providers just to assert exists is unnecessary.
    expect(starts.providers, {
      currentSessionProvider,
      activeHostProvider,
    });
    expect(starts.failures, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('last_session_selection')!), {'host': 'local:local', 'sessionId': null});
    expect(prefs.containsKey('last_session_id'), isFalse);
  });

  test('an explicit already-null new chat wins over a genuinely delayed preferences restore', () async {
    final store = await _delay({
      'active_host': HostRef.local.encode(),
      'last_session_selection': jsonEncode({'host': 'local:local', 'sessionId': 'late-saved'}),
      'last_session_id': 'legacy-leftover',
    });
    final container = _open();
    final seen = <String?>[];
    container.listen(currentSessionProvider, (_, next) => seen.add(next), fireImmediately: true);
    await store.requested.future;
    final controller = container.read(currentSessionProvider.notifier);
    expect(container.read(currentSessionProvider), isNull);
    controller.select(null);
    expect(controller.selectionRevision, 1);
    store.reply.complete();
    await _settle(container);
    expect(container.read(currentSessionProvider), isNull);
    expect(seen, [null]);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('last_session_selection')!), {'host': 'local:local', 'sessionId': null});
    expect(prefs.getString('last_session_id'), 'legacy-leftover');
    final restarted = _open();
    restarted.read(currentSessionProvider);
    await _settle(restarted);
    expect(restarted.read(currentSessionProvider), isNull);
  });

  test('a chosen session wins over delayed bound selection restoration', () async {
    final store = await _delay({
      'active_host': HostRef.local.encode(),
      'last_session_selection': jsonEncode({'host': 'local:local', 'sessionId': 'late-saved'}),
    });
    final container = _open();
    container.read(currentSessionProvider);
    await store.requested.future;
    container.read(currentSessionProvider.notifier).select('chosen');
    store.reply.complete();
    await _settle(container);
    expect(container.read(currentSessionProvider), 'chosen');
    expect(container.read(currentSessionProvider.notifier).selectionRevision, 1);
  });

  test('disposing before the delayed preference reply never publishes a conversation', () async {
    final store = await _delay({'last_session_selection': jsonEncode({'host': 'local:local', 'sessionId': 'late-saved'})});
    final container = ProviderContainer();
    final seen = <String?>[];
    container.listen(currentSessionProvider, (_, next) => seen.add(next), fireImmediately: true);
    await store.requested.future;
    container.dispose();
    store.reply.complete();
    for (var i = 0; i < 16; i++) {
      await Future<void>.value();
    }
    expect(seen, [null]);
  });




  test('Lite active host stays local without initializing or reading remote auto-connect prefs', () async {
    final store = await _delay({
      'active_host': _remote,
      'remote_auto_connect_on_startup': true,
    });
    final starts = _Starts();
    final container = _open(starts);
    container.read(activeHostProvider);
    expect(container.read(activeHostProvider), HostRef.local);
    expect(store.requested.isCompleted, isFalse);
    expect(starts.providers, {activeHostProvider});
    expect(starts.failures, isEmpty);
  });

  for (final paired in [false, true]) {
    test('Lite never migrates a saved ${paired ? 'paired' : 'legacy'} remote ID to the local host', () async {
      final savedHost = _remote;
      SharedPreferences.setMockInitialValues({
        'active_host': savedHost,
        'remote_auto_connect_on_startup': true,
        'last_session_id': 'remote-legacy',
        if (paired) 'last_session_selection': jsonEncode({'host': 'relay:saved-mac', 'sessionId': 'remote-paired'}),
      });
      final starts = _Starts();
      final container = _open(starts);
      container.read(currentSessionProvider);
      await _settle(container);
      expect(container.read(currentSessionProvider), isNull);
      expect(container.read(activeHostProvider), HostRef.local);
      expect(starts.providers, {currentSessionProvider, activeHostProvider});
      expect(starts.failures, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_host'), savedHost);
      expect(prefs.getString('last_session_id'), 'remote-legacy');
      expect(prefs.getBool('remote_auto_connect_on_startup'), isTrue);
    });
  }

  test('unbound local preferences are ignored and never removed when choosing a conversation', () async {
    SharedPreferences.setMockInitialValues({'active_host': HostRef.local.encode(), 'last_session_id': 'unbound'});
    final container = _open();
    container.read(currentSessionProvider);
    await _settle(container);
    expect(container.read(currentSessionProvider), isNull);
    container.read(currentSessionProvider.notifier).select('current');
    await _settle(container);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_session_id'), 'unbound');
    expect(prefs.getString('active_host'), HostRef.local.encode());
    expect(jsonDecode(prefs.getString('last_session_selection')!), {'host': 'local:local', 'sessionId': 'current'});
  });
}
