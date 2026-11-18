import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../web/startup_cover.dart';

/// A native Node smoke test is a prerequisite, not an installed DSH engine.
enum IosProbeState { idle, starting, probeReady, error }

enum IosProbeReason { nodeVersion, nodeCapabilities, probeTimeout, probeFailed, runtimeUnavailable }

class IosLocalProbeStatus {
  const IosLocalProbeStatus({
    required this.state,
    required this.compatible,
    this.nodeVersion,
    this.reason,
    this.capabilities = const {},
    this.loaderChecks,
    this.coreChecks,
    this.persistenceChecks,
    this.appBackgrounded = false,
  });

  static const dshVersion = '0.2.2-rc.3';
  static const requiredNode = '>=24.9.0';
  static const capabilityKeys = [
    'filesystemWriteRead',
    'intl',
    'getBuiltinModule',
    'sqlite',
    'sqliteFts5',
    'importMetaMain',
    'importMetaFilename',
    'importMetaDirname',
  ];

  static const loaderCheckKeys = [
    'dshLoaderBooted',
    'serviceVerified',
    'disposeVerified',
    'badBaselineRejected',
  ];
  static const coreCheckKeys = [
    'coreBooted',
    'servicesVerified',
    'firstTurnStreamed',
    'secondTurnHistoryVerified',
    'cancellationSettled',
    'errorSettled',
    'disposeVerified',
    'badBaselineRejected',
    'ephemeral',
  ];

  static const persistenceCheckKeys = [
    'storageBooted',
    'writerExclusionVerified',
    'readWhileOwnedVerified',
    'atomicAppendVerified',
    'flushVerified',
    'coldResumeVerified',
    'disposeVerified',
    'badBaselineRejected',
  ];

  static Map<String, bool?>? _checks(Object? raw, List<String> keys, {bool requireEphemeral = false}) {
    if (raw == null) return null;
    if (raw is! Map || raw['engineReady'] != false || (requireEphemeral && raw['ephemeral'] != true)) {
      throw const FormatException('invalid iOS validation report');
    }
    return {
      for (final key in keys) key: raw[key] is bool ? raw[key] as bool : null,
    };
  }

  /// Deliberately excludes endpoints, tokens, paths and arbitrary probe output.
  factory IosLocalProbeStatus.fromMap(Object? raw) {
    if (raw is! Map ||
        raw['engineReady'] != false ||
        raw['compatible'] is! bool ||
        raw['appBackgrounded'] is! bool ||
        raw['dshVersion'] != dshVersion ||
        raw['requiredNode'] != requiredNode) {
      throw const FormatException('invalid iOS probe status');
    }
    final state = switch (raw['state']) {
      'idle' => IosProbeState.idle,
      'starting' => IosProbeState.starting,
      'probeReady' => IosProbeState.probeReady,
      'error' => IosProbeState.error,
      _ => throw const FormatException('invalid iOS probe state'),
    };
    final node = raw['nodeVersion'];
    if (node != null &&
        (node is! String ||
            node.length > 48 ||
            (node.isNotEmpty && !RegExp(r'^v?\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?$').hasMatch(node)))) {
      throw const FormatException('invalid Node version');
    }
    if (state == IosProbeState.probeReady && (node == null || node == '')) {
      throw const FormatException('missing Node probe version');
    }
    final reason = switch (raw['reason']) {
      null || '' => null,
      'node_version' => IosProbeReason.nodeVersion,
      'node_capabilities' => IosProbeReason.nodeCapabilities,
      'probe_timeout' => IosProbeReason.probeTimeout,
      'probe_failed' => IosProbeReason.probeFailed,
      'runtime_unavailable' => IosProbeReason.runtimeUnavailable,
      _ => IosProbeReason.runtimeUnavailable,
    };
    final report = raw['report'];
    final capabilities = report is Map ? report['capabilities'] : null;
    return IosLocalProbeStatus(
      state: state,
      compatible: raw['compatible'] as bool,
      nodeVersion: node is String && node.isNotEmpty ? node : null,
      reason: reason,
      capabilities: {
        if (capabilities is Map)
          for (final key in capabilityKeys)
            if (capabilities[key] case final bool value) key: value,
      },
      loaderChecks: _checks(report is Map ? report['loader'] : null, loaderCheckKeys),
      coreChecks: _checks(report is Map ? report['core'] : null, coreCheckKeys, requireEphemeral: true),
      persistenceChecks: _checks(report is Map ? report['persistence'] : null, persistenceCheckKeys),
      appBackgrounded: raw['appBackgrounded'] as bool,
    );
  }

  final IosProbeState state;
  final bool compatible;
  final String? nodeVersion;
  final IosProbeReason? reason;
  final Map<String, bool> capabilities;
  final Map<String, bool?>? loaderChecks;
  final Map<String, bool?>? coreChecks;
  final Map<String, bool?>? persistenceChecks;
  final bool appBackgrounded;
}

/// iPhone/iPad's first local-runtime gate. It never mounts the Android installer,
/// restores a computer destination, or treats a successful probe as DSH ready.
class IosLocalEnginePage extends StatefulWidget {
  const IosLocalEnginePage({super.key});

  @override
  State<IosLocalEnginePage> createState() => _IosLocalEnginePageState();
}

class _IosLocalEnginePageState extends State<IosLocalEnginePage> {
  static const _channel = MethodChannel('dsh/ios-local');
  static const _requestTimeout = Duration(seconds: 10);
  // Native also bounds its probe; keep the UI bounded if that endpoint regresses.
  static const _probeTimeout = Duration(seconds: 60);
  late final AppLifecycleListener _lifecycle;
  IosLocalProbeStatus? _status;
  IosProbeReason? _failure;
  Timer? _poll;
  DateTime? _pendingSince;
  bool _requesting = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _visible = false;
        _poll?.cancel();
      },
      onShow: () {
        _visible = true;
        unawaited(_request('getStatus'));
      },
    );
    unawaited(_request('getStatus'));
  }

  Future<void> _request(String method) async {
    if (_requesting || !mounted) return;
    _poll?.cancel();
    setState(() => _requesting = true);
    try {
      final raw = await _channel.invokeMethod<Object?>(method).timeout(_requestTimeout);
      final status = IosLocalProbeStatus.fromMap(raw);
      if (!mounted) return;
      if (status.state == IosProbeState.starting) {
        _pendingSince ??= DateTime.now();
        if (DateTime.now().difference(_pendingSince!) >= _probeTimeout) {
          setState(() => _failure = IosProbeReason.probeTimeout);
          return;
        }
      } else {
        _pendingSince = null;
      }
      setState(() {
        _status = status;
        _failure = null;
      });
    } on TimeoutException {
      if (mounted) setState(() => _failure = IosProbeReason.probeTimeout);
    } on MissingPluginException {
      if (mounted) setState(() => _failure = IosProbeReason.runtimeUnavailable);
    } on PlatformException {
      if (mounted) setState(() => _failure = IosProbeReason.probeFailed);
    } on FormatException {
      if (mounted) setState(() => _failure = IosProbeReason.runtimeUnavailable);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
        if (_visible && _failure == null && _status?.state == IosProbeState.starting) {
          _poll = Timer(const Duration(milliseconds: 500), () => unawaited(_request('getStatus')));
        }
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  String _reasonText(L10n l10n, IosProbeReason reason) => switch (reason) {
    IosProbeReason.nodeVersion => l10n.iosLocalNodeVersionMismatch,
    IosProbeReason.nodeCapabilities => l10n.iosLocalCapabilitiesMissing,
    IosProbeReason.probeTimeout => l10n.iosLocalProbeTimeout,
    IosProbeReason.probeFailed => l10n.iosLocalProbeFailed,
    IosProbeReason.runtimeUnavailable => l10n.iosLocalRuntimeUnavailable,
  };

  String _capabilityText(L10n l10n, String key) => switch (key) {
    'filesystemWriteRead' => l10n.iosLocalCapabilityFileSystem,
    'intl' => l10n.iosLocalCapabilityIntl,
    'getBuiltinModule' => l10n.iosLocalCapabilityBuiltinModule,
    'sqlite' => l10n.iosLocalCapabilitySqlite,
    'sqliteFts5' => l10n.iosLocalCapabilitySqliteFts,
    'importMetaMain' => l10n.iosLocalCapabilityImportMain,
    'importMetaFilename' => l10n.iosLocalCapabilityImportFilename,
    'importMetaDirname' => l10n.iosLocalCapabilityImportDirname,
    _ => throw ArgumentError.value(key),
  };

  String _validationText(L10n l10n, String group, String key) => switch ((group, key)) {
    ('loader', 'dshLoaderBooted') => l10n.iosLocalLoaderBooted,
    ('loader', 'serviceVerified') => l10n.iosLocalLoaderService,
    ('loader', 'disposeVerified') => l10n.iosLocalLoaderDispose,
    ('loader', 'badBaselineRejected') => l10n.iosLocalLoaderBadBaseline,
    ('core', 'coreBooted') => l10n.iosLocalCoreBooted,
    ('core', 'servicesVerified') => l10n.iosLocalCoreServices,
    ('core', 'firstTurnStreamed') => l10n.iosLocalCoreFirstTurn,
    ('core', 'secondTurnHistoryVerified') => l10n.iosLocalCoreSecondTurn,
    ('core', 'cancellationSettled') => l10n.iosLocalCoreCancellation,
    ('core', 'errorSettled') => l10n.iosLocalCoreError,
    ('core', 'disposeVerified') => l10n.iosLocalCoreDispose,
    ('core', 'badBaselineRejected') => l10n.iosLocalCoreBadBaseline,
    ('core', 'ephemeral') => l10n.iosLocalCoreEphemeral,
    ('persistence', 'storageBooted') => l10n.iosLocalStorageBooted,
    ('persistence', 'writerExclusionVerified') => l10n.iosLocalStorageWriter,
    ('persistence', 'readWhileOwnedVerified') => l10n.iosLocalStorageReader,
    ('persistence', 'atomicAppendVerified') => l10n.iosLocalStorageAtomic,
    ('persistence', 'flushVerified') => l10n.iosLocalStorageFlush,
    ('persistence', 'coldResumeVerified') => l10n.iosLocalStorageResume,
    ('persistence', 'disposeVerified') => l10n.iosLocalStorageDispose,
    ('persistence', 'badBaselineRejected') => l10n.iosLocalStorageRejected,
    _ => throw ArgumentError.value(key),
  };

  Widget _validationSection(
    L10n l10n, {
    required String group,
    required String title,
    required String detail,
    required Map<String, bool?> checks,
  }) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('ios-local-$group-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(detail),
        const SizedBox(height: 12),
        for (final entry in checks.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (entry.value) {
                    true => AppIcons.done,
                    false => AppIcons.attention,
                    null => AppIcons.engine,
                  },
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_validationText(l10n, group, entry.key))),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    switch (entry.value) {
                      true => l10n.iosLocalCheckPassed,
                      false => l10n.iosLocalCheckFailed,
                      null => l10n.iosLocalCheckNotRun,
                    },
                    key: ValueKey('ios-local-$group-${entry.key}'),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status;
    final reason = _failure ?? status?.reason;
    final starting = _failure == null && status?.state == IosProbeState.starting;
    final probeReady = _failure == null && status?.state == IosProbeState.probeReady;
    final failed = reason != null || status?.state == IosProbeState.error;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final title = failed
        ? l10n.iosLocalProbeUnavailable
        : starting
        ? l10n.iosLocalProbeRunning
        : probeReady
        ? l10n.iosLocalProbePassed
        : _requesting
        ? l10n.iosLocalChecking
        : l10n.iosLocalProbeIdle;
    final detail = reason != null
        ? _reasonText(l10n, reason)
        : status?.state == IosProbeState.error
        ? l10n.iosLocalProbeFailed
        : probeReady
        ? (status!.compatible ? l10n.iosLocalProbeCompatible : l10n.iosLocalCapabilitiesMissing)
        : starting
        ? l10n.iosLocalProbeRunningDetail
        : l10n.iosLocalProbeIdleDetail;
    return Scaffold(
      key: const ValueKey('ios-local-engine-page'),
      backgroundColor: StartupCover.backgroundOf(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Center(
                   child: MediaQuery(
                     data: MediaQuery.of(context).copyWith(
                       disableAnimations: WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations,
                     ),
                     child: Image(
                       image: StartupCover.image,
                       key: const ValueKey('local-web-startup-cover'),
                       height: 148,
                       width: 148 * 2 / 3,
                       fit: BoxFit.contain,
                       excludeFromSemantics: true,
                     ),
                   ),
                 ),
                 const SizedBox(height: 12),
                 Text(
                   l10n.localWebExploreBeyond,
                   textAlign: TextAlign.center,
                   style: theme.textTheme.titleLarge?.copyWith(
                     fontSize: 22,
                     fontWeight: FontWeight.w500,
                     letterSpacing: 4,
                     height: 1.35,
                   ),
                 ),
                const SizedBox(height: 24),
                Text(l10n.iosLocalTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(l10n.iosLocalScope, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (starting || (_requesting && status == null))
                              SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: title),
                              )
                            else
                              Icon(failed ? AppIcons.attention : AppIcons.engine, color: failed ? colors.warning : null),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(title, key: const ValueKey('ios-local-status'), style: theme.textTheme.titleMedium),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(detail, key: const ValueKey('ios-local-detail')),
                        const Divider(height: 32),
                        Text(l10n.iosLocalNodeVersion(status?.nodeVersion ?? l10n.iosLocalNotDetected)),
                        const SizedBox(height: 6),
                        Text(l10n.iosLocalRequiredNode(IosLocalProbeStatus.requiredNode)),
                        const SizedBox(height: 6),
                        Text(l10n.iosLocalDshVersion(IosLocalProbeStatus.dshVersion)),
                        const SizedBox(height: 16),
                        Text(
                          l10n.iosLocalDshNotStarted,
                          key: const ValueKey('ios-local-dsh-not-started'),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(l10n.iosLocalProbeOnly),
                        if (status?.capabilities.isNotEmpty ?? false) ...[
                          const Divider(height: 32),
                          Text(l10n.iosLocalCapabilitiesTitle, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 12),
                          for (final entry in status!.capabilities.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(entry.value ? AppIcons.done : AppIcons.attention, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_capabilityText(l10n, entry.key))),
                                  Text(entry.value ? l10n.iosLocalCheckPassed : l10n.iosLocalCheckFailed),
                                ],
                              ),
                            ),
                        ],
                        if (status?.loaderChecks != null)
                           _validationSection(
                             l10n,
                             group: 'loader',
                             title: l10n.iosLocalLoaderTitle,
                             detail: l10n.iosLocalLoaderDetail,
                             checks: status!.loaderChecks!,
                           ),
                         if (status?.coreChecks != null)
                           _validationSection(
                             l10n,
                             group: 'core',
                             title: l10n.iosLocalCoreTitle,
                             detail: l10n.iosLocalCoreDetail,
                             checks: status!.coreChecks!,
                           ),
                         if (status?.persistenceChecks case final checks?)
                            _validationSection(
                              l10n,
                              group: 'persistence',
                              title: l10n.iosLocalStorageTitle,
                              detail: l10n.iosLocalStorageDetail,
                              checks: checks,
                            ),
                          if (status?.appBackgrounded == true) ...[
                          const SizedBox(height: 12),
                          Text(l10n.iosLocalBackgroundObservation),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('ios-local-start-probe'),
                  onPressed: !_requesting && _failure == null && status?.state == IosProbeState.idle
                      ? () => unawaited(_request('startProbe'))
                      : null,
                  icon: const Icon(AppIcons.play),
                  label: Text(starting ? l10n.iosLocalProbeRunning : l10n.iosLocalRunProbe),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('ios-local-refresh'),
                  onPressed: _requesting ? null : () => unawaited(_request('getStatus')),
                  icon: const Icon(AppIcons.refresh),
                  label: Text(l10n.iosLocalRefresh),
                ),
                const SizedBox(height: 12),
                Text(l10n.iosLocalBackgroundLimit, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
