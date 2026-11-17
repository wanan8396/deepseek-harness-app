import 'json.dart';
import 'models.dart';

/// The full state carried by a `replace` frame of `workspace/follow` for a
/// non-owner Peer. The shared update parser keeps it as unknown until here.
WorkspaceBaseline? workspaceReplaceFrame(WorkspaceUpdate update) {
  if (update is! UnknownWorkspaceUpdate || update.raw['type'] != 'replace') return null;
  final value = asMapOrEmpty(update.raw['value']);
  return WorkspaceBaseline(
    asListOrEmpty(value['items']).map(Workspace.fromJson).toList(growable: false),
    asStringList(value['archivedSessionIds']),
    asStringList(value['pinnedSessionIds']),
  );
}
