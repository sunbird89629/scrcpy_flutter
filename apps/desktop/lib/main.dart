import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocale();
  runApp(
    TranslationProvider(
      child: BootApp(router: createRouter()),
    ),
  );
}

/// Root application widget that wires [MaterialApp.router] to the
/// provided [GoRouter] and applies the light/dark themes from
/// `autoglm_ui_kit`.
class BootApp extends StatelessWidget {
  /// Creates a [BootApp] with the given [router].
  const BootApp({required this.router, super.key});

  /// The router driving navigation for this app.
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AutoGLM',
      theme: lightTheme,
      darkTheme: darkTheme,
      routerConfig: router,
    );
  }
}
