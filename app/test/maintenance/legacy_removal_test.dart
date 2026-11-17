import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Independent, explicit source/dependency retirement contract. Do not import
/// removed providers just to show they stay unmounted: the sources are gone.
const retiredSources=<String>[
 'lib/account','lib/companion','lib/pets','lib/phone','lib/plugins','lib/remote','lib/share_code','lib/share_hosted','lib/ui_config','lib/update','lib/usage','lib/voice','lib/wallpaper',
 'lib/ui/account','lib/ui/agents','lib/ui/bots','lib/ui/chat','lib/ui/community','lib/ui/companion','lib/ui/cordis','lib/ui/engine_settings','lib/ui/features','lib/ui/files','lib/ui/forum','lib/ui/pets','lib/ui/phone','lib/ui/plugins','lib/ui/providers','lib/ui/remote','lib/ui/replay','lib/ui/session','lib/ui/share','lib/ui/share_code','lib/ui/share_hosted','lib/ui/star','lib/ui/terminal','lib/ui/update','lib/ui/wallpaper','lib/ui/workspace',
 'lib/state/phone_state.dart','lib/state/bots_state.dart','lib/state/account_state.dart','lib/state/provider_keys.dart','lib/state/providers_state.dart','lib/state/hosts_state.dart','lib/ui/web/dsh_web_launcher.dart',
 '../packages/dsh_remote','../runtime/bridge','../runtime/patches','../sdk/plugin-kit',
];
List<String> retirementViolations(Directory app){
 final issues=<String>[];
 for(final path in retiredSources){if(FileSystemEntity.typeSync('${app.path}/$path')!=FileSystemEntityType.notFound)issues.add(path);}
 final pubspec=File('${app.path}/pubspec.yaml').readAsStringSync();
 for(final dependency in ['dsh_remote','dartssh2','flutter_webrtc','live2d_native']){
  if(RegExp('^\\s*${RegExp.escape(dependency)}:',multiLine:true).hasMatch(pubspec))issues.add('dependency:$dependency');
 }
 return issues;
}
void main(){
 test('retired features have no actual source tree or dedicated dependencies',(){expect(retirementViolations(Directory.current),isEmpty);});
 test('the retirement oracle rejects a restored source and dependency (bad baseline)',(){
  final parent=Directory.systemTemp.createTempSync('retirement-oracle-');addTearDown(()=>parent.deleteSync(recursive:true));
  final app=Directory('${parent.path}/app')..createSync();
  File('${app.path}/pubspec.yaml').writeAsStringSync('dependencies:\n  flutter_webrtc: 1.0.0\n');
  Directory('${app.path}/lib/phone').createSync(recursive:true);File('${app.path}/lib/phone/phone_channel.dart').writeAsStringSync('class RetiredPhone {}');
  expect(retirementViolations(app),containsAll(['lib/phone','dependency:flutter_webrtc']));
 });
 test('ordinary notifications keep no phone or pet production imports',(){
  final paths=['lib/notify','lib/state/notify_state.dart'];
  for(final path in paths){
   final files=Directory(path).existsSync()?Directory(path).listSync(recursive:true).whereType<File>():[File(path)];
   for(final file in files.where((file)=>file.path.endsWith('.dart'))){
    expect(RegExp(r'''(?:import|export)\s+['"][^'"]*(?:/phone/|/pets/|/companion/|/ui/chat/)''').hasMatch(file.readAsStringSync()),isFalse,reason:file.path);
   }
  }
 });
 test('test bootstrap keeps real fonts/language/performance but no retired widget setup',(){
  final source=File('test/flutter_test_config.dart').readAsStringSync();
  expect(source,contains('await loadTestFonts()'));expect(source,contains('PerformanceChannel.create'));
  expect(source,contains('AppLanguageController.initial'));expect(source,contains('setUpEnglishPreview()'));
  expect(source, isNot(contains('PetSheets')));expect(source,isNot(contains('tipStart')));
 });
}
