// Phone-shell fixtures only. No native chat, plugin, phone-control or remote graph.
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/onboarding_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/common/side_insets.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';
export 'test_fonts.dart' show cjkFamily, loadTestFonts;

ThemeData testTheme(Brightness brightness) {
  final base = brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme();
  return withTestFonts(base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const [cjkFamily])));
}

void usePhoneView(WidgetTester tester) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(tester.view.reset);
}

void usePhoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.padding = const FakeViewPadding(top: 64, bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 48);
  addTearDown(tester.view.reset);
}

Widget testApp(Widget home, {Brightness brightness = Brightness.light, List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: testTheme(Brightness.light),
        darkTheme: testTheme(Brightness.dark),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MirroredSideInsets(child: child!),
        home: home,
      ),
    );

class FakeRuntime extends LocalRuntimeController {
  FakeRuntime(this.initial);
  final LocalRuntimeState initial;
  @override
  LocalRuntimeState build() => initial;
  @override
  Future<void> install() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> reset() async {}
}

class StaticRuntime extends FakeRuntime {
  StaticRuntime() : super(const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.running)));
}

class FakeSettings extends SettingsController {
  FakeSettings([this.initial = const AppSettings(loaded: true)]);
  final AppSettings initial;
  @override
  AppSettings build() => initial;
  @override
  Future<void> setThemeMode(ThemeMode mode) async => state = state.copyWith(themeMode: mode);
  @override
  Future<void> setAutoStartLocal(bool value) async => state = state.copyWith(autoStartLocal: value);
  @override
  Future<void> setPhoneStorage(bool value) async => state = state.copyWith(phoneStorage: value);
}

typedef TestSettings = FakeSettings;

class FakeOnboardingPrefs extends OnboardingPrefsController {
  FakeOnboardingPrefs([this.initial = const OnboardingPrefs(loaded: true, welcomeSeen: true)]);
  final OnboardingPrefs initial;
  @override
  OnboardingPrefs build() => initial;
  @override
  Future<void> markWelcomeSeen() async => state = state.copyWith(welcomeSeen: true);
  @override
  Future<void> setSetupStep(SetupStep? step) async =>
      state = step == null ? state.copyWith(clearSetupStep: true) : state.copyWith(setupStep: step);
}

class FakeCurrentSession extends CurrentSessionController {
  FakeCurrentSession(this.initial);
  final String? initial;
  @override
  String? build() => initial;
}

typedef FixedSession = FakeCurrentSession;

class NoLocalEngine extends LocalConnectionController {
  @override
  Future<HostConnection?> build() async => null;
}

class ShellHarness {
  ShellHarness({this.session, this.settings = const AppSettings(loaded: true), this.runtime, this.extra = const []});
  final String? session;
  final AppSettings settings;
  final LocalRuntimeController Function()? runtime;
  final List<Override> extra;
  List<Override> get overrides => [
    localConnectionProvider.overrideWith(NoLocalEngine.new),
    localRuntimeProvider.overrideWith(runtime ?? StaticRuntime.new),
    settingsProvider.overrideWith(() => FakeSettings(settings)),
    currentSessionProvider.overrideWith(() => FakeCurrentSession(session)),
    ...extra,
  ];
}

Future<void> loadGoldenFonts() => loadTestFonts();
Widget goldenApp({required Widget home, required Brightness brightness, List<Override> overrides = const [],
  OnboardingPrefs? prefs, bool animations = false}) => testApp(
    Builder(builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations), child: home)),
    brightness: brightness,
    overrides: [
      localConnectionProvider.overrideWith(NoLocalEngine.new),
      onboardingPrefsProvider.overrideWith(() => FakeOnboardingPrefs(prefs ?? const OnboardingPrefs(loaded: true, welcomeSeen: true))),
      ...overrides,
    ],
  );

void goldenBoth(String name, Widget Function() home, {List<Override> Function()? overrides,
  Future<void> Function(WidgetTester)? before}) {
  for (final brightness in Brightness.values) {
    testWidgets('$name (${brightness.name})', (tester) async {
      await tester.runAsync(loadGoldenFonts);
      usePhoneSurface(tester);
      await tester.pumpWidget(goldenApp(home: home(), brightness: brightness, overrides: overrides?.call() ?? const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      if (before != null) await before(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_${brightness.name}.png'));
    });
  }
}

Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) { await tester.pump(const Duration(milliseconds: 100)); }
}
void mockClipboard(WidgetTester tester) => tester.binding.defaultBinaryMessenger
    .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

const runningStatus = RuntimeStatus(phase: RuntimePhase.running, abi: 'arm64-v8a',
  bundledVersion: 'official-rc3-fixture', installedVersion: 'official-rc3-fixture',
  dshVersion: '0.2.2-rc.5', nodeVersion: '24.22.1', baseUrl: 'http://127.0.0.1:3080', token: 'fixture-token');
const sampleLogs = ['[dsh-app] runtime ready', 'dsh web: http://127.0.0.1:3080/?token=•••'];
