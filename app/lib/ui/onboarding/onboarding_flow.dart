import 'package:flutter/material.dart';

import 'access_step.dart';
import 'onboarding_scaffold.dart';
import 'runtime_choice.dart';
import 'runtime_setup_page.dart';
import 'welcome_page.dart';

/// First-run pages owned by the phone shell, not the webpage's model settings.
enum OnboardingStep { welcome, runtime, access, finishing }

class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({
    super.key,
    required this.step,
    required this.onWelcomeDone,
    required this.onRuntimeDone,
    this.chooseRuntime = false,
    this.onComputer,
    this.onLocal,
    this.onAccessDone,
    this.onFinished,
    this.beside = false,
  });

  final OnboardingStep step;
  final VoidCallback onWelcomeDone;
  final VoidCallback onRuntimeDone;
  final bool chooseRuntime;
  final VoidCallback? onComputer;
  final VoidCallback? onLocal;
  final VoidCallback? onAccessDone;
  final VoidCallback? onFinished;
  final bool beside;

  @override
  Widget build(BuildContext context) {
    final Widget page = switch (step) {
      OnboardingStep.welcome => WelcomePage(onStart: onWelcomeDone),
      OnboardingStep.runtime when chooseRuntime && onLocal != null => RuntimeChoiceView(
        onLocal: onLocal!,
        onComputer: onComputer,
      ),
      OnboardingStep.runtime => RuntimeSetupPage(onDone: onRuntimeDone),
      OnboardingStep.access => AccessStepPage(onDone: onAccessDone ?? () {}),
      OnboardingStep.finishing => RuntimeSetupPage(onDone: onFinished ?? onRuntimeDone, waiting: true),
    };
    // Runtime remains the first of the existing two visible setup segments.
    const steps = [OnboardingStep.runtime, OnboardingStep.access];
    final index = steps.indexOf(step);
    final content = KeyedSubtree(
      key: ValueKey(step),
      child: index < 0
          ? page
          : OnboardingProgress(
              step: index + 1,
              steps: steps.length,
              runtime: beside && step != OnboardingStep.runtime,
              child: page,
            ),
    );
    return LiteOnboardingTheme(child: content);
  }
}
