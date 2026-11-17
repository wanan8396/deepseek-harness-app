// The Android side of the diagnostics bundle
// (`diagnostics/DiagnosticsPlugin.kt`).

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App, device and bundled-runtime facts only Android knows.
class NativeDiagnostics {
  const NativeDiagnostics({this.app = const {}, this.device = const {}, this.manifest = const {}});

  factory NativeDiagnostics.fromMap(Map<Object?, Object?> map) {
    Map<String, Object?> section(Object? raw) =>
        raw is Map ? {for (final e in raw.entries) '${e.key}': e.value} : const {};
    return NativeDiagnostics(
      app: section(map['app']),
      device: section(map['device']),
      manifest: section(map['manifest']),
    );
  }

  /// `versionName`, `versionCode`, `abi`.
  final Map<String, Object?> app;

  /// `manufacturer`, `brand`, `model`, `android`, `sdkInt`, `abis`,
  /// `memoryMb`, `freeStorageMb`, and `display` (`widthPx`, `heightPx`,
  /// `density`, `densityDpi`, `fontScale`).
  final Map<String, Object?> device;

  /// Summary of `assets/runtime/manifest.json`: versions, sizes, file count.
  final Map<String, Object?> manifest;
}

/// MethodChannel `dsh/diagnostics`. Without the native side (tests, other
/// platforms) it answers empty.
class DiagnosticsChannel {
  const DiagnosticsChannel([this.channel = const MethodChannel('dsh/diagnostics')]);

  final MethodChannel channel;

  Future<NativeDiagnostics> info() async {
    try {
      final map = await channel.invokeMapMethod<Object?, Object?>('info');
      return map == null ? const NativeDiagnostics() : NativeDiagnostics.fromMap(map);
    } on MissingPluginException {
      return const NativeDiagnostics();
    }
  }

  /// The last lines of the engine's log file, up to [maxBytes]: unlike the
  /// in-memory log it survives the app being closed.
  Future<List<String>> engineLog({int maxBytes = 512 * 1024}) async {
    try {
      return await channel.invokeListMethod<String>('engineLog', {'maxBytes': maxBytes}) ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

final diagnosticsChannelProvider = Provider<DiagnosticsChannel>((ref) => const DiagnosticsChannel());
