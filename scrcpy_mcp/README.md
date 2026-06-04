# scrcpy_mcp

MCP server for [scrcpy](https://github.com/Genymobile/scrcpy) — Android screen mirroring and device control via the [Model Context Protocol](https://modelcontextprotocol.io/).

Built with [mcp_dart](https://pub.dev/packages/mcp_dart).

Two transports are supported:

- **stdio** — the CLI entry point (`bin/scrcpy_mcp.dart`) for clients that launch the server as a subprocess (Claude Code, Cursor, …).
- **HTTP (Streamable)** — served by the desktop app's MCP Server panel via `McpHttpServer`, for clients that connect to a running app over HTTP.

## Features

### Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `list_devices` | List connected Android devices | — |
| `start_mirroring` | Start screen mirroring | `device_id` (required) |
| `stop_mirroring` | Stop the active session | — |
| `inject_key` | Send a key event | `keycode` (required), `action` (optional) |
| `inject_touch` | Send a touch event | `x`, `y`, `width`, `height` (required), `action` (optional) |
| `inject_text` | Input text | `text` (required) |
| `inject_scroll` | Send a scroll event | `x`, `y`, `width`, `height`, `hScroll`, `vScroll` (required) |

**Key actions:** `0` = down, `1` = up (default: `0`)

**Touch actions:** `0` = down, `1` = up, `2` = move (default: `0`)

**Common keycodes:** `3` = Home, `4` = Back, `187` = App Switch

### Resources

| URI | Description | Format |
|-----|-------------|--------|
| `device://list` | Connected device list | JSON array |
| `mirroring://status` | Current mirroring status | JSON object |

**Mirroring status example:**
```json
{
  "active": true,
  "device_id": "emulator-5554",
  "proxy_url": "http://127.0.0.1:27183",
  "player_url": "http://127.0.0.1:27184"
}
```

### Prompts

| Prompt | Description | Arguments |
|--------|-------------|-----------|
| `control_device` | Device control assistant | `device_id` (optional) |
| `troubleshoot` | Device troubleshooting assistant | `issue` (optional) |

## Usage

### stdio transport (CLI)

```bash
# Run with default adb path
dart run scrcpy_mcp/bin/scrcpy_mcp.dart

# Run with custom adb path
dart run scrcpy_mcp/bin/scrcpy_mcp.dart /path/to/adb
```

Configure your MCP client to launch this command. For example, in Claude Code's `settings.json`:

```json
{
  "mcpServers": {
    "scrcpy": {
      "command": "dart",
      "args": ["run", "scrcpy_mcp/bin/scrcpy_mcp.dart"]
    }
  }
}
```

> Set the `OPENAI_*` agent environment variables before launching to additionally
> enable the `run_task` agent tool (see `AgentConfig.fromEnv` / `OpenAiLlmClient`).

### HTTP (Streamable) transport

The desktop app (`scrcpy_app`) hosts the server over HTTP via its **MCP Server**
panel (`McpServerController` → `McpHttpServer`). Start the app, open the panel,
and click start. The server is then reachable at:

```
http://localhost:7070/mcp
```

The port defaults to `7070` and can be changed in the panel while the server is
stopped. Point a Streamable-HTTP MCP client at the URL — for example:

```json
{
  "mcpServers": {
    "scrcpy": {
      "type": "http",
      "url": "http://localhost:7070/mcp"
    }
  }
}
```

This transport reuses the app's live scrcpy session, so the device state is
shared with what you see mirrored in the app.

### As a library

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:stream_channel/stream_channel.dart';

// Create server with a StreamChannel for MCP transport
final server = ScrcpyMcpServer(
  channel,
  adb: ScrcpyMcpAdb(adbClient),
);

// Wait for server to finish
await server.done;
```

#### Using adapters

The package includes adapters for bridging `autoglm_adb` to `scrcpy_view`:

```dart
import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

final adbClient = AdbClient(adbPath: 'adb');
final scrcpyAdb = ScrcpyMcpAdb(adbClient);

final server = ScrcpyMcpServer(
  channel,
  adb: scrcpyAdb,
);
```

## Architecture

```
scrcpy_mcp
├── lib/
│   ├── scrcpy_mcp.dart              # Library exports
│   └── src/
│       ├── scrcpy_mcp_server.dart    # MCPServer implementation
│       └── scrcpy_mcp_adapters.dart  # ADB/Logger adapters
├── bin/
│   └── scrcpy_mcp.dart              # CLI entry point
└── test/
    └── scrcpy_mcp_server_test.dart   # Unit tests
```

## Development

```bash
# Install dependencies
melos bootstrap

# Run tests
cd scrcpy_mcp && flutter test

# Run analyzer
cd scrcpy_mcp && dart analyze

# Run CLI
dart run scrcpy_mcp/bin/scrcpy_mcp.dart
```

## Dependencies

- [dart_mcp](https://pub.dev/packages/dart_mcp) — MCP protocol implementation
- [scrcpy_view](../scrcpy_view) — Scrcpy widget/protocol package
- [autoglm_adb](../packages/autoglm_adb) — ADB client

## License

Apache-2.0
