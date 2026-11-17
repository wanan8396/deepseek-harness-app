import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// The original looping cover supplied for the phone shell, using Flutter's
/// animated codec without a progress indicator or artificial minimum delay.
class StartupCover extends StatelessWidget {
  const StartupCover({super.key});

  static const asset = 'assets/branding/startup-cover.gif';

  // Equal AssetImage keys share Flutter's cached image stream while it is live.
  static const image = AssetImage(asset);

  /// The page colour behind the cover, shared by all startup stages.
  static const lightBackground = Color(0xFFF7F8FA);
  static const darkBackground = Color(0xFF151517);

  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBackground : lightBackground;

  /// Tallest the picture is drawn, in logical pixels.
  static const maxHeight = 520.0;

  /// Space taken below the picture for the slogan and its gap.
  static const sloganSpace = 52.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      // Only the platform's own reduce-motion pauses the animation. The app's
      // automatic light-performance mode used to reach MediaQuery and froze the
      // GIF on its closed-eye first frame.
      final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
      final height = math.min(StartupCover.maxHeight, math.max(64.0, constraints.maxHeight - StartupCover.sloganSpace));
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaQuery(
            data: media.copyWith(disableAnimations: reduceMotion),
            child: Image(
              image: StartupCover.image,
              key: const ValueKey('local-web-startup-cover'),
              height: height,
              width: height * 2 / 3,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.localWebExploreBeyond,
            key: const ValueKey('local-web-startup-tagline'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 4, height: 1.35),
          ),
        ],
      );
    },
  );
}

/// [StartupCover] on the shared page colour, centred exactly as every stage
/// draws it. Use this instead of assembling background + padding per screen.
class StartupStage extends StatelessWidget {
  const StartupStage({super.key, this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: StartupCover.backgroundOf(context),
    child: SafeArea(
      child: Padding(padding: padding, child: const Center(child: StartupCover())),
    ),
  );
}
