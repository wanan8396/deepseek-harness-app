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
    final mark = Image.asset(
      dark ? 'assets/branding/whale-dark.png' : 'assets/branding/whale.png',
      width: size * 0.65,
      height: size * 0.65,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    // A disabled handle is decoration, not a control: it must not swallow a tap
    // meant for the webpage underneath it (the sidebar's archive action sits
    // exactly here once it is open).
    if (onSidebar == null) {
      return SizedBox.square(dimension: size, child: Center(child: mark));
    }
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
              child: Center(child: mark),
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
    // Only the two controls take the touch. A box spanning the row would, even
    // at `Colors.transparent`, because `ColoredBox` hit-tests as opaque: every
    // tap that landed on the webpage under this band (the sidebar's archive
    // action, most of all) reached an invisible layer instead of its own
    // control. Nothing is laid out across the row here, so the space between
    // the buttons passes straight through to the page, and a button with no
    // handler (`onSidebar == null`) passes through as well.
    final body = Padding(
      padding: EdgeInsets.fromLTRB(padding.left + edge, 0, padding.right + edge, bottomInset(padding.bottom)),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(child: handle(buttonSize)),
            ),
            const Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: WebConnectionButton()),
            ),
          ],
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
