import 'package:autoglm_app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
  cardTheme: const CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
    elevation: 1,
  ),
);
