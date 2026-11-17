import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/notify_state.dart';
import 'package:dsh_app/state/selection_state.dart';
import 'package:dsh_app/state/host_ref.dart';
import 'package:dsh_app/state/web_connection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notify/support.dart';

class _Destination extends WebConnectionController {
  @override
  WebConnectionState build() => const WebConnectionState(loaded: true);
  void select(WebConnectionMode mode) => state = WebConnectionState(loaded: true, mode: mode);
}

class _Local extends LocalConnectionController {
  _Local(this.connection);
  final HostConnection connection;
  @override
  Future<HostConnection?> build() async => connection;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ordinary Lite notifications never initialize the extra Bot filter or session feed', () async {
    SharedPreferences.setMockInitialValues({});
    final channel = FakeNotifyChannel();
    final source = FakeAlertSource()..sessions = [session('s1', title: 'official notification')];
    final connection = fakeHostConnection();
    final destination = _Destination();
    final container = ProviderContainer(
      overrides: [
        webConnectionProvider.overrideWith(() => destination),
        notifyChannelProvider.overrideWithValue(channel),
        alertSourceFactoryProvider.overrideWithValue((_) => source),
        alertTimingProvider.overrideWithValue((announce: Duration.zero, reconcile: const Duration(milliseconds: 30))),
        localConnectionProvider.overrideWith(() => _Local(connection)),
        activeConnectionProvider.overrideWithValue(AsyncData(connection)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(chatAlertsProvider, (_, _) {});
    addTearDown(sub.close);
    await settle();
    container.read(appForegroundProvider.notifier).set(false);
    await settle();
    source.emit(approval('official-request', 's1'));
    await settle();
    expect(channel.shown, hasLength(1));
    expect(channel.shown.single.title, 'official notification');
    expect(container.exists(activeConnectionProvider), isFalse);
    container.read(chatAlertsProvider.notifier).open(HostRef.local, 's1');
    expect(container.read(currentSessionProvider), 's1');
    // Keep the following deliveries observable after exercising the real tap owner.
    container.read(currentSessionProvider.notifier).select(null);

    destination.select(WebConnectionMode.computer);
    await settle();
    expect(container.read(chatAlertsProvider), isNull);
    expect(channel.cancelledAll, greaterThan(0));
    source.emit(approval('retired-local-request', 's1'));
    await settle();
    expect(channel.shown, hasLength(1), reason: 'retired local tracker cannot notify over a computer page');

    destination.select(WebConnectionMode.local);
    await settle();
    source.emit(approval('fresh-local-request', 's1'));
    await settle();
    expect(channel.shown, hasLength(2));
  });
}
