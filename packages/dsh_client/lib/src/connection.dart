/// HTTP + WebSocket access to one authenticated `dsh web` Host.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'background_session_read.dart';
import 'errors.dart';
import 'json.dart';
import 'models.dart' show SessionSummary;

/// Signed browser-session cookie minted by `GET /?token=<launch token>`.
class DshCookie {
  const DshCookie({required this.name, required this.value, required this.authority, this.expiresAt});

  factory DshCookie.fromJson(Map<String, Object?> json) => DshCookie(
    name: asString(json['name']) ?? '',
    value: asString(json['value']) ?? '',
    authority: asString(json['authority']) ?? '',
    expiresAt: asEpochMs(json['expiresAt']),
  );

  final String name;
  final String value;
  final String authority;
  final DateTime? expiresAt;
  String get header => '$name=$value';

  Map<String, Object?> toJson() => {
    'name': name,
    'value': value,
    'authority': authority,
    if (expiresAt != null) 'expiresAt': expiresAt!.millisecondsSinceEpoch,
  };

  @override
  String toString() => 'DshCookie($name for $authority, expires $expiresAt)';
}

/// One observed wire exchange, for local diagnostics and tests.
class DshTraceEntry {
  DshTraceEntry(this.direction, this.channel, this.data) : time = DateTime.now();
  final DateTime time;
  final String direction;
  final String channel;
  final Object? data;

  Map<String, Object?> toJson() => {
    't': time.millisecondsSinceEpoch,
    'dir': direction,
    'channel': channel,
    'data': data,
  };
}

typedef DshTracer = void Function(DshTraceEntry entry);

/// Raw HTTP response with its complete body.
class DshHttpResponse {
  const DshHttpResponse(this.statusCode, this.contentType, this.body, {this.setCookies = const []});
  final int statusCode;
  final String contentType;
  final Uint8List body;
  final List<String> setCookies;
  String get text => utf8.decode(body, allowMalformed: true);
}

/// Physical HTTP/WebSocket transport for the Lite client's local Host.
class DshConnection {
  DshConnection(
    Uri baseUri, {
    this.hostHeader,
    this.cookie,
    HttpClient? httpClient,
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 120),
    DshTracer? tracer,
  }) : baseUri = _normalizeBase(baseUri),
       _http = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null,
       _usesDefaultHttp = httpClient == null && HttpOverrides.current == null,
       _tracer = tracer {
    if (_ownsClient) {
      _http
        ..connectionTimeout = connectTimeout
        ..idleTimeout = const Duration(seconds: 15)
        ..autoUncompress = true;
    }
  }

  final Uri baseUri;
  final String? hostHeader;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final HttpClient _http;
  final bool _ownsClient;
  final bool _usesDefaultHttp;
  DshTracer? _tracer;
  bool _closed = false;
  BackgroundListReads? _backgroundReads;

  DshTracer? get tracer => _tracer;
  set tracer(DshTracer? value) {
    if (!identical(value, _tracer)) {
      _backgroundReads?.close();
      _backgroundReads = null;
    }
    _tracer = value;
  }

  DshCookie? cookie;
  String get authority => hostHeader ?? _authorityOf(baseUri);

  bool get canReadSessionsInBackground =>
      runtimeType == DshConnection && _usesDefaultHttp && !_closed && tracer == null && HttpOverrides.current == null;

  Future<List<SessionSummary>> readSessionsInBackground() async =>
      (await readListInBackground(BackgroundListKind.sessions)) as List<SessionSummary>;

  Future<Object?> readListInBackground(BackgroundListKind kind) {
    if (!canReadSessionsInBackground) throw StateError('background session reads are unavailable');
    return (_backgroundReads ??= BackgroundListReads()).read(
      BackgroundListRequest(
        uri: resolve('/api/${kind.endpoint}'),
        kind: kind,
        rpcId: uuidV4(),
        connectTimeout: connectTimeout,
        requestTimeout: requestTimeout,
        hostHeader: hostHeader,
        cookieHeader: cookie?.header,
      ),
    );
  }

  Uri resolve(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(
      path: '${baseUri.path}$normalized',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// Exchanges the launch token for a session cookie bound to this authority.
  Future<DshCookie> login(String token) async {
    final uri = resolve('/', {'token': token});
    tracer?.call(DshTraceEntry('out', 'http', {'method': 'GET', 'path': '/?token=<redacted>'}));
    final response = await _exchange('GET', uri, followRedirects: false);
    tracer?.call(DshTraceEntry('in', 'http', {'status': response.statusCode, 'path': '/'}));
    if (response.statusCode == 401) {
      throw const DshHttpException(401, 'launch token rejected (stale token, other dsh process, or wrong host:port)');
    }
    if (response.statusCode != 303 && response.statusCode != 302) {
      throw DshHttpException(response.statusCode, 'unexpected login response', body: response.text);
    }
    final minted = response.setCookies
        .map((raw) => _parseSetCookie(raw, authority))
        .whereType<DshCookie>()
        .where((value) => value.name.startsWith('dsh-auth-'))
        .firstOrNull;
    if (minted == null) throw const DshProtocolException('login redirect carried no dsh-auth cookie');
    cookie = minted;
    return minted;
  }

  /// Posts one JSON request to the Host's RPC endpoint.
  Future<DshHttpResponse> postJson(String path, Object? body, {Duration? timeout}) => _exchange(
    'POST',
    resolve(path),
    body: utf8.encode(jsonEncode(body)),
    contentType: 'application/json',
    timeout: timeout,
  );

  /// Opens the authenticated `/api/remote.mux` WebSocket.
  Future<WebSocket> connectWebSocket(String path, {Duration? timeout}) async {
    final headers = <String, Object>{if (cookie != null) 'Cookie': cookie!.header, 'Host': ?hostHeader};
    final uri = resolve(path).replace(scheme: baseUri.scheme == 'https' ? 'wss' : 'ws');
    var abandoned = false;
    try {
      return await WebSocket.connect(uri.toString(), headers: headers, customClient: _http)
          .then((socket) {
            if (abandoned || _closed) {
              unawaited(socket.close().catchError((_) {}));
              throw const DshClosedException('WebSocket connection abandoned');
            }
            return socket;
          })
          .timeout(
            timeout ?? connectTimeout,
            onTimeout: () {
              abandoned = true;
              throw TimeoutException('WebSocket connect timed out');
            },
          );
    } on WebSocketException catch (error) {
      final status = error.httpStatusCode;
      if (status != null) throw DshHttpException(status, 'WebSocket upgrade refused: ${error.message}');
      throw DshTransportException('WebSocket failed: ${error.message}', error);
    } on TimeoutException catch (error) {
      throw DshTransportException('WebSocket connect timed out', error);
    } on SocketException catch (error) {
      throw DshTransportException('WebSocket connect failed: ${error.message}', error);
    } on HttpException catch (error) {
      throw DshTransportException('WebSocket connect failed: ${error.message}', error);
    } on HandshakeException catch (error) {
      throw DshTransportException('TLS handshake failed: ${error.message}', error);
    }
  }

  void close({bool force = false}) {
    _closed = true;
    _backgroundReads?.close();
    if (_ownsClient) _http.close(force: force);
  }

  Future<DshHttpResponse> _exchange(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    bool followRedirects = true,
    Duration? timeout,
  }) async {
    HttpClientRequest? request;
    StreamIterator<List<int>>? responseBody;
    TimeoutException? expired;

    Future<DshHttpResponse> run() async {
      request = await _http.openUrl(method, uri);
      final req = request!;
      final deadlineError = expired;
      if (deadlineError != null) {
        unawaited(req.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
        req.abort(deadlineError);
        throw deadlineError;
      }
      req.followRedirects = followRedirects;
      _applyHost(req.headers);
      if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie!.header);
      if (contentType != null) req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final response = await req.close();
      final setCookies = response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
      final builder = BytesBuilder(copy: false);
      final chunks = responseBody = StreamIterator(response);
      while (await chunks.moveNext()) {
        builder.add(chunks.current);
      }
      final type = response.headers.contentType;
      return DshHttpResponse(
        response.statusCode,
        type == null ? '' : '${type.primaryType}/${type.subType}'.toLowerCase(),
        builder.takeBytes(),
        setCookies: setCookies,
      );
    }

    try {
      return await run().timeout(timeout ?? requestTimeout);
    } on TimeoutException catch (error) {
      expired = error;
      unawaited(responseBody?.cancel().catchError((Object _) {}));
      request?.abort(error);
      throw DshTransportException('$method ${uri.path} timed out', error);
    } on SocketException catch (error) {
      throw DshTransportException('$method ${uri.path} failed: ${error.message}', error);
    } on HttpException catch (error) {
      throw DshTransportException('$method ${uri.path} failed: ${error.message}', error);
    } on HandshakeException catch (error) {
      throw DshTransportException('TLS handshake failed: ${error.message}', error);
    }
  }

  void _applyHost(HttpHeaders headers) {
    final override = hostHeader;
    if (override == null) return;
    final parsed = Uri.tryParse('http://$override');
    if (parsed == null || parsed.host.isEmpty) {
      throw ArgumentError.value(override, 'hostHeader', 'expected host or host:port');
    }
    headers.host = parsed.host;
    headers.port = parsed.hasPort ? parsed.port : 80;
  }

  static Uri _normalizeBase(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'baseUri', 'expected an http(s) URL');
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.port, path: path);
  }

  static String _authorityOf(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    return uri.port == defaultPort ? host : '$host:${uri.port}';
  }

  static DshCookie? _parseSetCookie(String raw, String authority) {
    final parts = raw.split(';');
    final first = parts.first;
    final eq = first.indexOf('=');
    if (eq <= 0) return null;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    DateTime? expiresAt;
    for (final attribute in parts.skip(1)) {
      final at = attribute.indexOf('=');
      final key = (at < 0 ? attribute : attribute.substring(0, at)).trim().toLowerCase();
      final attrValue = at < 0 ? '' : attribute.substring(at + 1).trim();
      if (key == 'max-age') {
        final seconds = int.tryParse(attrValue);
        if (seconds != null) expiresAt = DateTime.now().add(Duration(seconds: seconds));
      } else if (key == 'expires' && expiresAt == null) {
        try {
          expiresAt = HttpDate.parse(attrValue);
        } on Object {
          // Keep the cookie without an expiry rather than failing login.
        }
      }
    }
    return DshCookie(name: name, value: value, authority: authority, expiresAt: expiresAt);
  }
}
