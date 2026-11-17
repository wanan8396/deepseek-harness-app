// Lite first run keeps every file/background permission on one page. Only
// explicit row taps open system UI; returning to the app just reads its state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/access_state.dart';
import '../../state/lite_access_confirmation_state.dart';
import '../onboarding/onboarding_scaffold.dart';
import '../theme/app_icons.dart';
import 'access_text.dart';

class LitePermissionsPage extends ConsumerStatefulWidget {
  const LitePermissionsPage({super.key, required this.onDone, this.finishing = false, this.settings = false});

  final VoidCallback onDone;
  final bool finishing;
  final bool settings;

  static const features = {AccessFeature.files, AccessFeature.background};

  @override
  ConsumerState<LitePermissionsPage> createState() => _LitePermissionsPageState();
}

class _LitePermissionsPageState extends ConsumerState<LitePermissionsPage> {
  late final AppLifecycleListener _lifecycle;
  final _tried = <AccessItem>{};
  AccessItem? _opening;
  AccessItem? _confirming;
  bool _finishing = false;

  bool get _busy => _opening != null || _confirming != null || _finishing || widget.finishing;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _refresh() async {
    try {
      await ref.read(accessReadingsProvider.notifier).refresh();
    } catch (_) {
      if (mounted) _toast(context.l10n.accessFinishFailed);
    }
  }

  Future<void> _open(AccessItem item) async {
    if (_busy) return;
    final again = _tried.contains(item);
    setState(() {
      _opening = item;
      _tried.add(item);
    });
    var opened = false;
    try {
      opened = await ref.read(accessDriverProvider).open(item, again: again);
      if (!mounted) return;
      // This records a visit only, never a detected grant. A failed launch
      // must not make an unknown vendor switch look settled.
      if (opened && item.vendor) await ref.read(accessVisitedProvider.notifier).mark(item);
    } catch (_) {
      // Keep the row available for retry, with the same failure as false.
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    setState(() => _opening = null);
    if (!opened) _toast(context.l10n.accessOpenFailed);
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _finishing = true);
    try {
      await applyFileAccess(ref.container);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) _toast(context.l10n.accessFinishFailed);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _confirmVendor(AccessItem item) async {
    if (_busy || !item.vendor) return;
    setState(() => _confirming = item);
    try {
      await ref.read(liteAccessConfirmedProvider.notifier).confirm(item);
    } catch (_) {
      if (mounted) _toast(context.l10n.accessFinishFailed);
    } finally {
      if (mounted) setState(() => _confirming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final readings = ref.watch(accessReadingsProvider).value;
    final visited = ref.watch(accessVisitedProvider);
    final confirmed = ref.watch(liteAccessConfirmedProvider);
    final rows = [
      if (readings != null)
        for (final item in accessWalk(LitePermissionsPage.features, readings.vendor))
          if (accessStateOf(item, readings, visited) case final state?) (item, state),
    ];
    return OnboardingScaffold(
      key: const ValueKey('lite-permissions-page'),
      leading: widget.settings ? BackButton(onPressed: widget.onDone) : null,
      showRuntime: !widget.settings,
      children: [
        OnboardingHeader(icon: AppIcons.systemAccess, title: l10n.accessPageTitle, message: l10n.accessPageSubtitle),
        const SizedBox(height: 20),
        if (rows.isNotEmpty)
          LiteOnboardingCard(
            key: const ValueKey('lite-permissions-card'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, (item, state)) in rows.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _PermissionRow(
                    item: item,
                    state: state,
                    vendor: readings!.vendor,
                    busy: _busy,
                    confirmed: item.vendor && confirmed.contains(item),
                    onOpen: () => unawaited(_open(item)),
                    onConfirm: () => unawaited(_confirmVendor(item)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Spacer(),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('lite-permissions-continue'),
          onPressed: _busy ? null : () => unawaited(_finish()),
          child: Text(widget.settings ? l10n.accessRootDone : l10n.commonContinue),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.item,
    required this.state,
    this.vendor,
    required this.busy,
    required this.confirmed,
    required this.onOpen,
    required this.onConfirm,
  });

  final AccessItem item;
  final AccessState state;
  final String? vendor;
  final bool busy;
  final bool confirmed;
  final VoidCallback onOpen;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.title(l10n, vendor: vendor), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(item.why(l10n), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 5),
        Text(
          confirmed ? l10n.accessStateConfirmed : state.label(l10n),
          key: ValueKey('lite-permission-state-${item.name}'),
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final button = FilledButton(
      key: ValueKey('lite-permission-get-${item.name}'),
      onPressed: state == AccessState.on || busy ? null : onOpen,
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.45),
      ),
      child: Text(
        item.vendor ? l10n.accessViewSettings : (state == AccessState.on ? l10n.accessStateOn : l10n.accessTurnOn),
      ),
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (item.vendor && !confirmed)
          TextButton(
            key: ValueKey('lite-permission-confirm-${item.name}'),
            onPressed: busy ? null : onConfirm,
            child: Text(l10n.accessConfirmEnabled),
          ),
      ],
    );
    // The shared scaffold measures intrinsic height to make its column scroll.
    // Avoid a nested LayoutBuilder, which has no intrinsic dimensions.
    final stacked = MediaQuery.sizeOf(context).width < 360 || MediaQuery.textScalerOf(context).scale(14) > 18;
    return Padding(
      key: ValueKey('lite-permission-row-${item.name}'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                details,
                const SizedBox(height: 10),
                Align(alignment: AlignmentDirectional.centerEnd, child: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }
}
