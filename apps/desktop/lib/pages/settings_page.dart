import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// Settings page placeholder; real content is wired in Task 12.
class SettingsPage extends StatelessWidget {
  /// Creates a [SettingsPage].
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.settings)),
      body: const Center(child: Text('Settings — wired in Task 12')),
    );
  }
}
