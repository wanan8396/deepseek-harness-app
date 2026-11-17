import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/web_connection_state.dart';
import '../../state/web_appearance_state.dart';
import '../settings/local_web_settings_screen.dart';

/// The existing whale control opens the webpage's conversations/workspaces.
class WebHandleButton extends StatelessWidget {
  const WebHandleButton({super.key, required this.size, this.onSidebar});

  final double size;
  final VoidCallback? onSidebar;

  static String get tooltip => appL10n.webChatsWorkspaces;

  @override
  Widget build(BuildContext context) {
    final tooltip = context.l10n.webChatsWorkspaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onSidebar,
              child: Center(
                child: Image.asset(
                  dark ? 'assets/branding/whale-dark.png' : 'assets/branding/whale.png',
                  width: size * 0.65,
                  height: size * 0.65,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom controls remain outside the webpage's reserved content area.
class WebBottomHandle extends ConsumerWidget {
  const WebBottomHandle({super.key, required this.handle, this.background});

  static const height = 48.0;
  static const buttonSize = 40.0;
  static const edge = 12.0;
  static const pageOverlap = 12.0;

  static double bottomInset(double systemBottom) => systemBottom < edge ? edge : systemBottom;

  final Widget Function(double size) handle;
  final Color? background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = MediaQuery.viewPaddingOf(context);
    final body = ColoredBox(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding.left + edge, 0, padding.right + edge, bottomInset(padding.bottom)),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [handle(buttonSize), const WebConnectionButton()],
          ),
        ),
      ),
    );
    final base = Theme.of(context);
    final brightness = ref.watch(webAppearanceProvider) ?? base.brightness;
    final dark = brightness == Brightness.dark;
    return Theme(
      data: base.copyWith(
        brightness: brightness,
        colorScheme: base.colorScheme.copyWith(
          brightness: brightness,
          onSurface: dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115),
          onSurfaceVariant: dark ? const Color(0xFFCFD3D6) : const Color(0xFF61666B),
        ),
      ),
      child: body,
    );
  }
}

/// The phone shell's local/computer connection selector.
class WebConnectionButton extends ConsumerWidget {
  const WebConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final computer = ref.watch(webConnectionProvider.select((s) => s.mode == WebConnectionMode.computer));
    return TextButton(
      key: const ValueKey('web-connection-switch'),
      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: () => unawaited(
        Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const LocalWebSettingsScreen())),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(computer ? context.l10n.remotePairComputer : context.l10n.commonThisPhone),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 16),
        ],
      ),
    );
  }
}
