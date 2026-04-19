import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// Devices landing page.
class DevicesPage extends StatelessWidget {
  /// Creates a [DevicesPage].
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.devices)),
      body: Center(child: Text(t.page.devices.placeholder)),
    );
  }
}
