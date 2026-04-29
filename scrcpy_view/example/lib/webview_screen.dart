import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/views/control/control_view.dart';
import 'package:scrcpy_view_example/webview_controller.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final controller = WebViewController();
  Timer? _autoStartTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Scrcpy InAppWebView (AutoGLM)'),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          Expanded(
            child: ScrcpyView(
              adb: controller.adbClient,
              deviceId: controller.deviceId,
            ),
          ),
          ControlView(),
        ],
      ),
    );
  }
}
