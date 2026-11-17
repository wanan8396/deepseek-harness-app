import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/ui/launch/launch_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lite web-style launch', () {
    for (final dark in [false, true]) {
      testWidgets('animated cover without loading UI in ${dark ? 'dark' : 'light'} mode', (tester) async {
        final controller = LaunchController(
          snapshot: LaunchSnapshot(systemSplash: false, dark: dark, coldEngine: true),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(body: LaunchOverlay(controller: controller)),
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('lite-launch-stage')), findsOneWidget);
        expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
        expect(find.byKey(const ValueKey('local-web-startup-tagline')), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(controller.reduced, isFalse);
        controller.ready(waitsForEngine: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump();
        expect(controller.phase, LaunchPhase.gone);
        expect(find.byKey(const ValueKey('lite-launch-stage')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
