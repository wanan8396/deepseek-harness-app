import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/ios/ios_local_engine_page.dart';
import 'package:dsh_app/ui/onboarding/runtime_setup_page.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/lite_harness.dart';

const _channel = MethodChannel('dsh/ios-local');
const _start = ValueKey('ios-local-start-probe');
const _refresh = ValueKey('ios-local-refresh');
const _loaderPassed = <String, Object?>{
  'dshLoaderBooted': true,
  'serviceVerified': true,
  'disposeVerified': true,
  'badBaselineRejected': true,
  'engineReady': false,
};
const _corePassed = <String, Object?>{
  'coreBooted': true,
  'servicesVerified': true,
  'firstTurnStreamed': true,
  'secondTurnHistoryVerified': true,
  'cancellationSettled': true,
  'errorSettled': true,
  'disposeVerified': true,
  'badBaselineRejected': true,
  'ephemeral': true,
  'engineReady': false,
};

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

  test('starting status survives the native method codec and strict parser', () {
    final raw = const StandardMethodCodec().decodeEnvelope(
      const StandardMethodCodec().encodeSuccessEnvelope(_status(state: 'starting')),
    );
    final status = IosLocalProbeStatus.fromMap(raw);
    expect(status.state, IosProbeState.starting);
    expect(status.reason, isNull);
    expect(status.compatible, isFalse);
  });

  test('absent validation reports retain the original probe-only status', () {
    final status = IosLocalProbeStatus.fromMap(_status());
    expect(status.loaderChecks, isNull);
    expect(status.coreChecks, isNull);
  });

  test('validation parser keeps only fixed checks and preserves three states', () {
    final status = IosLocalProbeStatus.fromMap(_status(report: {
      'loader': {
        'engineReady': false,
        'dshLoaderBooted': true,
        'serviceVerified': false,
        'disposeVerified': null,
        'unknownPrivateCheck': true,
        'path': '/private/loader-parser-fixture',
      },
      'core': {
        'engineReady': false,
        'ephemeral': true,
        'coreBooted': true,
        'servicesVerified': false,
        'firstTurnStreamed': null,
        'secondTurnHistoryVerified': 'true',
        'badBaselineRejected': false,
        'modelKind': 'private-model-kind-parser-fixture',
        'providerId': 'private-provider-parser-fixture',
        'token': 'private-core-parser-fixture',
        'unknownPrivateCheck': false,
      },
    }));
    expect(status.loaderChecks, {
      'dshLoaderBooted': true,
      'serviceVerified': false,
      'disposeVerified': null,
      'badBaselineRejected': null,
    });
    expect(status.coreChecks, {
      'coreBooted': true,
      'servicesVerified': false,
      'firstTurnStreamed': null,
      'secondTurnHistoryVerified': null,
      'cancellationSettled': null,
      'errorSettled': null,
      'disposeVerified': null,
      'badBaselineRejected': false,
      'ephemeral': true,
    });
    expect(status.compatible, isFalse);
  });

  test('each nested validation report requires explicit engineReady false', () {
    for (final group in ['loader', 'core']) {
      final good = group == 'loader' ? _loaderPassed : _corePassed;
      for (final value in [true, null, 'false']) {
        expect(
          () => IosLocalProbeStatus.fromMap(_status(report: {
            group: {...good, 'engineReady': value},
          })),
          throwsFormatException,
          reason: '$group engineReady=$value',
        );
      }
      final missing = Map<String, Object?>.of(good)..remove('engineReady');
      expect(
        () => IosLocalProbeStatus.fromMap(_status(report: {group: missing})),
        throwsFormatException,
        reason: '$group missing engineReady',
      );
      expect(
        () => IosLocalProbeStatus.fromMap(_status(report: {group: 'invalid report'})),
        throwsFormatException,
      );
    }
  });

  test('a core report requires its explicit in-memory marker', () {
    for (final value in [false, null, 'true']) {
      expect(
        () => IosLocalProbeStatus.fromMap(_status(report: {
          'core': {..._corePassed, 'ephemeral': value},
        })),
        throwsFormatException,
      );
    }
    final missing = Map<String, Object?>.of(_corePassed)..remove('ephemeral');
    expect(
      () => IosLocalProbeStatus.fromMap(_status(report: {'core': missing})),
      throwsFormatException,
    );
  });

  _testIosWidgets('reads native status and starts only an explicit local probe', (tester) async {
    final started = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'startProbe') {
        final reply = await started.future;
        return reply;
      }
      return _status();
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
    await tester.pump();
    await _frames(tester);
    final statusLabel = find.byKey(const ValueKey('ios-local-status'));
    await tester.ensureVisible(statusLabel);
    expect(
      tester.widget<Text>(statusLabel).data,
      '正在运行本地探针',
      reason: tester.widget<Text>(find.byKey(const ValueKey('ios-local-detail'))).data,
    );
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
    expect(find.byKey(const ValueKey('ios-local-loader-section')), findsNothing);
    expect(find.byKey(const ValueKey('ios-local-core-section')), findsNothing);
    expect(find.byType(RuntimeSetupPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('Loader and core tables render passed failed and unchecked independently', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady',
      nodeVersion: '24.22.1',
      compatible: true,
      report: {
        'loader': {
          'engineReady': false,
          'dshLoaderBooted': true,
          'serviceVerified': false,
          'disposeVerified': null,
        },
        'core': {
          'engineReady': false,
          'ephemeral': true,
          'coreBooted': true,
          'servicesVerified': false,
          'firstTurnStreamed': null,
        },
      },
    ));
    await _mount(tester);
    expect(find.byKey(const ValueKey('ios-local-loader-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('ios-local-core-section')), findsOneWidget);
    final expected = {
      'ios-local-loader-dshLoaderBooted': '通过',
      'ios-local-loader-serviceVerified': '未通过',
      'ios-local-loader-disposeVerified': '未检测',
      'ios-local-loader-badBaselineRejected': '未检测',
      'ios-local-core-coreBooted': '通过',
      'ios-local-core-servicesVerified': '未通过',
      'ios-local-core-firstTurnStreamed': '未检测',
      'ios-local-core-secondTurnHistoryVerified': '未检测',
      'ios-local-core-cancellationSettled': '未检测',
      'ios-local-core-errorSettled': '未检测',
      'ios-local-core-disposeVerified': '未检测',
      'ios-local-core-badBaselineRejected': '未检测',
      'ios-local-core-ephemeral': '通过',
    };
    for (final entry in expected.entries) {
      expect(tester.widget<Text>(find.byKey(ValueKey(entry.key))).data, entry.value);
    }
    expect(find.text('内嵌 Node.js 探针已完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('unknown private report fields never render or choose the fixture model label', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady',
      nodeVersion: '24.22.1',
      compatible: true,
      report: {
        'loader': {
          ..._loaderPassed,
          'unknownPrivateCheck': true,
          'paths': ['/private/loader-ui-fixture'],
          'token': 'private-loader-token-fixture',
        },
        'core': {
          ..._corePassed,
          'unknownPrivateCheck': true,
          'providerId': 'private-provider-ui-fixture',
          'modelId': 'private-model-ui-fixture',
          'paths': ['/private/core-ui-fixture'],
          'token': 'private-core-token-fixture',
          'errorCode': 'private-error-ui-fixture',
        },
        'privateUnknownReport': {'token': 'private-outer-token-fixture'},
      },
    ));
    await _mount(tester);
    expect(find.textContaining('unknownPrivateCheck'), findsNothing);
    expect(find.textContaining('/private/'), findsNothing);
    expect(find.textContaining('private-'), findsNothing);
    expect(find.textContaining('固定离线测试模型'), findsOneWidget);
    expect(find.textContaining('不发起模型 API 调用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('passing Node and Loader remain visible when core validation fails', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady',
      nodeVersion: '24.22.1',
      compatible: true,
      report: {
        'capabilities': {'sqlite': true},
        'loader': _loaderPassed,
        'core': {..._corePassed, 'firstTurnStreamed': false, 'errorSettled': false},
      },
    ));
    await _mount(tester);
    expect(find.text('内嵌 Node.js 探针已完成'), findsOneWidget);
    expect(find.textContaining('Node.js 版本与已检测能力符合当前要求'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-loader-dshLoaderBooted'))).data, '通过');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-firstTurnStreamed'))).data, '未通过');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-errorSettled'))).data, '未通过');
    expect(find.byKey(const ValueKey('ios-local-dsh-not-started')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('a failed core bad baseline remains visible after the other core checks pass', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady',
      nodeVersion: '24.22.1',
      compatible: true,
      report: {
        'loader': _loaderPassed,
        'core': {..._corePassed, 'badBaselineRejected': false, 'stage': 'negative'},
      },
    ));
    await _mount(tester);
    for (final key in [
      'coreBooted', 'servicesVerified', 'firstTurnStreamed', 'secondTurnHistoryVerified',
      'cancellationSettled', 'errorSettled', 'disposeVerified',
    ]) {
      expect(tester.widget<Text>(find.byKey(ValueKey('ios-local-core-$key'))).data, '通过');
    }
    expect(find.text('核心错误启动基线已拦截'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-badBaselineRejected'))).data, '未通过');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-loader-badBaselineRejected'))).data, '通过');
    expect(find.text('DSH 本机引擎未启动'), findsOneWidget);
    expect(find.byKey(const ValueKey('ios-local-engine-page')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  _testIosWidgets('all Loader and core checks passing still leaves the whole engine not ready', (tester) async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return _status(
        state: 'probeReady',
        nodeVersion: '24.22.1',
        compatible: true,
        report: {'loader': _loaderPassed, 'core': _corePassed},
      );
    });
    await _mount(tester);
    expect(find.byKey(const ValueKey('ios-local-engine-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
    expect(find.text('DSH 本机引擎未启动'), findsOneWidget);
    expect(find.textContaining('仅使用内存存储和固定离线测试模型'), findsOneWidget);
    expect(find.textContaining('仍不代表完整本机引擎已就绪或可正式聊天'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-ephemeral'))).data, '通过');
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(RuntimeSetupPage), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    expect(calls.map((call) => call.method), ['getStatus']);
    expect(calls.every((call) => call.arguments == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final group in ['loader', 'core']) {
    for (final readiness in ['true', 'missing']) {
      _testIosWidgets('$group engineReady $readiness is a visible contract failure', (tester) async {
        final report = Map<String, Object?>.of(group == 'loader' ? _loaderPassed : _corePassed);
        if (readiness == 'true') {
          report['engineReady'] = true;
        } else {
          report.remove('engineReady');
        }
        messenger.setMockMethodCallHandler(_channel, (_) async => _status(
          state: 'probeReady', nodeVersion: '24.22.1', compatible: true,
          report: {group: report},
        ));
        await _mount(tester);
        expect(find.textContaining('此安装包的本机运行时状态不可用'), findsOneWidget);
        expect(find.byKey(const ValueKey('ios-local-loader-section')), findsNothing);
        expect(find.byKey(const ValueKey('ios-local-core-section')), findsNothing);
        expect(find.byType(RuntimeSetupPage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

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
    await tester.pump();
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

  _testIosWidgets('English validation tables preserve three states and fit large text', (tester) async {
    AppLocale.use(AppLocale.en);
    tester.view.physicalSize = const Size(640, 1136);
    messenger.setMockMethodCallHandler(_channel, (_) async => _status(
      state: 'probeReady', nodeVersion: '24.22.1', compatible: true,
      report: {
        'loader': {..._loaderPassed, 'serviceVerified': false, 'disposeVerified': null},
        'core': {..._corePassed, 'servicesVerified': false, 'firstTurnStreamed': null},
      },
    ));
    await _mount(tester, page: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
        child: const IosLocalEnginePage(),
      ),
    ));
    expect(find.text('Official DSH Loader validation'), findsOneWidget);
    expect(find.text('DSH core validation (offline)'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-loader-dshLoaderBooted'))).data, 'Passed');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-loader-serviceVerified'))).data, 'Not passed');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-loader-disposeVerified'))).data, 'Not checked');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-coreBooted'))).data, 'Passed');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-servicesVerified'))).data, 'Not passed');
    expect(tester.widget<Text>(find.byKey(const ValueKey('ios-local-core-firstTurnStreamed'))).data, 'Not checked');
    expect(find.textContaining('not a real model provider'), findsOneWidget);
    expect(find.textContaining('No model API calls are made'), findsOneWidget);
    expect(find.text('On-device DSH engine has not started'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(_refresh));
    expect(tester.widget<OutlinedButton>(find.byKey(_refresh)).onPressed, isNotNull);
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
