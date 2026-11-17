// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dsh/runtime');
  late Map<String, Object?> status;
  late List<MethodCall> calls;
  Completer<Map<String, Object?>>? delayed;
  const reply = {
    'generation': 3,
    'text': 'synthetic-viewer-fixture',
    'displayName': 'cordis.patch.yml',
    'profile': 'web',
    'relativeDisplayPath': '/root/.dsh/profiles/web/cordis.patch.yml',
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    delayed = null;
    status = {'phase': 'running', 'baseUrl': 'http://127.0.0.1:41234/', 'token': 'synthetic-token', 'generation': 3};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getStatus') return status;
      if (call.method == 'readLocalSettingsDocument') return delayed == null ? reply : delayed!.future;
      return null;
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );
  Future<FakeWebViewController> open(WidgetTester tester, {bool computer = false}) async {
    final platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      testApp(
        WebViewPage(
          url: Uri.parse(computer ? 'http://192.0.2.10:3090/' : 'http://127.0.0.1:41234/'),
          title: 'Fixture',
          dshWeb: true,
          computerWeb: computer,
          root: true,
        ),
        overrides: ShellHarness().overrides,
      ),
    );
    for (var i = 0; i < 30 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final page = platform.controller;
    page.finish();
    for (
      var i = 0;
      i < 100 && (!computer && !page.scripts.any((s) => s.contains('__dshSettingsDocumentDispose')));
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    if (!computer) {
      expect(
        page.scripts.any((s) => s.contains('__dshSettingsDocumentDispose')),
        isTrue,
        reason:
            'Bridge initialization: phase=${status["phase"]}, generation=${status["generation"]}, calls=${calls.map((c) => c.method).toList()}, scripts=${page.scripts.length}',
      );
    }
    return page;
  }

  String nonce(FakeWebViewController page) {
    final script = page.scripts.lastWhere((s) => s.contains('__dshSettingsDocumentDispose'));
    return jsonDecode(RegExp(r'\}\)\(("[^"\n]+")\);\s*$').firstMatch(script)!.group(1)!) as String;
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('computer pages never register or request local configuration reads', (tester) async {
    final page = await open(tester, computer: true);
    await frames(tester);
    expect(page.channels, isNot(contains('DshAppSettingsDocument')));
    expect(calls, isEmpty);
    expect(page.scripts.any((s) => s.contains('__dshSettingsDocumentDispose')), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('local action opens only in Flutter and never returns document text to JS', (tester) async {
    final page = await open(tester);
    page.post('DshAppSettingsDocument', nonce(page));
    await frames(tester);
    expect(find.text('synthetic-viewer-fixture'), findsOneWidget);
    expect(calls.where((c) => c.method == 'readLocalSettingsDocument'), hasLength(1));
    expect(page.scripts.any((s) => s.contains('synthetic-viewer-fixture')), isFalse);
    status = {...status, 'phase': 'installed'};
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(find.text('synthetic-viewer-fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('bad page ticket never invokes native reads', (tester) async {
    final page = await open(tester);
    page.post('DshAppSettingsDocument', 'old-or-forged-ticket');
    await frames(tester);
    expect(calls.where((c) => c.method == 'readLocalSettingsDocument'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('navigation retires a pending configuration result', (tester) async {
    final page = await open(tester);
    delayed = Completer<Map<String, Object?>>();
    page.post('DshAppSettingsDocument', nonce(page));
    await frames(tester);
    expect(calls.where((c) => c.method == 'readLocalSettingsDocument'), hasLength(1));
    page.start();
    delayed!.complete(reply);
    await frames(tester);
    expect(find.text('synthetic-viewer-fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
