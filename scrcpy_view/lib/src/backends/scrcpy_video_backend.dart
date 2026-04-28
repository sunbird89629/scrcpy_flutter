import 'package:flutter/material.dart';
import 'package:scrcpy_view/src/control_message.dart';

/// Controller for sending touch events to the device.
class ScrcpyTouchController {
  final void Function(ScrcpyInjectTouchMessage) _sendTouch;

  /// Creates a touch controller that sends touch events through [onSend].
  ScrcpyTouchController(void Function(ScrcpyInjectTouchMessage) onSend)
      : _sendTouch = onSend;

  /// Send a touch event to the device.
  void send(ScrcpyInjectTouchMessage msg) => _sendTouch(msg);
}

/// Renders the Android device screen and relays touch events.
abstract class ScrcpyVideoBackend {
  /// Build a widget that displays the video stream from [playerUrl].
  Widget build({
    required String playerUrl,
    required ScrcpyTouchController touchController,
    required void Function(ScrcpyControlMessage) onControlMessage,
  });
}
