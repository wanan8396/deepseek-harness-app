import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/ios/ios_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/lite_harness.dart';

const _channel = MethodChannel('dsh/ios-local');
const _key = ValueKey('ios-chat-key');
const _input = ValueKey('ios-chat-input');
const _start = ValueKey('ios-chat-start');
const _send = ValueKey('ios-chat-send');
const _cancel = ValueKey('ios-chat-cancel');
const _stop = ValueKey('ios-chat-stop');
const _refresh = ValueKey('ios-chat-refresh');
const _draft = ValueKey('ios-chat-draft');
const _status = ValueKey('ios-chat-status');
const _error = ValueKey('ios-chat-error');
const _userMessage = {'role': 'user', 'text': 'Hi from this device'};
const _savedMessage = {'role': 'assistant', 'text': 'This answer was saved.'};

Map<String, Object?> _snapshot(
  String state, {
  List<Map<String, String>> messages = const [],
  String draft = '',
  String? errorCode,
}) => {'state': state, 'messages': messages, 'draft': draft, 'errorCode': errorCode};

Finder _message(String text) => find.byWidgetPredicate((widget) => widget is SelectableText && widget.data == text);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, ValueKey<String> key) async {
  await tester.tap(find.byKey(key));
  await _frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    AppLocale.use(AppLocale.en);
    calls = [];
  });
  tearDown(() {
    AppLocale.use(AppLocale.zhCN);
    messenger.setMockMethodCallHandler(_channel, null);
  });

  void install(FutureOr<Object?> Function(MethodCall) reply) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  Future<void> mount(WidgetTester tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const IosChatPage()));
    await _frames(tester);
  }

  testWidgets('explicit start passes only the key, then send, poll and cancel use only chat payloads', (tester) async {
    final startReply = Completer<Object?>();
    final sendReply = Completer<Object?>();
    var active = false;
    install((call) => switch (call.method) {
      'chatSnapshot' => active
          ? _snapshot('running', messages: const [_userMessage], draft: 'Actual streamed response')
          : _snapshot('stopped'),
      'startChat' => startReply.future,
      'chatSend' => sendReply.future,
      'chatCancel' => _snapshot('ready', messages: const [_userMessage, _savedMessage]),
      _ => throw StateError(call.method),
    });
    await mount(tester);
    expect(calls.map((call) => call.method), ['chatSnapshot']);
    expect(tester.widget<TextField>(find.byKey(_key)).obscureText, isTrue);
    expect(tester.widget<TextField>(find.byKey(_key)).autofillHints, isNull);
    await tester.enterText(find.byKey(_key), ' malformed key ');
    await _tap(tester, _start);
    expect(calls, hasLength(1));
    expect(find.byKey(_error), findsOneWidget);

    await tester.enterText(find.byKey(_key), '  sk-widget-fixture  ');
    final keyInput = tester.widget<TextField>(find.byKey(_key)).controller!;
    await _tap(tester, _start);
    expect(calls.last.method, 'startChat');
    expect(calls.last.arguments, {'apiKey': 'sk-widget-fixture'});
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    expect(find.byKey(_input), findsNothing);
    startReply.complete(_snapshot('ready'));
    await _frames(tester);
    expect(keyInput.text, isEmpty);
    expect(find.byKey(_key), findsNothing);
    expect(tester.widget<Text>(find.byKey(_status)).data, contains('Model access is checked when you send'));

    await tester.enterText(find.byKey(_input), _userMessage['text']!);
    await _tap(tester, _send);
    expect(calls.last.arguments, {'text': _userMessage['text']});
    expect(tester.widget<IconButton>(find.byKey(_send)).onPressed, isNull);
    active = true;
    sendReply.complete(_snapshot('running', messages: const [_userMessage]));
    await _frames(tester);
    expect(find.byKey(_send), findsNothing);
    expect(tester.widget<TextField>(find.byKey(_input)).controller!.text, isEmpty);
    expect(find.byKey(_draft), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester);
    expect(tester.widget<SelectableText>(find.byKey(_draft)).data, 'Actual streamed response');
    expect(_message(_userMessage['text']!), findsOneWidget);

    await _tap(tester, _cancel);
    expect(calls.map((call) => call.method), ['chatSnapshot', 'startChat', 'chatSend', 'chatSnapshot', 'chatCancel']);
    expect(calls.where((call) => call.method == 'chatSnapshot' || call.method == 'chatCancel')
        .every((call) => call.arguments == null), isTrue);
    expect(find.byKey(_draft), findsNothing);
    expect(_message(_savedMessage['text']!), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, hasLength(5));
  });

  testWidgets('reattaches without a key; auth failure requires stop and another key to restore history', (tester) async {
    final messages = [_userMessage, _savedMessage];
    install((call) => switch (call.method) {
      'chatSnapshot' => _snapshot('ready', messages: messages, errorCode: 'IOS_CHAT_AUTH_FAILED'),
      'chatStop' => _snapshot('stopped'),
      'startChat' => _snapshot('ready', messages: messages),
      _ => throw StateError(call.method),
    });
    await mount(tester);
    expect(find.byKey(_key), findsNothing);
    expect(_message(_savedMessage['text']!), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_error)).data, contains('did not accept the API key'));
    expect(tester.widget<IconButton>(find.byKey(_send)).onPressed, isNull);

    await _tap(tester, _stop);
    expect(calls.last.arguments, isNull);
    expect(tester.widget<TextField>(find.byKey(_key)).controller!.text, isEmpty);
    expect(_message(_savedMessage['text']!), findsNothing);
    await tester.enterText(find.byKey(_key), 'sk-another-widget-fixture');
    await _tap(tester, _start);
    expect(_message(_userMessage['text']!), findsOneWidget);
    expect(_message(_savedMessage['text']!), findsOneWidget);
    expect(find.byKey(_error), findsNothing);
    expect(calls.map((call) => call.method), ['chatSnapshot', 'chatStop', 'startChat']);
  });

  testWidgets('keeps composing text when the engine rejects send in a status reply', (tester) async {
    install((call) => switch (call.method) {
      'chatSnapshot' => _snapshot('ready'),
      'chatSend' => _snapshot('ready', errorCode: 'IOS_CHAT_INPUT_INVALID'),
      _ => throw StateError(call.method),
    });
    await mount(tester);
    await tester.enterText(find.byKey(_input), _userMessage['text']!);
    await _tap(tester, _send);
    expect(tester.widget<TextField>(find.byKey(_input)).controller!.text, _userMessage['text']);
    expect(find.byKey(_error), findsOneWidget);
    expect(_message(_userMessage['text']!), findsNothing);
    expect(calls.map((call) => call.method), ['chatSnapshot', 'chatSend']);
  });

  testWidgets('redacts FlutterError data and refresh never repeats a failed start or carries a key', (tester) async {
    install((call) {
      if (call.method == 'startChat') {
        throw PlatformException(
          code: 'IOS_CHAT_TIMEOUT',
          message: 'secret-start-fixture',
          details: {'path': '/private/fixture'},
        );
      }
      if (call.method == 'chatSnapshot') return _snapshot('stopped');
      throw StateError(call.method);
    });
    await mount(tester);
    await tester.enterText(find.byKey(_key), 'sk-widget-fixture');
    await _tap(tester, _start);
    expect(tester.widget<Text>(find.byKey(_error)).data, 'The request timed out.');
    expect(find.textContaining('secret-start-fixture'), findsNothing);
    expect(find.textContaining('/private/fixture'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNull);
    await _tap(tester, _refresh);
    expect(find.byKey(_error), findsNothing);
    expect(calls.map((call) => call.method), ['chatSnapshot', 'startChat', 'chatSnapshot']);
    expect(calls.last.arguments, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_start)).onPressed, isNotNull);
  });

  testWidgets('ignores a stale running snapshot after cancel and an in-flight reply after unmount', (tester) async {
    final stale = Completer<Object?>();
    final reopening = Completer<Object?>();
    var reads = 0;
    install((call) => switch (call.method) {
      'chatSnapshot' => switch (++reads) {
        1 => _snapshot('running', draft: 'Current draft'),
        2 => stale.future,
        _ => reopening.future,
      },
      'chatCancel' => _snapshot('ready', messages: const [_userMessage]),
      _ => throw StateError(call.method),
    });
    await mount(tester);
    expect(find.byKey(_draft), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, hasLength(2));
    await _tap(tester, _cancel);
    expect(find.byKey(_cancel), findsNothing);
    stale.complete(_snapshot('running', draft: 'Stale draft'));
    await _frames(tester);
    expect(_message('Stale draft'), findsNothing);
    expect(_message(_userMessage['text']!), findsOneWidget);
    await _tap(tester, _refresh);
    await tester.pumpWidget(const SizedBox());
    reopening.complete(_snapshot('running', draft: 'Late draft'));
    await tester.pump(const Duration(seconds: 2));
    expect(calls.map((call) => call.method), ['chatSnapshot', 'chatSnapshot', 'chatCancel', 'chatSnapshot']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pauses polling while backgrounded and reads the latest on resume', (tester) async {
    var running = true;
    install((call) {
      expect(call.method, 'chatSnapshot');
      expect(call.arguments, isNull);
      return running ? _snapshot('running') : _snapshot('ready', messages: const [_savedMessage]);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    try {
      await mount(tester);
      expect(calls, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, hasLength(1));
      running = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(calls, hasLength(2));
      expect(_message(_savedMessage['text']!), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
}
