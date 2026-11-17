import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/l10n.dart';
import '../../state/web_connection_state.dart';
import 'local_web_settings_screen.dart' show WebSettingsFrame;

/// Preview validation only; the connection controller independently validates
/// and strips transient credentials before persistence. Never execute QR data.
Uri? previewComputerAddress(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.contains(RegExp(r'[\s\\\x00-\x1f\x7f]'))) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port < 1 ||
      uri.port > 65535) {
    return null;
  }
  return uri;
}

/// HTTP(S) LAN webpage connection. PIN entry stays in the website; this page
/// records addresses only and opens the camera only after the scan button.
class ConnectComputerPage extends ConsumerStatefulWidget {
  const ConnectComputerPage({super.key});

  @override
  ConsumerState<ConnectComputerPage> createState() => _ConnectComputerPageState();
}

class _ConnectComputerPageState extends ConsumerState<ConnectComputerPage> {
  final _address = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect(String text, {bool qr = false, String? recordId}) async {
    if (_busy) return;
    final uri = previewComputerAddress(text);
    if (uri == null) {
      setState(() => _error = context.l10n.stateProviderUrlInvalid);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.remotePairConfirmTitle),
        // Origin only: a scanned launch-token query is never echoed in preview.
        content: Text(uri.origin, key: const ValueKey('computer-origin-preview')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(
            key: const ValueKey('computer-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.remoteConnectComputer),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(webConnectionProvider.notifier);
      if (recordId != null) {
        await controller.connectRecord(recordId);
      } else if (qr) {
        await controller.connectQr(text);
      } else {
        await controller.connectComputer(text);
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.commonConnectionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _AddressScanner()));
    if (text != null && mounted) await _connect(text, qr: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(webConnectionProvider);
    return WebSettingsFrame(
      title: l10n.remoteConnectComputer,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const ValueKey('computer-address'),
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            decoration: InputDecoration(
              labelText: l10n.remoteServerAddress,
              hintText: 'http://192.168.1.100:3090',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: _busy || !state.loaded ? null : (text) => unawaited(_connect(text)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('computer-connect'),
                onPressed: _busy || !state.loaded ? null : () => unawaited(_connect(_address.text)),
                child: Text(l10n.remoteConnectComputer),
              ),
              OutlinedButton.icon(
                key: const ValueKey('computer-scan'),
                onPressed: _busy ? null : () => unawaited(_scan()),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l10n.pluginsQrCode),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(l10n.remoteDirectoryRecent, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final record in state.records)
            ListTile(
              key: ValueKey('computer-record-${record.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(record.label),
              subtitle: Text(record.baseUrl, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: _busy ? null : () => unawaited(_connect(record.baseUrl, recordId: record.id)),
              trailing: IconButton(
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await ref.read(webConnectionProvider.notifier).removeRecord(record.id);
                        } catch (_) {
                          if (mounted) setState(() => _error = l10n.commonConnectionFailed);
                        }
                      },
              ),
            ),
        ],
      ),
    );
  }
}

class _AddressScanner extends StatefulWidget {
  const _AddressScanner();
  @override
  State<_AddressScanner> createState() => _AddressScannerState();
}

class _AddressScannerState extends State<_AddressScanner> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  late final Future<void> _ready;
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    _ready = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? const MethodChannel('dsh/app').invokeMethod<void>('initializePairingScanner')
        : Future<void>.value();
  }

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebSettingsFrame(
    title: context.l10n.pluginsQrCode,
    child: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(context.l10n.remotePairCameraFailed));
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return MobileScanner(
          controller: _scanner,
          onDetect: (capture) {
            if (_seen) return;
            final text = capture.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .firstOrNull;
            if (text == null) return;
            _seen = true;
            unawaited(_scanner.stop().catchError((Object _) {}));
            Navigator.of(context).pop(text);
          },
          errorBuilder: (context, _) => Center(child: Text(context.l10n.remotePairCameraFailed)),
        );
      },
    ),
  );
}
