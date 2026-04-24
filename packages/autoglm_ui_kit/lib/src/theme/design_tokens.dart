import 'package:flutter/material.dart';

/// Design tokens for the AutoGLM project, synchronized with DESIGN.md.
class AppSpacing {
  /// No spacing.
  static const double none = 0;

  /// Extra small spacing (4px).
  static const double xs = 4;

  /// Small spacing (8px).
  static const double sm = 8;

  /// Medium spacing (16px).
  static const double md = 16;

  /// Large spacing (24px).
  static const double lg = 24;

  /// Extra large spacing (32px).
  static const double xl = 32;

  /// Helper for common medium edge insets.
  static const EdgeInsets edgeInsetsMd = EdgeInsets.all(md);

  /// Helper for common small edge insets.
  static const EdgeInsets edgeInsetsSm = EdgeInsets.all(sm);
}

/// Border radius tokens for the AutoGLM project.
class AppRadius {
  /// No radius.
  static const double none = 0;

  /// Small radius (4px).
  static const double sm = 4;

  /// Medium radius (8px).
  static const double md = 8;

  /// Large radius (12px).
  static const double lg = 12;

  /// Full/Circular radius (9999px).
  static const double full = 9999;

  /// Small border radius.
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));

  /// Medium border radius.
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));

  /// Large border radius.
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
}

/// Color tokens for the AutoGLM project.
class AppColors {
  /// The seed color for theme generation.
  static const Color seed = Color(0xFF3F51B5); // Colors.indigo
}
