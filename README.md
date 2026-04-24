# AutoGLM Flutter

Flutter Desktop rewrite of [AutoGLM-GUI](https://github.com/suyiiyii/AutoGLM-GUI). Single-machine macOS desktop app (Windows/Linux planned for later sub-projects).

## Status

Sub-project **#1: Monorepo + Skeleton** — complete. The app boots with 5 navigable empty pages, persists settings to `~/Library/Application Support/AutoGLM/settings.json`, and writes daily-rotated logs to `~/Library/Application Support/AutoGLM/logs/`. Real ADB / scrcpy / Agent / SQLite / MCP integration arrive in subsequent sub-projects.

## Prerequisites

- macOS (only verified target for now)
- Flutter SDK ≥ 3.24
- Dart SDK ≥ 3.5

## Setup

```bash
# 1. Install melos
dart pub global activate melos

# 2. Bootstrap the workspace
melos bootstrap

# 3. Generate code
melos run gen          # freezed / json_serializable
melos run gen:i18n     # slang strings.g.dart

# 4. Verify
melos run analyze      # expect: 0 issues
melos run format       # expect: no diff
melos run test         # expect: all green

# 5. Run the app
cd apps/desktop && flutter run -d macos
```

## Layout

```
apps/
  desktop/             # Flutter Desktop app (entry point)
packages/
  autoglm_core/        # shared models + settings + logging
  autoglm_ui_kit/      # shared theme
  autoglm_adb/         # ADB layer
  autoglm_scrcpy/      # scrcpy client + video streaming
```

## Sub-projects roadmap

| # | Subsystem | Status |
|---|---|---|
| 1 | Monorepo + Skeleton | done |
| 2 | ADB layer + wireless pairing | pending |
| 3 | scrcpy client + video rendering | pending |
| 4 | SQLite storage (drift) | pending |
| 5 | GLM Agent | pending |
| 6 | UI shell wiring across the above | pending |
| 7 | MCP Server | pending |

## Monorepo (Melos)

This repo uses Dart 3.5+ pub workspaces with [Melos](https://melos.invertase.dev/) for task orchestration — all packages share one resolved dependency tree.

### Daily commands

```bash
melos bootstrap             # bs — install deps + link local packages
                            # rerun after pulling or editing any pubspec.yaml
melos run analyze           # static analysis across all packages
melos run format            # check formatting (no changes)
melos run format:fix        # apply formatting
melos run test              # run all tests
melos run gen               # build_runner (freezed / json_serializable)
melos run gen:i18n          # regenerate slang strings.g.dart
```

### Scoping to specific packages

Scripts run in every package by default. Narrow with `--scope` / `--ignore`:

```bash
melos run analyze --scope="autoglm_core"
melos run test --scope="autoglm_*"          # glob match
melos run test --ignore="apps_desktop"
```

### Adding dependencies

Because of pub workspaces, add dependencies inside the target package, not at the root:

```bash
cd packages/autoglm_core
dart pub add some_package
cd - && melos bootstrap                     # refresh links
```

### Diagnostics

```bash
melos list                  # list all packages
melos list --graph          # dependency graph (JSON) — useful for spotting cycles
melos clean                 # nuke .dart_tool + pubspec.lock; follow with `melos bs`
```

### Conventions

- One PR can span `packages/*` and `apps/desktop` — prefer that over staging changes across PRs.
- Lower layers (`autoglm_core`) must not import from upper layers (`apps/desktop`); verify with `melos list --graph`.
- Open the IDE at the repo root so cross-package navigation works.

## Settings file

`~/Library/Application Support/AutoGLM/settings.json` — JSON, hand-editable. Fields:
- `themeMode`: "ThemeMode.system" | "ThemeMode.light" | "ThemeMode.dark"
- `locale`: "system" | "zh-CN" | "en-US"
- `llmBaseUrl`, `llmModel`, `llmApiKey`
- `mcpServerEnabled`, `mcpServerPort`
