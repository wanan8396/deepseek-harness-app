import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active webpage's appearance, not a second persisted theme preference.
/// Connection routes follow this while the webpage owns the actual setting.
final webAppearanceProvider = NotifierProvider<WebAppearanceController, Brightness?>(WebAppearanceController.new);

class WebAppearanceController extends Notifier<Brightness?> {
  @override
  Brightness? build() => null;

  void report(String value) {
    final next = switch (value) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => null,
    };
    if (next != null && state != next) state = next;
  }
}
