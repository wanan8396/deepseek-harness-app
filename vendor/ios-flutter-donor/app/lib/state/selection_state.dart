import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_variant.dart';
import 'host_ref.dart';

/// Whether a cold start restores the last host. Manual connects and their
/// short-network-outage recovery are independent of this preference.
class RemoteAutoConnectController extends Notifier<bool> {
  static const prefsKey = 'remote_auto_connect_on_startup';
  late Future<void> _loaded;

  @override
  bool build() {
    _loaded = _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getBool(prefsKey);
      if (stored != null && ref.mounted) state = stored;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    await _loaded;
    if (!ref.mounted) return;
    state = value;
    try {
      await (await SharedPreferences.getInstance()).setBool(prefsKey, value);
    } catch (_) {}
  }
}

final remoteAutoConnectProvider = NotifierProvider<RemoteAutoConnectController, bool>(RemoteAutoConnectController.new);

/// Which host the chat, session list and new chats use. Persisted.
class ActiveHostController extends Notifier<HostRef> {
  static const prefsKey = 'active_host';
  bool _touched = false;
  late Future<void> _loaded;

  @override
  HostRef build() {
    if (localWebLite) {
      _loaded = Future<void>.value();
      return HostRef.local;
    }
    // Read the startup preference now, so the remote hosts page shows the
    // stored value from its first frame.
    ref.read(remoteAutoConnectProvider);
    _loaded = _restore();
    return HostRef.local;
  }

  /// The startup host choice has settled, including a disabled auto-connect
  /// preference or an earlier explicit selection.
  Future<void> get ready => _loaded;

  Future<void> _restore() async {
    final owner = ref;
    try {
      final prefs = await SharedPreferences.getInstance();
      final restored = HostRef.decode(prefs.getString(prefsKey));
      final autoConnect = prefs.getBool(RemoteAutoConnectController.prefsKey) ?? true;
      if (!_touched && owner.mounted && autoConnect) state = restored;
    } catch (_) {
      // No preferences backend (tests): stay on 本机.
    }
  }

  /// Switches hosts. The open conversation belongs to the old host, so the
  /// chat goes back to "新对话".
  void select(HostRef host) {
    if (localWebLite) return;
    _touched = true;
    if (host == state && host.name == state.name) return;
    final changed = host != state;
    state = host;
    if (changed) ref.read(currentSessionProvider.notifier).select(null);
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(prefsKey, host.encode()))
          .catchError((_) => false),
    );
  }

  /// Hosts matching [gone] no longer exist (a deleted SSH host, a signed-out
  /// relay account): leave one in use for 本机, and drop one only saved for
  /// the next launch (with 连接上次使用的主机 off, this launch never used it).
  Future<void> forget(bool Function(HostRef host) gone) async {
    if (localWebLite) return;
    if (gone(state)) {
      select(HostRef.local);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (gone(HostRef.decode(prefs.getString(prefsKey)))) await prefs.setString(prefsKey, HostRef.local.encode());
    } catch (_) {}
  }
}

final activeHostProvider = NotifierProvider<ActiveHostController, HostRef>(ActiveHostController.new);

/// Folder chosen for the unsent new-chat draft, scoped to the active host.
/// This is a local drawer folder, not the engine's working directory.
class PendingSessionFolderController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(activeHostProvider);
    return null;
  }

  void select(String? folderId) => state = folderId;
}

final pendingSessionFolderProvider = NotifierProvider<PendingSessionFolderController, String?>(
  PendingSessionFolderController.new,
);

/// The session shown in the chat screen; null means "new chat".
class CurrentSessionController extends Notifier<String?> {
  static const _key = 'last_session_id';
  static const _selectionKey = 'last_session_selection';

  static String _hostKey(HostRef host) => '${host.kind.name}:${host.id}';

  /// Every explicit choice counts, including selecting the already-null new chat.
  int _selectionRevision = 0;
  int get selectionRevision => _selectionRevision;

  /// Something was chosen before the last conversation was read back (新对话
  /// from a share or a launcher shortcut on a cold start): that choice stands.
  bool _touched = false;

  @override
  String? build() {
    _restore();
    return null;
  }

  /// Reopens the conversation that was open when the app was last closed.
  Future<void> _restore() async {
    final owner = ref;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!owner.mounted || _touched || state != null) return;
      final raw = prefs.getString(_selectionKey);
      final legacy = prefs.getString(_key);
      if (raw == null && legacy == null) return;

      await owner.read(activeHostProvider.notifier).ready;
      if (!owner.mounted || _touched || state != null) return;
      final host = owner.read(activeHostProvider);
      if (raw != null) {
        final saved = jsonDecode(raw);
        if (saved is! Map || saved['host'] != _hostKey(host)) return;
        final id = saved['sessionId'];
        if (id is String) state = id;
      } else {
        // Old IDs have no host binding. Keep their existing compatibility
        // only when startup actually chose the saved host; a skipped remote
        // must not turn its unbound ID into a local conversation.
        if (HostRef.decode(prefs.getString(ActiveHostController.prefsKey)) == host) state = legacy;
      }
    } catch (_) {
      // No preferences backend (tests) or unreadable store: start with a new chat.
    }
  }

  void select(String? sessionId) {
    _selectionRevision++;
    _touched = true;
    final host = ref.read(activeHostProvider);
    ref.read(pendingSessionFolderProvider.notifier).select(null);
    state = sessionId;
    unawaited(_persist(host, sessionId));
  }

  Future<void> _persist(HostRef host, String? sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // One value owns both pieces, including an explicit new-chat choice.
      // Its null ID also wins if removing a leftover legacy key fails.
      await prefs.setString(_selectionKey, jsonEncode({'host': _hostKey(host), 'sessionId': sessionId}));
      await prefs.remove(_key);
    } catch (_) {}
  }
}

final currentSessionProvider = NotifierProvider<CurrentSessionController, String?>(CurrentSessionController.new);
