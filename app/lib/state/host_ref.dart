import 'dart:convert';

/// The phone's official local service identity used by native integrations.
class HostRef {
  const HostRef._();

  static const local = HostRef._();

  String get key => 'local:local';

  String encode() => jsonEncode({'kind': 'local', 'id': 'local'});

  /// Only the current explicitly bound local identity is accepted.
  static HostRef? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map && value['kind'] == 'local' && value['id'] == 'local' ? local : null;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'HostRef(local)';
}
