import 'package:flutter/material.dart';

/// Dark theme used across all AutoGLM Flutter apps.
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.dark,
  ),
);
