import 'dart:convert';

import '../../l10n/l10n.dart';

/// Destinations the phone shell asks the official webpage to open.
class DshWebTarget {
  const DshWebTarget({this.sessionId, this.settings, this.newSession = false});

  final String? sessionId;
  final DshWebSettings? settings;
  final bool newSession;

  bool get isHome => sessionId == null && settings == null && !newSession;

  Map<String, Object?> toJson() => {
    'session': ?sessionId,
    'settings': ?settings?.key,
    if (newSession) 'newSession': true,
  };

  String get openScript => 'window.__dshAppOpen && window.__dshAppOpen(${jsonEncode(toJson())});';

  @override
  bool operator ==(Object other) => other is DshWebTarget && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'DshWebTarget(${jsonEncode(toJson())})';
}

/// IDs of settings sections owned and rendered by the official webpage.
enum DshWebSettings {
  general('general'),
  models('models'),
  plugins('plugins'),
  agentPresets('agent-presets'),
  account('account');

  const DshWebSettings(this.key);
  final String key;
}

/// Result reported by the injected official-page navigation adapter.
class DshWebOpenResult {
  const DshWebOpenResult({required this.ok, this.step});

  static DshWebOpenResult? parse(String message) {
    try {
      final json = jsonDecode(message);
      if (json is! Map) return null;
      final step = json['step'];
      return DshWebOpenResult(ok: json['ok'] == true, step: step is String ? step : null);
    } on FormatException {
      return null;
    }
  }

  final bool ok;
  final String? step;

  String? get problem => ok
      ? null
      : switch (step) {
          'session' => appL10n.webTargetSessionMissing,
          'boot' => appL10n.webTargetNotLoaded,
          'settings' => appL10n.webTargetSettingsMissing,
          'newSession' => appL10n.webTargetNewChatFailed,
          _ => appL10n.webTargetPageFailed,
        };
}
