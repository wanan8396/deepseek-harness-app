import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real Android host Root, deliberately separate from PRoot's simulated uid 0.
class RootAccessStatus {
  const RootAccessStatus({
    this.native = false,
    this.phase = 'unavailable',
    this.uid,
    this.error,
    this.preferredRoot = false,
    this.mode = 'stopped',
    this.restartRequired = false,
  });

  final bool native;
  final String phase;
  final int? uid;
  final String? error;
  final bool preferredRoot;
  final String mode;
  final bool restartRequired;
  bool get granted => native && phase == 'ready' && uid == 0;
  bool get requesting => phase == 'requesting';

  factory RootAccessStatus.fromWire(Object? value) {
    if (value is! Map) return const RootAccessStatus();
    final native = value['native'] == true;
    final phase = value['state'];
    final uid = value['uid'];
    const states = {'off', 'requesting', 'ready', 'denied', 'unavailable', 'timeout', 'disconnected', 'error'};
    final valid = phase is String && states.contains(phase);
    final ready = native && phase == 'ready' && value['granted'] == true && uid is int && uid == 0;
    return RootAccessStatus(
      native: native,
      phase: ready ? 'ready' : (valid && phase != 'ready' ? phase : 'error'),
      uid: ready ? 0 : null,
      error: value['error'] is String ? value['error'] as String : null,
      preferredRoot: value['preferredRoot'] == true,
      mode: const {'root', 'proot', 'stopped', 'pending'}.contains(value['mode']) ? value['mode'] as String : 'stopped',
      restartRequired: value['restartRequired'] == true,
    );
  }
}

abstract class RootAccessDriver {
  Future<RootAccessStatus> status();
  Future<RootAccessStatus> request();
  Future<RootAccessStatus> disconnect();
}

class NativeRootAccessDriver implements RootAccessDriver {
  static const channel = MethodChannel('dsh/root');

  Future<RootAccessStatus> _call(String method) async {
    try {
      final result = await channel
          .invokeMethod<Object?>(method)
          .timeout(Duration(seconds: method == 'request' ? 35 : 5));
      return RootAccessStatus.fromWire(result);
    } on MissingPluginException {
      return const RootAccessStatus();
    }
  }

  @override
  Future<RootAccessStatus> status() => _call('status');
  @override
  Future<RootAccessStatus> request() => _call('request');
  @override
  Future<RootAccessStatus> disconnect() => _call('disconnect');
}

final rootAccessDriverProvider = Provider<RootAccessDriver>((ref) => NativeRootAccessDriver());
final rootAccessProvider = AsyncNotifierProvider.autoDispose<RootAccessController, RootAccessStatus>(
  RootAccessController.new,
);

class RootAccessController extends AsyncNotifier<RootAccessStatus> {
  int _epoch = 0;
  bool _changing = false;

  @override
  Future<RootAccessStatus> build() => ref.read(rootAccessDriverProvider).status();

  /// A status read never requests su. A resume during authorization must not
  /// overwrite its newer result or issue a second manager prompt.
  Future<void> refresh() async {
    if (_changing) return;
    final ticket = ++_epoch;
    try {
      final result = await ref.read(rootAccessDriverProvider).status();
      if (ref.mounted && ticket == _epoch) state = AsyncData(result);
    } catch (error, stack) {
      if (ref.mounted && ticket == _epoch) state = AsyncError(error, stack);
    }
  }

  Future<void> request() => _change(request: true);
  Future<void> disconnect() => _change(request: false);

  Future<void> _change({required bool request}) async {
    if (_changing || state.value?.requesting == true) return;
    _changing = true;
    final ticket = ++_epoch;
    final driver = ref.read(rootAccessDriverProvider);
    final previous = state.value;
    state = AsyncData(RootAccessStatus(
      native: previous?.native ?? true,
      phase: 'requesting',
      preferredRoot: previous?.preferredRoot ?? false,
      mode: previous?.mode ?? 'stopped',
      restartRequired: previous?.restartRequired ?? false,
    ));
    try {
      final result = await (request ? driver.request() : driver.disconnect());
      if (ref.mounted && ticket == _epoch) state = AsyncData(result);
    } catch (error, stack) {
      if (ref.mounted && ticket == _epoch) state = AsyncError(error, stack);
    } finally {
      _changing = false;
    }
  }
}
