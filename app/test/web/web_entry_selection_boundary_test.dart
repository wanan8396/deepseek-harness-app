// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/links/launcher_entries.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart' as legacy;
import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/local_connection_state.dart';
import 'package:dsh_app/state/local_web_sessions_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/web/web_home.dart';
import 'package:dsh_app/ui/web/web_target.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart' show pumpFrames, testApp, usePhoneView;
import 'support/fake_webview.dart';

final class _Starts extends ProviderObserver {
  final providers = <Object>{};

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) => providers.add(context.provider);
}

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => const LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:3080', token: 'fixture'),
  );
}

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

class _Carrier extends DshCarrier {
  final calls = <String>[];
  final link = _Link();

  @override
  String get kind => 'recording-web-entry';
  @override
  DshTracer? get tracer => null;
  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) async {
    calls.add(endpoint);
    if (endpoint != 'session/list') fail('unexpected RPC: $endpoint');
    return const RpcOk({'items': []});
  }

  @override
  Future<DshMuxLink> openLink(MuxOptions options) async => link;
  @override
  Future<void> close() async {}
}

class _Link implements DshMuxLink {
  late DshMuxFrameHandler onFrame;
  final endpoints = <String>[];

  @override
  void start({required DshMuxFrameHandler onFrame, required DshMuxLossHandler onLost}) => this.onFrame = onFrame;
  @override
  void open(String streamId, String endpoint, Map<String, Object?> payload) {
    endpoints.add(endpoint);
    scheduleMicrotask(() {
      final Object value;
      if (endpoint == r'$events') {
        value = {
          'type': 'ready',
          'clientId': 'fixture',
          'host': {'home': '/root'},
        };
      } else if (endpoint == 'workspace/follow') {
        value = {
          'type': 'baseline',
          'value': {'items': [], 'archivedSessionIds': []},
        };
      } else {
        fail('unexpected stream: $endpoint');
      }
      onFrame({'type': 'item', 'streamId': streamId, 'value': value});
    });
  }

  @override
  void cancel(String streamId) {}
  @override
  Future<void> close(int code, String reason) async {}
  @override
  void sendItem(String streamId, Object? value) {}
  @override
  void endUplink(String streamId) {}
}

Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('WebHome and launcher selection consumers import only their current local owners', () {
    final home = File('lib/ui/web/web_home.dart').readAsStringSync();
    expect(home, contains("import '../../state/selection_state.dart';"));

    expect(home, isNot(contains("import '../../state/hosts_state.dart'")));
    expect(home, isNot(contains("import '../../state/sessions_state.dart'")));
    final launcher = File('lib/links/launcher_entries.dart').readAsStringSync();
    // Recent shortcuts now come from the local Web session inventory.
    expect(launcher, contains("import '../state/local_web_sessions_state.dart';"));
    expect(launcher, isNot(contains("import '../state/hosts_state.dart'")));
    // No native session-feed graph is retained.
    expect(launcher, isNot(contains("import '../state/sessions_state.dart';")));
  });

  testWidgets('Lite queued local shortcut opens the real page and callback without legacy provider initialization', (
    tester,
  ) async {
    usePhoneView(tester);
    SharedPreferences.setMockInitialValues({
      'active_host': jsonEncode({'kind':'ssh','id':'old-host'}),
      'last_session_id': 'remote-old-id',
    });
    final native = <MethodCall>[];
    const channel = MethodChannel('dsh/shortcuts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final starts = _Starts();
    final carrier = _Carrier();
    final client = DshClient.withCarrier(carrier);
    final container = ProviderContainer(
      observers: [starts],
      overrides: [
        localRuntimeProvider.overrideWith(_Runtime.new),
        settingsProvider.overrideWith(_Settings.new),
        networkKicksProvider.overrideWithValue(const Stream.empty()),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async => client),
      ],
    );
    addTearDown(container.dispose);
    final bridge = container.read(launcherBridgeProvider);
    // The real NativeInbox buffers this recorded entry until WebEntryHost mounts.
    bridge.add(const OpenChatEntry(HostRef.local, 'local-shortcut'));
    final platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: testApp(const WebHome())));
    await _frames(tester);
    expect(platform.controllers, hasLength(1));
    final page = platform.controller;
    expect(page.loads.single.host, '127.0.0.1');
    page.finish();
    await _frames(tester);
    expect(container.read(currentSessionProvider), 'local-shortcut');
    expect(page.scripts, contains(const DshWebTarget(sessionId: 'local-shortcut').openScript));
    expect(native.where((call) => call.method == 'ready'), hasLength(1));
    expect(native.where((call) => call.method == 'setRecent'), hasLength(1));
    expect(container.exists(officialLocalConnectionProvider), isTrue);
    expect(container.exists(localWebRecentShortcutsProvider), isTrue);
    expect(carrier.calls, ['session/list']);
    expect(carrier.link.endpoints.toSet(), {r'$events', 'workspace/follow'});
    for (final provider in <Object>[legacy.activeConnectionProvider, legacy.localConnectionProvider]) {
      expect(starts.providers, isNot(contains(provider)), reason: '$provider unexpectedly initialized');
    }
    page.post('DshAppState', jsonEncode({'session': 'page-selected'}));
    await pumpFrames(tester, 3);
    expect(container.read(currentSessionProvider), 'page-selected');
    expect(
      page.scripts.where((script) => script == const DshWebTarget(sessionId: 'page-selected').openScript),
      isEmpty,
    );
    expect(LauncherEntry.parse({'kind':'chat','sessionId':'remote-shortcut','host':jsonEncode({'kind':'ssh','id':'old-host'})}), isNull);
    await pumpFrames(tester, 3);
    expect(container.read(currentSessionProvider), 'page-selected');
    expect(platform.controllers, hasLength(1));
    expect(page.loads, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

}
