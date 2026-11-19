import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../links/launcher_models.dart';
import 'host_ref.dart';
import 'local_connection_state.dart';

/// Read-only recent conversations from the official local Web connection.
/// Null preserves existing launcher shortcuts while the inventory is unknown.
final localWebRecentShortcutsProvider = NotifierProvider<LocalWebRecentShortcutsController, List<RecentShortcut>?>(
  LocalWebRecentShortcutsController.new,
);

final localWebTitleClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

typedef _Title = ({DateTime updatedAt, String? title, bool? blank});
typedef _Failure = ({DateTime updatedAt, int count, DateTime retryAt});

class LocalWebRecentShortcutsController extends Notifier<List<RecentShortcut>?> {
  static const titleReadsAtOnce = 2;
  static const titleReadsPerList = 40;
  final Map<DshClient, int> _callsOut = Map.identity();
  int _epoch = 0;
  _Inventory? _inventory;

  @override
  List<RecentShortcut>? build() {
    final connection = ref.watch(officialLocalConnectionProvider);
    final epoch = ++_epoch;
    final previous = _inventory;
    previous?.retire();
    _inventory = null;
    final owner = ref;
    if (connection.isLoading || connection.hasError || connection.value == null) return null;
    final inventory = _inventory = _Inventory(connection.value!.client, owner.read(localWebTitleClockProvider));
    owner.onDispose(inventory.retire);
    bool current() => owner.mounted && epoch == _epoch && !inventory.retired;
    inventory.current = current;
    inventory.mux = inventory.client.mux.states.listen((status) {
      if (!current()) return;
      if (status == DshConnectionState.reconnecting) {
        // Pending HTTP projection calls survive a mux generation. Retire their
        // answers, but keep counting their slots until they actually finish.
        owner.invalidateSelf();
      } else if (status == DshConnectionState.unauthorized || status == DshConnectionState.closed) {
        inventory.retire();
        state = null;
      }
    });
    inventory.events = inventory.client.hostEvents.listen((event) {
      if (!current()) return;
      if (event is SessionAddedEvent ||
          event is SessionRemovedEvent ||
          event is SessionStatusEvent ||
          event is HostReadyEvent) {
        // A ready edge during the initial read is covered by that read. A
        // conversation edge is not: it may have happened after its snapshot.
        if (event is HostReadyEvent && inventory.loading) return;
        inventory.debounce?.cancel();
        inventory.debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_refresh(inventory)));
      }
    });
    inventory.workspaces = inventory.client.watchWorkspaces().listen(
      (update) {
        if (!current()) return;
        final archived = switch (update) {
          WorkspaceBaseline(:final archivedSessionIds) => archivedSessionIds,
          WorkspaceArchivedUpdate(:final archivedSessionIds) => archivedSessionIds,
          _ => workspaceReplaceFrame(update)?.archivedSessionIds,
        };
        if (archived == null) return;
        inventory.archived = archived.toSet();
        _publish(inventory);
      },
      onError: (Object _) {
        if (!current()) return;
        inventory.archived = null;
        _publish(inventory);
      },
    );
    unawaited(_start(inventory));
    return null;
  }

  Future<void> _start(_Inventory inventory) async {
    // Compatibility only: a saved companion conversation remains hidden, but
    // no companion owner (and thus no native-chat/account owner) is started.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('companion_sessions');
      final bindings = raw == null ? null : jsonDecode(raw);
      final binding = bindings is Map ? bindings['local:null'] : null;
      inventory.companionId = binding is Map && binding['id'] is String ? binding['id'] as String : null;
    } catch (_) {
      // An unreadable legacy preference has no binding, as in the old owner.
    }
    inventory.preferencesReady = true;
    if (inventory.current()) await _refresh(inventory);
  }

  /// Also used by explicit refreshes; no session mutation API is exposed.
  Future<void> refresh() async {
    final inventory = _inventory;
    if (inventory != null) await _refresh(inventory);
  }

  Future<void> _refresh(_Inventory inventory) async {
    if (!inventory.current()) return;
    if (inventory.loading) {
      inventory.reload = true;
      return;
    }
    inventory.loading = true;
    state = null;
    try {
      final rows = await inventory.client.listSessions();
      if (!inventory.current()) return;
      inventory.rows = rows;
      inventory.failed = false;
      _queueTitles(inventory);
    } catch (_) {
      if (!inventory.current()) return;
      inventory.failed = true;
    } finally {
      inventory.loading = false;
      if (inventory.current()) {
        _publish(inventory);
        if (inventory.reload) {
          inventory.reload = false;
          unawaited(_refresh(inventory));
        }
      }
    }
  }

  bool _visible(_Inventory inventory, SessionSummary row) =>
      row.sessionId.isNotEmpty &&
      !row.blank &&
      !row.isSubagent &&
      !(inventory.archived?.contains(row.sessionId) ?? false) &&
      row.sessionId != inventory.companionId;

  void _publish(_Inventory inventory) {
    if (!inventory.current()) return;
    if (!inventory.preferencesReady ||
        inventory.loading ||
        inventory.failed ||
        inventory.rows == null ||
        inventory.archived == null) {
      state = null;
      return;
    }
    final rows = [for (final row in inventory.rows!) _withTitle(row, inventory.titles[row.sessionId])]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = [
      for (final row in rows.where((row) => _visible(inventory, row)).take(maxRecentShortcuts))
        RecentShortcut(
          sessionId: row.sessionId,
          title: switch (row.title?.trim()) {
            final title? when title.isNotEmpty => title,
            _ => appL10n.commonUntitledChat,
          },
          host: HostRef.local,
        ),
    ];
  }

  void _queueTitles(_Inventory inventory) {
    if (inventory.unsupported) return;
    final now = inventory.now();
    final rows = inventory.rows!.where((row) {
      final failure = inventory.failures[row.sessionId];
      return _visible(inventory, row) &&
          row.projectionsKind != 'sequenced' &&
          (row.title?.trim().isEmpty ?? true) &&
          !inventory.running.contains(row.sessionId) &&
          inventory.titles[row.sessionId]?.updatedAt != row.updatedAt &&
          !(failure != null && failure.updatedAt == row.updatedAt && now.isBefore(failure.retryAt));
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    inventory.queue
      ..clear()
      ..addAll(rows.take(titleReadsPerList));
    _nextTitles(inventory);
  }

  void _nextTitles(_Inventory inventory) {
    final client = inventory.client;
    while (inventory.current() &&
        !inventory.unsupported &&
        (_callsOut[client] ?? 0) < titleReadsAtOnce &&
        inventory.queue.isNotEmpty) {
      final row = inventory.queue.removeFirst();
      inventory.running.add(row.sessionId);
      _callsOut[client] = (_callsOut[client] ?? 0) + 1;
      unawaited(_readTitle(inventory, row));
    }
  }

  Future<void> _readTitle(_Inventory inventory, SessionSummary row) async {
    _Title? title;
    var unsupported = false;
    var failed = false;
    try {
      final projections = await inventory.client.projections(row.sessionId);
      title = (updatedAt: row.updatedAt, title: projections?.title, blank: projections?.blank);
    } on DshRemoteException catch (error) {
      unsupported = error.code == 'METHOD_NOT_ALLOWED' || error.code.endsWith('method-not-found');
      failed = !unsupported;
    } on DshHttpException catch (error) {
      unsupported = error.statusCode == 403 || error.statusCode == 404;
      failed = !unsupported;
    } catch (_) {
      failed = true;
    }
    final client = inventory.client;
    final out = (_callsOut[client] ?? 1) - 1;
    if (out == 0) {
      _callsOut.remove(client);
    } else {
      _callsOut[client] = out;
    }
    inventory.running.remove(row.sessionId);
    if (!inventory.current()) {
      final next = _inventory;
      if (next != null && identical(next.client, client)) _nextTitles(next);
      return;
    }
    if (unsupported) {
      inventory.unsupported = true;
      inventory.queue.clear();
    }
    // A row updated while its projection was out is a different generation.
    // Discard that answer (including failures) and ask the current row again.
    final live = inventory.rows?.where((live) => live.sessionId == row.sessionId).firstOrNull;
    if (live?.updatedAt == row.updatedAt) {
      if (failed) {
        final before = inventory.failures[row.sessionId];
        final count = before?.updatedAt == row.updatedAt ? before!.count + 1 : 1;
        var wait = count == 1 ? Duration.zero : const Duration(seconds: 15) * (1 << (count - 2).clamp(0, 10));
        if (wait > const Duration(minutes: 10)) wait = const Duration(minutes: 10);
        inventory.failures[row.sessionId] = (
          updatedAt: row.updatedAt,
          count: count,
          retryAt: inventory.now().add(wait),
        );
      }
      if (title != null) {
        inventory.titles[row.sessionId] = title;
        inventory.failures.remove(row.sessionId);
        _publish(inventory);
      }
    } else if (live != null && !inventory.unsupported) {
      // Refill only for a changed row; a failure waits for the next list.
      _queueTitles(inventory);
    }
    _nextTitles(inventory);
  }
}

/// Pure row projection: sequenced hints win; old titles may bridge a refresh,
/// but a folded blank flag applies only to the exact row that was read.
SessionSummary _withTitle(SessionSummary row, _Title? read) {
  if (read == null || row.projectionsKind == 'sequenced') return row;
  final title = read.title?.trim();
  final fill = (row.title?.trim().isEmpty ?? true) && title != null && title.isNotEmpty;
  final blank = read.blank == true && read.updatedAt == row.updatedAt;
  return row.copyWith(
    blank: blank ? true : null,
    projections: fill ? SessionProjections(row.projections.asOfSeq, {...row.projections.values, 'title': title}) : null,
  );
}

class _Inventory {
  _Inventory(this.client, this.now);
  final DshClient client;
  final DateTime Function() now;
  late bool Function() current;
  bool retired = false;
  bool preferencesReady = false;
  bool loading = false;
  bool reload = false;
  bool failed = false;
  bool unsupported = false;
  String? companionId;
  List<SessionSummary>? rows;
  Set<String>? archived;
  final titles = <String, _Title>{};
  final failures = <String, _Failure>{};
  final running = <String>{};
  final queue = ListQueue<SessionSummary>();
  StreamSubscription<DshConnectionState>? mux;
  StreamSubscription<HostEvent>? events;
  StreamSubscription<WorkspaceUpdate>? workspaces;
  Timer? debounce;

  void retire() {
    if (retired) return;
    retired = true;
    queue.clear();
    debounce?.cancel();
    unawaited(mux?.cancel());
    unawaited(events?.cancel());
    unawaited(workspaces?.cancel());
  }
}
