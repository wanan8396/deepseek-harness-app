import 'dart:convert';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/locale_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/settings/connect_computer_page.dart';
import 'package:dsh_app/ui/settings/local_web_settings_screen.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_fonts.dart';

const _local = ValueKey('local-web-connect-local');
const _computer = ValueKey('local-web-connect-computer');

Future<ProviderContainer> _open(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: withTestFonts(ThemeData()),
        locale: AppLocale.zhCN,
        supportedLocales: AppLocale.supported,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-connection'),
              onPressed: () =>
                  Navigator.of(context)
                      .push<void>(MaterialPageRoute<void>(builder: (_) => const LocalWebSettingsScreen())),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-connection')));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(LocalWebSettingsScreen)));
  await container.read(webConnectionProvider.notifier).ready;
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('connection-only native route', () {
    for (final size in [const Size(390, 844), const Size(1024, 768)]) {
      testWidgets('only phone and computer destinations at $size', (tester) async {
        final container = await _open(tester, size: size);
        expect(find.text(appL10n.featuresScheduleRunLocation), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(find.byKey(const ValueKey('local-web-guide-entry')), findsNothing);
        expect(
          find.descendant(of: find.byKey(const ValueKey('local-web-settings-list')), matching: find.byType(Divider)),
          findsNothing,
        );
        expect(find.text('使用说明'), findsNothing);
        final gap = tester.getRect(find.byKey(_computer)).top - tester.getRect(find.byKey(_local)).bottom;
        expect(gap, 8);
        expect(find.text(appL10n.commonThisPhone), findsOneWidget);
        expect(find.text(appL10n.remotePairComputer), findsOneWidget);
        final local = tester.widget<ListTile>(find.byKey(_local));
        expect(local.selected, isTrue);
        expect(find.descendant(of: find.byKey(_local), matching: find.byIcon(Icons.check)), findsOneWidget);
        expect(
          find.descendant(of: find.byKey(_local), matching: find.byKey(const ValueKey('local-web-permissions'))),
          findsOneWidget,
        );
        expect(tester.widget<ListTile>(find.byKey(_computer)).selected, isFalse);
        for (final feature in ['theme', 'language', 'engine', 'models', 'info', 'version', 'licenses']) {
          expect(find.byKey(ValueKey('local-web-$feature')), findsNothing);
        }
        for (final title in ['System', 'Light', 'Dark', 'Language', '跟随系统', '浅色', '深色', '语言']) {
          expect(find.text(title), findsNothing);
        }
        expect(find.byIcon(AppIcons.engine), findsNothing);
        expect(find.byIcon(AppIcons.info), findsNothing);
        expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
        expect(container.exists(settingsProvider), isFalse);
        expect(container.exists(appLanguageProvider), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('local selection persists the real state and returns to the first route', (tester) async {
      final container = await _open(tester);
      final controller = container.read(webConnectionProvider.notifier);
      await controller.connectComputer('http://192.0.2.10:3090/');
      await tester.pumpAndSettle();
      expect(find.text('192.0.2.10'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(_computer)).selected, isTrue);
      await tester.tap(find.byKey(_local));
      await tester.pumpAndSettle();
      expect(container.read(webConnectionProvider).mode, WebConnectionMode.local);
      expect(container.read(webConnectionProvider).computerUrl, isNull);
      final saved = jsonDecode((await SharedPreferences.getInstance()).getString(WebConnectionController.prefsKey)!);
      expect(saved['mode'], 'local');
      expect(saved['selectedId'], isNull);
      expect(saved['records'], hasLength(1));
      expect(find.byType(LocalWebSettingsScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-connection')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('computer destination opens manual address, scan and history route', (tester) async {
      final container = await _open(tester);
      await container.read(webConnectionProvider.notifier).connectComputer('http://192.0.2.10:3090/');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_computer));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectComputerPage), findsOneWidget);
      expect(find.byKey(const ValueKey('computer-address')), findsOneWidget);
      expect(find.byKey(const ValueKey('computer-connect')), findsOneWidget);
      expect(find.byKey(const ValueKey('computer-scan')), findsOneWidget);
      expect(find.text(appL10n.remoteDirectoryRecent), findsOneWidget);
      final record = container.read(webConnectionProvider).records.single;
      expect(find.byKey(ValueKey('computer-record-${record.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
