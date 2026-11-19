// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/onboarding/local_install.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:dsh_app/links/launcher_entries.dart';
import 'package:dsh_app/links/share_intake.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/local_connection_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/ui_mode_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/settings/connect_computer_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dsh_app/ui/notify/chat_alert_host.dart';
import 'package:dsh_app/ui/settings/local_web_settings_screen.dart';
import 'package:dsh_app/ui/web/local_web_screen.dart';
import 'package:dsh_app/ui/web/startup_cover.dart';
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:dsh_app/ui/web/web_home.dart';
import 'package:dsh_app/ui/web/web_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

class _LoadingRuntime extends LocalRuntimeController {
  _LoadingRuntime(this.initial, {this.loaded = true, this.failStart = false});
  final RuntimeStatus initial;
  final bool loaded;
  final bool failStart;
  int starts = 0;

  @override
  LocalRuntimeState build() => LocalRuntimeState(loaded: loaded, status: initial);

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('fixture_start_failed');
  }

  void report(RuntimeStatus next) => state = LocalRuntimeState(loaded: true, status: next);
}

class _StoppedRuntime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() =>
      const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.installed));
}

class _RunningRuntime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => const LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:3080', token: 'fixture'),
  );
}

class _NoOfficialConnection extends OfficialLocalConnectionController {
  @override
  Future<HostConnection?> build() async => null;
}

class _ComputerConnection extends WebConnectionController {
  @override
  WebConnectionState build() {
    ready = Future<void>.value();
    return const WebConnectionState(
      loaded: true,
      mode: WebConnectionMode.computer,
      computerUrl: 'http://192.0.2.10:3090/',
    );
  }

  @override
  Future<void> setLocal() async => state = const WebConnectionState(loaded: true);
}

void _window(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
}

Future<FakeWebViewController> _liveHome(
  WidgetTester tester,
  Size size, {
  bool adapt = true,
  bool computer = false,
}) async {
  _window(tester, size);
  final platform = FakeWebViewPlatform();
  WebViewPlatform.instance = platform;
  await tester.pumpWidget(
    testApp(
      const WebHome(),
      overrides: [
        ...ShellHarness(
          runtime: _RunningRuntime.new,
          settings: const AppSettings(loaded: true),
        ).overrides,
        // Geometry fixtures do not provide an actual local HTTP/mux service.
        officialLocalConnectionProvider.overrideWith(_NoOfficialConnection.new),
        recentShortcutsProvider.overrideWithValue(const []),
        if (computer) webConnectionProvider.overrideWith(_ComputerConnection.new),
      ],
    ),
  );
  for (var i = 0; i < 30 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(platform.controller.loads, isNotEmpty);
  platform.controller.finish();
  await pumpFrames(tester);
  return platform.controller;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));



  group('phone-local web shell', () {
    testWidgets('installed engine starts once after status load and shows only waiting', (tester) async {
      final runtime = _LoadingRuntime(const RuntimeStatus(phase: RuntimePhase.installed), loaded: false);
      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 0);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      expect(find.text(appL10n.localWebExploreBeyond), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      tester.view.physicalSize = const Size(1688, 780);
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      expect(find.text(appL10n.localWebExploreBeyond), findsOneWidget);
      expect(find.byIcon(AppIcons.engine), findsNothing);
      expect(find.byTooltip('Engine status'), findsNothing);
      expect(find.byKey(const ValueKey('local-web-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('startup failure waits for explicit retry rather than looping', (tester) async {
      final runtime = _LoadingRuntime(const RuntimeStatus(phase: RuntimePhase.installed), failStart: true);
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(find.byKey(const ValueKey('local-web-retry')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.error, error: 'fixture failure'));
      await pumpFrames(tester);
      runtime.report(const RuntimeStatus(phase: RuntimePhase.installed));
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      expect(find.byKey(const ValueKey('local-web-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('local-web-retry')));
      await pumpFrames(tester);
      expect(runtime.starts, 2);
      expect(find.byIcon(AppIcons.engine), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('running status enters webpage without an engine management step', (tester) async {
      final runtime = _LoadingRuntime(const RuntimeStatus(phase: RuntimePhase.installed));
      WebViewPlatform.instance = FakeWebViewPlatform();
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 1);
      runtime.report(
        const RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:3080', token: 'fixture'),
      );
      await pumpFrames(tester);
      expect(find.byType(WebViewPage), findsOneWidget);
      expect(find.byKey(const ValueKey('local-web-waiting')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing runtime retains installation recovery without auto start', (tester) async {
      final runtime = _LoadingRuntime(const RuntimeStatus(phase: RuntimePhase.notInstalled, bundledVersion: 'fixture'));
      await tester.pumpWidget(
        testApp(const LocalWebScreen(), overrides: ShellHarness(runtime: () => runtime).overrides),
      );
      await pumpFrames(tester);
      expect(runtime.starts, 0);
      expect(find.byKey(const ValueKey('local-web-install')), findsOneWidget);
      expect(find.byIcon(AppIcons.engine), findsNothing);
      await tester.tap(find.byKey(const ValueKey('local-web-install')));
      await pumpFrames(tester);
      expect(find.byType(LocalInstallPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final computer in [false, true]) {
      testWidgets(
        'whale toggles the live web sidebar; connection entry alone opens native routes, computer=$computer',
        (tester) async {
          final page = await _liveHome(tester, const Size(390, 844), computer: computer);
          final platform = WebViewPlatform.instance as FakeWebViewPlatform;
          const toggle = 'window.__dshApp && window.__dshApp.toggleSidebar()';
          final viewport = tester.getRect(find.byKey(fakeWebViewKey));
          expect(find.byTooltip(appL10n.webChatsWorkspaces), findsOneWidget);
          expect(find.byIcon(AppIcons.menu), findsNothing);
          expect(find.byKey(const ValueKey('web-controls-bottom-menu')), findsNothing);
          await tester.tap(find.byType(WebHandleButton));
          await pumpFrames(tester, 2);
          expect(page.scripts.where((s) => s == toggle), hasLength(1));
          expect(find.byType(LocalWebSettingsScreen), findsNothing);
          final connection = find.byKey(const ValueKey('web-connection-switch'));
          expect(
            find.descendant(
              of: connection,
              matching: find.text(computer ? appL10n.remotePairComputer : appL10n.commonThisPhone),
            ),
            findsOneWidget,
          );
          await tester.tap(connection);
          await tester.pumpAndSettle();
          expect(find.byType(LocalWebSettingsScreen), findsOneWidget);
          expect(find.byKey(const ValueKey('local-web-connect-local')), findsOneWidget);
          expect(find.byKey(const ValueKey('local-web-connect-computer')), findsOneWidget);
          expect(find.byKey(const ValueKey('web-handle-settings')), findsNothing);
          expect(find.byKey(const ValueKey('web-handle-native')), findsNothing);
          expect(find.byKey(const ValueKey('web-handle-host')), findsNothing);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(platform.controllers, hasLength(1));
          expect(platform.controller, same(page));
          expect(page.loads, hasLength(1));
          expect(tester.getRect(find.byKey(fakeWebViewKey)), viewport);
          expect(find.byType(WebHandleButton), findsOneWidget);
          expect(connection, findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final brightness in Brightness.values) {
      testWidgets('connection selector has only local and computer rows and ${brightness.name} preview', (
        tester,
      ) async {
        _window(tester, const Size(420, 820));
        const shot = ValueKey('settings-shot');
        await tester.pumpWidget(
          testApp(
            const RepaintBoundary(key: shot, child: LocalWebSettingsScreen()),
            brightness: brightness,
            overrides: ShellHarness(runtime: _StoppedRuntime.new).overrides,
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            AssetImage(
              brightness == Brightness.dark ? 'assets/branding/wordmark-dark.png' : 'assets/branding/wordmark.png',
            ),
            tester.element(find.byType(LocalWebSettingsScreen)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('local-web-settings-list')), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(find.byKey(const ValueKey('local-web-guide-entry')), findsNothing);
        expect(
          find.descendant(of: find.byKey(const ValueKey('local-web-settings-list')), matching: find.byType(Divider)),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('local-web-connect-local')), findsOneWidget);
        expect(find.byKey(const ValueKey('local-web-connect-computer')), findsOneWidget);
        for (final key in [
          'theme',
          'language',
          'run-location',
          'version',
          'licenses',
          'section-0',
          'section-1',
          'section-2',
        ]) {
          expect(find.byKey(ValueKey('local-web-$key')), findsNothing);
        }
        expect(find.byKey(const ValueKey('local-web-phone-control')), findsNothing);
        for (final key in [
          'phone-layout',
          'models',
          'logs',
          'diagnostics',
          'source',
          'background',
          'notifications',
          'file-access',
        ]) {
          expect(find.byKey(ValueKey('local-web-$key')), findsNothing);
        }
        expect(find.byKey(const ValueKey('local-web-engine')), findsNothing);
        expect(find.byKey(const ValueKey('local-web-auto-start')), findsNothing);
        expect(find.text('切回原生界面'), findsNothing);
        expect(find.text('切换主机'), findsNothing);
        expect(find.text('宠物'), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shot));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory('build/local-web-shots').create(recursive: true);
          await File('${dir.path}/settings-${brightness.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }

    testWidgets('wide connection selector goes directly to computer address, scan and history', (tester) async {
      _window(tester, const Size(1080, 800));
      await tester.pumpWidget(
        testApp(const LocalWebSettingsScreen(), overrides: ShellHarness(runtime: _RunningRuntime.new).overrides),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('local-web-settings-categories')), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.byKey(const ValueKey('local-web-guide-entry')), findsNothing);
      expect(
        find.descendant(of: find.byKey(const ValueKey('local-web-settings-list')), matching: find.byType(Divider)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('local-web-connect-local')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('local-web-connect-computer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectComputerPage), findsOneWidget);
      expect(find.byKey(const ValueKey('computer-address')), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.byKey(const ValueKey('local-web-permissions')), findsNothing);
      expect(find.byKey(const ValueKey('local-web-models')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(320, 760), const Size(390, 844), const Size(844, 390), const Size(1100, 800)]) {
      for (final adapt in [true, false]) {
        testWidgets('one bottom-left handle reserves chat space: $size adapt=$adapt', (tester) async {
          final page = await _liveHome(tester, size, adapt: adapt);
          expect(find.byType(WebHandleButton), findsOneWidget);
          final handle = tester.getRect(find.byType(WebHandleButton));
          final row = tester.getRect(find.byKey(const ValueKey('web-controls-bottom')));
          expect(handle.left, 12);
          expect(handle.size, const Size.square(40));
          // 48dp row + 24dp navigation inset.
          expect(row.top, size.height - 72);
          expect(handle.top, row.top + 4);
          expect(row.height, 72);
          // The row draws no box of its own: a transparent ColoredBox still
          // hit-tests as opaque, which put an invisible strip over the page.
          expect(
            find.descendant(of: find.byKey(const ValueKey('web-controls-bottom')), matching: find.byType(ColoredBox)),
            findsNothing,
          );
          final connection = tester.getRect(find.byKey(const ValueKey('web-connection-switch')));
          expect(connection.right, size.width - 12);
          expect(connection.center.dy, handle.center.dy);
          expect(connection.overlaps(handle), isFalse);
          expect(find.byIcon(AppIcons.menu), findsNothing);
          expect(find.byKey(const ValueKey('web-controls-bottom-menu')), findsNothing);
          for (final chrome in ['inline', 'seat', 'side', 'bar']) {
            expect(find.byKey(ValueKey('web-controls-$chrome')), findsNothing);
          }
          expect(tester.getSize(find.byKey(fakeWebViewKey)), size);
          final insets = WebPageInsets.resolve(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            keyboard: 0,
            dshWeb: true,
            adapt: true,
            leadingAtBottom: true,
          );
          // The composer comes down over the row's empty top (pageOverlap), so
          // the input box ends just above the whale; the row and its touch
          // target stay exactly where they were.
          expect(insets.bottom, 60);
          expect(insets.lead, 0);
          expect(insets.leadHeight, 0);
          expect(insets.layerTop, 24);
          final contentBottom =
              size.height - (insets.chrome == WebChrome.side ? insets.frameBottom : insets.rootBottom);
          expect(contentBottom, row.top + WebBottomHandle.pageOverlap);
          // The card's own bottom padding (measured on device) keeps the
          // visible input box above the whale, though the page now reaches
          // into that empty band.
          expect(WebBottomHandle.pageOverlap, lessThan(WebBottomHandle.height));
          // Existing page insets reserve both controls without shrinking the WebView.
          expect(page.insetsScript, contains('--dsh-app-inset-bottom:60.0px'));
          expect(page.insetsScript, contains('--dsh-app-safe-bottom:24.0px'));
          expect(page.insetsScript, contains('--dsh-app-inset-top:24.0px'));
          expect(page.insetsScript, contains('--dsh-app-lead:0.0px'));
          expect(page.insetsScript, contains('--dsh-app-lead-h:0.0px'));
          expect(page.insetsScript, isNot(contains('left:48.0px!important')));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the bottom row leaves the page between the whale and the switch touchable', (tester) async {
      final page = await _liveHome(tester, const Size(390, 844));
      final handle = tester.getRect(find.byType(WebHandleButton));
      final connection = tester.getRect(find.byKey(const ValueKey('web-connection-switch')));

      /// Every render object the bottom row owns.
      Set<Object> rowRenderObjects() {
        final objects = <Object>{};
        void collect(Element element) {
          final object = element.renderObject;
          if (object != null) objects.add(object);
          element.visitChildren(collect);
        }

        collect(tester.element(find.byKey(const ValueKey('web-controls-bottom'))));
        return objects;
      }

      // The gap the page sits behind: between the two controls, on their row.
      // The sidebar's archive action lands here, so a tap must reach the page.
      final gap = Offset((handle.right + connection.left) / 2, handle.center.dy);
      expect(gap.dx, greaterThan(handle.right));
      expect(gap.dx, lessThan(connection.left));

      final hits = tester.hitTestOnBinding(gap).path.map((entry) => entry.target).toSet();
      expect(
        hits.intersection(rowRenderObjects()),
        isEmpty,
        reason: 'the row must not hit-test in the gap: a transparent box there put an invisible strip over the page',
      );

      // Both controls still answer for themselves.
      final whaleHits = tester.hitTestOnBinding(handle.center).path.map((e) => e.target).toSet();
      expect(whaleHits.intersection(rowRenderObjects()), isNotEmpty);
      final switchHits = tester.hitTestOnBinding(connection.center).path.map((e) => e.target).toSet();
      expect(switchHits.intersection(rowRenderObjects()), isNotEmpty);

      // The probe hit none of the row, so the tap went to the page instead of
      // a control: the whale never opened the sidebar for a tap in the gap.
      expect(page.scripts.where((s) => s == 'window.__dshApp && window.__dshApp.toggleSidebar()'), isEmpty);
      await tester.tap(find.byType(WebHandleButton));
      await pumpFrames(tester, 2);
      expect(page.scripts.where((s) => s == 'window.__dshApp && window.__dshApp.toggleSidebar()'), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawer, rotation and foreground keep whale clickable; keyboard and real modal restore it', (
      tester,
    ) async {
      final page = await _liveHome(tester, const Size(390, 844));
      final platform = WebViewPlatform.instance as FakeWebViewPlatform;
      const toggle = 'window.__dshApp && window.__dshApp.toggleSidebar()';
      page.post('DshAppSidebar', 'open');
      // The real modal bridge excludes rc2's data-shortcut-modal=sidebar;
      // the DOM geometry test exercises that production bridge directly.
      page.post('DshAppModal', 'closed');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(find.byKey(const ValueKey('web-connection-switch')), findsOneWidget);
      final before = page.scripts.where((s) => s == toggle).length;
      await tester.tap(find.byType(WebHandleButton));
      await pumpFrames(tester, 2);
      expect(page.scripts.where((s) => s == toggle), hasLength(before + 1));
      page.post('DshAppSidebar', 'closed');
      page.post('DshAppSidebar', 'open');
      tester.view.physicalSize = const Size(844, 390);
      await pumpFrames(tester);
      expect(tester.getSize(find.byKey(fakeWebViewKey)), const Size(844, 390));
      expect(find.byType(WebHandleButton), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      await pumpFrames(tester, 5);
      expect(find.byType(WebHandleButton), findsNothing);
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.physicalSize = const Size(390, 844);
      await pumpFrames(tester);
      expect(find.byType(WebHandleButton), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(page.scripts.lastWhere((s) => s.contains('__dshAppSidebar(true)')), isNotEmpty);
      expect(find.byType(WebHandleButton), findsOneWidget);
      page.post('DshAppModal', 'open');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsNothing);
      page.post('DshAppModal', 'closed');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsOneWidget);
      final after = page.scripts.where((s) => s == toggle).length;
      await tester.tap(find.byType(WebHandleButton));
      await pumpFrames(tester);
      expect(page.scripts.where((s) => s == toggle), hasLength(after + 1));
      expect(platform.controllers, hasLength(1));
      expect(platform.controller, same(page));
      expect(page.loads, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard hides whale and connection, releases its inset, keeps controller, viewport and Back', (
      tester,
    ) async {
      final page = await _liveHome(tester, const Size(390, 844));
      final platform = WebViewPlatform.instance as FakeWebViewPlatform;
      final viewport = tester.getRect(find.byKey(fakeWebViewKey));
      expect(find.byKey(const ValueKey('web-connection-switch')), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 24);
      await pumpFrames(tester, 5);
      expect(find.byType(WebHandleButton), findsNothing);
      expect(find.byKey(const ValueKey('web-connection-switch')), findsNothing);
      expect(find.byKey(const ValueKey('web-controls-bottom')), findsNothing);
      expect(tester.getRect(find.byKey(fakeWebViewKey)), viewport);
      expect(page.insetsScript, contains('#root{bottom:300.0px!important}'));
      expect(page.insetsScript, contains('window.__dshAppKeyboard = 300.0;'));
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      await pumpFrames(tester);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(find.byKey(const ValueKey('web-connection-switch')), findsOneWidget);
      expect(platform.controllers, hasLength(1));
      expect(platform.controller, same(page));
      expect(page.loads, hasLength(1));
      expect(tester.getRect(find.byKey(fakeWebViewKey)), viewport);
      page.history = 1;
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(page.goBacks, 1);
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(390, 844), const Size(320, 568), const Size(844, 390)]) {
      testWidgets('cover does not move when waiting hands off to WebView at $size', (tester) async {
        _window(tester, size);
        final platform = FakeWebViewPlatform();
        WebViewPlatform.instance = platform;
        final runtime = _LoadingRuntime(const RuntimeStatus(phase: RuntimePhase.starting));
        await tester.pumpWidget(
          testApp(
            LocalWebScreen(handle: (_) => const SizedBox.square(dimension: 40), handleAtBottom: true),
            overrides: ShellHarness(runtime: () => runtime).overrides,
          ),
        );
        await pumpFrames(tester);
        final image = find.byKey(const ValueKey('local-web-startup-cover'));
        final slogan = find.byKey(const ValueKey('local-web-startup-tagline'));
        final waitingImage = tester.getRect(image);
        final waitingSlogan = tester.getRect(slogan);
        expect(tester.getRect(find.byType(StartupStage)).size, size);
        runtime.report(const RuntimeStatus(
          phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:3080', token: 'fixture',
        ));
        await pumpFrames(tester);
        expect(find.byType(WebViewPage), findsOneWidget);
        expect(find.byKey(const ValueKey('lite-web-loading-stage')), findsOneWidget);
        expect(tester.getRect(image), waitingImage);
        expect(tester.getRect(slogan), waitingSlogan);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('stopped engine keeps disabled whale and active connection in a single 48dp row', (tester) async {
      _window(tester, const Size(390, 844));
      await tester.pumpWidget(
        testApp(
          const WebHome(),
          overrides: [
            ...ShellHarness(runtime: _StoppedRuntime.new).overrides,
          ],
        ),
      );
      await pumpFrames(tester);
      expect(find.byType(LocalWebScreen), findsOneWidget);
      expect(find.byType(ChatAlertHost), findsOneWidget);
      expect(find.byType(WebEntryHost), findsOneWidget);
      expect(find.byType(WebHandleButton), findsOneWidget);
      final row = tester.getRect(find.byKey(const ValueKey('web-controls-bottom')));
      expect(row.height, 72);
      expect(row.top, 844 - 72);
      final backdrop = tester.widget<ColoredBox>(
        find.descendant(of: find.byType(StartupStage), matching: find.byType(ColoredBox)).first,
      );
      expect(backdrop.color, const Color(0xFFF7F8FA));
      expect(tester.getRect(find.byType(StartupStage)).bottom, 844);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final cover = tester.widget<Image>(find.byKey(const ValueKey('local-web-startup-cover')));
      expect((cover.image as AssetImage).assetName, 'assets/branding/startup-cover.gif');
      expect(find.text(appL10n.localWebExploreBeyond), findsOneWidget);
      final whale = tester.getRect(find.byType(WebHandleButton));
      expect(whale.size, const Size.square(40));
      expect(whale.top, row.top + 4);
      expect(tester.getRect(find.byKey(const ValueKey('local-web-waiting'))).bottom, 844,
          reason: 'the controls overlay the full-height cover rather than shifting its centre');
      expect(tester.widget<WebHandleButton>(find.byType(WebHandleButton)).onSidebar, isNull);
      expect(find.byIcon(AppIcons.menu), findsNothing);
      expect(find.byKey(const ValueKey('web-controls-bottom-menu')), findsNothing);
      expect(find.byType(WebViewPage), findsNothing);
      expect(tester.allWidgets.where((w) => w.runtimeType.toString() == '_PetHost'), isEmpty);
      await tester.tap(find.byType(WebHandleButton));
      await pumpFrames(tester, 2);
      expect(find.byType(LocalWebSettingsScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('web-connection-switch')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalWebSettingsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('local-web-connect-local')), findsOneWidget);
      expect(find.byKey(const ValueKey('local-web-connect-computer')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('computer preview accepts only plain HTTP(S) URLs', () {
      expect(previewComputerAddress('http://192.0.2.10:3090/')?.host, '192.0.2.10');
      expect(previewComputerAddress('https://computer.example/?token=fixture')?.origin, 'https://computer.example');
      for (final value in [
        'javascript:alert(1)',
        'dshgo://pair/fixture',
        '{"url":"http://example.com"}',
        'file:///data/local',
        'http://user:secret@example.com',
        'http://example.com:65536',
        'http://example.com/ bad',
      ]) {
        expect(previewComputerAddress(value), isNull);
      }
    });

    testWidgets('computer address requires preview confirmation; camera stays off; records reconnect', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(testApp(const ConnectComputerPage(), overrides: ShellHarness().overrides));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(ConnectComputerPage)));
      expect(find.byType(MobileScanner), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('computer-address')), 'javascript:alert(1)');
      await tester.tap(find.byKey(const ValueKey('computer-connect')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(webConnectionProvider).mode, WebConnectionMode.local);
      await tester.enterText(find.byKey(const ValueKey('computer-address')), 'http://192.0.2.10:3090/');
      await tester.tap(find.byKey(const ValueKey('computer-connect')));
      await tester.pumpAndSettle();
      expect(find.text('http://192.0.2.10:3090'), findsOneWidget);
      expect(container.read(webConnectionProvider).mode, WebConnectionMode.local);
      await tester.tap(find.byKey(const ValueKey('computer-confirm')));
      await tester.pumpAndSettle();
      final record = container.read(webConnectionProvider).records.single;
      expect(record.baseUrl, 'http://192.0.2.10:3090/');
      expect(container.read(webConnectionProvider).mode, WebConnectionMode.computer);
      await container.read(webConnectionProvider.notifier).setLocal();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('computer-record-${record.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('computer-origin-preview')), findsOneWidget);
      expect(container.read(webConnectionProvider).mode, WebConnectionMode.local);
      expect(tester.takeException(), isNull);
    });

    testWidgets('computer home never reads or writes phone session integrations', (tester) async {
      usePhoneView(tester);
      final platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      await tester.pumpWidget(
        testApp(
          const WebHome(),
          overrides: [
            ...ShellHarness(session: 'phone-session', runtime: _StoppedRuntime.new).overrides,
            webConnectionProvider.overrideWith(_ComputerConnection.new),
          ],
        ),
      );
      for (var i = 0; i < 30 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      final page = platform.controller;
      expect(page.loads.single.host, '192.0.2.10');
      page.finish();
      for (var i = 0; i < 30 && !page.scripts.any((s) => s.contains('window.__dshAppOpen = function')); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.byType(ChatAlertHost), findsNothing);
      expect(find.byType(WebEntryHost), findsNothing);
      expect(find.byType(LocalWebScreen), findsNothing);
      expect(find.byType(WebHandleButton), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(WebHome)));
      container.read(currentSessionProvider.notifier).select('phone-changed');
      container.read(webOpenProvider.notifier).request(const DshWebTarget(sessionId: 'phone-only'));
      await pumpFrames(tester);
      expect(page.scripts.where((s) => s.startsWith('window.__dshAppOpen &&') && s.contains('phone-')), isEmpty);
      container.read(webOpenProvider.notifier).request(const DshWebTarget(settings: DshWebSettings.models));
      await pumpFrames(tester);
      expect(page.scripts, contains(const DshWebTarget(settings: DshWebSettings.models).openScript));
      expect(container.read(currentSessionProvider), 'phone-changed');
      await container.read(webConnectionProvider.notifier).setLocal();
      await pumpFrames(tester);
      expect(find.byType(LocalWebScreen), findsOneWidget);
      expect(find.byType(ChatAlertHost), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final computer in [false, true]) {
      testWidgets('settings keeps permission entry and preserves web conversation, computer=$computer', (tester) async {
        _window(tester, const Size(420, 1100));
        await tester.pumpWidget(
          testApp(
            Scaffold(
              key: const ValueKey('web-conversation'),
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-settings-fixture'),
                  onPressed: () =>
                      Navigator.of(context)
                          .push<void>(MaterialPageRoute<void>(builder: (_) => const LocalWebSettingsScreen())),
                  child: const Text('settings'),
                ),
              ),
            ),
            overrides: [
              ...ShellHarness(session: 'unchanged', runtime: _StoppedRuntime.new).overrides,
              if (computer) webConnectionProvider.overrideWith(_ComputerConnection.new),
            ],
          ),
        );
        final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('web-conversation'))));
        await tester.tap(find.byKey(const ValueKey('open-settings-fixture')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('local-web-permissions')), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(LocalWebSettingsScreen), findsNothing);
        expect(find.byKey(const ValueKey('web-conversation')), findsOneWidget);
        expect(container.read(webOpenProvider), isNull);
        expect(container.read(currentSessionProvider), 'unchanged');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shares remain drafts; remote shortcuts never retarget local chat', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: WebEntryHost()), overrides: ShellHarness().overrides));
      final container = ProviderScope.containerOf(tester.element(find.byType(WebEntryHost)));
      container.read(shareIntakeProvider).add(const IncomingShare(text: 'https://go.dshtui.com/c/shared'));
      await pumpFrames(tester);
      final request = container.read(webOpenProvider);
      expect(request?.target.newSession, isTrue);
      expect(request?.compose?.text, 'https://go.dshtui.com/c/shared');
      container.read(webOpenProvider.notifier).taken(request!);
      expect(LauncherEntry.parse({'kind':'chat','sessionId':'foreign-session','host':jsonEncode({'kind':'ssh','id':'old-host'})}), isNull);
      await pumpFrames(tester);
      expect(container.read(currentSessionProvider), isNull);
      expect(container.read(webOpenProvider), isNull);
      container.read(launcherBridgeProvider).add(const OpenChatEntry(HostRef.local, 'local-session'));
      await pumpFrames(tester);
      expect(container.read(currentSessionProvider), 'local-session');
      expect(tester.takeException(), isNull);
    });
  });
}
