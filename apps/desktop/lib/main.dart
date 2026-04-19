import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const _BootApp());
}

class _BootApp extends StatelessWidget {
  const _BootApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoGLM',
      theme: lightTheme,
      darkTheme: darkTheme,
      home: const Scaffold(
        body: Center(child: Text('AutoGLM — Task 7 boot')),
      ),
    );
  }
}
