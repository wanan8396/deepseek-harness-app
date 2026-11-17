// 冷启动与热启动：系统启动画面交接、默认运动、引擎就绪与轻点跳过都按实际帧序验证。

import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/ui/launch/launch_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late FakeLaunchChannel channel;
  setUp(() => channel = FakeLaunchChannel());

  /// Without a system splash, the original cover stage starts on the first frame.
  Future<LaunchController> start(
    WidgetTester tester, {
    required bool cold,
    bool? reduceMotion,
    bool systemSplash = false,
  }) async {
    usePhone(tester);
    final c = LaunchController(
      snapshot: snapshotFor(systemSplash: systemSplash, coldEngine: cold),
      channel: channel,
    );
    await tester.pumpWidget(launchApp(c, reduceMotion: reduceMotion));
    await tester.pump();
    return c;
  }

  /// Advances [ms] in 20 ms frames, so animations and timers land in order.
  Future<void> wait(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 20) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  test('begin says whether the engine is starting cold', () async {
    final cold = await LaunchSnapshot.fromMap({'active': true, 'coldEngine': true});
    expect(cold!.coldEngine, isTrue);
    final warm = await LaunchSnapshot.fromMap({'active': true});
    expect(warm!.coldEngine, isFalse);
  });

  group('cold start', () {
    testWidgets('plays the whole motion although the app was ready early, then goes at once', (tester) async {
      final c = await start(tester, cold: true);
      expect(c.phase, LaunchPhase.playing);
      await wait(tester, 200);
      c.ready();
      await tester.pump();
      expect(c.phase, LaunchPhase.playing);
      expect(c.holds, isTrue);
      await wait(tester, 1100);
      expect(c.phase, LaunchPhase.playing);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      await wait(tester, 120);
      expect(c.phase, LaunchPhase.leaving);
      await wait(tester, launchLeaveDuration.inMilliseconds + 40);
      expect(c.phase, LaunchPhase.gone);
    });

    testWidgets('the engine up before the motion ends: it goes then', (tester) async {
      final c = await start(tester, cold: true);
      await wait(tester, 200);
      c.ready();
      await wait(tester, 300);
      expect(c.phase, LaunchPhase.playing);
      c.engineReady();
      await tester.pump();
      expect(c.phase, LaunchPhase.leaving);
      expect(channel.marks, containsAllInOrder(['firstFrame', 'ready', 'engine']));
    });

    testWidgets('the engine up before the app is ready: ready goes at once', (tester) async {
      final c = await start(tester, cold: true);
      c.engineReady();
      await wait(tester, 100);
      c.ready();
      await tester.pump();
      expect(c.phase, LaunchPhase.leaving);
    });

    testWidgets('a first page on a remote host does not wait for this phone engine', (tester) async {
      final c = await start(tester, cold: true);
      await wait(tester, 100);
      c.ready(waitsForEngine: false);
      await tester.pump();
      expect(c.phase, LaunchPhase.leaving);
      // The cover's own interval is still armed while it plays; the fade to gone is what
      // releases it, so the test must not end with that timer pending.
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      expect(c.phase, LaunchPhase.gone);
    });

    testWidgets('Android 12+: waits for the splash before playing, then plays it all', (tester) async {
      final c = await start(tester, cold: true, systemSplash: true);
      c.ready();
      await wait(tester, 300);
      expect(c.phase, LaunchPhase.cover);
      await c.handOver(removed: true);
      await tester.pump();
      expect(c.phase, LaunchPhase.playing);
      await wait(tester, 1300);
      expect(c.phase, LaunchPhase.playing);
      await wait(tester, 100);
      expect(c.phase, LaunchPhase.leaving);
    });

    testWidgets('a tap skips the default motion, even before the app is ready', (tester) async {
      final c = await start(tester, cold: true);
      await wait(tester, 300);
      await tester.tap(find.byKey(LaunchOverlay.skipKey));
      await tester.pump();
      expect(c.phase, LaunchPhase.leaving);
      await wait(tester, launchLeaveDuration.inMilliseconds + 40);
      expect(c.phase, LaunchPhase.gone);
    });
  });

  group('no waiting', () {



    testWidgets('warm start (the engine already ran): goes the moment the app is ready', (tester) async {
      final c = await start(tester, cold: false);
      await wait(tester, 200);
      c.ready();
      await tester.pump();
      expect(c.holds, isFalse);
      expect(c.phase, LaunchPhase.leaving);
    });

    testWidgets('reduced motion leaves a warm startup when the app is ready', (tester) async {
      final c = await start(tester, cold: false, reduceMotion: true);
      await wait(tester, 200);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      c.ready();
      await tester.pump();
      expect(c.phase, LaunchPhase.gone);
    });

    testWidgets('减少动画 on a cold start: nothing plays, nothing is waited for', (tester) async {
      final c = await start(tester, cold: true, reduceMotion: true);
      await tester.pump();
      expect(c.reduced, isTrue);
      await wait(tester, 100);
      c.ready();
      await tester.pump();
      expect(c.phase, LaunchPhase.gone);
    });

    testWidgets('system reduced motion arriving late releases a held cold start', (tester) async {
      usePhone(tester);
      final c = LaunchController(
        snapshot: snapshotFor(systemSplash: false, coldEngine: true),
        channel: channel,
      );
      await tester.pumpWidget(launchApp(c));
      await tester.pump();
      c.ready();
      await wait(tester, 200);
      expect(c.phase, LaunchPhase.playing);
      await tester.pumpWidget(launchApp(c, reduceMotion: true));
      await tester.pump();
      await tester.pump();
      expect(c.phase, isIn([LaunchPhase.leaving, LaunchPhase.gone]));
    });
  });
}
