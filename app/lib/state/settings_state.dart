import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../performance/performance_state.dart';

/// Preferences owned by the phone shell. Model credentials and conversation
/// settings belong to the connected official web page, not to Flutter.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoStartLocal = true,
    this.autoStartLocalExplicit = true,
    this.phoneStorage = false,
    this.webPhoneLayout = true,
    this.loaded = false,
  });

  final ThemeMode themeMode;

  /// Start the local DSH automatically when the app opens.
  final bool autoStartLocal;

  /// A stored user choice. Policy defaults never create this preference.
  final bool autoStartLocalExplicit;

  /// Mount the phone's shared storage at /sdcard in the Linux environment.
  final bool phoneStorage;

  /// The current phone shell always uses its existing mobile web layout.
  final bool webPhoneLayout;
  final bool loaded;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? autoStartLocal,
    bool? autoStartLocalExplicit,
    bool? phoneStorage,
    bool? loaded,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    autoStartLocal: autoStartLocal ?? this.autoStartLocal,
    autoStartLocalExplicit: autoStartLocalExplicit ?? this.autoStartLocalExplicit,
    phoneStorage: phoneStorage ?? this.phoneStorage,
    webPhoneLayout: webPhoneLayout,
    loaded: loaded ?? this.loaded,
  );
}

class SettingsController extends Notifier<AppSettings> {
  static const _themeKey = 'theme_mode';
  static const _autoStartKey = 'auto_start_local';
  static const _phoneStorageKey = 'phone_storage';
  late Future<void> _loaded;

  @override
  AppSettings build() {
    ref.listen(performanceDefaultsProvider.select((p) => p.autoStartLocal), (_, next) {
      if (!state.autoStartLocalExplicit) state = state.copyWith(autoStartLocal: next);
    });
    _loaded = _load();
    return const AppSettings(autoStartLocalExplicit: false);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    await performanceReady(ref);
    if (!ref.mounted) return;
    state = AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_themeKey),
        orElse: () => ThemeMode.system,
      ),
      autoStartLocal: prefs.getBool(_autoStartKey) ?? ref.read(performanceDefaultsProvider).autoStartLocal,
      autoStartLocalExplicit: prefs.containsKey(_autoStartKey),
      phoneStorage: prefs.getBool(_phoneStorageKey) ?? false,
      loaded: true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _loaded;
    if (!ref.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
    if (ref.mounted) state = state.copyWith(themeMode: mode);
  }

  Future<void> setPhoneStorage(bool value) async {
    await _loaded;
    if (!ref.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_phoneStorageKey, value);
    if (ref.mounted) state = state.copyWith(phoneStorage: value);
  }

  Future<void> setAutoStartLocal(bool value) async {
    await _loaded;
    if (!ref.mounted) return;
    state = state.copyWith(autoStartLocal: value, autoStartLocalExplicit: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
