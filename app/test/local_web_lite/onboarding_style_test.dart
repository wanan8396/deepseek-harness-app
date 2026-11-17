// Real Flutter widget previews, not device captures. Run with:
// DSH_TEST_FONT_DIR=<Noto CJK directory> flutter test --no-pub
//   test/local_web_lite/onboarding_style_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/state/access_state.dart';
import 'package:dsh_app/ui/access/lite_permissions_page.dart';
import 'package:dsh_app/ui/launch/launch_overlay.dart';
import 'package:dsh_app/ui/onboarding/onboarding_flow.dart';
import 'package:dsh_app/ui/onboarding/onboarding_scaffold.dart';
import 'package:dsh_app/ui/onboarding/welcome_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/support.dart';
import '../support/lite_harness.dart';

const _preview = ValueKey('onboarding-widget-preview');

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  Brightness brightness, {
  FakeAccessDriver? driver,
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    goldenApp(
      home: RepaintBoundary(key: _preview, child: page),
      brightness: brightness,
      overrides: [if (driver != null) ...accessOverrides(driver)],
    ),
  );
  final context = tester.element(find.byKey(_preview));
  // Decode the actual bundled assets before capturing, not an empty image frame.
  await tester.runAsync(() async {
    for (final suffix in ['', '-dark']) {
      for (final name in ['whale', 'wordmark']) {
        await precacheImage(AssetImage('assets/branding/$name$suffix.png'), context);
      }
    }
  });
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_preview));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final file = File('build/local-web-shots/widget-preview-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Color _ink(Brightness brightness) => brightness == Brightness.dark ? const Color(0xfff3f3f4) : const Color(0xff18181b);

void _expectCard(WidgetTester tester, Brightness brightness) {
  final material = tester.widget<Material>(find.byKey(const ValueKey('lite-onboarding-card')).first);
  final shape = material.shape! as RoundedRectangleBorder;
  expect(shape.borderRadius, BorderRadius.circular(12));
  expect(shape.side.width, 1);
  expect(shape.side.color, brightness == Brightness.dark ? const Color(0xff343437) : const Color(0xffe4e4e7));
  expect(material.color, brightness == Brightness.dark ? const Color(0xff202022) : Colors.white);
  expect(find.byType(GlassSurface), findsNothing);
  expect(find.byType(BackdropFilter), findsNothing);
}

void _expectPrimary(WidgetTester tester, Key key, Brightness brightness) {
  final context = tester.element(find.byKey(key));
  final style = FilledButtonTheme.of(context).style!;
  expect(style.backgroundColor!.resolve({}), _ink(brightness));
  expect((style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(12));
  expect(tester.widget<FilledButton>(find.byKey(key)).onPressed, isNotNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));


  group('lite onboarding styling and retained actions', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets('Welcome first button and whale brand ($mode)', (tester) async {
        var starts = 0;
        await _pump(
          tester,
          OnboardingFlow(
            step: OnboardingStep.welcome,
            onWelcomeDone: () => starts++,
            onRuntimeDone: () {},
          ),
          brightness,
        );
        expect(find.byType(WelcomePage), findsOneWidget);
        expect(find.byKey(const ValueKey('lite-brand-whale')), findsOneWidget);
        expect(find.byKey(const ValueKey('lite-brand-wordmark')), findsOneWidget);
        expect(find.byType(AppBackdrop), findsNothing);
        final scaffold = tester.widget<Scaffold>(find.byKey(const ValueKey('lite-onboarding-scaffold')));
        expect(
          scaffold.backgroundColor,
          brightness == Brightness.dark ? const Color(0xff151517) : const Color(0xfff7f8fa),
        );
        _expectPrimary(tester, const ValueKey('lite-welcome-start'), brightness);
        await _shot(tester, 'welcome-$mode');
        await tester.tap(find.byKey(const ValueKey('lite-welcome-start')));
        expect(starts, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('single permission card, icon, grant and continue remain functional ($mode)', (tester) async {
        final driver = FakeAccessDriver(
          offPhone,
          answer: (item, now) => item == AccessItem.storage ? readingsWith(now, storage: true) : now,
        );
        var done = 0;
        await _pump(tester, LitePermissionsPage(onDone: () => done++), brightness, driver: driver);
        _expectCard(tester, brightness);
        _expectPrimary(tester, const ValueKey('lite-permissions-continue'), brightness);
        _expectPrimary(tester, const ValueKey('lite-permission-get-storage'), brightness);
        final tile = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(OnboardingHeader), matching: find.byType(DecoratedBox)),
        );
        final shape = (tile.decoration as ShapeDecoration).shape as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
        expect(shape.side.width, 1);
        final iconFinder = find.descendant(of: find.byType(OnboardingHeader), matching: find.byType(Icon));
        final icon = tester.widget<Icon>(iconFinder);
        expect(icon.color, _ink(brightness));
        expect(icon.size, 22);
        expect(
          tester.getSize(find.ancestor(of: iconFinder, matching: find.byType(SizedBox)).first),
          const Size.square(44),
        );
        // Compact title uses native letterforms, not an enlarged low-resolution wordmark.
        expect(find.byKey(const ValueKey('lite-brand-whale')), findsNothing);
        expect(find.byKey(const ValueKey('lite-brand-wordmark')), findsOneWidget);
        expect(find.text('deepseek'), findsOneWidget);
        expect(find.text('HARNESS'), findsOneWidget);
        final titleImages = tester.widgetList<Image>(
          find.descendant(of: find.byKey(const ValueKey('lite-brand-wordmark')), matching: find.byType(Image)),
        );
        expect(titleImages.map((image) => (image.image as AssetImage).assetName), [
          brightness == Brightness.dark ? 'assets/branding/whale-dark.png' : 'assets/branding/whale.png',
        ]);
        expect(find.text('查看设置'), findsNWidgets(2));
        expect(find.text('我已开启'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('lite-permission-confirm-storage')), findsNothing);
        await _shot(tester, 'permissions-page-$mode');
        await tester.tap(find.byKey(const ValueKey('lite-permission-get-storage')));
        await _frames(tester);
        expect(driver.opened, ['storage']);
        expect(driver.readings.storage, isTrue);
        expect(find.byKey(const ValueKey('lite-permission-row-battery')), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(const ValueKey('lite-permission-get-storage'))).onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('lite-permission-confirm-vendorBackground')));
        await tester.tap(find.byKey(const ValueKey('lite-permission-confirm-vendorBackground')));
        await _frames(tester);
        expect(find.text('已确认开启'), findsOneWidget);
        expect(find.byKey(const ValueKey('lite-permission-confirm-vendorBackground')), findsNothing);
        expect(
          tester.widget<FilledButton>(find.byKey(const ValueKey('lite-permission-get-vendorBackground'))).onPressed,
          isNotNull,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('lite-permissions-continue')));
        await tester.tap(find.byKey(const ValueKey('lite-permissions-continue')));
        await _frames(tester);
        expect(driver.readings.battery, isFalse);
        expect(done, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('permission states and continue stay on the same card ($mode)', (tester) async {
        var done = 0;
        await _pump(
          tester,
          LitePermissionsPage(onDone: () => done++),
          brightness,
          driver: FakeAccessDriver(const AccessReadings(storage: true, notifications: false, battery: false)),
        );
        _expectCard(tester, brightness);
        _expectPrimary(tester, const ValueKey('lite-permissions-continue'), brightness);
        for (final item in [AccessItem.storage, AccessItem.notifications, AccessItem.battery]) {
          expect(find.byKey(ValueKey('lite-permission-row-${item.name}')), findsOneWidget);
        }
        expect(tester.widget<Text>(find.byKey(const ValueKey('lite-permission-state-storage'))).data, '已开启');
        expect(find.text('未开启'), findsNWidgets(2));
        expect(
          tester.widget<FilledButton>(find.byKey(const ValueKey('lite-permission-get-storage'))).onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('lite-permissions-continue')));
        await tester.tap(find.byKey(const ValueKey('lite-permissions-continue')));
        await _frames(tester);
        expect(done, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('launch uses original animated cover without loading UI and still skips ($mode)', (tester) async {
        final dark = brightness == Brightness.dark;
        final controller = LaunchController(
          snapshot: LaunchSnapshot(systemSplash: false, dark: dark, coldEngine: true),
        );
        addTearDown(controller.dispose);
        await _pump(tester, LaunchOverlay(controller: controller), brightness);
        final cover = tester.widget<Image>(find.byKey(const ValueKey('local-web-startup-cover')));
        expect((cover.image as AssetImage).assetName, 'assets/branding/startup-cover.gif');
        expect(find.text('探索未至之境'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await _shot(tester, 'launch-$mode');
        expect(controller.phase, LaunchPhase.playing);
        await tester.tap(find.byKey(LaunchOverlay.skipKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump();
        expect(controller.phase, LaunchPhase.gone);
        expect(find.byKey(LaunchOverlay.skipKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('compact permission layout scrolls at large text without overflow', (tester) async {
      var done = 0;
      await _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
          child: LitePermissionsPage(onDone: () => done++),
        ),
        Brightness.light,
        driver: FakeAccessDriver(const AccessReadings(storage: false)),
        size: const Size(320, 568),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('lite-permissions-continue')));
      await tester.tap(find.byKey(const ValueKey('lite-permissions-continue')));
      await _frames(tester);
      expect(done, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
