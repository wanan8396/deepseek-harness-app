import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_bridge.dart';

/// App-only read channel. Never accepts a filename or sends document text to JavaScript.
class LocalSettingsDocuments {
  LocalSettingsDocuments({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('dsh/runtime');
  final MethodChannel _channel;

  Future<RuntimeStatus> status() async =>
      RuntimeStatus.fromMap(await _channel.invokeMapMethod<Object?, Object?>('getStatus') ?? const {});

  static bool sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port && a.userInfo.isEmpty && b.userInfo.isEmpty;

  static bool canRead(RuntimeStatus status, Uri page) {
    final base = Uri.tryParse(status.baseUrl ?? '');
    return status.isRunning &&
        status.generation != null &&
        status.generation! > 0 &&
        base != null &&
        base.scheme == 'http' &&
        base.host == '127.0.0.1' &&
        base.port > 0 &&
        sameOrigin(base, page);
  }

  static bool sameRun(RuntimeStatus a, RuntimeStatus b) =>
      a.isRunning &&
      b.isRunning &&
      a.generation != null &&
      a.generation == b.generation &&
      a.baseUrl == b.baseUrl &&
      a.token == b.token &&
      a.mode == b.mode;

  Future<LocalSettingsDocument> read(RuntimeStatus owner) async {
    final base = Uri.tryParse(owner.baseUrl ?? '');
    if (base == null || !canRead(owner, base)) throw const FormatException('configuration unavailable');
    final raw = await _channel.invokeMapMethod<Object?, Object?>('readLocalSettingsDocument', {
      'baseUrl': owner.baseUrl,
      'token': owner.token,
    });
    if (raw == null ||
        raw['generation'] != owner.generation ||
        raw['text'] is! String ||
        raw['displayName'] != 'cordis.patch.yml' ||
        raw['profile'] is! String ||
        raw['relativeDisplayPath'] is! String) {
      throw const FormatException('configuration unavailable');
    }
    final text = raw['text'] as String;
    if (text.length > 512 * 1024 || utf8.encode(text).length > 512 * 1024) {
      throw const FormatException('configuration too large');
    }
    final profile = raw['profile'] as String;
    final path = raw['relativeDisplayPath'] as String;
    final expected = owner.inSafeMode
        ? '/var/lib/dsh-app/safe-mode/home/profiles/dsh-app-safe/cordis.patch.yml'
        : '/root/.dsh/profiles/web/cordis.patch.yml';
    if (path != expected || profile != (owner.inSafeMode ? 'dsh-app-safe' : 'web')) {
      throw const FormatException('configuration unavailable');
    }
    return LocalSettingsDocument(text: text, path: path);
  }
}

class LocalSettingsDocument {
  const LocalSettingsDocument({required this.text, required this.path});
  final String text;
  final String path;
}

/// Read-only presentation. No save, clipboard, export, HTML or persistent cache.
class LocalSettingsDocumentPage extends StatefulWidget {
  const LocalSettingsDocumentPage({super.key, required this.document, required this.owner, required this.documents});
  final LocalSettingsDocument document;
  final RuntimeStatus owner;
  final LocalSettingsDocuments documents;

  @override
  State<LocalSettingsDocumentPage> createState() => _LocalSettingsDocumentPageState();
}

class _LocalSettingsDocumentPageState extends State<LocalSettingsDocumentPage> {
  Timer? _timer;
  bool _checking = false;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_checking || _expired) return;
    _checking = true;
    try {
      final next = await widget.documents.status();
      if (mounted && !LocalSettingsDocuments.sameRun(widget.owner, next)) _expire();
    } catch (_) {
      if (mounted) _expire();
    } finally {
      _checking = false;
    }
  }

  void _expire() {
    _timer?.cancel();
    setState(() => _expired = true);
    // Remove rendered text immediately, even if another route currently covers us.
    final route = ModalRoute.of(context);
    if (route?.isCurrent ?? false) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.webConfigDocumentTitle)),
      body: _expired
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('${l10n.webConfigDocumentReadOnly}\n${widget.document.path}'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.document.text,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
