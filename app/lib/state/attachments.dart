import 'dart:typed_data';


import '../l10n/l10n.dart';

/// Something picked in the composer and not sent yet.
///
/// Images DSH takes inline (png, jpeg, webp, gif) ride in the prompt itself;
/// anything else is staged first (`fileUploads/upload`, or a streamed binary
/// upload on hosts that support it) and referenced by its receipt. Which one
/// is decided from the bytes, not the file name.
class DraftAttachment {
  DraftAttachment({required this.name, required this.bytes, this.mediaType}) : id = _nextId++;

  factory DraftAttachment.sniff(String name, Uint8List bytes) =>
      DraftAttachment(name: name, bytes: bytes, mediaType: inlineImageType(bytes));

  static int _nextId = 0;

  /// Stable within the app run; keys the tray and the optimistic bubble.
  final int id;
  final String name;
  final Uint8List bytes;

  /// Set for inline images; null for files.
  final String? mediaType;

  bool get isImage => mediaType != null;
  int get size => bytes.length;
}

/// DSH's inline image limit (`SessionProjections.imageLimits` default).
const maxImageBytes = 20 * 1024 * 1024;

/// Files stream to the engine (`/api/session/uploadFileBinary`), so the
/// transfer holds about one copy of the file; the picker still keeps the
/// staged bytes (about two while assembling), so one message also has
/// [maxMessageBytes]. On a host without that route the client falls back to
/// base64 and refuses what one RPC frame can't hold.
const maxFileBytes = 200 * 1024 * 1024;

/// At most this many attachments per message (DSH allows 20 images).
const maxAttachments = 9;

/// Bytes one message's attachments may hold. The picker and the tray keep
/// every file in memory until the message is sent, so the ceiling is the
/// phone's heap rather than the Host; the share path's Kotlin budget
/// (`MAX_TOTAL_BYTES`) matches this.
const maxMessageBytes = 400 * 1024 * 1024;

/// Media type when [bytes] is an image DSH accepts inline, else null.
String? inlineImageType(Uint8List bytes) {
  bool at(int offset, List<int> sig) {
    if (bytes.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// "1.2 MB", "860 KB", "12 B".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

/// Why [a] can't be attached, or null when it can.
String? attachmentProblem(DraftAttachment a) {
  if (a.size == 0) return appL10n.stateAttachmentEmpty(a.name);
  if (a.isImage && a.size > maxImageBytes) {
    return appL10n.stateAttachmentImageLimit(a.name);
  }
  if (!a.isImage && a.size > maxFileBytes) {
    return appL10n.stateAttachmentFileLimit(a.name);
  }
  return null;
}

/// Bytes held by [attachments], counted against [maxMessageBytes].
int totalAttachmentBytes(Iterable<DraftAttachment> attachments) {
  var total = 0;
  for (final a in attachments) {
    total += a.size;
  }
  return total;
}

/// Why [a] can't join a message already holding [heldBytes], or null when it
/// fits. Checked in every path that grows the tray, so repeated picks cannot
/// pile past [maxMessageBytes] (or [limit], a smaller carrier such as the web
/// page's composer).
String? attachmentBudgetProblem(int heldBytes, DraftAttachment a, {int limit = maxMessageBytes}) =>
    heldBytes + a.size > limit ? appL10n.stateAttachmentTotalLimit : null;

