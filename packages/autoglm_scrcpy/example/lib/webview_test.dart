import 'dart:async';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_driver/driver_extension.dart';

void main() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the logger
  final tempDir = await getTemporaryDirectory();
  initAppLogger(logsDir: p.join(tempDir.path, 'autoglm_logs'));

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ScrcpyWebViewTestScreen(),
    ),
  );
}

class ScrcpyWebViewTestScreen extends StatefulWidget {
  const ScrcpyWebViewTestScreen({super.key});

  @override
  State<ScrcpyWebViewTestScreen> createState() => _ScrcpyWebViewTestScreenState();
}

class _ScrcpyWebViewTestScreenState extends State<ScrcpyWebViewTestScreen> {
  final List<String> _logs = [];
  ScrcpyServer? _server;
  bool _isRunning = false;
  
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    // Auto-start after a short delay for debugging
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isRunning) {
        _startTest();
      }
    });
  }

  void _addLog(String message) {
    debugPrint(message);
    setState(() {
      _logs.add(
        '${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}: $message',
      );
    });
    // Auto-scroll logs
  }

  Future<void> _startTest() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    const adbClient = AdbClient();

    _addLog('Searching for devices...');
    final devices = await adbClient.devices();
    if (devices.isEmpty) {
      _addLog('Error: No devices found!');
      setState(() => _isRunning = false);
      return;
    }

    final deviceId = devices.first;
    _addLog('Using device: $deviceId');

    _server = ScrcpyServer(
      adbClient: adbClient,
      deviceId: deviceId,
    );

    _addLog('Starting scrcpy server...');
    await _server!.start();

    final url = _server!.playerUrl;
    _addLog('Web Player URL: $url');

    // Trigger load in WebView if already initialized
    if (_webViewController != null) {
      await _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
  }

  Future<void> _stopTest() async {
    _addLog('--- Stop Button Clicked ---');
    await _server?.stop();
    _addLog('Server cleanup finished.');
    setState(() {
      _isRunning = false;
      _server = null;
    });
  }

  @override
  void dispose() {
    _server?.stop();
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
          // Left Side: Controls and Logs
          SizedBox(
            width: 300,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.indigo[800],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunning ? null : _startTest,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: const Key('stop_button'),
                        onPressed: _isRunning ? _stopTest : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[900],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.all(8),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) => Text(
                        _logs[index],
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right Side: InAppWebView
          Expanded(
            child: Container(
              color: Colors.black,
              child: InAppWebView(
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  verticalScrollBarEnabled: false,
                  horizontalScrollBarEnabled: false,
                  supportZoom: false,
                  disableVerticalScroll: true,
                  disableHorizontalScroll: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  // Register JS Handler for logs
                  controller.addJavaScriptHandler(
                    handlerName: 'logHandler',
                    callback: (args) {
                      _addLog('[WebView] ${args[0]}');
                    },
                  );
                  
                  // If server already started, load URL
                  if (_server != null) {
                    controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(_server!.playerUrl)),
                    );
                  }
                },
                onConsoleMessage: (controller, consoleMessage) {
                  _addLog('[Console] ${consoleMessage.message}');
                },
                onLoadStop: (controller, url) {
                  _addLog('WebView Loaded: $url');
                },
                onReceivedError: (controller, request, error) {
                  _addLog('WebView Error: ${error.description}');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
