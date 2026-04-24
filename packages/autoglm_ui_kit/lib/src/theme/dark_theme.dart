import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Dark theme used across all AutoGLM Flutter apps.
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
  ),
  cardTheme: CardTheme(
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
    elevation: 0, // Dark mode often uses less elevation
  ),
);
