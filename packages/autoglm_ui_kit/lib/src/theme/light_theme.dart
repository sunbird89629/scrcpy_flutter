import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Light theme used across all AutoGLM Flutter apps.
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.light,
  ),
  cardTheme: CardTheme(
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
    elevation: 1,
  ),
);
