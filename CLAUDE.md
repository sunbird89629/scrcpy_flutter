# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Always use Context7 when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.

## Project Overview

Flutter Desktop rewrite of [AutoGLM-GUI](https://github.com/suyiiyii/AutoGLM-GUI) — a macOS app for Android device management, real-time screen mirroring via Scrcpy protocol, and AI agent chat. Melos-managed Dart pub workspace monorepo.

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

Scope to specific packages: `melos run test --scope="autoglm_*"`

Run the desktop app: `cd apps/desktop && flutter run -d macos`

Run the scrcpy example: `cd packages/autoglm_scrcpy/example && flutter run -d macos`

Add deps inside the target package (not at root), then `melos bootstrap` from root.

## Architecture

```
autoglm_logger ──> autoglm_core ──> autoglm_adb ──> autoglm_scrcpy
                                                          │
                       autoglm_ui_kit ────────────────────┼──> apps/desktop
```

Lower layers must never import from upper layers.

### Key packages

**autoglm_scrcpy** (most complex) — Scrcpy protocol v3.3.4 implementation:
- `ScrcpyServer` — orchestrates the full lifecycle: pushes JAR to device, sets up ADB forwarding (auto-retry on port conflict), launches on-device scrcpy server, bridges video/control sockets
- `ScrcpyStreamParser` — binary protocol parser: 64-byte device name + 12-byte codec metadata header, then 8-byte PTS + 4-byte length frames. PTS bit 63 = CONFIG (SPS/PPS), bit 62 = KEYFRAME
- `ScrcpyProxyServer` — HTTP server remuxing H.264 Annex-B into MPEG-TS for media_kit compatibility. Late-joiners get buffered SPS/PPS + PAT/PMT before first keyframe
- `ScrcpyWebsocketServer` — WebSocket + static HTTP server. Serves web player + proxies H.264 with SPS/PPS injection per keyframe + 8-byte host timestamp prefix per frame
- `MpegTsMuxer` — custom MPEG-TS muxer (188-byte packets, 90kHz PTS)
- `control_message.dart` — Scrcpy v3 control protocol: inject keycode (type 0), text (1), touch (2), scroll (3), back/screen-on (4)

**autoglm_core** — `Settings`/`SettingsRepository`, `HistoryDatabase` (SQLite via sqflite_common_ffi), `TraceManager` (daily-rolling JSONL). Re-exports `autoglm_logger`.

**autoglm_adb** — `AdbClient` (shell, forward, reverse, push, pair, connect), `AdbProcessRunner`.

**autoglm_ui_kit** — Material 3 light/dark themes seeded from `Colors.indigo`. Design tokens in `DESIGN.md`.

## Conventions

- Use `appLogger` from `package:autoglm_core` for all logging (never `print`)
- Use `MockAdbClient` from scrcpy tests for unit tests that don't need a real device
- Integration tests requiring a physical Android device go in `scrcpy_real_device_test.dart`
- Assets (scrcpy JAR, web player) are extracted to temp directories at runtime
- Low-latency encoding: `video_codec_options=i-frame-interval=1,latency=1,profile=1`
- One PR can span `packages/*` and `apps/desktop`
