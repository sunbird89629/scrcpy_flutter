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

## Common commands

```bash
melos run analyze           # static analysis
melos run format            # check formatting
melos run format:fix        # apply formatting
melos run test              # run all tests
melos run gen               # build_runner (freezed / json)
melos run gen:i18n          # slang
```

## Settings file

`~/Library/Application Support/AutoGLM/settings.json` — JSON, hand-editable. Fields:
- `themeMode`: "ThemeMode.system" | "ThemeMode.light" | "ThemeMode.dark"
- `locale`: "system" | "zh-CN" | "en-US"
- `llmBaseUrl`, `llmModel`, `llmApiKey`
- `mcpServerEnabled`, `mcpServerPort`
