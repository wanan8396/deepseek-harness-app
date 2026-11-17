import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/notify_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';
import 'package:dsh_app/state/host_ref.dart';

class _Mux extends DshMux {
  _Mux(super.carrier);
  @override
  MuxGeneration get generation => const MuxGeneration(1, 'fixture-client', '/tmp');
}

class _Rpc extends DshRpc {
  _Rpc(super.carrier);
  final results = <Map<String, Object?>>[];
  @override
  Future<Object?> call(String endpoint, [Map<String, Object?> args = const {}, Duration? timeout]) async {
    expect(endpoint, r'$events/result');
    results.add(args);
    return null;
  }
}

class _Client extends DshClient {
  _Client() : super(DshConnection(Uri.parse('http://127.0.0.1:9')));
  late final _fixtureMux = _Mux(carrier);
  late final _fixtureRpc = _Rpc(carrier);
  @override
  DshMux get mux => _fixtureMux;
  @override
  _Rpc get rpc => _fixtureRpc;
  final replies = <(ApprovalRequest, ApprovalDecision)>[];
  bool failReply = false;
  @override
  Future<void> respondApproval(ApprovalRequest request, ApprovalDecision decision) async {
    replies.add((request, decision));
    if (failReply) throw StateError('disconnected');
  }
}

class _Local extends LocalConnectionController {
  _Local(this.connection);
  final HostConnection? connection;
  @override
  Future<HostConnection?> build() async => connection;
}

void main() {
  late _Client client;
  late FakeAlertSource source;
  late FakeNotifyChannel channel;
  late ProviderContainer container;
  const localHost = HostRef.local;
  const request = ApprovalRequest(eventId: 'approval-1', sessionId: 's1', toolName: 'bash', callId: 'call-1');

  NotifyAction action({ApprovalDecision decision = ApprovalDecision.allowOnce, HostRef host = localHost}) =>
      NotifyAction(
        host: host,
        group: notifyGroup(host, 's1'),
        key: request.eventId,
        eventId: request.eventId,
        decision: decision,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = _Client();
    source = FakeAlertSource()
      ..sessions = [session('s1')]
      ..approvalCalls['call-1'] = const ToolCallPart(id: 'call-1', name: 'bash', arguments: '{"command":"echo ready"}');
    channel = FakeNotifyChannel();
    final localConnection = HostConnection(client: client);

    container = ProviderContainer(
      overrides: [
        notifyChannelProvider.overrideWithValue(channel),
        alertSourceFactoryProvider.overrideWithValue((connection) => source),
        alertTimingProvider.overrideWithValue((announce: Duration.zero, reconcile: const Duration(milliseconds: 30))),
        localConnectionProvider.overrideWith(() => _Local(localConnection)),
      ],
    );
    container.listen(chatAlertsProvider, (_, _) {});
    container.read(appForegroundProvider.notifier).set(false);
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await channel.actionController.close();
    await channel.tapController.close();
    await client.close();
  });

  Future<void> announce() async {
    source.emit(const ApprovalRequestedEvent(request));
    await settle();
  }

  test('local approval action reaches its DSH client and acknowledges allowOnce', () async {
    await announce();
    expect(channel.shown.single.canApprove, isTrue);
    expect(channel.shown.single.text, '运行：echo ready');
    channel.actionController.add(action());
    await settle();
    expect(client.replies, [(request, ApprovalDecision.allowOnce)]);
    expect(channel.actionResults.single.$2, NotifyActionResult.handled);
  });

  test('reject decision reaches respondApproval unchanged', () async {
    await announce();
    final result = await container
        .read(chatAlertsProvider.notifier)
        .respondAction(action(decision: ApprovalDecision.reject));
    expect(result, NotifyActionResult.handled);
    expect(client.replies.single.$2, ApprovalDecision.reject);
  });

  test('a disconnected local notification source fails without replying', () async {
    await announce();
    source.isConnected = false;
    expect(await container.read(chatAlertsProvider.notifier).respondAction(action()), NotifyActionResult.failed);
    expect(client.replies, isEmpty);
  });

  test('withdrawn request is gone', () async {
    await announce();
    source.emit(const HostRequestCancelledEvent('approval-1'));
    expect(await container.read(chatAlertsProvider.notifier).respondAction(action()), NotifyActionResult.gone);
    expect(client.replies, isEmpty);
  });

  test('missing exact tool call leaves actions disabled', () async {
    source.approvalCalls.clear();
    await announce();
    expect(channel.shown.single.canApprove, isFalse);
    expect(await container.read(chatAlertsProvider.notifier).respondAction(action()), NotifyActionResult.gone);
    expect(client.replies, isEmpty);
  });

  test('RPC errors report failure rather than a successful approval', () async {
    await announce();
    client.failReply = true;
    expect(await container.read(chatAlertsProvider.notifier).respondAction(action()), NotifyActionResult.failed);
  });

  test('approval previews use exact calls, mask secrets and stay within 90 characters', () {
    const key = 'sk-1234567890abcdefghijklmnopqrstuvwxyz';
    final preview = approvalPreview(
      request,
      const ToolCallPart(id: 'call-1', name: 'bash', arguments: '{"command":"echo $key\\nnext line"}'),
    )!;
    expect(preview.text, startsWith('运行：echo sk-12345'));
    expect(preview.text, isNot(contains('next line')));
    expect(preview.fullText, contains('next line'));
    expect(preview.fullText, isNot(contains(key.substring(8))));
    final long = approvalPreview(
      request,
      ToolCallPart(id: 'call-1', name: 'bash', arguments: '{"command":"${'字' * 120}"}'),
    )!;
    expect(long.text.runes.length, lessThanOrEqualTo(90));
    expect(approvalPreview(request, const ToolCallPart(id: 'another', name: 'bash', arguments: '{}')), isNull);
    expect(approvalPreview(request, const ToolCallPart(id: 'call-1', name: 'bash', arguments: 'invalid')), isNull);
    for (final (tool, field, verb) in [
      ('write', 'file_path', '写入'),
      ('edit', 'path', '修改'),
      ('web_fetch', 'url', '打开'),
    ]) {
      final result = approvalPreview(
        ApprovalRequest(eventId: 'e', sessionId: 's', toolName: tool, callId: 'c'),
        ToolCallPart(id: 'c', name: tool, arguments: '{"$field":"target"}'),
      )!;
      expect(result.text, '$verb：target');
    }
  });






  test('native action parser accepts only explicit one-shot decisions', () {
    final payload = {'host': localHost.encode(), 'group': 'g', 'key': 'k', 'eventId': 'e', 'decision': 'allowed-once'};
    expect(NotifyAction.fromMap(payload)?.decision, ApprovalDecision.allowOnce);
    expect(NotifyAction.fromMap({...payload, 'decision': 'next'}), isNull);
    expect(NotifyAction.fromMap({...payload, 'eventId': ''}), isNull);
    for (final host in [null, '', 'x', '{"kind":"ssh","id":"old"}', '{"kind":"relay","id":"old"}', '{"kind":"local","id":"other"}']) {
      expect(NotifyAction.fromMap({...payload, 'host': host}), isNull);
    }
  });
}
