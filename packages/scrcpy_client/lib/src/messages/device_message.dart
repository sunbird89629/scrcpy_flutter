import 'dart:typed_data';

/// Base class for all scrcpy device-to-host messages.
sealed class ScrcpyDeviceMessage {
  const ScrcpyDeviceMessage();
}

/// Type 0: Device clipboard content, sent in response to a
/// ScrcpyGetClipboardMessage control message.
final class ScrcpyClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyClipboardDeviceMessage({
    required this.sequence,
    required this.text,
  });

  final int sequence;
  final String text;
}

/// Type 1: Acknowledgement that a ScrcpySetClipboardMessage was applied.
final class ScrcpyAckClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyAckClipboardDeviceMessage({required this.sequence});

  final int sequence;
}

/// Type 2: HID output data from a UHID device registered on the host.
final class ScrcpyUhidOutputDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyUhidOutputDeviceMessage({required this.id, required this.data});

  final int id;
  final Uint8List data;
}
