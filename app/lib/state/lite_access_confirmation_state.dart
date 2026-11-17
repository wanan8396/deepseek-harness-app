// A user's explicit confirmation of Lite's unreadable vendor switches, kept
// separately from both API grants and the record that settings were visited.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'access_state.dart';

final liteAccessConfirmedProvider = NotifierProvider<LiteAccessConfirmedController, Set<AccessItem>>(
  LiteAccessConfirmedController.new,
);

class LiteAccessConfirmedController extends Notifier<Set<AccessItem>> {
  static const prefsKey = 'lite_access_confirmed_vendor';
  static const _items = {AccessItem.vendorBackground, AccessItem.autostart};

  late final Future<void> ready;
  Future<void> _saving = Future<void>.value();

  @override
  Set<AccessItem> build() {
    ready = _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(prefsKey) ?? const <String>[];
      if (!ref.mounted) return;
      state = {
        for (final item in _items)
          if (names.contains(item.name)) item,
      };
    } catch (_) {
      // An unreadable record confirms nothing. An explicit retry may save it.
    }
  }

  /// Only an explicit user action calls this. Serialize saves so simultaneous
  /// taps neither duplicate a write nor overwrite another vendor confirmation.
  Future<void> confirm(AccessItem item) {
    if (!_items.contains(item)) return Future<void>.value();
    final operation = _saving.then((_) async {
      await ready;
      if (!ref.mounted || state.contains(item)) return;
      final prefs = await SharedPreferences.getInstance();
      final next = {...state, item};
      final saved = await prefs.setStringList(prefsKey, [for (final value in next) value.name]);
      if (!saved) throw StateError('lite_access_confirmation_save_failed');
      if (ref.mounted) state = next;
    });
    // A failed save leaves the row unconfirmed and later retries available.
    _saving = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
