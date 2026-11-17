import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/local_footprint.dart' show RuntimeMissing;
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../../state/engine_control.dart';
import '../../state/settings_state.dart';
import '../../state/web_appearance_state.dart';
import '../onboarding/local_install.dart';
import 'web_handle.dart';
import 'startup_cover.dart';
import 'web_target.dart';
import 'web_view_page.dart';

/// `http://127.0.0.1:3080/?token=…` — the official DSH Web UI's launch URL.
Uri localWebUri(String baseUrl, String token) =>
    Uri.parse(baseUrl).replace(path: '/', queryParameters: {'token': token});

/// The official DSH webpage served by the phone's local engine.
class LocalWebScreen extends ConsumerWidget {
  const LocalWebScreen({super.key, this.target, this.handle, this.handleAtBottom = false, this.link, this.onSession});

  /// Page to land on (a session, a panel, a settings section…).
  final DshWebTarget? target;

  /// 网页模式: the page is the app's home; [handle] takes the back button's
  /// seat (and a place in the engine page's bar while the engine is down).
  final Widget Function(double size)? handle;
  final bool handleAtBottom;

  /// See [WebViewPage.link] and [WebViewPage.onSession].
  final DshWebLink? link;
  final ValueChanged<String?>? onSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(localRuntimeProvider.select((s) => s.status));
    final phoneLayout = ref.watch(settingsProvider.select((s) => s.webPhoneLayout));
    if (status.isRunning) {
      return WebViewPage(
        // A restart issues a new token, and the layout switch applies on
        // load: rebuild the WebView for either.
        key: ValueKey((status.token, phoneLayout)),
        url: localWebUri(status.baseUrl!, status.token!),
        title: context.l10n.webTitle,
        subtitle: context.l10n.commonThisPhone,
        externalDisabledReason: context.l10n.webLocalAppOnly,
        dshWeb: true,
        phoneLayout: phoneLayout,
        openTarget: target,
        leading: handle,
        leadingAtBottom: handleAtBottom,
        root: handle != null,
        link: link,
        onSession: onSession,
      );
    }
    if (handleAtBottom && handle != null) {
      // Same full viewport as the WebView: the original cover never shifts.
      return Stack(
        fit: StackFit.expand,
        children: [
          const _LiteWaiting(),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: WebBottomHandle(key: const ValueKey('web-controls-bottom'), handle: handle!),
            ),
        ],
      );
    }
    return const _LiteWaiting();
  }
}

/// The lite edition waits for its local webpage instead of exposing engine
/// management. An installed runtime gets one automatic start attempt per mount;
/// an error never schedules another attempt until the person taps Retry.
class _LiteWaiting extends ConsumerStatefulWidget {
  const _LiteWaiting();

  @override
  ConsumerState<_LiteWaiting> createState() => _LiteWaitingState();
}

class _LiteWaitingState extends ConsumerState<_LiteWaiting> {
  bool _attempted = false;
  bool _starting = false;
  bool _startFailed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(localRuntimeProvider, (_, next) => _ensureStartedOnce(next), fireImmediately: true);
  }

  void _ensureStartedOnce(LocalRuntimeState state) {
    if (!state.loaded) return;
    final phase = state.status.phase;
    if (phase == RuntimePhase.error) {
      _attempted = true;
      _startFailed = true;
      return;
    }
    if (_attempted) return;
    if (phase == RuntimePhase.starting) {
      _attempted = true;
      return;
    }
    // A previous app exit can still be stopping. Wait for installed before
    // consuming this mount's one start attempt.
    if (phase != RuntimePhase.installed) return;
    _attempted = true;
    if (!EngineControl.shouldAutoStart(state.status)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(localRuntimeProvider).status.phase == RuntimePhase.installed) unawaited(_start());
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _startFailed = false;
    });
    try {
      await EngineControl.ensureStarted(ProviderScope.containerOf(context, listen: false));
    } catch (_) {
      if (mounted) setState(() => _startFailed = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localRuntimeProvider);
    final status = state.status;
    final missing = state.loaded && status.runtimeMissing;
    final failed =
        !_starting &&
        (_startFailed ||
            status.phase == RuntimePhase.error ||
            (status.phase == RuntimePhase.installed && !EngineControl.shouldAutoStart(status)));
    final waiting = !missing && !failed;
    final brightness = ref.watch(webAppearanceProvider) ?? Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    if (waiting) {
      return const Scaffold(
        key: ValueKey('local-web-waiting'),
        backgroundColor: Colors.transparent,
        body: StartupStage(),
      );
    }
    return Scaffold(
      key: const ValueKey('local-web-waiting'),
      backgroundColor: StartupCover.backgroundOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    dark ? 'assets/branding/wordmark-dark.png' : 'assets/branding/wordmark.png',
                    width: 220,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    missing ? context.l10n.localEnvNotInstalled : context.l10n.webEngineStartFailed,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (failed)
                    FilledButton(
                      key: const ValueKey('local-web-retry'),
                      onPressed: () => unawaited(_start()),
                      child: Text(context.l10n.commonRetry),
                    ),
                  if (missing)
                    FilledButton(
                      key: const ValueKey('local-web-install'),
                      onPressed: () => unawaited(openLocalInstall(context)),
                      child: Text(context.l10n.phoneEngineInstallRuntime),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
