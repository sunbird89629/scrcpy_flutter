# scrcpy_app

Flutter macOS desktop client for Android screen mirroring via the [scrcpy](https://github.com/Genymobile/scrcpy) protocol. Includes an embedded MCP server so AI agents can control the device over HTTP.

## Features

- **Device list** — auto-discovers connected Android devices via ADB
- **Screen mirroring** — low-latency H.264 video streamed from the device
- **MCP server** — start a local StreamableHTTP MCP server with one click; AI agents connect to `http://localhost:7070/mcp`

## MCP Server

The MCP panel is always visible at the bottom of the window.

**Idle state:**
```
MCP Server    Port: [7070]    [Start]
```

**Running state:**
```
● MCP Running   http://localhost:7070/mcp   [Copy]   [Stop]
```

### Connecting an AI agent

Add the server URL to your agent's MCP configuration. Example for Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "scrcpy": {
      "type": "streamable_http",
      "url": "http://localhost:7070/mcp"
    }
  }
}
```

### Available MCP tools

| Tool | Description |
|---|---|
| `list_devices` | List connected Android device serials |
| `start_mirroring` | Start screen mirroring for a device |
| `stop_mirroring` | Stop the active mirroring session |
| `inject_key` | Send a key event (Home=3, Back=4, AppSwitch=187) |
| `inject_touch` | Send a touch event at (x, y) coordinates |
| `inject_text` | Type text on the device |
| `inject_scroll` | Send a scroll event |
| `take_screenshot` | Capture the screen as a PNG image |

The AI agent and the Flutter UI share the same mirroring session — starting mirroring from the agent is immediately visible in the app window, and vice versa.

## Running

```bash
cd scrcpy_app && flutter run -d macos
```

Requires ADB on `$PATH` and at least one Android device connected with USB debugging enabled.
