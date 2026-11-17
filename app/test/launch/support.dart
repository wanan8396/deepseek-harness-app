import 'dart:async';

import 'package:dsh_app/launch/launch_state.dart';
import 'package:dsh_app/ui/launch/launch_overlay.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_fonts.dart';

class FakeLaunchChannel extends LaunchChannel {
  FakeLaunchChannel({this.answer});

  final Map<Object?, Object?>? answer;
  final calls = <String>[];
  final marks = <String>[];
  void Function({bool removed})? onSystemSplash;
  Completer<void>? fading;

  @override
  Future<Map<Object?, Object?>?> begin() async {
    calls.add('begin');
    return answer;
  }

  @override
  Future<bool> reveal() async {
    calls.add('reveal');
    if (fading case final f?) await f.future;
    return true;
  }

  @override
  Future<void> mark(String name) async => marks.add(name);

  @override
  Future<void> done() async => calls.add('done');

  @override
  void listen(void Function({bool removed}) onSystemSplash) => this.onSystemSplash = onSystemSplash;

  @override
  void stopListening() => calls.add('stopListening');
}

LaunchSnapshot snapshotFor({bool systemSplash = true, bool dark = false, bool coldEngine = false}) => LaunchSnapshot(
  systemSplash: systemSplash,
  dark: dark,
  coldEngine: coldEngine,
);

void usePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.padding = const FakeViewPadding(top: 64, bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 48);
  addTearDown(tester.view.reset);
}

Widget launchApp(
  LaunchController controller, {
  Brightness brightness = Brightness.light,
  bool? reduceMotion,
  Widget home = const Scaffold(body: Center(child: Text('home'))),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: withTestFonts(buildLightTheme()),
  darkTheme: withTestFonts(buildDarkTheme()),
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => Stack(
    fit: StackFit.expand,
    // Same per-controller key as LaunchLayer: a second controller must reach a fresh
    // overlay State, whose initState is what calls firstFrame() for it.
    children: [child!, LaunchOverlay(key: ObjectKey(controller), controller: controller, reduceMotion: reduceMotion)],
  ),
  home: home,
);

const launchLeaveDuration = Duration(milliseconds: 300);
