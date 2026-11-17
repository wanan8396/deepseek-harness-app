import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/links/launcher_entries.dart' as launcher;
import 'package:dsh_app/links/launcher_models.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart' as legacy;
import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/local_connection_state.dart';
import 'package:dsh_app/state/local_web_sessions_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _row(
  String id,
  int updated, {
  String? title = 'Title',
  bool cold = false,
  bool blank = false,
  bool child = false,
}) => {
  'sessionId': id,
  'updatedAt': updated,
  'running': false,
  'blank': blank,
  'origin': child ? 'subagent' : null,
  'agentAvailable': !cold,
  if (!cold)
    'projections': {
      'kind': 'sequenced',
      'asOfSeq': 1,
      'values': {'title': title},
    },
};

Map<String, Object?> _folded(String? title, {bool blank = false}) => {
  'kind': 'sequenced',
  'asOfSeq': 2,
  'values': {
    'title': title,
    'sessionListMetadata': {'blank': blank},
  },
};

class _Carrier extends DshCarrier {
  final calls = <String>[];
  final link = _Link();
  List<Map<String, Object?>> rows = [];
  final held = <(String, Completer<Object?>)>[];
  final folded = <String, Object?>{};
  bool holdTitles = false;
  bool failLists = false;
  bool failTitles = false;
  Completer<Object?>? listReply;
  int outstanding = 0;
  int peak = 0;

  @override
  String get kind => 'recording-official-recent';
  @override
  DshTracer? get tracer => null;
  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async {
    calls.add(endpoint);
    switch (endpoint) {
      case 'session/list':
        if (failLists) return const RpcError(DshRemoteException('gateway/internal', 'fixture list failure'));
        return RpcOk(listReply == null ? {'items': rows} : await listReply!.future);
      case 'session/projections':
        final id = (args['request'] as Map)['sessionId'] as String;
        outstanding++;
        if (outstanding > peak) peak = outstanding;
        try {
          if (failTitles) return const RpcError(DshRemoteException('gateway/internal', 'fixture title failure'));
          if (holdTitles) {
            final reply = Completer<Object?>();
            held.add((id, reply));
            return RpcOk(await reply.future);
          }
          return RpcOk(folded[id]);
        } finally {
          outstanding--;
        }
      default:
        fail('unexpected RPC: $endpoint');
    }
  }

  @override
  Future<DshMuxLink> openLink(MuxOptions options) async => link;
  @override
  Future<void> close() async {}
}

class _Link implements DshMuxLink {
  late DshMuxFrameHandler onFrame;
  final streams = <String, String>{};
  final cancelled = <String>[];
  bool baseline = true;
  List<String> archived = [];

  @override
  void start({required DshMuxFrameHandler onFrame, required DshMuxLossHandler onLost}) => this.onFrame = onFrame;
  @override
  void open(String streamId, String endpoint, Map<String, Object?> payload) {
    streams[streamId] = endpoint;
    scheduleMicrotask(() {
      if (endpoint == r'$events') {
        item(streamId, {
          'type': 'ready',
          'clientId': 'fixture',
          'host': {'home': '/root'},
        });
      } else if (endpoint == 'workspace/follow') {
        if (baseline) {
          workspace({
            'type': 'baseline',
            'value': {'items': [], 'archivedSessionIds': archived},
          });
        }
      } else {
        fail('unexpected stream: $endpoint');
      }
    });
  }

  void item(String id, Object? value) => onFrame({'type': 'item', 'streamId': id, 'value': value});
  void workspace(Map<String, Object?> value) {
    for (final entry in streams.entries.where((entry) => entry.value == 'workspace/follow')) {
      if (!cancelled.contains(entry.key)) item(entry.key, value);
    }
  }

  void event(String event, List<Object?> args) => item(
    streams.entries.firstWhere((entry) => entry.value == r'$events').key,
    {'type': 'emit', 'event': event, 'args': args},
  );
  @override
  void cancel(String streamId) => cancelled.add(streamId);
  @override
  Future<void> close(int code, String reason) async {}
  @override
  void sendItem(String streamId, Object? value) {}
  @override
  void endUplink(String streamId) {}
}

class _Official extends OfficialLocalConnectionController {
  _Official(this.connection);
  final HostConnection? connection;
  @override
  Future<HostConnection?> build() async => connection;
  void replace(HostConnection? connection) => state = AsyncData(connection);
  void loading() => state = const AsyncLoading();
  void failConnection() => state = AsyncError(StateError('fixture'), StackTrace.current);
}

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => const LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:9', token: 'fixture'),
  );
}

class _Destination extends WebConnectionController {
  @override
  WebConnectionState build() => const WebConnectionState(loaded: true);
  void computer() => state = const WebConnectionState(loaded: true, mode: WebConnectionMode.computer);
}

Future<void> _settle([int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Carrier host;
  late DshClient client;
  late ProviderContainer container;
  late DateTime clock;
  ProviderContainer start() {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        officialLocalConnectionProvider.overrideWith(() => _Official(HostConnection(client: client, isLocal: true))),
        localWebTitleClockProvider.overrideWithValue(() => clock),
      ],
    );
    container.listen(localWebRecentShortcutsProvider, (_, _) {});
    return container;
  }

  List<RecentShortcut>? getRecents() => container.read(localWebRecentShortcutsProvider);
  List<String>? ids() => getRecents()?.map((row) => row.sessionId).toList();
  Future<void> refresh() async {
    await container.read(localWebRecentShortcutsProvider.notifier).refresh();
    await _settle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 12);
    host = _Carrier();
    client = DshClient.withCarrier(host);
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    for (final (_, reply) in host.held) {
      if (!reply.isCompleted) reply.complete(null);
    }
    await _settle();
    await client.close();
  });

  test('real official list is sorted, filtered and limited; stale hidden-session prefs have no effect', () async {
    SharedPreferences.setMockInitialValues({
      'companion_sessions': jsonEncode({
        'local:null': {'id': 'companion'},
        'ssh:box': {'id': 'other-host'},
      }),
    });
    host.rows = [
      _row('older', 1),
      _row('third', 3, title: '   '),
      _row('new', 5, title: '  New  '),
      _row('second', 4),
      _row('blank', 10, blank: true),
      _row('child', 11, child: true),
      _row('archived', 12),
      _row('companion', 13),
      _row('', 20),
    ];
    host.link.archived = ['archived'];
    start();
    expect(getRecents(), isNull);
    await _settle();
    expect(ids(), ['companion', 'new', 'second']);
    expect(getRecents()!.map((row) => row.title), ['Title', 'New', 'Title']);
    host.rows.removeWhere((row) => row['sessionId'] == 'companion');
    await refresh();
    expect(ids(), ['new', 'second', 'third']);
    expect(getRecents()!.map((row) => row.title), ['New', 'Title', '未命名对话']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('companion_sessions'), isNotNull);
    expect(getRecents()!.every((row) => row.host == HostRef.local), isTrue);
    expect(host.calls, ['session/list', 'session/list']);
    expect(host.link.streams.values.toSet(), {r'$events', 'workspace/follow'});
  });

  test('unknown archive inventory, loading and failures stay null; confirmed empty is []', () async {
    host.link.baseline = false;
    start();
    await _settle();
    expect(getRecents(), isNull);
    host.link.workspace({
      'type': 'baseline',
      'value': {'items': [], 'archivedSessionIds': []},
    });
    await _settle();
    expect(getRecents(), isEmpty);
    host.failLists = true;
    await refresh();
    expect(getRecents(), isNull);
    host.failLists = false;
    host.listReply = Completer<Object?>();
    final pending = refresh();
    expect(getRecents(), isNull);
    host.listReply!.complete({'items': []});
    await pending;
    expect(getRecents(), isEmpty);
    final owner = container.read(officialLocalConnectionProvider.notifier) as _Official;
    owner.loading();
    await _settle();
    expect(getRecents(), isNull);
    owner.failConnection();
    await _settle();
    expect(getRecents(), isNull);
    owner.replace(null);
    await _settle();
    expect(getRecents(), isNull);
  });

  test('official archive and replace frames update shortcuts without mutation RPCs', () async {
    host.rows = [_row('a', 2), _row('b', 1)];
    start();
    await _settle();
    expect(ids(), ['a', 'b']);
    host.link.workspace({
      'type': 'archived',
      'archivedSessionIds': ['a'],
    });
    await _settle();
    expect(ids(), ['b']);
    host.link.workspace({
      'type': 'replace',
      'value': {
        'items': [],
        'archivedSessionIds': ['b'],
      },
    });
    await _settle();
    expect(ids(), ['a']);
    expect(host.calls, ['session/list']);
  });

  test('host events reread the official inventory', () async {
    host.rows = [_row('before', 1)];
    start();
    await _settle();
    host.rows = [_row('after', 2)];
    host.link.event('api-session/status', ['before', false]);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await _settle();
    expect(ids(), ['after']);
    expect(host.calls, ['session/list', 'session/list']);
  });

  test('projection reads cap at two outstanding and forty rows, hide folded blanks', () async {
    host.rows = [for (var i = 0; i < 45; i++) _row('s$i', 100 - i, cold: true)];
    host.holdTitles = true;
    start();
    await _settle();
    expect(host.held.map((read) => read.$1), ['s0', 's1']);
    for (var i = 0; i < 40; i++) {
      final (id, reply) = host.held[i];
      reply.complete(_folded('  $id title  ', blank: id == 's0'));
      await _settle();
    }
    expect(host.peak, 2);
    expect(host.held, hasLength(40));
    expect(ids(), ['s1', 's2', 's3']);
    expect(getRecents()!.first.title, 's1 title');
    expect(host.calls.toSet(), {'session/list', 'session/projections'});
  });

  test('late projection from an older row never overwrites a newer row', () async {
    host.rows = [_row('a', 1, cold: true)];
    host.holdTitles = true;
    start();
    await _settle();
    host.rows = [_row('a', 2, cold: true)];
    await refresh();
    expect(host.held, hasLength(1));
    host.held[0].$2.complete(_folded('stale title', blank: true));
    await _settle();
    expect(ids(), ['a']);
    expect(getRecents()!.single.title, '未命名对话');
    expect(host.held, hasLength(2));
    host.held[1].$2.complete(_folded('current title'));
    await _settle();
    expect(getRecents()!.single.title, 'current title');
  });

  test('retired same-client reads occupy slots but never land in the next inventory', () async {
    host.rows = [_row('old-a', 3, cold: true), _row('old-b', 2, cold: true)];
    host.holdTitles = true;
    start();
    await _settle();
    final owner = container.read(officialLocalConnectionProvider.notifier) as _Official;
    owner.replace(null);
    await _settle();
    host.rows = [_row('new', 4, cold: true)];
    owner.replace(HostConnection(client: client, isLocal: true));
    await _settle();
    expect(host.held, hasLength(2));
    host.held[0].$2.complete(_folded('old title'));
    await _settle();
    expect(host.held, hasLength(3));
    expect(ids(), ['new']);
    host.held[2].$2.complete(_folded('new title'));
    await _settle();
    expect(getRecents()!.single.title, 'new title');
    expect(host.peak, 2);
  });

  test('real mux reconnect retires pending projections without freeing their two slots', () async {
    host.rows = [_row('old-a', 3, cold: true), _row('old-b', 2, cold: true)];
    host.holdTitles = true;
    start();
    await _settle();
    final generation = client.mux.generation;
    host.rows = [_row('new', 4, cold: true)];
    client.mux.reconnect();
    await client.mux.ready();
    await _settle(40);
    expect(client.mux.generation, isNotNull);
    expect(client.mux.generation, isNot(same(generation)));
    expect(host.held, hasLength(2));
    host.held[0].$2.complete(_folded('stale title'));
    await _settle();
    expect(host.held, hasLength(3));
    expect(ids(), ['new'], reason: 'streams=${host.link.streams} cancelled=${host.link.cancelled} calls=${host.calls}');
    host.held[2].$2.complete(_folded('after reconnect'));
    await _settle();
    expect(getRecents()!.single.title, 'after reconnect');
    expect(host.peak, 2);
  });

  test('projection failures retry next list then back off; changed rows retry at once', () async {
    host.rows = [_row('a', 1, cold: true)];
    host.failTitles = true;
    start();
    await _settle();
    await refresh();
    expect(host.calls.where((call) => call == 'session/projections'), hasLength(2));
    await refresh();
    expect(host.calls.where((call) => call == 'session/projections'), hasLength(2));
    clock = clock.add(const Duration(seconds: 15));
    await refresh();
    expect(host.calls.where((call) => call == 'session/projections'), hasLength(3));
    host.rows = [_row('a', 2, cold: true)];
    host.failTitles = false;
    host.folded['a'] = _folded('recovered');
    await refresh();
    expect(host.calls.where((call) => call == 'session/projections'), hasLength(4));
    expect(getRecents()!.single.title, 'recovered');
  });

  test('actual official owner switches to computer with no native account/bot/companion owners', () async {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        webConnectionProvider.overrideWith(_Destination.new),
        localRuntimeProvider.overrideWith(_Runtime.new),
        networkKicksProvider.overrideWithValue(const Stream.empty()),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async => client),
      ],
    );
    container.listen(localWebRecentShortcutsProvider, (_, _) {});
    host.rows = [_row('a', 1)];
    await _settle();
    expect(ids(), ['a']);
    (container.read(webConnectionProvider.notifier) as _Destination).computer();
    await _settle();
    expect(getRecents(), isNull);
    expect(host.calls, ['session/list']);
    expect(container.exists(legacy.activeConnectionProvider), isFalse);
    expect(container.exists(legacy.localConnectionProvider), isFalse);
    expect(container.exists(settingsProvider), isFalse);
  });

  test('Lite legacy API forwards to neutral provider and remains overridable', () async {
    const row = RecentShortcut(sessionId: 'fixture', title: 'Fixture', host: HostRef.local);
    container = ProviderContainer(
      overrides: [
        localWebRecentShortcutsProvider.overrideWith(() => _Recents([row])),
      ],
    );
    expect(container.read(launcher.recentShortcutsProvider), [row]);
    expect(container.exists(legacy.activeConnectionProvider), isFalse);
  });
}

class _Recents extends LocalWebRecentShortcutsController {
  _Recents(this.rows);
  final List<RecentShortcut>? rows;
  @override
  List<RecentShortcut>? build() => rows;
}
