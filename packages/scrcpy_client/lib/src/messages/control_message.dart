import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_client/src/messages/scrcpy_control_message.dart';

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
    // scrcpy protocol: scroll values are signed 15-bit fixed-point (i16fp) where
    // INT16_MAX (32767) = 1.0. The scrcpy client convention accepts natural values
    // in [-16, 16], divides by 16 to normalize to [-1, 1], then multiplies by 32767.
    // Values outside [-16, 16] are clamped to the maximum scroll magnitude.
    final hNorm = (hScroll / 16.0).clamp(-1.0, 1.0);
    final vNorm = (vScroll / 16.0).clamp(-1.0, 1.0);
    buffer.setInt16(13, (hNorm * 32767).toInt());
    buffer.setInt16(15, (vNorm * 32767).toInt());
    buffer.setUint32(17, buttons);
    return buffer.buffer.asUint8List();
  }
}

/// Type 9: Set Clipboard
///
/// Writes [text] to the device clipboard. When [paste] is true the scrcpy
/// server immediately triggers a paste event after setting the clipboard,
/// making this the only reliable way to inject CJK / non-ASCII text.
class ScrcpySetClipboardMessage extends ScrcpyControlMessage {
  const ScrcpySetClipboardMessage({
    required this.text,
    this.sequence = 0,
    this.paste = true,
  });

  final String text;
  final int sequence;
  final bool paste;

  @override
  int get type => 9;

  @override
  Uint8List toBinary() {
    final utf8Text = utf8.encode(text);
    // type(1) + sequence(8) + paste(1) + text_len(4) + text
    final out = ByteData(14 + utf8Text.length);
    out.setUint8(0, type);
    out.setUint64(1, sequence);
    out.setUint8(9, paste ? 1 : 0);
    out.setUint32(10, utf8Text.length);
    out.buffer.asUint8List().setAll(14, utf8Text);
    return out.buffer.asUint8List();
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
