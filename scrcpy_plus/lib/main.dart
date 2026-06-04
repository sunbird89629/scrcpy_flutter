// scrcpy_plus/lib/main.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_plus/app/app_controller.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  // Tray-only app: the macOS Flutter engine only runs this entrypoint once the
  // nib shows the window, so we can't suppress it natively. Instead hide the
  // window as soon as it's ready, leaving only the tray icon.
  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
    await windowManager.hide();
  });

  final configDir = p.join(
    Platform.environment['HOME']!,
    'Library',
    'Application Support',
    'scrcpy_plus',
  );

  final settingsManager = SettingsManager(configDir: configDir);
  final controller = AppController(settingsManager: settingsManager);

  await controller.init();

  // Keep the app running — no window, no widget tree needed.
  // The app lives entirely in the system tray.
}
