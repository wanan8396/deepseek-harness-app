import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_dsh.dart';

const fastMux = MuxOptions(readyTimeout: Duration(seconds: 2), retryCaps: [Duration(milliseconds: 10)]);

void main() {
  test('workspace update parsers distinguish baselines, complete archive sets and peer replace frames', () {
    final baseline = WorkspaceUpdate.fromJson({
      'type': 'baseline',
      'value': {
        'items': [
          {
            'workspaceId': 'w1',
            'path': '/work',
            'title': 'Work',
            'sessionIds': ['s1'],
          },
        ],
        'archivedSessionIds': ['s0'],
        'pinnedSessionIds': ['s1'],
      },
    });
    expect(baseline, isA<WorkspaceBaseline>());
    expect((baseline as WorkspaceBaseline).archivedSessionIds, ['s0']);
    expect(baseline.workspaces.single.sessionIds, ['s1']);

    final archived = WorkspaceUpdate.fromJson({
      'type': 'archived',
      'archivedSessionIds': ['s0', 's2'],
    });
    expect(archived, isA<WorkspaceArchivedUpdate>());
    expect((archived as WorkspaceArchivedUpdate).archivedSessionIds, ['s0', 's2']);

    final replaced = WorkspaceUpdate.fromJson({
      'type': 'replace',
      'value': {
        'items': [
          {'workspaceId': 'w2', 'path': '/other', 'title': 'Other', 'sessionIds': []},
        ],
        'archivedSessionIds': ['s3'],
        'pinnedSessionIds': [],
      },
    });
    expect(workspaceReplaceFrame(replaced)?.workspaces.single.workspaceId, 'w2');
    expect(workspaceReplaceFrame(archived), isNull);
  });

  test('workspace follow reopens on a new mux generation and starts with another baseline', () async {
    final host = await FakeDsh.start();
    addTearDown(host.close);
    var opened = 0;
    host.onOpen = (socket, streamId, endpoint, payload) {
      expect(endpoint, 'workspace/follow');
      opened++;
      socket.item(streamId, {
        'type': 'baseline',
        'value': {
          'items': [
            {'workspaceId': 'w$opened', 'path': '/work/$opened', 'title': 'Work $opened', 'sessionIds': []},
          ],
          'archivedSessionIds': ['archived-$opened'],
          'pinnedSessionIds': <Object?>[],
        },
      });
    };
    final client = await DshClient.connect(baseUri: host.baseUri, token: FakeDsh.token, muxOptions: fastMux);
    addTearDown(client.close);
    final updates = <WorkspaceUpdate>[];
    final secondBaseline = Completer<void>();
    final sub = client.watchWorkspaces().listen((update) {
      updates.add(update);
      if (updates.whereType<WorkspaceBaseline>().length == 2 && !secondBaseline.isCompleted) secondBaseline.complete();
    });
    addTearDown(sub.cancel);
    await _eventually(() => updates.whereType<WorkspaceBaseline>().length == 1);
    await host.sockets.first.ws.close();
    await secondBaseline.future.timeout(const Duration(seconds: 4));
    expect(host.sockets, hasLength(2));
    expect(opened, 2);
    expect(updates.whereType<WorkspaceBaseline>().map((update) => update.workspaces.single.workspaceId), ['w1', 'w2']);
    expect(updates.whereType<WorkspaceBaseline>().map((update) => update.archivedSessionIds.single), [
      'archived-1',
      'archived-2',
    ]);
  });
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
