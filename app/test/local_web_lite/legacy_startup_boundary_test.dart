import 'dart:io';
import 'package:dsh_app/app.dart';
import 'package:dsh_app/diagnostics/diagnostics_bundle.dart';
import 'package:dsh_app/diagnostics/diagnostics_channel.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/lite_harness.dart';
class _Logs extends LocalRuntimeLogsController {@override List<String> build()=>const ['fixture engine log'];}
class _Diagnostics extends DiagnosticsChannel {
 @override Future<NativeDiagnostics> info() async=>const NativeDiagnostics();
 @override Future<List<String>> engineLog({int maxBytes=512*1024}) async=>const ['fixture engine log'];
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final (mode,brightness) in [(ThemeMode.light,Brightness.light),(ThemeMode.dark,Brightness.dark)]) {
  testWidgets('saved $mode still owns native theme without retired ui.json/accent modules',(tester) async {
   final c=ProviderContainer(overrides:[settingsProvider.overrideWith(()=>FakeSettings(AppSettings(loaded:true,themeMode:mode)))]);addTearDown(c.dispose);
   await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const DshApp(home:Scaffold(body:Text('saved theme target')))));
   await tester.pumpAndSettle();expect(Theme.of(tester.element(find.text('saved theme target'))).brightness,brightness);
   expect(c.exists(localRuntimeProvider),isFalse);expect(Directory('lib/ui_config').existsSync(),isFalse);expect(Directory('lib/ui/chat').existsSync(),isFalse);
   expect(tester.takeException(),isNull);
  });
 }
 test('diagnostics keep engine facts and never call retired phone channel',() async {
  const phone=MethodChannel('dsh/phone');final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;final calls=<String>[];
  messenger.setMockMethodCallHandler(phone,(call) async{calls.add(call.method);return null;});addTearDown(()=>messenger.setMockMethodCallHandler(phone,null));
  final c=ProviderContainer(overrides:[localRuntimeProvider.overrideWith(()=>FakeRuntime(const LocalRuntimeState(loaded:true))),localRuntimeLogsProvider.overrideWith(_Logs.new),settingsProvider.overrideWith(()=>FakeSettings()),diagnosticsChannelProvider.overrideWithValue(_Diagnostics())]);addTearDown(c.dispose);
  final snapshot=await c.read(Provider((ref)=>collectDiagnostics(ref,DateTime.utc(2026,11,12))));
  expect(calls,isEmpty);expect(snapshot.engineLog,['fixture engine log']);expect(DiagnosticsBundle.summary(snapshot).keys,isNot(contains('phone')));
  expect(File('lib/state/phone_state.dart').existsSync(),isFalse);
 });
}
