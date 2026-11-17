import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('retired telemetry has no source owner, startup import or dependency',(){
  expect(Directory('lib/usage').existsSync(),isFalse);
  for(final path in ['lib/app.dart','lib/ui/web/web_home.dart','lib/ui/shell/root_gate.dart']){
   final source=File(path).readAsStringSync();expect(RegExp(r"(?:import|export).*usage/").hasMatch(source),isFalse,reason:path);
  }
  final pubspec=File('pubspec.yaml').readAsStringSync();
  expect(RegExp(r'^\s*(?:firebase_analytics|sentry_flutter|amplitude_flutter):',multiLine:true).hasMatch(pubspec),isFalse);
 });
}
