import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';

/// Parses scrcpy device-to-host binary messages from the control socket.
///
/// Feed raw bytes via [feed]; parsed messages are emitted on [messages].
/// Wire format (all integers big-endian):
///   Type 0 CLIPBOARD:    type(1) | sequence(8) | length(4) | text(length)
///   Type 1 ACK_CLIPBOARD: type(1) | sequence(8)
///   Type 2 UHID_OUTPUT:  type(1) | id(2) | size(2) | data(size)
class ScrcpyDeviceMessageParser {
  ScrcpyDeviceMessageParser({this.logger = const NoOpScrcpyLogger()});

  final ScrcpyLogger logger;

  Uint8List _buffer = Uint8List(0);
  final _controller = StreamController<ScrcpyDeviceMessage>.broadcast();

  /// Stream of parsed device messages.
  Stream<ScrcpyDeviceMessage> get messages => _controller.stream;

  /// Feed raw bytes from the control socket into the parser.
  void feed(Uint8List data) {
    if (_buffer.isEmpty) {
      _buffer = data;
    } else {
      final merged = Uint8List(_buffer.length + data.length);
      merged.setRange(0, _buffer.length, _buffer);
      merged.setRange(_buffer.length, merged.length, data);
      _buffer = merged;
    }
    _process();
  }

  void _process() {
    var offset = 0;
    outer:
    while (offset < _buffer.length) {
      final type = _buffer[offset];
      switch (type) {
        case 0: // CLIPBOARD
          if (_buffer.length - offset < 13) break outer;
          final hdr = ByteData.sublistView(_buffer, offset + 1, offset + 13);
          final sequence = hdr.getUint64(0);
          final length = hdr.getUint32(8);
          if (_buffer.length - offset < 13 + length) break outer;
          final text = utf8.decode(
            _buffer.sublist(offset + 13, offset + 13 + length),
          );
          _controller.add(
            ScrcpyClipboardDeviceMessage(sequence: sequence, text: text),
          );
          offset += 13 + length;

        case 1: // ACK_CLIPBOARD
          if (_buffer.length - offset < 9) break outer;
          final sequence = ByteData.sublistView(
            _buffer,
            offset + 1,
            offset + 9,
          ).getUint64(0);
          _controller.add(ScrcpyAckClipboardDeviceMessage(sequence: sequence));
          offset += 9;

        case 2: // UHID_OUTPUT
          if (_buffer.length - offset < 5) break outer;
          final hdr = ByteData.sublistView(_buffer, offset + 1, offset + 5);
          final id = hdr.getUint16(0);
          final size = hdr.getUint16(2);
          if (_buffer.length - offset < 5 + size) break outer;
          final data = Uint8List.fromList(
            _buffer.sublist(offset + 5, offset + 5 + size),
          );
          _controller.add(ScrcpyUhidOutputDeviceMessage(id: id, data: data));
          offset += 5 + size;

        default:
          logger.warn(
            '[ScrcpyDeviceMessageParser] Unknown type: $type — stream desynced',
          );
          offset = _buffer.length; // consume all, stream is unrecoverable
          break outer;
      }
    }

    if (offset > 0) {
      _buffer = offset >= _buffer.length
          ? Uint8List(0)
          : Uint8List.sublistView(_buffer, offset);
    }
  }

  /// Closes the message stream.
  void close() => _controller.close();
}
