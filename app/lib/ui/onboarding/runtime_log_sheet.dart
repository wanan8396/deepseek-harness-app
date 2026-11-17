import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_state.dart';
import '../common/app_sheet.dart';
import '../engine/log_view.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// The setup log reads top to bottom, following new lines only at the tail.
/// Unlike a reversed terminal list, a short log leaves no blank area above it.
class RuntimeLogSheet extends ConsumerStatefulWidget {
  const RuntimeLogSheet({super.key, this.title});

  final String? title;

  @override
  ConsumerState<RuntimeLogSheet> createState() => _RuntimeLogSheetState();
}

class _RuntimeLogSheetState extends ConsumerState<RuntimeLogSheet> {
  final _scroll = ScrollController();
  bool _tailScheduled = false;

  @override
  void initState() {
    super.initState();
    _followTail();
  }

  void _followTail() {
    if (_tailScheduled) return;
    _tailScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tailScheduled = false;
      if (!mounted || !_scroll.hasClients || _scroll.position.isScrollingNotifier.value) return;
      final position = _scroll.position;
      if ((position.maxScrollExtent - position.pixels).abs() <= 0.5) return;
      _scroll.jumpTo(position.maxScrollExtent);
      // Lazy, wrapped rows refine the extent as they are laid out. Settle at
      // the actual tail, not just the first estimated maximum.
      _followTail();
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(localRuntimeLogsProvider, (_, _) {
      if (!_scroll.hasClients || _scroll.position.extentAfter <= 24) _followTail();
    });
    final logs = ref.watch(localRuntimeLogsProvider);
    final colors = DshColors.of(context);
    final l10n = context.l10n;
    final base = AppType.monoSmall(color: colors.codeWellFg);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              widget.title ?? l10n.shellEngineLogs,
              actions: [
                SheetIconButton(
                  tooltip: l10n.commonCopy,
                  icon: AppIcons.copy,
                  onPressed: logs.isEmpty ? null : () => LogActions.copy(context, logs),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colors.codeWellBg,
                    shape: AppShape.outlined(colors.codeWellBorder, width: 0.5),
                  ),
                  child: ClipRSuperellipse(
                    borderRadius: AppShape.radiusMd,
                    child: logs.isEmpty
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(l10n.phoneLogEmpty, style: base.copyWith(color: colors.textTertiary)),
                            ),
                          )
                        : SelectionArea(
                            child: Scrollbar(
                              controller: _scroll,
                              child: ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                itemCount: logs.length,
                                itemBuilder: (context, index) {
                                  final line = stripAnsi(logs[index]);
                                  final lower = line.toLowerCase();
                                  final color = line.startsWith('[dsh-app]')
                                      ? Theme.of(context).colorScheme.primary
                                      : lower.contains('error') ||
                                            lower.contains('fatal') ||
                                            lower.contains('exception')
                                      ? colors.danger
                                      : colors.codeWellFg;
                                  return Text(line, style: base.copyWith(color: color));
                                },
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
