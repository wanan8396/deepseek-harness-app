import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_dsh.dart';

void main() {
  late FakeDsh host;
  setUp(() async => host = await FakeDsh.start());
  tearDown(() async => host.close());

  test('session inventory, projections and history preserve ids and child address semantics', () async {
    host.handlers['session/list'] = (_) => {
      'ok': true,
      'value': {
        'items': [
          {
            'sessionId': 'root-1',
            'updatedAt': 1792712155483,
            'running': false,
            'blank': false,
            'agentAvailable': true,
            'projections': {
              'kind': 'sequenced',
              'asOfSeq': 4,
              'values': {'title': 'Root'},
            },
          },
          {
            'sessionId': 'child-1',
            'updatedAt': 1792712155484,
            'running': false,
            'blank': false,
            'agentAvailable': true,
            'parentSessionId': 'root-1',
            'origin': 'subagent',
            'projections': {
              'kind': 'sequenced',
              'asOfSeq': 7,
              'values': {
                'subagent': {'mode': 'continuable'},
              },
            },
          },
        ],
      },
    };
    host.handlers['session/projections'] = (args) {
      expect(args, {
        'request': {'sessionId': 'child-1'},
      });
      return {
        'ok': true,
        'value': {
          'asOfSeq': 9,
          'values': {'title': 'Child title'},
        },
      };
    };
    Map<String, Object?>? pageRequest;
    host.handlers['session/page'] = (args) {
      pageRequest = (args['request'] as Map).cast<String, Object?>();
      return {
        'ok': true,
        'value': {
          'records': [
            {
              'event': {
                'seq': 8,
                'time': 1792712155485,
                'type': 'assistant/message',
                'data': {
                  'turn': 2,
                  'step': 1,
                  'message': {
                    'content': [
                      {'type': 'text', 'text': 'reply'},
                    ],
                  },
                },
              },
            },
            {
              'event': {
                'seq': 9,
                'time': 1792712155486,
                'type': 'turn/end',
                'data': {
                  'turn': 2,
                  'reason': {'kind': 'completed'},
                },
              },
            },
          ],
          'hasMore': true,
        },
      };
    };

    final client = await DshClient.connect(baseUri: host.baseUri, token: FakeDsh.token, startMux: false);
    addTearDown(client.close);
    final sessions = await client.listSessions();
    expect(sessions.map((session) => session.sessionId), ['root-1', 'child-1']);
    expect(client.sessionAddressOf('root-1'), {'kind': 'session', 'sessionId': 'root-1'});
    expect(client.sessionAddressOf('child-1'), {
      'kind': 'subagent',
      'parentSessionId': 'root-1',
      'childSessionId': 'child-1',
      'mode': 'continuable',
    });

    final projections = await client.projections('child-1');
    expect(projections?.title, 'Child title');
    expect(projections?.asOfSeq, 9);

    final page = await client.history('child-1', throughSeq: 9, maxMessages: 2);
    expect(page.hasMore, isTrue);
    expect(page.events.map((event) => event.seq), [8, 9]);
    expect((page.events.first as AssistantMessageEvent).message.text, 'reply');
    expect((page.events.last as TurnEndedEvent).reason.kind, 'completed');
    expect(pageRequest, {
      'address': {'kind': 'subagent', 'parentSessionId': 'root-1', 'childSessionId': 'child-1', 'mode': 'continuable'},
      'throughSeq': 9,
      'maxMessages': 2,
    });
  });
}
