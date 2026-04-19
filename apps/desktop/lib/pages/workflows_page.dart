import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// Workflows landing page.
class WorkflowsPage extends StatelessWidget {
  /// Creates a [WorkflowsPage].
  const WorkflowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.workflows)),
      body: Center(child: Text(t.page.workflows.placeholder)),
    );
  }
}
