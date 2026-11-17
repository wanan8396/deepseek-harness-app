// Native startup-window handoff for the phone shell. The visible layer itself is the original
// 40-frame GIF in ui/web/startup_cover.dart; this controller only coordinates native reveal,
// skip, local-engine readiness and the final fade.

import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueNotifier;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class LaunchSnapshot {
  const LaunchSnapshot({required this.systemSplash, required this.dark, this.coldEngine = false});

  /// Android 12+ keeps its own splash over the first Flutter frame until `reveal`.
  final bool systemSplash;

  /// The startup window and the GIF surface use the system brightness.
  final bool dark;

  /// The local engine was stopped and launch startup is starting it now.
  final bool coldEngine;

  static Future<LaunchSnapshot?> fromMap(Map<Object?, Object?>? raw) async {
    if (raw == null || raw['active'] != true) return null;
    return LaunchSnapshot(
      systemSplash: raw['systemSplash'] == true,
      dark: raw['dark'] == true,
      coldEngine: raw['coldEngine'] == true,
    );
  }
}

/// The native `dsh/launch` startup handoff channel.
class LaunchChannel {
  const LaunchChannel([this.channel = const MethodChannel('dsh/launch')]);

  final MethodChannel channel;

  Future<Map<Object?, Object?>?> begin() => _call<Map<Object?, Object?>>('begin');
  Future<bool> reveal() async => await _call<bool>('reveal') ?? false;
  Future<void> mark(String name) => _call<void>('mark', {'name': name});
  Future<void> done() => _call<void>('done');

  void listen(void Function({bool removed}) onSystemSplash) {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'systemSplash') return;
      final raw = call.arguments;
      onSystemSplash(removed: raw is Map && raw['removed'] == true);
    });
  }

  void stopListening() => channel.setMethodCallHandler(null);

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

enum LaunchPhase { cover, playing, leaving, gone }

/// One cold-start native handoff. It owns no custom media, theme choice or alternate launch mode.
class LaunchController extends ChangeNotifier {
  LaunchController({
    required this.snapshot,
    this.channel = const LaunchChannel(),
    this.handOverWait = const Duration(milliseconds: 700),
  });

  static final active = ValueNotifier<LaunchController?>(null);
  static const coverMotionDuration = Duration(milliseconds: 1360);
  static const readyWait = Duration(milliseconds: 200);

  final LaunchSnapshot snapshot;
  final LaunchChannel channel;
  final Duration handOverWait;

  LaunchPhase _phase = LaunchPhase.cover;
  LaunchPhase get phase => _phase;
  bool _ready = false;
  bool _firstFrame = false;
  bool _handingOver = false;
  Timer? _handOverTimer;
  Timer? _motionTimer;
  bool _waitsForEngine = true;
  bool _engineReady = false;
  bool _motionDone = false;
  bool _reduced = false;
  bool _skipped = false;

  static Future<LaunchController?> begin({LaunchChannel channel = const LaunchChannel()}) async {
    try {
      final snapshot = await LaunchSnapshot.fromMap(await channel.begin());
      if (snapshot == null) return null;
      final controller = LaunchController(snapshot: snapshot, channel: channel);
      channel.listen(controller.handOver);
      active.value = controller;
      return controller;
    } catch (_) {
      unawaited(channel.done());
      return null;
    }
  }

  void firstFrame() {
    if (_firstFrame) return;
    _firstFrame = true;
    unawaited(channel.mark('firstFrame'));
    if (!snapshot.systemSplash) {
      _play();
    } else {
      _handOverTimer = Timer(handOverWait, _play);
    }
  }

  Future<void> handOver({bool removed = false}) async {
    if (_handingOver || _phase == LaunchPhase.gone) return;
    _handingOver = true;
    _handOverTimer?.cancel();
    if (removed) return _play();
    await SchedulerBinding.instance.endOfFrame;
    SchedulerBinding.instance.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;
    await channel.reveal();
    unawaited(channel.mark('handedOver'));
    _play();
  }

  /// The shell has reached its first page. A cold local start holds the GIF only until the engine
  /// answers or the original cover interval has elapsed; a warm start leaves as soon as ready.
  void ready({bool waitsForEngine = true}) {
    if (_ready) return;
    _ready = true;
    _waitsForEngine = waitsForEngine;
    unawaited(channel.mark('ready'));
    if (_phase == LaunchPhase.playing) {
      _leaveIfDone();
    } else if (_phase == LaunchPhase.cover && _firstFrame && !_handingOver && !_coldHold) {
      _handOverTimer?.cancel();
      _handOverTimer = Timer(readyWait, _play);
    }
  }

  bool get _coldHold =>
      !_skipped && !_reduced && snapshot.coldEngine && _waitsForEngine && !_engineReady;

  bool get holds => _coldHold && !_motionDone;

  void skip() {
    if (_skipped || _phase == LaunchPhase.leaving || _phase == LaunchPhase.gone) return;
    _skipped = true;
    _motionTimer?.cancel();
    unawaited(channel.mark('skipped'));
    if (_phase != LaunchPhase.playing) return;
    _phase = LaunchPhase.leaving;
    notifyListeners();
  }

  void engineReady() {
    if (_engineReady) return;
    _engineReady = true;
    _motionTimer?.cancel();
    _motionDone = true;
    unawaited(channel.mark('engine'));
    _leaveIfDone();
  }

  void motionDone() {
    if (_motionDone) return;
    _motionDone = true;
    _leaveIfDone();
  }

  bool get reduced => _reduced;
  set reduced(bool value) {
    if (_reduced == value) return;
    _reduced = value;
    if (value) {
      _motionTimer?.cancel();
      _motionDone = true;
    }
    _leaveIfDone();
  }

  void _leaveIfDone() {
    if (_phase != LaunchPhase.playing || !_ready || holds) return;
    _phase = LaunchPhase.leaving;
    notifyListeners();
  }

  void _play() {
    _handOverTimer?.cancel();
    if (_phase != LaunchPhase.cover) return;
    _phase = _skipped ? LaunchPhase.leaving : LaunchPhase.playing;
    if (_phase == LaunchPhase.playing && _coldHold) {
      _motionTimer = Timer(coverMotionDuration, motionDone);
    }
    notifyListeners();
    _leaveIfDone();
  }

  void gone() {
    if (_phase == LaunchPhase.gone) return;
    _phase = LaunchPhase.gone;
    _handOverTimer?.cancel();
    _motionTimer?.cancel();
    channel.stopListening();
    unawaited(channel.done());
    if (identical(active.value, this)) active.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_phase != LaunchPhase.gone) {
      _phase = LaunchPhase.gone;
      _handOverTimer?.cancel();
      _motionTimer?.cancel();
      channel.stopListening();
      unawaited(channel.done());
      if (identical(active.value, this)) active.value = null;
    }
    super.dispose();
  }
}
