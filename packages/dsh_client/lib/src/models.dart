/// Wire models consumed by the official local Web client: session inventory,
/// workspace updates, host events and the small history projection used by
/// alerts. Unknown host and history events remain typed unknown values.
library;

import 'json.dart';

// Session content used by approval previews and one-turn history reads.
sealed class Part {
  const Part();

  static Part fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return switch (asString(map['type'])) {
      'text' => TextPart(asString(map['text']) ?? ''),
      'tool-call' => ToolCallPart(
        id: asString(map['id']) ?? '',
        name: asString(map['name']) ?? '',
        arguments: asString(map['arguments']) ?? '',
      ),
      final type => UnknownPart(type ?? '', map),
    };
  }
}

final class TextPart extends Part {
  const TextPart(this.text);
  final String text;
}

final class ToolCallPart extends Part {
  const ToolCallPart({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final String arguments;
  Map<String, Object?>? get decodedArguments => asMap(tryDecodeJson(arguments));
}

final class UnknownPart extends Part {
  const UnknownPart(this.type, this.raw);
  final String type;
  final Map<String, Object?> raw;
}

class Message {
  const Message({required this.id, required this.parts, this.raw = const {}});

  factory Message.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return Message(
      id: asString(map['id']) ?? '',
      parts: [for (final raw in asListOrEmpty(map['content'])) Part.fromJson(raw)],
      raw: map,
    );
  }

  final String id;
  final List<Part> parts;
  final Map<String, Object?> raw;
  String get text => parts.whereType<TextPart>().map((part) => part.text).join();
  List<ToolCallPart> get toolCalls => parts.whereType<ToolCallPart>().toList(growable: false);
}

// Sessions and projection hints.
class SessionProjections {
  const SessionProjections(this.asOfSeq, this.values);

  factory SessionProjections.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return SessionProjections(asInt(map['asOfSeq']) ?? -1, asMapOrEmpty(map['values']));
  }

  static const empty = SessionProjections(-1, {});

  final int asOfSeq;
  final Map<String, Object?> values;
  String? get title => asString(values['title']);
  bool? get blank => asBool(asMap(values['sessionListMetadata'])?['blank']);
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    required this.agentAvailable,
    this.cwd,
    this.parentSessionId,
    this.origin,
    this.projections = SessionProjections.empty,
    this.projectionsKind,
    this.raw = const {},
  });

  factory SessionSummary.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    final hints = asMap(map['projections']);
    return SessionSummary(
      sessionId: asString(map['sessionId']) ?? '',
      updatedAt: asEpochMs(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      running: map['running'] == true,
      blank: map['blank'] == true,
      agentAvailable: map['agentAvailable'] == true,
      cwd: asString(map['cwd']),
      parentSessionId: asString(map['parentSessionId']),
      origin: asString(map['origin']),
      projections: hints == null ? SessionProjections.empty : SessionProjections.fromJson(hints),
      projectionsKind: asString(hints?['kind']),
      raw: map,
    );
  }

  final String sessionId;
  final DateTime updatedAt;
  final bool running;
  final bool blank;
  final bool agentAvailable;
  final String? cwd;
  final String? parentSessionId;
  final String? origin;
  final SessionProjections projections;
  final String? projectionsKind;
  final Map<String, Object?> raw;

  String? get title => projections.title;
  bool get isSubagent => origin == 'subagent';

  SessionSummary copyWith({
    bool? running,
    DateTime? updatedAt,
    bool? blank,
    SessionProjections? projections,
    String? projectionsKind,
  }) => SessionSummary(
    sessionId: sessionId,
    updatedAt: updatedAt ?? this.updatedAt,
    running: running ?? this.running,
    blank: blank ?? this.blank,
    agentAvailable: agentAvailable,
    cwd: cwd,
    parentSessionId: parentSessionId,
    origin: origin,
    projections: projections ?? this.projections,
    projectionsKind: projectionsKind ?? this.projectionsKind,
    raw: raw,
  );
}

class HistoryPage {
  const HistoryPage(this.events, this.hasMore);
  final List<SessionLogEvent> events;
  final bool hasMore;
}

// Workspaces: list and archive updates are consumed by the recent-session view.
class Workspace {
  const Workspace({
    required this.workspaceId,
    required this.path,
    required this.title,
    required this.sessionIds,
    this.createdAt,
    this.updatedAt,
  });

  factory Workspace.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return Workspace(
      workspaceId: asString(map['workspaceId']) ?? '',
      path: asString(map['path']) ?? '',
      title: asString(map['title']) ?? '',
      sessionIds: asStringList(map['sessionIds']),
      createdAt: DateTime.tryParse(asString(map['createdAt']) ?? ''),
      updatedAt: DateTime.tryParse(asString(map['updatedAt']) ?? ''),
    );
  }

  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

sealed class WorkspaceUpdate {
  const WorkspaceUpdate();

  static WorkspaceUpdate fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    switch (asString(map['type'])) {
      case 'baseline':
        final value = asMapOrEmpty(map['value']);
        return WorkspaceBaseline(
          asListOrEmpty(value['items']).map(Workspace.fromJson).toList(growable: false),
          asStringList(value['archivedSessionIds']),
          asStringList(value['pinnedSessionIds']),
        );
      case 'upsert':
        return WorkspaceUpsert(Workspace.fromJson(map['workspace']));
      case 'remove':
        return WorkspaceRemoved(asString(map['workspaceId']) ?? '');
      case 'order':
        return WorkspaceOrder(asStringList(map['workspaceIds']));
      case 'archived':
        return WorkspaceArchivedUpdate(asStringList(map['archivedSessionIds']));
      case 'pinned':
        return WorkspacePinnedUpdate(asStringList(map['pinnedSessionIds']));
      default:
        return UnknownWorkspaceUpdate(map);
    }
  }
}

final class WorkspaceBaseline extends WorkspaceUpdate {
  const WorkspaceBaseline(this.workspaces, this.archivedSessionIds, this.pinnedSessionIds);
  final List<Workspace> workspaces;
  final List<String> archivedSessionIds;
  final List<String> pinnedSessionIds;
}

final class WorkspaceUpsert extends WorkspaceUpdate {
  const WorkspaceUpsert(this.workspace);
  final Workspace workspace;
}

final class WorkspaceRemoved extends WorkspaceUpdate {
  const WorkspaceRemoved(this.workspaceId);
  final String workspaceId;
}

final class WorkspaceOrder extends WorkspaceUpdate {
  const WorkspaceOrder(this.workspaceIds);
  final List<String> workspaceIds;
}

/// Contains the complete archived set, rather than a delta.
final class WorkspaceArchivedUpdate extends WorkspaceUpdate {
  const WorkspaceArchivedUpdate(this.archivedSessionIds);
  final List<String> archivedSessionIds;
}

final class WorkspacePinnedUpdate extends WorkspaceUpdate {
  const WorkspacePinnedUpdate(this.pinnedSessionIds);
  final List<String> pinnedSessionIds;
}

final class UnknownWorkspaceUpdate extends WorkspaceUpdate {
  const UnknownWorkspaceUpdate(this.raw);
  final Map<String, Object?> raw;
}

// Host-wide $events. The Mux owns event arrival order, replay and cancellation.
sealed class DshEvent {
  const DshEvent();
}

enum DshConnectionState { idle, connecting, connected, reconnecting, unauthorized, closed }

sealed class HostEvent extends DshEvent {
  const HostEvent();

  static HostEvent fromFrame(Object? json) {
    final frame = asMapOrEmpty(json);
    switch (asString(frame['type'])) {
      case 'ready':
        return HostReadyEvent(asString(frame['clientId']) ?? '', asString(asMap(frame['host'])?['home']) ?? '');
      case 'emit':
        final event = asString(frame['event']) ?? '';
        final args = asListOrEmpty(frame['args']);
        Object? arg(int index) => index < args.length ? args[index] : null;
        switch (event) {
          case 'api-session/added':
            return SessionAddedEvent(SessionSummary.fromJson(arg(0)));
          case 'api-session/removed':
            return SessionRemovedEvent(asString(arg(0)) ?? '');
          case 'api-session/status':
            return SessionStatusEvent(asString(arg(0)) ?? '', arg(1) == true);
          default:
            return UnknownHostEvent(event, frame);
        }
      case 'waterfall':
        final event = asString(frame['event']) ?? '';
        final eventId = asString(frame['eventId']) ?? '';
        final agentId = asString(frame['agentId']) ?? '';
        if (event == 'approval/request') {
          return ApprovalRequestedEvent(ApprovalRequest.fromWaterfall(eventId, agentId, frame['request']));
        }
        if (event == 'user-questions/request') {
          return UserQuestionRequestedEvent(UserQuestionRequest.fromWaterfall(eventId, agentId, frame['request']));
        }
        return UnknownHostEvent(event, frame, eventId: eventId, agentId: agentId);
      case 'cancel':
        return HostRequestCancelledEvent(asString(frame['eventId']) ?? '');
      default:
        return UnknownHostEvent(asString(frame['type']) ?? '', frame);
    }
  }
}

final class HostReadyEvent extends HostEvent {
  const HostReadyEvent(this.clientId, this.home);
  final String clientId;
  final String home;
}

final class SessionAddedEvent extends HostEvent {
  const SessionAddedEvent(this.summary);
  final SessionSummary summary;
}

final class SessionRemovedEvent extends HostEvent {
  const SessionRemovedEvent(this.sessionId);
  final String sessionId;
}

final class SessionStatusEvent extends HostEvent {
  const SessionStatusEvent(this.sessionId, this.running);
  final String sessionId;
  final bool running;
}

final class ApprovalRequestedEvent extends HostEvent {
  const ApprovalRequestedEvent(this.request);
  final ApprovalRequest request;
}

final class UserQuestionRequestedEvent extends HostEvent {
  const UserQuestionRequestedEvent(this.request);
  final UserQuestionRequest request;
}

final class HostRequestCancelledEvent extends HostEvent {
  const HostRequestCancelledEvent(this.eventId);
  final String eventId;
}

final class UnknownHostEvent extends HostEvent {
  const UnknownHostEvent(this.event, this.raw, {this.eventId, this.agentId});
  final String event;
  final Map<String, Object?> raw;
  final String? eventId;
  final String? agentId;
}

enum ApprovalDecision {
  allowOnce('allowed-once'),
  reject('rejected'),
  pass('next');

  const ApprovalDecision(this.wire);
  final String wire;
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.eventId,
    required this.sessionId,
    required this.toolName,
    this.callId,
    this.reason,
    this.displayReason = const {},
    this.raw = const {},
  });

  factory ApprovalRequest.fromWaterfall(String eventId, String agentId, Object? request) {
    final map = asMapOrEmpty(request);
    final display = asMapOrEmpty(map['displayReason']);
    return ApprovalRequest(
      eventId: eventId,
      sessionId: agentId,
      toolName: asString(map['toolName']) ?? 'tool',
      callId: asString(map['callId']),
      reason: asString(map['reason']),
      displayReason: {
        for (final entry in display.entries)
          if (entry.value is String) entry.key: entry.value! as String,
      },
      raw: map,
    );
  }

  final String eventId;
  final String sessionId;
  final String toolName;
  final String? callId;
  final String? reason;
  final Map<String, String> displayReason;
  final Map<String, Object?> raw;

  String describe([String locale = 'en']) =>
      displayReason[locale] ?? displayReason['en'] ?? reason ?? 'Allow $toolName?';
}

class UserQuestion {
  const UserQuestion({required this.id, required this.question});

  factory UserQuestion.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return UserQuestion(id: asString(map['id']) ?? '', question: asString(map['question']) ?? '');
  }

  final String id;
  final String question;
}

class UserQuestionRequest {
  const UserQuestionRequest({
    required this.eventId,
    required this.sessionId,
    required this.questions,
    this.raw = const {},
  });

  factory UserQuestionRequest.fromWaterfall(String eventId, String agentId, Object? request) {
    final map = asMapOrEmpty(request);
    return UserQuestionRequest(
      eventId: eventId,
      sessionId: agentId,
      questions: asListOrEmpty(map['questions']).map(UserQuestion.fromJson).toList(growable: false),
      raw: map,
    );
  }

  final String eventId;
  final String sessionId;
  final List<UserQuestion> questions;
  final Map<String, Object?> raw;
}

// The subset of the durable log read by notification turn summaries. Unknown
// event kinds remain in the sequence so callers can retain the server cursor.
sealed class SessionLogEvent extends DshEvent {
  const SessionLogEvent(this.seq, this.time, this.type, this.data);

  final int seq;
  final DateTime time;
  final String type;
  final Map<String, Object?> data;

  static SessionLogEvent fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    final seq = asInt(map['seq']) ?? -1;
    final time = asEpochMs(map['time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final type = asString(map['type']) ?? '';
    final data = asMapOrEmpty(map['data']);
    final turn = asInt(data['turn']) ?? 0;
    final step = asInt(data['step']) ?? 0;
    return switch (type) {
      'turn/start' => TurnStartedEvent(seq, time, data, turn: turn),
      'turn/end' => TurnEndedEvent(seq, time, data, turn: turn, reason: TurnEndReason.fromJson(data['reason'])),
      'assistant/message' => AssistantMessageEvent(
        seq,
        time,
        data,
        turn: turn,
        step: step,
        message: Message.fromJson(data['message']),
      ),
      'tool/call' => ToolCallEvent(
        seq,
        time,
        data,
        turn: turn,
        step: step,
        callId: asString(data['callId']) ?? '',
        name: asString(data['name']) ?? '',
        arguments: asString(data['arguments']) ?? '',
      ),
      _ => UnknownEvent(seq, time, type, data),
    };
  }
}

final class TurnStartedEvent extends SessionLogEvent {
  const TurnStartedEvent(int seq, DateTime time, Map<String, Object?> data, {required this.turn})
    : super(seq, time, 'turn/start', data);
  final int turn;
}

class LlmFailure {
  const LlmFailure({required this.message, required this.code, this.status, this.raw = const {}});

  static LlmFailure? fromJson(Object? json) {
    final map = asMap(json);
    if (map == null) return null;
    return LlmFailure(
      message: asString(map['message']) ?? '',
      code: asString(map['code']) ?? 'UNKNOWN',
      status: asInt(map['status']),
      raw: map,
    );
  }

  final String message;
  final String code;
  final int? status;
  final Map<String, Object?> raw;
}

class TurnEndReason {
  const TurnEndReason(this.kind, {this.cancelCause, this.error, this.raw = const {}});

  factory TurnEndReason.fromJson(Object? json) {
    final map = asMapOrEmpty(json);
    return TurnEndReason(
      asString(map['kind']) ?? 'unknown',
      cancelCause: asString(asMap(map['reason'])?['kind']),
      error: LlmFailure.fromJson(map['error']),
      raw: map,
    );
  }

  final String kind;
  final String? cancelCause;
  final LlmFailure? error;
  final Map<String, Object?> raw;
}

final class TurnEndedEvent extends SessionLogEvent {
  const TurnEndedEvent(int seq, DateTime time, Map<String, Object?> data, {required this.turn, required this.reason})
    : super(seq, time, 'turn/end', data);
  final int turn;
  final TurnEndReason reason;
}

final class AssistantMessageEvent extends SessionLogEvent {
  const AssistantMessageEvent(
    int seq,
    DateTime time,
    Map<String, Object?> data, {
    required this.turn,
    required this.step,
    required this.message,
  }) : super(seq, time, 'assistant/message', data);
  final int turn;
  final int step;
  final Message message;
}

final class ToolCallEvent extends SessionLogEvent {
  const ToolCallEvent(
    int seq,
    DateTime time,
    Map<String, Object?> data, {
    required this.turn,
    required this.step,
    required this.callId,
    required this.name,
    required this.arguments,
  }) : super(seq, time, 'tool/call', data);
  final int turn;
  final int step;
  final String callId;
  final String name;
  final String arguments;
}

final class UnknownEvent extends SessionLogEvent {
  const UnknownEvent(super.seq, super.time, super.type, super.data);
}

/// RPC replies for `/api/session/page`.
class TurnWindow {
  const TurnWindow(this.minMessages, this.minTurns);
  final int minMessages;
  final int minTurns;
  Map<String, Object?> toJson() => {'minMessages': minMessages, 'minTurns': minTurns};
}
