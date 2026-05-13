import 'package:flutter/material.dart';

class AppTheme {
  static const _indigoSeed = Color.fromARGB(255, 140, 141, 146);

  static final light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _indigoSeed,
    brightness: Brightness.light,
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _indigoSeed,
    brightness: Brightness.dark,
  );
}
