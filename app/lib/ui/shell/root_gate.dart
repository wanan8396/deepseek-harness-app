import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/diagnostics_publish.dart';
import '../../launch/launch_state.dart';
import '../../runtime/local_footprint.dart';
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../../state/notify_state.dart';
import '../../state/onboarding_state.dart';
import '../../state/settings_state.dart';
import '../../state/web_connection_state.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/setup_progress.dart';
import '../settings/connect_computer_page.dart';
import '../web/mode_home.dart';
import '../web/startup_cover.dart';

/// Restores phone setup only; webpage sign-in and model settings belong to DSH.
OnboardingStep? initialOnboardingStep({
  required RuntimeStatus status,
  required OnboardingPrefs prefs,
  bool useComputerWeb = false,
}) {
  if (useComputerWeb) return null;
  final installedCurrent = status.installedVersion != null && status.installedVersion == status.bundledVersion;
  final needsRuntime = switch (status.phase) {
    RuntimePhase.notInstalled || RuntimePhase.installing => true,
    RuntimePhase.error => !installedCurrent,
    _ => false,
  };
  if (prefs.setupStep case final resume? when installedCurrent || status.installedVersion == null) {
    return switch (resume) {
      // Saved setup from older installs resumes at the retained permissions step.
      SetupStep.appearance || SetupStep.access => OnboardingStep.access,
      _ => needsRuntime ? OnboardingStep.finishing : null,
    };
  }
  if (needsRuntime) {
    if (status.phase == RuntimePhase.installing || !runtimeStepAsks(status)) return OnboardingStep.runtime;
    return prefs.welcomeSeen ? OnboardingStep.runtime : OnboardingStep.welcome;
  }
  return null;
}

bool runtimeStepAsks(RuntimeStatus status) =>
    status.installedVersion == null && status.phase != RuntimePhase.installing;

/// Computer pages never mount the phone's runtime setup or local integrations.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key, this.home});

  @visibleForTesting
  final Widget? home;

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _computerReady = false;

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(webConnectionProvider);
    if (!connection.loaded) return const _Splash();
    if (connection.mode == WebConnectionMode.computer) {
      if (!_computerReady) {
        _computerReady = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(webConnectionProvider).mode == WebConnectionMode.computer) {
            LaunchController.active.value?.ready(waitsForEngine: false);
          }
        });
      }
      return widget.home ?? const ModeHome();
    }
    _computerReady = false;
    return _LocalRootGate(home: widget.home);
  }
}

/// The local webpage's waiting stage owns startup after phone setup is complete.
class _LocalRootGate extends ConsumerStatefulWidget {
  const _LocalRootGate({this.home});

  final Widget? home;

  @override
  ConsumerState<_LocalRootGate> createState() => _LocalRootGateState();
}

class _LocalRootGateState extends ConsumerState<_LocalRootGate> {
  bool _decided = false;
  bool _publishedDiagnostics = false;
  bool _launchReady = false;
  OnboardingStep? _step;
  bool _chooseRuntime = false;
  bool _pickingComputer = false;
  bool _beside = false;

  OnboardingPrefsController get _prefs => ref.read(onboardingPrefsProvider.notifier);

  void _goTo(OnboardingStep? step) {
    if (mounted) setState(() => _step = step);
  }

  void _startUnpack() {
    ref.read(installEtaProvider);
    unawaited(ref.read(runtimeInstallProvider.notifier).install());
    // Prime Android's installation notification channels while setup is visible.
    unawaited(ref.read(notifyChannelProvider).status().then<void>((_) {}, onError: (_) {}));
  }

  void _chooseLocal() {
    _beside = true;
    unawaited(_prefs.setSetupStep(SetupStep.access));
    _startUnpack();
    _goTo(OnboardingStep.access);
  }

  void _afterAccess() {
    if (ref.read(setupRuntimeProvider) != SetupRuntime.ready) {
      unawaited(_prefs.setSetupStep(SetupStep.finishing));
      _goTo(OnboardingStep.finishing);
      return;
    }
    _afterFinishing();
  }

  void _afterFinishing() {
    _beside = false;
    unawaited(_prefs.setSetupStep(null));
    _goTo(null);
  }

  Future<void> _useComputerWeb() async {
    if (_pickingComputer) return;
    _pickingComputer = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectComputerPage()));
    } finally {
      _pickingComputer = false;
    }
    // RootGate disposes this local owner. Its saved setup survives a return.
  }

  void _publishDiagnostics() {
    if (_publishedDiagnostics || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _publishedDiagnostics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(diagnosticsPublisherProvider).publish());
    });
  }

  void _resumeBeside(SetupStep? saved, RuntimeStatus status) {
    if (saved == null) return;
    _beside = _step == OnboardingStep.access || _step == OnboardingStep.finishing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_beside) return unawaited(_prefs.setSetupStep(null));
      if (setupRuntimeOf(status) == SetupRuntime.absent) _startUnpack();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsLoaded = ref.watch(settingsProvider.select((settings) => settings.loaded));
    final runtime = ref.watch(localRuntimeProvider.select((s) => (status: s.status, loaded: s.loaded)));
    final prefs = ref.watch(onboardingPrefsProvider);
    ref.listen(localRuntimeProvider.select((s) => s.status.phase), (previous, next) {
      if (_decided && _step == null && next == RuntimePhase.notInstalled && previous != RuntimePhase.notInstalled) {
        _chooseRuntime = false;
        _goTo(OnboardingStep.runtime);
      }
      if (next == RuntimePhase.running) {
        _publishDiagnostics();
      } else {
        _publishedDiagnostics = false;
      }
    });
    if (runtime.status.phase == RuntimePhase.running) _publishDiagnostics();

    final Widget child;
    if (!settingsLoaded || !runtime.loaded || !prefs.loaded) {
      child = const _Splash();
    } else {
      if (!_decided) {
        _decided = true;
        _step = initialOnboardingStep(status: runtime.status, prefs: prefs);
        _chooseRuntime = runtimeStepAsks(runtime.status);
        if (_chooseRuntime && _step != null) ref.read(localFootprintProvider);
        _resumeBeside(prefs.setupStep, runtime.status);
      }
      if (_step case final step?) {
        child = OnboardingFlow(
          step: step,
          chooseRuntime: _chooseRuntime,
          beside: _beside,
          onLocal: _chooseRuntime ? _chooseLocal : null,
          onAccessDone: _afterAccess,
          onFinished: _afterFinishing,
          onComputer: _useComputerWeb,
          onWelcomeDone: () {
            unawaited(_prefs.markWelcomeSeen());
            _chooseRuntime = runtimeStepAsks(ref.read(localRuntimeProvider).status);
            _goTo(OnboardingStep.runtime);
          },
          onRuntimeDone: () => _goTo(null),
        );
      } else {
        child = widget.home ?? const ModeHome();
      }
    }
    if (child is! _Splash && !_launchReady) {
      _launchReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) LaunchController.active.value?.ready(waitsForEngine: true);
      });
    }
    return KeyedSubtree(
      key: ValueKey(child is _Splash ? 'splash' : (_step == null ? 'home' : 'onboarding')),
      child: child,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: StartupStage(key: ValueKey('lite-restore-stage')),
  );
}
