import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_variant.dart';
import '../web/startup_cover.dart';
import '../../launch/launch_state.dart';
import '../../runtime/local_footprint.dart';
import '../../diagnostics/diagnostics_publish.dart';
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../../share_code/guest_fs.dart';
import '../../state/engine_control.dart';
import '../../state/hosts_state.dart';
import '../../state/notify_state.dart';
import '../../state/onboarding_state.dart';
import '../../state/settings_state.dart';
import '../../state/web_connection_state.dart';
import '../settings/connect_computer_page.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/setup_progress.dart';
import '../remote/remote_screen.dart';
import '../theme/theme.dart';
import '../web/mode_home.dart';
import 'brand_mark.dart';
import 'usage_upgrade_notice.dart';

/// Where a launch should start, given what is installed and configured.
///
/// - First run on this phone, set up while the runtime unpacked
///   ([OnboardingPrefs.setupStep]) and not over yet → back to that page; the
///   connection page only while nothing is connected, the waiting page only
///   while the runtime is not there.
/// - Runtime mid-install → setup, which carries on.
/// - The app runs without the runtime ([OnboardingPrefs.localDeclined]: a
///   remote host instead, or uninstalled) → home.
/// - Runtime outdated → setup, which upgrades it.
/// - Runtime missing → setup, which first asks 本机 or 远程主机 (welcome
///   first on a truly fresh install).
/// - Runtime ready but nothing to talk to (no DeepSeek key, no custom provider
///   on the local engine), and the user never chose "稍后设置" → key entry.
/// - Otherwise → home (`null`).
OnboardingStep? initialOnboardingStep({
  required RuntimeStatus status,
  required bool hasApiKey,
  required OnboardingPrefs prefs,
  bool hasCustomProvider = false,
  bool useComputerWeb = false,
}) {
  if (localWebLite && useComputerWeb) return null;
  final installedCurrent = status.installedVersion != null && status.installedVersion == status.bundledVersion;
  final needsRuntime = switch (status.phase) {
    RuntimePhase.notInstalled || RuntimePhase.installing => true,
    RuntimePhase.error => !installedCurrent,
    _ => false,
  };
  // Only a first install (nothing older to upgrade) that was not given up for
  // a remote host.
  if (prefs.setupStep case final resume?
      when (localWebLite || !prefs.localDeclined) && (installedCurrent || status.installedVersion == null)) {
    final connected = localWebLite || hasApiKey || hasCustomProvider || prefs.keySkipped;
    return switch (resume) {
      SetupStep.appearance => localWebLite ? OnboardingStep.access : OnboardingStep.appearance,
      SetupStep.access => OnboardingStep.access,
      SetupStep.connect when !connected => OnboardingStep.apiKey,
      _ => needsRuntime ? OnboardingStep.finishing : null,
    };
  }
  if (needsRuntime) {
    // An install that was running when the app went away carries on.
    if (status.phase == RuntimePhase.installing) return OnboardingStep.runtime;
    // Runs without it (also after leaving a failed upgrade for a remote host).
    if (!localWebLite && prefs.localDeclined) return null;
    // An upgrade (an older rootfs exists) skips the welcome and the choice.
    if (!runtimeStepAsks(status)) return OnboardingStep.runtime;
    return prefs.welcomeSeen ? OnboardingStep.runtime : OnboardingStep.welcome;
  }
  if (!localWebLite && !hasApiKey && !hasCustomProvider && !prefs.keySkipped) return OnboardingStep.apiKey;
  return null;
}

/// Whether the setup step asks 本机 or 远程主机 first: nothing to upgrade and
/// no install underway.
bool runtimeStepAsks(RuntimeStatus status) =>
    status.installedVersion == null && status.phase != RuntimePhase.installing;

/// Resolves the lite edition's destination before mounting any local runtime
/// consumers. Switching to the computer disposes the local gate; coming back
/// creates a fresh gate that resumes the phone's saved setup.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key, this.home});

  /// Stands in for [ModeHome] (tests).
  @visibleForTesting
  final Widget? home;

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _computerReady = false;

  @override
  Widget build(BuildContext context) {
    if (!localWebLite) return _LocalRootGate(home: widget.home);
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

/// The full edition's existing gate and the lite edition's on-device setup.
/// Lite home startup belongs to LocalWebScreen's waiting page, not this gate.
class _LocalRootGate extends ConsumerStatefulWidget {
  const _LocalRootGate({this.home});

  final Widget? home;

  @override
  ConsumerState<_LocalRootGate> createState() => _LocalRootGateState();
}

class _LocalRootGateState extends ConsumerState<_LocalRootGate> {
  bool _decided = false;

  /// Published this engine run's diagnostics snapshot (the agent reads it on demand).
  bool _publishedDiagnostics = false;
  bool _launchReady = false;
  OnboardingStep? _step;
  bool _autoStartDone = false;

  /// The setup step asks 本机 or 远程主机 first ([runtimeStepAsks]).
  bool _chooseRuntime = false;

  /// The host list is open over the setup step.
  bool _pickingRemote = false;

  /// First run on this phone, setting up while the runtime unpacks
  /// (docs/design/onboarding-parallel-setup.md).
  bool _beside = false;

  /// The engine was asked to start for it, once.
  bool _besideEngine = false;

  ProviderContainer get _container => ProviderScope.containerOf(context, listen: false);

  void _goTo(OnboardingStep? step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _afterRuntime() {
    // The full edition needs DSH for key entry; lite starts on its waiting page.
    if (!localWebLite) {
      _autoStartDone = true;
      unawaited(EngineControl.ensureStarted(_container));
    }
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(onboardingPrefsProvider);
    _goTo(localWebLite || settings.hasModelAccess || prefs.keySkipped ? null : OnboardingStep.apiKey);
  }

  void _afterKey() {
    if (_beside) return _finishBeside();
    if (!localWebLite) {
      _autoStartDone = true;
      unawaited(EngineControl.ensureStarted(_container));
    }
    _goTo(null);
  }

  // ── Set up beside the unpack ──

  OnboardingPrefsController get _prefs => ref.read(onboardingPrefsProvider.notifier);

  /// The unpack, through the one entry (a second request is the first one).
  void _startUnpack() {
    // Time left is estimated from the first progress report on.
    ref.read(installEtaProvider);
    unawaited(ref.read(runtimeInstallProvider.notifier).install());
    // Android 13 asks about notifications once the channels exist: now, as the
    // unpack (and its notification) starts, not over a later step.
    unawaited(ref.read(notifyChannelProvider).status().then<void>((_) {}, onError: (_) {}));
  }

  /// The engine for the sign-in (and a custom provider's save), as soon as
  /// the runtime is there.
  void _startEngineBeside() {
    // Lite has no native sign-in step: its home waiting page is the sole owner.
    if (localWebLite || _besideEngine) return;
    _besideEngine = true;
    _autoStartDone = true;
    unawaited(EngineControl.ensureStarted(_container));
  }

  /// 「本机」: unpack in the background, set up meanwhile.
  void _chooseLocal() {
    _beside = true;
    unawaited(_prefs.setSetupStep(localWebLite ? SetupStep.access : SetupStep.appearance));
    _startUnpack();
    _goTo(localWebLite ? OnboardingStep.access : OnboardingStep.appearance);
  }

  void _afterAppearance() {
    unawaited(_prefs.setSetupStep(SetupStep.access));
    _goTo(OnboardingStep.access);
  }

  void _afterAccess() {
    final connected =
        localWebLite || ref.read(settingsProvider).hasModelAccess || ref.read(onboardingPrefsProvider).keySkipped;
    if (connected) return _finishBeside();
    unawaited(_prefs.setSetupStep(SetupStep.connect));
    _goTo(OnboardingStep.apiKey);
  }

  /// Everything set: home if the runtime is there, else wait for it.
  void _finishBeside() {
    if (ref.read(setupRuntimeProvider) != SetupRuntime.ready) {
      unawaited(_prefs.setSetupStep(SetupStep.finishing));
      _goTo(OnboardingStep.finishing);
      return;
    }
    _startEngineBeside();
    _leaveBeside();
    _goTo(null);
  }

  /// The unpack the waiting page showed is done.
  void _afterFinishing() {
    _startEngineBeside();
    _leaveBeside();
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(onboardingPrefsProvider);
    _goTo(localWebLite || settings.hasModelAccess || prefs.keySkipped ? null : OnboardingStep.apiKey);
  }

  void _leaveBeside() {
    _beside = false;
    unawaited(_prefs.setSetupStep(null));
  }

  /// 「远程主机」: the host list over the setup step. Picking a host there
  /// (it closes itself) finishes first run without the runtime; coming back
  /// without one returns to the choice.
  Future<void> _useRemote() async {
    if (localWebLite || _pickingRemote) return;
    _pickingRemote = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RemoteScreen()));
    } finally {
      _pickingRemote = false;
    }
    if (!mounted || ref.read(activeHostProvider).isLocal) return;
    if (_beside) _leaveBeside();
    await ref.read(onboardingPrefsProvider.notifier).setLocalDeclined(true);
    // What installing does on the other path: Android 13 asks about
    // notifications once the channels exist, before the first reply lands.
    unawaited(ref.read(notifyChannelProvider).status().then<void>((_) {}, onError: (_) {}));
    _autoStartDone = true;
    _goTo(null);
  }

  Future<void> _useComputerWeb() async {
    if (!localWebLite || _pickingRemote) return;
    _pickingRemote = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectComputerPage()));
    } finally {
      _pickingRemote = false;
    }
    // RootGate switches owners when the connection changes. Keep this phone's
    // saved setup step intact so a later local return resumes it.
  }

  /// Writes the diagnostics snapshot once per engine run, after the frame that saw it.
  /// Widget tests have no rootfs and must not leave diagnostics timeouts behind.
  void _publishDiagnostics() {
    if (_publishedDiagnostics || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _publishedDiagnostics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(diagnosticsPublisherProvider).publish());
    });
  }

  void _maybeAutoStart() {
    if (localWebLite || _autoStartDone) return;
    _autoStartDone = true;
    final settings = ref.read(settingsProvider);
    if (!settings.autoStartLocal) return;
    final status = ref.read(localRuntimeProvider).status;
    // After repeated crashes with automatic safe mode off, the failure card
    // waits for the user instead of starting again.
    if (status.phase == RuntimePhase.installed && EngineControl.shouldAutoStart(status)) {
      unawaited(ref.read(localRuntimeProvider.notifier).start());
    }
  }

  /// Back to first run's set-up-beside-the-unpack after the app went away:
  /// an unpack that died with the process starts again (from scratch, as
  /// Android always does); one that is done gets the engine going.
  void _resumeBeside(SetupStep? saved, RuntimeStatus status) {
    if (saved == null) return;
    _beside = switch (_step) {
      OnboardingStep.appearance || OnboardingStep.access || OnboardingStep.apiKey || OnboardingStep.finishing => true,
      _ => false,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // First run is over (finished while away, or a remote host instead).
      if (!_beside) return unawaited(_prefs.setSetupStep(null));
      switch (setupRuntimeOf(status)) {
        case SetupRuntime.absent:
          _startUnpack();
        case SetupRuntime.ready when _step != OnboardingStep.finishing:
          _startEngineBeside();
        case _:
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider.select((s) => (status: s.status, loaded: s.loaded)));
    final prefs = ref.watch(onboardingPrefsProvider);
    // The last host comes back while the splash shows, so a phone without
    // the runtime doesn't open on 本机 for a frame before its remote host.
    ref.read(activeHostProvider);

    // "重置运行环境" sends the user back through setup; 「卸载运行环境」
    // (localDeclined) stays home.
    ref.listen(localRuntimeProvider.select((s) => s.status.phase), (prev, next) {
      if (_decided &&
          _step == null &&
          next == RuntimePhase.notInstalled &&
          prev != RuntimePhase.notInstalled &&
          (localWebLite || !ref.read(onboardingPrefsProvider).localDeclined)) {
        _chooseRuntime = false;
        _goTo(OnboardingStep.runtime);
      }
    });
    // Setting up beside the unpack: the engine starts the moment the runtime
    // is there (the waiting page goes on by itself and starts it then).
    ref.listen(setupRuntimeProvider, (prev, next) {
      if (_beside && next == SetupRuntime.ready && prev != SetupRuntime.ready && _step != OnboardingStep.finishing) {
        _startEngineBeside();
      }
    });
    // The rootfs came or went: files read straight from it look again.
    ref.listen(localRuntimeProvider.select((s) => s.status.installedVersion), (prev, next) {
      if (prev != next) ref.invalidate(guestFsProvider);
    });
    // The engine is up: write this run's diagnostics where its agent can read them.
    // A restart publishes the next snapshot.
    ref.listen(localRuntimeProvider.select((s) => s.status.phase), (_, next) {
      if (next == RuntimePhase.running) {
        _publishDiagnostics();
      } else {
        _publishedDiagnostics = false;
      }
    });
    if (runtime.status.phase == RuntimePhase.running) _publishDiagnostics();

    final Widget child;
    if (!settings.loaded || !runtime.loaded || !prefs.loaded) {
      child = const _Splash();
    } else {
      if (!_decided) {
        _decided = true;
        _step = initialOnboardingStep(
          status: runtime.status,
          hasApiKey: settings.hasApiKey,
          hasCustomProvider: settings.customProviderIds.isNotEmpty,
          prefs: prefs,
        );
        _chooseRuntime = runtimeStepAsks(runtime.status);
        // The choice shows what installing costs: read it before it opens.
        if (_chooseRuntime && _step != null) ref.read(localFootprintProvider);
        _resumeBeside(prefs.setupStep, runtime.status);
      }
      if (_step case final step?) {
        child = OnboardingFlow(
          step: step,
          chooseRuntime: _chooseRuntime,
          beside: _beside,
          onLocal: _chooseRuntime ? _chooseLocal : null,
          onAppearanceDone: _afterAppearance,
          onAccessDone: _afterAccess,
          onFinished: _afterFinishing,
          onRemote: _useRemote,
          onComputer: localWebLite ? _useComputerWeb : null,
          onWelcomeDone: () {
            unawaited(ref.read(onboardingPrefsProvider.notifier).markWelcomeSeen());
            _chooseRuntime = runtimeStepAsks(ref.read(localRuntimeProvider).status);
            _goTo(OnboardingStep.runtime);
          },
          onRuntimeDone: _afterRuntime,
          onKeyDone: _afterKey,
        );
      } else {
        if (!localWebLite) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeAutoStart();
          });
        }
        // The native shell or the web page, by 界面 (ui_mode_state.dart); an
        // install from before usage statistics is told about them there, once.
        final home = widget.home ?? const ModeHome();
        child = localWebLite ? home : UsageUpgradeNotice(child: home);
      }
    }
    if (child is! _Splash && !_launchReady) {
      // 启动画面: the first page is up. A warm start's launch screen goes now; a cold start of
      // this phone's engine finishes its motion first (or goes when the engine is up).
      _launchReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) LaunchController.active.value?.ready(waitsForEngine: ref.read(activeHostProvider).isLocal);
      });
    }
    if (localWebLite) {
      return KeyedSubtree(
        key: ValueKey(child is _Splash ? 'splash' : (_step == null ? 'home' : 'onboarding')),
        child: child,
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.page),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: KeyedSubtree(
        key: ValueKey(child is _Splash ? 'splash' : (_step == null ? 'home' : 'onboarding')),
        child: child,
      ),
    );
  }
}

/// Shown for the few hundred ms before settings and runtime status arrive. Same
/// colour as the Android launch window; the mark fades in only if loading is slow.
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (localWebLite) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: StartupStage(key: ValueKey('lite-restore-stage')),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(Theme.of(context).brightness),
      child: AppBackdrop(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: AppMotion.of(context, AppMotion.slow),
            child: const BrandMark(size: 64, tile: true),
          ),
        ),
      ),
    );
  }
}
