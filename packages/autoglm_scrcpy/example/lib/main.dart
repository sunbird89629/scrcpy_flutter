import 'package:autoglm_scrcpy_example/fpv/fpv_test.dart';
import 'package:autoglm_scrcpy_example/webview/webview_test.dart';

const testType = "webview";
void main(List<String> args) {
  if (testType == "webview") {
    launchWebView();
  } else {
    launchFpv();
  }
}
