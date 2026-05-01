# AutoGLM Flutter

Flutter Desktop rewrite of [AutoGLM-GUI](https://github.com/suyiiyii/AutoGLM-GUI). Single-machine macOS desktop app (Windows/Linux planned for later sub-projects).

## Status

The monorepo skeleton, shared packages, ADB wrapper, scrcpy stream layer, settings persistence, basic history storage, app shell, and placeholder UI pages are in place. The next work is to harden device/scrcpy reliability, replace placeholders with real workflows, connect the agent loop, and polish the desktop product experience.

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
cd autoglm_app && flutter run -d macos
```

## Current Project Map

```
autoglm_app/           # Main AutoGLM Flutter desktop app
  lib/
    main.dart          # App bootstrap: logging, settings repository, MCP toolkit, MediaKit
    app.dart           # MaterialApp, themes, NavigationRail shell
    router.dart        # go_router routes: devices/chat/workflows/history/settings
    pages/             # Top-level app pages
    providers/         # Riverpod wiring for settings, ADB, devices, scrcpy, history, locale
    i18n/              # slang translation JSON files
  pubspec.yaml

scrcpy_app/            # Standalone scrcpy demo/test Flutter app
  lib/
    main.dart
    scrcpy_app.dart
    app_controller.dart
    device_list_widget.dart
    home_page.dart
  macos/               # macOS runner files
  pubspec.yaml

scrcpy_view/           # Reusable scrcpy protocol + Flutter viewing package
  lib/
    scrcpy_view.dart   # Public exports
    src/
      scrcpy_server.dart
      scrcpy_stream_parser.dart
      scrcpy_proxy_server.dart
      scrcpy_websocket_server.dart
      control_message.dart
      mpeg_ts_muxer.dart
      backends/
  assets/
    scrcpy-server-v3.3.4
    web_player/
  example/             # Package example app
  test/
  pubspec.yaml

scrcpy_mcp/            # MCP-facing wrapper around scrcpy operations
  lib/
    scrcpy_mcp.dart
    src/scrcpy_mcp_server.dart
  test/
  pubspec.yaml

packages/
  autoglm_core/        # Shared settings, history, trace models/managers, logger exports
    lib/
      autoglm_core.dart
      src/
        history/
        models/
        settings/
        trace/
    test/

  autoglm_adb/         # ADB binary lifecycle and command wrapper
    lib/
      autoglm_adb.dart
      src/
        adb_binary_manager.dart
        adb_client.dart
        adb_process_runner.dart
        exceptions.dart
    test/

  autoglm_logger/      # App logger facade and class logger helpers
    lib/

  autoglm_ui_kit/      # Shared Material themes and design tokens
    lib/
      autoglm_ui_kit.dart
      src/theme/
    test/

docs/
  plans/               # Implementation plans by date/sub-project
  specs/               # Design/spec documents

melos.yaml             # Melos package list and workspace scripts
pubspec.yaml           # Dart workspace root and Melos dev dependency
analysis_options.yaml  # Root analyzer configuration
```

## Roadmap

| Phase | Area | Status | Goal |
|---|---|---|---|
| 0 | Monorepo foundation | done | Keep `autoglm_app`, `scrcpy_view`, `scrcpy_mcp`, and shared packages bootstrapped through Melos with analyze/format/test scripts. |
| 1 | Core services | mostly done | Maintain settings, logging, ADB process execution, trace records, and history storage as stable lower-level packages. |
| 2 | Device management | in progress | Make Android device discovery, selection, wireless pairing, connect/disconnect, and error recovery production-ready. |
| 3 | Scrcpy mirroring | in progress | Stabilize server deployment, socket lifecycle, H.264 parsing, MPEG-TS proxying, video playback, and input control. |
| 4 | Desktop app shell | in progress | Replace placeholder sidebars/pages with real device state, stream status, session state, and actionable controls. |
| 5 | Agent execution loop | planned | Connect chat input to an LLM/tool loop that can observe the device screen, issue ADB/scrcpy control actions, and record steps. |
| 6 | Workflows | planned | Add reusable automation workflows, workflow runs, run history, cancellation, retry, and parameter editing. |
| 7 | MCP integration | planned | Expose device, screen, control, history, and workflow operations as MCP tools with clear lifecycle ownership. |
| 8 | Product hardening | planned | Add tests, diagnostics, onboarding, localization polish, packaging, update strategy, and cross-platform preparation. |

### Phase Details

**Phase 2: Device Management**
- Show connected USB and wireless devices with model/name/status, not only raw device IDs.
- Finish pairing/connect flows with validation, loading states, success/failure messages, and refresh behavior.
- Handle common ADB states: unauthorized, offline, multiple devices, missing ADB, failed platform-tools download.
- Add focused tests around `AdbClient`, `AdbBinaryManager`, provider refresh, and device selection.

**Phase 3: Scrcpy Mirroring**
- Make `ScrcpyServer.start()` and `stop()` idempotent and resilient to partial startup failure.
- Surface metadata, proxy readiness, server logs, and stream errors in the UI.
- Add reconnect/restart controls when the device disconnects or the scrcpy process exits.
- Verify control messages for touch, text, back/home/app switch, and coordinate mapping.
- Keep parser/proxy tests around packet fragmentation, config packets, keyframes, and client connection timing.

**Phase 4: Desktop App Shell**
- Replace the current device sidebar placeholder with selected-device details, stream status, and quick controls.
- Turn `ChatPage` into the main operation workspace: screen preview, task input, execution log, and current agent state.
- Expand `HistoryPage` with search, filters, details, and step replay/debug views.
- Expand `SettingsPage` for provider/model/base URL/API key, MCP settings, logs path, and diagnostics.

**Phase 5: Agent Execution Loop**
- Define the agent runtime boundary: task request, screen observation, tool call, result, trace span, history step.
- Implement first tool set: screenshot/observe, tap, swipe, text input, key event, wait, shell command.
- Persist each run as conversation + steps + trace timing so failures can be inspected.
- Add cancellation/timeouts and make agent state explicit in the UI.

**Phase 6: Workflows**
- Define workflow model: name, description, parameters, steps, target app/device constraints.
- Build create/edit/run UI on `WorkflowsPage`.
- Store workflow definitions and workflow run records.
- Support run cancellation, retry from failed step, and export/import later if needed.

**Phase 7: MCP Integration**
- Promote `scrcpy_mcp` from wrapper to a lifecycle-aware server surface.
- Expose safe MCP tools for listing devices, starting/stopping mirroring, observing screen state, sending controls, and reading history.
- Add guardrails so MCP calls cannot fight the UI for ownership of the same active device session.

**Phase 8: Product Hardening**
- Add widget/integration coverage for the main desktop flows.
- Improve logs and diagnostics screens so users can report actionable failures.
- Package the macOS app and document signing/notarization expectations.
- Prepare Windows/Linux support only after the macOS ADB/scrcpy path is stable.

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
melos run test --ignore="autoglm_app"
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

- One PR can span `packages/*`, `autoglm_app`, `scrcpy_app`, `scrcpy_view`, and `scrcpy_mcp` when a feature crosses package boundaries.
- Lower layers (`autoglm_core`, `autoglm_adb`, `scrcpy_view`) must not import from upper application layers such as `autoglm_app`; verify with `melos list --graph`.
- Open the IDE at the repo root so cross-package navigation works.

## Settings file

`~/Library/Application Support/AutoGLM/settings.json` — JSON, hand-editable. Fields:
- `themeMode`: "ThemeMode.system" | "ThemeMode.light" | "ThemeMode.dark"
- `locale`: "system" | "zh-CN" | "en-US"
- `llmBaseUrl`, `llmModel`, `llmApiKey`
- `mcpServerEnabled`, `mcpServerPort`
