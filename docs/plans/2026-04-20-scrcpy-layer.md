# Sub-project #3: Scrcpy Layer & Screen Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Scrcpy client package (`autoglm_scrcpy`) that can deploy the Scrcpy server to an Android device, establish a connection, and parse the raw H264 video stream into discrete packets for UI consumption.

**Architecture:** Create a new package `packages/autoglm_scrcpy`. It will depend on `autoglm_adb`. A `ScrcpyServer` class will handle life-cycle (push, forward, run). A `ScrcpyStreamDecoder` will wrap a `Socket` to parse the custom Scrcpy binary protocol and emit a stream of `ScrcpyPacket` objects.

**Tech Stack:** Dart 3.5, `autoglm_adb`, `path_provider`.

---

## File Structure

```
autoglm-flutter/
├── packages/
│   └── autoglm_scrcpy/
│       ├── pubspec.yaml
│       ├── analysis_options.yaml
│       ├── assets/
│       │   └── scrcpy-server-v3.3.3
│       ├── lib/
│       │   ├── autoglm_scrcpy.dart
│       │   └── src/
│       │       ├── scrcpy_server.dart
│       │       ├── scrcpy_packet.dart
│       │       └── scrcpy_stream_parser.dart
│       └── test/
│           ├── scrcpy_stream_parser_test.dart
│           └── smoke_test.dart
```

---

## Task 1: Scaffold `autoglm_scrcpy` package

**Files:**
- Create: `packages/autoglm_scrcpy/pubspec.yaml`
- Create: `packages/autoglm_scrcpy/analysis_options.yaml`
- Create: `packages/autoglm_scrcpy/lib/autoglm_scrcpy.dart`

- [ ] **Step 1: Create directory layout and copy server binary**
```bash
cd /Users/hao/ai/mobile/autoglm-flutter
mkdir -p packages/autoglm_scrcpy/lib/src
mkdir -p packages/autoglm_scrcpy/test
mkdir -p packages/autoglm_scrcpy/assets
cp /Users/hao/ai/mobile/AutoGLM-GUI/AutoGLM_GUI/resources/scrcpy-server-v3.3.3 packages/autoglm_scrcpy/assets/
```

- [ ] **Step 2: Write `packages/autoglm_scrcpy/pubspec.yaml`**
```yaml
name: autoglm_scrcpy
description: Scrcpy protocol implementation for AutoGLM.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"

resolution: workspace

dependencies:
  autoglm_adb:
    path: ../autoglm_adb
  flutter:
    sdk: flutter
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  very_good_analysis: ^7.0.0

flutter:
  assets:
    - assets/scrcpy-server-v3.3.3
```

- [ ] **Step 3: Update root `pubspec.yaml` to include new package**
```bash
sed -i '' '/- packages\/autoglm_adb/a \
  - packages\/autoglm_scrcpy' /Users/hao/ai/mobile/autoglm-flutter/pubspec.yaml
```

- [ ] **Step 4: Bootstrap**
```bash
cd /Users/hao/ai/mobile/autoglm-flutter
melos bootstrap
```

---

## Task 2: Implement `ScrcpyPacket` and `ScrcpyStreamParser`

**Files:**
- Create: `packages/autoglm_scrcpy/lib/src/scrcpy_packet.dart`
- Create: `packages/autoglm_scrcpy/lib/src/scrcpy_stream_parser.dart`
- Create: `packages/autoglm_scrcpy/test/scrcpy_stream_parser_test.dart`

- [ ] **Step 1: Define `ScrcpyPacket`**
```dart
import 'dart:typed_data';

enum ScrcpyPacketType { configuration, video }

class ScrcpyPacket {
  const ScrcpyPacket({
    required this.type,
    required this.data,
    this.pts,
    this.isKeyFrame = false,
  });

  final ScrcpyPacketType type;
  final Uint8List data;
  final int? pts;
  final bool isKeyFrame;
}
```

- [ ] **Step 2: Implement `ScrcpyStreamParser`**
Implement the parser as a `StreamTransformer` or a class that takes a `Stream<Uint8List>` and yields `ScrcpyPacket`. Handle the 64-byte device name header and 12-byte packet headers.

---

## Task 3: Implement `ScrcpyServer` Life-cycle

**Files:**
- Create: `packages/autoglm_scrcpy/lib/src/scrcpy_server.dart`

- [ ] **Step 1: Implement Server deployment**
Use `AdbClient` to push the server binary from assets to `/data/local/tmp/`.
- [ ] **Step 2: Implement Server execution**
Use `AdbClient.shell` (need to add shell method to `AdbClient` if not exists) to run the `app_process` command.
- [ ] **Step 3: Add `shell` and `forward` methods to `AdbClient`**
Modify `packages/autoglm_adb` to support these essential commands.

---

## Task 4: UI Integration (Video Placeholder)

- [ ] **Step 1: Add `autoglm_scrcpy` to `apps/desktop`**
- [ ] **Step 2: Create a Scrcpy Controller and wire into `ChatPage`**
Show a loading indicator while starting scrcpy, then show "Streaming..." placeholder. (Real rendering with ffmpeg or similar will be Sub-project #5).
