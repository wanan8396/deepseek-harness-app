import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'host_ref.dart';

/// Native integrations belong only to the phone's official Web service.
class ActiveHostController extends Notifier<HostRef> {
  @override
  HostRef build() => HostRef.local;
}

final activeHostProvider = NotifierProvider<ActiveHostController, HostRef>(ActiveHostController.new);

/// The conversation selected in the local Web page; null means a new chat.
class CurrentSessionController extends Notifier<String?> {
  static const _selectionKey = 'last_session_selection';

  static String _hostKey(HostRef host) => host.key;

  /// Every explicit choice counts, including selecting the already-null new chat.
  int _selectionRevision = 0;
  int get selectionRevision => _selectionRevision;

  /// Explicit choices during a cold-start restore always win.
  bool _touched = false;

  @override
  String? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final owner = ref;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!owner.mounted || _touched || state != null) return;
      final raw = prefs.getString(_selectionKey);
      if (raw == null) return;
      final host = owner.read(activeHostProvider);
      final saved = jsonDecode(raw);
      if (saved is! Map || saved['host'] != _hostKey(host)) return;
      final id = saved['sessionId'];
      if (id is String) state = id;
    } catch (_) {
      // Missing preferences or an unreadable store starts with a new chat.
    }
  }

  void select(String? sessionId) {
    _selectionRevision++;
    _touched = true;
    final host = ref.read(activeHostProvider);
    state = sessionId;
    unawaited(_persist(host, sessionId));
  }

  Future<void> _persist(HostRef host, String? sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // One value owns both pieces, including an explicit new-chat choice.
      await prefs.setString(_selectionKey, jsonEncode({'host': _hostKey(host), 'sessionId': sessionId}));
    } catch (_) {}
  }
}

final currentSessionProvider = NotifierProvider<CurrentSessionController, String?>(CurrentSessionController.new);
