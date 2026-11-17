import 'package:dsh_app/state/web_appearance_state.dart';
import 'package:dsh_app/ui/settings/local_web_settings_screen.dart';
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

Future<FakeWebViewController> _mount(WidgetTester tester, {bool root = true}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final platform = FakeWebViewPlatform();
  WebViewPlatform.instance = platform;
  await tester.pumpWidget(
    testApp(
      WebViewPage(
        url: Uri.parse('http://example.invalid/'),
        title: 'fixture',
        dshWeb: true,
        root: root,
        leadingAtBottom: true,
        leading: (size) => WebHandleButton(size: size, onSidebar: () {}),
      ),
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
    i < 30 &&
        root &&
        (!page.scripts.any((s) => s.contains('window.__dshAppAppearance')) ||
            !page.scripts.any((s) => s.contains('window.__dshAppHeaderMenus')));
    i++
  ) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await pumpFrames(tester);
  return page;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('appearance reports accept only light/dark without creating persisted settings', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(webAppearanceProvider.notifier);
    expect(container.read(webAppearanceProvider), isNull);
    controller.report('invalid');
    expect(container.read(webAppearanceProvider), isNull);
    controller.report('dark');
    expect(container.read(webAppearanceProvider), Brightness.dark);
    controller.report('light');
    controller.report('{"dark":true}');
    expect(container.read(webAppearanceProvider), Brightness.light);
  });

  group('Lite connection appearance matches webpage', () {
    for (final dark in [false, true]) {
      testWidgets('actual web ${dark ? 'dark' : 'light'} panel colors and all controls agree', (tester) async {
        final page = await _mount(tester);
        expect(page.channels, contains('DshAppAppearance'));
        expect(page.scripts.where((s) => s.contains('window.__dshAppAppearance')), hasLength(1));
        expect(page.scripts.where((s) => s.contains('window.__dshAppHeaderMenus')), hasLength(1));
        page.post('DshAppAppearance', dark ? 'dark' : 'light');
        await pumpFrames(tester);
        final image = tester.widget<Image>(
          find.descendant(of: find.byType(WebHandleButton), matching: find.byType(Image)),
        );
        expect(
          (image.image as AssetImage).assetName,
          dark ? 'assets/branding/whale-dark.png' : 'assets/branding/whale.png',
        );
        await tester.tap(find.byKey(const ValueKey('web-connection-switch')));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ListView));
        final theme = Theme.of(context);
        final ink = dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);
        final surface = dark ? const Color(0xFF2C2C2E) : Colors.white;
        expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
        expect(theme.scaffoldBackgroundColor, surface);
        expect(theme.colorScheme.surface, surface);
        expect(theme.colorScheme.primary, ink);
        expect(theme.colorScheme.onSurface, ink);
        expect(theme.colorScheme.onSurfaceVariant, dark ? const Color(0xFFCFD3D6) : const Color(0xFF61666B));
        expect(theme.listTileTheme.selectedColor, ink);
        expect(theme.listTileTheme.selectedTileColor, dark ? const Color(0xFF43454A) : const Color(0xFFEBEEF2));
        expect(theme.filledButtonTheme.style!.backgroundColor!.resolve({}), ink);
        expect(theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}), ink);
        expect(theme.textButtonTheme.style!.foregroundColor!.resolve({}), ink);
        expect(theme.textSelectionTheme.cursorColor, ink);
        // Changing the webpage setting updates an open native route as well.
        page.post('DshAppAppearance', dark ? 'light' : 'dark');
        await pumpFrames(tester);
        expect(Theme.of(tester.element(find.byType(ListView))).brightness, dark ? Brightness.light : Brightness.dark);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect((WebViewPlatform.instance as FakeWebViewPlatform).controllers, hasLength(1));
        expect(page.loads, hasLength(1));
        expect(page.reloads, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('non-root pages do not register a global appearance channel', (tester) async {
      final page = await _mount(tester, root: false);
      expect(page.channels, isNot(contains('DshAppAppearance')));
      expect(page.scripts.where((s) => s.contains('window.__dshAppAppearance')), isEmpty);
      expect(page.scripts.where((s) => s.contains('window.__dshAppHeaderMenus')), isEmpty);
      expect(find.byType(LocalWebSettingsScreen), findsNothing);
    });
  });

}
