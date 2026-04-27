import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/src/control_message.dart';
import 'package:autoglm_scrcpy_example/webview/touch_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initAppLogger);
  test('parses JS handler args into ScrcpyInjectTouchMessage', () {
    ScrcpyInjectTouchMessage? received;
    final handler = TouchHandler(onTouch: (msg) => received = msg);
    // 模拟 JS 传来的参数: [action, pointerId, x, y, width, height, pressure]
    handler.callback([0, 42, 100, 200, 1080, 1920, 1.0]);
    expect(received, isNotNull);
    expect(received!.action, ScrcpyAction.down);
    expect(received!.pointerId, 42);
    expect(received!.x, 100);
    expect(received!.y, 200);
    expect(received!.width, 1080);
    expect(received!.height, 1920);
    expect(received!.pressure, 1.0);
  });

  test('ignores args with fewer than 7 elements', () {
    ScrcpyInjectTouchMessage? received;
    final handler = TouchHandler(onTouch: (msg) => received = msg);

    handler.callback([0, 42, 100, 200, 1080, 1920]);

    expect(received, isNull);
  });

  
}
