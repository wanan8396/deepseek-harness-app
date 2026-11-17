// File/background permissions used by the phone shell. System readings,
// visits to vendor pages and the user's explicit confirmations stay distinct.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../runtime/background_net.dart' show backgroundSettingsProvider;
import '../runtime/runtime_bridge.dart' show RuntimePhase;
import '../runtime/runtime_state.dart';
import 'engine_control.dart';
import 'notify_state.dart';
import 'settings_state.dart';

enum AccessFeature { files, background }

/// System dialogs first, followed by the maker's background-running pages.
enum AccessItem {
  storage,
  notifications,
  battery,
  vendorBackground,
  autostart;

  bool get vendor => vendorWire != null;

  String? get vendorWire => switch (this) {
    vendorBackground => 'background',
    autostart => 'autostart',
    _ => null,
  };

  bool get dialog => this == storage || this == battery;
}

enum AccessState {
  on,
  off,
  visited,
  unknown;

  bool get settled => this == on || this == visited;
}

const vendorSwitches = <String, List<AccessItem>>{
  'vivo': [AccessItem.vendorBackground, AccessItem.autostart],
  'xiaomi': [AccessItem.vendorBackground, AccessItem.autostart],
  'huawei': [AccessItem.vendorBackground],
  'honor': [AccessItem.vendorBackground],
  'oppo': [AccessItem.vendorBackground],
};

List<AccessItem> accessItemsFor(AccessFeature feature, String? vendor) {
  final own = vendorSwitches[vendor] ?? const <AccessItem>[];
  final items = switch (feature) {
    AccessFeature.files => [AccessItem.storage],
    AccessFeature.background => [
      AccessItem.notifications,
      AccessItem.battery,
      AccessItem.vendorBackground,
      AccessItem.autostart,
    ],
  };
  return [
    for (final item in AccessItem.values)
      if (items.contains(item) && (!item.vendor || own.contains(item))) item,
  ];
}

List<AccessItem> accessWalk(Iterable<AccessFeature> features, String? vendor) {
  final wanted = {for (final feature in features) ...accessItemsFor(feature, vendor)};
  return [
    for (final item in AccessItem.values)
      if (wanted.contains(item)) item,
  ];
}

/// Null means that the native side supplied no reading, not a denied grant.
class AccessReadings {
  const AccessReadings({this.vendor, this.appLabel, this.storage, this.notifications, this.battery, this.metered});

  final String? vendor;
  final String? appLabel;
  final bool? storage;
  final bool? notifications;
  final bool? battery;
  final bool? metered;

  bool? granted(AccessItem item) => switch (item) {
    AccessItem.storage => storage,
    AccessItem.notifications => notifications,
    AccessItem.battery => battery,
    AccessItem.vendorBackground || AccessItem.autostart => null,
  };
}

/// A vendor visit records navigation only. It never claims a detected grant.
AccessState? accessStateOf(AccessItem item, AccessReadings readings, Set<AccessItem> visited) {
  if (item.vendor) return visited.contains(item) ? AccessState.visited : AccessState.unknown;
  return switch (readings.granted(item)) {
    true => AccessState.on,
    false => AccessState.off,
    null => null,
  };
}

abstract class AccessDriver {
  Future<AccessReadings> read();
  Future<bool> open(AccessItem item, {bool again = false});
  Future<bool> openAppInfo();
}

class SystemAccessDriver implements AccessDriver {
  SystemAccessDriver(this.ref);

  final Ref ref;

  static Future<T?> _safe<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      // Tests, desktop or a failed native read: unknown.
      return null;
    }
  }

  @override
  Future<AccessReadings> read() async {
    final bridge = ref.read(runtimeBridgeProvider);
    final info = _safe(() => ref.read(backgroundSettingsProvider.future));
    final storage = _safe(() async => (await bridge.storageStatus()).granted);
    final notifications = _safe(() async {
      final status = await ref.read(notifyChannelProvider).status();
      return status.native ? status.enabled : null;
    });
    final battery = _safe(bridge.batteryExempt);
    final metered = _safe(bridge.networkMetered);
    final settings = await info;
    ref.invalidate(batteryExemptProvider);
    ref.invalidate(notifySystemStatusProvider);
    return AccessReadings(
      vendor: settings?.vendor,
      appLabel: settings?.label,
      storage: await storage,
      notifications: await notifications,
      battery: await battery,
      metered: await metered,
    );
  }

  @override
  Future<bool> open(AccessItem item, {bool again = false}) async {
    final bridge = ref.read(runtimeBridgeProvider);
    return await _safe<bool>(() async {
          switch (item) {
            case AccessItem.storage:
              final access = await bridge.requestStorage();
              if (access.granted) return true;
              if (access.permission && !access.legacy) return bridge.openAllFilesAccess();
              if (again) return openAppInfo();
              return true;
            case AccessItem.notifications:
              return ref.read(notifyChannelProvider).openSettings();
            case AccessItem.battery:
              return await bridge.requestBatteryExempt() ?? false;
            case AccessItem.vendorBackground || AccessItem.autostart:
              return await bridge.openVendorSettings(item.vendorWire!) != null;
          }
        }) ??
        false;
  }

  @override
  Future<bool> openAppInfo() async => await _safe(ref.read(runtimeBridgeProvider).openAppDetails) ?? false;
}

/// Apply an explicitly completed permissions page. A detected storage grant
/// enables the existing /sdcard mount; returning from settings alone does not.
Future<void> applyFileAccess(ProviderContainer container) async {
  final readings = await container.read(accessReadingsProvider.notifier).refresh();
  if (readings.storage != true || container.read(settingsProvider).phoneStorage) return;
  await container.read(settingsProvider.notifier).setPhoneStorage(true);
  final phase = container.read(localRuntimeProvider).status.phase;
  if (phase == RuntimePhase.running || phase == RuntimePhase.starting) {
    unawaited(EngineControl.restart(container));
  }
}

final accessDriverProvider = Provider<AccessDriver>((ref) => SystemAccessDriver(ref));

final accessReadingsProvider = AsyncNotifierProvider<AccessReadingsController, AccessReadings>(
  AccessReadingsController.new,
);

class AccessReadingsController extends AsyncNotifier<AccessReadings> {
  @override
  Future<AccessReadings> build() => ref.read(accessDriverProvider).read();

  Future<AccessReadings> refresh() async {
    final readings = await ref.read(accessDriverProvider).read();
    if (ref.mounted) state = AsyncData(readings);
    return readings;
  }
}

final accessVisitedProvider = NotifierProvider<AccessVisitedController, Set<AccessItem>>(AccessVisitedController.new);

class AccessVisitedController extends Notifier<Set<AccessItem>> {
  static const prefsKey = 'system_access_visited';

  @override
  Set<AccessItem> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(prefsKey) ?? const [];
      if (!ref.mounted) return;
      state = {...state, for (final name in names) ?AccessItem.values.asNameMap()[name]};
    } catch (_) {}
  }

  Future<void> mark(AccessItem item) async {
    if (state.contains(item)) return;
    state = {...state, item};
    try {
      final prefs = await SharedPreferences.getInstance();
      // Preserve names belonging to retired features rather than rewriting
      // the user's existing preference as part of source cleanup.
      final names = {...?prefs.getStringList(prefsKey), for (final value in state) value.name};
      await prefs.setStringList(prefsKey, names.toList());
    } catch (_) {}
  }
}
