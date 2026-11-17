import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native open-with file delivery. No feature or custom-scheme routing.
class AppLinks {
  AppLinks({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('dsh/links') {
    _controller = StreamController<Uri>.broadcast(onListen: _flush);
    _channel.setMethodCallHandler(_onCall);
    unawaited(_ready());
  }

  static const unreadableScheme = 'x-deepseek-harness-unreadable';
  final MethodChannel _channel;
  late final StreamController<Uri> _controller;
  final _held = <Uri>[];
  bool _disposed = false;

  /// Cold-start arrivals wait for WebEntryHost's first listener.
  Stream<Uri> get links => _controller.stream;

  Future<void> _ready() async {
    try {
      await _channel.invokeMethod<bool>('ready');
    } on MissingPluginException {
      // No Android bridge in desktop/widget tests.
    } on PlatformException {
      // A later native arrival remains independent of the ready probe.
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'link') throw MissingPluginException(call.method);
    final uri = parseNativeLink(call.arguments);
    if (uri != null) add(uri);
    return null;
  }

  void add(Uri uri) {
    if (_disposed || (uri.scheme != 'file' && uri.scheme != unreadableScheme)) return;
    if (_controller.hasListener) {
      _controller.add(uri);
    } else {
      _held.add(uri);
    }
  }

  void _flush() {
    final held = List.of(_held);
    _held.clear();
    held.forEach(_controller.add);
  }

  /// The native side copies opened files into its private cache before delivery.
  static Uri? parseNativeLink(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['uri'];
    if (value is String && value.isNotEmpty && value.length <= 64 * 1024) {
      final uri = Uri.tryParse(value);
      if (uri != null && uri.scheme == 'file') return uri;
    }
    if (raw['error'] is String) {
      final name = raw['name'];
      return Uri(scheme: unreadableScheme, path: name is String ? name : '');
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _held.clear();
    _channel.setMethodCallHandler(null);
    unawaited(_controller.close());
  }
}

final appLinksProvider = Provider<AppLinks>((ref) {
  final links = AppLinks();
  ref.onDispose(links.dispose);
  return links;
});
