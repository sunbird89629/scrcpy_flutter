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

// ---------------------------------------------------------------------------
// Internal base classes for messages that share a binary layout.
// ---------------------------------------------------------------------------

/// A control message whose payload is only the single-byte type field.
abstract class _ScrcpyEmptyMessage extends ScrcpyControlMessage {
  const _ScrcpyEmptyMessage();

  @override
  Uint8List toBinary() => Uint8List(1)..[0] = type;
}

/// A control message whose payload is a single byte after the type field.
abstract class _ScrcpyOneBytePayloadMessage extends ScrcpyControlMessage {
  const _ScrcpyOneBytePayloadMessage();

  int get payloadByte;

  @override
  Uint8List toBinary() {
    final out = Uint8List(2);
    out[0] = type;
    out[1] = payloadByte;
    return out;
  }
}

// ---------------------------------------------------------------------------
// Control message types (ordered by type number).
// ---------------------------------------------------------------------------

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

/// Type 5: Expand Notification Panel
///
/// Equivalent to swiping down to reveal notifications.
class ScrcpyExpandNotificationPanelMessage extends _ScrcpyEmptyMessage {
  const ScrcpyExpandNotificationPanelMessage();

  @override
  int get type => 5;
}

/// Type 6: Expand Settings Panel
///
/// Opens the quick-settings panel (equivalent to a two-finger swipe down).
class ScrcpyExpandSettingsPanelMessage extends _ScrcpyEmptyMessage {
  const ScrcpyExpandSettingsPanelMessage();

  @override
  int get type => 6;
}

/// Type 7: Collapse Panels
///
/// Collapses any expanded notification or settings panel.
class ScrcpyCollapsePanelsMessage extends _ScrcpyEmptyMessage {
  const ScrcpyCollapsePanelsMessage();

  @override
  int get type => 7;
}

/// Copy-key actions for [ScrcpyGetClipboardMessage].
class ScrcpyClipboardCopyKey {
  static const int none = 0;
  static const int copy = 1;
  static const int cut = 2;
}

/// Type 8: Get Clipboard
///
/// Requests the device clipboard contents. Use [copyKey] to optionally
/// trigger a copy or cut before reading.
class ScrcpyGetClipboardMessage extends _ScrcpyOneBytePayloadMessage {
  const ScrcpyGetClipboardMessage({this.copyKey = ScrcpyClipboardCopyKey.none});

  final int copyKey;

  @override
  int get type => 8;

  @override
  int get payloadByte => copyKey;
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

/// Type 10: Set Display Power
///
/// Turns the device display on or off without stopping mirroring.
class ScrcpySetDisplayPowerMessage extends _ScrcpyOneBytePayloadMessage {
  const ScrcpySetDisplayPowerMessage({required this.on});

  final bool on;

  @override
  int get type => 10;

  @override
  int get payloadByte => on ? 1 : 0;
}

/// Type 11: Rotate Device
///
/// Rotates the device display by 90 degrees.
class ScrcpyRotateDeviceMessage extends _ScrcpyEmptyMessage {
  const ScrcpyRotateDeviceMessage();

  @override
  int get type => 11;
}

/// Type 12: UHID Create
///
/// Creates a virtual HID device on the Android device. [name] is the device
/// name, [reportDescriptor] is the raw HID report descriptor bytes.
class ScrcpyUhidCreateMessage extends ScrcpyControlMessage {
  ScrcpyUhidCreateMessage({
    required this.id,
    this.vendorId = 0,
    this.productId = 0,
    this.name = '',
    Uint8List? reportDescriptor,
  }) : assert(name.length <= 255),
       reportDescriptor = reportDescriptor ?? Uint8List(0);

  final int id;
  final int vendorId;
  final int productId;
  final String name;
  final Uint8List reportDescriptor;

  @override
  int get type => 12;

  @override
  Uint8List toBinary() {
    final utf8Name = utf8.encode(name);
    // layout: type(1) id(2) vendor(2) product(2) name_len(1) name(var)
    //          desc_len(2) desc(var)
    final out = ByteData(8 + utf8Name.length + 2 + reportDescriptor.length);
    out.setUint8(0, type);
    out.setUint16(1, id);
    out.setUint16(3, vendorId);
    out.setUint16(5, productId);
    out.setUint8(7, utf8Name.length);
    final buf = out.buffer.asUint8List();
    buf.setAll(8, utf8Name);
    final descOff = 8 + utf8Name.length;
    out.setUint16(descOff, reportDescriptor.length);
    buf.setAll(descOff + 2, reportDescriptor);
    return buf;
  }
}

/// Type 13: UHID Input
///
/// Sends an input report to a virtual HID device.
class ScrcpyUhidInputMessage extends ScrcpyControlMessage {
  const ScrcpyUhidInputMessage({required this.id, required this.data});

  final int id;
  final Uint8List data;

  @override
  int get type => 13;

  @override
  Uint8List toBinary() {
    final out = ByteData(5 + data.length);
    out.setUint8(0, type);
    out.setUint16(1, id);
    out.setUint16(3, data.length);
    out.buffer.asUint8List().setAll(5, data);
    return out.buffer.asUint8List();
  }
}

/// Type 14: UHID Destroy
///
/// Destroys a previously created virtual HID device.
class ScrcpyUhidDestroyMessage extends ScrcpyControlMessage {
  const ScrcpyUhidDestroyMessage({required this.id});

  final int id;

  @override
  int get type => 14;

  @override
  Uint8List toBinary() {
    final out = ByteData(3);
    out.setUint8(0, type);
    out.setUint16(1, id);
    return out.buffer.asUint8List();
  }
}

/// Type 15: Open Hard Keyboard Settings
///
/// Opens the Android physical keyboard settings dialog.
class ScrcpyOpenHardKeyboardSettingsMessage extends _ScrcpyEmptyMessage {
  const ScrcpyOpenHardKeyboardSettingsMessage();

  @override
  int get type => 15;
}

/// Type 16: Start App
///
/// Launches the named app on the device. [name] is the Android package name
/// (e.g. `com.android.settings`).
class ScrcpyStartAppMessage extends ScrcpyControlMessage {
  const ScrcpyStartAppMessage(this.name) : assert(name.length <= 255);

  final String name;

  @override
  int get type => 16;

  @override
  Uint8List toBinary() {
    final utf8Name = utf8.encode(name);
    final out = Uint8List(2 + utf8Name.length);
    out[0] = type;
    out[1] = utf8Name.length;
    out.setAll(2, utf8Name);
    return out;
  }
}

/// Type 17: Reset Video
///
/// Requests a video encoder reset (IDR frame) on the server.
class ScrcpyResetVideoMessage extends _ScrcpyEmptyMessage {
  const ScrcpyResetVideoMessage();

  @override
  int get type => 17;
}

/// Type 18: Camera Set Torch
///
/// Toggles the camera flashlight on or off.
class ScrcpyCameraSetTorchMessage extends _ScrcpyOneBytePayloadMessage {
  const ScrcpyCameraSetTorchMessage({required this.on});

  final bool on;

  @override
  int get type => 18;

  @override
  int get payloadByte => on ? 1 : 0;
}

/// Type 19: Camera Zoom In
///
/// Zooms the camera in.
class ScrcpyCameraZoomInMessage extends _ScrcpyEmptyMessage {
  const ScrcpyCameraZoomInMessage();

  @override
  int get type => 19;
}

/// Type 20: Camera Zoom Out
///
/// Zooms the camera out.
class ScrcpyCameraZoomOutMessage extends _ScrcpyEmptyMessage {
  const ScrcpyCameraZoomOutMessage();

  @override
  int get type => 20;
}

/// Type 21: Resize Display
///
/// Changes the mirroring resolution to [width]×[height].
class ScrcpyResizeDisplayMessage extends ScrcpyControlMessage {
  const ScrcpyResizeDisplayMessage({required this.width, required this.height});

  final int width;
  final int height;

  @override
  int get type => 21;

  @override
  Uint8List toBinary() {
    final out = ByteData(5);
    out.setUint8(0, type);
    out.setUint16(1, width);
    out.setUint16(3, height);
    return out.buffer.asUint8List();
  }
}
