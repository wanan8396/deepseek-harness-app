// The ways in from outside the app other than links and
// shares — the launcher icon's long-press shortcuts (新对话, 语音输入, the
// three latest conversations), the Quick Settings tile (新对话), and a
// screenshot taken explicitly from the floating pet. Native
// side: android/.../shortcuts/ (EntryActivity, ShortcutsPlugin — MethodChannel
// `dsh/shortcuts`) and tile/NewChatTileService.kt. Routed by
// lib/ui/shell/system_entry_host.dart.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_variant.dart';
import '../l10n/l10n.dart';
import '../state/connection_state.dart';
import '../state/selection_state.dart';
import '../state/local_web_sessions_state.dart';
import '../state/sessions_state.dart';
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

/// The active host's latest conversations, for the launcher. Null while that
/// isn't known (not connected, the list loading): the launcher keeps what it
/// shows rather than being emptied by a stopped engine.
final recentShortcutsProvider = Provider<List<RecentShortcut>?>((ref) {
  if (localWebLite) return ref.watch(localWebRecentShortcutsProvider);
  final connected = ref.watch(activeConnectionProvider.select((c) => c.value != null));
  if (!connected) return null;
  final sessions = ref.watch(sessionsProvider);
  if (sessions.isLoading || !sessions.hasValue || sessions.hasError) {
    return null;
  }
  final host = ref.watch(activeHostProvider);
  return [
    for (final s in sessions.value!.take(maxRecentShortcuts))
      RecentShortcut(
        sessionId: s.sessionId,
        // The drawer's fallback (ui/shell/sessions_drawer.dart `sessionTitle`).
        title: switch (s.title?.trim()) {
          final t? when t.isNotEmpty => t,
          _ => appL10n.commonUntitledChat,
        },
        host: host,
      ),
  ];
});
