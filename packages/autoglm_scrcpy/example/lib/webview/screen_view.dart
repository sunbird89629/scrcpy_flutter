import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ScreenView extends StatefulWidget {
  const ScreenView({
    required this.playerUrl,
    required this.onLog,
    required this.onTouch,
  });

  final String? playerUrl;
  final ValueChanged<String> onLog;
  final ValueChanged<ScrcpyInjectTouchMessage> onTouch;

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  InAppWebViewController? _controller;

  @override
  void didUpdateWidget(covariant ScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final url = widget.playerUrl;
    if (url != null && url != oldWidget.playerUrl) {
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  void _handleTouchArgs(List<dynamic> args) {
    // TODO(debug): temporary logging — remove after touch pipeline verified
    widget.onLog('[Touch] handler fired args.length=${args.length} raw=$args');
    if (args.length < 7) return;
    final msg = ScrcpyInjectTouchMessage(
      action: (args[0] as num).toInt(),
      pointerId: (args[1] as num).toInt(),
      x: (args[2] as num).toInt(),
      y: (args[3] as num).toInt(),
      width: (args[4] as num).toInt(),
      height: (args[5] as num).toInt(),
      pressure: (args[6] as num).toDouble(),
    );
    widget.onLog('[Touch] action=${msg.action} ptr=${msg.pointerId} x=${msg.x} y=${msg.y} w=${msg.width} h=${msg.height} p=${msg.pressure.toStringAsFixed(2)}');
    widget.onTouch(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: InAppWebView(
        initialSettings: InAppWebViewSettings(
          isInspectable: kDebugMode,
          transparentBackground: false,
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
          controller.addJavaScriptHandler(
            handlerName: 'touchHandler',
            callback: _handleTouchArgs,
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
    );
  }
}
