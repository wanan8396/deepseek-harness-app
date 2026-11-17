// The app's view of the web sidebar (assets/web/dsh_web_sidebar.js), run under
// node against a model of the page (test/local_web_lite/support/
// sidebar_bridge_harness.mjs). What matters here is the state the app's whale
// hides on: the official drawer, Lite's own drawer, a drawer caught
// mid-transition, a fullscreen panel, a replaced frame, and the forced re-check
// the page needs after a load. Needs `node` on PATH; skipped without it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String? _node() {
  for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final name in Platform.isWindows ? const ['node.exe', 'node'] : const ['node']) {
      final candidate = File('$dir${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return null;
}

void main() {
  final node = _node();
  final skip = node == null ? 'node is not installed' : null;

  test('the reported sidebar state covers every way the page can be covered', () async {
    final result = await Process.run(node!, ['test/local_web_lite/support/sidebar_bridge_harness.mjs']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, contains('Sidebar bridge passed'));
    expect(result.stderr, isEmpty, reason: jsonEncode('${result.stderr}'));
  }, skip: skip);
}
