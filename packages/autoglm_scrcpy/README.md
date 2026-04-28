# autoglm_scrcpy

A Flutter/Dart implementation of the [Scrcpy](https://github.com/Genymobile/scrcpy) protocol (v3.x), designed for the AutoGLM ecosystem. It enables high-performance, low-latency screen streaming and (planned) control from Android devices to host applications.

## 🚀 Status: MVP (Video Only)

Currently, this package focuses on establishing the core scrcpy tunnel and distributing the video stream via modern web-friendly protocols.

### Features
- ✅ **Scrcpy v3.3.4 Support**: Automatically manages server binary pushing and lifecycle.
- ✅ **Annex-B H.264 Parsing**: Robust binary parsing of the scrcpy stream including PTS and keyframe detection.
- ✅ **SPS/PPS Injection**: Enables late-joining clients to start decoding immediately.
- ✅ **WebSocket Proxy**: Forwards H.264 packets to web-based decoders (e.g., WebCodecs).
- ✅ **MPEG-TS Proxy**: Provides an HTTP stream for compatibility with players like `media_kit`.
- ✅ **Built-in Web Player**: Includes a minimal web player asset for quick testing.

---

## 🗺 Project Roadmap

### Phase 1: Interaction & Control (90% Complete)
- [x] **Control Socket Management**: Stable v3.x handshake (Read Dummy -> Send Bootstrap).
- [x] **Message Serialization**: Implemented `InjectKeyCode`, `InjectTouchEvent`, `InjectTextMessage`, and `InjectScrollEvent`.
- [x] **Coordinate Mapping**: Basic scaling implemented; needs refinement for letterboxing/display cutout.

### Phase 2: Audio Support
- [ ] **Audio Stream Parsing**: Support for scrcpy v2.0+ audio tunnels.
- [ ] **OPUS Decoding**: Integration for real-time audio playback.

### Phase 3: Advanced Protocol Features
- [ ] **Rotation Awareness**: Dynamic metadata updates when the device orientation changes.
- [ ] **Clipboard Synchronization**: Bi-directional copy-paste support.
- [ ] **Codec Selection**: Support for H.265 and AV1 encoding for improved efficiency.

### Phase 4: Flutter Native Rendering
- [ ] **Custom Texture Integration**: Direct rendering of H.264 packets in Flutter via FFI/Texture to bypass WebView overhead.
- [ ] **Performance Optimization**: Reduce end-to-end latency below 50ms.

### Phase 5: Enhanced UX
- [ ] **Drag & Drop**: Automatically push and install files dragged into the viewer.
- [ ] **Multi-Device Dashboard**: Management of multiple concurrent scrcpy sessions.

---

## 📦 Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  autoglm_scrcpy:
    path: path/to/autoglm_scrcpy
```

## 🛠 Usage

```dart
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';

final server = ScrcpyServer(
  adbClient: myAdbClient,
  deviceId: 'your_device_id',
);

// Start the server
await server.start();

// Use the web player URL in a WebView or browser
print('Player: ${server.playerUrl}');

// Or connect to the raw MPEG-TS stream
print('Stream: ${server.proxyUrl}');
```

## 🏗 Architecture

- **`ScrcpyServer`**: Orchestrates ADB setup, binary deployment, and socket tunnels.
- **`ScrcpyStreamParser`**: Decodes the multiplexed binary protocol into discrete packets.
- **`ScrcpyWebsocketServer`**: A Shelf-based proxy that bridges H.264 to Web clients.
- **`ScrcpyProxyServer`**: Remuxes H.264 to MPEG-TS over HTTP.

## 📄 License

This project is part of the AutoGLM ecosystem. See the root LICENSE for details.





# Project Struction
scrcpy_flutter
|-- scrcpy_view 一个 library project, 可以嵌入到其他项目中, 未来会发布到 pub.dev
|-- scrcpy_app 复刻 https://github.com/Genymobile/scrcpy 客户端项目
|-- scrcpy_mcp scrcpy_app 对应的 mcp
|-- autoglm_app 集成了 autoglm 包含 AI agent 的项目