import 'package:dsh_app/links/launcher_entries.dart';
import 'package:dsh_app/state/host_ref.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dsh/shortcuts');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LauncherEntry.parse', () {
    test('new and a recent local conversation', () {
      expect(LauncherEntry.parse({'kind': 'new'}), isA<NewChatEntry>());
      final chat = LauncherEntry.parse({'kind': 'chat', 'sessionId': 's1', 'host': HostRef.local.encode()});
      expect(chat, isA<OpenChatEntry>());
      chat as OpenChatEntry;
      expect(chat.sessionId, 's1');
      expect(chat.host, HostRef.local);
    });

    test('anything else is dropped', () {
      expect(LauncherEntry.parse(null), isNull);
      expect(LauncherEntry.parse({'kind': 'chat'}), isNull);
      expect(LauncherEntry.parse({'kind': 'chat', 'sessionId': ''}), isNull);
      expect(LauncherEntry.parse({'kind': 'delete-everything'}), isNull);
      expect(LauncherEntry.parse({'kind': 'voice'}), isNull);
      for(final host in [null, '', 'x', '{"kind":"ssh","id":"old"}', '{"kind":"relay","id":"old"}', '{"kind":"local","id":"other"}']) {
        expect(LauncherEntry.parse({'kind':'chat','sessionId':'s1','host':host}), isNull);
      }
    });
  });

  group('setRecent', () {
    late List<Object?> sent;
    late bool accept;

    setUp(() {
      sent = [];
      accept = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        if (call.method == 'setRecent') {
          sent.add(call.arguments);
          return accept;
        }
        return true;
      });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
    );

    const a = RecentShortcut(sessionId: 'a', title: '周报', host: HostRef.local);
    const b = RecentShortcut(sessionId: 'b', title: '修复登录', host: HostRef.local);

    test('publishes once per change', () async {
      final bridge = LauncherBridge();
      addTearDown(bridge.dispose);
      expect(await bridge.setRecent([a, b]), isTrue);
      expect(await bridge.setRecent([a, b]), isTrue);
      expect(sent, hasLength(1));
      expect(sent.single, {
        'items': [
          {'id': 'a', 'title': '周报', 'host': HostRef.local.encode()},
          {'id': 'b', 'title': '修复登录', 'host': HostRef.local.encode()},
        ],
      });
      await bridge.setRecent([b, a]);
      await bridge.setRecent(const []);
      expect(sent, hasLength(3));
    });

    test('tries again after the launcher refused (rate limit)', () async {
      final bridge = LauncherBridge();
      addTearDown(bridge.dispose);
      accept = false;
      expect(await bridge.setRecent([a]), isFalse);
      accept = true;
      expect(await bridge.setRecent([a]), isTrue);
      expect(sent, hasLength(2));
    });
  });

  test('without a native side, setRecent is a quiet no', () async {
    final bridge = LauncherBridge();
    addTearDown(bridge.dispose);
    expect(await bridge.setRecent(const []), isFalse);
  });

}
