# autoglm_app

AI agent desktop app for Android device management, built with Flutter.

## Features

- **AI Chat** — conversational interface powered by configurable LLM providers
- **Device Management** — connect and manage Android devices via ADB
- **Settings** — theme (light/dark/system), locale (zh-CN/en-US), LLM configuration
- **History** — conversation persistence with SQLite
- **MCP Integration** — Model Context Protocol support for tool-augmented AI workflows

## Getting Started

```bash
# From the repo root
melos bootstrap

# Run the app
cd autoglm_app && flutter run -d macos
```

## Architecture

- **State management**: [Riverpod](https://riverpod.dev/) with code generation
- **Navigation**: [go_router](https://pub.dev/packages/go_router) with ShellRoute for sidebar layout
- **i18n**: [slang](https://pub.dev/packages/slang) (zh-CN base locale, en-US)
- **Themes**: Material 3 light/dark themes defined in `lib/theme/`

## Project structure

```
lib/
  main.dart                  # Entry point, provider overrides
  app_shell.dart             # Sidebar + NavigationRail layout
  router.dart                # go_router configuration
  pages/                     # Route pages (chat, settings, device, etc.)
  providers/                 # Riverpod providers (settings, theme, locale)
```

## Configuration

Settings are stored as JSON at `<appSupportDir>/settings.json`:

| Field | Default | Description |
|-------|---------|-------------|
| `themeMode` | `system` | `system`, `light`, or `dark` |
| `locale` | `system` | `system`, `zh-CN`, or `en-US` |
| `llmProvider` | `gemini` | LLM provider name |
| `llmBaseUrl` | _(empty)_ | Custom LLM API base URL |
| `llmModel` | `gemini-1.5-pro` | Model identifier |
| `llmApiKey` | _(empty)_ | API key for the LLM provider |
| `mcpServerEnabled` | `false` | Enable MCP server |
| `mcpServerPort` | `3000` | MCP server port |

## Related packages

- [autoglm_core](../packages/autoglm_core/) — Shared settings, history, logging
- [autoglm_adb](../packages/autoglm_adb/) — ADB binary wrapper
- [scrcpy_view](../scrcpy_view/) — Android screen mirroring widget
