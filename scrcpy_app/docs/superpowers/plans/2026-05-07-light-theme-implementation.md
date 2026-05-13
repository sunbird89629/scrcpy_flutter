# Light Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a "Soft & Accessible" light theme for ScrcpyApp with Indigo as the primary accent color.

**Architecture:** Use Material 3's `ColorScheme.fromSeed` for the base theme and a `ThemeExtension` to manage custom surface colors (like the sidebar background). Update the root `MaterialApp` to support both light and dark themes and default to system settings.

**Tech Stack:** Flutter (Material 3), Dart.

---

### Task 1: Define Light Theme Extension and Data

**Files:**
- Create: `lib/theme/app_theme.dart`
- Modify: `lib/scrcpy_app.dart`

- [ ] **Step 1: Create `lib/theme/app_theme.dart` with custom color extension**

```dart
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "feat: define AppTheme and custom AppColors extension"
```

---

### Task 2: Update `ScrcpyApp` to support Light Mode

**Files:**
- Modify: `lib/scrcpy_app.dart`

- [ ] **Step 1: Refactor `ScrcpyApp` to use `AppTheme`**

```dart
import 'package:flutter/material.dart';
import 'package:scrcpy_app/home_page.dart';
import 'package:scrcpy_app/theme/app_theme.dart';

class ScrcpyApp extends StatelessWidget {
  const ScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrcpyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system, // Allow system to decide or user later
      home: const HomePage(),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/scrcpy_app.dart
git commit -m "feat: enable light theme and system theme mode in ScrcpyApp"
```

---

### Task 3: Update `HomePage` for Shaded Layers

**Files:**
- Modify: `lib/home_page.dart`

- [ ] **Step 1: Update `HomePage` to use `sidebarBackground` from extension**

```dart
// Find where the sidebar/left panel is built and use:
// color: Theme.of(context).extension<AppColors>()!.sidebarBackground,
```
*(Need to read `lib/home_page.dart` first to get exact lines, but the plan is to use the extension color for the left-side list area)*

- [ ] **Step 2: Commit**

```bash
git add lib/home_page.dart
git commit -m "style: apply shaded layer background to HomePage sidebar"
```

---

### Task 4: Verification

- [ ] **Step 1: Run the app and toggle system appearance**
- [ ] **Step 2: Verify light theme colors match design spec**
- [ ] **Step 3: Run static analysis**

Run: `dart analyze`
Expected: No issues.
