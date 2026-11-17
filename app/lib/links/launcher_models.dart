import '../state/host_ref.dart';

/// Where a launcher shortcut or the tile asked to go.
sealed class LauncherEntry {
  const LauncherEntry();

  /// One `entry` call's arguments; null for anything malformed.
  static LauncherEntry? parse(Object? raw) {
    if (raw is! Map) return null;
    final sessionId = raw['sessionId'];
    final host = HostRef.decode(raw['host'] is String ? raw['host'] as String : null);
    return switch (raw['kind']) {
      'new' => const NewChatEntry(),
      'chat' when sessionId is String && sessionId.isNotEmpty && host != null => OpenChatEntry(host, sessionId),
      _ => null,
    };
  }
}

/// A new conversation in the official webpage.
class NewChatEntry extends LauncherEntry {
  const NewChatEntry();
}

/// One of the recent conversations.
class OpenChatEntry extends LauncherEntry {
  const OpenChatEntry(this.host, this.sessionId);
  final HostRef host;
  final String sessionId;
}

/// A conversation as a launcher shortcut.
class RecentShortcut {
  const RecentShortcut({required this.sessionId, required this.title, required this.host});
  final String sessionId;
  final String title;
  final HostRef host;

  Map<String, Object?> toJson() => {'id': sessionId, 'title': title, 'host': host.encode()};

  @override
  bool operator ==(Object other) =>
      other is RecentShortcut && other.sessionId == sessionId && other.title == title && other.host == host;

  @override
  int get hashCode => Object.hash(sessionId, title, host);
}

/// At most this many conversations on the launcher.
const maxRecentShortcuts = 3;
