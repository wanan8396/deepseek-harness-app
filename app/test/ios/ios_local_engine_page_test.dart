import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/ios/ios_local_engine_page.dart';
import 'package:dsh_app/ui/onboarding/runtime_setup_page.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/lite_harness.dart';

const _channel = MethodChannel('dsh/ios-local');
const _start = ValueKey('ios-local-start-probe');
const _refresh = ValueKey('ios-local-refresh');

Map<String, Object?> _status({
  String state = 'idle',
  String? nodeVersion,
  bool compatible = false,
  String? reason,
  Map<String, Object?> report = const {},
}) => {
  'state': state,
  'nodeVersion': nodeVersion,
  'dshVersion': '0.2.2-rc.3',
  'requiredNode': '>=24.9.0',
  'engineReady': false,
  'compatible': compatible,
  'reason': reason,
  'report': report,
  'appBackgrounded': false,
};

Future<void> _frames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mount(WidgetTester tester, {Widget page = const IosLocalEnginePage()}) async {
  await tester.pumpWidget(testApp(page));
  await _frames(tester);
}

// The variant restores the platform before Flutter verifies its debug globals;
// package:test tearDown runs too late for that invariant.
void _testIosWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(780, 1688);
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.view.reset();
    }
  }, variant: TargetPlatformVariant.only(platform));
}

class _LocalDestination extends WebConnectionController {
  @override
  WebConnectionState build() {
    ready = Future<void>.value();
    return const WebConnectionState(loaded: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    AppLocale.use(AppLocale.zhCN);
    calls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return _status();
    });
  });

  tearDown(() {
    AppLocale.use(AppLocale.zhCN);
    messenger.setMockMethodCallHandler(_channel, null);
  });

  _testIosWidgets('reads native status and starts only an explicit local probe', (tester) async {
    final started = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return call.method == 'startProbe' ? started.future : _status();
    });
    await _mount(tester);
    expect(calls.map((call) => call.method), ['getStatus']);
    await tester.ensureVisible(find.byKey(_start));
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(calls.map((call) => call.method), ['getStatus', 'startProbe']);
    expect(calls.every((call) => call.arguments == null), isTrue);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    started.complete(_status(state: 'starting'));
    await messenger.platformMessagesFinished;
    await _frames(tester);
    final statusLabel = find.byKey(const ValueKey('ios-local-status'));
    await tester.ensureVisible(statusLabel);
    expect(tester.widget<Text>(statusLabel).data, '正在运行本地探针');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('compatible Node smoke is not an installed or running DSH engine', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady',
      nodeVersion: '24.22.1',
      compatible: true,
      report: {
        'capabilities': {'sqlite': true, 'unknownPrivateCapability': true},
        'token': 'private-token-must-not-render',
        'path': '/private/probe-must-not-render',
      },
    ));
    await _mount(tester);
    expect(find.text('内嵌 Node.js 探针已完成'), findsOneWidget);
    expect(find.textContaining('DSH 本机引擎未启动'), findsOneWidget);
    expect(find.textContaining('DSH 引擎适配仍在验证'), findsOneWidget);
    expect(find.textContaining('Node.js：24.22.1'), findsOneWidget);
    expect(find.textContaining('版本未满足'), findsNothing);
    expect(find.textContaining('private-token'), findsNothing);
    expect(find.textContaining('/private/probe'), findsNothing);
    expect(find.textContaining('unknownPrivateCapability'), findsNothing);
    expect(find.byType(RuntimeSetupPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('version incompatibility is reported only by its native reason', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady', nodeVersion: '18.20.4', reason: 'node_version',
    ));
    await _mount(tester);
    expect(find.textContaining('版本未满足 DSH 要求'), findsOneWidget);
    expect(find.text('本地探针尚未就绪'), findsOneWidget);
    expect(find.byKey(const ValueKey('ios-local-dsh-not-started')), findsOneWidget);
  });

  for (final reason in ['node_capabilities', 'probe_failed', 'probe_timeout', 'runtime_unavailable', 'unknown_reason']) {
    _testIosWidgets('native $reason remains an explicit local failure', (tester) async {
      messenger.setMockMethodCallHandler(_channel, (_) async => _status(state: 'error', reason: reason));
      await _mount(tester);
      expect(find.text('本地探针尚未就绪'), findsOneWidget);
      expect(find.byKey(_refresh), findsOneWidget);
      expect(find.byType(RuntimeSetupPage), findsNothing);
      expect(find.text('连接电脑'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  _testIosWidgets('a missing bridge is visible instead of Ubuntu installation', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => throw MissingPluginException('iOS fixture'));
    await _mount(tester);
    await messenger.platformMessagesFinished;
    await _frames(tester);
    expect(find.textContaining('此安装包的本机运行时状态不可用'), findsOneWidget);
    expect(find.byType(RuntimeSetupPage), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(_refresh)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('malformed or falsely ready native replies fail closed', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => {..._status(), 'engineReady': true});
    await _mount(tester);
    expect(find.textContaining('此安装包的本机运行时状态不可用'), findsOneWidget);
    expect(find.byType(RuntimeSetupPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('status requests have a bounded wait and recover through refresh', (tester) async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (_) => pending.future);
    await _mount(tester);
    await tester.pump(const Duration(seconds: 11));
    await _frames(tester);
    expect(find.textContaining('读取或运行探针已超时'), findsOneWidget);
    pending.complete(_status());
    messenger.setMockMethodCallHandler(_channel, (_) async => _status());
    await tester.ensureVisible(find.byKey(_refresh));
    await tester.tap(find.byKey(_refresh));
    await _frames(tester);
    expect(find.text('本地探针尚未运行'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNotNull);
  });

  _testIosWidgets('starting polls at 500ms and stops after native completion', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return calls.length < 3
          ? _status(state: 'starting')
          : _status(state: 'probeReady', nodeVersion: '24.22.1', compatible: true);
    });
    await _mount(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await _frames(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await _frames(tester);
    expect(calls, hasLength(3));
    expect(find.text('内嵌 Node.js 探针已完成'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, hasLength(3));
    await tester.pumpWidget(const SizedBox());
  });

  _testIosWidgets('iOS RootGate bypasses both Android runtime and saved remote state', (tester) async {
    await tester.pumpWidget(testApp(const RootGate(), overrides: [
      webConnectionProvider.overrideWith(() => throw StateError('iOS read computer state')),
      localRuntimeProvider.overrideWith(() => throw StateError('iOS read Android runtime')),
      settingsProvider.overrideWith(() => throw StateError('iOS read Android settings')),
    ]));
    await _frames(tester);
    expect(find.byType(IosLocalEnginePage), findsOneWidget);
    expect(calls.map((call) => call.method), ['getStatus']);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('iOS retains the RootGate test-only home override', (tester) async {
    await _mount(tester, page: const RootGate(home: Scaffold(body: Text('test home'))));
    expect(find.text('test home'), findsOneWidget);
    expect(calls, isEmpty);
  });

  _testIosWidgets('Android RootGate retains its existing local path', (tester) async {
    await tester.pumpWidget(goldenApp(
      home: const RootGate(home: Scaffold(body: Text('Android home'))),
      brightness: Brightness.light,
      overrides: [
        webConnectionProvider.overrideWith(_LocalDestination.new),
        localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(
          loaded: true, status: RuntimeStatus(phase: RuntimePhase.installed),
        ))),
        settingsProvider.overrideWith(() => FakeSettings()),
      ],
    ));
    await _frames(tester);
    expect(find.text('Android home'), findsOneWidget);
    expect(find.byType(IosLocalEnginePage), findsNothing);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  }, platform: TargetPlatform.android);

  _testIosWidgets('the probe UI also renders English without changing native meaning', (tester) async {
    AppLocale.use(AppLocale.en);
    await _mount(tester);
    expect(find.text('Run local probe'), findsOneWidget);
    expect(find.text('On-device DSH engine has not started'), findsOneWidget);
    expect(find.textContaining('remote engine'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('English branding and controls fit a narrow large-text viewport', (tester) async {
    AppLocale.use(AppLocale.en);
    tester.view.physicalSize = const Size(640, 1136);
    await _mount(tester, page: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
        child: const IosLocalEnginePage(),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(_start));
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
