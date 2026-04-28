import 'package:autoglm_scrcpy_example/webview/webview_controller.dart';
import 'package:flutter/material.dart';

class WebViewScope extends InheritedNotifier<WebViewController> {
  const WebViewScope({
    super.key,
    required WebViewController controller,
    required super.child,
  }) : super(notifier: controller);

  static WebViewController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<WebViewScope>();
    assert(scope != null, 'WebViewScope.of() called without an ancestor');
    return scope!.notifier!;
  }
}
