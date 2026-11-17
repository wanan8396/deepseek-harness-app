// First run offers this phone's runtime or a computer's HTTP(S) webpage.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/local_footprint.dart';
import '../common/pressable.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'onboarding_scaffold.dart';

/// Where DSH runs.
enum RuntimeOption { local, computer }

/// Phone storage/memory information is shown before installing; a computer
/// choice opens the separate HTTP(S) connection page.
class RuntimeChoiceView extends ConsumerStatefulWidget {
  const RuntimeChoiceView({super.key, required this.onLocal, this.onComputer, this.leading});

  final VoidCallback onLocal;
  final VoidCallback? onComputer;

  /// Top-left key, as [OnboardingScaffold.leading].
  final Widget? leading;

  @override
  ConsumerState<RuntimeChoiceView> createState() => _RuntimeChoiceViewState();
}

class _RuntimeChoiceViewState extends ConsumerState<RuntimeChoiceView> {
  RuntimeOption? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final footprint = ref.watch(localFootprintProvider).value;
    final selected = widget.onComputer == null ? RuntimeOption.local : (_picked ?? RuntimeOption.local);
    final colors = DshColors.of(context);

    final String localDetail;
    var localWarn = false;
    if (footprint != null && footprint.lowStorage) {
      localDetail = l10n.localEnvLowStorage(footprint.requiredRoundedMb!);
      localWarn = true;
    } else if (footprint?.unpackedMb case final unpacked?) {
      localDetail = l10n.localEnvThisPhoneDetail(LocalFootprint.round(unpacked), LocalFootprint.engineMemoryMb);
    } else {
      localDetail = l10n.localEnvThisPhoneDetailShort(LocalFootprint.engineMemoryMb);
    }

    return OnboardingScaffold(
      leading: widget.leading,
      children: [
        const Spacer(),
        OnboardingHeader(icon: AppIcons.thisPhone, title: l10n.commonThisPhone, message: l10n.shellRuntimeFirstSetup),
        const SizedBox(height: 28),
        RuntimeOptionCard(
          key: const ValueKey('runtime-option-local'),
          icon: AppIcons.thisPhone,
          title: l10n.commonThisPhone,
          detail: localDetail,
          detailColor: localWarn ? colors.warning : null,
          selected: selected == RuntimeOption.local,
          onTap: () => setState(() => _picked = RuntimeOption.local),
        ),
        if (widget.onComputer != null) ...[
          const SizedBox(height: RuntimeOptionCard.gap),
          RuntimeOptionCard(
            key: const ValueKey('runtime-option-computer'),
            icon: AppIcons.computer,
            title: l10n.remoteConnectComputer,
            detail: l10n.localEnvRemoteDetail,
            selected: selected == RuntimeOption.computer,
            onTap: () => setState(() => _picked = RuntimeOption.computer),
          ),
        ],
        const Spacer(flex: 2),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: selected == RuntimeOption.local ? widget.onLocal : widget.onComputer,
          child: Text(l10n.commonContinue),
        ),
      ],
    );
  }
}

/// One choice: a 40 glyph tile, title (with an optional 「推荐」 tag) over
/// one line of detail, and a radio mark. [pad] on every side, so the glyph
/// and the mark sit the same distance from their edges; the ring is drawn
/// inside the edge and moves nothing.
class RuntimeOptionCard extends StatelessWidget {
  const RuntimeOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.detailColor,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final Color? detailColor;

  static const pad = 16.0;
  static const glyph = 40.0;
  static const mark = 22.0;
  static const gap = 12.0;

  /// The ring round the chosen card.
  static const ring = 2.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final duration = AppMotion.of(context, AppMotion.quick);
    final fill = dark ? Colors.white.withValues(alpha: 0.05) : scheme.onSurface.withValues(alpha: 0.04);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: [title, detail].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.std,
          padding: const EdgeInsets.all(pad),
          decoration: ShapeDecoration(
            color: fill,
            shape: const RoundedSuperellipseBorder(borderRadius: AppShape.radiusLg),
          ),
          foregroundDecoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: AppShape.radiusLg,
              side: BorderSide(
                color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7),
                width: selected ? ring : 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: dark ? Colors.white.withValues(alpha: 0.07) : scheme.onSurface.withValues(alpha: 0.06),
                  shape: Squircle.border(AppShape.sm),
                ),
                child: SizedBox.square(
                  dimension: glyph,
                  child: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: detailColor ?? colors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: duration,
                child: Icon(
                  selected ? AppIcons.radioOn : AppIcons.radioOff,
                  key: ValueKey(selected),
                  size: mark,
                  color: selected ? scheme.primary : colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
