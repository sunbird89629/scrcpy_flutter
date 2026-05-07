import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.sidebarBackground,
  });

  final Color? sidebarBackground;

  @override
  AppColors copyWith({Color? sidebarBackground}) {
    return AppColors(
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      sidebarBackground: Color.lerp(sidebarBackground, other.sidebarBackground, t),
    );
  }
}

class AppTheme {
  static const _indigoSeed = Color(0xFF3F51B5);

  static final light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _indigoSeed,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF9FAFB),
    extensions: const [
      AppColors(
        sidebarBackground: Color(0xFFF3F4F6),
      ),
    ],
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _indigoSeed,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0D0D0D),
    extensions: const [
      AppColors(
        sidebarBackground: Color(0xFF1A1A1A),
      ),
    ],
  );
}
