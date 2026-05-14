import 'dart:typed_data';

/// Base class for all scrcpy control messages.
abstract class ScrcpyControlMessage {
  const ScrcpyControlMessage();

  /// The type of the control message.
  int get type;

  /// Serializes the message to binary format (Big-Endian).
  Uint8List toBinary();
}
