// Current phone-shell startup, restoration and computer isolation regressions.
import 'dart:convert';
import 'package:dsh_app/diagnostics/diagnostics_publish.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/onboarding_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_app/ui/access/lite_permissions_page.dart';
import 'package:dsh_app/ui/onboarding/access_step.dart';
import 'package:dsh_app/ui/onboarding/onboarding_flow.dart';
import 'package:dsh_app/ui/onboarding/runtime_choice.dart';
import 'package:dsh_app/ui/onboarding/runtime_setup_page.dart';
import 'package:dsh_app/ui/onboarding/setup_progress.dart';
import 'package:dsh_app/ui/onboarding/welcome_page.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:dsh_app/ui/web/local_web_screen.dart';
import 'package:dsh_app/ui/web/mode_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import '../access/support.dart';
import '../onboarding/local_optional_support.dart';
import '../onboarding/parallel_setup_support.dart';
import '../support/lite_harness.dart';
import '../web/support/fake_webview.dart';

class _DeferredWebConnection extends WebConnectionController {
 @override WebConnectionState build() {ready=Future<void>.value();return const WebConnectionState();}
 void restoreComputer()=>state=const WebConnectionState(loaded:true,mode:WebConnectionMode.computer,computerUrl:'http://192.0.2.10:3090/');
}
Future<GateRig> _pumpLocalGate(WidgetTester tester,{LocalRuntimeState runtime=const LocalRuntimeState(loaded:true,status:missingStatus),OnboardingPrefs prefs=const OnboardingPrefs(loaded:true,welcomeSeen:true),AppSettings settings=const AppSettings(loaded:true),List<Override> overrides=const []}) async {
 final fake=UnpackingRuntime(runtime);usePhoneSurface(tester);
 await tester.pumpWidget(goldenApp(home:const RootGate(),brightness:Brightness.light,prefs:prefs,overrides:[
  localRuntimeProvider.overrideWith(()=>fake),settingsProvider.overrideWith(()=>FakeSettings(settings)),footprint(roomyPhone),...overrides]));
 await frames(tester);return GateRig(fake,ProviderScope.containerOf(tester.element(find.byType(RootGate))));
}
void main() {
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final kind in ['ssh','relay']) {
   test('stored $kind preferences are ignored and preserved',() async {
    final previous=jsonEncode({'kind':kind,'id':'old-host'});
    final saved=jsonEncode([{'id':'old-ssh','host':'saved.example','user':'user'}]);
    SharedPreferences.setMockInitialValues({'active_host':previous,'last_session_id':'old-session','remote_ssh_hosts':saved,'remote_auto_connect_on_startup':true});
    final c=ProviderContainer();addTearDown(c.dispose);final observed=<HostRef>[];
    c.listen(activeHostProvider,(_,next)=>observed.add(next),fireImmediately:true);
    c.read(currentSessionProvider.notifier).select('local-session');
    for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}
    expect(c.read(activeHostProvider),HostRef.local);expect(observed,everyElement(HostRef.local));
    expect(c.read(currentSessionProvider),'local-session');
    final prefs=await SharedPreferences.getInstance();expect(prefs.getString('active_host'),previous);
    expect(prefs.getString('last_session_id'),'old-session');
    expect(prefs.getString('remote_ssh_hosts'),saved);expect(prefs.getBool('remote_auto_connect_on_startup'),isTrue);
   });
  }
 test('old native and layout preferences never select a native product',() async {
  for(final old in ['native','web','old-value']) {
   SharedPreferences.setMockInitialValues({'ui_mode':old,'web_phone_layout':false});
   final c=ProviderContainer();c.read(settingsProvider);
   for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}
   expect(c.read(settingsProvider).loaded,isTrue);expect(c.read(settingsProvider).webPhoneLayout,isTrue);
   final prefs=await SharedPreferences.getInstance();expect(prefs.getString('ui_mode'),old);expect(prefs.getBool('web_phone_layout'),isFalse);c.dispose();
  }
 });
 test('old local opt-out never skips missing, installing or outdated setup',() {
  const prefs=OnboardingPrefs(loaded:true,welcomeSeen:true,localDeclined:true,keySkipped:true);
  for(final status in [missingStatus,installingStatus,failedStatus,const RuntimeStatus(phase:RuntimePhase.notInstalled,bundledVersion:bundled,installedVersion:'old')]) {
   expect(initialOnboardingStep(status:status,prefs:prefs),OnboardingStep.runtime);
  }
  expect(initialOnboardingStep(status:missingStatus,prefs:const OnboardingPrefs(localDeclined:true)),OnboardingStep.welcome);
  expect(initialOnboardingStep(status:stoppedStatus,prefs:prefs),isNull);
  expect(initialOnboardingStep(status:missingStatus,prefs:prefs,useComputerWeb:true),isNull);
 });
 test('saved appearance/access resumes at retained permissions and connect resumes finishing',() {
  for(final status in [missingStatus,installingStatus,failedStatus,stoppedStatus]) {
   for(final saved in [SetupStep.appearance,SetupStep.access]) {
    expect(initialOnboardingStep(status:status,prefs:OnboardingPrefs(loaded:true,localDeclined:true,setupStep:saved)),OnboardingStep.access);
   }
  }
  expect(initialOnboardingStep(status:installingStatus,prefs:const OnboardingPrefs(loaded:true,setupStep:SetupStep.connect)),OnboardingStep.finishing);
 });
 testWidgets('fresh setup installs once, uses files/background permissions and starts only after finishing',(tester) async {
  final driver=FakeAccessDriver(offPhone);final rig=await _pumpLocalGate(tester,overrides:accessOverrides(driver));
  expect(find.byType(RuntimeChoiceView),findsOneWidget);await chooseThisPhone(tester);
  expect(rig.runtime.calls,['install']);expect(rig.prefs.setupStep,SetupStep.access);expect(find.byType(AccessStepPage),findsOneWidget);
  expect(find.byType(LitePermissionsPage),findsOneWidget);expect(find.bySemanticsLabel('第 2 步，共 2 步'),findsOneWidget);
  for(final name in ['storage','battery']) {expect(find.byKey(ValueKey('lite-permission-row-$name')),findsOneWidget);}
  for(final name in ['accessibility','overlay','mic','root']) {expect(find.byKey(ValueKey('lite-permission-row-$name')),findsNothing);}
  rig.runtime.unpack(0.4);await frames(tester,2);
  await tester.ensureVisible(find.byKey(const ValueKey('lite-permissions-continue')));await tester.tap(find.byKey(const ValueKey('lite-permissions-continue')));await frames(tester);
  expect(find.byType(RuntimeSetupPage),findsOneWidget);expect(rig.prefs.setupStep,SetupStep.finishing);expect(rig.runtime.calls,['install']);
  rig.runtime.finish();await frames(tester);expect(find.byType(ModeHome),findsOneWidget);expect(rig.runtime.calls,['install','start']);
  await frames(tester);expect(rig.runtime.calls,['install','start']);expect(driver.opened,isEmpty);expect(tester.takeException(),isNull);
 });
 testWidgets('failed finishing has explicit retry and no retired remote escape',(tester) async {
  await pumpGate(tester,runtime:const LocalRuntimeState(loaded:true,status:failedStatus),prefs:const OnboardingPrefs(loaded:true,welcomeSeen:true,setupStep:SetupStep.finishing));
  expect(find.byType(RuntimeSetupPage),findsOneWidget);expect(find.widgetWithText(FilledButton,'重试'),findsOneWidget);
  expect(find.text('改用远程主机'),findsNothing);expect(tester.takeException(),isNull);
 });
 testWidgets('upgrade installs once then waiting page owns exactly one start',(tester) async {
  final rig=await _pumpLocalGate(tester,runtime:const LocalRuntimeState(loaded:true,status:RuntimeStatus(phase:RuntimePhase.notInstalled,bundledVersion:bundled,installedVersion:'old')));
  expect(find.byType(RuntimeSetupPage),findsOneWidget);expect(rig.runtime.calls,['install']);rig.runtime.finish();await frames(tester,20);
  expect(find.byType(ModeHome),findsOneWidget);expect(rig.runtime.calls,['install','start']);await frames(tester);expect(rig.runtime.calls,['install','start']);
 });
 testWidgets('runtime removal returns to installation without erasing saved setup',(tester) async {
  final rig=await _pumpLocalGate(tester,runtime:const LocalRuntimeState(loaded:true,status:stoppedStatus),settings:const AppSettings(loaded:true,autoStartLocal:false));
  expect(find.byType(LocalWebScreen),findsOneWidget);rig.runtime.emit(missingStatus);await frames(tester);
  expect(find.byType(RuntimeSetupPage),findsOneWidget);expect(rig.runtime.calls,['start','install']);
 });
 testWidgets('local mode starts once despite saved auto-start false and window rebuilds',(tester) async {
  final rig=await _pumpLocalGate(tester,runtime:const LocalRuntimeState(loaded:true,status:stoppedStatus),settings:const AppSettings(loaded:true,autoStartLocal:false));
  expect(rig.runtime.calls,['start']);rig.runtime.emit(stoppedStatus);tester.view.physicalSize=const Size(1688,780);await frames(tester);
  expect(rig.runtime.calls,['start']);expect(tester.takeException(),isNull);
 });
 testWidgets('restored computer enters WebView without constructing phone runtime or setup',(tester) async {
  SharedPreferences.setMockInitialValues({WebConnectionController.prefsKey:jsonEncode({'mode':'computer','selectedId':'pc','records':[{'id':'pc','label':'desktop','baseUrl':'http://192.0.2.10:3090/','lastUsed':'2026-01-01T00:00:00Z'}]})});
  final platform=FakeWebViewPlatform();WebViewPlatform.instance=platform;var runtimeReads=0;usePhoneSurface(tester);
  await tester.pumpWidget(goldenApp(home:const RootGate(),brightness:Brightness.light,overrides:[
   localRuntimeProvider.overrideWith(() {runtimeReads++;throw StateError('computer_read_runtime');}),
   setupRuntimeProvider.overrideWith((ref)=>throw StateError('computer_read_setup')),
   diagnosticsPublisherProvider.overrideWith((ref)=>throw StateError('computer_publish_diagnostics')),
   settingsProvider.overrideWith(()=>FakeSettings(const AppSettings()))]));
  await frames(tester);
  for(var i=0;i<30 && (platform.controllers.isEmpty || platform.controllers.single.loads.isEmpty);i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await tester.pump();}
  expect(platform.controllers,hasLength(1));expect(platform.controllers.single.loads,[Uri.parse('http://192.0.2.10:3090/')]);expect(find.byType(WelcomePage),findsNothing);expect(find.byType(LocalWebScreen),findsNothing);
  final c=ProviderScope.containerOf(tester.element(find.byType(RootGate)));expect(runtimeReads,0);expect(c.exists(localRuntimeProvider),isFalse);expect(c.exists(setupRuntimeProvider),isFalse);expect(c.exists(diagnosticsPublisherProvider),isFalse);expect(tester.takeException(),isNull);
 });
 testWidgets('destination restoration waits behind original cover without initializing phone runtime',(tester) async {
  final destination=_DeferredWebConnection();var reads=0;
  await tester.pumpWidget(goldenApp(home:const RootGate(home:Scaffold(body:Text('computer-home'))),brightness:Brightness.light,overrides:[
   webConnectionProvider.overrideWith(()=>destination),localRuntimeProvider.overrideWith(() {reads++;throw StateError('local_before_restore');})]));
  await frames(tester);expect(find.text('computer-home'),findsNothing);expect(find.byKey(const ValueKey('local-web-startup-cover')),findsOneWidget);expect(reads,0);
  destination.restoreComputer();await frames(tester);expect(find.text('computer-home'),findsOneWidget);expect(reads,0);expect(tester.takeException(),isNull);
 });
}
