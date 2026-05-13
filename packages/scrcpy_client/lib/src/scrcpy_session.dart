import 'package:scrcpy_client/src/control_message.dart';

/// Abstraction over a scrcpy mirroring session.
///
/// Pure-Dart contract: no Flutter or HTTP-proxy concerns.
/// Flutter consumers use a separate ScrcpyViewController which adds
/// proxy/WebSocket server management on top.
abstract class ScrcpySession {
  /// Whether a mirroring session is currently active.
  bool get isConnected;

  /// The width of the scrcpy video stream, or `null` if no metadata yet.
  ///
  /// scrcpy may scale device frames (e.g. via `max_size`) so this can
  /// differ from the device's logical resolution. Touch/scroll control
  /// messages are silently dropped by the scrcpy server when the
  /// `width`/`height` they report do not equal the video size, so callers
  /// using device-resolution coordinates must rescale to this size.
  int? get videoWidth;

  /// The height of the scrcpy video stream, or `null` if no metadata yet.
  /// See [videoWidth].
  int? get videoHeight;

  /// Starts a mirroring session for [deviceId].
  Future<void> start(String deviceId);

  /// Stops the active mirroring session.
  Future<void> stop();

  /// Sends a raw control message to the device.
  void sendControlMessage(ScrcpyControlMessage message);

  /// Injects text into the focused field on the device.
  void injectText(String text);
}
