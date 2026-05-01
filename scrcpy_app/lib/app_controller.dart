import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_app/scrcpy_app_adb.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class AppController extends ChangeNotifier {
  AppController._();
  static final _instance = AppController._();
  factory AppController() => _instance;

  final scrcpyViewController = ScrcpyViewController(
    adb: const ScrcpyAppAdb(AdbClient()),
  );

  bool _running = false;
  bool get running => _running;
  set running(bool value) {
    _running = value;
    notifyListeners();
  }

  connectDevice(final String deviceId) async {
    await scrcpyViewController.start(deviceId, onStarted: () {
      running = true;
    });
  }
}
