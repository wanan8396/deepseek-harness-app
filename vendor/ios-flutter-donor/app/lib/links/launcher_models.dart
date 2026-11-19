import '../state/host_ref.dart';

/// Where a launcher shortcut or the tile asked to go.
sealed class LauncherEntry {
  const LauncherEntry();

  /// One `entry` call's arguments; null for anything malformed.
  static LauncherEntry? parse(Object? raw) {
    if (raw is! Map) return null;
    final sessionId = raw['sessionId'];
    final host = raw['host'];
    final text = raw['text'] is String ? raw['text'] as String : '';
    final path = raw['path'];
    return switch (raw['kind']) {
      'new' => NewChatEntry(text: text),
      'voice' => NewChatEntry(voice: true, text: text),
      'screenshot' when path is String && path.startsWith('/') && !path.contains('\u0000') => ScreenshotEntry(path),
      'chat' when sessionId is String && sessionId.isNotEmpty => OpenChatEntry(
        HostRef.decode(host is String ? host : null),
        sessionId,
      ),
      _ => null,
    };
  }
}

/// A new conversation; [voice] starts dictation in its composer.
class NewChatEntry extends LauncherEntry {
  const NewChatEntry({this.voice = false, this.text = ''});
  final String text;
  final bool voice;
}

/// A pet screenshot in the app's private cache, authenticated by the native
/// entry bridge. It is attached to a new-chat draft, never sent automatically.
class ScreenshotEntry extends LauncherEntry {
  const ScreenshotEntry(this.path);
  final String path;
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
      other is RecentShortcut &&
      other.sessionId == sessionId &&
      other.title == title &&
      other.host == host &&
      other.host.name == host.name;

  @override
  int get hashCode => Object.hash(sessionId, title, host);
}

/// At most this many conversations on the launcher.
const maxRecentShortcuts = 3;
