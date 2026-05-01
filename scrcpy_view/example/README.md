# scrcpy_view Example

Minimal example demonstrating the `ScrcpyView` widget with a WebView-based video backend.

## Run

```bash
cd scrcpy_view/example
flutter run -d macos
```

Connect an Android device via ADB, select it from the dropdown, and the screen will mirror automatically.

## Usage

```dart
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/safe_adb_client.dart';

ScrcpyView(
  controller: ScrcpyViewController(adb: SafeAdbClient()),
)
```

`scrcpy_view` defines two abstract interfaces — `ScrcpyAdb` and `ScrcpyLogger` — so you can provide your own implementations. This example keeps a small local `SafeAdbClient` adapter that bridges `autoglm_adb` to `ScrcpyAdb`.
