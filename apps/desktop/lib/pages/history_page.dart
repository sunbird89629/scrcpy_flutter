import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// History landing page.
class HistoryPage extends StatelessWidget {
  /// Creates a [HistoryPage].
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.history)),
      body: Center(child: Text(t.page.history.placeholder)),
    );
  }
}
