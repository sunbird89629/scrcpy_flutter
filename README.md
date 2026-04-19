# AutoGLM Flutter

Flutter Desktop rewrite of [AutoGLM-GUI](https://github.com/suyiiyii/AutoGLM-GUI). Single-machine macOS desktop app (Windows/Linux planned).

## Setup

```bash
# 1. Install Dart-side tooling
dart pub global activate melos

# 2. Bootstrap workspace
melos bootstrap

# 3. Generate code
melos run gen
melos run gen:i18n

# 4. Verify
melos run analyze
melos run test

# 5. Run the app
cd apps/desktop && flutter run -d macos
```

## Layout

- `apps/desktop` — Flutter Desktop app
- `packages/autoglm_core` — shared models, settings, logging
- `packages/autoglm_ui_kit` — shared theme + widgets

## Sub-projects

This is sub-project #1 of 7 (Monorepo + Skeleton). Subsequent sub-projects:
2. ADB layer
3. scrcpy client + video rendering
4. Storage (drift / SQLite)
5. GLM Agent
6. UI Shell wiring
7. MCP Server
