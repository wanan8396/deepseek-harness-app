import 'dart:async';

import 'package:dsh_app/ui/theme/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<GlobalKey<NavigatorState>> openPage(
  WidgetTester tester, {
  bool canPop = true,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.android: AppPageTransitionsBuilder()},
        ),
        platform: TargetPlatform.android,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          systemGestureInsets: const EdgeInsets.symmetric(horizontal: 32),
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: const Scaffold(body: Text('Home')),
    ),
  );
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PopScope(
          canPop: canPop,
          child: const Scaffold(body: Center(child: Text('Child page'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('swipe starts inside the Android reserved edge ($direction)', (tester) async {
      final navigator = await openPage(tester, direction: direction);
      final rtl = direction == TextDirection.rtl;
      // Outside the OS-owned 32px strip and the old 20px application strip.
      await tester.timedDragFrom(
        Offset(rtl ? 358 : 42, 400),
        Offset(rtl ? -280 : 280, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), false);
      expect(find.text('Child page'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short edge swipe settles on the current page', (tester) async {
    final navigator = await openPage(tester);
    final gesture = await tester.startGesture(const Offset(42, 400));
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), true);
    expect(find.text('Child page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded touch strip still respects PopScope', (tester) async {
    final navigator = await openPage(tester, canPop: false);
    await tester.timedDragFrom(const Offset(42, 400), const Offset(280, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), true);
    expect(find.text('Child page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical movement and drags outside the edge keep the page', (tester) async {
    final navigator = await openPage(tester);
    await tester.timedDragFrom(const Offset(42, 400), const Offset(0, 180), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.timedDragFrom(const Offset(120, 400), const Offset(250, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), true);
    expect(find.text('Child page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
