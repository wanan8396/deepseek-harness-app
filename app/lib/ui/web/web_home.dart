import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../links/app_links.dart';
import '../../links/launcher_entries.dart';
import '../../links/share_intake.dart';
import '../../state/compose_inbox.dart';
import '../../state/selection_state.dart';
import '../../state/settings_state.dart';
import '../../state/ui_mode_state.dart';
import '../../state/web_connection_state.dart';
import '../notify/chat_alert_host.dart';
import 'local_web_screen.dart';
import 'web_handle.dart';
import 'web_target.dart';
import 'web_view_page.dart';

/// Maximum text/file payload handed to the webpage's composer in one paste.
const maxWebComposeBytes = 16 * 1024 * 1024;

/// Local integrations and computer pages have separate lifetimes and requests.
class WebHome extends ConsumerWidget {
  const WebHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(webConnectionProvider);
    if (!connection.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final url = connection.computerUrl;
    if (connection.mode == WebConnectionMode.computer && url != null) {
      return _ComputerWebHome(key: ValueKey(url), url: Uri.parse(url));
    }
    return const _LocalWebHome();
  }
}

class _ComputerWebHome extends ConsumerStatefulWidget {
  const _ComputerWebHome({super.key, required this.url});
  final Uri url;

  @override
  ConsumerState<_ComputerWebHome> createState() => _ComputerWebHomeState();
}

class _ComputerWebHomeState extends ConsumerState<_ComputerWebHome> {
  final _link = DshWebLink();

  @override
  void initState() {
    super.initState();
    // Never route a pending phone-owned share or session into the computer page.
    ref.listenManual(webOpenProvider, (_, request) {
      if (request == null) return;
      ref.read(webOpenProvider.notifier).taken(request);
      final target = request.target;
      if (request.compose != null || target.sessionId != null || target.settings == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        unawaited(_link.open(DshWebTarget(settings: target.settings)));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final phoneLayout = ref.watch(settingsProvider.select((s) => s.webPhoneLayout));
    return WebViewPage(
      key: ValueKey((widget.url, phoneLayout)),
      url: widget.url,
      computerWeb: true,
      title: context.l10n.webTitle,
      subtitle: widget.url.host,
      allowOpenExternal: true,
      reloadAfterBackground: const Duration(seconds: 60),
      dshWeb: true,
      phoneLayout: phoneLayout,
      leading: (size) => WebHandleButton(size: size),
      leadingAtBottom: true,
      root: true,
      link: _link,
    );
  }
}

class _LocalWebHome extends ConsumerStatefulWidget {
  const _LocalWebHome();

  @override
  ConsumerState<_LocalWebHome> createState() => _LocalWebHomeState();
}

class _LocalWebHomeState extends ConsumerState<_LocalWebHome> {
  final _link = DshWebLink();
  String? _webSession;

  @override
  void initState() {
    super.initState();
    ref.listenManual(currentSessionProvider, (_, next) {
      if (next == null || next == _webSession) return;
      _webSession = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_link.open(DshWebTarget(sessionId: next)));
      });
    });
    ref.listenManual(webOpenProvider, (_, request) {
      if (request != null) _take(request);
    }, fireImmediately: true);
  }

  void _onSession(String? id) {
    if (id == _webSession) return;
    _webSession = id;
    ref.read(currentSessionProvider.notifier).select(id);
  }

  void _take(WebOpenRequest request) {
    ref.read(webOpenProvider.notifier).taken(request);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      unawaited(_open(request));
    });
  }

  Future<void> _open(WebOpenRequest request) async {
    await _link.open(request.target);
    final compose = request.compose;
    if (compose == null) return;
    final problems = [...compose.problems];
    final files = <({String name, String? type, String base64})>[];
    var bytes = 0;
    for (final attachment in compose.attachments) {
      bytes += attachment.bytes.length;
      if (bytes > maxWebComposeBytes) {
        problems.add(appL10n.webAttachmentTooLarge);
        break;
      }
      files.add((name: attachment.name, type: attachment.mediaType, base64: base64Encode(attachment.bytes)));
    }
    final text = compose.text.trim();
    if (text.isEmpty && files.isEmpty) return _tell(problems);
    final result = await _link.compose(text, files: files);
    if (text.isNotEmpty && !result.text) {
      await Clipboard.setData(ClipboardData(text: text));
      problems.insert(0, appL10n.webTextCopied);
    }
    if (files.length > result.files) problems.add(appL10n.webAttachmentFailed);
    _tell(problems);
  }

  void _tell(List<String> problems) {
    if (problems.isEmpty || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problems.first)));
  }

  @override
  Widget build(BuildContext context) => ChatAlertHost(
    child: Stack(
      fit: StackFit.expand,
      children: [
        LocalWebScreen(
          handle: (size) => WebHandleButton(size: size),
          handleAtBottom: true,
          link: _link,
          onSession: _onSession,
        ),
        const WebEntryHost(),
      ],
    ),
  );
}

/// Android share/open-with, launcher shortcuts and the tile feed the local page.
class WebEntryHost extends ConsumerStatefulWidget {
  const WebEntryHost({super.key});

  @override
  ConsumerState<WebEntryHost> createState() => _WebEntryHostState();
}

class _WebEntryHostState extends ConsumerState<WebEntryHost> {
  StreamSubscription<IncomingShare>? _shares;
  StreamSubscription<LauncherEntry>? _entries;
  StreamSubscription<Uri>? _files;

  @override
  void initState() {
    super.initState();
    _shares = ref.read(shareIntakeProvider).shares.listen((share) => unawaited(_onShare(share)));
    _entries = ref.read(launcherBridgeProvider).entries.listen((entry) => unawaited(_onEntry(entry)));
    _files = ref.read(appLinksProvider).links.listen((uri) => unawaited(_onLocalLink(uri)));
    ref.listenManual(recentShortcutsProvider, (_, recents) {
      if (recents != null) unawaited(ref.read(launcherBridgeProvider).setRecent(recents));
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    unawaited(_shares?.cancel());
    unawaited(_entries?.cancel());
    unawaited(_files?.cancel());
    super.dispose();
  }

  Future<void> _onShare(IncomingShare share) async {
    final request = await ComposeRequest.fromShare(share, maxBytes: maxWebComposeBytes);
    if (mounted) _compose(request);
  }

  Future<void> _onEntry(LauncherEntry entry) async {
    switch (entry) {
      case NewChatEntry():
        // Native dictation is retired; the webpage starts the new conversation.
        if (mounted) _compose(null);
      case OpenChatEntry(:final sessionId):
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        ref.read(currentSessionProvider.notifier).select(sessionId);
    }
  }

  Future<void> _onLocalLink(Uri uri) async {
    try {
      if (await _onFile(uri)) return;
    } catch (_) {
      // Never log shared file contents or private paths.
    }
    if (!mounted) return;
    final file = uri.scheme == 'file' || uri.scheme == AppLinks.unreadableScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(file ? context.l10n.stateFileOpenFailed : context.l10n.stateLinkOpenFailed)),
    );
  }

  Future<bool> _onFile(Uri uri) async {
    if (uri.scheme != 'file') return false;
    final request = await ComposeRequest.fromFile(uri.toFilePath(), maxBytes: maxWebComposeBytes);
    if (!mounted) return false;
    _compose(request);
    return true;
  }

  void _compose(ComposeRequest? request) {
    if (mounted) ref.read(webOpenProvider.notifier).request(const DshWebTarget(newSession: true), compose: request);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
