// A real storage reading, not a visit or stale selection, owns /sdcard mounting.
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/access_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support.dart';

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(() => SharedPreferences.setMockInitialValues({}));
 Future<void> settle() async { for(var i=0;i<10;i++) { await Future<void>.delayed(Duration.zero); } }
 Future<(ProviderContainer, FakeEngine, FakeAccessDriver)> fixture(RuntimePhase phase,{bool? granted = true}) async {
  final runtime=FakeEngine(phase); final driver=FakeAccessDriver(AccessReadings(storage: granted));
  final container=ProviderContainer(overrides:[localRuntimeProvider.overrideWith(() => runtime),
   settingsProvider.overrideWith(StorageSettings.new), accessDriverProvider.overrideWithValue(driver)]);
  addTearDown(container.dispose); return (container,runtime,driver);
 }
 for(final granted in [false,null]) {
  test('a denied or unknown grant $granted never enables storage or restarts',() async {
   final (container,runtime,driver)=await fixture(RuntimePhase.running,granted:granted);
   await applyFileAccess(container); await settle();
   expect(container.read(settingsProvider).phoneStorage,isFalse);
   expect(runtime.stops,0); expect(runtime.starts,isEmpty); expect(driver.opened,isEmpty);
  });
 }
 for(final phase in [RuntimePhase.starting,RuntimePhase.running]) {
  test('$phase restarts once after the saved grant, then repeated completion is idempotent',() async {
   final (container,runtime,driver)=await fixture(phase);
   await applyFileAccess(container); await settle();
   expect(container.read(settingsProvider).phoneStorage,isTrue);
   expect(runtime.stops,1); expect(runtime.starts,[true]); expect(runtime.storageMounted,isTrue);
   await applyFileAccess(container); await settle();
   expect(runtime.stops,1); expect(runtime.starts,[true]); expect(driver.opened,isEmpty);
  });
 }
 for(final phase in [RuntimePhase.notInstalled,RuntimePhase.installing,RuntimePhase.installed]) {
  test('$phase applies grant without starting an unrequested engine',() async {
   final (container,runtime,_)=await fixture(phase);
   await applyFileAccess(container); await settle();
   expect(container.read(settingsProvider).phoneStorage,isTrue);
   expect(runtime.stops,0); expect(runtime.starts,isEmpty);
   await runtime.start(); expect(runtime.starts,[true]);
  });
 }
 test('finish refreshes a grant that changed after initial permission read',() async {
  final (container,runtime,driver)=await fixture(RuntimePhase.installed,granted:false);
  await container.read(accessReadingsProvider.future);
  driver.readings=const AccessReadings(storage:true);
  await applyFileAccess(container);
  expect(driver.reads,2); expect(container.read(settingsProvider).phoneStorage,isTrue);
  expect(runtime.starts,isEmpty);
 });
}
