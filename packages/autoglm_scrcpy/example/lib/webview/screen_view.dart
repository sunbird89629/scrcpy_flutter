import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:autoglm_scrcpy_example/webview/touch_handler.dart';
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

  late final TouchHandler _touchHandler = TouchHandler(
    onTouch: widget.onTouch,
  );

  @override
  void didUpdateWidget(covariant ScreenView oldWidget) {
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
            handlerName: _touchHandler.handlerName,
            callback: _touchHandler.callback,
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
