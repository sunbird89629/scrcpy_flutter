import 'dart:convert';
import 'dart:typed_data';

/// Base class for all scrcpy control messages.
abstract class ScrcpyControlMessage {
  const ScrcpyControlMessage();

  /// The type of the control message.
  int get type;

  /// Serializes the message to binary format (Big-Endian).
  Uint8List toBinary();
}

/// Action for key and touch events.
class ScrcpyAction {
  static const int down = 0;
  static const int up = 1;
  static const int move = 2; // Only for touch
  static const int cancel = 3; // Only for touch
  static const int multi = 2; // Only for key
}

/// Android `KeyEvent` keycodes used with [ScrcpyInjectKeyMessage].
/// Mirrors `android.view.KeyEvent.KEYCODE_*`.
class ScrcpyKeycode {
  /// `KEYCODE_HOME` — return to the launcher.
  static const int home = 3;

  /// `KEYCODE_BACK` — system back navigation.
  static const int back = 4;

  /// `KEYCODE_APP_SWITCH` — open the recent-apps overview.
  static const int appSwitch = 187;
}

/// Type 0: Inject Keycode
class ScrcpyInjectKeyMessage extends ScrcpyControlMessage {
  const ScrcpyInjectKeyMessage({
    required this.action,
    required this.keycode,
    this.repeat = 0,
    this.metastate = 0,
  });

  final int action;
  final int keycode;
  final int repeat;
  final int metastate;

  @override
  int get type => 0;

  @override
  Uint8List toBinary() {
    final buffer = ByteData(14);
    buffer.setUint8(0, type);
    buffer.setUint8(1, action);
    buffer.setUint32(2, keycode);
    buffer.setUint32(6, repeat);
    buffer.setUint32(10, metastate);
    return buffer.buffer.asUint8List();
  }
}

/// Type 1: Inject Text
class ScrcpyInjectTextMessage extends ScrcpyControlMessage {
  const ScrcpyInjectTextMessage(this.text);

  final String text;

  @override
  int get type => 1;

  @override
  Uint8List toBinary() {
    final utf8Text = utf8.encode(text);
    final buffer = ByteData(5 + utf8Text.length);
    buffer.setUint8(0, type);
    buffer.setUint32(1, utf8Text.length);
    final list = buffer.buffer.asUint8List();
    list.setAll(5, utf8Text);
    return list;
  }
}

/// Type 2: Inject Touch Event
class ScrcpyInjectTouchMessage extends ScrcpyControlMessage {
  const ScrcpyInjectTouchMessage({
    required this.action,
    required this.pointerId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pressure = 1.0,
    this.actionButton = 0,
    this.buttons = 0,
  });

  final int action;
  final int pointerId;
  final int x;
  final int y;
  final int width;
  final int height;
  final double pressure;
  final int actionButton;
  final int buttons;

  @override
  int get type => 2;

  @override
  Uint8List toBinary() {
    // Layout per scrcpy v3 ControlMessageReader (payload = 31 bytes):
    //   type(1) action(1) pointerId(8) x(4) y(4) w(2) h(2)
    //   pressure(2) actionButton(4) buttons(4) = 32 bytes total.
    final buffer = ByteData(32);
    buffer.setUint8(0, type);
    buffer.setUint8(1, action);
    buffer.setUint64(2, pointerId);
    buffer.setUint32(10, x);
    buffer.setUint32(14, y);
    buffer.setUint16(18, width);
    buffer.setUint16(20, height);

    final pressureInt = (pressure * 65535).clamp(0, 65535).toInt();
    buffer.setUint16(22, pressureInt);

    buffer.setUint32(24, actionButton);
    buffer.setUint32(28, buttons);
    return buffer.buffer.asUint8List();
  }
}

/// Type 3: Inject Scroll Event
class ScrcpyInjectScrollMessage extends ScrcpyControlMessage {
  const ScrcpyInjectScrollMessage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.hScroll,
    required this.vScroll,
    this.buttons = 0,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final int hScroll;
  final int vScroll;
  final int buttons;

  @override
  int get type => 3;

  @override
  Uint8List toBinary() {
    final buffer = ByteData(21);
    buffer.setUint8(0, type);
    buffer.setUint32(1, x);
    buffer.setUint32(5, y);
    buffer.setUint16(9, width);
    buffer.setUint16(11, height);
    buffer.setInt16(13, hScroll);
    buffer.setInt16(15, vScroll);
    buffer.setUint32(17, buttons);
    return buffer.buffer.asUint8List();
  }
}

/// Type 4: Back or Screen On
class ScrcpyBackOrScreenOnMessage extends ScrcpyControlMessage {
  const ScrcpyBackOrScreenOnMessage(this.action);

  final int action;

  @override
  int get type => 4;

  @override
  Uint8List toBinary() {
    final buffer = ByteData(2);
    buffer.setUint8(0, type);
    buffer.setUint8(1, action);
    return buffer.buffer.asUint8List();
  }
}
