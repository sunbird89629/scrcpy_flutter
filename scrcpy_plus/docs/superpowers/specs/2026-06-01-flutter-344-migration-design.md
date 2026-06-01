# Flutter 3.44 Migration Design

**Date:** 2026-06-01
**Status:** Approved
**Scope:** scrcpy_plus + workspace packages

## Goal

Migrate the scrcpy_flutter_workspace from Flutter 3.41.8 (Dart 3.11.5) to Flutter 3.44 stable, enabling new platform features.

## Current State

- **Flutter:** 3.41.8 / Dart 3.11.5
- **SDK constraint (workspace):** `^3.5.0`
- **macOS deployment target:** 10.15
- **Key deps:** tray_manager, window_manager, freezed, json_serializable, media_kit

## Migration Steps

### Step 1: Upgrade Flutter SDK

```bash
flutter upgrade
flutter --version  # verify 3.44.x
```

### Step 2: Update SDK Constraints

Update `environment.sdk` in all pubspec.yaml files:

| File | Current | Target |
|------|---------|--------|
| `pubspec.yaml` (root) | `^3.5.0` | `^3.10.0` |
| `scrcpy_plus/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `scrcpy_app/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `scrcpy_mcp/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `scrcpy_view/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `packages/adb_tools/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `packages/logger_utils/pubspec.yaml` | `^3.5.0` | `^3.10.0` |
| `packages/scrcpy_client/pubspec.yaml` | `^3.5.0` | `^3.10.0` |

> Flutter constraint `>=3.24.0` can stay as-is (3.44 satisfies it).

### Step 3: Bootstrap & Analyze

```bash
melos bootstrap
melos run analyze   # find all errors
melos run test      # verify tests pass
```

### Step 4: Fix Breaking Changes

Known breaking changes in Flutter 3.44 / Dart 3.10+:

| Change | Impact | Action |
|--------|--------|--------|
| `onReorder` deprecated | Low — grep for usage, migrate to new API | Replace or suppress |
| `TextDecoration` made `final` | Low — no custom subclasses expected | No action likely needed |
| `IconData` made `final` + `@mustBeConst` | Low — uses Material Icons constants | No action likely needed |
| `ExtendSelectionByPageIntent` removed | None — not used | No action |

Strategy:
1. Run `melos run analyze` to get full error list
2. Fix errors (not warnings) first
3. Then address warnings
4. For deprecated APIs: migrate if straightforward, otherwise suppress with `// ignore: deprecated_member_use`

### Step 5: macOS Platform Updates

**5a. Deployment Target**
- Current: 10.15
- Flutter 3.44 may require raising to 10.15+ (verify after upgrade)
- If needed: update `MACOSX_DEPLOYMENT_TARGET` in Xcode project

**5b. Display P3 (Wide Gamut)**
- Engine-level support, no code changes needed
- Automatically activates on P3-capable displays
- Video stream colors will render more accurately

**5c. SwiftPM**
- Existing CocoaPods-style plugins remain compatible
- No migration needed; new plugins will use SwiftPM automatically

### Step 6: Enable New Features (On-Demand)

New APIs available after migration (use when needed, no rush):

- **Multi-window:** `SatelliteWindowController`, popup/tooltip windows
- **UI components:** `RoundedSuperellipseInputBorder`, `CupertinoMenuAnchor`, `SizedBox.square()`
- **Utilities:** `ThemeMode.isDark`/`isLight`/`isSystem`, `FormState.fields`, `Form.clearError()`

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Third-party dep incompatibility | Low | `flutter pub outdated` to check; wait for patches if needed |
| macOS build breakage | Medium | Verify entitlements, deployment target after upgrade |
| Undocumented breaking changes | Low | `melos run analyze` catches most issues |

## Verification

1. `flutter --version` shows 3.44.x
2. `melos bootstrap` succeeds
3. `melos run analyze` passes with no errors
4. `melos run test` passes
5. `cd scrcpy_plus && flutter run -d macos` launches successfully
6. `cd scrcpy_app && flutter run -d macos` launches successfully
