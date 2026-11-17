import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/ui/web/local_settings_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/settings-document');
  const owner = RuntimeStatus(
    phase: RuntimePhase.running,
    baseUrl: 'http://127.0.0.1:41234/',
    token: 'synthetic',
    generation: 3,
  );
  const path = '/root/.dsh/profiles/web/cordis.patch.yml';
  late Map<Object?, Object?> reply;
  late List<MethodCall> calls;
  late LocalSettingsDocuments documents;
  setUp(() {
    calls = [];
    reply = {
      'generation': 3,
      'text': '[]\n',
      'displayName': 'cordis.patch.yml',
      'profile': 'web',
      'relativeDisplayPath': path,
    };
    documents = LocalSettingsDocuments(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getStatus') {
        return {'phase': 'running', 'baseUrl': owner.baseUrl, 'token': owner.token, 'generation': 3};
      }
      return reply;
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('status decodes the native launch generation and accepts old missing identity', () async {
    expect((await documents.status()).generation, 3);
    expect(RuntimeStatus.fromMap({'phase': 'running'}).generation, isNull);
  });
  test('read is pathless and accepts only the matching profile response', () async {
    final value = await documents.read(owner);
    expect(value.text, '[]\n');
    expect(value.path, path);
    expect(calls.single.method, 'readLocalSettingsDocument');
    expect(calls.single.arguments, {'baseUrl': 'http://127.0.0.1:41234/', 'token': 'synthetic'});
  });
  test('foreign origins and runtimes without identity are excluded', () {
    expect(LocalSettingsDocuments.canRead(owner, Uri.parse('http://127.0.0.1:41234/')), isTrue);
    for (final url in [
      'https://127.0.0.1:41234/',
      'http://127.0.0.1:41235/',
      'http://localhost:41234/',
      'http://example.test/',
    ]) {
      expect(LocalSettingsDocuments.canRead(owner, Uri.parse(url)), isFalse);
    }
    expect(
      LocalSettingsDocuments.canRead(
        const RuntimeStatus(phase: RuntimePhase.running, baseUrl: 'http://127.0.0.1:41234/', token: 'fixture'),
        Uri.parse(owner.baseUrl!),
      ),
      isFalse,
    );
  });
  test('generation, token, mode and phase changes retire ownership', () {
    for (final next in [
      const RuntimeStatus(
        phase: RuntimePhase.running,
        baseUrl: 'http://127.0.0.1:41234/',
        token: 'synthetic',
        generation: 4,
      ),
      const RuntimeStatus(
        phase: RuntimePhase.running,
        baseUrl: 'http://127.0.0.1:41234/',
        token: 'other',
        generation: 3,
      ),
      const RuntimeStatus(
        phase: RuntimePhase.running,
        baseUrl: 'http://127.0.0.1:41234/',
        token: 'synthetic',
        generation: 3,
        mode: EngineMode.safe,
      ),
      const RuntimeStatus(
        phase: RuntimePhase.stopping,
        baseUrl: 'http://127.0.0.1:41234/',
        token: 'synthetic',
        generation: 3,
      ),
    ]) {
      expect(LocalSettingsDocuments.sameRun(owner, next), isFalse);
    }
  });
  test('stale generation and unexpected paths never become a document', () async {
    for (final change in [
      {'generation': 2},
      {'relativeDisplayPath': '/sdcard/secret'},
      {'profile': 'other'},
      {'text': 5},
      {'text': 'x' * (512 * 1024 + 1)},
    ]) {
      final before = Map<Object?, Object?>.of(reply);
      reply.addAll(change);
      await expectLater(documents.read(owner), throwsFormatException);
      reply = before;
    }
  });
  test('stopped owner never starts a file read', () async {
    await expectLater(documents.read(const RuntimeStatus(phase: RuntimePhase.installed)), throwsFormatException);
    expect(calls, isEmpty);
  });
  test('safe profile cannot return normal configuration', () async {
    const safe = RuntimeStatus(
      phase: RuntimePhase.running,
      baseUrl: 'http://127.0.0.1:41234/',
      token: 'synthetic',
      generation: 3,
      mode: EngineMode.safe,
    );
    await expectLater(documents.read(safe), throwsFormatException);
    reply['profile'] = 'dsh-app-safe';
    reply['relativeDisplayPath'] = '/var/lib/dsh-app/safe-mode/home/profiles/dsh-app-safe/cordis.patch.yml';
    expect((await documents.read(safe)).text, '[]\n');
  });
  testWidgets('viewer is read only with no editable, clipboard or export controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: AppLocale.zhCN,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: AppLocale.supported,
        home: LocalSettingsDocumentPage(
          document: const LocalSettingsDocument(text: 'synthetic-data-only', path: path),
          owner: owner,
          documents: documents,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('配置文件'), findsOneWidget);
    expect(find.textContaining('只读'), findsOneWidget);
    expect(find.text('synthetic-data-only'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
