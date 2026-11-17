// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/web/web_view_platform.dart' as native;
import 'package:dsh_app/ui/web/web_back.dart';
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:dsh_app/ui/web/web_home.dart';
import 'package:dsh_app/ui/web/web_navigation.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

final _lan = Uri.parse('http://192.0.2.10:3090/');

/// Unlike the generic fake, retains the real app's navigation callback. A PIN
/// POST and both Location hops must reach this callback without being rerouted.
class _NavigationDelegate extends FakeNavigationDelegate {
  _NavigationDelegate(super.params);
  NavigationRequestCallback? request;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async =>
      request = onNavigationRequest;
}

class _NavigationPlatform extends FakeWebViewPlatform {
  late _NavigationDelegate navigation;

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) =>
      navigation = _NavigationDelegate(params);
}

class _ComputerConnection extends WebConnectionController {
  @override
  WebConnectionState build() {
    ready = Future<void>.value();
    return WebConnectionState(loaded: true, mode: WebConnectionMode.computer, computerUrl: _lan.toString());
  }
}

class _UnexpectedRuntime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => throw StateError('computer_read_phone_runtime');
}

class _UnexpectedSession extends CurrentSessionController {
  @override
  String? build() => throw StateError('computer_read_phone_session');
}

Future<_NavigationPlatform> _computer(WidgetTester tester) async {
  usePhoneView(tester);
  final platform = _NavigationPlatform();
  WebViewPlatform.instance = platform;
  await tester.pumpWidget(
    testApp(
      // A stale initial local target must be ignored by the computer owner.
      const WebHome(),
      overrides: [
        settingsProvider.overrideWith(() => TestSettings(const AppSettings(loaded: true))),
        webConnectionProvider.overrideWith(_ComputerConnection.new),
        localRuntimeProvider.overrideWith(_UnexpectedRuntime.new),
        currentSessionProvider.overrideWith(_UnexpectedSession.new),
      ],
    ),
  );
  for (var i = 0; i < 30 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(platform.controller.loads, [_lan]);
  expect(platform.navigation.request, isNotNull);
  return platform;
}

Future<void> _finish(WidgetTester tester, FakeWebViewController page, [Uri? url]) async {
  page.delegate!.onPageFinished!(url?.toString() ?? _lan.toString());
  for (var i = 0; i < 40 && !page.scripts.any((s) => s.contains('window.__dshAppBack = function')); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await pumpFrames(tester, 4);
}

String? _node() {
  final separator = Platform.isWindows ? ';' : ':';
  final executable = Platform.isWindows ? 'node.exe' : 'node';
  for (final entry in (Platform.environment['PATH'] ?? '').split(separator)) {
    final dir = entry.replaceAll('"', '');
    final candidate = File('$dir${Platform.pathSeparator}$executable');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebKeyboard.forgetHeights();
    final before = native.WebViewPlatform.instance;
    native.WebViewPlatform.instance = FakeNativeWebViewPlatform();
    addTearDown(() => native.WebViewPlatform.instance = before);
  });

  group('LAN PIN origin contract', () {
    for (final address in ['http://192.0.2.10:3090/', 'https://computer.example/', 'http://[2001:db8::10]:3090/']) {
      test('POST login, 302 / and 303 ./ stay embedded at $address', () {
        final base = Uri.parse(address);
        final login = base.resolve('/_remote/login');
        final redirect302 = login.resolve('/');
        final redirect303 = redirect302.resolve('./');
        for (final hop in [
          login,
          redirect302,
          redirect303,
          base.replace(queryParameters: {'token': 'fixture-only'}),
        ]) {
          expect(dshWebNavigation(base, hop.toString(), true), DshWebNavigation.stay, reason: hop.toString());
        }
      });
    }

    test('only the selected proxy origin stays; phone loopback is not substituted', () {
      expect(dshWebNavigation(_lan, 'http://192.0.2.10:3090/_remote/login', true), DshWebNavigation.stay);
      for (final target in [
        'http://127.0.0.1:3080/',
        'http://192.0.2.10:3091/',
        'https://192.0.2.10:3090/',
        'http://192.0.2.11:3090/',
      ]) {
        expect(dshWebNavigation(_lan, target, true), DshWebNavigation.external, reason: target);
      }
    });
  });

  group('computer WebView owner', () {
    testWidgets('PIN form navigation and both redirects retain the same WebView without phone providers', (
      tester,
    ) async {
      final platform = await _computer(tester);
      final page = platform.controller;
      final container = ProviderScope.containerOf(tester.element(find.byType(WebHome)));
      await _finish(tester, page);
      for (final hop in [_lan.resolve('/_remote/login'), _lan.resolve('/'), _lan.resolve('./')]) {
        expect(
          await platform.navigation.request!(NavigationRequest(url: hop.toString(), isMainFrame: true)),
          NavigationDecision.navigate,
        );
        page.delegate!.onPageStarted!(hop.toString());
        await _finish(tester, page, hop);
      }
      // The engine's browser handles POST/redirect/cookies. Flutter neither
      // reloads the launch URL for each hop nor exchanges a local token.
      expect(platform.controllers, hasLength(1));
      expect(page.loads, [_lan]);
      expect(page.reloads, 0);
      expect(page.channels, isNot(contains('DshAppState')));
      expect(page.scripts.where((s) => s.startsWith('window.__dshAppOpen &&') && s.contains('phone-initial')), isEmpty);
      expect(container.exists(localRuntimeProvider), isFalse);
      expect(container.exists(currentSessionProvider), isFalse);
      expect(container.exists(activeHostProvider), isFalse);
      expect(container.exists(localConnectionProvider), isFalse);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('computer loading clears on PIN page finish; failures never blame the local engine', (tester) async {
      final platform = await _computer(tester);
      final page = platform.controller;
      expect(tester.widget<WebViewPage>(find.byType(WebViewPage)).computerWeb, isTrue);
      expect(find.byKey(const ValueKey('lite-web-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('local-web-startup-cover')), findsOneWidget);
      expect(find.text(appL10n.localWebExploreBeyond), findsOneWidget);
      expect(find.text('Waiting to load'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('local-web-retry')), findsNothing);
      await _finish(tester, page);
      expect(find.byKey(const ValueKey('lite-web-loading')), findsNothing);
      // A favicon/resource failure must not replace a usable PIN form.
      page.delegate!.onWebResourceError!(
        const WebResourceError(errorCode: -2, description: 'fixture_icon_failure', isForMainFrame: false),
      );
      await pumpFrames(tester, 2);
      expect(find.text(appL10n.webComputerCheckConnection), findsNothing);
      page.fail();
      await pumpFrames(tester, 2);
      expect(find.text(appL10n.webComputerCheckConnection), findsOneWidget);
      expect(find.text(appL10n.webCheckConnection), findsNothing);
      expect(find.byKey(const ValueKey('lite-web-loading')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, appL10n.commonRetry));
      expect(page.loads, [_lan, _lan]);
      page.start();
      await pumpFrames(tester, 2);
      expect(find.byKey(const ValueKey('lite-web-loading')), findsOneWidget);
      expect(find.text(appL10n.webComputerCheckConnection), findsNothing);
      await _finish(tester, page);
      expect(find.byKey(const ValueKey('lite-web-loading')), findsNothing);
      expect(platform.controllers, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('connection selector return keeps the computer renderer and its login navigation', (tester) async {
      final platform = await _computer(tester);
      final page = platform.controller;
      await _finish(tester, page);
      await tester.tap(find.byKey(const ValueKey('web-connection-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(platform.controllers, hasLength(1));
      expect(page.loads, [_lan]);
      expect(page.reloads, 0);
      expect(find.byType(WebHome), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('root Back closes page state, then history, then exits instead of popping the home', (tester) async {
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final platform = await _computer(tester);
      final page = platform.controller;
      await _finish(tester, page);
      final answers = ['"layer"', '"none"', '"none"'];
      page.results = (script) => script == WebBack.script ? answers.removeAt(0) : false;
      page.history = 1;
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, 2);
      expect(page.goBacks, 0);
      expect(platformCalls.where((s) => s == 'SystemNavigator.pop'), isEmpty);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, 2);
      expect(page.goBacks, 1);
      expect(platformCalls.where((s) => s == 'SystemNavigator.pop'), isEmpty);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, 2);
      expect(platformCalls.where((s) => s == 'SystemNavigator.pop'), hasLength(1));
      expect(find.byType(WebHome), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final failed in [false, true]) {
      testWidgets('root Back exits even before PIN load completes, resource failure=$failed', (tester) async {
        var exits = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final platform = await _computer(tester);
        if (failed) platform.controller.fail();
        platform.controller.results = (_) => throw StateError('loading_or_error_page_asked_for_back');
        await tester.binding.handlePopRoute();
        await pumpFrames(tester, 2);
        expect(exits, 1);
        expect(tester.takeException(), isNull);
      });
    }
  });

  final node = _node();
  test('no-#root PIN document keeps its form and input event paths after phone and inset injection', () async {
    final variants = <Map<String, Object>>[];
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      for (final keyboard in [0.0, 300.0]) {
        variants.add({
          'script': WebPageInsets.resolve(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 16),
            keyboard: keyboard,
            dshWeb: true,
            adapt: true,
            leadingAtBottom: true,
          ).script,
          'keyboard': keyboard,
        });
      }
    }
    final result = await Process.run(node!, [
      'test/local_web_lite/support/pin_document_harness.mjs',
      jsonEncode(variants),
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final rows = (jsonDecode(result.stdout as String) as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(variants.length));
    for (final row in rows) {
      expect(row['action'], '/_remote/login');
      expect(row['method'], 'post');
      expect(row['pin'], 'TESTPIN123');
      expect(row['prevented'], isEmpty);
      expect(row['stopped'], isEmpty);
      // A page without #root has no composer padding of its own: it keeps clear
      // of the whole native row, unlike DSH Web's composer.
      expect(row['bodyInsets'], contains('body{padding-top:24.0px!important;padding-bottom:64.0px!important'));
      expect(row['bodyInsets'], isNot(contains('overflow:hidden')));
      expect(row['bodyInsets'], isNot(contains('#root{')));
      expect(row['keyboardSheet'], '');
      expect(row['seatSheet'], '');
      expect(row['readsLocalStorage'], 0);
    }
  }, skip: node == null ? 'node is not installed' : false);
}
