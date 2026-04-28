import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// A [ScrcpyVideoBackend] that uses [InAppWebView] to render the scrcpy stream.
class WebViewVideoBackend implements ScrcpyVideoBackend {
  const WebViewVideoBackend();

  @override
  Widget build({
    required String playerUrl,
    required ScrcpyTouchController touchController,
    required void Function(ScrcpyControlMessage) onControlMessage,
  }) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(playerUrl)),
      initialSettings: InAppWebViewSettings(
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        isInspectable: true,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'touchHandler',
          callback: (args) {
            final action = args[0] as int;
            final pointerId = args[1] as int;
            final cssX = args[2] as int;
            final cssY = args[3] as int;
            final cssW = args[4] as int;
            final cssH = args[5] as int;
            final internalW = args[6] as int;
            final internalH = args[7] as int;
            final pressure = (args[8] as num).toDouble();

            // Convert CSS coordinates to device coordinates
            if (internalW == 0 || internalH == 0) return;

            final x = (cssX * internalW) ~/ cssW;
            final y = (cssY * internalH) ~/ cssH;

            final msg = ScrcpyInjectTouchMessage(
              action: _mapAction(action),
              pointerId: pointerId,
              x: x,
              y: y,
              width: internalW,
              height: internalH,
              pressure: pressure,
              buttons: 1, // Default primary button
            );
            onControlMessage(msg);
          },
        );
      },
    );
  }

  int _mapAction(int jsAction) {
    switch (jsAction) {
      case 0: return ScrcpyAction.down;
      case 1: return ScrcpyAction.up;
      case 2: return ScrcpyAction.move;
      case 3: return ScrcpyAction.cancel;
      default: return ScrcpyAction.move;
    }
  }
}
