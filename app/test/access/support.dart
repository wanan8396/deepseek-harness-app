// File/background permission readings and runtime mount fixtures only.
import 'dart:async';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/access_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import '../support/lite_harness.dart';

const offPhone = AccessReadings(vendor: 'vivo', appLabel: 'DeepSeek harness',
 storage: false, notifications: false, battery: false, metered: false);
AccessReadings readingsWith(AccessReadings r, {String? vendor, bool clearVendor = false,
 bool? storage, bool? notifications, bool? battery, bool? metered}) => AccessReadings(
 vendor: clearVendor ? null : (vendor ?? r.vendor), appLabel: r.appLabel,
 storage: storage ?? r.storage, notifications: notifications ?? r.notifications,
 battery: battery ?? r.battery, metered: metered ?? r.metered);
typedef Answer = AccessReadings Function(AccessItem item, AccessReadings now);
class FakeAccessDriver implements AccessDriver {
 FakeAccessDriver(this.readings, {this.answer});
 AccessReadings readings; Answer? answer; final opened = <String>[]; int reads = 0;
 @override Future<AccessReadings> read() async { reads++; return readings; }
 @override Future<bool> open(AccessItem item, {bool again = false}) async {
  opened.add(again ? '${item.name}+' : item.name);
  if (answer case final answer?) readings = answer(item, readings);
  return true;
 }
 @override Future<bool> openAppInfo() async { opened.add('appInfo'); return true; }
}
class FlakyAccessDriver extends FakeAccessDriver {
 FlakyAccessDriver(super.readings, {super.answer}); int failures = 0;
 @override Future<AccessReadings> read() async {
  if (failures > 0) { failures--; reads++; throw PlatformException(code: 'unavailable'); }
  return super.read();
 }
}
List<Override> accessOverrides(FakeAccessDriver driver) => [
 accessDriverProvider.overrideWithValue(driver)];
class FakeEngine extends LocalRuntimeController {
 FakeEngine(this.phase, {this.storageMounted = false}); final RuntimePhase phase;
 bool storageMounted; final starts = <bool>[]; int stops = 0;
 @override LocalRuntimeState build() => LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: phase));
 @override Future<void> start() async {
  storageMounted = ref.read(settingsProvider).phoneStorage; starts.add(storageMounted);
  state = const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.starting));
 }
 @override Future<void> stop() async {
  stops++; state = const LocalRuntimeState(loaded: true, status: RuntimeStatus(phase: RuntimePhase.installed));
 }
}
class StorageSettings extends FakeSettings {
 StorageSettings() : super(const AppSettings(loaded: true)); Completer<void>? hold;
 @override Future<void> setPhoneStorage(bool value) async { await hold?.future; state = state.copyWith(phoneStorage: value); }
}
Future<void> awayAndBack(WidgetTester tester) async {
 for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
 AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
  tester.binding.handleAppLifecycleStateChanged(state);
 }
 for (var i=0;i<6;i++) { await tester.pump(const Duration(milliseconds:100)); }
}
