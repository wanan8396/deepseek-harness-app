import 'package:flutter/material.dart';

import '../access/lite_permissions_page.dart';

/// First-run permissions share the same explicit controls as phone settings.
class AccessStepPage extends StatelessWidget {
  const AccessStepPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => LitePermissionsPage(onDone: onDone);
}
