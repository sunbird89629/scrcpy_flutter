import 'package:logger_utils/logger_utils.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_app/scrcpy_app.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  initLogging();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    center: true,
    title: 'ScrcpyApp',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  runApp(const ScrcpyApp());
}
