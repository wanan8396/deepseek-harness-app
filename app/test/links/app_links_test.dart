import 'package:dsh_app/links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
const _channel=MethodChannel('dsh/links');
Future<void> _send(WidgetTester tester,Map<String,Object?> args) async=>tester.binding.defaultBinaryMessenger.handlePlatformMessage(_channel.name,const StandardMethodCodec().encodeMethodCall(MethodCall('link',args)),(_){});
void main(){
 testWidgets('cold-start file is buffered once for the first listener and ready is sent once',(tester) async{
  final calls=<String>[];tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel,(call) async{calls.add(call.method);return true;});
  addTearDown(()=>tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel,null));
  final links=AppLinks();addTearDown(links.dispose);await tester.pump();expect(calls,['ready']);
  await _send(tester,{'uri':'file:///cache/links/k/report.pdf'});final first=<Uri>[];final second=<Uri>[];
  links.links.listen(first.add);await tester.pump();links.links.listen(second.add);await tester.pump();
  expect(first,[Uri.parse('file:///cache/links/k/report.pdf')]);expect(second,isEmpty);
  await _send(tester,{'uri':'file:///cache/links/k/next.png'});await tester.pump();expect(first.last.pathSegments.last,'next.png');expect(second.single.pathSegments.last,'next.png');
 });
 testWidgets('native files and explicit errors are parsed, retired feature links are inert',(tester) async{
  final links=AppLinks();addTearDown(links.dispose);final got=<Uri>[];links.links.listen(got.add);
  await _send(tester,{'uri':'file:///cache/links/k/团队配置.dshgo'});await _send(tester,{'error':'too_large','name':'big.bin'});
  for(final uri in ['dshgo://share/plugin?p=abc','dshgo://forum/auth?payload=x','https://example.com','javascript:alert(1)']){await _send(tester,{'uri':uri});}
  await _send(tester,{'nonsense':1});await tester.pump();expect(got,hasLength(2));expect(got.first.pathSegments.last,'团队配置.dshgo');expect(got.last.scheme,AppLinks.unreadableScheme);expect(got.last.path,'big.bin');
 });
 testWidgets('absent native bridge stays quiet',(tester) async{final links=AppLinks();addTearDown(links.dispose);await tester.pump();expect(tester.takeException(),isNull);});
}
