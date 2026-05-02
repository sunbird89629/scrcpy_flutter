# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Apache 2.0 license
- CONTRIBUTING.md with development setup guide
- CHANGELOG.md (this file)

### Changed
- Removed dead duplicate `Settings` class (freezed version) from `autoglm_core`
- Enabled `very_good_analysis` lint rules for `scrcpy_app`
- Removed hardcoded FVM SDK path from melos config

### Fixed
- Cleaned up `.gitignore` — removed tracked developer-specific files (`.mcp.json`, `.gemini/`, screenshot artifacts)

## [0.2.0] - 2026-05-02

### Added
- Android navigation buttons (back/home/app-switch) via scrcpy control protocol
- MCP server panel in scrcpy_app with start/stop controls
- `takeScreenshot` via `adb exec-out` in both ADB adapters

## [0.1.0] - 2026-04-26

### Added
- Initial monorepo scaffold with Melos workspace
- **scrcpy_view**: Embeddable Flutter widget for Android screen mirroring via Scrcpy v3 protocol
  - H.264 stream parsing with SPS/PPS injection
  - HTTP proxy server (MPEG-TS muxing for media_kit)
  - WebSocket server with web player
  - Touch/key/text/scroll control message injection
  - WebView-based video player backend
- **scrcpy_app**: Standalone scrcpy desktop client with device selector
- **scrcpy_mcp**: MCP server wrapping scrcpy operations
  - Tools: `list_devices`, `start_mirroring`, `stop_mirroring`, `key`, `touch`, `text`, `scroll`
  - Resources: device list, mirroring status
  - Prompts: `control_device`, `troubleshoot`
  - CLI entry point for stdio MCP server
  - HTTP server for streamable MCP transport
- **autoglm_app**: AI agent desktop app with chat, settings, device management
  - Riverpod state management, go_router navigation
  - slang i18n (zh-CN base, en-US)
  - Material 3 light/dark themes
- **autoglm_core**: Shared settings, history database, trace manager, logger
- **autoglm_adb**: ADB binary wrapper with auto-download
- **autoglm_logger**: Logging facade with daily file rotation
- **autoglm_ui_kit**: Material 3 design tokens and shared themes
