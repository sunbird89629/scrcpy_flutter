import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Derived: the current effective ThemeMode. Defaults to system while settings
/// are still loading.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final asyncSettings = ref.watch(settingsProvider);
  return asyncSettings.maybeWhen(
    data: (s) => s.themeMode,
    orElse: () => ThemeMode.system,
  );
});
