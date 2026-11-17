// Bounded share and open-with requests passed to the official webpage.

import 'dart:io';
import 'dart:typed_data';


import '../l10n/l10n.dart';
import '../links/share_intake.dart';
import 'attachments.dart';

/// Name of the attachment a long shared text becomes.
String get sharedTextFileName => appL10n.fileSharedText;

/// One fill of the new-chat composer.
class ComposeRequest {
  const ComposeRequest({
    this.text = '',
    this.attachments = const [],
    this.problems = const [],
  });

  final String text;
  final List<DraftAttachment> attachments;

  /// What didn't come through, one short line each; the first is shown.
  final List<String> problems;

  /// Reads a share's files (copied into the app cache by the native side)
  /// into attachments, then deletes the copies: the bytes live in the draft.
  ///
  /// [heldBytes] is what the target draft already holds and [maxBytes] is the
  /// budget of the composer it lands in (the web page takes far less than a
  /// chat message): both are checked before a file is read, so a share cannot
  /// buffer bytes that the merge below would refuse anyway.
  static Future<ComposeRequest> fromShare(
    IncomingShare share, {
    Future<Uint8List> Function(String path)? read,
    int heldBytes = 0,
    int maxBytes = maxMessageBytes,
  }) async {
    final load = read ?? (path) => File(path).readAsBytes();
    final attachments = <DraftAttachment>[];
    final problems = [for (final s in share.skipped) skippedText(s)];
    var used = heldBytes;
    for (final file in share.files) {
      // Metadata can refuse a file before it is read; content providers may
      // omit it, so the post-read check below still applies.
      final length = read == null ? _fileLength(file.path) : null;
      if (length != null && used + length > maxBytes) {
        problems.add(appL10n.stateAttachmentTotalLimit);
        if (read == null) _discard(file.path);
        continue;
      }
      final Uint8List bytes;
      try {
        bytes = await load(file.path);
      } catch (_) {
        problems.add(appL10n.stateShareReadFailed(file.name));
        continue;
      } finally {
        if (read == null) _discard(file.path);
      }
      final attachment = DraftAttachment.sniff(file.name, bytes);
      final problem =
          attachmentProblem(attachment) ?? attachmentBudgetProblem(used, attachment, limit: maxBytes);
      if (problem != null) {
        problems.add(problem);
      } else {
        attachments.add(attachment);
        used += attachment.size;
      }
    }
    return ComposeRequest(text: share.composedText, attachments: attachments, problems: problems);
  }

  /// A file opened with the app, already in the cache.
  static Future<ComposeRequest> fromFile(
    String path, {
    Future<Uint8List> Function(String path)? read,
    int heldBytes = 0,
    int maxBytes = maxMessageBytes,
  }) async {
    final name = path.split('/').last;
    final length = read == null ? _fileLength(path) : null;
    if (length != null && heldBytes + length > maxBytes) {
      return ComposeRequest(problems: [appL10n.stateAttachmentTotalLimit]);
    }
    try {
      final bytes = await (read ?? (p) => File(p).readAsBytes())(path);
      final attachment = DraftAttachment.sniff(name, bytes);
      final problem =
          attachmentProblem(attachment) ?? attachmentBudgetProblem(heldBytes, attachment, limit: maxBytes);
      return problem == null ? ComposeRequest(attachments: [attachment]) : ComposeRequest(problems: [problem]);
    } catch (_) {
      return ComposeRequest(problems: [appL10n.stateShareReadFailed(name)]);
    }
  }

  static int? _fileLength(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  static void _discard(String path) {
    try {
      final file = File(path);
      final slot = file.parent;
      file.deleteSync();
      if (slot.listSync().isEmpty) slot.deleteSync();
    } catch (_) {
      // Pruned by the native side on the next share anyway.
    }
  }
}

/// One line for a shared item that didn't come through.
String skippedText(SkippedShare skipped) {
  final name = skipped.name;
  return switch (skipped.reason) {
    ShareSkipReason.tooMany => appL10n.stateShareAttachmentLimit(maxAttachments),
    ShareSkipReason.tooLarge =>
      name == null ? appL10n.stateShareFileTooLarge : appL10n.stateShareNamedFileTooLarge(name),
    ShareSkipReason.unreadable => name == null ? appL10n.stateShareFileUnreadable : appL10n.stateShareReadFailed(name),
  };
}
