// Runs around every test file under test/: real fonts first (strict: a
// missing font fails the run), so no test measures or draws the test
// engine's box font. No binding here: tests that never pump keep real
// sockets and HTTP.

import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/performance/performance_state.dart';
import 'package:dsh_app/state/locale_state.dart';

import 'support/english_preview.dart';
import 'support/quiet_performance.dart';
import 'support/test_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadTestFonts();
  // No device facts in tests: the app reads "unavailable" at once.
  PerformanceChannel.create = QuietPerformanceChannel.new;
  // Tests run in Chinese (goldens and finders were made in it); English
  // tests opt in with AppLocale.use(AppLocale.en) + an English MaterialApp.
  AppLanguageController.initial = AppLanguage.zh;
  AppLocale.use(AppLocale.zhCN);
  setUpEnglishPreview();
  await testMain();
}
