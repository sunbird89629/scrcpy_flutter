import 'dart:async';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy_example/webview/player_panel.dart';
import 'package:autoglm_scrcpy_example/webview/control_panel.dart';
import 'package:autoglm_scrcpy_example/webview/webview_controller.dart';
import 'package:autoglm_scrcpy_example/webview/webview_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void launchWebView() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();

  final tempDir = await getTemporaryDirectory();
  initAppLogger(logsDir: p.join(tempDir.path, 'autoglm_logs'));

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    ),
  );
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller = WebViewController();
  Timer? _autoStartTimer;

  @override
  void initState() {
    super.initState();
    _autoStartTimer = Timer(const Duration(seconds: 2), () {
      if (!_controller.isRunning) {
        _controller.start();
      }
    });
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewScope(
      controller: _controller,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: const Text('Scrcpy InAppWebView (AutoGLM)'),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: const Row(
          children: [
            Expanded(child: PlayerPanel()),
            ControlPanel(),
          ],
        ),
      ),
    );
  }
}
