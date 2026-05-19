// scrcpy_plus/lib/main.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_plus/app/app_controller.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

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
