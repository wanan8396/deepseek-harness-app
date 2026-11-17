// Text, photos and files received through Android's system share sheet.
// The native share channel copies files into the app cache; WebEntryHost
// hands them to a new conversation in the official webpage.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_inbox.dart';

/// One shared file, copied into the app cache (readable with dart:io).
class SharedFile {
  const SharedFile({required this.path, required this.name, this.mime, this.size});

  final String path;

  /// As the sender named it (a photo scaled on the way in is a `.jpg`).
  final String name;
  final String? mime;
  final int? size;
}

enum ShareSkipReason { tooLarge, unreadable, tooMany }

/// A shared item that did not come through.
class SkippedShare {
  const SkippedShare(this.reason, [this.name]);

  final ShareSkipReason reason;

  /// Null when the sender gave no name (or it wasn't read).
  final String? name;
}

/// One arrival from the share sheet.
class IncomingShare {
  const IncomingShare({this.text, this.subject, this.files = const [], this.skipped = const []});

  /// EXTRA_TEXT (several joined by a blank line).
  final String? text;

  /// EXTRA_SUBJECT: a browser's page title, a mail subject.
  final String? subject;
  final List<SharedFile> files;
  final List<SkippedShare> skipped;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && files.isEmpty && skipped.isEmpty;

  /// What goes into the composer: the text, and over a bare link the page
  /// title it came with. A subject alone (a file's name, a mail subject next
  /// to an attachment) is left out.
  String get composedText {
    final body = text?.trim() ?? '';
    final title = subject?.trim() ?? '';
    if (body.isEmpty) return '';
    if (title.isEmpty || body.contains(title) || !_isBareLink(body)) {
      return body;
    }
    return '$title\n$body';
  }

  static bool _isBareLink(String text) {
    if (text.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  /// One `share` call's arguments; null for anything malformed or empty.
  static IncomingShare? parse(Object? raw) {
    if (raw is! Map) return null;
    String? string(Object? v) => v is String && v.isNotEmpty ? v : null;
    final files = <SharedFile>[
      for (final f in raw['files'] is List ? raw['files'] as List : const [])
        if (f is Map && string(f['path']) != null && string(f['name']) != null)
          SharedFile(
            path: f['path'] as String,
            name: f['name'] as String,
            mime: string(f['mime']),
            size: f['size'] is int ? f['size'] as int : null,
          ),
    ];
    final skipped = <SkippedShare>[
      for (final s in raw['skipped'] is List ? raw['skipped'] as List : const [])
        if (s is Map)
          SkippedShare(switch (s['reason']) {
            'too_large' => ShareSkipReason.tooLarge,
            'too_many' => ShareSkipReason.tooMany,
            _ => ShareSkipReason.unreadable,
          }, string(s['name'])),
    ];
    final share = IncomingShare(
      text: string(raw['text']),
      subject: string(raw['subject']),
      files: files,
      skipped: skipped,
    );
    return share.isEmpty ? null : share;
  }
}

/// The native bridge: a stream of shares.
class ShareIntake extends NativeInbox<IncomingShare> {
  ShareIntake({MethodChannel? channel})
    : super(channel ?? const MethodChannel('dsh/share'), method: 'share', parse: IncomingShare.parse);

  Stream<IncomingShare> get shares => stream;
}

final shareIntakeProvider = Provider<ShareIntake>((ref) {
  final intake = ShareIntake();
  ref.onDispose(intake.dispose);
  return intake;
});
