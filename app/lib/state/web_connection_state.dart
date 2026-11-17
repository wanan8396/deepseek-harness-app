import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store_state.dart';

enum WebConnectionMode { local, computer }

class WebComputerRecord {
  const WebComputerRecord({required this.id, required this.label, required this.baseUrl, required this.lastUsed});

  final String id;
  final String label;

  /// Display/persistence address: never contains a query or fragment.
  final String baseUrl;
  final DateTime lastUsed;

  Map<String, Object> _toJson() => {
    'id': id,
    'label': label,
    'baseUrl': baseUrl,
    'lastUsed': lastUsed.toUtc().toIso8601String(),
  };
}

class WebConnectionState {
  const WebConnectionState({
    this.loaded = false,
    this.mode = WebConnectionMode.local,
    this.computerUrl,
    this.records = const [],
  });

  final bool loaded;
  final WebConnectionMode mode;

  /// Full navigation URL, including any login query, held in memory only.
  final String? computerUrl;
  final List<WebComputerRecord> records;
}

final webConnectionProvider = NotifierProvider<WebConnectionController, WebConnectionState>(
  WebConnectionController.new,
);

/// A web destination, independent of the phone's on-device engine/host state.
/// PIN sessions stay in WebView cookies; this controller never reads cookies.
class WebConnectionController extends Notifier<WebConnectionState> {
  static const prefsKey = 'web_connection.v1';
  static String secretKey(String recordId) => 'web-computer.$recordId.login-url';

  late Future<void> ready;
  Future<void> _pending = Future<void>.value();
  bool _selectionTouched = false;
  String? _activeId;

  @override
  WebConnectionState build() {
    ready = _load();
    return const WebConnectionState();
  }

  Future<void> _load() async {
    var records = <WebComputerRecord>[];
    var mode = WebConnectionMode.local;
    String? activeId;
    String? url;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
      final saved = raw == null ? null : jsonDecode(raw);
      if (saved is Map) {
        final byOrigin = <String, WebComputerRecord>{};
        if (saved['records'] case final List entries) {
          for (final entry in entries) {
            try {
              if (entry is! Map) continue;
              final id = entry['id'];
              final label = entry['label'];
              final base = entry['baseUrl'];
              final used = entry['lastUsed'];
              if (id is! String ||
                  !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
                  base is! String ||
                  used is! String) {
                continue;
              }
              final address = _parseAddress(base);
              final record = WebComputerRecord(
                id: id,
                label: _label(label is String ? label : null, address.label),
                baseUrl: address.baseUrl,
                lastUsed: DateTime.parse(used).toUtc(),
              );
              final previous = byOrigin[address.origin];
              if (previous == null || record.lastUsed.isAfter(previous.lastUsed)) byOrigin[address.origin] = record;
            } on FormatException {
              // Corrupt records do not prevent using this phone or other records.
            }
          }
        }
        final ids = <String>{};
        records = byOrigin.values.where((record) => ids.add(record.id)).toList()
          ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        if (!_selectionTouched && saved['mode'] == WebConnectionMode.computer.name) {
          for (final record in records) {
            if (record.id == saved['selectedId']) {
              activeId = record.id;
              url = await _recordUrl(record);
              mode = WebConnectionMode.computer;
              break;
            }
          }
        }
      }
    } catch (_) {
      // Unavailable/corrupt preferences start locally; restoration never writes.
    }
    if (!ref.mounted) return;
    // An explicit choice made during a slow secure-store read wins at startup.
    if (_selectionTouched) {
      activeId = null;
      url = null;
      mode = WebConnectionMode.local;
    }
    _activeId = activeId;
    state = WebConnectionState(loaded: true, mode: mode, computerUrl: url, records: List.unmodifiable(records));
  }

  Future<void> connectComputer(String input, {String? label}) async {
    final address = _parseAddress(input);
    final requestedLabel = label == null ? null : _label(label, address.label);
    _selectionTouched = true;
    return _enqueue(() async {
      WebComputerRecord? previous;
      for (final record in state.records) {
        if (_parseAddress(record.baseUrl).origin == address.origin) {
          previous = record;
          break;
        }
      }
      final record = WebComputerRecord(
        id: previous?.id ?? _newId(),
        label: requestedLabel ?? previous?.label ?? address.label,
        baseUrl: address.baseUrl,
        lastUsed: _usedAfter(previous?.lastUsed),
      );
      try {
        if (address.url != address.baseUrl) {
          await ref.read(secretStoreProvider).write(secretKey(record.id), address.url);
        } else if (previous != null) {
          // A new bare address needs no secret-store access. Replacing a login
          // URL explicitly must also forget its old query/fragment.
          await ref.read(secretStoreProvider).delete(secretKey(record.id));
        }
      } catch (_) {
        throw StateError('web_connection_secret_save_failed');
      }
      if (!ref.mounted) return;
      final records = [record, ...state.records.where((old) => old.id != record.id)];
      await _save(records, WebConnectionMode.computer, record.id);
      if (!ref.mounted) return;
      _activeId = record.id;
      state = WebConnectionState(
        loaded: true,
        mode: WebConnectionMode.computer,
        computerUrl: address.url,
        records: List.unmodifiable(records),
      );
    });
  }

  /// Remote-access QR payloads are plain HTTP(S) URLs, not JSON or deep links.
  Future<void> connectQr(String input, {String? label}) => connectComputer(input, label: label);

  Future<void> connectRecord(String id) {
    _selectionTouched = true;
    return _enqueue(() async {
      final matches = state.records.where((record) => record.id == id);
      if (matches.isEmpty) throw StateError('web_computer_record_missing');
      final previous = matches.first;
      final url = await _recordUrl(previous);
      if (!ref.mounted) return;
      final record = WebComputerRecord(
        id: previous.id,
        label: previous.label,
        baseUrl: previous.baseUrl,
        lastUsed: _usedAfter(previous.lastUsed),
      );
      final records = [record, ...state.records.where((old) => old.id != id)];
      await _save(records, WebConnectionMode.computer, id);
      if (!ref.mounted) return;
      _activeId = id;
      state = WebConnectionState(
        loaded: true,
        mode: WebConnectionMode.computer,
        computerUrl: url,
        records: List.unmodifiable(records),
      );
    });
  }

  Future<void> setLocal() {
    _selectionTouched = true;
    return _enqueue(() async {
      await _save(state.records, WebConnectionMode.local, null);
      if (!ref.mounted) return;
      _activeId = null;
      state = WebConnectionState(loaded: true, records: state.records);
    });
  }

  Future<void> removeRecord(String id) => _enqueue(() async {
    if (!state.records.any((record) => record.id == id)) return;
    final records = state.records.where((record) => record.id != id).toList();
    final active = _activeId == id;
    try {
      await ref.read(secretStoreProvider).delete(secretKey(id));
    } catch (_) {
      throw StateError('web_connection_secret_delete_failed');
    }
    if (!ref.mounted) return;
    await _save(records, active ? WebConnectionMode.local : state.mode, active ? null : _activeId);
    if (!ref.mounted) return;
    if (active) _activeId = null;
    state = WebConnectionState(
      loaded: true,
      mode: active ? WebConnectionMode.local : state.mode,
      computerUrl: active ? null : state.computerUrl,
      records: List.unmodifiable(records),
    );
  });

  Future<void> _enqueue(Future<void> Function() action) {
    // Serialize explicit actions, including preferences writes and secure-store
    // awaits, so a slow earlier connect never overwrites a later local choice.
    final next = _pending.then((_) async {
      await ready;
      if (ref.mounted) await action();
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<String> _recordUrl(WebComputerRecord record) async {
    try {
      final stored = await ref.read(secretStoreProvider).read(secretKey(record.id));
      if (stored != null) {
        final address = _parseAddress(stored);
        if (address.baseUrl == record.baseUrl) return address.url;
      }
    } catch (_) {
      // Keystore loss or a stale URL falls back to PIN login on the base URL.
    }
    return record.baseUrl;
  }

  Future<void> _save(List<WebComputerRecord> records, WebConnectionMode mode, String? selectedId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        prefsKey,
        jsonEncode({
          'mode': mode.name,
          'selectedId': selectedId,
          'records': [for (final record in records) record._toJson()],
        }),
      );
      if (!saved) throw StateError('save_failed');
    } catch (_) {
      throw StateError('web_connection_save_failed');
    }
  }
}

DateTime _usedAfter(DateTime? previous) {
  final now = DateTime.now().toUtc();
  return previous != null && !now.isAfter(previous) ? previous.add(const Duration(microseconds: 1)) : now;
}

String _newId() {
  final random = Random.secure();
  return 'web-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

String _label(String? input, String fallback) {
  final label = input?.trim();
  if (label == null || label.isEmpty) return fallback;
  if (label.length > 120 || RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(label)) throw _invalidAddress();
  return label;
}

class _ComputerAddress {
  const _ComputerAddress(this.url, this.baseUrl, this.origin, this.label);
  final String url;
  final String baseUrl;
  final String origin;
  final String label;
}

FormatException _invalidAddress() => const FormatException('Invalid HTTP(S) computer address.');

_ComputerAddress _parseAddress(String input) {
  if (RegExp(r'[\x00-\x1f\x7f-\x9f\\]').hasMatch(input)) throw _invalidAddress();
  final text = input.trim();
  if (RegExp(r'\s|%(?![0-9a-fA-F]{2})').hasMatch(text)) throw _invalidAddress();
  final match = RegExp(r'^(https?)://([^/?#]*)(.*)$', caseSensitive: false).firstMatch(text);
  if (match == null) throw _invalidAddress();
  final scheme = match[1]!.toLowerCase();
  final authority = match[2]!;
  if (authority.isEmpty || authority.contains('@') || authority.contains('%')) throw _invalidAddress();
  String host;
  String portText;
  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end < 0) throw _invalidAddress();
    final ip = InternetAddress.tryParse(authority.substring(1, end));
    if (ip == null || ip.type != InternetAddressType.IPv6) throw _invalidAddress();
    host = '[${InternetAddress.fromRawAddress(ip.rawAddress, type: InternetAddressType.IPv6).address.toLowerCase()}]';
    portText = authority.substring(end + 1);
  } else {
    final pieces = authority.split(':');
    if (pieces.length > 2) throw _invalidAddress();
    host = pieces.first.toLowerCase();
    portText = pieces.length == 2 ? ':${pieces[1]}' : '';
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      final octets = host.split('.');
      if (octets.length != 4 || octets.any((part) => int.tryParse(part) == null || int.parse(part) > 255)) {
        throw _invalidAddress();
      }
      host = octets.map(int.parse).join('.');
    } else {
      final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
      final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
      if (name.isEmpty || name.length > 253 || !name.split('.').every(label.hasMatch)) throw _invalidAddress();
    }
  }
  final defaultPort = scheme == 'https' ? 443 : 80;
  var port = defaultPort;
  if (portText.isNotEmpty) {
    if (!RegExp(r'^:[0-9]+$').hasMatch(portText)) throw _invalidAddress();
    final value = int.tryParse(portText.substring(1));
    if (value == null || value < 1 || value > 65535) throw _invalidAddress();
    port = value;
  }
  final suffix = port == defaultPort ? '' : ':$port';
  try {
    final url = Uri.parse('$scheme://$host$suffix${match[3]}').toString();
    final base = url.split(RegExp(r'[?#]')).first;
    return _ComputerAddress(url, base, '$scheme://$host:$port', '$host$suffix');
  } on FormatException {
    throw _invalidAddress();
  }
}
