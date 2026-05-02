import 'package:flutter/material.dart';

/// Design tokens for the AutoGLM project, synchronized with DESIGN.md.
class AppSpacing {
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const EdgeInsets edgeInsetsMd = EdgeInsets.all(md);
  static const EdgeInsets edgeInsetsSm = EdgeInsets.all(sm);
}

class AppRadius {
  static const double none = 0;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double full = 9999;

  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
}

class AppColors {
  static const Color seed = Color(0xFF3F51B5);
}
