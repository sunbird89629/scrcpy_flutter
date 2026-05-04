import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_app/scrcpy_app.dart';

void main() {
  initLogging();
  runApp(const ScrcpyApp());
}
