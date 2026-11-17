// Where an open lands in DSH Web: the names a plugin card target carries
// (web_target.dart), and that the landing waits out a load that failed
// (web_view_page.dart): the WebView finishes its own error page too, and the
// one landing an open gets was spent there, so 重试 came back on the home page.

// ignore_for_file: depend_on_referenced_packages


import 'package:dsh_app/ui/web/web_target.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import 'support/fake_webview.dart';

void main() {
  group('landing after a failed load', () {
    late FakeWebViewPlatform platform;
    setUp(() => WebViewPlatform.instance = platform = FakeWebViewPlatform());

    Iterable<String> opens() =>
        platform.controller.scripts.where((s) => s.startsWith('window.__dshAppOpen && window.__dshAppOpen('));

    /// Lets the bridges load from the asset bundle (real time), then frames.
    Future<void> injected(WidgetTester tester, int backBridges) async {
      for (var i = 0; i < 40 && platform.controller.scripts.where((s) => s.contains('__dshAppBack =')).length < backBridges; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('the target waits for the load that works, and lands once', (tester) async {
      await tester.pumpWidget(
        testApp(
          WebViewPage(
            url: Uri.parse('http://127.0.0.1:3080/?token=t'),
            title: '网页版',
            dshWeb: true,
            openTarget: const DshWebTarget(sessionId: 'retained-conversation'),
          ),
        ),
      );
      for (var i = 0; i < 20 && platform.controller.loads.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      // The engine isn't answering yet: Android finishes its error page too.
      platform.controller
        ..start()
        ..fail()
        ..finish();
      await injected(tester, 1);
      expect(find.text('页面没有打开'), findsOneWidget);
      expect(opens(), isEmpty, reason: 'not spent on the error page');
      expect(platform.controller.scripts.where((s) => s.contains('window.__dshAppOpen = function')), isEmpty);

      await tester.tap(find.text('重试'));
      await tester.pump();
      platform.controller
        ..start()
        ..finish();
      await injected(tester, 2);
      expect(find.text('页面没有打开'), findsNothing);
      expect(opens(), hasLength(1));
      expect(opens().single, contains('"session":"retained-conversation"'));

      // A later load (a conversation hop) is the bridge's to finish.
      platform.controller
        ..start()
        ..finish();
      await injected(tester, 3);
      expect(opens(), hasLength(1));
    });
  });
}
