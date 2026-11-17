import 'dart:async';

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_app/ui/web/local_web_screen.dart';
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/lite_harness.dart';

class _Runtime extends LocalRuntimeController {
  _Runtime(this.initial);
  final RuntimeStatus initial;
  int starts = 0;
  Completer<void>? startGate;

  @override
  LocalRuntimeState build() => LocalRuntimeState(loaded: true, status: initial);

  @override
  Future<void> start() async {
    starts++;
    await startGate?.future;
  }

  void report(RuntimeStatus status) => state = LocalRuntimeState(loaded: true, status: status);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Lite waiting failure and lifecycle boundaries', () {
    testWidgets('native start acknowledgement followed by asynchronous error never restarts itself', (tester) async {
      final runtime = _Runtime(const RuntimeStatus(phase: RuntimePhase.installed));
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.starting));
      await pumpFrames(tester, 2);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.error, error: 'fixture_async_failure'));
      await pumpFrames(tester, 2);
      expect(find.byKey(const ValueKey('local-web-retry')), findsOneWidget);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester, 12);
      expect(runtime.starts, 1);
      expect(find.byKey(const ValueKey('local-web-retry')), findsOneWidget);
      expect(find.byIcon(AppIcons.engine), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a restored error is manual-only and repeated taps share one pending start', (tester) async {
      final runtime = _Runtime(const RuntimeStatus(phase: RuntimePhase.error, error: 'fixture_restored_failure'));
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 0);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester);
      expect(runtime.starts, 0);
      runtime.startGate = Completer<void>();
      final retry = find.byKey(const ValueKey('local-web-retry'));
      // Two events before a frame rebuild must not issue two platform starts.
      await tester.tap(retry);
      await tester.tap(retry);
      expect(runtime.starts, 1);
      await pumpFrames(tester, 2);
      expect(retry, findsNothing);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.starting));
      runtime.startGate!.complete();
      await pumpFrames(tester, 2);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.error, error: 'fixture_retry_failure'));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(retry, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening while the old run stops waits for installed then starts exactly once', (tester) async {
      final runtime = _Runtime(const RuntimeStatus(phase: RuntimePhase.stopping));
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester, 2);
      expect(runtime.starts, 0);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(find.byKey(const ValueKey('local-web-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure-strike guard does not auto start but still offers an explicit retry', (tester) async {
      final runtime = _Runtime(const RuntimeStatus(phase: RuntimePhase.installed, autoSafe: false, strikes: 2));
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 0);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const ValueKey('local-web-retry')));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting home keeps only the bottom settings handle and root Back exits', (tester) async {
      usePhoneView(tester);
      final runtime = _Runtime(const RuntimeStatus(phase: RuntimePhase.starting));
      var exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(
        testApp(
          LocalWebScreen(
            handleAtBottom: true,
            handle: (size) => WebHandleButton(size: size, onSidebar: () {}),
          ),
          overrides: ShellHarness(runtime: () => runtime).overrides,
        ),
      );
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('web-controls-bottom')), findsOneWidget);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(find.byIcon(AppIcons.engine), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsNothing);
      expect(find.byKey(const ValueKey('web-controls-bottom')), findsNothing);
      expect(runtime.starts, 0);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, 2);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
