import 'package:flutter/material.dart';

/// Placeholder application shell.
///
/// Renders the current router [child]. The full shell (with navigation
/// rail, etc.) is introduced in Task 11.
class AppShell extends StatelessWidget {
  /// Creates an [AppShell] that wraps the current route [child].
  const AppShell({required this.child, super.key});

  /// The current route content rendered by the enclosing shell route.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: child);
  }
}
