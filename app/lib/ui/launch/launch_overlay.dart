import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launch/launch_state.dart';
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../theme/theme.dart';
import '../web/startup_cover.dart';

/// Keeps the original animated startup cover above the app until the native launch handoff and
/// the first usable screen are ready.
class LaunchLayer extends StatelessWidget {
  const LaunchLayer({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LaunchController?>(
    valueListenable: LaunchController.active,
    builder: (context, controller, _) {
      if (controller == null) return const SizedBox.shrink();
      final overlay = LaunchOverlay(key: ObjectKey(controller), controller: controller);
      return controller.snapshot.coldEngine ? _EngineWatch(controller: controller, child: overlay) : overlay;
    },
  );
}

class _EngineWatch extends ConsumerWidget {
  const _EngineWatch({required this.controller, required this.child});

  final LaunchController controller;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(localRuntimeProvider.select((s) => s.status.phase == RuntimePhase.running));
    if (running) SchedulerBinding.instance.addPostFrameCallback((_) => controller.engineReady());
    return child;
  }
}

/// The unmodified 40-frame startup GIF and its original light/dark surfaces.
class LaunchOverlay extends StatefulWidget {
  const LaunchOverlay({super.key, required this.controller, this.reduceMotion});

  final LaunchController controller;
  final bool? reduceMotion;
  static const skipKey = ValueKey('launch-skip');

  @override
  State<LaunchOverlay> createState() => _LaunchOverlayState();
}

class _LaunchOverlayState extends State<LaunchOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _shown = ReverseAnimation(CurvedAnimation(parent: _leave, curve: AppMotion.std));
  LaunchController get _c => widget.controller;

  bool get _systemReduced =>
      widget.reduceMotion ?? WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.firstFrame();
    });
  }

  @override
  void didUpdateWidget(LaunchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    final reduced = _systemReduced;
    if (_c.reduced != reduced) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.reduced = reduced;
      });
    }
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _leave.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (_c.phase == LaunchPhase.leaving && !_leave.isAnimating && !_leave.isCompleted) {
      if (_systemReduced) {
        _c.gone();
      } else {
        unawaited(_leave.forward().then((_) => _c.gone()));
      }
    }
    if (_c.reduced != _systemReduced) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.reduced = _systemReduced;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_c.phase == LaunchPhase.gone) return const SizedBox.shrink();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(_c.snapshot.dark ? Brightness.dark : Brightness.light),
      child: IgnorePointer(
        ignoring: _c.phase == LaunchPhase.leaving,
        child: FadeTransition(
          opacity: _shown,
          child: GestureDetector(
            key: LaunchOverlay.skipKey,
            behavior: HitTestBehavior.opaque,
            onTap: _c.skip,
            child: Material(
              color: StartupCover.backgroundOf(context),
              child: const StartupStage(key: ValueKey('lite-launch-stage')),
            ),
          ),
        ),
      ),
    );
  }
}
