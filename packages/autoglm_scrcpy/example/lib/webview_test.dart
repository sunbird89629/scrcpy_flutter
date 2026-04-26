import 'dart:async';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  State<ScrcpyWebViewTestScreen> createState() =>
      _ScrcpyWebViewTestScreenState();
}

class _ScrcpyWebViewTestScreenState extends State<ScrcpyWebViewTestScreen> {
  final List<String> _logs = [];
  ScrcpyServer? _server;
  bool _isRunning = false;

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
    if (!mounted) return;
    setState(() {
      _logs.add(
        '${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}: $message',
      );
      if (_logs.length > 500) _logs.removeAt(0);
    });
  }

  void _handlePointerEvent(PointerEvent event, Size widgetSize) {
    if (_server == null) return;

    int action;
    if (event is PointerDownEvent) {
      action = ScrcpyAction.down;
    } else if (event is PointerMoveEvent) {
      // PointerMove fires per frame during a drag; drop no-op moves so we
      // don't allocate + send a redundant scrcpy packet for each one.
      if (event.delta == Offset.zero) return;
      action = ScrcpyAction.move;
    } else if (event is PointerUpEvent) {
      action = ScrcpyAction.up;
    } else {
      return;
    }

    _server!.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: event.pointer,
        x: event.localPosition.dx.toInt(),
        y: event.localPosition.dy.toInt(),
        width: widgetSize.width.toInt(),
        height: widgetSize.height.toInt(),
        pressure: event.pressure,
      ),
    );
  }

  void _injectKey(int keycode) {
    if (_server == null) return;
    _addLog('Injecting keycode: $keycode');
    _server!.sendControlMessage(
      ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down,
        keycode: keycode,
      ),
    );
    _server!.sendControlMessage(
      ScrcpyInjectKeyMessage(
        action: ScrcpyAction.up,
        keycode: keycode,
      ),
    );
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

    final server = ScrcpyServer(
      adbClient: adbClient,
      deviceId: deviceId,
    );

    _addLog('Starting scrcpy server...');
    await server.start();

    if (!mounted) {
      await server.stop();
      return;
    }

    setState(() => _server = server);
    _addLog('Web Player URL: ${server.playerUrl}');
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
          Expanded(
            child: _ScreenView(
              playerUrl: _server?.playerUrl,
              onLog: _addLog,
              onPointerEvent: _handlePointerEvent,
            ),
          ),
          SizedBox(
            width: 300,
            child: _ControlView(
              isRunning: _isRunning,
              logs: _logs,
              onStart: _startTest,
              onStop: _stopTest,
              onInjectKey: _injectKey,
            ),
          )
        ],
      ),
    );
  }
}

class _ScreenView extends StatefulWidget {
  const _ScreenView({
    required this.playerUrl,
    required this.onLog,
    required this.onPointerEvent,
  });

  final String? playerUrl;
  final ValueChanged<String> onLog;
  final void Function(PointerEvent event, Size widgetSize) onPointerEvent;

  @override
  State<_ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<_ScreenView> {
  InAppWebViewController? _controller;

  @override
  void didUpdateWidget(covariant _ScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final url = widget.playerUrl;
    if (url != null && url != oldWidget.playerUrl) {
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              InAppWebView(
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
                  _controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'logHandler',
                    callback: (args) {
                      widget.onLog('[WebView] ${args[0]}');
                    },
                  );

                  final url = widget.playerUrl;
                  if (url != null) {
                    controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(url)),
                    );
                  }
                },
                onConsoleMessage: (controller, consoleMessage) {
                  widget.onLog('[Console] ${consoleMessage.message}');
                },
                onLoadStop: (controller, url) {
                  widget.onLog('WebView Loaded: $url');
                },
                onReceivedError: (controller, request, error) {
                  widget.onLog('WebView Error: ${error.description}');
                },
              ),
              // Overlay to capture gestures
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => widget.onPointerEvent(e, widgetSize),
                  onPointerMove: (e) => widget.onPointerEvent(e, widgetSize),
                  onPointerUp: (e) => widget.onPointerEvent(e, widgetSize),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlView extends StatelessWidget {
  const _ControlView({
    required this.isRunning,
    required this.logs,
    required this.onStart,
    required this.onStop,
    required this.onInjectKey,
  });

  final bool isRunning;
  final List<String> logs;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<int> onInjectKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.indigo[800],
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: isRunning ? null : onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    key: const Key('stop_button'),
                    onPressed: isRunning ? onStop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              if (isRunning) ...[
                const Divider(color: Colors.white24, height: 24),
                const Text(
                  'Remote Control',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlBtn(
                        Icons.arrow_back, () => onInjectKey(ScrcpyKeycode.back)),
                    _controlBtn(Icons.circle_outlined,
                        () => onInjectKey(ScrcpyKeycode.home)),
                    _controlBtn(
                        Icons.menu, () => onInjectKey(ScrcpyKeycode.appSwitch)),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => Text(
                logs[index],
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
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white10,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}
