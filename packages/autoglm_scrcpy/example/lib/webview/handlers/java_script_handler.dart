import 'package:flutter_inappwebview/flutter_inappwebview.dart';

abstract class JavaScriptHandler {
  String get handlerName;
  JavaScriptHandlerCallback get callback;
}
