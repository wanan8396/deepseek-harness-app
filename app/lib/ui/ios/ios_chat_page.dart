import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';

enum _ChatState { stopped, ready, running }

enum _ChatError implements Exception {
  keyInvalid,
  inputInvalid,
  busy,
  auth,
  rateLimited,
  network,
  model,
  storage,
  timeout,
  unavailable,
  stopped,
  start,
  send,
  cancel,
  stop,
  responseLimit,
  protocol;

  static _ChatError fromCode(Object? code) => switch (code) {
    'IOS_CHAT_KEY_INVALID' => keyInvalid,
    'IOS_CHAT_INPUT_INVALID' => inputInvalid,
    'IOS_CHAT_BUSY' => busy,
    'IOS_CHAT_AUTH_FAILED' => auth,
    'IOS_CHAT_RATE_LIMITED' => rateLimited,
    'IOS_CHAT_NETWORK_FAILED' => network,
    'IOS_CHAT_MODEL_FAILED' => model,
    'IOS_CHAT_STORAGE_FAILED' => storage,
    'IOS_CHAT_TIMEOUT' || 'IOS_CHAT_REQUEST_EXPIRED' => timeout,
    'IOS_CHAT_UNAVAILABLE' => unavailable,
    'IOS_CHAT_NOT_STARTED' || 'IOS_CHAT_STOPPED' => stopped,
    'IOS_CHAT_BOOT_FAILED' || 'IOS_CHAT_START_FAILED' => start,
    'IOS_CHAT_SEND_FAILED' => send,
    'IOS_CHAT_CANCEL_FAILED' => cancel,
    'IOS_CHAT_STOP_FAILED' => stop,
    'IOS_CHAT_RESPONSE_LIMIT' => responseLimit,
    _ => protocol,
  };

  String label(L10n l10n) => switch (this) {
    _ChatError.keyInvalid => l10n.iosChatKeyInvalid,
    _ChatError.inputInvalid => l10n.iosChatInputInvalid,
    _ChatError.busy => l10n.iosChatBusyError,
    _ChatError.auth => l10n.iosChatAuthError,
    _ChatError.rateLimited => l10n.iosChatRateLimitError,
    _ChatError.network => l10n.iosChatNetworkError,
    _ChatError.model => l10n.iosChatModelError,
    _ChatError.storage => l10n.iosChatStorageError,
    _ChatError.timeout => l10n.iosChatTimeoutError,
    _ChatError.unavailable => l10n.iosChatUnavailableError,
    _ChatError.stopped => l10n.iosChatStopped,
    _ChatError.start => l10n.iosChatStartupError,
    _ChatError.send => l10n.iosChatSendError,
    _ChatError.cancel => l10n.iosChatCancelError,
    _ChatError.stop => l10n.iosChatStopError,
    _ChatError.responseLimit => l10n.iosChatResponseLimitError,
    _ChatError.protocol => l10n.iosChatProtocolError,
  };
}

typedef _ChatMessage = ({bool isUser, String text});

class _ChatSnapshot {
  const _ChatSnapshot(this.state, this.messages, this.draft, this.error);

  factory _ChatSnapshot.fromReply(Object? reply) {
    if (reply is! Map || !reply.containsKey('errorCode')) throw _ChatError.protocol;
    final state = switch (reply['state']) {
      'stopped' => _ChatState.stopped,
      'ready' => _ChatState.ready,
      'running' => _ChatState.running,
      _ => throw _ChatError.protocol,
    };
    final rawMessages = reply['messages'];
    final draft = reply['draft'];
    final error = reply['errorCode'];
    if (rawMessages is! List || draft is! String || (error != null && error is! String)) {
      throw _ChatError.protocol;
    }
    final messages = <_ChatMessage>[];
    for (final message in rawMessages) {
      if (message is! Map || message['text'] is! String) throw _ChatError.protocol;
      final isUser = switch (message['role']) {
        'user' => true,
        'assistant' => false,
        _ => throw _ChatError.protocol,
      };
      messages.add((isUser: isUser, text: message['text'] as String));
    }
    return _ChatSnapshot(state, messages, draft, error == null ? null : _ChatError.fromCode(error));
  }

  final _ChatState state;
  final List<_ChatMessage> messages;
  final String draft;
  final _ChatError? error;
}

/// The platform channel owns the on-device engine; a route only observes it.
class IosChatPage extends StatefulWidget {
  const IosChatPage({super.key});

  @override
  State<IosChatPage> createState() => _IosChatPageState();
}

class _IosChatPageState extends State<IosChatPage> {
  static const _channel = MethodChannel('dsh/ios-local');
  static const _requestTimeout = Duration(seconds: 30);
  static const _pollInterval = Duration(milliseconds: 400);
  // Bound automatic observation, not the engine turn. Refresh resumes polling.
  static const _pollBudget = 750;
  static final _validKey = RegExp(r'^[!-~]{1,1024}$');

  final _keyInput = TextEditingController();
  final _messageInput = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  _ChatSnapshot? _snapshot;
  _ChatError? _requestError;
  Timer? _poll;
  bool _foreground = true;
  bool _reading = false;
  bool _needsRefresh = false;
  String? _command;
  int _revision = 0;
  int _pollsLeft = _pollBudget;

  bool get _started => _snapshot != null && _snapshot!.state != _ChatState.stopped;
  bool get _running => _snapshot?.state == _ChatState.running;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      if (_foreground) {
        unawaited(_refresh());
      } else {
        _poll?.cancel();
      }
    });
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    _keyInput.dispose();
    _messageInput.dispose();
    super.dispose();
  }

  Future<_ChatSnapshot> _invoke(String method, [Map<String, String>? arguments]) async {
    try {
      final reply = await _channel.invokeMethod<Object?>(method, arguments).timeout(_requestTimeout);
      return _ChatSnapshot.fromReply(reply);
    } on PlatformException catch (error) {
      // Only map the fixed code; native messages/details are never displayed or logged.
      throw _ChatError.fromCode(error.code);
    } on MissingPluginException {
      throw _ChatError.unavailable;
    } on TimeoutException {
      throw _ChatError.timeout;
    } on FormatException {
      throw _ChatError.protocol;
    }
  }

  void _applySnapshot(_ChatSnapshot snapshot) {
    if (snapshot.state == _ChatState.stopped) {
      if (_started) _messageInput.clear();
    } else if (_keyInput.text.isNotEmpty) {
      _keyInput.clear();
    }
    _snapshot = snapshot;
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (mounted && _foreground && _running && !_reading && _command == null && !_needsRefresh && _pollsLeft > 0) {
      _poll = Timer(_pollInterval, () => unawaited(_refresh(automatic: true)));
    }
  }

  Future<void> _refresh({bool automatic = false}) async {
    if (!mounted || !_foreground || _reading || _command != null) return;
    _poll?.cancel();
    final revision = _revision;
    // Unlike mutations, status reads do not need to disable Cancel or Stop.
    setState(() {
      _reading = true;
      _pollsLeft = automatic ? _pollsLeft - 1 : _pollBudget;
    });
    try {
      final snapshot = await _invoke('chatSnapshot');
      if (!mounted || revision != _revision) return;
      setState(() {
        _applySnapshot(snapshot);
        if (!automatic) {
          _requestError = null;
          _needsRefresh = false;
        }
      });
    } on _ChatError catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _requestError = error;
        _needsRefresh = true;
      });
    } finally {
      if (mounted) {
        setState(() => _reading = false);
        _schedulePoll();
      }
    }
  }

  Future<void> _mutate(String method, [Map<String, String>? arguments]) async {
    if (!mounted || _command != null) return;
    _poll?.cancel();
    // A snapshot already on the wire is older than this mutation (native FIFO).
    _revision++;
    setState(() {
      _command = method;
      _requestError = null;
      _pollsLeft = _pollBudget;
    });
    try {
      final snapshot = await _invoke(method, arguments);
      if (!mounted) return;
      if (method == 'startChat' && snapshot.state == _ChatState.stopped) throw _ChatError.protocol;
      if (method == 'chatStop' && snapshot.state != _ChatState.stopped) throw _ChatError.protocol;
      if (method == 'chatSend' && snapshot.state == _ChatState.stopped) throw _ChatError.stopped;
      final sent = method == 'chatSend' && _sendAccepted(snapshot, arguments?['text']);
      setState(() {
        _applySnapshot(snapshot);
        _needsRefresh = false;
        if (sent) _messageInput.clear();
      });
    } on _ChatError catch (error) {
      if (!mounted) return;
      setState(() {
        _requestError = error;
        // With an uncertain acknowledgement, read status before another start/send.
        _needsRefresh = error != _ChatError.keyInvalid && error != _ChatError.inputInvalid;
      });
    } finally {
      if (mounted) {
        setState(() => _command = null);
        _schedulePoll();
      }
    }
  }

  bool _sendAccepted(_ChatSnapshot snapshot, String? text) {
    // Storage failure, busy and invalid input may be returned as snapshots
    // rather than channel exceptions. Other errors may be fast model failures.
    switch (snapshot.error) {
      case null:
        return true;
      case _ChatError.auth || _ChatError.rateLimited || _ChatError.network || _ChatError.model || _ChatError.timeout:
        final index = snapshot.messages.lastIndexWhere((message) => message.isUser);
        return index >= 0 && snapshot.messages[index].text == text;
      default:
        return false;
    }
  }

  void _start() {
    if (_command != null || _needsRefresh || _snapshot?.state != _ChatState.stopped) return;
    final key = _keyInput.text.trim();
    if (!_validKey.hasMatch(key)) {
      setState(() => _requestError = _ChatError.keyInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    unawaited(_mutate('startChat', {'apiKey': key}));
  }

  void _send() {
    if (_command != null || _needsRefresh || !_started || _running || _snapshot?.error == _ChatError.auth) return;
    final text = _messageInput.text;
    if (text.trim().isEmpty || utf8.encode(text).length > 8192) {
      setState(() => _requestError = _ChatError.inputInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    unawaited(_mutate('chatSend', {'text': text}));
  }

  Widget _status(L10n l10n) {
    final theme = Theme.of(context);
    final label = switch (_command) {
      'startChat' => l10n.iosChatStarting,
      'chatSend' => l10n.iosChatSending,
      'chatCancel' => l10n.iosChatCancelling,
      'chatStop' => l10n.iosChatStopping,
      _ => switch (_snapshot?.state) {
        null => _reading ? l10n.iosLocalChecking : l10n.iosChatStateUnknown,
        _ChatState.stopped => l10n.iosChatStopped,
        _ChatState.ready => l10n.iosChatReady,
        _ChatState.running => l10n.iosChatRunning,
      },
    };
    final error = _requestError ?? _snapshot?.error;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, key: const ValueKey('ios-chat-status'), style: theme.textTheme.bodyMedium),
          if (error != null)
            Text(
              error.label(l10n),
              key: const ValueKey('ios-chat-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (_needsRefresh)
            Text(l10n.iosChatRefreshNeeded, style: theme.textTheme.bodySmall)
          else if (_running && _pollsLeft == 0 && !_reading)
            Text(l10n.iosChatPollingPaused, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _setup(L10n l10n) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _status(l10n),
      const SizedBox(height: 12),
      Text(l10n.iosChatScope),
      const SizedBox(height: 8),
      Text(l10n.iosChatKeyHelp),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('ios-chat-key'),
        controller: _keyInput,
        enabled: _command == null,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autofillHints: null,
        decoration: InputDecoration(labelText: l10n.iosChatKeyLabel),
        onSubmitted: (_) => _start(),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('ios-chat-start'),
        onPressed: _command == null && !_needsRefresh && _snapshot?.state == _ChatState.stopped ? _start : null,
        child: Text(l10n.iosChatStart),
      ),
    ],
  );

  Widget _message(L10n l10n, _ChatMessage message, {bool draft = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.isUser ? l10n.iosChatUser : l10n.iosChatAssistant, style: theme.textTheme.labelLarge),
          SelectableText(message.text, key: draft ? const ValueKey('ios-chat-draft') : null),
        ],
      ),
    );
  }

  Widget _conversation(L10n l10n, _ChatSnapshot snapshot, {required bool compact}) {
    final draft = _running ? snapshot.draft : '';
    final count = snapshot.messages.length;
    final draftCount = draft.isEmpty ? 0 : 1;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: 1 + draftCount + count,
            itemBuilder: (context, index) {
              if (index == 0) return _status(l10n);
              if (draftCount == 1 && index == 1) return _message(l10n, (isUser: false, text: draft), draft: true);
              return _message(l10n, snapshot.messages[count - index + draftCount]);
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ios-chat-input'),
                  controller: _messageInput,
                  enabled: _command == null && !_running,
                  minLines: 1,
                  maxLines: compact ? 1 : 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: l10n.iosChatMessageHint),
                ),
              ),
              const SizedBox(width: 8),
              if (_running)
                IconButton(
                  key: const ValueKey('ios-chat-cancel'),
                  tooltip: l10n.iosChatCancel,
                  onPressed: _command == null ? () => unawaited(_mutate('chatCancel')) : null,
                  icon: const Icon(AppIcons.stopGenerating),
                )
              else
                IconButton.filled(
                  key: const ValueKey('ios-chat-send'),
                  tooltip: l10n.iosChatSend,
                  onPressed: _command == null && !_needsRefresh && snapshot.error != _ChatError.auth ? _send : null,
                  icon: const Icon(AppIcons.send),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = _snapshot;
    return Scaffold(
      key: const ValueKey('ios-chat-page'),
      appBar: AppBar(
        title: Text(l10n.iosChatOpen),
        actions: [
          IconButton(
            key: const ValueKey('ios-chat-refresh'),
            tooltip: l10n.iosLocalRefresh,
            onPressed: _command == null && !_reading ? () => unawaited(_refresh()) : null,
            icon: const Icon(AppIcons.refresh),
          ),
          if (_started)
            IconButton(
              key: const ValueKey('ios-chat-stop'),
              tooltip: l10n.iosChatStop,
              onPressed: _command == null ? () => unawaited(_mutate('chatStop')) : null,
              icon: const Icon(AppIcons.stop),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: snapshot == null || snapshot.state == _ChatState.stopped
                ? _setup(l10n)
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        _conversation(l10n, snapshot, compact: constraints.maxHeight < 240),
                  ),
          ),
        ),
      ),
    );
  }
}
