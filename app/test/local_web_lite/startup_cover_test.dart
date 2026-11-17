import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_app/ui/web/startup_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/lite_harness.dart';

void main() {
  test('startup asset retains the original 40 frame looping GIF', () async {
    final bytes = File(StartupCover.asset).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
    final codec = await ui.instantiateImageCodec(bytes);
    addTearDown(codec.dispose);
    expect(codec.frameCount, 40);
    expect(codec.repetitionCount, -1);
    final first = await codec.getNextFrame();
    expect(first.image.width, 512);
    expect(first.image.height, 768);
    first.image.dispose();
  });

  for (final size in [const Size(390, 844), const Size(844, 390), const Size(320, 568)]) {
    testWidgets('cover and slogan fit below the dress at $size without loading UI', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: SafeArea(child: Center(child: StartupCover())),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      final image = find.byKey(const ValueKey('local-web-startup-cover'));
      final slogan = find.byKey(const ValueKey('local-web-startup-tagline'));
      expect(image, findsOneWidget);
      expect(find.text('探索未至之境'), findsOneWidget);
      final style = tester.widget<Text>(slogan).style!;
      expect(style.fontSize, 22);
      expect(style.letterSpacing, 4);
      expect(style.fontWeight, FontWeight.w500);
      expect(tester.getRect(slogan).top, greaterThan(tester.getRect(image).bottom));
      expect(tester.getRect(slogan).bottom, lessThanOrEqualTo(size.height));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
