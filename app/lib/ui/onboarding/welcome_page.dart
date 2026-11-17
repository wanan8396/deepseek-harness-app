import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'onboarding_scaffold.dart';

/// First screen on a fresh install, using the phone shell's existing branding.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return OnboardingScaffold(
      showBrand: false,
      children: [
        const Spacer(flex: 3),
        const Center(child: LiteBrandLockup()),
        const SizedBox(height: 28),
        Text(
          l10n.shellWelcomeMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w600, height: 1.35),
        ),
        const Spacer(flex: 4),
        FilledButton(key: const ValueKey('lite-welcome-start'), onPressed: onStart, child: Text(l10n.shellGetStarted)),
        const SizedBox(height: 16),
      ],
    );
  }
}
