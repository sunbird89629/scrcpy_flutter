import 'package:autoglm_scrcpy_example/webview/handlers/touch_handler.dart';
import 'package:autoglm_scrcpy_example/webview/webview_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  InAppWebViewController? _webViewController;
  String? _loadedUrl;
  late final TouchHandler _touchHandler = TouchHandler(
    onTouch: (msg) => WebViewScope.of(context).sendTouch(msg),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final url = WebViewScope.of(context).playerUrl;
    if (url != null && url != _loadedUrl) {
      _loadedUrl = url;
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = WebViewScope.of(context);
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
        onWebViewCreated: (ctrl) {
          _webViewController = ctrl;
          ctrl.addJavaScriptHandler(
            handlerName: 'logHandler',
            callback: (args) {
              controller.addLog('[WebView] ${args[0]}');
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: _touchHandler.handlerName,
            callback: _touchHandler.callback,
          );

          final url = controller.playerUrl;
          if (url != null) {
            ctrl.loadUrl(
              urlRequest: URLRequest(url: WebUri(url)),
            );
          }
        },
        onConsoleMessage: (ctrl, msg) {
          controller.addLog('[Console] ${msg.message}');
        },
        onLoadStop: (ctrl, url) {
          controller.addLog('WebView Loaded: $url');
        },
        onReceivedError: (ctrl, request, error) {
          controller.addLog('WebView Error: ${error.description}');
        },
      ),
    );
  }
}
