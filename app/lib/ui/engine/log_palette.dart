import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The existing log card colors, independent of the retired terminal emulator.
@immutable
class LogPalette {
  LogPalette._(AppAccent palette)
    : background = NeutralTones.forAccent(palette).terminal,
      accent = _softAccent(palette);

  static LogPalette of(BuildContext context) => LogPalette._(DshSurfaces.of(context).accent);

  final Color background;
  final Color accent;

  static const _mistSoft = Color(0xFF9DB4FF);

  static Color _softAccent(AppAccent palette) {
    if (palette == AppAccent.mist) return _mistSoft;
    final base = Oklch.fromColor(AppAccent.mist.seedDark);
    final own = Oklch.fromColor(palette.seedDark);
    return retint(_mistSoft, hueShift: own.h - base.h, chromaScale: own.c / base.c);
  }
}
