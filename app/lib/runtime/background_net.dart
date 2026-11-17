import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'runtime_bridge.dart';
import 'runtime_state.dart';

/// The phone maker and the app's name in system settings; null without the
/// native side. Permission pages read this without observing conversations.
final backgroundSettingsProvider = FutureProvider<BackgroundSettingsInfo?>(
  (ref) => ref.watch(runtimeBridgeProvider).backgroundSettings(),
);
