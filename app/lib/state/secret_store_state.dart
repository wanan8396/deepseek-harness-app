import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secret_store.dart';

/// Keystore-backed in the app; tests override with [MemorySecretStore].
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());
