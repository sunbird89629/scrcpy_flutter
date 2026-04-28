# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Always use Context7 when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.

## Project Overview

Flutter Desktop monorepo for Android device screen mirroring via Scrcpy protocol and AI agent chat. Melos-managed Dart pub workspace.

## Build, Test, Lint

```bash
melos bootstrap             # install deps + link local packages
melos run gen               # freezed / json_serializable codegen
melos run gen:i18n          # slang i18n codegen
melos run analyze           # dart analyze --fatal-infos --fatal-warnings
melos run format            # check formatting (no diff expected)
melos run format:fix        # auto-format
melos run test              # run all tests
```

Run the desktop apps:
```bash
cd autoglm_app && flutter run -d macos    # AI agent app
cd scrcpy_app && flutter run -d macos     # scrcpy client app
```

Add deps inside the target package (not at root), then `melos bootstrap` from root.

## Architecture

```
packages/autoglm_logger ──> packages/autoglm_core
packages/autoglm_adb ──> scrcpy_view (publishable widget library)
                                      │
packages/autoglm_ui_kit ──────────────┼──> autoglm_app (AI agent)
                                      │
                                      └──> scrcpy_app (scrcpy client)
                                      └──> scrcpy_mcp (MCP server)
```

Lower layers must never import from upper layers.

### Key packages

**scrcpy_view** — Publishable Flutter widget library for Android screen mirroring:
- `ScrcpyView` — embeddable widget managing `ScrcpyServer` lifecycle
- `ScrcpyServer` — orchestrates the full lifecycle: pushes JAR to device, sets up ADB forwarding (auto-retry on port conflict), launches on-device scrcpy server, bridges video/control sockets
- `ScrcpyStreamParser` — binary protocol parser: 64-byte device name + 12-byte codec metadata header, then 8-byte PTS + 4-byte length frames. PTS bit 63 = CONFIG (SPS/PPS), bit 62 = KEYFRAME
- `ScrcpyProxyServer` — HTTP server remuxing H.264 Annex-B into MPEG-TS for media_kit compatibility. Late-joiners get buffered SPS/PPS + PAT/PMT before first keyframe
- `ScrcpyWebsocketServer` — WebSocket + static HTTP server. Serves web player + proxies H.264 with SPS/PPS injection per keyframe + 8-byte host timestamp prefix per frame
- `MpegTsMuxer` — custom MPEG-TS muxer (188-byte packets, 90kHz PTS)
- `control_message.dart` — Scrcpy v3 control protocol: inject keycode (type 0), text (1), touch (2), scroll (3), back/screen-on (4)
- `ScrcpyAdb` / `ScrcpyLogger` — abstract interfaces; consumers provide implementations via adapters

**autoglm_app** — AI agent desktop app (chat, workflows, history, settings, device management)

**scrcpy_app** — Standalone scrcpy desktop client (device selector + mirroring)

**scrcpy_mcp** — MCP server wrapping scrcpy operations

**autoglm_core** — `Settings`/`SettingsRepository`, `HistoryDatabase` (SQLite via sqflite_common_ffi), `TraceManager` (daily-rolling JSONL). Re-exports `autoglm_logger`.

**autoglm_adb** — `AdbClient` (shell, forward, reverse, push, pair, connect), `AdbProcessRunner`.

**autoglm_ui_kit** — Material 3 light/dark themes seeded from `Colors.indigo`. Design tokens in `DESIGN.md`.

## Conventions

- Use `appLogger` from `package:autoglm_core` for all logging (never `print`)
- Use `ScrcpyAdb` interface from `scrcpy_view` for testing without a real device
- Integration tests requiring a physical Android device go in relevant `*_real_device_test.dart`
- Assets (scrcpy JAR, web player) are extracted to temp directories at runtime
- Low-latency encoding: `video_codec_options=i-frame-interval=1,latency=1,profile=1`
- One PR can span `packages/*`, `scrcpy_*`, and `autoglm_app`
