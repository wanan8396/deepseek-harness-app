import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/ui/web/startup_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('Android splash handoff reveals onto the original animated StartupStage', (tester) async {
    usePhone(tester);
    final channel = FakeLaunchChannel();
    final controller = LaunchController(snapshot: snapshotFor(systemSplash: true), channel: channel);
    addTearDown(controller.dispose);
    await tester.pumpWidget(launchApp(controller));
    await tester.pump();

    expect(controller.phase, LaunchPhase.cover);
    expect(channel.marks, ['firstFrame']);
    expect(find.byType(StartupStage), findsOneWidget);
    final cover = tester.widget<Image>(find.byKey(const ValueKey('local-web-startup-cover')));
    expect(cover.image, StartupCover.image);

    final handoff = controller.handOver();
    await tester.pump();
    await tester.pump();
    await handoff;
    expect(channel.calls, contains('reveal'));
    expect(channel.marks, containsAllInOrder(['firstFrame', 'handedOver']));
    expect(controller.phase, LaunchPhase.playing);
    expect(find.byType(StartupCover), findsOneWidget);

    controller.ready(waitsForEngine: false);
    await tester.pump();
    expect(controller.phase, LaunchPhase.leaving);
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(controller.phase, LaunchPhase.gone);
    expect(channel.calls, contains('done'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('native removal skips reveal and starts the retained cover immediately', (tester) async {
    usePhone(tester);
    final channel = FakeLaunchChannel();
    final controller = LaunchController(snapshot: snapshotFor(systemSplash: true), channel: channel);
    addTearDown(controller.dispose);
    await tester.pumpWidget(launchApp(controller));
    await tester.pump();
    await controller.handOver(removed: true);
    await tester.pump();

    expect(controller.phase, LaunchPhase.playing);
    expect(channel.calls, isNot(contains('reveal')));
    expect(channel.marks, containsAllInOrder(['firstFrame']));
    expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
  });

  testWidgets('first-frame-only devices start immediately and the splash fallback is bounded', (tester) async {
    usePhone(tester);
    final firstFrameOnly = LaunchController(snapshot: snapshotFor(systemSplash: false), channel: FakeLaunchChannel());
    addTearDown(firstFrameOnly.dispose);
    await tester.pumpWidget(launchApp(firstFrameOnly));
    await tester.pump();
    expect(firstFrameOnly.phase, LaunchPhase.playing);
    expect(find.byType(StartupStage), findsOneWidget);

    final channel = FakeLaunchChannel();
    final fallback = LaunchController(snapshot: snapshotFor(systemSplash: true), channel: channel);
    addTearDown(fallback.dispose);
    await tester.pumpWidget(launchApp(fallback));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 699));
    expect(fallback.phase, LaunchPhase.cover);
    await tester.pump(const Duration(milliseconds: 1));
    expect(fallback.phase, LaunchPhase.playing);
    fallback.ready(waitsForEngine: false);
    await tester.pump();
    expect(fallback.phase, LaunchPhase.leaving);
  });

  testWidgets('ready shortens an unclaimed splash wait to the handoff grace period', (tester) async {
    usePhone(tester);
    final controller = LaunchController(snapshot: snapshotFor(systemSplash: true), channel: FakeLaunchChannel());
    addTearDown(controller.dispose);
    await tester.pumpWidget(launchApp(controller));
    await tester.pump();
    controller.ready(waitsForEngine: false);
    await tester.pump(const Duration(milliseconds: 199));
    expect(controller.phase, LaunchPhase.cover);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.phase, LaunchPhase.leaving);
  });
}
