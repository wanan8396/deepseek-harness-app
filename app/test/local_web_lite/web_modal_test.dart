// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/ui/web/web_view_platform.dart' as native;
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

String? _node() {
  for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    final candidate = File(
      '${dir.replaceAll('"', '')}${Platform.pathSeparator}${Platform.isWindows ? 'node.exe' : 'node'}',
    );
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

Future<FakeWebViewController> _page(
  WidgetTester tester, {
  bool root = true,
  bool adapt = true,
  bool bottom = true,
}) async {
  usePhoneView(tester);
  final platform = FakeWebViewPlatform();
  WebViewPlatform.instance = platform;
  await tester.pumpWidget(
    testApp(
      WebViewPage(
        url: Uri.parse('http://192.0.2.10:3090/'),
        title: 'Computer',
        computerWeb: true,
        dshWeb: true,
        root: root,
        phoneLayout: adapt,
        leadingAtBottom: bottom,
        leading: (size) => WebHandleButton(size: size, onSidebar: () {}),
      ),
      overrides: ShellHarness().overrides,
    ),
  );
  for (var i = 0; i < 30 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  final page = platform.controller;
  expect(page.loads, hasLength(1));
  page.finish();
  for (var i = 0; i < 40 && !page.scripts.any((s) => s.contains('window.__dshAppModal')); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (!root) break;
  }
  await pumpFrames(tester, 2);
  return page;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final old = native.WebViewPlatform.instance;
    native.WebViewPlatform.instance = FakeNativeWebViewPlatform();
    addTearDown(() => native.WebViewPlatform.instance = old);
  });

  group('Lite visible modal handoff', () {
    for (final adapt in [true, false]) {
      for (final bottom in [true, false]) {
        testWidgets('dialog hides native controls and restores the same renderer, adapt=$adapt bottom=$bottom', (
          tester,
        ) async {
          final page = await _page(tester, adapt: adapt, bottom: bottom);
          final platform = WebViewPlatform.instance as FakeWebViewPlatform;
          final connection = find.byKey(const ValueKey('web-connection-switch'));
          expect(page.channels, contains('DshAppModal'));
          expect(page.scripts.where((s) => s.contains('window.__dshAppModal')), hasLength(1));
          final before = tester.getRect(find.byKey(fakeWebViewKey));
          final insets = page.insetsScript;
          final native = find.byType(WebHandleButton);
          final top = find.byKey(ValueKey(adapt ? 'web-controls-inline' : 'web-controls-seat'));
          expect(native, findsOneWidget);
          expect(top, bottom ? findsNothing : findsOneWidget);
          expect(connection, bottom ? findsOneWidget : findsNothing);
          page.post('DshAppModal', 'open');
          await pumpFrames(tester, 2);
          expect(native, findsNothing);
          expect(connection, findsNothing);
          expect(top, findsNothing);
          expect(find.byKey(const ValueKey('web-controls-bottom')), findsNothing);
          expect(tester.getRect(find.byKey(fakeWebViewKey)), before);
          expect(page.insetsScript, insets);
          expect(page.loads, hasLength(1));
          page.post('DshAppModal', 'garbage');
          await pumpFrames(tester, 2);
          expect(native, findsNothing);
          page.post('DshAppModal', 'closed');
          await pumpFrames(tester, 2);
          expect(native, findsOneWidget);
          expect(top, bottom ? findsNothing : findsOneWidget);
          expect(connection, bottom ? findsOneWidget : findsNothing);
          expect(page.loads, hasLength(1));
          expect(platform.controllers, hasLength(1));
          expect(platform.controller, same(page));
          expect(tester.getRect(find.byKey(fakeWebViewKey)), before);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('sidebar keeps bottom controls reachable while real modal and keyboard still suppress them', (tester) async {
      final page = await _page(tester);
      final platform = WebViewPlatform.instance as FakeWebViewPlatform;
      final viewport = tester.getRect(find.byKey(fakeWebViewKey));
      page.post('DshAppSidebar', 'open');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(find.byKey(const ValueKey('web-connection-switch')), findsOneWidget);
      page.post('DshAppModal', 'open');
      page.post('DshAppSidebar', 'closed');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsNothing);
      page.post('DshAppModal', 'closed');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(find.byKey(const ValueKey('web-connection-switch')), findsOneWidget);
      page.post('DshAppSidebar', 'open');
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await pumpFrames(tester, 3);
      page.post('DshAppSidebar', 'closed');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsNothing);
      tester.view.viewInsets = const FakeViewPadding();
      await pumpFrames(tester, 3);
      expect(find.byType(WebHandleButton), findsOneWidget);
      expect(platform.controllers, hasLength(1));
      expect(page.loads, hasLength(1));
      expect(tester.getRect(find.byKey(fakeWebViewKey)), viewport);
      expect(tester.takeException(), isNull);
    });

    testWidgets('modal and keyboard handoff never restores either bottom control early', (tester) async {
      final page = await _page(tester);
      final platform = WebViewPlatform.instance as FakeWebViewPlatform;
      final viewport = tester.getRect(find.byKey(fakeWebViewKey));
      final whale = find.byType(WebHandleButton);
      final connection = find.byKey(const ValueKey('web-connection-switch'));
      page.post('DshAppModal', 'open');
      await pumpFrames(tester, 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      tester.view.padding = const FakeViewPadding(top: 48);
      await pumpFrames(tester, 3);
      page.post('DshAppModal', 'closed');
      await pumpFrames(tester, 2);
      expect(whale, findsNothing);
      expect(connection, findsNothing);
      page.post('DshAppModal', 'open');
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
      await pumpFrames(tester, 3);
      expect(whale, findsNothing);
      expect(connection, findsNothing);
      page.post('DshAppModal', 'closed');
      await pumpFrames(tester, 2);
      expect(whale, findsOneWidget);
      expect(connection, findsOneWidget);
      expect(platform.controllers, hasLength(1));
      expect(platform.controller, same(page));
      expect(page.loads, hasLength(1));
      expect(tester.getRect(find.byKey(fakeWebViewKey)), viewport);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation clears an old document modal and injects observer on the next page', (tester) async {
      final page = await _page(tester);
      page.post('DshAppModal', 'open');
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsNothing);
      page.start();
      await pumpFrames(tester, 2);
      expect(find.byType(WebHandleButton), findsOneWidget);
      page.finish();
      for (var i = 0; i < 20 && page.scripts.where((s) => s.contains('window.__dshAppModal')).length < 2; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(page.scripts.where((s) => s.contains('window.__dshAppModal')), hasLength(2));
      expect(page.loads, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('full edition and non-root pages retain their original controls without a modal channel', (tester) async {
    final page = await _page(tester, root: false);
    expect(page.channels, isNot(contains('DshAppModal')));
    expect(page.scripts.where((s) => s.contains('window.__dshAppModal')), isEmpty);
    expect(find.byType(WebHandleButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final node = _node();
  test('observer reports only visible dialogs, is idempotent, and never consumes form events', () async {
    final result = await Process.run(node!, ['test/local_web_lite/support/modal_bridge_harness.mjs']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(out['observeCount'], 1);
    expect(out['messages'], ['closed', 'open', 'closed', 'open', 'closed', 'open', 'closed', 'open']);
    expect(out['events'], unorderedEquals(['transitionend', 'animationend']));
  }, skip: node == null ? 'node is not installed' : false);
}
