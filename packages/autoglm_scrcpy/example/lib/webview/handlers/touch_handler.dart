import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:autoglm_scrcpy_example/webview/handlers/js_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class TouchHandler extends JavaScriptHandler {
  final void Function(ScrcpyInjectTouchMessage) onTouch;
  TouchHandler({required this.onTouch});

  @override
  String get handlerName => "touchHandler";

  @override
  JavaScriptHandlerCallback get callback => _handleTouchArgs;

  void _handleTouchArgs(List<dynamic> args) {
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
    onTouch(msg);
  }
}
