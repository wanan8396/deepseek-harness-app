import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../state/app_info.dart';
import '../theme/theme.dart';
import '../shell/harness_wordmark.dart';
import 'setup_progress.dart';

/// Where a first-run page sits in the flow; [OnboardingScaffold] draws it as a
/// thin step bar in the top row. Provided by `OnboardingFlow`; absent when a
/// page is opened on its own (permissions from connection settings).
class OnboardingProgress extends InheritedWidget {
  const OnboardingProgress({
    super.key,
    required this.step,
    required this.steps,
    this.runtime = false,
    required super.child,
  });

  /// 1-based step shown as current.
  final int step;
  final int steps;

  /// The runtime unpacks beside this step (first run on this phone): the
  /// scaffold keeps it in view with a [SetupProgressCapsule].
  final bool runtime;

  static OnboardingProgress? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnboardingProgress>();

  @override
  bool updateShouldNotify(OnboardingProgress oldWidget) =>
      step != oldWidget.step || steps != oldWidget.steps || runtime != oldWidget.runtime;
}

/// Shared frame for the first-run pages: backdrop, safe area, a 440dp reading column
/// centred on tablets, and a column that fills the screen but scrolls when the
/// keyboard (or a large font scale) needs more room.
///
/// A fixed 56dp top row holds an optional back button 12 in from the left and,
/// inside the flow, the step bar centred on the screen. While the runtime
/// unpacks beside the step ([OnboardingProgress.runtime]) a fixed bottom row
/// holds its capsule, centred; the row keeps its height whether the capsule
/// shows or not, and steps aside for the keyboard.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.children,
    this.leading,
    this.showRuntime = true,
    this.showBrand = true,
  });

  final bool showBrand;

  /// Laid out in a full-height column; use [Spacer]s to distribute space.
  final List<Widget> children;

  /// Optional widget pinned at the top-left (the back button).
  final Widget? leading;

  /// False on a page that shows the unpack itself (a big halo): no capsule.
  final bool showRuntime;

  /// Space under the capsule, above the bottom safe area.
  static const capsuleBottom = 12.0;

  @override
  Widget build(BuildContext context) {
    return LiteOnboardingTheme(child: Builder(builder: _buildLite));
  }

  Widget _buildLite(BuildContext context) {
    final theme = Theme.of(context);
    final progress = OnboardingProgress.maybeOf(context);
    final capsule = showRuntime && (progress?.runtime ?? false) && MediaQuery.viewInsetsOf(context).bottom == 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(theme.brightness),
      child: Scaffold(
        key: const ValueKey('lite-onboarding-scaffold'),
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        if (leading case final leading?) ...[leading, const SizedBox(width: 8)],
                        if (showBrand) const Expanded(child: LiteBrandLockup(compact: true)) else const Spacer(),
                        if (progress != null) ...[
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 64,
                            child: FittedBox(
                              child: OnboardingStepBar(step: progress.step, steps: progress.steps, animate: false),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (capsule)
                    Padding(
                      key: const ValueKey('setup-capsule-slot'),
                      padding: const EdgeInsets.only(bottom: capsuleBottom),
                      child: const SetupProgressCapsule(),
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

/// The web edition's first-run palette, scoped away from the full app theme.
class LiteOnboardingTheme extends StatelessWidget {
  const LiteOnboardingTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? const Color(0xff151517) : const Color(0xfff7f8fa);
    final surface = dark ? const Color(0xff202022) : Colors.white;
    final ink = dark ? const Color(0xfff3f3f4) : const Color(0xff18181b);
    final muted = dark ? const Color(0xffa3a3aa) : const Color(0xff65656d);
    final border = dark ? const Color(0xff343437) : const Color(0xffe4e4e7);
    final surfaces = DshSurfaces.of(context);
    GlassStyle plain(GlassStyle style) => style.copyWith(
      fill: surface,
      fallbackFill: surface,
      hairline: border,
      hairlineWidth: 1,
      rim: Colors.transparent,
      blurSigma: 0,
      shadows: const [],
    );
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: theme.colorScheme.copyWith(
          primary: ink,
          onPrimary: background,
          primaryContainer: border,
          onPrimaryContainer: ink,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: border,
        ),
        textTheme: theme.textTheme
            .apply(bodyColor: ink, displayColor: ink)
            .copyWith(
              headlineMedium: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: background,
            minimumSize: const Size(64, 50),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: muted,
            minimumSize: const Size(48, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        extensions: [
          ...theme.extensions.values.where((extension) => extension is! DshSurfaces),
          surfaces.copyWith(
            backdropTop: background,
            backdropBottom: background,
            glowPrimary: Colors.transparent,
            glowSecondary: Colors.transparent,
            chrome: plain(surfaces.chrome),
            sheet: plain(surfaces.sheet),
            card: plain(surfaces.card),
            pill: plain(surfaces.pill),
            blurEnabled: false,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Shared supplied whale and wordmark, without a tile, glow, or delayed reveal.
class LiteBrandLockup extends StatelessWidget {
  const LiteBrandLockup({super.key, this.compact = false, this.dark});

  final bool compact;
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final suffix = isDark ? '-dark' : '';
    final whale = Image.asset(
      'assets/branding/whale$suffix.png',
      key: const ValueKey('lite-brand-whale'),
      width: compact ? 30 : 112,
      height: compact ? 26 : 88,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final wordmark = Image.asset(
      'assets/branding/wordmark$suffix.png',
      key: const ValueKey('lite-brand-wordmark'),
      width: compact ? 165 : 240,
      height: compact ? 20 : 28,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    return Semantics(
      label: AppInfo.name,
      image: true,
      child: compact
          // Native letterforms keep the compact permission header sharp at high DPI.
          ? HarnessWordmark(key: const ValueKey('lite-brand-wordmark'), dark: isDark)
          : Column(mainAxisSize: MainAxisSize.min, children: [whale, const SizedBox(height: 24), wordmark]),
    );
  }
}

class LiteOnboardingCard extends StatelessWidget {
  const LiteOnboardingCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('lite-onboarding-card'),
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// Thin segmented bar: one segment per step, done ones filled, the current one
/// filling in as the page arrives, the rest a quiet track.
class OnboardingStepBar extends StatelessWidget {
  const OnboardingStepBar({super.key, required this.step, required this.steps, this.animate = true});

  final int step;
  final int steps;

  /// Fill the current segment in (true) or show it already full.
  final bool animate;

  static const width = 120.0;
  static const height = 3.0;
  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final track = scheme.onSurface.withValues(alpha: scheme.brightness == Brightness.dark ? 0.14 : 0.10);
    Widget segment(double fill) => ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fill,
              child: ColoredBox(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: l10n.shellOnboardingStep(step, steps),
      child: SizedBox(
        width: width,
        child: Row(
          children: [
            for (var i = 1; i <= steps; i++) ...[
              if (i > 1) const SizedBox(width: gap),
              Expanded(
                child: i < step
                    ? segment(1)
                    : i > step
                    ? segment(0)
                    : TweenAnimationBuilder<double>(
                        tween: Tween(begin: animate ? 0 : 1, end: 1),
                        duration: AppMotion.of(context, AppMotion.slow),
                        curve: AppMotion.enter,
                        builder: (context, t, _) => segment(t),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cross-fade between first-run pages with a short horizontal drift: forward,
/// the new page comes from the right and the old one leaves left; back, the
/// other way. Each child needs its own key.
class OnboardingSwitcher extends StatelessWidget {
  const OnboardingSwitcher({super.key, required this.child, this.forward = true});

  final Widget child;
  final bool forward;

  static const _drift = 24.0;

  @override
  Widget build(BuildContext context) {
    final current = child.key;
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.page),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        // The outgoing page's animation runs 1 → 0, so "from" is where it goes.
        final incoming = child.key == current;
        final from = (incoming == forward ? 1 : -1) * _drift;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(from * (1 - animation.value), 0),
            child: Opacity(opacity: animation.value, alwaysIncludeSemantics: incoming, child: child),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Top of a first-run form step: a soft icon tile, the title, one short line.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: SizedBox.square(dimension: 44, child: Icon(icon, size: 22, color: scheme.onPrimaryContainer)),
        ),
        const SizedBox(height: 22),
        Text(title, style: theme.textTheme.headlineMedium),
        if (message case final message?) ...[
          const SizedBox(height: 6),
          Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// One plain fact on a first-run step: a 20dp line icon and a short line.
class OnboardingFact extends StatelessWidget {
  const OnboardingFact({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;

  /// Icon and text in one colour (a warning); null: the usual pair.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
