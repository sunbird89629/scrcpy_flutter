import 'package:autoglm_ui_kit/src/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Light theme used across all AutoGLM Flutter apps.
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.seed,
  ),
  cardTheme: const CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
    elevation: 1,
  ),
);
