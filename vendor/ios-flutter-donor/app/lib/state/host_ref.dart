import 'dart:convert';

import '../l10n/l10n.dart';

/// The three kinds of DSH host the app can talk to.
enum HostKind { local, ssh, relay }

/// Identifies a host: the on-device engine, a saved SSH host, or a relay
/// (ds-harness-remote) device. Equality is by kind + id; [name] is only a
/// cached display name for relay hosts (their list lives on the server).
class HostRef {
  const HostRef._(this.kind, this.id, [this.name]);

  static const local = HostRef._(HostKind.local, 'local');

  const HostRef.ssh(String id) : this._(HostKind.ssh, id);

  const HostRef.relay(String id, {String? name}) : this._(HostKind.relay, id, name);

  final HostKind kind;
  final String id;
  final String? name;

  bool get isLocal => kind == HostKind.local;

  String encode() => jsonEncode({'kind': kind.name, 'id': id, if (name != null) 'name': name});

  static HostRef decode(String? raw) {
    if (raw == null || raw.isEmpty) return local;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return local;
      final id = map['id'];
      final name = map['name'];
      if (id is! String || id.isEmpty) return local;
      return switch (map['kind']) {
        'ssh' => HostRef.ssh(id),
        'relay' => HostRef.relay(id, name: name is String ? name : null),
        _ => local,
      };
    } catch (_) {
      return local;
    }
  }

  @override
  bool operator ==(Object other) => other is HostRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'HostRef(${kind.name}:$id)';
}

/// Chat-header label for a connection: "本机", "电脑 · SSH", "家里的 Mac · 远程".
String hostLabel(HostKind kind, String? name) => switch (kind) {
  HostKind.local => appL10n.commonThisPhone,
  HostKind.ssh => '${_short(name ?? appL10n.stateSshHost)} · SSH',
  HostKind.relay => appL10n.stateHostRemoteLabel(_short(name ?? appL10n.commonRemoteHost)),
};

String _short(String name) {
  final t = name.trim();
  return t.length <= 14 ? t : '${t.substring(0, 13)}…';
}

