import 'package:flutter/material.dart';

import '../../state/app_info.dart';

/// Native glyphs stay sharp at the phone's physical pixel density. Only the
/// whale is a raster asset; the original 245x35 image is not enlarged as text.
class HarnessWordmark extends StatelessWidget {
  const HarnessWordmark({super.key, this.dark});

  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);
    final ground = isDark ? const Color(0xFF151517) : Colors.white;
    return Semantics(
      label: AppInfo.name,
      image: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                isDark ? 'assets/branding/whale-dark.png' : 'assets/branding/whale.png',
                width: 29,
                height: 26,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 8),
              Text(
                'deepseek',
                style: TextStyle(color: ink, fontSize: 25, height: 1, fontWeight: FontWeight.w700, letterSpacing: -1),
              ),
              const SizedBox(width: 7),
              DecoratedBox(
                decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(3)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  child: Text(
                    'HARNESS',
                    style: TextStyle(
                      color: ground,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
