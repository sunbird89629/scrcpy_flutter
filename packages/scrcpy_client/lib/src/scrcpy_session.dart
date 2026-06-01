import 'dart:async';

import 'package:scrcpy_client/src/messages/control_message.dart';
import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/messages/scrcpy_control_message.dart';

/// Abstraction over a scrcpy mirroring session.
///
/// Pure-Dart contract: no Flutter or HTTP-proxy concerns.
/// Flutter consumers use a separate ScrcpyViewController which adds
/// proxy/WebSocket server management on top.
abstract class ScrcpySession {
  /// Whether a mirroring session is currently active.
  bool get isConnected;

  /// The width of the scrcpy video stream, or `null` if no metadata yet.
  int? get videoWidth;

  /// The height of the scrcpy video stream, or `null` if no metadata yet.
  int? get videoHeight;

  /// Starts a mirroring session for [deviceId].
  Future<void> start(String deviceId);

  /// Stops the active mirroring session.
  Future<void> stop();

  /// Sends a raw control message to the device.
  void sendControlMessage(ScrcpyControlMessage message);

  /// Injects text into the focused field on the device.
  void injectText(String text);

  /// Stream of parsed device→host messages received on the control socket.
  Stream<ScrcpyDeviceMessage> get deviceMessages;

  /// Reads the device clipboard.
  ///
  /// Sends a [ScrcpyGetClipboardMessage] then waits for the device to reply
  /// with a [ScrcpyClipboardDeviceMessage]. Throws [TimeoutException] if no
  /// reply arrives within [timeout].
  Future<String> getClipboard({Duration timeout = const Duration(seconds: 5)});
}
