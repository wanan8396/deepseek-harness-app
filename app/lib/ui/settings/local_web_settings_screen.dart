import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/web_appearance_state.dart';
import '../../state/web_connection_state.dart';
import '../access/lite_permissions_page.dart';
import '../theme/app_icons.dart';
import '../shell/harness_wordmark.dart';
import 'connect_computer_page.dart';

/// Plain, opaque surfaces matching the web client; no glass or backdrop blur.
class WebSettingsFrame extends ConsumerWidget {
  const WebSettingsFrame({super.key, required this.title, required this.child, this.brand = false});

  final String title;
  final Widget child;
  final bool brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context);
    final brightness = ref.watch(webAppearanceProvider) ?? base.brightness;
    final dark = brightness == Brightness.dark;
    // Match the web settings panel, including controls, instead of retaining
    // the full app's blue primary/selected states inside a neutral page.
    // Resolved from dsh-client-ui-theme 0.2.2-rc.1's layer-2, label,
    // border-l2 and sidebar-nav-item-active tokens (light / dark).
    final surface = dark ? const Color(0xFF2C2C2E) : Colors.white;
    final background = surface;
    final ink = dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);
    final muted = dark ? const Color(0xFFCFD3D6) : const Color(0xFF61666B);
    final line = dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000);
    final selected = dark ? const Color(0xFF43454A) : const Color(0xFFEBEEF2);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Theme(
      data: base.copyWith(
        brightness: brightness,
        scaffoldBackgroundColor: background,
        colorScheme: base.colorScheme.copyWith(
          brightness: brightness,
          primary: ink,
          onPrimary: surface,
          primaryContainer: selected,
          onPrimaryContainer: ink,
          secondary: ink,
          onSecondary: surface,
          secondaryContainer: selected,
          onSecondaryContainer: ink,
          surface: surface,
          surfaceTint: Colors.transparent,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: line,
          outlineVariant: line,
        ),
        textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
        iconTheme: base.iconTheme.copyWith(color: ink),
        dividerColor: line,
        listTileTheme: ListTileThemeData(
          textColor: ink,
          iconColor: muted,
          selectedColor: ink,
          selectedTileColor: selected,
          shape: shape,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: surface, elevation: 0, shape: shape),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: BorderSide(color: line),
            shape: shape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: ink, shape: shape),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ink),
          ),
          labelStyle: TextStyle(color: muted),
          floatingLabelStyle: TextStyle(color: muted),
          hintStyle: TextStyle(color: muted),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: ink,
          selectionColor: ink.withValues(alpha: 0.18),
          selectionHandleColor: ink,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: background,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: brand ? HarnessWordmark(dark: dark) : Text(title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: line),
          ),
        ),
        body: SafeArea(top: false, child: child),
      ),
    );
  }
}

/// Selects the webpage's connection only; all web settings stay in the webpage.
class LocalWebSettingsScreen extends ConsumerStatefulWidget {
  const LocalWebSettingsScreen({super.key});

  @override
  ConsumerState<LocalWebSettingsScreen> createState() => _LocalWebSettingsScreenState();
}

class _LocalWebSettingsScreenState extends ConsumerState<LocalWebSettingsScreen> {
  bool _busy = false;

  Future<void> _selectLocal() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(webConnectionProvider.notifier).setLocal();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.commonConnectionFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connection = ref.watch(webConnectionProvider);
    final computer = connection.mode == WebConnectionMode.computer;
    final enabled = connection.loaded && !_busy;
    return WebSettingsFrame(
      title: l10n.featuresScheduleRunLocation,
      child: ListView(
        key: const ValueKey('local-web-settings-list'),
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            key: const ValueKey('local-web-connect-local'),
            leading: const Icon(Icons.phone_android, size: 20),
            title: Text(l10n.commonThisPhone),
            selected: !computer,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!computer) const Icon(Icons.check, size: 20),
                IconButton(
                  key: const ValueKey('local-web-permissions'),
                  tooltip: l10n.accessRootPermissions,
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 22),
                  onPressed: enabled
                      ? () => unawaited(
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (pageContext) =>
                                  LitePermissionsPage(settings: true, onDone: () => Navigator.of(pageContext).pop()),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            onTap: enabled ? () => unawaited(_selectLocal()) : null,
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('local-web-connect-computer'),
            leading: const Icon(AppIcons.remoteHosts, size: 20),
            title: Text(l10n.remotePairComputer),
            subtitle: computer ? Text(Uri.tryParse(connection.computerUrl ?? '')?.host ?? '') : null,
            selected: computer,
            trailing: Icon(computer ? Icons.check : Icons.chevron_right, size: 20),
            onTap: enabled
                ? () => unawaited(
                    Navigator.of(context)
                        .push<void>(MaterialPageRoute<void>(builder: (_) => const ConnectComputerPage())),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
