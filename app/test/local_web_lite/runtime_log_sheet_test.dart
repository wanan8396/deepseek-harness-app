import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/ui/common/app_sheet.dart';
import 'package:dsh_app/ui/onboarding/runtime_setup_page.dart';
import 'package:dsh_app/ui/onboarding/setup_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/lite_harness.dart';

class _Logs extends LocalRuntimeLogsController {
  _Logs(this.initial);
  final List<String> initial;

  @override
  List<String> build() => initial;

  void emit(List<String> lines) => state = lines;
}

Future<_Logs> _openLogs(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<String> lines = const ['[dsh-app] preparing runtime', 'unpacking files'],
  Brightness brightness = Brightness.light,
  double scale = 1,
  double keyboard = 0,
  FakeRuntime? runtime,
}) async {
  usePhoneSurface(tester);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * tester.view.devicePixelRatio);
  if (keyboard > 0) tester.view.padding = const FakeViewPadding(top: 64);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final logs = _Logs(lines);
  await tester.pumpWidget(
    goldenApp(
      brightness: brightness,
      overrides: [
        localRuntimeLogsProvider.overrideWith(() => logs),
        localRuntimeProvider.overrideWith(() => runtime ?? (throw StateError('logs must not control installation'))),
      ],
      home: runtime != null
          ? RuntimeSetupPage(onDone: () => throw StateError('logs must not finish installation'))
          : Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showRuntimeLogSheet(context, title: '安装日志'),
                  child: const Text('open logs'),
                ),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(runtime == null ? 'open logs' : '查看日志'));
  await tester.pumpAndSettle();
  return logs;
}

Finder get _list => find.descendant(of: find.byType(BottomSheet), matching: find.byType(ListView));

void _expectTopAligned(WidgetTester tester, String firstLine) {
  final list = tester.getRect(_list);
  final first = tester.getRect(find.text(firstLine));
  expect(first.top - list.top, inInclusiveRange(0, 16), reason: 'short logs start at the top, not the bottom');
  expect(first.left, greaterThanOrEqualTo(list.left));
  expect(first.right, lessThanOrEqualTo(list.right));
}

ScrollableState _scrollState(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(of: _list, matching: find.byType(Scrollable)).first);

class _InstallingRuntime extends FakeRuntime {
  _InstallingRuntime()
    : super(
        const LocalRuntimeState(
          loaded: true,
          status: RuntimeStatus(phase: RuntimePhase.installing, bundledVersion: 'fixture-runtime'),
        ),
      );

  int mutations = 0;

  @override
  Future<void> install() async => mutations++;
  @override
  Future<void> stop() async => mutations++;
  @override
  Future<void> reset() async => mutations++;
}

void main() {
  testWidgets('short runtime logs start immediately below the compact header', (tester) async {
    await _openLogs(tester);
    _expectTopAligned(tester, '[dsh-app] preparing runtime');
    final header = tester.getRect(find.byType(SheetHeader));
    final list = tester.getRect(_list);
    expect(list.top - header.bottom, inInclusiveRange(0, 12));
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (size, brightness, scale, keyboard) in [
    (const Size(320, 568), Brightness.light, 2.0, 0.0),
    (const Size(390, 844), Brightness.dark, 1.0, 0.0),
    (const Size(844, 390), Brightness.light, 2.0, 0.0),
    (const Size(320, 568), Brightness.dark, 2.0, 240.0),
  ]) {
    testWidgets('logs fit $size $brightness scale=$scale keyboard=$keyboard with system insets', (tester) async {
      await _openLogs(tester, size: size, brightness: brightness, scale: scale, keyboard: keyboard);
      _expectTopAligned(tester, '[dsh-app] preparing runtime');
      final header = tester.getRect(find.byType(SheetHeader));
      final list = tester.getRect(_list);
      final close = tester.getRect(find.byTooltip('关闭'));
      final copy = tester.getRect(find.byTooltip('复制'));
      expect(header.top, greaterThanOrEqualTo(32));
      expect(list.height, greaterThan(60));
      expect(list.bottom, lessThanOrEqualTo(size.height - (keyboard > 0 ? keyboard : 24)));
      expect(close.overlaps(list), isFalse);
      expect(copy.overlaps(close), isFalse);
      expect(find.byTooltip('关闭').hitTestable(), findsOneWidget);
      expect(find.byTooltip('复制').hitTestable(), findsOneWidget);
      expect(Theme.of(tester.element(_list)).brightness, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty logs are clear and copy becomes enabled when live lines arrive', (tester) async {
    final logs = await _openLogs(tester, lines: const []);
    expect(find.text('还没有日志'), findsOneWidget);
    final empty = tester.getRect(find.text('还没有日志'));
    final header = tester.getRect(find.byType(SheetHeader));
    expect(empty.top - header.bottom, inInclusiveRange(0, 20));
    final copy = find.byWidgetPredicate((widget) => widget is SheetIconButton && widget.tooltip == '复制');
    expect(tester.widget<SheetIconButton>(copy).onPressed, isNull);
    logs.emit(const ['[dsh-app] live install log']);
    await tester.pumpAndSettle();
    expect(find.text('还没有日志'), findsNothing);
    _expectTopAligned(tester, '[dsh-app] live install log');
    expect(tester.widget<SheetIconButton>(copy).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lines wrap and the tail follows live logs without moving a reader at the top', (tester) async {
    final longLine = 'extracting ${'very-long-path-component/' * 20}finished';
    final lines = [longLine, for (var i = 0; i < 100; i++) 'unpacking file $i'];
    final logs = await _openLogs(tester, size: const Size(320, 568), lines: lines);
    final position = _scrollState(tester).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.extentAfter, closeTo(0, 1));
    logs.emit([...lines, 'tail appended']);
    await tester.pumpAndSettle();
    expect(position.extentAfter, closeTo(0, 1));
    expect(find.text('tail appended').hitTestable(), findsOneWidget);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    final line = tester.getRect(find.text(longLine));
    final list = tester.getRect(_list);
    expect(line.height, greaterThan(36));
    expect(line.left, greaterThanOrEqualTo(list.left));
    expect(line.right, lessThanOrEqualTo(list.right));
    logs.emit([...lines, 'tail appended', 'another live line']);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    _expectTopAligned(tester, longLine);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    logs.emit([...lines, 'tail appended', 'another live line', 'latest line']);
    await tester.pumpAndSettle();
    expect(position.extentAfter, closeTo(0, 1));
    expect(find.text('latest line').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed-height log batches finish at the real last line', (tester) async {
    final lines = [for (var i = 0; i < 180; i++) 'file $i ${'path-component/' * (i % 17)}'];
    final logs = await _openLogs(tester, size: const Size(320, 568), lines: lines);
    expect(find.text(lines.last).hitTestable(), findsOneWidget);
    logs.emit([...lines, for (var i = 0; i < 20; i++) 'new file $i ${'nested/' * (i * 3)}', 'batch finished']);
    await tester.pumpAndSettle();
    expect(find.text('batch finished').hitTestable(), findsOneWidget);
    expect(_scrollState(tester).position.extentAfter, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open log sheet adapts to rotation and an appearing keyboard', (tester) async {
    await _openLogs(tester, size: const Size(320, 568), scale: 2);
    tester.view.physicalSize = const Size(844, 390) * tester.view.devicePixelRatio;
    tester.view.padding = const FakeViewPadding(left: 96, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(left: 96, bottom: 48);
    await tester.pumpAndSettle();
    _expectTopAligned(tester, '[dsh-app] preparing runtime');
    final list = tester.getRect(_list);
    expect(list.left, greaterThanOrEqualTo(48));
    expect(list.right, lessThanOrEqualTo(844 - 48));
    expect(list.bottom, lessThanOrEqualTo(390 - 24));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.view.padding = const FakeViewPadding(left: 96);
    await tester.pumpAndSettle();
    expect(tester.getRect(_list).bottom, lessThanOrEqualTo(390 - 160));
    expect(find.byTooltip('关闭').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy reads current logs and close leaves an in-progress upgrade untouched', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final runtime = _InstallingRuntime();
    final logs = await _openLogs(tester, runtime: runtime);
    logs.emit(const ['\x1B[32mnew log\x1B[0m', 'current tail']);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复制'));
    await tester.pumpAndSettle();
    expect(copied, ['new log\ncurrent tail']);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(RuntimeSetupPage), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(RuntimeSetupPage)));
    expect(container.read(localRuntimeProvider).status.phase, RuntimePhase.installing);
    expect(container.read(runtimeInstallProvider), isFalse);
    expect(runtime.mutations, 0);
    expect(tester.takeException(), isNull);
  });
}
