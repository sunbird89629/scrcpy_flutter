import 'package:autoglm_logger/autoglm_logger.dart';
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
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ScrcpyApp());
}
