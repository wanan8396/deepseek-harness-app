// Launcher long-press shortcuts and the Quick Settings tile enter the local
// Web page through the `dsh/shortcuts` channel, routed by WebEntryHost.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/local_web_sessions_state.dart';
import 'launcher_models.dart';
import 'native_inbox.dart';

export 'launcher_models.dart';

/// The native bridge: entries in, recent conversations out.
class LauncherBridge extends NativeInbox<LauncherEntry> {
  LauncherBridge({MethodChannel? channel})
    : super(channel ?? const MethodChannel('dsh/shortcuts'), method: 'entry', parse: LauncherEntry.parse);

  Stream<LauncherEntry> get entries => stream;

  /// What the launcher has, as far as this run knows.
  List<RecentShortcut>? _published;

  /// Publishes [recents] (newest first) unless the launcher already has
  /// them. True when the launcher has them now.
  Future<bool> setRecent(List<RecentShortcut> recents) async {
    if (_published != null && listEquals(_published, recents)) return true;
    try {
      final ok = await channel.invokeMethod<bool>('setRecent', {
        'items': [for (final r in recents) r.toJson()],
      });
      // Refused while rate-limited: the next change tries again.
      if (ok ?? false) _published = List.unmodifiable(recents);
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final launcherBridgeProvider = Provider<LauncherBridge>((ref) {
  final bridge = LauncherBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// Local Web conversations only. Null preserves existing launcher shortcuts
/// while the official engine is stopped or its inventory is unknown.
final recentShortcutsProvider = Provider<List<RecentShortcut>?>((ref) => ref.watch(localWebRecentShortcutsProvider));
