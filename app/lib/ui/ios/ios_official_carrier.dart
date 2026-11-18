import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

const _officialChannel = MethodChannel('dsh/ios-local');
const _streamPath = '/api/ios-app/stream';
final _uuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
final _random = Random.secure();

const _closed = IosOfficialTransportException('IOS_OFFICIAL_CLOSED');
const _invalidReply = IosOfficialTransportException('IOS_OFFICIAL_INVALID_REPLY');
const _invalidRequest = IosOfficialTransportException('IOS_OFFICIAL_INVALID_REQUEST');

/// Transport or protocol failure, distinct from an official RPC error result.
/// This exception never carries a request, response body or platform details.
final class IosOfficialTransportException implements Exception {
  const IosOfficialTransportException(this.code, {this.status});

  final String code;
  final int? status;

  @override
  String toString() => 'IosOfficialTransportException($code${status == null ? '' : ', status: $status'})';
}

/// Uninterpreted native reply; callers may use their own RPC envelope types.
final class IosOfficialReply {
  const IosOfficialReply(this.status, this.body);

  final int status;
  final String body;
}

sealed class IosOfficialRpcResult {
  const IosOfficialRpcResult();
}

final class IosOfficialRpcSuccess extends IosOfficialRpcResult {
  const IosOfficialRpcSuccess(this.value);

  final Object? value;
}

final class IosOfficialRpcFailure extends IosOfficialRpcResult {
  const IosOfficialRpcFailure(this.error);

  final Map<String, Object?> error;
}

/// One App-owned native Host generation. No socket, HTTP client or legacy SDK
/// connection state is involved; the platform owns its lifetime and routing.
final class IosOfficialCarrier {
  IosOfficialCarrier._(this._channel, this.generation);

  static Future<IosOfficialCarrier> start({
    required String apiKey,
    required String protocol,
    required String baseUrl,
    required String modelId,
    MethodChannel channel = _officialChannel,
  }) async {
    final generation = await _invoke(channel, 'startOfficialRuntime', {
      'apiKey': apiKey,
      'protocol': protocol,
      'baseUrl': baseUrl,
      'modelId': modelId,
    });
    if (generation is! String || generation.length != 36 || !_uuid.hasMatch(generation)) {
      throw _invalidReply;
    }
    return IosOfficialCarrier._(channel, generation);
  }

  final MethodChannel _channel;
  final String generation;
  final _streams = <_Downlink>{};
  final _pendingPosts = <Completer<IosOfficialReply>>{};
  bool _closing = false;
  Future<void>? _stopFuture;

  /// Sends pre-encoded JSON via the native POST lane, exposing non-200 status
  /// codes to callers which already implement an official wire decoder.
  Future<IosOfficialReply> rawPost(String path, String body, {Duration? timeout}) {
    if (_closing) return Future.error(_closed);
    final pending = Completer<IosOfficialReply>();
    _pendingPosts.add(pending);
    unawaited(_completePost(pending, path, body, timeout));
    return pending.future;
  }

  Future<void> _completePost(
    Completer<IosOfficialReply> pending,
    String path,
    String body,
    Duration? timeout,
  ) async {
    try {
      final value = await _invoke(_channel, 'callOfficialRuntime', {
        'generation': generation,
        'path': path,
        'body': body,
      }, timeout: timeout);
      if (pending.isCompleted) return;
      if (value is! Map) throw _invalidReply;
      final status = value['status'];
      final text = value['body'];
      if (status is! int || status < 200 || status > 599 || text is! String) {
        throw _invalidReply;
      }
      pending.complete(IosOfficialReply(status, text));
    } catch (error, stack) {
      if (!pending.isCompleted) pending.completeError(error, stack);
    } finally {
      _pendingPosts.remove(pending);
    }
  }

  Future<IosOfficialRpcResult> call(
    String endpoint,
    Map<String, Object?> args, {
    Duration? timeout,
  }) async {
    final hex = _newId();
    final rpcId = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    final reply = await _postJson('/api/$endpoint', {
      'type': 'client-request',
      'rpcId': rpcId,
      'method': endpoint,
      'payload': {'args': args},
    }, timeout: timeout);
    final result = reply['result'];
    if (reply['type'] != 'server-response' || result is! Map<String, Object?>) {
      throw _invalidReply;
    }
    final echoed = reply['rpcId'];
    if (result['ok'] == true && echoed == rpcId) {
      return IosOfficialRpcSuccess(result['value']);
    }
    final error = result['error'];
    // Gateway validation failures can use the reserved ID instead of echoing.
    if (result['ok'] == false &&
        (echoed == rpcId || echoed == 'invalid-request') &&
        error is Map<String, Object?>) {
      return IosOfficialRpcFailure(error);
    }
    throw _invalidReply;
  }

  /// Cold, single-subscription downlink. Starts at listen time and holds at
  /// most one outstanding pull. Cancelling it leaves the generation running.
  Stream<Object?> openStream(String endpoint, Map<String, Object?> args) =>
      _Downlink(this, endpoint, args).stream;

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final String body;
    try {
      body = jsonEncode(payload);
    } on JsonUnsupportedObjectError {
      throw _invalidRequest;
    }
    final reply = await rawPost(path, body, timeout: timeout);
    if (reply.status != 200) {
      throw IosOfficialTransportException('IOS_OFFICIAL_STATUS', status: reply.status);
    }
    try {
      final decoded = jsonDecode(reply.body);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // FormatException retains the input, so do not propagate it.
    }
    throw _invalidReply;
  }

  /// Invalidate Dart consumers immediately. Native stop aborts the entire
  /// generation, including commands whose replies have not made it to Dart.
  Future<void> close() {
    final stop = _stopFuture;
    if (stop != null) return stop;
    _closing = true;
    for (final stream in _streams.toList()) {
      stream.runtimeClosed();
    }
    for (final pending in _pendingPosts) {
      pending.completeError(_closed);
    }
    _pendingPosts.clear();
    return _stopFuture = _stop();
  }

  Future<void> _stop() async {
    try {
      if (await _invoke(_channel, 'stopOfficialRuntime', {'generation': generation}) != null) {
        throw _invalidReply;
      }
    } on IosOfficialTransportException catch (error) {
      if (error.code == 'IOS_OFFICIAL_GENERATION_STALE') return;
      // Native may still be settling a stop. Allow a retry, but never accept
      // another request on this carrier, even if stop failed.
      _stopFuture = null;
      rethrow;
    }
  }
}

final class _Downlink {
  _Downlink(this._carrier, this._endpoint, this._args) {
    _controller = StreamController<Object?>(
      onListen: _listen,
      onResume: _pull,
      onCancel: _cancel,
    );
  }

  final IosOfficialCarrier _carrier;
  final String _endpoint;
  final Map<String, Object?> _args;
  final String _id = 's${_newId()}';
  late final StreamController<Object?> _controller;
  bool _opening = false;
  bool _pulling = false;
  bool _ended = false;
  bool _nativeEnded = false;
  Future<void>? _closeFuture;

  Stream<Object?> get stream => _controller.stream;

  void _listen() {
    if (_carrier._closing) {
      _controller.addError(_closed);
      _end();
      return;
    }
    _carrier._streams.add(this);
    _opening = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final reply = await _carrier._postJson(_streamPath, {
        'type': 'open',
        'id': _id,
        'endpoint': _endpoint,
        'payload': {'args': _args},
      });
      if (reply['opened'] != true) throw _invalidReply;
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _opening = false;
    }
    if (_ended) {
      await _closeNative();
    } else {
      _pull();
    }
  }

  void _pull() {
    if (_opening || _pulling || _ended || _controller.isPaused) return;
    _pulling = true;
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final reply = await _carrier._postJson(_streamPath, {'type': 'next', 'id': _id});
      if (_ended) return;
      if (reply['idle'] == true) return;
      if (reply['done'] == true) {
        // The mailbox already released the stream before acknowledging done.
        _nativeEnded = true;
        _end();
        return;
      }
      if (reply['done'] != false || !reply.containsKey('value')) throw _invalidReply;
      _controller.add(reply['value']);
    } catch (error, stack) {
      if (!_ended) {
        _fail(error, stack);
        unawaited(_closeNative());
      }
    } finally {
      _pulling = false;
      // Let a delivered item reach the consumer before testing pause/cancel.
      if (!_ended) scheduleMicrotask(_pull);
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_ended) return;
    _controller.addError(error, stack);
    _end();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _carrier._streams.remove(this);
    unawaited(_controller.close());
  }

  void runtimeClosed() => _end();

  Future<void> _cancel() async {
    _end();
    // Wait for admission in _open before sending close. The mailbox can pick
    // up a close file before an earlier open file if both are outstanding.
    // A pending next has no such ordering requirement and must not block close.
    if (!_opening) await _closeNative();
  }

  Future<void> _closeNative() {
    if (_carrier._closing || _nativeEnded) return Future.value();
    return _closeFuture ??= _sendClose();
  }

  Future<void> _sendClose() async {
    try {
      await _carrier._postJson(_streamPath, {'type': 'close', 'id': _id});
    } on IosOfficialTransportException {
      // The subscription has already ended. Generation stop also disposes
      // streams if this best-effort close cannot reach the mailbox.
    }
  }
}

Future<Object?> _invoke(
  MethodChannel channel,
  String method,
  Map<String, Object?> args, {
  Duration? timeout,
}) async {
  try {
    final call = channel.invokeMethod<Object?>(method, args);
    return await (timeout == null ? call : call.timeout(timeout));
  } on PlatformException catch (error) {
    final code = switch (error.code) {
      'IOS_CHAT_KEY_INVALID' ||
      'IOS_CHAT_CHANNEL_INVALID' ||
      'IOS_OFFICIAL_WORKSPACE_UNAVAILABLE' ||
      'IOS_OFFICIAL_BUSY' ||
      'IOS_OFFICIAL_TIMEOUT' ||
      'IOS_OFFICIAL_INVALID_REQUEST' ||
      'IOS_OFFICIAL_GENERATION_STALE' => error.code,
      _ => 'IOS_OFFICIAL_UNAVAILABLE',
    };
    throw IosOfficialTransportException(code);
  } on TimeoutException {
    throw const IosOfficialTransportException('IOS_OFFICIAL_TIMEOUT');
  } catch (_) {
    throw const IosOfficialTransportException('IOS_OFFICIAL_UNAVAILABLE');
  }
}

String _newId() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
