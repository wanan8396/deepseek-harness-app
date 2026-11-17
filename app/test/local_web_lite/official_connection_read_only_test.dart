import 'dart:async';
import 'dart:io';
import 'package:dsh_app/notify/chat_alerts.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
class _Destination extends WebConnectionController {@override WebConnectionState build()=>const WebConnectionState(loaded:true);}
class _Runtime extends LocalRuntimeController {@override LocalRuntimeState build()=>const LocalRuntimeState(loaded:true,status:RuntimeStatus(phase:RuntimePhase.running,baseUrl:'http://127.0.0.1:9',token:'fixture'));}
class _Carrier extends DshCarrier {
 final link=_Link();final calls=<String>[];bool closed=false;
 @override String get kind=>'official-fixture';@override DshTracer? get tracer=>null;
 @override Future<RpcResult> call(String endpoint,Map<String,Object?> args,{Duration? timeout}) async{
  calls.add(endpoint);if(endpoint!='session/list')fail('unexpected mutation: $endpoint');
  return const RpcOk({'items':[{'sessionId':'recent','updatedAt':1,'running':false,'blank':false,'agentAvailable':true}]});
 }
 @override Future<DshMuxLink> openLink(MuxOptions options) async=>link;
 @override Future<void> close() async=>closed=true;
}
class _Link implements DshMuxLink {
 late DshMuxFrameHandler frame;late String id;final opened=Completer<void>();
 @override void start({required DshMuxFrameHandler onFrame,required DshMuxLossHandler onLost})=>frame=onFrame;
 @override void open(String streamId,String endpoint,Map<String,Object?> payload){expect(endpoint,r'$events');id=streamId;if(!opened.isCompleted)opened.complete();}
 void event(Map<String,Object?> value)=>frame({'type':'item','streamId':id,'value':value});
 void ready()=>event({'type':'ready','clientId':'fixture-client','host':{'home':'/root'}});
 @override void cancel(String streamId){}@override Future<void> close(int code,String reason) async{}
 @override void sendItem(String streamId,Object? value){}@override void endUplink(String streamId){}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('connection needs official ready, never native credentials/repair, and retains read events',() async{
  final carrier=_Carrier();final client=DshClient.withCarrier(carrier);var settingsReads=0;
  final c=ProviderContainer(retry:(_,_)=>null,overrides:[webConnectionProvider.overrideWith(_Destination.new),localRuntimeProvider.overrideWith(_Runtime.new),networkKicksProvider.overrideWithValue(const Stream.empty()),localClientConnectorProvider.overrideWithValue(({required baseUri,required token}) async=>client),settingsProvider.overrideWith((){settingsReads++;throw StateError('unexpected_native_settings');})]);
  addTearDown(() async{c.dispose();await client.close();});final sub=c.listen(localConnectionProvider,(_,_){});addTearDown(sub.close);
  await carrier.link.opened.future;expect(client.mux.generation,isNull);expect(carrier.calls,isEmpty);
  carrier.link.ready();final connection=await c.read(localConnectionProvider.future);
  expect(connection?.client,same(client));expect(client.mux.generation?.clientId,'fixture-client');expect(settingsReads,0);expect(c.exists(settingsProvider),isFalse);
  expect(carrier.calls,isEmpty);expect(carrier.closed,isFalse);
  final source=DshAlertSource(connection!.client);final event=source.events.firstWhere((event)=>event is SessionStatusEvent);
  carrier.link.event({'type':'emit','event':'api-session/status','args':['recent',true]});
  expect(await event,isA<SessionStatusEvent>().having((event)=>event.running,'running',true));expect(source.connected,isTrue);
  expect((await source.listSessions()).single.sessionId,'recent');expect(carrier.calls,['session/list']);
  for(final path in ['lib/state/provider_keys.dart','lib/state/providers_state.dart','lib/share_code/guest_fs.dart']){expect(File(path).existsSync(),isFalse,reason:path);}
 });
}
