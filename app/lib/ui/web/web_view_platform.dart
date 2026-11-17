import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A WebView renderer is shared by all live pages in the process.
@immutable
class WebViewRendererGone {
  const WebViewRendererGone({required this.webViewId, required this.crashed});

  final int webViewId;
  final bool crashed;
}

/// The shell's native WebView lifecycle/color/zoom extension.
abstract class WebViewPlatform {
  static WebViewPlatform instance = MethodChannelWebViewPlatform();

  Future<bool> attach(int webViewId, {required bool dark, required int textZoom});
  Future<void> setDark(int webViewId, bool dark);
  Future<void> setTextZoom(int webViewId, int percent);
  Future<void> destroy(int webViewId);
  Stream<WebViewRendererGone> get events;
}

class MethodChannelWebViewPlatform extends WebViewPlatform {
  // Retain the installed Android bridge's wire identity during source retirement.
  MethodChannelWebViewPlatform([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('dsh/islands');

  final MethodChannel _channel;
  final _events = StreamController<WebViewRendererGone>.broadcast();
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (call.method == 'rendererGone' && args is Map && args['id'] is int) {
        _events.add(WebViewRendererGone(webViewId: args['id'] as int, crashed: args['crashed'] == true));
      }
      return null;
    });
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return null;
    _listen();
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> attach(int webViewId, {required bool dark, required int textZoom}) async =>
      await _call<bool>('attach', {'id': webViewId, 'dark': dark, 'textZoom': textZoom}) ?? false;

  @override
  Future<void> setDark(int webViewId, bool dark) => _call<void>('setDark', {'id': webViewId, 'dark': dark});

  @override
  Future<void> setTextZoom(int webViewId, int percent) =>
      _call<void>('setTextZoom', {'id': webViewId, 'zoom': percent});

  @override
  Future<void> destroy(int webViewId) => _call<void>('destroy', {'id': webViewId});

  @override
  Stream<WebViewRendererGone> get events {
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) _listen();
    return _events.stream;
  }
}
