import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notify/chat_alerts.dart';
import '../notify/notify_channel.dart';
import 'connection_state.dart';
import 'host_ref.dart';
import 'selection_state.dart';
import 'web_connection_state.dart';

export '../notify/chat_alerts.dart';
export '../notify/notify_channel.dart';

final notifyChannelProvider = Provider<NotifyChannel>((ref) => NotifyChannel());

/// Preferences for the local web engine's ordinary notifications. Retired
/// notification keys are left in storage, not migrated or removed.
class NotifyPrefs {
  const NotifyPrefs({
    this.enabled = true,
    this.done = true,
    this.failed = true,
    this.approval = true,
    this.question = true,
    this.loaded = false,
  });

  final bool enabled;
  final bool done;
  final bool failed;
  final bool approval;
  final bool question;
  final bool loaded;

  bool allows(AlertKind kind) =>
      enabled &&
      switch (kind) {
        AlertKind.done => done,
        AlertKind.failed || AlertKind.stopped => failed,
        AlertKind.approval => approval,
        AlertKind.question => question,
      };

  NotifyPrefs copyWith({bool? enabled, bool? done, bool? failed, bool? approval, bool? question, bool? loaded}) =>
      NotifyPrefs(
        enabled: enabled ?? this.enabled,
        done: done ?? this.done,
        failed: failed ?? this.failed,
        approval: approval ?? this.approval,
        question: question ?? this.question,
        loaded: loaded ?? this.loaded,
      );
}

class NotifyPrefsController extends Notifier<NotifyPrefs> {
  static const _keys = (
    enabled: 'notify_enabled',
    done: 'notify_done',
    failed: 'notify_failed',
    approval: 'notify_approval',
    question: 'notify_question',
  );

  late Future<void> _loaded;

  @override
  NotifyPrefs build() {
    _loaded = _load();
    return const NotifyPrefs();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      state = NotifyPrefs(
        enabled: prefs.getBool(_keys.enabled) ?? true,
        done: prefs.getBool(_keys.done) ?? true,
        failed: prefs.getBool(_keys.failed) ?? true,
        approval: prefs.getBool(_keys.approval) ?? true,
        question: prefs.getBool(_keys.question) ?? true,
        loaded: true,
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loaded: true);
    }
  }

  Future<void> _save(String key, bool value, NotifyPrefs Function(NotifyPrefs) apply) async {
    await _loaded;
    if (!ref.mounted) return;
    state = apply(state);
    try {
      await (await SharedPreferences.getInstance()).setBool(key, value);
    } catch (_) {
      // Kept for this run only.
    }
  }

  Future<void> setEnabled(bool value) => _save(_keys.enabled, value, (s) => s.copyWith(enabled: value));
  Future<void> setDone(bool value) => _save(_keys.done, value, (s) => s.copyWith(done: value));
  Future<void> setFailed(bool value) => _save(_keys.failed, value, (s) => s.copyWith(failed: value));
  Future<void> setApproval(bool value) => _save(_keys.approval, value, (s) => s.copyWith(approval: value));
  Future<void> setQuestion(bool value) => _save(_keys.question, value, (s) => s.copyWith(question: value));
}

final notifyPrefsProvider = NotifierProvider<NotifyPrefsController, NotifyPrefs>(NotifyPrefsController.new);

final notifySystemStatusProvider = FutureProvider<NotifySystemStatus>(
  (ref) => ref.watch(notifyChannelProvider).status(),
);

class FlagController extends Notifier<bool> {
  FlagController(this._initial);

  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) {
    if (value != state) state = value;
  }
}

final appForegroundProvider = NotifierProvider<FlagController, bool>(() => FlagController(true));
final chatOnScreenProvider = NotifierProvider<FlagController, bool>(() => FlagController(true));

typedef ChatTarget = ({HostRef host, String sessionId});

final viewedChatProvider = Provider<ChatTarget?>((ref) {
  if (!ref.watch(appForegroundProvider) || !ref.watch(chatOnScreenProvider)) return null;
  final session = ref.watch(currentSessionProvider);
  return session == null ? null : (host: HostRef.local, sessionId: session);
});

final alertSourceFactoryProvider = Provider<AlertSource Function(HostConnection connection)>(
  (ref) =>
      (connection) => DshAlertSource(connection.client),
);

final alertTimingProvider = Provider<({Duration announce, Duration reconcile})>(
  (ref) => (announce: const Duration(milliseconds: 800), reconcile: const Duration(seconds: 3)),
);

enum AlertDelivery { none, banner, system }

AlertDelivery deliveryFor(ChatAlert alert, {required NotifyPrefs prefs, required bool foreground, ChatTarget? viewed}) {
  if (!prefs.allows(alert.kind)) return AlertDelivery.none;
  if (viewed != null && viewed.host == alert.host && viewed.sessionId == alert.sessionId) return AlertDelivery.none;
  return foreground ? AlertDelivery.banner : AlertDelivery.system;
}

NotifyPost postFor(ChatAlert alert) => NotifyPost(
  group: notifyGroup(alert.host, alert.sessionId),
  key: alert.key,
  attention: alert.kind.attention,
  title: alert.title,
  text: alert.text,
  publicText: alert.kind.publicText,
  sessionId: alert.sessionId,
  host: alert.host,
  kind: alert.kind.name,
  eventId: alert.eventId,
  canApprove: alert.canApprove,
  fullText: alert.fullText,
);

/// Owns one alert tracker for the local official engine. Computer pages have
/// their own web behavior and never attach a native client or phone alerts.
class ChatAlertsController extends Notifier<ChatAlert?> {
  HostConnection? _connection;
  HostAlertTracker? _tracker;
  StreamSubscription<NotifyAction>? _actions;
  bool _built = false;

  NotifyChannel get _channel => ref.read(notifyChannelProvider);
  ChatAlert? get _banner => _built ? state : null;

  bool get _localAlertsEnabled {
    final destination = ref.read(webConnectionProvider);
    return destination.loaded && destination.mode == WebConnectionMode.local;
  }

  set _banner(ChatAlert? value) {
    if (_built) state = value;
  }

  @override
  ChatAlert? build() {
    _built = false;
    final channel = _channel;
    unawaited(() async {
      if (!(await channel.status()).native || !ref.mounted) return;
      _actions = channel.actions.listen((action) async {
        await channel.completeAction(action, await respondAction(action));
      });
    }());
    ref.onDispose(() {
      unawaited(_actions?.cancel());
      unawaited(_tracker?.dispose());
      _tracker = null;
      _connection = null;
    });
    ref.listen(localConnectionProvider, (_, next) {
      _attach(_localAlertsEnabled ? next.value : null);
    }, fireImmediately: true);
    ref.listen(webConnectionProvider.select((s) => (s.loaded, s.mode)), (_, _) {
      _attach(_localAlertsEnabled ? ref.read(localConnectionProvider).value : null);
      if (!_localAlertsEnabled) {
        _banner = null;
        unawaited(_channel.cancelAll());
      }
    });
    ref.listen(viewedChatProvider, (_, viewed) {
      if (viewed != null) _clearSessionNotifications(viewed.sessionId);
    }, fireImmediately: true);
    ref.listen(notifyPrefsProvider.select((p) => p.enabled), (was, enabled) {
      if (was == true && !enabled) {
        _banner = null;
        unawaited(_channel.cancelAll());
      }
    });
    ref.listen(appForegroundProvider, (_, foreground) {
      final banner = _banner;
      if (!foreground && banner != null) {
        _banner = null;
        // Attention prompts are re-delivered from the still-pending requests.
        if (!banner.kind.attention) unawaited(_channel.show(postFor(banner)));
      }
      if (!foreground) {
        for (final alert in _tracker?.pendingAlerts ?? const <ChatAlert>[]) {
          _deliver(alert);
        }
      }
    });
    _built = true;
    return null;
  }

  Future<NotifyActionResult> respondAction(NotifyAction action) async {
    if (!_localAlertsEnabled) return NotifyActionResult.failed;
    final connection = _connection;
    final tracker = _tracker;
    if (connection == null || tracker == null || !tracker.source.connected) return NotifyActionResult.failed;
    final request = tracker.approvalFor(action.eventId);
    if (request == null) return NotifyActionResult.gone;
    try {
      await connection.client.respondApproval(request, action.decision);
      return NotifyActionResult.handled;
    } catch (_) {
      return NotifyActionResult.failed;
    }
  }

  void _attach(HostConnection? connection) {
    if (_connection != null && connection != null && identical(_connection!.client, connection.client)) {
      _connection = connection;
      return;
    }
    unawaited(_tracker?.dispose());
    _tracker = null;
    _connection = connection;
    if (connection == null) return;
    final timing = ref.read(alertTimingProvider);
    late final HostAlertTracker tracker;
    bool attached() => ref.mounted && _localAlertsEnabled && identical(_tracker, tracker);
    tracker = HostAlertTracker(
      host: HostRef.local,
      source: ref.read(alertSourceFactoryProvider)(connection),
      onAlert: (alert) {
        if (attached()) _deliver(alert);
      },
      onWithdraw: (_, session, key) {
        if (!attached()) return;
        unawaited(_channel.cancel(notifyGroup(HostRef.local, session), key));
        final banner = _banner;
        if (banner?.sessionId == session && banner?.key == key) _banner = null;
      },
      onSessionGone: (_, session) {
        if (attached()) _clearSessionNotifications(session);
      },
      announceDelay: timing.announce,
      reconcileDelay: timing.reconcile,
    );
    _tracker = tracker;
    tracker.start();
  }

  void _deliver(ChatAlert alert) {
    if (!_localAlertsEnabled) return;
    switch (deliveryFor(
      alert,
      prefs: ref.read(notifyPrefsProvider),
      foreground: ref.read(appForegroundProvider),
      viewed: ref.read(viewedChatProvider),
    )) {
      case AlertDelivery.none:
        return;
      case AlertDelivery.banner:
        _banner = alert;
      case AlertDelivery.system:
        unawaited(_channel.show(postFor(alert)));
    }
  }

  void _clearSessionNotifications(String sessionId) {
    unawaited(_channel.cancelGroup(notifyGroup(HostRef.local, sessionId)));
    if (_banner?.sessionId == sessionId) _banner = null;
  }

  void dismissBanner(ChatAlert alert) {
    if (identical(_banner, alert)) _banner = null;
  }

  void open(HostRef host, String sessionId) {
    ref.read(currentSessionProvider.notifier).select(sessionId);
  }
}

final chatAlertsProvider = NotifierProvider<ChatAlertsController, ChatAlert?>(ChatAlertsController.new);
