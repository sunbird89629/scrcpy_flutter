import 'package:scrcpy_client/scrcpy_client.dart';

/// Callback for sending touch events to the device.
typedef ScrcpyTouchCallback = void Function(ScrcpyInjectTouchMessage);
