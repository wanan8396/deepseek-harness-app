import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/access_state.dart';
import 'package:dsh_app/state/lite_access_confirmation_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/access/lite_permissions_page.dart';
import 'package:dsh_app/ui/onboarding/access_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/support.dart';
import '../support/lite_harness.dart';

const _continue = ValueKey('lite-permissions-continue');
Key _get(AccessItem item) => ValueKey('lite-permission-get-${item.name}');
Key _row(AccessItem item) => ValueKey('lite-permission-row-${item.name}');
Key _state(AccessItem item) => ValueKey('lite-permission-state-${item.name}');
Key _confirm(AccessItem item) => ValueKey('lite-permission-confirm-${item.name}');

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAccessDriver driver, {
  VoidCallback? onDone,
  FakeEngine? engine,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    goldenApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: AccessStepPage(onDone: onDone ?? () {}),
      ),
      brightness: Brightness.light,
      overrides: [
        ...accessOverrides(driver),
        localRuntimeProvider.overrideWith(() => engine ?? FakeEngine(RuntimePhase.installed)),
        settingsProvider.overrideWith(StorageSettings.new),
      ],
    ),
  );
  await _frames(tester);
  return ProviderScope.containerOf(tester.element(find.byType(AccessStepPage)));
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await _frames(tester);
}

String? _label(WidgetTester tester, AccessItem item) => tester.widget<Text>(find.byKey(_state(item))).data;

class _OpeningDriver extends FakeAccessDriver {
  _OpeningDriver(super.readings);

  bool succeeds = false;
  bool throws = false;
  Completer<void>? hold;

  @override
  Future<bool> open(AccessItem item, {bool again = false}) async {
    await super.open(item, again: again);
    await hold?.future;
    if (throws) throw StateError('settings not available');
    return succeeds;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));


  group('Lite single-page permissions', () {
    for (final vendor in [null, 'samsung', 'vivo', 'xiaomi', 'huawei', 'honor', 'oppo']) {
      testWidgets('shows only available file/background items for $vendor', (tester) async {
        final driver = FakeAccessDriver(readingsWith(offPhone, vendor: vendor, clearVendor: vendor == null));
        final engine = FakeEngine(RuntimePhase.installed);
        await _pump(tester, driver, engine: engine);
        expect(find.byType(LitePermissionsPage), findsOneWidget);
        for (final item in [AccessItem.storage, AccessItem.notifications, AccessItem.battery]) {
          expect(find.byKey(_row(item)), findsOneWidget);
          expect(_label(tester, item), '未开启');
          expect(tester.widget<FilledButton>(find.byKey(_get(item))).onPressed, isNotNull);
          expect(find.byKey(_confirm(item)), findsNothing);
        }
        final vendorItems = vendorSwitches[vendor] ?? const <AccessItem>[];
        for (final item in [AccessItem.vendorBackground, AccessItem.autostart]) {
          expect(find.byKey(_row(item)), vendorItems.contains(item) ? findsOneWidget : findsNothing);
        }
        for (final name in ['mic','accessibility','overlay','popup']) {
          expect(find.byKey(ValueKey('lite-permission-row-$name')), findsNothing);
        }
        expect(driver.opened, isEmpty);
        expect(engine.starts, isEmpty);
        expect(engine.stops, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('omits unreadable items and disables only detected grants', (tester) async {
      final driver = FakeAccessDriver(const AccessReadings(storage: false, battery: true));
      await _pump(tester, driver);
      expect(find.byKey(_row(AccessItem.notifications)), findsNothing);
      expect(_label(tester, AccessItem.battery), '已开启');
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.battery))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.storage))).onPressed, isNotNull);
      expect(find.byKey(_continue), findsOneWidget);
      expect(driver.opened, isEmpty);
    });

    testWidgets('denial stays on the page, retry passes again and grant refreshes without opening the next item', (
      tester,
    ) async {
      final driver = FakeAccessDriver(const AccessReadings(storage: false, notifications: false, battery: false));
      var done = 0;
      await _pump(tester, driver, onDone: () => done++);
      final reads = driver.reads;
      await _tap(tester, _get(AccessItem.storage));
      expect(driver.reads, greaterThan(reads));
      expect(driver.opened, ['storage']);
      expect(_label(tester, AccessItem.storage), '未开启');
      expect(find.byType(LitePermissionsPage), findsOneWidget);
      expect(done, 0);
      driver.answer = (item, now) => readingsWith(now, storage: true);
      await _tap(tester, _get(AccessItem.storage));
      expect(driver.opened, ['storage', 'storage+']);
      expect(_label(tester, AccessItem.storage), '已开启');
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.storage))).onPressed, isNull);
      expect(_label(tester, AccessItem.notifications), '未开启');
      expect(done, 0);
      await _tap(tester, _continue);
      expect(done, 1);
      expect(driver.opened, ['storage', 'storage+']);
    });

    testWidgets('successful vendor launch records visited, never granted, and allows reopening', (tester) async {
      final driver = _OpeningDriver(offPhone)..succeeds = true;
      final container = await _pump(tester, driver);
      await _tap(tester, _get(AccessItem.vendorBackground));
      expect(container.read(accessVisitedProvider), {AccessItem.vendorBackground});
      expect(container.read(liteAccessConfirmedProvider), isEmpty);
      await awayAndBack(tester);
      expect(container.read(liteAccessConfirmedProvider), isEmpty);
      expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_get(AccessItem.vendorBackground)), matching: find.text('查看设置')),
        findsOneWidget,
      );
      expect(_label(tester, AccessItem.vendorBackground), '已去设置');
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.vendorBackground))).onPressed, isNotNull);
      await _tap(tester, _get(AccessItem.vendorBackground));
      expect(driver.opened, ['vendorBackground', 'vendorBackground+']);
      expect(_label(tester, AccessItem.vendorBackground), '已去设置');
      expect(_label(tester, AccessItem.autostart), '去设置');
      expect(tester.takeException(), isNull);
    });

    for (final throws in [false, true]) {
      testWidgets('vendor launch ${throws ? 'exception' : 'false'} remains unvisited with retry and continue', (
        tester,
      ) async {
        final driver = _OpeningDriver(offPhone)..throws = throws;
        var done = 0;
        final container = await _pump(tester, driver, onDone: () => done++);
        final reads = driver.reads;
        await _tap(tester, _get(AccessItem.vendorBackground));
        expect(container.read(accessVisitedProvider), isEmpty);
        expect(container.read(liteAccessConfirmedProvider), isEmpty);
        expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsOneWidget);
        expect(_label(tester, AccessItem.vendorBackground), '去设置');
        expect(driver.reads, greaterThan(reads));
        expect(find.text('没能打开系统设置'), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.vendorBackground))).onPressed, isNotNull);
        await tester.drag(find.byType(SnackBar), const Offset(0, 100));
        await _frames(tester);
        await _tap(tester, _continue);
        expect(done, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('OPPO battery grant and legacy visited never imply vendor confirmation', (tester) async {
      SharedPreferences.setMockInitialValues({
        AccessVisitedController.prefsKey: ['vendorBackground'],
      });
      final driver = FakeAccessDriver(
        const AccessReadings(vendor: 'oppo', storage: true, notifications: true, battery: true),
      );
      final container = await _pump(tester, driver);
      expect(_label(tester, AccessItem.battery), '已开启');
      expect(_label(tester, AccessItem.vendorBackground), '已去设置');
      expect(container.read(liteAccessConfirmedProvider), isEmpty);
      expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_get(AccessItem.vendorBackground)), matching: find.text('查看设置')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.vendorBackground))).onPressed, isNotNull);
      expect(find.text('已确认开启'), findsNothing);
      expect(driver.opened, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit vendor confirmation persists across rebuilds without impersonating a system grant', (
      tester,
    ) async {
      final driver = FakeAccessDriver(
        const AccessReadings(vendor: 'oppo', storage: false, notifications: false, battery: true),
      );
      var container = await _pump(tester, driver);
      await _tap(tester, _confirm(AccessItem.vendorBackground));
      expect(_label(tester, AccessItem.vendorBackground), '已确认开启');
      expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsNothing);
      expect(find.byKey(_confirm(AccessItem.storage)), findsNothing);
      expect(_label(tester, AccessItem.storage), '未开启');
      expect(container.read(liteAccessConfirmedProvider), {AccessItem.vendorBackground});
      expect(container.read(accessVisitedProvider), isEmpty);
      expect((await SharedPreferences.getInstance()).getStringList(LiteAccessConfirmedController.prefsKey), [
        'vendorBackground',
      ]);
      expect(driver.opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
      container = await _pump(tester, driver);
      expect(container.read(liteAccessConfirmedProvider), {AccessItem.vendorBackground});
      expect(_label(tester, AccessItem.vendorBackground), '已确认开启');
      expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.vendorBackground))).onPressed, isNotNull);
      await _tap(tester, _get(AccessItem.vendorBackground));
      expect(driver.opened, ['vendorBackground']);
      expect(_label(tester, AccessItem.vendorBackground), '已确认开启');
      expect(find.byKey(_confirm(AccessItem.vendorBackground)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('confirmation store filters stale names and serializes duplicate confirmations', () async {
      SharedPreferences.setMockInitialValues({
        LiteAccessConfirmedController.prefsKey: ['storage', 'battery', 'popup', 'not-an-item', 'autostart'],
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(liteAccessConfirmedProvider.notifier);
      await controller.ready;
      expect(container.read(liteAccessConfirmedProvider), {AccessItem.autostart});
      await controller.confirm(AccessItem.storage);
      expect(container.read(liteAccessConfirmedProvider), {AccessItem.autostart});
      await Future.wait([
        controller.confirm(AccessItem.vendorBackground),
        controller.confirm(AccessItem.vendorBackground),
        controller.confirm(AccessItem.autostart),
      ]);
      expect(container.read(liteAccessConfirmedProvider), {AccessItem.autostart, AccessItem.vendorBackground});
      final saved = (await SharedPreferences.getInstance()).getStringList(LiteAccessConfirmedController.prefsKey)!;
      expect(saved, unorderedEquals(['autostart', 'vendorBackground']));
      expect(saved.length, 2);
    });

    testWidgets('resume refreshes actual readings without triggering a permission request', (tester) async {
      final driver = FakeAccessDriver(const AccessReadings(storage: false, notifications: false, battery: false));
      await _pump(tester, driver);
      final reads = driver.reads;
      driver.readings = const AccessReadings(storage: true, notifications: true, battery: true);
      await awayAndBack(tester);
      expect(driver.reads, greaterThan(reads));
      for (final item in [AccessItem.storage, AccessItem.notifications, AccessItem.battery]) {
        expect(_label(tester, item), '已开启');
        expect(tester.widget<FilledButton>(find.byKey(_get(item))).onPressed, isNull);
      }
      expect(driver.opened, isEmpty);
      expect(find.byType(LitePermissionsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending system dialog prevents concurrent opens and finish', (tester) async {
      final hold = Completer<void>();
      final driver = _OpeningDriver(const AccessReadings(storage: false, battery: false))
        ..hold = hold
        ..succeeds = true;
      await _pump(tester, driver);
      await _tap(tester, _get(AccessItem.storage));
      expect(driver.opened, ['storage']);
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.battery))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(_continue)).onPressed, isNull);
      hold.complete();
      await _frames(tester);
      expect(tester.widget<FilledButton>(find.byKey(_get(AccessItem.battery))).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(find.byKey(_continue)).onPressed, isNotNull);
      expect(driver.opened, ['storage']);
    });

    testWidgets('continue uses finish fresh readings and applies file access only at completion', (tester) async {
      final driver = FakeAccessDriver(const AccessReadings(storage: false, notifications: false, battery: false));
      var done = 0;
      final container = await _pump(tester, driver, onDone: () => done++);
      expect(container.read(settingsProvider).phoneStorage, isFalse);
      driver.readings = const AccessReadings(storage: true, notifications: false, battery: false);
      await _tap(tester, _continue);
      expect(container.read(settingsProvider).phoneStorage, isTrue);
      expect(driver.opened, isEmpty);
      expect(done, 1);
    });

    testWidgets('failed finish keeps selection and offers both toast retry and bottom continue', (tester) async {
      final driver = FlakyAccessDriver(const AccessReadings(storage: false));
      var done = 0;
      await _pump(tester, driver, onDone: () => done++);
      driver.failures = 1;
      await _tap(tester, _continue);
      expect(done, 0);
      expect(find.text('没能完成设置'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_continue)).onPressed, isNotNull);
      ScaffoldMessenger.of(tester.element(find.byKey(_continue))).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await _tap(tester, _continue);
      await _frames(tester);
      expect(done, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('obsolete partial selection restores the fixed features without opening removed capabilities', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'system_access_setup': jsonEncode({
          'features': ['phone', 'pet', 'voice'],
          'skipped': <String>[],
        }),
      });
      final driver = FakeAccessDriver(offPhone);
      await _pump(tester, driver);
      expect(find.byType(LitePermissionsPage), findsOneWidget);
      expect(driver.opened, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all vendor rows and continue remain reachable on a narrow large-font page', (tester) async {
      final driver = FakeAccessDriver(offPhone);
      var done = 0;
      await _pump(tester, driver, onDone: () => done++, size: const Size(280, 568), textScale: 2);
      await _tap(tester, _get(AccessItem.autostart));
      expect(_label(tester, AccessItem.autostart), '已去设置');
      await _tap(tester, _continue);
      expect(done, 1);
      expect(driver.opened, ['autostart']);
      expect(tester.takeException(), isNull);
    });
  });
}
