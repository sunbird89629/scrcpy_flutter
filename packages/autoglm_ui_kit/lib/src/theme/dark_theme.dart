import 'package:autoglm_ui_kit/src/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Dark theme used across all AutoGLM Flutter apps.
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
  ),
  cardTheme: const CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
    elevation: 0, // Dark mode often uses less elevation
  ),
);
