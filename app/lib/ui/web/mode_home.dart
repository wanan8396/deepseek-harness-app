import 'package:flutter/material.dart';

import 'web_home.dart';

/// The phone shell always hosts the official DSH webpage.
class ModeHome extends StatelessWidget {
  const ModeHome({super.key});

  @override
  Widget build(BuildContext context) => const WebHome();
}
