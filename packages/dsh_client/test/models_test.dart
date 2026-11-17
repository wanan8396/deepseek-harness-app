import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  test('session summary preserves session id, parent and sequenced title projection', () {
    final row = SessionSummary.fromJson({
      'sessionId': 'child-1',
      'updatedAt': 1792712155483,
      'running': true,
      'blank': false,
      'agentAvailable': true,
      'parentSessionId': 'root-1',
      'origin': 'subagent',
      'projections': {
        'kind': 'sequenced',
        'asOfSeq': 41,
        'values': {
          'title': 'child title',
          'sessionListMetadata': {'blank': true},
        },
      },
    });
    expect(row.sessionId, 'child-1');
    expect(row.parentSessionId, 'root-1');
    expect(row.isSubagent, isTrue);
    expect(row.projectionsKind, 'sequenced');
    expect(row.projections.asOfSeq, 41);
    expect(row.title, 'child title');
    expect(row.projections.blank, isTrue);
    expect(row.copyWith(running: false).sessionId, 'child-1');
  });

  test('Host events retain approval identity and tolerant unknown waterfalls', () {
    final approval = HostEvent.fromFrame({
      'type': 'waterfall',
      'event': 'approval/request',
      'eventId': 'evt-1',
      'agentId': 'session-1',
      'request': {
        'toolName': 'bash',
        'callId': 'call-1',
        'displayReason': {'en': 'run'},
      },
    });
    expect(approval, isA<ApprovalRequestedEvent>());
    final request = (approval as ApprovalRequestedEvent).request;
    expect(request.eventId, 'evt-1');
    expect(request.sessionId, 'session-1');
    expect(request.displayReason['en'], 'run');

    final unknown = HostEvent.fromFrame({
      'type': 'waterfall',
      'event': 'future/request',
      'eventId': 'future-1',
      'agentId': 'session-2',
    });
    expect(unknown, isA<UnknownHostEvent>());
    expect((unknown as UnknownHostEvent).eventId, 'future-1');
    expect(HostEvent.fromFrame({'type': 'cancel', 'eventId': 'evt-1'}), isA<HostRequestCancelledEvent>());
  });

  test('history parser preserves ordered turn boundaries and unknown sequence rows', () {
    final events = [
      SessionLogEvent.fromJson({
        'seq': 5,
        'time': 1792712155483,
        'type': 'turn/start',
        'data': {'turn': 2},
      }),
      SessionLogEvent.fromJson({
        'seq': 6,
        'time': 1792712155484,
        'type': 'assistant/message',
        'data': {
          'turn': 2,
          'step': 1,
          'message': {
            'content': [
              {'type': 'text', 'text': 'done'},
            ],
          },
        },
      }),
      SessionLogEvent.fromJson({
        'seq': 7,
        'time': 1792712155485,
        'type': 'turn/end',
        'data': {
          'turn': 2,
          'reason': {'kind': 'completed'},
        },
      }),
      SessionLogEvent.fromJson({'seq': 8, 'time': 1792712155486, 'type': 'future/event', 'data': {}}),
    ];
    expect(events.map((event) => event.seq), [5, 6, 7, 8]);
    expect(events[1], isA<AssistantMessageEvent>().having((event) => event.message.text, 'text', 'done'));
    expect(events[2], isA<TurnEndedEvent>().having((event) => event.reason.kind, 'kind', 'completed'));
    expect(events.last, isA<UnknownEvent>().having((event) => event.type, 'type', 'future/event'));
  });
}
