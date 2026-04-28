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
import 'package:scrcpy_adapters/scrcpy_adapters.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

ScrcpyView(
  adb: AdbClientAdapter(AdbClient()),
  deviceId: 'your-device-serial',
  videoBackend: const WebViewVideoBackend(),
  onError: (err) => print('Error: $err'),
)
```

`scrcpy_view` defines two abstract interfaces — `ScrcpyAdb` and `ScrcpyLogger` — so you can provide your own implementations. This example uses the shared `scrcpy_adapters` package which bridges `autoglm_adb` and `autoglm_logger`.
