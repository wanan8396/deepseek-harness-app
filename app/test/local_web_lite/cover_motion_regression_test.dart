// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/launch/launch_overlay.dart';
import 'package:dsh_app/ui/web/web_view_platform.dart' as native;
import 'package:dsh_app/ui/web/startup_cover.dart';
import 'package:dsh_app/ui/web/web_handle.dart';
import 'package:dsh_app/ui/web/web_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

const _coverKey = ValueKey('local-web-startup-cover');
const _loadingKey = ValueKey('lite-web-loading');
final _url = Uri.parse('http://192.0.2.10:3090/');
const _sidebarScript = 'window.__dshApp && window.__dshApp.toggleSidebar()';

typedef _Pixels = ({String whole, String face});
typedef _GifFrame = ({Duration duration, _Pixels pixels});

Future<_Pixels> _pixels(ui.Image image) async {
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  // Original 512x768 asset: only the face/eyes, not the moving dress or hair.
  final face = BytesBuilder(copy: false);
  for (var y = 80; y < 200; y++) {
    final start = (y * image.width + 190) * 4;
    face.add(Uint8List.sublistView(bytes, start, start + 140 * 4));
  }
  return (whole: sha256.convert(bytes).toString(), face: sha256.convert(face.takeBytes()).toString());
}

Future<List<_GifFrame>> _referenceFrames() async {
  final asset = await rootBundle.load(StartupCover.asset);
  final codec = await ui.instantiateImageCodec(asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes));
  try {
    expect(codec.frameCount, 40);
    expect(codec.repetitionCount, -1);
    final frames = <_GifFrame>[];
    for (var i = 0; i <= 32; i++) {
      final frame = await codec.getNextFrame();
      try {
        expect((frame.image.width, frame.image.height), (512, 768));
        frames.add((duration: frame.duration, pixels: await _pixels(frame.image)));
      } finally {
        frame.image.dispose();
      }
    }
    return frames;
  } finally {
    codec.dispose();
  }
}

/// Observes the same AssetImage stream used by the real Image widget. No fake
/// codec/frameBuilder: decode must complete, then the widget must paint it.
class _FrameObserver {
  _FrameObserver(WidgetTester tester) {
    final finder = find.byKey(_coverKey);
    final widget = tester.widget<Image>(finder);
    expect(widget.image, isA<AssetImage>());
    expect((widget.image as AssetImage).assetName, StartupCover.asset);
    stream = widget.image.resolve(createLocalImageConfiguration(tester.element(finder)));
    listener = ImageStreamListener((info, _) {
      emitted++;
      info.dispose();
    });
    stream.addListener(listener);
  }

  late final ImageStream stream;
  late final ImageStreamListener listener;
  int emitted = 0;

  Future<void> waitFor(WidgetTester tester, int count) async {
    // Native image decoding is real async, not advanced by one giant fake-clock
    // pump. Keep fake time fixed while waiting for each requested frame.
    for (var attempt = 0; attempt < 100 && emitted < count; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(emitted, count, reason: 'AssetImage must actually emit frame ${count - 1}');
    await tester.pump();
  }

  void dispose() => stream.removeListener(listener);
}

Future<_Pixels> _renderedPixels(WidgetTester tester) async {
  final raw = find.descendant(of: find.byKey(_coverKey), matching: find.byType(RawImage));
  expect(raw, findsOneWidget);
  final widget = tester.widget<RawImage>(raw);
  final render = tester.renderObject<RenderImage>(raw);
  expect(widget.image, isNotNull);
  expect(render.image, isNotNull);
  expect(render.image!.isCloneOf(widget.image!), isTrue);
  return (await tester.runAsync(() => _pixels(render.image!)))!;
}

LaunchController _coldController() => LaunchController(
  snapshot: const LaunchSnapshot(systemSplash: false, dark: false, coldEngine: true),
);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  var remaining = duration;
  const frame = Duration(milliseconds: 10);
  while (remaining > Duration.zero) {
    final step = remaining < frame ? remaining : frame;
    await tester.pump(step);
    remaining -= step;
  }
}

class _ComputerConnection extends WebConnectionController {
  @override
  WebConnectionState build() {
    ready = Future<void>.value();
    return WebConnectionState(loaded: true, mode: WebConnectionMode.computer, computerUrl: _url.toString());
  }
}

/// Only the platform surface is faked; WebViewPage and its cover are untouched.
class _TouchPlatform extends FakeWebViewPlatform {
  int pageTaps = 0;

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) =>
      _TouchSurface(params, () => pageTaps++);
}

class _TouchSurface extends PlatformWebViewWidget {
  _TouchSurface(super.params, this.onTap) : super.implementation();
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: fakeWebViewKey,
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const SizedBox.expand(),
  );
}

Future<_TouchPlatform> _webPage(WidgetTester tester) async {
  usePhoneView(tester);
  final before = WebViewPlatform.instance;
  final platform = _TouchPlatform();
  WebViewPlatform.instance = platform;
  if (before != null) addTearDown(() => WebViewPlatform.instance = before);
  await tester.pumpWidget(
    testApp(
      WebViewPage(
        url: _url,
        title: 'Computer',
        computerWeb: true,
        dshWeb: true,
        root: true,
        leadingAtBottom: true,
        leading: (size) => WebHandleButton(size: size, onSidebar: () {}),
      ),
      overrides: [webConnectionProvider.overrideWith(_ComputerConnection.new)],
    ),
  );
  for (var i = 0; i < 40 && (platform.controllers.isEmpty || platform.controller.loads.isEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  expect(platform.controllers, hasLength(1));
  expect(platform.controller.loads, [_url]);
  expect(platform.controller.delegate!.onPageFinished, isNotNull);
  return platform;
}

double _coverOpacity(WidgetTester tester) {
  final fade = find.descendant(of: find.byKey(_loadingKey), matching: find.byType(FadeTransition));
  expect(fade, findsOneWidget);
  return tester.widget<FadeTransition>(fade).opacity.value;
}

int _sidebarTaps(FakeWebViewController controller) => controller.scripts.where((s) => s == _sidebarScript).length;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebKeyboard.forgetHeights();
    final before = native.WebViewPlatform.instance;
    native.WebViewPlatform.instance = FakeNativeWebViewPlatform();
    addTearDown(() => native.WebViewPlatform.instance = before);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final ancestorReduced in [false, true]) {
    testWidgets('real AssetImage paints frames 0/20/32 at GIF times; ancestor reduced=$ancestorReduced', (
      tester,
    ) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures();
      addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final frames = (await tester.runAsync(_referenceFrames))!;
      expect(frames.first.duration, const Duration(milliseconds: 850));
      Duration startsAt(int index) => frames.take(index).fold(Duration.zero, (sum, frame) => sum + frame.duration);
      expect(startsAt(20), const Duration(milliseconds: 1990));
      expect(startsAt(32), const Duration(milliseconds: 2710));
      expect(frames[20].pixels.face, isNot(frames[0].pixels.face));
      expect(frames[32].pixels.face, isNot(frames[0].pixels.face));

      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: ancestorReduced),
                child: const Center(child: StartupCover()),
              ),
            ),
          ),
        ),
      );
      expect(MediaQuery.disableAnimationsOf(tester.element(find.byType(StartupCover))), ancestorReduced);
      expect(MediaQuery.disableAnimationsOf(tester.element(find.byKey(_coverKey))), isFalse);
      final observer = _FrameObserver(tester);
      await observer.waitFor(tester, 1);
      final first = await _renderedPixels(tester);
      expect(first, frames[0].pixels, reason: 'RawImage/RenderImage must really start on frame 0');
      debugPrint('rendered GIF frame=0 elapsed=0ms face=${first.face}');

      var elapsed = Duration.zero;
      for (var i = 1; i <= 32; i++) {
        final nextStart = startsAt(i);
        await tester.pump(nextStart - elapsed);
        elapsed = nextStart;
        await observer.waitFor(tester, i + 1);
        if (i == 20 || i == 32) {
          if (i == 20) {
            // Hold frame 20 beyond 2s, not just at its 1990ms leading edge.
            const afterTwoSeconds = Duration(milliseconds: 2010);
            final extra = afterTwoSeconds - elapsed;
            expect(extra, lessThan(frames[i].duration));
            await tester.pump(extra);
            elapsed += extra;
          }
          final rendered = await _renderedPixels(tester);
          expect(rendered, frames[i].pixels, reason: 'real RawImage at frame $i, elapsed=$elapsed');
          expect(rendered.whole, isNot(first.whole));
          expect(rendered.face, isNot(first.face));
          debugPrint('rendered GIF frame=$i elapsed=${elapsed.inMilliseconds}ms face=${rendered.face}');
        }
      }
      expect(elapsed, const Duration(milliseconds: 2710));
      expect(tester.takeException(), isNull);
      observer.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  testWidgets('real system reduced motion pauses the rendered GIF even if its stream keeps decoding', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final frames = (await tester.runAsync(_referenceFrames))!;
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const Scaffold(body: Center(child: StartupCover()))));
    expect(MediaQuery.disableAnimationsOf(tester.element(find.byKey(_coverKey))), isTrue);
    final observer = _FrameObserver(tester);
    await observer.waitFor(tester, 1);
    final first = await _renderedPixels(tester);
    expect(first, frames[0].pixels);
    var elapsed = Duration.zero;
    for (var i = 1; i <= 32; i++) {
      await tester.pump(frames[i - 1].duration);
      elapsed += frames[i - 1].duration;
      await observer.waitFor(tester, i + 1);
    }
    expect(elapsed, const Duration(milliseconds: 2710));
    expect(
      await _renderedPixels(tester),
      first,
      reason: 'the codec reached frame 32 but the actual reduced-motion RawImage stays on frame 0',
    );
    expect(tester.takeException(), isNull);
    observer.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  group('Lite cover motion regression', () {
    testWidgets('cold controller holds within the cover interval until motionDone', (tester) async {
      final controller = _coldController();
      addTearDown(controller.dispose);
      controller.firstFrame();
      controller.ready(waitsForEngine: true);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(controller.reduced, isFalse);
      expect(controller.holds, isTrue);
      expect(controller.phase, LaunchPhase.playing);
      controller.motionDone();
      expect(controller.holds, isFalse);
      expect(controller.phase, LaunchPhase.leaving);
      controller.gone();
      await tester.pump();
    });

    testWidgets('launch overlay matches the full-viewport loading stage geometry', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(const Scaffold(body: StartupStage())));
      await tester.pump();
      final imageRect = tester.getRect(find.byKey(_coverKey));
      final sloganRect = tester.getRect(find.byKey(const ValueKey('local-web-startup-tagline')));
      final controller = _coldController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(testApp(Scaffold(body: LaunchOverlay(controller: controller, reduceMotion: false))));
      await tester.pump();
      expect(tester.getRect(find.byKey(_coverKey)), imageRect);
      expect(tester.getRect(find.byKey(const ValueKey('local-web-startup-tagline'))), sloganRect);
      expect(tester.getRect(find.byType(StartupStage)).size, const Size(390, 844));
      controller.gone();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('cold overlay is not forced reduced; default 1360ms motion still ends before GIF eyes open', (
      tester,
    ) async {
      final controller = _coldController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(testApp(Scaffold(body: LaunchOverlay(controller: controller, reduceMotion: false))));
      await tester.pump();
      controller.ready(waitsForEngine: true);
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(controller.reduced, isFalse);
      expect(controller.holds, isTrue);
      expect(controller.phase, LaunchPhase.playing);
      expect(find.byKey(const ValueKey('lite-launch-stage')), findsOneWidget);
      expect(LaunchController.coverMotionDuration, const Duration(milliseconds: 1360));
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(controller.reduced, isFalse);
      expect(controller.phase, LaunchPhase.gone, reason: 'default motionDone + 300ms leave, not forced reduced');
      expect(find.byKey(const ValueKey('lite-launch-stage')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Lite overlay ignores ancestor performance reduction when system motion is enabled', (tester) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures();
      addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final controller = _coldController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: LaunchOverlay(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.ready(waitsForEngine: true);
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(controller.reduced, isFalse);
      expect(controller.holds, isTrue);
      expect(controller.phase, LaunchPhase.playing);
      controller.engineReady();
      await tester.pump();
      await _pumpFor(tester, const Duration(milliseconds: 310));
      expect(controller.phase, LaunchPhase.gone);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit reduced motion hands off immediately without waiting for engine or GIF', (tester) async {
      final controller = _coldController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(testApp(Scaffold(body: LaunchOverlay(controller: controller, reduceMotion: true))));
      await tester.pump();
      expect(controller.reduced, isTrue);
      controller.ready(waitsForEngine: true);
      await tester.pump();
      expect(controller.holds, isFalse);
      expect(controller.phase, LaunchPhase.gone);
      expect(find.byKey(const ValueKey('lite-launch-stage')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onPageFinished fades for 220ms, absorbs page taps, and preserves bottom-control layering', (
      tester,
    ) async {
      final platform = await _webPage(tester);
      final controller = platform.controller;
      final viewState = tester.state(find.byType(WebViewPage));
      final cover = find.byKey(_loadingKey);
      final bodyPoint = tester.getCenter(find.byKey(fakeWebViewKey));
      final whale = find.byType(WebHandleButton);
      final absorber = find.ancestor(of: cover, matching: find.byType(AbsorbPointer)).first;
      expect(tester.widget<AbsorbPointer>(absorber).absorbing, isTrue);
      expect(_coverOpacity(tester), 1);
      expect(tester.widget<AnimatedOpacity>(cover).duration, const Duration(milliseconds: 220));
      await tester.tapAt(bodyPoint);
      await tester.tap(whale);
      expect(platform.pageTaps, 0);
      expect(_sidebarTaps(controller), 0, reason: 'bottom whale is disabled while loading');

      controller.finish();
      await tester.pump();
      expect(cover, findsOneWidget);
      expect(_coverOpacity(tester), 1, reason: 'finish starts the fade instead of removing the cover');
      await tester.pump(const Duration(milliseconds: 110));
      expect(_coverOpacity(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.tapAt(bodyPoint);
      expect(platform.pageTaps, 0, reason: 'a partially transparent cover must still absorb page taps');
      // The actual native row is later in the Stack than the cover: AbsorbPointer
      // protects the WebView beneath, not the bottom controls painted above it.
      await tester.tap(whale);
      expect(_sidebarTaps(controller), 1, reason: 'bottom control remains above the fading page cover');
      await tester.pump(const Duration(milliseconds: 109));
      expect(cover, findsOneWidget);
      expect(_coverOpacity(tester), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(_coverOpacity(tester), closeTo(0, 0.000001));
      // Flutter's simulation marks completion on the first tick after 220ms.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(cover, findsNothing);
      await tester.tapAt(bodyPoint);
      await tester.tap(whale);
      expect(platform.pageTaps, 1);
      expect(_sidebarTaps(controller), 2);
      expect(tester.state(find.byType(WebViewPage)), same(viewState));
      expect(platform.controllers, [controller]);
      expect(controller.loads, [_url]);
      expect(controller.reloads, 0);
      await tester.pump(const Duration(milliseconds: 450));
      expect(tester.takeException(), isNull);
    });

    testWidgets('main-frame error removes a fading cover immediately; retry restores then fades the same view', (
      tester,
    ) async {
      final platform = await _webPage(tester);
      final controller = platform.controller;
      controller.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_coverOpacity(tester), allOf(greaterThan(0), lessThan(1)));
      controller.fail();
      await tester.pump();
      expect(find.byKey(_loadingKey), findsNothing);
      expect(find.text(appL10n.webComputerCheckConnection), findsOneWidget);
      final retry = find.widgetWithText(FilledButton, appL10n.commonRetry);
      expect(retry.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      expect(controller.loads, [_url, _url]);
      controller.start();
      await tester.pump();
      expect(find.text(appL10n.webComputerCheckConnection), findsNothing);
      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(_coverOpacity(tester), 1);
      controller.delegate!.onWebResourceError!(
        const WebResourceError(errorCode: -2, description: 'fixture_icon', isForMainFrame: false),
      );
      await tester.pump();
      expect(find.byKey(_loadingKey), findsOneWidget, reason: 'a subresource error is not a page failure');
      controller.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byKey(_loadingKey), findsNothing);
      expect(find.text(appL10n.webComputerCheckConnection), findsNothing);
      expect(platform.controllers, [controller]);
      expect(controller.reloads, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderer error releases cover; old controller finish does not release reopened page cover', (
      tester,
    ) async {
      final platform = await _webPage(tester);
      final old = platform.controller;
      final islands = native.WebViewPlatform.instance as FakeNativeWebViewPlatform;
      islands.gone(webViewId: old.webViewIdentifier);
      await tester.pump();
      expect(find.byKey(_loadingKey), findsNothing);
      expect(find.byType(RendererGone), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, appL10n.webReopen));
      await tester.pump();
      final current = platform.controllers.last;
      for (var i = 0; i < 20 && current.loads.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(platform.controllers, hasLength(2));
      expect(current, isNot(same(old)));
      expect(current.loads, [_url]);
      expect(find.byKey(_loadingKey), findsOneWidget);
      old.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(_coverOpacity(tester), 1, reason: 'stale onPageFinished must not fade the current controller');
      current.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byKey(_loadingKey), findsNothing);
      expect(current.loads, [_url]);
      expect(tester.takeException(), isNull);
    });
  });
}
