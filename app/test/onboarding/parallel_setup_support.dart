// Phone-shell setup fixture: installation progress and saved step only.
import 'dart:async';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/onboarding_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import '../support/lite_harness.dart';
import 'local_optional_support.dart';
const unpackTotal=120586240;
const installingStatus=RuntimeStatus(phase:RuntimePhase.installing,bundledVersion:bundled,abi:'arm64-v8a');
const failedStatus=RuntimeStatus(phase:RuntimePhase.error,bundledVersion:bundled,abi:'arm64-v8a',error:'install failed: no space');
RuntimeProgressEvent unpackProgress(double fraction)=>RuntimeProgressEvent(step:'extract',done:(unpackTotal*fraction).round(),total:unpackTotal);
LocalRuntimeState unpackingState(double? fraction)=>LocalRuntimeState(loaded:true,status:installingStatus,progress:fraction==null?null:unpackProgress(fraction));
class UnpackingRuntime extends RecordingLocalRuntime {
 UnpackingRuntime(super.initial); Completer<void>? _unpack;
 @override Future<void> install() { calls.add('install');return (_unpack=Completer<void>()).future; }
 void unpack(double fraction)=>state=unpackingState(fraction);
 void finish() {state=const LocalRuntimeState(loaded:true,status:stoppedStatus);if(_unpack case final c? when !c.isCompleted)c.complete();}
 void fail() {state=const LocalRuntimeState(loaded:true,status:failedStatus);if(_unpack case final c? when !c.isCompleted)c.completeError(StateError('install_failed'));}
}
class GateRig {
 GateRig(this.runtime,this.container);final UnpackingRuntime runtime;final ProviderContainer container;
 OnboardingPrefs get prefs=>container.read(onboardingPrefsProvider);
}
Future<void> frames(WidgetTester tester,[int n=10]) async {for(var i=0;i<n;i++){await tester.pump(const Duration(milliseconds:100));}}
Future<GateRig> pumpGate(WidgetTester tester,{LocalRuntimeState runtime=const LocalRuntimeState(loaded:true,status:missingStatus),OnboardingPrefs prefs=const OnboardingPrefs(loaded:true,welcomeSeen:true),AppSettings settings=const AppSettings(loaded:true),List<Override> overrides=const []}) async {
 final fake=UnpackingRuntime(runtime);usePhoneSurface(tester);
 await tester.pumpWidget(goldenApp(home:const RootGate(home:Scaffold(body:Text('home'))),brightness:Brightness.light,prefs:prefs,
 overrides:[localRuntimeProvider.overrideWith(()=>fake),settingsProvider.overrideWith(()=>FakeSettings(settings)),footprint(roomyPhone),...overrides]));
 await frames(tester);return GateRig(fake,ProviderScope.containerOf(tester.element(find.byType(RootGate))));
}
Future<void> chooseThisPhone(WidgetTester tester) async {await tester.tap(find.widgetWithText(FilledButton,'继续'));await frames(tester);}
